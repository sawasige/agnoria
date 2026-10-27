import Foundation
import Testing
@testable import Agnoria

/// Apple Intelligence が使える環境（Mac など）でだけ動く。シミュレータでは skip
@Suite("Foundation Models の類題")
struct AIAssistTests {
    @Test("類題は生成文の和訳を持ち、空欄を正解で埋めた英文を作れる")
    @MainActor func practiceClozeHasTranslation() async throws {
        guard AIAssist.isAvailable else { return }   // 非対応環境では何もしない
        let w = WordSnapshot(id: "w-test", word: "invoice", pos: "名", meaning: "請求書",
                             example: "Please pay the invoice within 30 days.", exampleJa: "30日以内に請求書をお支払いください。",
                             distractors: ["a", "b", "c"], category: "ビジネス一般", level: 450,
                             enDistractors: ["candidate", "discount", "interview"])
        let q = try #require(await AIAssist.practiceCloze(for: w))
        #expect(q.isPractice)
        #expect(q.prompt.contains(Cloze.blank))
        #expect(q.completedPrompt.lowercased().contains("invoice"))
        let ja = try #require(q.promptJa)
        #expect(!ja.isEmpty)
        #expect(ja.unicodeScalars.contains { $0.value >= 0x3040 })   // 日本語が含まれる
        #expect(Set(q.choices) == ["invoice", "candidate", "discount", "interview"])   // 誤答は人手の原形
    }

    @Test("類題は、単語を活用させて書いた文を出さず、文頭の空欄では選択肢を大文字にする")
    func practiceSentenceForm() throws {
        let d = ["attend", "explain", "retire"]
        let p = try #require(AIAssist.practiceSentence("We ship orders to customers every day.", word: "ship", distractors: d))
        #expect(p.prompt == "We \(Cloze.blank) orders to customers every day.")
        #expect(p.choices == ["ship", "attend", "explain", "retire"])
        // モデルが shipped と書いた → 原形の選択肢と合わないので出さない
        #expect(AIAssist.practiceSentence("Your items were shipped to you this morning.", word: "ship", distractors: d) == nil)
        // 文頭 → 大文字で始める
        let head = try #require(AIAssist.practiceSentence("Ship all the orders before noon on Friday.", word: "ship", distractors: d))
        #expect(head.prompt == "\(Cloze.blank) all the orders before noon on Friday.")
        #expect(head.choices == ["Ship", "Attend", "Explain", "Retire"])
        // 短い文は手がかりがないので出さない
        #expect(AIAssist.practiceSentence("This is my luggage.", word: "luggage", distractors: d) == nil)
        // Markdown の強調は外す
        #expect(AIAssist.practiceSentence("We need to **ship** more boxes to Osaka.", word: "ship", distractors: d)?.prompt
                == "We need to \(Cloze.blank) more boxes to Osaka.")
        // 和訳の後ろの記号は切る
        #expect(AIAssist.firstSentence("会議に出席します。」}<x> ") == "会議に出席します。")
    }
}
