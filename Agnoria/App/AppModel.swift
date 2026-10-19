import Foundation
import Observation
import SwiftData

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
    var path: [Route] = []
    var run: QuizRun?
    var importState: ImportState = .idle
    var lastSavedSession: StudySession?
    /// 直近のセット完走で開いたスコア帯（結果画面の演出用）。次のセット開始で消す
    var lastUnlockedLevel: Int?
    /// 直近のセット完走でクリアしたスコア帯（専用画面の演出用 §4.3.1 [v1.5]）。次のセット開始とホームで消す
    var pendingStageClear: Stage.Clear?

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, settings: AppSettings, analytics: UsageAnalytics? = nil) {
        self.container = container
        self.settings = settings
        self.analytics = analytics ?? UsageAnalytics(settings: settings)
    }

    // MARK: - 取り込み

    /// 起動時にバックグラウンドで実行。JSON が前回と同じなら何もしない
    func importBundledDataIfNeeded() async {
        guard importState != .running else { return }
        importState = .running
        backfillMasteredAt()
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
        }
    }

    /// [v1.4] masteredAt 追加前に習得していた問題へ、最後の回答日時を習得日として補う（起動時に 1 回。該当がなければ何もしない）
    func backfillMasteredAt() {
        let rows = (try? context.fetch(FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.masteredAt == nil }))) ?? []
        var changed = false
        for p in rows where Priority.isGraduated(p.recentResults) {
            p.masteredAt = p.lastAnsweredAt ?? .now
            changed = true
        }
        if changed { try? context.save() }
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
        try? context.save()
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
        try? context.save()
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
    }

    /// 演出を見終えて結果へ
    func showResultAfterStageClear() {
        path = [.result]
    }

    #if DEBUG
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
        if let existing = try? context.fetch(descriptor).first { return existing }
        let p = ItemProgress(itemID: itemID)
        context.insert(p)
        return p
    }

    func progressMap() -> [String: ProgressSnapshot] {
        let all = (try? context.fetch(FetchDescriptor<ItemProgress>())) ?? []
        return Dictionary(all.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
    }

    func isBookmarked(_ itemID: String) -> Bool {
        let descriptor = FetchDescriptor<ItemProgress>(predicate: #Predicate { $0.itemID == itemID })
        return (try? context.fetch(descriptor).first?.isBookmarked) ?? false
    }

    func toggleBookmark(_ itemID: String) {
        let p = progress(for: itemID)
        p.isBookmarked.toggle()
        try? context.save()
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
    }
}
