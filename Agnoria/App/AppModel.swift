import Foundation
import Observation
import SwiftData

enum Route: Hashable {
    case quiz
    case result
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
    var path: [Route] = []
    var run: QuizRun?
    var importState: ImportState = .idle
    var lastSavedSession: StudySession?

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
    }

    // MARK: - 取り込み

    /// 起動時にバックグラウンドで実行。JSON が前回と同じなら何もしない
    func importBundledDataIfNeeded() async {
        guard importState != .running else { return }
        importState = .running
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

    // MARK: - セット

    /// 条件からセットを作って開始。対象が0件なら nil
    @discardableResult
    func startQuiz(_ config: QuizConfig) -> QuizRun? {
        var rng = SystemRandomNumberGenerator()
        let questions = buildQuestions(config, using: &rng)
        guard !questions.isEmpty else { return nil }
        let run = QuizRun(config: config, questions: questions)
        self.run = run
        path = [.quiz]
        return run
    }

    func buildQuestions(_ config: QuizConfig, using rng: inout some RandomNumberGenerator) -> [QuizQuestion] {
        let progress = progressMap()
        switch config.mode {
        case .grammar:
            let items = (try? context.fetch(FetchDescriptor<GrammarQuestion>(
                predicate: #Predicate { !$0.isArchived }))) ?? []
            let snaps = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.snapshot) })
            let candidates = items.map {
                SetBuilder.Candidate(id: $0.id, category: $0.category, level: $0.level, progress: progress[$0.id])
            }
            let eligible = SetBuilder.eligible(candidates, config: config, enabledLevels: settings.enabledLevels)
            let picked = SetBuilder.pick(from: eligible, using: &rng).compactMap { snaps[$0.id] }
            return SetBuilder.grammarQuestions(picked, using: &rng)
        case .word:
            let items = (try? context.fetch(FetchDescriptor<Word>(
                predicate: #Predicate { !$0.isArchived }))) ?? []
            let pool = items.map(\.snapshot)
            let snaps = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
            let candidates = items.map {
                SetBuilder.Candidate(id: $0.id, category: $0.category, level: $0.level, progress: progress[$0.id])
            }
            let eligible = SetBuilder.eligible(candidates, config: config, enabledLevels: settings.enabledLevels)
            let picked = SetBuilder.pick(from: eligible, using: &rng).compactMap { snaps[$0.id] }
            return SetBuilder.wordQuestions(picked, format: config.format, pool: pool, using: &rng)
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
        path = [.result]
    }

    /// 途中離脱。セットは保存しない（回答済みの Progress はそのまま残す）
    func abandonRun() {
        run = nil
        path = []
    }

    func goHome() {
        run = nil
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
    }

    /// 学習履歴のリセット（Progress と StudySession を全削除。問題データは残す）
    func resetHistory() throws {
        try context.delete(model: ItemProgress.self)
        try context.delete(model: StudySession.self)
        try context.save()
    }
}
