import Foundation
import Observation
import SwiftData
import CoreData
#if os(iOS)
import WidgetKit
#endif

enum Route: Hashable {
    case quiz
    /// スコア帯クリアの演出（結果の前に挟む）[v1.5]
    case stageClear
    case result
    case stats
    case pick
}

enum ImportState: Equatable, Sendable {
    case idle
    case running
    case done
    case failed(String)
}

/// アプリ全体の状態（MV）。ナビゲーション・取り込み・セットの開始と記録を担当
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let settings: AppSettings
    let analytics: UsageAnalytics
    /// 記録ストアが iCloud 同期の構成か（§2.3 [v1.7]）
    let cloudSync: Bool
    var path: [Route] = []
    var run: QuizRun?
    var importState: ImportState = .idle
    var lastSavedSession: StudySession?
    /// 直近のセット完走で開いたスコア帯（結果画面の演出用）。次のセット開始で消す
    var lastUnlockedLevel: Int?
    /// 直近のセット完走でクリアしたスコア帯（専用画面の演出用 §4.3.1 [v1.5]）。次のセット開始とホームで消す
    var pendingStageClear: Stage.Clear?

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, settings: AppSettings, analytics: UsageAnalytics? = nil, cloudSync: Bool = false) {
        self.container = container
        self.settings = settings
        self.analytics = analytics ?? UsageAnalytics(settings: settings)
        self.cloudSync = cloudSync
        if cloudSync { observeRemoteChanges() }
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

    /// 同期後の整合: 重複の合成 → 到達帯の再計算（高い方に揃える）→ ウィジェットの写し
    func reconcileAfterSync() {
        mergeDuplicateRecords()
        let computed = Stage.unlockedFromRecords(byLevel: stageState().byLevel)
        if computed > settings.unlockedLevel { settings.unlockedLevel = computed }
        refreshWidgetSnapshot()
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

    // MARK: - 取り込み

    /// 起動時にバックグラウンドで実行。JSON が前回と同じなら何もしない
    func importBundledDataIfNeeded() async {
        guard importState != .running else { return }
        importState = .running
        // 1.7 で問題データを別ストアに分けた。初回は fingerprint を消して新しいストアへ取り込み直す（§2.3）
        if !settings.storesSplit {
            settings.importedFingerprint = nil
            settings.storesSplit = true
        }
        backfillMasteredAt()
        mergeDuplicateRecords()
        // 取り込みの要否にかかわらず、起動のたびにウィジェットの写しを書き直す（早期 return の経路でも）
        defer { refreshWidgetSnapshot() }
        do {
            let payload = try BundleData.load()
            if settings.importedFingerprint == payload.fingerprint {
                importState = .done
                return
            }
            let importer = DataImporter(modelContainer: container)
            _ = try await importer.importData(payload)
            settings.importedFingerprint = payload.fingerprint
            importState = .done
        } catch {
            importState = .failed(String(describing: error))
            analytics.record(error, "import")
        }
    }

    // MARK: - ウィジェット

    /// ウィジェット用の写しを書き直す（§4.6 [v1.6]）。起動時・セット完走・履歴リセット・到達帯の変更で呼ぶ。
    /// iOS 以外は App Group を持たないので何もしない
    func refreshWidgetSnapshot() {
        #if os(iOS)
        let stage = stageState()
        let dates = ((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).map(\.finishedAt)
        WidgetSnapshot.make(stage: stage, sessionDates: dates).save()
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
        lastUnlockedLevel = nil
        pendingStageClear = nil
        let run = QuizRun(config: config, questions: questions)
        self.run = run
        path = [.quiz]
        analytics.log(.setStart(config))
        return run
    }

    /// 単語・文法の候補をまとめて優先度抽出し、選ばれたものだけ問題化する。
    /// config.mode が指定されていれば eligible で片方に絞られる。nil（おまかせ）なら両方が混ざる
    func buildQuestions(_ config: QuizConfig, using rng: inout some RandomNumberGenerator) -> [QuizQuestion] {
        let progress = progressMap()
        let grammar = (try? context.fetch(FetchDescriptor<GrammarQuestion>(
            predicate: #Predicate { !$0.isArchived }))) ?? []
        let words = (try? context.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { !$0.isArchived }))) ?? []
        let grammarSnaps = Dictionary(uniqueKeysWithValues: grammar.map { ($0.id, $0.snapshot) })
        let pool = words.map(\.snapshot)
        let wordSnaps = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })

        var candidates: [SetBuilder.Candidate] = []
        if config.mode != .word {
            candidates += grammar.map {
                SetBuilder.Candidate(id: $0.id, mode: .grammar, category: $0.category, level: $0.level,
                                     progress: progress[$0.id])
            }
        }
        if config.mode != .grammar {
            candidates += words.map {
                SetBuilder.Candidate(id: $0.id, mode: .word, category: $0.category, level: $0.level,
                                     progress: progress[$0.id])
            }
        }
        let eligible = SetBuilder.eligible(candidates, config: config, enabledLevels: settings.enabledLevels)
        // おまかせは今のステージを中心に、到達済みの帯を少し混ぜる（§3.4）
        let picked: [SetBuilder.Candidate]
        if config.isAuto, config.filter == .all, config.restrictTo == nil {
            let stage = stageState()
            picked = SetBuilder.pick(from: eligible, factor: {
                Stage.weightFactor(level: $0.level, current: stage.current, unlocked: stage.unlocked)
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
        analytics.log(.setFinish(run.config, count: run.answers.count,
                                 correct: run.answers.filter(\.isCorrect).count,
                                 durationSec: Int(session.finishedAt.timeIntervalSince(session.startedAt))))
        let stage = stageState()
        if let clear = Stage.clearEvent(unlocked: stage.unlocked, byLevel: stage.byLevel,
                                        topCelebrated: settings.topStageCelebrated) {
            if let next = clear.next {
                settings.unlockedLevel = next
                lastUnlockedLevel = next
            } else {
                settings.topStageCelebrated = true
            }
            pendingStageClear = clear
            analytics.log(.stageClear(clear))
            analytics.syncUserProperties()
            path = [.stageClear]
        } else {
            path = [.result]
        }
        refreshWidgetSnapshot()
    }

    /// 演出を見終えて結果へ
    func showResultAfterStageClear() {
        path = [.result]
    }

    #if DEBUG
    /// Crashlytics の確認用。起動引数 `-debugCrash YES` を付けるとホーム表示直後にわざと落ちる（§7.1）。
    /// 報告は次回起動時に送られるので、落とした後にもう一度 `-analytics YES` で起動する
    func crashIfRequested() {
        guard UserDefaults.standard.bool(forKey: "debugCrash") else { return }
        fatalError("Crashlytics の確認用のクラッシュ（起動引数 -debugCrash YES）")
    }

    /// 確認・撮影用。起動引数 `-debugStageClear 500` でホーム表示直後に「450 点帯クリア → 500 点帯へ」の演出を出す。
    /// `-debugStageClear top` なら最上位クリアの演出。記録や設定は変えない
    func showDebugStageClearIfRequested() {
        guard let arg = UserDefaults.standard.string(forKey: "debugStageClear"), path.isEmpty else { return }
        if arg == "top" {
            pendingStageClear = Stage.Clear(cleared: Stage.last, next: nil)
        } else if let next = Int(arg), let i = Stage.levels.firstIndex(of: next), i > 0 {
            pendingStageClear = Stage.Clear(cleared: Stage.levels[i - 1], next: next)
        } else {
            return
        }
        path = [.stageClear]
    }
    #endif

    // MARK: - ステージ

    struct StageState {
        var current: Int
        var unlocked: Int
        var byLevel: [Int: MasterySummary]
    }

    /// 全レベルの習得状況と、今取り組む帯
    func stageState() -> StageState {
        let progress = progressMap()
        let grammar = (try? context.fetch(FetchDescriptor<GrammarQuestion>(
            predicate: #Predicate { !$0.isArchived }))) ?? []
        let words = (try? context.fetch(FetchDescriptor<Word>(
            predicate: #Predicate { !$0.isArchived }))) ?? []
        let items = grammar.map { (id: $0.id, level: $0.level) } + words.map { (id: $0.id, level: $0.level) }
        let byLevel = MasteryStats.byLevel(items: items, progress: progress)
        let unlocked = settings.unlockedLevel
        return StageState(current: Stage.current(unlocked: unlocked, byLevel: byLevel),
                          unlocked: unlocked, byLevel: byLevel)
    }

    /// 途中離脱。セットは保存しない（回答済みの Progress はそのまま残す）
    func abandonRun() {
        if let run { analytics.log(.setAbort(run.config, answered: run.answers.count)) }
        run = nil
        path = []
    }

    func goHome() {
        run = nil
        pendingStageClear = nil
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

    /// 学習履歴のリセット（Progress と StudySession を全削除。問題データは残す）
    func resetHistory() throws {
        try context.delete(model: ItemProgress.self)
        try context.delete(model: StudySession.self)
        try context.save()
        settings.unlockedLevel = Stage.first
        settings.topStageCelebrated = false
        lastUnlockedLevel = nil
        pendingStageClear = nil
        analytics.log(.historyReset)
        analytics.syncUserProperties()
        refreshWidgetSnapshot()
    }
}
