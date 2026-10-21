import Foundation
import Testing
@testable import Agnoria

@Suite("リスニング（応答問題）")
struct ListeningTests {
    private let snapshot = ListeningSnapshot(
        id: "lis-wh-001", category: "WH 疑問文", question: "When is the sales report due?", questionJa: "売上報告書の締め切りはいつですか。",
        choices: ["By Friday afternoon.", "Yes, it's on sale.", "In the conference room."],
        choicesJa: ["金曜の午後までです。", "はい、セール中です。", "会議室です。"],
        answer: 0, explanation: "When で時を尋ねている。", level: 450)

    @Test("応答をシャッフルしても和訳と正解は同じ応答に付いてくる") func shuffleKeepsTranslations() {
        for seed in 1...20 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let q = ListeningQuestionFactory.make(snapshot, using: &rng)
            #expect(q.mode == .listening && q.isListening)
            #expect(q.choices.count == 3 && q.choicesJa?.count == 3)
            #expect(q.choices[q.correctIndex] == "By Friday afternoon.")
            #expect(q.promptJa == "売上報告書の締め切りはいつですか。")
            #expect(q.speechText == nil, "読み上げボタンではなく ListeningPlayer で再生する")
            for (en, ja) in zip(q.choices, q.choicesJa ?? []) {
                let i = snapshot.choices.firstIndex(of: en)!
                #expect(snapshot.choicesJa[i] == ja)
            }
        }
    }

    @Test("おまかせには入らず、分野画面のリスニングだけで出る") func autoExcludesListening() {
        #expect(DrillMode.autoModes == [.word, .grammar])
        #expect(DrillMode.allCases.contains(.listening))
        let all = [
            SetBuilder.Candidate(id: "w", mode: .word, category: "ビジネス一般", level: 450, progress: nil),
            SetBuilder.Candidate(id: "l", mode: .listening, category: "WH 疑問文", level: 450, progress: nil),
        ]
        let listeningOnly = SetBuilder.eligible(all, config: QuizConfig(mode: .listening, category: nil, format: nil),
                                                enabledLevels: SetBuilder.allLevels)
        #expect(listeningOnly.map(\.id) == ["l"])
        #expect(SetBuilder.allLevels[.listening] == Level.allValues)
    }

    @Test("台本: 番号 → 問いかけ → 記号と応答 3 つ。番号と記号はナレーター、間は仕様どおり") func script() throws {
        let s = ListeningScript.make(number: 10, question: "When is it due?", choices: ["Friday.", "Yes.", "Here."])
        #expect(s.count == 8)
        #expect(s.map(\.text) == ["Number 10.", "When is it due?", "A.", "Friday.", "B.", "Yes.", "C.", "Here."])
        #expect(s.map(\.role) == [.narrator, .speaker, .narrator, .speaker, .narrator, .speaker, .narrator, .speaker])
        #expect(s.map(\.part) == [.number, .question, .response(0), .response(0), .response(1), .response(1), .response(2), .response(2)])
        #expect(s.map(\.pauseAfter) == [ListeningScript.pauseAfterNumber, ListeningScript.pauseAfterQuestion,
                                        ListeningScript.pauseAfterLetter, ListeningScript.pauseBetweenResponses,
                                        ListeningScript.pauseAfterLetter, ListeningScript.pauseBetweenResponses,
                                        ListeningScript.pauseAfterLetter, 0])
        #expect(ListeningScript.pauseAfterQuestion >= 1 && ListeningScript.pauseBetweenResponses >= 1, "本番並みの間")
    }

    @Test("分野の記号とタイトル") func categories() {

        #expect(DrillMode.listening.categories.count == 5)
        #expect(DrillMode.symbol(for: "WH 疑問文") == "questionmark.bubble")
        #expect(DrillMode.listening.title == "リスニング")
    }
}

@Suite("リスニングの声の選び方")
struct ListeningVoiceTests {
    private func voice(_ id: String, _ lang: String, quality: Int = 1, gender: Int = 0) -> ListeningVoice.Candidate {
        ListeningVoice.Candidate(identifier: id, language: lang, quality: quality, gender: gender)
    }

    @Test("同じ問題は毎回同じ声、問いかけと応答は別の声") func deterministicAndDistinct() throws {
        let voices = [voice("us-f", "en-US", quality: 1, gender: 2), voice("us-m", "en-US", quality: 1, gender: 1),
                      voice("gb-f", "en-GB", quality: 2, gender: 2), voice("gb-m", "en-GB", quality: 1, gender: 1),
                      voice("au-f", "en-AU", quality: 1, gender: 2)]
        let a = try #require(ListeningVoice.pick(seed: "lis-wh-001", available: voices))
        let b = try #require(ListeningVoice.pick(seed: "lis-wh-001", available: voices))
        #expect(a == b)
        #expect(a.question != a.responses)
        // 問題が変われば言語も散らばる
        let langs = Set((1...30).compactMap { i -> String? in
            guard let p = ListeningVoice.pick(seed: "lis-\(i)", available: voices) else { return nil }
            return voices.first { $0.identifier == p.question }?.language
        })
        #expect(langs.count == 3, "\(langs)")
    }

    @Test("品質の高い声を優先し、同じ言語に別の性別が無ければ別の言語から応答の声を選ぶ") func qualityAndFallback() throws {
        let voices = [voice("us-compact", "en-US", quality: 1, gender: 2), voice("us-premium", "en-US", quality: 3, gender: 2),
                      voice("gb", "en-GB", quality: 1, gender: 2)]
        // en-US が選ばれる seed を探す
        let seed = try #require((1...50).map { "s\($0)" }.first { s in
            guard let p = ListeningVoice.pick(seed: s, available: voices) else { return false }
            return p.question.hasPrefix("us")
        })
        let p = try #require(ListeningVoice.pick(seed: seed, available: voices))
        #expect(p.question == "us-premium")
        #expect(p.responses == "gb")
    }

    @Test("英語の声が 1 つしか無ければ両方同じ声、無ければ nil") func degenerate() {
        let one = ListeningVoice.pick(seed: "x", available: [voice("only", "en-US")])
        #expect(one == ListeningVoice.Pick(question: "only", responses: "only"))
        let foreign = ListeningVoice.pick(seed: "x", available: [voice("ja", "ja-JP")])
        #expect(foreign == ListeningVoice.Pick(question: "ja", responses: "ja"))
        #expect(ListeningVoice.pick(seed: "x", available: []) == nil)
    }
}
