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
        #expect(payload.listening.count >= 30)
        let issues = BundleData.validate(payload)
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test("5分野すべてに問題がある") func allCategoriesPresent() throws {
        let payload = try BundleData.load(bundle: bundle)
        #expect(Set(payload.words.map(\.category)) == Set(WordCategory.allCases.map(\.rawValue)))
        #expect(Set(payload.grammar.map(\.category)) == Set(GrammarCategory.allCases.map(\.rawValue)))
        #expect(Set(payload.listening.map(\.category)) == Set(ListeningCategory.allCases.map(\.rawValue)))
    }

    @Test("リスニングは各帯 30 問（5 分野 × 6）で、解説が選択肢を A / B / C で指さない") func listeningShape() throws {
        let payload = try BundleData.load(bundle: bundle)
        #expect(payload.listening.count == 120)
        for level in Level.allCases {
            let inLevel = payload.listening.filter { $0.level == level.rawValue }
            #expect(inLevel.count == 30, "\(level.rawValue)")
            for cat in ListeningCategory.allCases {
                #expect(inLevel.filter { $0.category == cat.rawValue }.count == 6, "\(level.rawValue) \(cat.rawValue)")
            }
        }
        // 画面では応答の順をシャッフルするので、解説は文字（A / B / C）ではなく応答の英文で指す
        let letters = try Regex(#"(\(|（|\b)[ABC](\)|）|\b)"#)
        for l in payload.listening {
            #expect(!l.explanation.contains(letters), "\(l.id): \(l.explanation)")
            #expect(l.choices.allSatisfy { $0.count <= 80 } && l.question.count <= 100, "\(l.id): 長すぎる")
        }
        // 正解の位置が偏っていない（シャッフルするので必須ではないが、データの癖を見る）
        let positions = Dictionary(grouping: payload.listening, by: \.answer).mapValues(\.count)
        #expect(positions.values.allSatisfy { $0 >= 25 }, "\(positions)")
    }

    @Test("商標名がデータに含まれない") func noTrademark() throws {
        for name in ["words", "grammar", "listening"] {
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
        let a = try BundleData.decode(wordsData: Data("[]".utf8), grammarData: Data("[]".utf8), listeningData: Data("[]".utf8))
        let b = try BundleData.decode(wordsData: Data("[ ]".utf8), grammarData: Data("[]".utf8), listeningData: Data("[]".utf8))
        let c = try BundleData.decode(wordsData: Data("[]".utf8), grammarData: Data("[]".utf8), listeningData: Data("[ ]".utf8))
        #expect(a.fingerprint != b.fingerprint)
        #expect(a.fingerprint != c.fingerprint)
    }
}

@Suite("問題データのカタログ")
struct QuestionCatalogTests {
    private var bundle: Bundle { Bundle(for: ItemProgress.self) }

    @Test("同梱 JSON をメモリに読む。起動 1 秒以内の予算に収まる速さ") func loads() throws {
        let clock = ContinuousClock()
        var catalog = QuestionCatalog.empty
        let elapsed = try clock.measure { catalog = QuestionCatalog(try BundleData.load(bundle: bundle)) }
        #expect(elapsed < .milliseconds(500), "\(elapsed)")
        #expect(catalog.words.count == 400 && catalog.grammar.count == 200 && catalog.listening.count == 120)
        #expect(!catalog.isEmpty && QuestionCatalog.empty.isEmpty)
        #expect(catalog.wordByID["w-0001"]?.word == "invoice")
        #expect(catalog.grammarByID["pos-001"] != nil && catalog.listeningByID["lis-wh-001"] != nil)
    }

    @Test("軸ごとの集計用の一覧と、到達帯までの絞り込み") func items() throws {
        let catalog = QuestionCatalog(try BundleData.load(bundle: bundle))
        #expect(catalog.levelItemsByMode[.word]?.count == 400)
        #expect(catalog.levelItemsByMode[.listening]?.count == 120)
        #expect(catalog.categoryItems(.grammar, levels: [450]).count == 50)
        #expect(catalog.categoryItems(.word, levels: [450, 500]).count == 200)
        #expect(Set(catalog.categoryItems(.listening, levels: Level.allValues).map(\.category)) == Set(ListeningCategory.allCases.map(\.rawValue)))
    }

    @Test("JSON に無い id の記録は集計に入らない（記録は消さない）") func unknownIDsIgnored() throws {
        let catalog = QuestionCatalog(words: [], grammar: [], listening: [
            ListeningSnapshot(id: "l1", category: "WH 疑問文", question: "q", questionJa: "j", choices: ["a", "b", "c"],
                              choicesJa: ["a", "b", "c"], answer: 0, explanation: "e", level: 450)])
        var done = ProgressSnapshot(itemID: "deleted"); done.recentResults = [true, true, true]
        let progress = ["deleted": done, "l1": ProgressSnapshot(itemID: "l1")]
        let s = MasteryStats.byLevel(items: catalog.levelItems(.listening), progress: progress)
        #expect(s[450]?.total == 1 && s[450]?[.mastered] == 0)
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
