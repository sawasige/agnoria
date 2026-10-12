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

    @Test("分野指定・形式指定が反映される") func categoryAndFormat() async throws {
        let model = try await makeModel()
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

    @Test("レベル絞り込みで0件なら開始しない") func levelFilterEmpty() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        // 600 点帯の単語が無い分野を探す
        let emptyCategory = try #require(WordCategory.allCases.map(\.rawValue).first { cat in
            !payload.words.contains { $0.category == cat && $0.level == 600 }
        })
        model.settings.enabledLevels = [600]
        #expect(model.startQuiz(QuizConfig(mode: .word, category: emptyCategory, format: nil)) == nil)
        #expect(model.path.isEmpty)
        model.settings.enabledLevels = Level.allValues
        #expect(model.startQuiz(QuizConfig(mode: .word, category: emptyCategory, format: nil)) != nil)
    }
}
