import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Foundation Models（§5）。非対応端末では isAvailable == false になり UI を出さない。
/// 失敗・タイムアウト時は nil を返し、呼び出し側はボタンを静かに消す。
enum AIAssist {
    nonisolated static let timeout: Duration = .seconds(5)

    /// 学習者像の表現。商標名はアプリ内文字列に含めない（§0 / §10）
    private nonisolated static let learnerProfile = "ビジネス英語を学び始めた初中級（スコア帯450点前後）の日本語話者"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// 解説の言い換え。保存しない
    static func rephrase(explanation: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        return await withTimeout {
            let session = LanguageModelSession(instructions: """
                あなたは英語講師です。\(learnerProfile)向けに、与えられた文法・語彙の解説を
                日本語で2文以内に言い換えてください。専門用語は避け、前置きや箇条書きは不要です。
                """)
            let response = try await session.respond(to: explanation)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #else
        return nil
        #endif
    }

    /// 単語 cloze の類題を1問生成。練習用で履歴には記録しない
    static func practiceCloze(for word: WordSnapshot) async -> QuizQuestion? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let generated: PracticeCloze? = await withTimeout {
            let session = LanguageModelSession(instructions: """
                あなたは英語教材の作成者です。\(learnerProfile)向けに、ビジネス場面の英語の例文を1文作ります。
                例文には対象の単語をちょうど1回含め、対象の単語の部分だけを ______ （アンダースコア6つ）にしてください。
                誤答の選択肢は、品詞が同じで意味が異なる一般的な英単語を3語、対象の単語と重複しないように挙げてください。
                誤答は、その例文の空欄に入れると意味が通らない語だけにしてください（類義語や同じ文脈で自然に使える語は避ける）。
                """)
            let prompt = "対象の単語: \(word.word) / 品詞: \(word.pos) / 意味: \(word.meaning)"
            return try await session.respond(to: prompt, generating: PracticeCloze.self).content
        }
        guard let g = generated, g.sentence.contains(Cloze.blank) else { return nil }
        let distractors = Array(Set(g.distractors.map { $0.trimmingCharacters(in: .whitespaces) })
            .filter { !$0.isEmpty && $0.lowercased() != word.word.lowercased() }
            .prefix(3))
        guard distractors.count == 3 else { return nil }
        var rng = SystemRandomNumberGenerator()
        let (choices, correct) = ChoiceShuffler.shuffle([word.word] + distractors, correctIndex: 0, using: &rng)
        return QuizQuestion(itemID: word.id, mode: .word, wordFormat: .cloze, categoryName: "練習用",
                            prompt: g.sentence, choices: choices, correctIndex: correct,
                            explanation: word.meaning, word: word,
                            speechText: g.sentence.replacingOccurrences(of: Cloze.blank, with: word.word),
                            isPractice: true)
        #else
        return nil
        #endif
    }

    /// 5秒で諦める。例外もすべて nil に落とす
    private static func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

#if canImport(FoundationModels)
@Generable
struct PracticeCloze {
    @Guide(description: "対象の単語を ______ に置き換えた英語の例文1文。8〜16語")
    var sentence: String
    @Guide(description: "誤答となる英単語3語。対象の単語と同じ品詞で意味が異なるもの", .count(3))
    var distractors: [String]
}
#endif
