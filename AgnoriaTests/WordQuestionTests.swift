import Testing
@testable import Agnoria

@Suite("Cloze 置換")
struct ClozeTests {
    @Test func exactMatch() {
        #expect(Cloze.fill("Please pay the invoice within 30 days.", word: "invoice")
                == "Please pay the ______ within 30 days.")
    }
    @Test func caseInsensitive() {
        #expect(Cloze.fill("Revenue increased by ten percent.", word: "revenue")
                == "______ increased by ten percent.")
    }
    @Test func inflections() {
        #expect(Cloze.fill("All applicants must submit a résumé.", word: "applicant")
                == "All ______ must submit a résumé.")
        #expect(Cloze.fill("The meeting has been postponed.", word: "postpone")
                == "The meeting has been ______.")
        #expect(Cloze.fill("The firm is recruiting engineers.", word: "recruit")
                == "The firm is ______ engineers.")
        #expect(Cloze.fill("We are estimating the cost.", word: "estimate")
                == "We are ______ the cost.")
        #expect(Cloze.fill("She applies every year.", word: "apply")
                == "She ______ every year.")
        #expect(Cloze.fill("We are shipping the order today.", word: "ship")
                == "We are ______ the order today.")
    }
    @Test("短い語が長い語の先頭に誤マッチしない") func noFalsePrefix() {
        #expect(Cloze.fill("Please pay the invoice within 30 days.", word: "in") == nil)
        #expect(Cloze.fill("The report is due.", word: "port") == nil)
    }
    @Test func notFound() {
        #expect(Cloze.fill("Please pay the bill.", word: "invoice") == nil)
    }
    @Test func phrase() {
        #expect(Cloze.fill("She is in charge of the Tokyo office.", word: "in charge of")
                == "She is ______ the Tokyo office.")
    }
}

@Suite("単語の出題形式")
struct WordQuestionFactoryTests {
    static func word(_ id: String, _ w: String, pos: String = "名詞", level: Int = 500, meaning: String? = nil) -> WordSnapshot {
        WordSnapshot(id: id, word: w, pos: pos, meaning: meaning ?? "意味\(id)", example: "Please check the \(w) now.",
                     exampleJa: "和訳", distractors: ["誤1", "誤2", "誤3"], category: "ビジネス一般", level: level)
    }

    let pool: [WordSnapshot] = [
        word("1", "invoice"), word("2", "receipt"), word("3", "estimate"), word("4", "contract"),
        word("5", "budget", level: 450), word("6", "attend", pos: "動詞"), word("7", "adopt", pos: "動詞"),
        word("8", "despite", pos: "前置詞"),
    ]

    @Test("meaning: 正解 + distractors の4択") func meaningFormat() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let q = WordQuestionFactory.make(pool[0], format: .meaning, pool: pool, using: &rng)!
        #expect(q.prompt == "invoice")
        #expect(q.choices.count == 4)
        #expect(q.choices[q.correctIndex] == "意味1")
        #expect(Set(q.choices) == ["意味1", "誤1", "誤2", "誤3"])
    }

    @Test("cloze: 例文が空欄化され、誤答は同 pos の他単語") func clozeFormat() {
        var rng = SeededRandomNumberGenerator(seed: 2)
        let q = WordQuestionFactory.make(pool[0], format: .cloze, pool: pool, using: &rng)!
        #expect(q.wordFormat == .cloze)
        #expect(q.prompt == "Please check the ______ now.")
        #expect(q.choices[q.correctIndex] == "invoice")
        #expect(!q.choices.contains("attend"))  // 動詞は混ざらない
        #expect(!q.choices.contains("budget"))  // 同 pos・同 level が3語以上あるので level 450 は使わない
    }

    @Test("jaToEn: 日本語の意味から英語を選ぶ") func jaToEnFormat() {
        var rng = SeededRandomNumberGenerator(seed: 3)
        let q = WordQuestionFactory.make(pool[0], format: .jaToEn, pool: pool, using: &rng)!
        #expect(q.prompt == "意味1")
        #expect(q.choices[q.correctIndex] == "invoice")
    }

    @Test("誤答抽出: 同 pos が3語未満なら level → pos の順に条件を外す") func distractorFallback() {
        var rng = SeededRandomNumberGenerator(seed: 4)
        // 動詞は2語しかない → 全体から3語
        let d = WordQuestionFactory.distractorWords(for: pool[5], pool: pool, using: &rng)
        #expect(d.count == 3)
        #expect(!d.contains { $0.id == "6" })
        // 前置詞は1語 → 全体から3語
        let d2 = WordQuestionFactory.distractorWords(for: pool[7], pool: pool, using: &rng)
        #expect(d2.count == 3)
    }

    @Test("cloze が作れない語は meaning にフォールバック") func clozeFallback() {
        var rng = SeededRandomNumberGenerator(seed: 5)
        var w = pool[0]
        w.example = "This sentence has no target word."
        let q = WordQuestionFactory.make(w, format: .cloze, pool: pool, using: &rng)!
        #expect(q.wordFormat == .meaning)
    }

    @Test("ランダム形式は語ごとに決まる") func randomFormat() {
        var rng = SeededRandomNumberGenerator(seed: 6)
        let qs = SetBuilder.wordQuestions(pool, format: nil, pool: pool, using: &rng)
        #expect(qs.count == pool.count)
        #expect(Set(qs.compactMap(\.wordFormat)).count > 1)
    }
}

@Suite("例文 3 つの使い分け")
struct MultiExampleTests {
    private func word() -> WordSnapshot {
        WordSnapshot(id: "w-m", word: "invoice", pos: "名詞", meaning: "請求書",
                     examples: [.init(en: "Please pay the invoice within 30 days.", ja: "30 日以内に請求書をお支払いください。"),
                                .init(en: "The invoice was sent yesterday.", ja: "請求書は昨日送られました。"),
                                .init(en: "No target word here.", ja: "対象語なし")],
                     distractors: ["領収書", "見積書", "契約書"], category: "ビジネス一般", level: 450)
    }

    @Test("穴埋めは空欄にできる文だけから選び、解説用の例文と和訳を運ぶ") func clozePicksFillable() {
        let w = word()
        var rng = SystemRandomNumberGenerator()
        var seen = Set<String>()
        for _ in 0..<40 {
            let q = WordQuestionFactory.make(w, format: .cloze, pool: [w], using: &rng)
            // 誤答が足りないので meaning にフォールバックするが、例文の選び方は pickExample で確認する
            #expect(q != nil)
            if let ex = WordQuestionFactory.pickExample(w, forCloze: true, using: &rng) { seen.insert(ex.en) }
        }
        #expect(seen == ["Please pay the invoice within 30 days.", "The invoice was sent yesterday."])
    }

    @Test("meaning / jaToEn は 3 つのどれかを例文として運び、読み上げも同じ文") func meaningCarriesExample() {
        let w = word()
        var rng = SystemRandomNumberGenerator()
        let q = WordQuestionFactory.make(w, format: .meaning, pool: [w], using: &rng)!
        let ex = q.example!
        #expect(w.examples.contains(ex))
        #expect(q.speechText == ex.en)
        #expect(q.promptJa == nil)
    }
}
