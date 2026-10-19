import Foundation
import Testing
import SwiftData
@testable import Agnoria

@Suite("バンドル JSON")
struct BundleDataTests {
    private var bundle: Bundle { Bundle(for: ItemProgress.self) }

    @Test("読み込めて検証エラーがない") func loadsAndValidates() throws {
        let payload = try BundleData.load(bundle: bundle)
        #expect(payload.words.count >= 50)
        #expect(payload.grammar.count >= 30)
        let issues = BundleData.validate(payload)
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test("5分野すべてに問題がある") func allCategoriesPresent() throws {
        let payload = try BundleData.load(bundle: bundle)
        #expect(Set(payload.words.map(\.category)) == Set(WordCategory.allCases.map(\.rawValue)))
        #expect(Set(payload.grammar.map(\.category)) == Set(GrammarCategory.allCases.map(\.rawValue)))
    }

    @Test("商標名がデータに含まれない") func noTrademark() throws {
        for name in ["words", "grammar"] {
            let url = try #require(bundle.url(forResource: name, withExtension: "json"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("TOEIC"), "\(name).json")
        }
    }

    @Test("すべての単語で cloze か meaning が作れる") func everyWordProducesQuestion() throws {
        let payload = try BundleData.load(bundle: bundle)
        var rng = SeededRandomNumberGenerator(seed: 9)
        for w in payload.words {
            for f in WordFormat.allCases {
                let q = WordQuestionFactory.make(w, format: f, pool: payload.words, using: &rng)
                #expect(q != nil, "\(w.id) \(f)")
                if let q {
                    #expect(q.choices.count == 4, "\(w.id) \(f)")
                    #expect(Set(q.choices).count == 4, "\(w.id) \(f): 選択肢が重複")
                }
            }
        }
    }

    @Test("fingerprint は内容が変わると変わる") func fingerprintChanges() throws {
        let a = try BundleData.decode(wordsData: Data("[]".utf8), grammarData: Data("[]".utf8))
        let b = try BundleData.decode(wordsData: Data("[ ]".utf8), grammarData: Data("[]".utf8))
        #expect(a.fingerprint != b.fingerprint)
    }
}

@Suite("SwiftData 取り込み", .serialized)
struct ImporterTests {
    private func makeWord(_ id: String, _ word: String) -> WordSnapshot {
        WordSnapshot(id: id, word: word, pos: "名詞", meaning: "m", example: "e \(word)", exampleJa: "j",
                     distractors: ["a", "b", "c"], category: "ビジネス一般", level: 450)
    }
    private func makeGrammar(_ id: String) -> GrammarSnapshot {
        GrammarSnapshot(id: id, category: "品詞", question: "x ______ y", questionJa: "x a y の訳", choices: ["a", "b", "c", "d"],
                        answer: 0, explanation: "e", level: 450)
    }

    @Test("upsert と アーカイブ") func upsertAndArchive() async throws {
        let container = try AgnoriaSchema.makeContainer(inMemory: true)
        let importer = DataImporter(modelContainer: container)

        let first = BundleData.Payload(words: [makeWord("w1", "alpha"), makeWord("w2", "beta")],
                                       grammar: [makeGrammar("g1")], fingerprint: "1")
        let s1 = try await importer.importData(first)
        #expect(s1 == .init(inserted: 3, updated: 0, archived: 0))

        // w2 を削除、w1 を更新、w3 を追加
        let second = BundleData.Payload(words: [makeWord("w1", "alpha2"), makeWord("w3", "gamma")],
                                        grammar: [makeGrammar("g1")], fingerprint: "2")
        let s2 = try await importer.importData(second)
        #expect(s2 == .init(inserted: 1, updated: 2, archived: 1))

        let context = ModelContext(container)
        let words = try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.id)]))
        #expect(words.map(\.id) == ["w1", "w2", "w3"])
        #expect(words[0].word == "alpha2")
        #expect(words[1].isArchived)
        #expect(!words[2].isArchived)

        // 履歴は id に紐づくので残る
        let p = ItemProgress(itemID: "w2")
        p.record(isCorrect: false)
        context.insert(p)
        try context.save()
        let third = BundleData.Payload(words: [makeWord("w1", "alpha2"), makeWord("w2", "beta"), makeWord("w3", "gamma")],
                                       grammar: [makeGrammar("g1")], fingerprint: "3")
        _ = try await importer.importData(third)
        let revived = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.id == "w2" }))
        #expect(revived.first?.isArchived == false)
        let progress = try context.fetch(FetchDescriptor<ItemProgress>())
        #expect(progress.count == 1)
        #expect(progress.first?.recentResults == [false])
    }
}

@Suite("連続日数・称号")
struct StreakTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour))!
        return cal.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func doneTodayAndYesterday() {
        let r = Streak.compute(sessionDates: [day(-2), day(-1), day(0, hour: 8), day(0, hour: 20)], today: day(0), calendar: cal)
        #expect(r == .init(days: 3, doneToday: true))
    }
    @Test("今日まだでも昨日までの連続は維持") func notYetToday() {
        let r = Streak.compute(sessionDates: [day(-2), day(-1)], today: day(0), calendar: cal)
        #expect(r == .init(days: 2, doneToday: false))
    }
    @Test func broken() {
        let r = Streak.compute(sessionDates: [day(-3), day(-2)], today: day(0), calendar: cal)
        #expect(r == .init(days: 0, doneToday: false))
    }
    @Test func empty() {
        #expect(Streak.compute(sessionDates: [], today: day(0), calendar: cal) == .init(days: 0, doneToday: false))
    }
    @Test func ranks() {
        #expect(Rank.title(totalCorrect: 0) == "Kore")
        #expect(Rank.title(totalCorrect: 100) == "Kore, Learning")
        #expect(Rank.title(totalCorrect: 300) == "Persephone")
        #expect(Rank.title(totalCorrect: 600) == "Persephone, in Spring")
    }
}

@Suite("QuizRun")
@MainActor
struct QuizRunTests {
    private func question(_ i: Int) -> QuizQuestion {
        QuizQuestion(itemID: "q\(i)", mode: .grammar, wordFormat: nil, categoryName: "品詞", prompt: "p",
                     choices: ["a", "b", "c", "d"], correctIndex: 1, explanation: "e", word: nil, speechText: nil)
    }

    @Test func flow() {
        let run = QuizRun(config: QuizConfig(mode: .grammar, category: nil, format: nil),
                          questions: (0..<3).map(question))
        #expect(run.answer(1)?.isCorrect == true)
        #expect(run.answer(0) == nil, "二重回答は無視")
        run.next()
        #expect(run.index == 1)
        run.next()
        #expect(run.index == 1, "未回答では進まない")
        _ = run.answer(0)
        run.next()
        #expect(run.isLast)
        _ = run.answer(1)
        #expect(run.isFinished)
        #expect(run.correctCount == 2)
        #expect(run.wrongAnswers.map(\.question.itemID) == ["q1"])
    }
}

@Suite("効果音の音源")
struct SoundAssetTests {
    @Test("correct / wrong の CAF がバンドルされている") func bundled() {
        let bundle = Bundle(for: ItemProgress.self)
        for effect in SoundEffects.Effect.allCases {
            #expect(bundle.url(forResource: effect.rawValue, withExtension: "caf") != nil, "\(effect.rawValue).caf")
        }
    }
}

@Suite("文法問題の和訳")
struct GrammarTranslationTests {
    @Test("文法問題は和訳を運び、空欄を正解で埋めた英文を作れる") func promptJa() {
        let g = GrammarSnapshot(id: "pos-900", category: "品詞", question: "Please ______ the form.", questionJa: "用紙に記入してください。",
                                choices: ["complete", "completion", "completely", "completed"], answer: 0, explanation: "e", level: 450)
        var rng = SystemRandomNumberGenerator()
        let q = GrammarQuestionFactory.make(g, using: &rng)
        #expect(q.promptJa == "用紙に記入してください。")
        #expect(q.completedPrompt == "Please complete the form.")
        #expect(q.choices[q.correctIndex] == "complete")
    }

    @Test("単語問題は和訳を word 側に持つので promptJa は nil") func wordHasNoPromptJa() {
        let w = WordSnapshot(id: "w-900", word: "invoice", pos: "名", meaning: "請求書", example: "Please pay the invoice.",
                             exampleJa: "請求書をお支払いください。", distractors: ["a", "b", "c"], category: "ビジネス一般", level: 450)
        var rng = SystemRandomNumberGenerator()
        let q = WordQuestionFactory.make(w, format: .meaning, pool: [w], using: &rng)
        #expect(q?.promptJa == nil)
    }
}
