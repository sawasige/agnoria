import Foundation
import Observation
import SwiftData
import CoreData
import UserNotifications
#if os(iOS)
import WidgetKit
#endif

enum Route: Hashable {
    case quiz
    /// スコア帯クリアの演出（結果の前に挟む）[v1.5]
    case stageClear
    case result
    case stats
}


/// アプリ全体の状態（MV）。ナビゲーション・セットの開始と記録を担当
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let settings: AppSettings
    let analytics: UsageAnalytics
    /// 記録ストアが iCloud 同期の構成か（§2.3 [v1.7]）
    let cloudSync: Bool
    /// 同梱の問題データ（§2.1 [v1.9]）。起動時に JSON から読む
    let catalog: QuestionCatalog
    /// 問題データを読めなかったときの説明（ホームに出す）。読めていれば nil
    let catalogError: String?
    var path: [Route] = []
    var run: QuizRun?
    var lastSavedSession: StudySession?
    /// 直近のセット完走で次の帯が開いた軸（結果画面の表示用。next が開いた帯）。次のセット開始で消す
    var lastUnlocked: [Stage.Clear] = []
    /// 直近のセット完走で増えた習得（結果画面の表示用 §4.3 [v2.4]）。次のセット開始で消す
    var lastSetGain: (newlyMastered: Int, nearlyMastered: Int) = (0, 0)
    /// 直近のセット完走でクリアしたスコア帯（専用画面の演出用 §4.3.1 [v1.5]）。軸ごとに 1 件 [v1.8]。次のセット開始とホームで消す
    var pendingStageClears: [Stage.Clear] = []
    /// 結果画面で評価ダイアログを頼むきっかけ（§4.8 [v1.8]）。結果画面が頼んだら消す
    var pendingReviewRequest: ReviewPrompt.Trigger?

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, settings: AppSettings, analytics: UsageAnalytics? = nil, cloudSync: Bool = false,
         catalog: QuestionCatalog = .empty, catalogError: String? = nil) {
        self.container = container
        self.settings = settings
        self.analytics = analytics ?? UsageAnalytics(settings: settings)
        self.cloudSync = cloudSync
        self.catalog = catalog
        self.catalogError = catalogError
        if cloudSync { observeRemoteChanges() }
        ReminderScheduler.shared.onOpen = { [weak self] in self?.analytics.log(.reminderOpened) }
    }

    // MARK: - iCloud 同期（§2.3）

    enum CloudSyncStatus { case off, notSignedIn, syncing }

    /// 設定画面の状態表示用。トグルは持たない
    var cloudSyncStatus: CloudSyncStatus {
        guard cloudSync else { return .off }
        return FileManager.default.ubiquityIdentityToken == nil ? .notSignedIn : .syncing
    }

    private var remoteChangeTask: Task<Void, Never>?

    /// 他の端末からの変更が届いたら、重複をまとめ、到達帯を求め直し、ウィジェットの写しを書き直す。
    /// 通知は短時間に連続するので 1 秒まとめてから処理する
    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remoteChangeTask?.cancel()
                self.remoteChangeTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self.reconcileAfterSync()
                }
            }
        }
    }

    /// 同期後の整合: 重複の合成 → 軸ごとの到達帯の再計算（高い方に揃える）→ ウィジェットの写し
    func reconcileAfterSync() {
        mergeDuplicateRecords()
        raiseUnlockedLevelsFromRecords()
        refreshWidgetSnapshot()
        refreshReminders()
    }

    /// 記録から軸ごとに到達帯を求め、今より高ければ上げる（下げない。手動で戻した帯は同期では戻さない）
    private func raiseUnlockedLevelsFromRecords() {
        for (mode, state) in stageStates() {
            let computed = Stage.unlockedFromRecords(byLevel: state.byLevel)
            if computed > settings.unlockedLevel(mode) { settings.setUnlockedLevel(computed, for: mode) }
        }
    }

    /// 同じ itemID の ItemProgress、同じ id の StudySession を 1 件にまとめる（§2.3 の衝突規則）
    func mergeDuplicateRecords() {
        let progress = (try? context.fetch(FetchDescriptor<ItemProgress>())) ?? []
        var changed = false
        for (_, group) in Dictionary(grouping: progress, by: \.itemID) where group.count > 1 {
            let keep = group[0]
            for extra in group.dropFirst() {
                keep.absorb(extra.snapshot)
                context.delete(extra)
            }
            changed = true
        }
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        for (_, group) in Dictionary(grouping: sessions, by: \.id) where group.count > 1 {
            for extra in group.dropFirst() { context.delete(extra) }
            changed = true
        }
        if changed { save("merge") }
    }

    // MARK: - 起動時の整備

    /// 起動時に 1 回。記録の補正と移行、ウィジェットの写し、通知の予約
    func prepareAtLaunch() {
        removeLegacyQuestionStore()
        backfillMasteredAt()
        mergeDuplicateRecords()
        // 1.8 で到達帯を軸ごとに分けた。初回は記録から軸ごとに求め直す（§3.4 [v1.8]）
        if !settings.stageTracksMigrated {
            raiseUnlockedLevelsFromRecords()
            settings.stageTracksMigrated = true
        }
        refreshWidgetSnapshot()
        refreshReminders()
    }

    /// 1.7〜1.8 の問題ストア（questions.store）と取り込みのキーを消す [v1.9]（§2.1、Issue #21）。無ければ何もしない
    func removeLegacyQuestionStore() {
        for url in AgnoriaSchema.legacyQuestionStoreURLs where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        settings.removeLegacyImportKeys()
    }

    // MARK: - ウィジェット

    /// ウィジェット用の写しを書き直す（§4.6 [v1.6]）。起動時・セット完走・履歴リセット・到達帯の変更で呼ぶ。
    /// iOS 以外は App Group を持たないので何もしない
    func refreshWidgetSnapshot() {
        #if os(iOS)
        let dates = ((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).map(\.finishedAt)
        WidgetSnapshot.make(stages: stageStates(), sessionDates: dates).save()
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - リマインダー

    /// 通知の予約を今の設定と記録で置き換える（§4.9 [v1.8]）。起動時・セット完走・履歴リセット・同期後・設定の変更で呼ぶ
    func refreshReminders() {
        let enabled = settings.reminderEnabled
        let minutes = settings.reminderMinutes
        let dates = ((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).map(\.finishedAt)
        Task { await ReminderScheduler.shared.reschedule(enabled: enabled, minutes: minutes, sessionDates: dates) }
    }

    /// 通知の許可を求め、結果で設定を更新して予約し直す。設定のトグルと、最初の完走後の 1 回で使う
    @discardableResult
    func requestReminderPermission() async -> Bool {
        let granted = await ReminderScheduler.shared.requestAuthorization()
        analytics.log(.reminderPermission(granted: granted))
        settings.reminderEnabled = granted
        refreshReminders()
        return granted
    }

    /// 最初のセット完走後に一度だけ、通知の許可を尋ねる（結果画面から呼ぶ）。尋ねたら true
    func askReminderIfNeeded() async -> Bool {
        guard Self.reminderPromptEnabled, !settings.reminderPrompted, lastSavedSession != nil else { return false }
        settings.reminderPrompted = true
        // 設定で先にオン・オフを決めていれば尋ねない
        guard await ReminderScheduler.shared.authorizationStatus() == .notDetermined else { return false }
        await requestReminderPermission()
        return true
    }

    // MARK: - 初回のスコアの目安（§4.1 [v2.0]、Issue #50）

    /// 初回起動で「今のスコアの目安」を尋ねるか。記録が 1 件でもあれば尋ねない（1.3 からの更新で出さない）
    var shouldAskStartingLevel: Bool {
        guard Self.startingLevelPromptEnabled, !settings.startingLevelAsked else { return false }
        if hasAnyRecords {
            settings.startingLevelAsked = true
            return false
        }
        return true
    }

    private var hasAnyRecords: Bool {
        ((try? context.fetchCount(FetchDescriptor<ItemProgress>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<StudySession>())) ?? 0) > 0
    }

    /// 選択肢と、それぞれの開始の帯。「〜600」は 600 点帯を最後に残して 550 から
    enum StartingLevelChoice: CaseIterable, Identifiable {
        case never, upTo450, upTo550, upTo600
        var id: Self { self }
        var title: String {
            switch self {
            case .never: "受けたことがない"
            case .upTo450: "450 点くらいまで"
            case .upTo550: "550 点くらいまで"
            case .upTo600: "600 点くらいまで"
            }
        }
        var detail: String {
            switch self {
            case .never, .upTo450: "450 点帯の基本から"
            case .upTo550: "500 点帯から（450 点帯は復習で混ざります）"
            case .upTo600: "550 点帯から（下の帯は復習で混ざります）"
            }
        }
        var level: Int {
            switch self {
            case .never, .upTo450: 450
            case .upTo550: 500
            case .upTo600: 550
            }
        }
    }

    /// 選んだ目安で、単語・文法・応答問題の到達帯をまとめて合わせる。nil（あとで）は 450 のまま
    func applyStartingLevel(_ choice: StartingLevelChoice?) {
        settings.startingLevelAsked = true
        if let choice {
            settings.startingLevel = choice.level
            for mode in DrillMode.allCases where settings.unlockedLevel(mode) < choice.level {
                settings.setUnlockedLevel(choice.level, for: mode)
            }
        }
        analytics.log(.startingLevel(choice?.level ?? 0))
        analytics.syncUserProperties()
        refreshWidgetSnapshot()
    }

    /// 起動引数 `-startingLevelPrompt NO` で尋ねない（UI テストはこれで起動）
    static var startingLevelPromptEnabled: Bool {
        UserDefaults.standard.object(forKey: "startingLevelPrompt") == nil || UserDefaults.standard.bool(forKey: "startingLevelPrompt")
    }

    /// 起動引数 `-reminderPrompt NO` で通知の許可を尋ねない（UI テストはこれで起動）
    static var reminderPromptEnabled: Bool {

        UserDefaults.standard.object(forKey: "reminderPrompt") == nil || UserDefaults.standard.bool(forKey: "reminderPrompt")
    }

    /// 保存。失敗はクラッシュさせず非致命エラーとして記録する（§7.1）
    private func save(_ what: String) {
        do { try context.save() } catch { analytics.record(error, "save.\(what)") }
    }

    /// [v1.4] masteredAt 追加前に習得していた問題へ、最後の回答日時を習得日として補う（起動時に 1 回。該当がなければ何もしない）
    func backfillMasteredAt() {
        let rows = (try? context.fetch(FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.masteredAt == nil }))) ?? []
        var changed = false
        for p in rows where Priority.isGraduated(p.recentResults) {
            p.masteredAt = p.lastAnsweredAt ?? .now
            changed = true
        }
        if changed { save("backfill") }
    }

    // MARK: - セット

    /// 条件からセットを作って開始。対象が0件なら nil
    @discardableResult
    func startQuiz(_ config: QuizConfig) -> QuizRun? {
        var rng = SystemRandomNumberGenerator()
        let questions = buildQuestions(config, using: &rng)
        guard !questions.isEmpty else { return nil }
        lastUnlocked = []
        lastSetGain = (0, 0)
        pendingStageClears = []
        pendingReviewRequest = nil
        let run = QuizRun(config: config, questions: questions)
        self.run = run
        path = [.quiz]
        analytics.log(.setStart(config))
        return run
    }

    /// 候補をまとめて優先度抽出し、選ばれたものだけ問題化する。
    /// config.mode が指定されていれば eligible でその軸に絞られる。nil（おまかせ・復習）なら単語・文法が混ざり、
    /// ホームの切り替えがオンならリスニングも混ざる（§3.2 [v1.9]）
    func buildQuestions(_ config: QuizConfig, using rng: inout some RandomNumberGenerator) -> [QuizQuestion] {
        let progress = progressMap()
        let modes = config.mode.map { [$0] } ?? settings.autoModes
        let grammar = modes.contains(.grammar) ? catalog.grammar : []
        let words = modes.contains(.word) ? catalog.words : []
        let listening = modes.contains(.listening) ? catalog.listening : []
        let grammarSnaps = catalog.grammarByID
        let listeningSnaps = catalog.listeningByID
        let pool = catalog.words
        let wordSnaps = catalog.wordByID

        var candidates: [SetBuilder.Candidate] = []
        candidates += grammar.map {
            SetBuilder.Candidate(id: $0.id, mode: .grammar, category: $0.category, level: $0.level,
                                 progress: progress[$0.id])
        }
        candidates += words.map {
            SetBuilder.Candidate(id: $0.id, mode: .word, category: $0.category, level: $0.level,
                                 progress: progress[$0.id])
        }
        candidates += listening.map {
            SetBuilder.Candidate(id: $0.id, mode: .listening, category: $0.category, level: $0.level,
                                 progress: progress[$0.id])
        }
        let eligible = SetBuilder.eligible(candidates, config: config, enabledLevels: settings.enabledLevelsByMode)
        // おまかせは軸ごとに今のステージを中心に、到達済みの帯を少し混ぜる（§3.4）
        let picked: [SetBuilder.Candidate]
        if config.isAuto, config.filter == .all, config.restrictTo == nil {
            let stages = stageStates()
            picked = SetBuilder.pick(from: eligible, factor: { c in
                guard let s = stages[c.mode] else { return 0 }
                return Stage.weightFactor(level: c.level, current: s.current, unlocked: s.unlocked)
            }, using: &rng)
        } else {
            picked = SetBuilder.pick(from: eligible, using: &rng)
        }
        return picked.compactMap { c in
            switch c.mode {
            case .grammar:
                guard let g = grammarSnaps[c.id] else { return nil }
                return GrammarQuestionFactory.make(g, using: &rng)
            case .word:
                guard let w = wordSnaps[c.id] else { return nil }
                let f = config.format ?? (WordFormat.allCases.randomElement(using: &rng) ?? .meaning)
                return WordQuestionFactory.make(w, format: f, pool: pool, using: &rng)
            case .listening:
                guard let l = listeningSnaps[c.id] else { return nil }
                return ListeningQuestionFactory.make(l, using: &rng)
            }
        }
    }

    /// 回答を確定し、即座に Progress へ記録（§3.3）。練習問題は記録しない
    func answerCurrent(_ chosen: Int) {
        guard let run, let a = run.answer(chosen) else { return }
        guard !a.question.isPractice else { return }
        let p = progress(for: a.question.itemID)
        p.record(isCorrect: a.isCorrect)
        save("answer")
    }

    func advance() {
        run?.next()
    }

    /// セット完走。StudySession を保存して結果へ
    func finishRun() {
        guard let run, run.isFinished else { return }
        let session = StudySession(
            startedAt: run.startedAt, finishedAt: .now, mode: run.config.mode,
            category: run.config.category, questionFormat: run.config.format,
            results: run.answers.map {
                SessionResult(itemID: $0.question.itemID, isCorrect: $0.isCorrect,
                              chosenIndex: $0.chosenIndex, elapsedMs: $0.elapsedMs)
            })
        context.insert(session)
        save("session")
        lastSavedSession = session
        let ids = run.questions.filter { !$0.isPractice }.map(\.itemID)
        lastSetGain = MasteryStats.setGain(itemIDs: ids, progress: Dictionary(ids.map { ($0, progress(for: $0).snapshot) }, uniquingKeysWith: { a, _ in a }),
                                           since: run.startedAt)
        analytics.log(.setFinish(run.config, count: run.answers.count,
                                 correct: run.answers.filter(\.isCorrect).count,
                                 durationSec: Int(session.finishedAt.timeIntervalSince(session.startedAt))))
        // このセットで出した軸だけ判定する（手動で下げた別の軸が、関係ないセットでクリア扱いになるのを避ける）
        let modes = Set(run.questions.filter { !$0.isPractice }.map(\.mode))
        let stages = stageStates()
        let clears = DrillMode.allCases.filter(modes.contains).compactMap { mode -> Stage.Clear? in
            guard let s = stages[mode] else { return nil }
            return Stage.clearEvent(mode: mode, unlocked: s.unlocked, byLevel: s.byLevel,
                                    topCelebrated: settings.topStageCelebrated.contains(mode))
        }
        if Self.reviewPromptEnabled {
            pendingReviewRequest = ReviewPrompt.trigger(
                correct: run.correctCount, total: run.questions.count,
                finishedSets: (try? context.fetchCount(FetchDescriptor<StudySession>())) ?? 0,
                stageCleared: !clears.isEmpty,
                lastAskedVersion: settings.reviewRequestedVersion, currentVersion: Self.appVersion)
            #if DEBUG
            // 確認用。起動引数 `-debugReviewPrompt YES` で、条件に関係なく毎セット頼む
            if UserDefaults.standard.bool(forKey: "debugReviewPrompt") { pendingReviewRequest = .highScore }
            #endif
        }
        if !clears.isEmpty {
            for clear in clears {
                if let next = clear.next {
                    settings.setUnlockedLevel(next, for: clear.mode)
                } else {
                    settings.setTopStageCelebrated(true, for: clear.mode)
                }
                analytics.log(.stageClear(clear))
            }
            lastUnlocked = clears.filter { $0.next != nil }
            pendingStageClears = clears
            analytics.syncUserProperties()
            path = [.stageClear]
        } else {
            path = [.result]
        }
        refreshWidgetSnapshot()
        refreshReminders()
    }

    /// 演出を見終えて結果へ
    func showResultAfterStageClear() {
        path = [.result]
    }

    /// 結果画面が評価ダイアログを頼む直前に呼ぶ。頼むきっかけを消費し、このバージョンでは以後頼まない
    func consumeReviewRequest() -> Bool {
        guard let trigger = pendingReviewRequest else { return false }
        pendingReviewRequest = nil
        settings.reviewRequestedVersion = Self.appVersion
        analytics.log(.reviewRequested(trigger))
        return true
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// 起動引数 `-reviewPrompt NO` で評価ダイアログを頼まない（UI テストはこれで起動）
    static var reviewPromptEnabled: Bool {
        UserDefaults.standard.object(forKey: "reviewPrompt") == nil || UserDefaults.standard.bool(forKey: "reviewPrompt")
    }

    #if DEBUG
    /// 撮影用。起動引数 `-debugSeedProgress YES` で、記録を消して「学習が進んだ状態」のサンプル記録を作る
    /// （単語・文法は 450 点帯クリア済みで 500 点帯の途中、応答問題は 450 点帯の途中、12 日連続、今日も学習済み）。
    /// シミュレータ専用。`-cloudSync NO` と一緒に使う
    func seedDebugProgressIfRequested() {
        guard UserDefaults.standard.bool(forKey: "debugSeedProgress") else { return }
        try? context.delete(model: ItemProgress.self)
        try? context.delete(model: StudySession.self)
        let cal = Calendar.current
        let now = Date.now
        var rng = SeededRandomNumberGenerator(seed: 7)
        func day(_ ago: Int, hour: Int) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: -ago, to: cal.startOfDay(for: now))!)!
        }
        // 軸・帯ごとの (習得, 学習中, 苦手) の件数
        let plan: [(DrillMode, Int, Int, Int, Int)] = [
            (.word, 450, 88, 6, 4), (.word, 500, 38, 10, 6),
            (.grammar, 450, 44, 3, 2), (.grammar, 500, 15, 6, 4),
            (.listening, 450, 17, 5, 3),
        ]
        var seeded: [String] = []
        for (mode, level, mastered, learning, struggling) in plan {
            let ids = catalog.items(mode).filter { $0.level == level }.map(\.id).shuffled(using: &rng)
            for (i, id) in ids.enumerated() {
                let p = ItemProgress(itemID: id)
                if i < mastered {
                    p.recentResults = [true, true, true]
                    p.totalAnswered = Int.random(in: 3...6, using: &rng); p.totalCorrect = p.totalAnswered - Int.random(in: 0...1, using: &rng)
                    let d = day(Int.random(in: 0...11, using: &rng), hour: 20)
                    p.masteredAt = d; p.lastAnsweredAt = d
                } else if i < mastered + learning {
                    p.recentResults = [true, false, true]
                    p.totalAnswered = 3; p.totalCorrect = 2; p.lastAnsweredAt = day(Int.random(in: 0...3, using: &rng), hour: 21)
                } else if i < mastered + learning + struggling {
                    p.recentResults = [false, true, false]
                    p.totalAnswered = 3; p.totalCorrect = 1; p.lastAnsweredAt = day(Int.random(in: 0...2, using: &rng), hour: 21)
                } else {
                    continue
                }
                context.insert(p)
                seeded.append(id)
            }
        }
        // 12 日連続（1 日 1〜3 セット）。日別グラフの山に変化を付ける
        let setsPerDay = [2, 1, 2, 3, 1, 2, 2, 1, 3, 2, 1, 2]
        for (ago, sets) in setsPerDay.enumerated() {
            for s in 0..<sets {
                let finished = day(ago, hour: 7 + s * 6)
                let results = (0..<10).map { _ in
                    SessionResult(itemID: seeded.randomElement(using: &rng) ?? "", isCorrect: Int.random(in: 0..<10, using: &rng) < 7,
                                  chosenIndex: 0, elapsedMs: 4000)
                }
                context.insert(StudySession(startedAt: finished.addingTimeInterval(-200), finishedAt: finished, mode: nil,
                                            category: nil, questionFormat: nil, results: results))
            }
        }
        save("debugSeed")
        settings.setUnlockedLevel(500, for: .word)
        settings.setUnlockedLevel(500, for: .grammar)
        settings.setUnlockedLevel(450, for: .listening)
        settings.stageTracksMigrated = true
    }

    /// Crashlytics の確認用。起動引数 `-debugCrash YES` を付けるとホーム表示直後にわざと落ちる（§7.1）。

    /// 報告は次回起動時に送られるので、落とした後にもう一度 `-analytics YES` で起動する
    func crashIfRequested() {
        guard UserDefaults.standard.bool(forKey: "debugCrash") else { return }
        fatalError("Crashlytics の確認用のクラッシュ（起動引数 -debugCrash YES）")
    }

    /// 確認・撮影用。起動引数 `-debugStageClear 500` でホーム表示直後に「単語 450 点帯クリア → 500 点帯へ」の演出を出す。
    /// `top` なら最上位クリア、`grammar:500` / `listening:500` のように軸を付けられ、`both:500` なら全軸同時。記録や設定は変えない

    func showDebugStageClearIfRequested() {
        guard let arg = UserDefaults.standard.string(forKey: "debugStageClear"), path.isEmpty else { return }
        let parts = arg.split(separator: ":").map(String.init)
        let level = parts.last ?? ""
        let modes: [DrillMode] = parts.count < 2 ? [.word]
            : parts[0] == "both" ? DrillMode.allCases : [DrillMode(rawValue: parts[0]) ?? .word]
        let clears: [Stage.Clear] = modes.compactMap { mode in
            if level == "top" { return Stage.Clear(mode: mode, cleared: Stage.last, next: nil) }
            guard let next = Int(level), let i = Stage.levels.firstIndex(of: next), i > 0 else { return nil }
            return Stage.Clear(mode: mode, cleared: Stage.levels[i - 1], next: next)
        }
        guard !clears.isEmpty else { return }
        pendingStageClears = clears
        path = [.stageClear]
    }
    #endif

    // MARK: - ステージ

    struct StageState {
        var current: Int
        var unlocked: Int
        var byLevel: [Int: MasterySummary]
    }

    /// 軸ごとの全レベルの習得状況と、今取り組む帯（§3.4 [v1.8]）
    func stageStates() -> [DrillMode: StageState] {
        let progress = progressMap()
        let items = catalog.levelItemsByMode
        return Dictionary(uniqueKeysWithValues: DrillMode.allCases.map { mode in

            let byLevel = MasteryStats.byLevel(items: items[mode] ?? [], progress: progress)
            let unlocked = settings.unlockedLevel(mode)
            return (mode, StageState(current: Stage.current(unlocked: unlocked, byLevel: byLevel, floor: settings.startingLevel),

                                     unlocked: unlocked, byLevel: byLevel))
        })
    }

    func stageState(_ mode: DrillMode) -> StageState {
        stageStates()[mode] ?? StageState(current: Stage.first, unlocked: Stage.first, byLevel: [:])
    }

    /// 途中離脱。セットは保存しない（回答済みの Progress はそのまま残す）
    func abandonRun() {
        if let run { analytics.log(.setAbort(run.config, answered: run.answers.count)) }
        run = nil
        path = []
    }

    func goHome() {
        run = nil
        pendingStageClears = []
        pendingReviewRequest = nil
        path = []
    }

    // MARK: - Progress

    func progress(for itemID: String) -> ItemProgress {
        let descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.itemID == itemID })
        let found = (try? context.fetch(descriptor)) ?? []
        if let existing = found.first {
            // 同期で重複していたらここでまとめる
            for extra in found.dropFirst() {
                existing.absorb(extra.snapshot)
                context.delete(extra)
            }
            return existing
        }
        let p = ItemProgress(itemID: itemID)
        context.insert(p)
        return p
    }

    func progressMap() -> [String: ProgressSnapshot] {
        let all = (try? context.fetch(FetchDescriptor<ItemProgress>())) ?? []
        return Dictionary(all.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, b in RecordMerge.merge(a, b) })
    }

    func isBookmarked(_ itemID: String) -> Bool {
        let descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.itemID == itemID })
        return ((try? context.fetch(descriptor)) ?? []).contains { $0.isBookmarked }
    }

    func toggleBookmark(_ itemID: String) {
        let p = progress(for: itemID)
        p.isBookmarked.toggle()
        save("bookmark")
        analytics.log(.bookmarkToggled(on: p.isBookmarked))
    }

    /// 設定で到達帯を下げたときの「やり直し」（§3.4 / §4.4 [v2.0]、Issue #56）。
    /// その軸の、level 以上の帯の問題の習得（直近の正誤と習得日時）を消して未学習に戻す。累計の回答数・正解数・ブックマーク・セットの記録は残す。
    /// 到達帯を level にし、最上位の演出フラグを戻し、開始の帯が level より上なら level まで下げる
    func restartStage(_ mode: DrillMode, from level: Int) {
        let ids = Set(catalog.items(mode).filter { $0.level >= level }.map(\.id))
        let rows = (try? context.fetch(FetchDescriptor<ItemProgress>())) ?? []
        for p in rows where ids.contains(p.itemID) {
            p.recentResults = []
            p.masteredAt = nil
        }
        save("restartStage")
        settings.setUnlockedLevel(level, for: mode)
        settings.setTopStageCelebrated(false, for: mode)
        settings.setStageRestartedAt(.now, for: mode)
        if settings.startingLevel > level { settings.startingLevel = level }
        lastUnlocked = []
        lastSetGain = (0, 0)
        pendingStageClears = []
        analytics.log(.stageRestart(mode: mode, level: level))
        analytics.syncUserProperties()
        refreshWidgetSnapshot()
    }

    /// 学習履歴のリセット（Progress と StudySession を全削除。問題データは残す）
    func resetHistory() throws {
        try context.delete(model: ItemProgress.self)
        try context.delete(model: StudySession.self)
        try context.save()
        settings.startingLevel = Stage.first
        for mode in DrillMode.allCases {
            settings.setUnlockedLevel(Stage.first, for: mode)
            settings.setTopStageCelebrated(false, for: mode)
            settings.setStageRestartedAt(nil, for: mode)
        }

        lastUnlocked = []
        lastSetGain = (0, 0)
        pendingStageClears = []
        pendingReviewRequest = nil
        analytics.log(.historyReset)
        analytics.syncUserProperties()
        refreshWidgetSnapshot()
        refreshReminders()
    }
}
