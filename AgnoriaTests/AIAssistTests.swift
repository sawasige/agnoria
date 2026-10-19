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
                             distractors: ["a", "b", "c"], category: "ビジネス一般", level: 450)
        let q = try #require(await AIAssist.practiceCloze(for: w))
        #expect(q.isPractice)
        #expect(q.prompt.contains(Cloze.blank))
        #expect(q.completedPrompt.lowercased().contains("invoice"))
        let ja = try #require(q.promptJa)
        #expect(!ja.isEmpty)
        #expect(ja.unicodeScalars.contains { $0.value >= 0x3040 })   // 日本語が含まれる
        print("類題: \(q.completedPrompt) / \(ja)")
    }
}
