import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Foundation Models（§5）。非対応端末では isAvailable == false になり UI を出さない。
/// 失敗・タイムアウト時は nil を返し、呼び出し側はボタンを静かに消す。
enum AIAssist {
    nonisolated static let timeout: Duration = .seconds(5)
    /// 類題は例文・和訳・誤答を構造化して作るので長くかかる。モデルの読み込みが乗る初回は Mac でも 5 秒を超えた
    nonisolated static let practiceTimeout: Duration = .seconds(15)

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

    #if canImport(FoundationModels)
    private nonisolated static let practiceInstructions = """
        あなたは英語教材の作成者です。\(learnerProfile)向けに、ビジネス場面の英語の例文を1文作ります。
        対象の単語を、与えられた意味で、文法的に正しく使ってください。
        例文は 10 語前後にし、その単語を隠しても場面から言い当てられる手がかり（誰が・何を・どこで）を入れてください。
        「This is my ...」のような、ほかの多くの語でも成り立つ短い文は避けてください。
        例文には対象の単語を、活用させずに与えられた形のままちょうど1回含めてください。
        例文の自然な日本語訳も付けてください。
        """
    #endif

    /// 類題のモデルを先に読み込んでおく。押してから読み込むと初回が遅い（§5 [v2.2]）
    static func prewarmPractice() {
        #if canImport(FoundationModels)
        guard isAvailable else { return }
        LanguageModelSession(instructions: practiceInstructions).prewarm()
        #endif
    }

    /// 単語 cloze の類題を1問生成。練習用で履歴には記録しない。
    /// 誤答は人手で選んだ原形（`en_distractors`）を使う。モデルに誤答を作らせると、ship に deliver、
    /// efficient に fast のような文脈に入る語を出しがちで、正解が 2 つになる（§5 [v2.2]）
    static func practiceCloze(for word: WordSnapshot) async -> QuizQuestion? {
        #if canImport(FoundationModels)
        guard isAvailable, let distractors = word.enDistractors, distractors.count == 3 else { return nil }
        let generated: PracticeCloze? = await withTimeout(practiceTimeout) {
            let session = LanguageModelSession(instructions: practiceInstructions)
            let prompt = "対象の単語: \(word.word) / 品詞: \(word.pos) / 意味: \(word.meaning)"
            // 和訳のあとに記号を書き続けて文脈の上限まで止まらないことがあるので、長さを切る
            return try await session.respond(to: prompt, generating: PracticeCloze.self,
                                             options: GenerationOptions(maximumResponseTokens: 200)).content
        }
        guard let g = generated,
              let practice = practiceSentence(g.sentence, word: word.word, distractors: distractors) else { return nil }
        let sentenceJa = firstSentence(g.sentenceJa)
        var rng = SystemRandomNumberGenerator()
        let (choices, correct) = ChoiceShuffler.shuffle(practice.choices, correctIndex: 0, using: &rng)
        return QuizQuestion(itemID: word.id, mode: .word, wordFormat: .cloze, categoryName: "練習用",
                            prompt: practice.prompt, promptJa: sentenceJa.isEmpty ? nil : sentenceJa,
                            choices: choices, correctIndex: correct,
                            explanation: word.meaning, word: word,
                            speechText: practice.prompt.replacingOccurrences(of: Cloze.blank, with: practice.choices[0]),
                            isPractice: true)
        #else
        return nil
        #endif
    }

    /// 生成した完全な英文から類題を作る（選択肢は先頭が正解）。空欄はアプリで作る:
    /// 単語と完全に一致する語だけを空欄にし、モデルが活用させて書いた（shipped）文は原形の選択肢と
    /// 空欄の形が合わないので出さない。文頭なら選択肢を大文字で始める（§3.1 の穴埋めと同じ）
    nonisolated static func practiceSentence(_ sentence: String, word: String, distractors: [String]) -> (prompt: String, choices: [String])? {
        // 単語を **ship** のように Markdown の強調で囲んで書くことがある
        let s = sentence.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 短い文（This is my luggage.）は手がかりがなく、誤答も入ってしまう
        guard s.split(separator: " ").count >= 7 else { return nil }
        let all = [word] + distractors
        if let prompt = Cloze.blankOut(s, token: word) { return (prompt, all) }
        let capital = { (w: String) in w.prefix(1).uppercased() + w.dropFirst() }
        if let prompt = Cloze.blankOut(s, token: capital(word)), prompt.hasPrefix(Cloze.blank) {
            return (prompt, all.map(capital))
        }
        return nil
    }

    /// 和訳は最初の「。」まで（後ろに記号が続くことがある）
    nonisolated static func firstSentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = t.firstIndex(of: "。") else { return t }
        return String(t[...end])
    }

    /// 決めた時間で諦める（既定 5 秒）。例外もすべて nil に落とす
    private static func withTimeout<T: Sendable>(_ limit: Duration = timeout, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
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
    @Guide(description: "対象の単語を与えられた形のまま1回含む英語の例文1文。8〜16語")
    var sentence: String
    @Guide(description: "例文の自然な日本語訳。1文")
    var sentenceJa: String
}
#endif
