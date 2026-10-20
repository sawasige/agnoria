import Foundation
import Testing
import SwiftData
@testable import Agnoria

/// バンドルデータを in-memory の SwiftData に取り込み、セットが最後まで回ることを確認する
@Suite("AppModel 通し", .serialized)
@MainActor
struct AppModelTests {
    private func makeModel() async throws -> AppModel {
        let container = try AgnoriaSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
        let model = AppModel(container: container, settings: AppSettings(defaults: defaults))
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        _ = try await DataImporter(modelContainer: container).importData(payload)
        return model
    }

    @Test("おまかせは単語と文法が混ざった10問になり、セッションは mode=auto で保存される") func autoRun() async throws {
        let model = try await makeModel()
        var rng = SeededRandomNumberGenerator(seed: 11)
        let qs = model.buildQuestions(.auto, using: &rng)
        #expect(qs.count == 10)
        #expect(qs.contains { $0.mode == .word })
        #expect(qs.contains { $0.mode == .grammar })

        let run = try #require(model.startQuiz(.auto))
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        let sessions = try model.container.mainContext.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.first?.mode == StudySession.autoMode)
        #expect(sessions.first?.category == nil)
    }

    @Test("単語・文法それぞれで10問セットが最後まで回り、セッションが保存される") func fullRun() async throws {
        let model = try await makeModel()
        for mode in DrillMode.allCases {
            let run = try #require(model.startQuiz(QuizConfig(mode: mode, category: nil, format: nil)))
            #expect(run.questions.count == 10)
            #expect(model.path == [.quiz])
            while !run.isFinished {
                model.answerCurrent(run.current.correctIndex)
                if !run.isLast { model.advance() }
            }
            model.finishRun()
            #expect(model.path == [.result])
            #expect(run.correctCount == 10)
        }
        let sessions = try model.container.mainContext.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.results.count == 10 })
        let progress = try model.container.mainContext.fetch(FetchDescriptor<ItemProgress>())
        #expect(progress.count == 20)
    }

    @Test("masteredAt 追加前に習得していた問題は起動時に補われる") func backfill() async throws {
        let model = try await makeModel()
        let ctx = model.container.mainContext
        let a = ItemProgress(itemID: "w-0001"); a.recentResults = [true, true, true]; a.lastAnsweredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let b = ItemProgress(itemID: "w-0002"); b.recentResults = [true, true]; b.lastAnsweredAt = .now
        ctx.insert(a); ctx.insert(b); try ctx.save()
        model.backfillMasteredAt()
        #expect(a.masteredAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(b.masteredAt == nil)
        #expect(Mastery.of(a.snapshot) == .mastered)
    }

    @Test("分野指定・形式指定が反映される") func categoryAndFormat() async throws {
        let model = try await makeModel()
        model.settings.unlockedLevel = Stage.last
        var rng = SeededRandomNumberGenerator(seed: 1)
        let qs = model.buildQuestions(QuizConfig(mode: .word, category: "人事・採用", format: .cloze), using: &rng)
        #expect(qs.count == 10)
        #expect(qs.allSatisfy { $0.categoryName == "人事・採用" })
        #expect(qs.allSatisfy { $0.wordFormat == .cloze })
        #expect(qs.allSatisfy { $0.prompt.contains(Cloze.blank) })
    }

    @Test("間違えた問題だけ・ブックマークだけ") func wrongAndBookmark() async throws {
        let model = try await makeModel()
        var rng = SeededRandomNumberGenerator(seed: 2)
        #expect(model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly), using: &rng).isEmpty)

        let run = try #require(model.startQuiz(QuizConfig(mode: .grammar, category: nil, format: nil)))
        let wrongIndex = (run.current.correctIndex + 1) % 4
        model.answerCurrent(wrongIndex)
        let wrongID = run.current.itemID
        model.toggleBookmark(wrongID)
        model.abandonRun()
        #expect(model.path.isEmpty)

        let wrongOnly = model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly), using: &rng)
        #expect(wrongOnly.map(\.itemID) == [wrongID])
        let bookmarked = model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked), using: &rng)
        #expect(bookmarked.map(\.itemID) == [wrongID])

        try model.resetHistory()
        #expect(model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked), using: &rng).isEmpty)
    }

    @Test("到達帯より上のレベルは出題されない") func stageLimitsLevels() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        let top = Set(payload.words.filter { $0.level == Stage.last }.map(\.id))
        try #require(!top.isEmpty)
        model.settings.unlockedLevel = Stage.first
        #expect(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil, restrictTo: top)) == nil)
        #expect(model.path.isEmpty)
        var rng = SeededRandomNumberGenerator(seed: 5)
        let levels = Dictionary(uniqueKeysWithValues: (payload.words.map { ($0.id, $0.level) } + payload.grammar.map { ($0.id, $0.level) }))
        let auto = model.buildQuestions(.auto, using: &rng)
        #expect(!auto.isEmpty)
        #expect(auto.allSatisfy { levels[$0.itemID] == Stage.first })
        model.settings.unlockedLevel = Stage.last
        #expect(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil, restrictTo: top)) != nil)
    }

    @Test("到達帯の習得率が80%を超えたセットの完走で次の帯が開く") func unlockNextStage() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        let firstLevelIDs = payload.words.filter { $0.level == Stage.first }.map(\.id)
            + payload.grammar.filter { $0.level == Stage.first }.map(\.id)
        for id in firstLevelIDs {
            let p = model.progress(for: id)
            for _ in 0..<3 { p.record(isCorrect: true) }
        }
        #expect(model.settings.unlockedLevel == Stage.first)
        let run = try #require(model.startQuiz(.auto))
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        #expect(model.settings.unlockedLevel == Stage.next(after: Stage.first))
        #expect(model.lastUnlockedLevel == Stage.next(after: Stage.first))
        #expect(model.stageState().current == Stage.next(after: Stage.first))
        #expect(model.pendingReviewRequest == .stageClear)
        try model.resetHistory()
        #expect(model.settings.unlockedLevel == Stage.first)
        #expect(model.lastUnlockedLevel == nil)
    }

    @Test("全問正解を 5 セット完走すると評価ダイアログを頼み、同じバージョンでは以後頼まない") func reviewRequest() async throws {
        let model = try await makeModel()
        for n in 1...6 {
            let run = try #require(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil)))
            while !run.isFinished {
                model.answerCurrent(run.current.correctIndex)
                if !run.isLast { model.advance() }
            }
            model.finishRun()
            #expect(model.pendingReviewRequest == (n == ReviewPrompt.minFinishedSets ? .highScore : nil))
            if n == ReviewPrompt.minFinishedSets {
                #expect(model.consumeReviewRequest())
                #expect(!model.consumeReviewRequest())
                #expect(model.settings.reviewRequestedVersion == AppModel.appVersion)
            }
        }
    }
}
