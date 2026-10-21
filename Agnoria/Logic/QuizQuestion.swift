import Foundation

/// 画面に出す1問。値型。SwiftData には依存しない
nonisolated struct QuizQuestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let itemID: String
    let mode: DrillMode
    let wordFormat: WordFormat?
    let categoryName: String
    let prompt: String
    /// 空欄を正解で埋めた prompt の和訳 [v1.7]。文法問題・単語の穴埋め・練習問題で持つ
    let promptJa: String?
    /// 単語問題でこの問題に使った例文（3 つのうちの 1 つ）[v1.7]。解説と読み上げに使う
    let example: ExampleSentence?
    let choices: [String]
    /// リスニングの応答の和訳（choices と同じ順）[v1.9]。他は nil
    let choicesJa: [String]?
    let correctIndex: Int
    /// 文法: explanation / 単語: 意味（例文は word から）
    let explanation: String
    let word: WordSnapshot?
    /// 読み上げる英文（例文）。無ければ nil
    let speechText: String?
    /// Foundation Models で生成した練習問題。履歴に記録しない
    var isPractice: Bool = false

    init(itemID: String, mode: DrillMode, wordFormat: WordFormat?, categoryName: String,
         prompt: String, promptJa: String? = nil, choices: [String], choicesJa: [String]? = nil, correctIndex: Int,
         explanation: String, word: WordSnapshot?, example: ExampleSentence? = nil, speechText: String?,
         isPractice: Bool = false) {
        id = UUID()
        self.itemID = itemID
        self.mode = mode
        self.wordFormat = wordFormat
        self.categoryName = categoryName
        self.prompt = prompt
        self.promptJa = promptJa
        self.choices = choices
        self.choicesJa = choicesJa
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.word = word
        self.example = example
        self.speechText = speechText
        self.isPractice = isPractice
    }

    static let choiceLabels = ["A", "B", "C", "D"]

    /// 空欄（______）を正解で埋めた英文。空欄が無ければ prompt のまま
    var completedPrompt: String { prompt.replacingOccurrences(of: Cloze.blank, with: choices[correctIndex]) }

    /// リスニング: 問いかけと応答を音声だけで出し、回答まで文字を見せない（§4.2 [v1.9]）
    var isListening: Bool { mode == .listening }
}

/// リスニング（応答問題）の 1 問 [v1.9]。応答の並びをシャッフルし、和訳も同じ順に並べ替える
nonisolated enum ListeningQuestionFactory {
    static func make(_ l: ListeningSnapshot, using rng: inout some RandomNumberGenerator) -> QuizQuestion {
        let (choices, correct) = ChoiceShuffler.shuffle(l.choices, correctIndex: l.answer, using: &rng)
        let order = choices.map { c in l.choices.firstIndex(of: c) ?? 0 }
        let ja = order.map { l.choicesJa.indices.contains($0) ? l.choicesJa[$0] : "" }
        return QuizQuestion(itemID: l.id, mode: .listening, wordFormat: nil, categoryName: l.category,
                            prompt: l.question, promptJa: l.questionJa, choices: choices, choicesJa: ja,
                            correctIndex: correct, explanation: l.explanation, word: nil, speechText: nil)
    }
}


nonisolated enum GrammarQuestionFactory {
    static func make(_ g: GrammarSnapshot, using rng: inout some RandomNumberGenerator) -> QuizQuestion {
        let (choices, correct) = ChoiceShuffler.shuffle(g.choices, correctIndex: g.answer, using: &rng)
        return QuizQuestion(itemID: g.id, mode: .grammar, wordFormat: nil, categoryName: g.category,
                            prompt: g.question, promptJa: g.questionJa, choices: choices, correctIndex: correct,
                            explanation: g.explanation, word: nil,
                            speechText: g.question.replacingOccurrences(of: Cloze.blank, with: g.choices[g.answer]))
    }
}

nonisolated enum WordQuestionFactory {
    /// 誤答用の他単語3語。同 pos・同 level → 同 pos → 全体 の順で条件を緩める
    static func distractorWords(for w: WordSnapshot, pool: [WordSnapshot],
                                using rng: inout some RandomNumberGenerator) -> [WordSnapshot] {
        let others = pool.filter { $0.id != w.id && $0.word.lowercased() != w.word.lowercased()
            && $0.meaning != w.meaning }
        let tiers: [[WordSnapshot]] = [
            others.filter { $0.pos == w.pos && $0.level == w.level },
            others.filter { $0.pos == w.pos },
            others,
        ]
        for tier in tiers where tier.count >= 3 {
            return Array(tier.shuffled(using: &rng).prefix(3))
        }
        return Array(others.shuffled(using: &rng).prefix(3))
    }

    /// 例文 3 つから 1 つを選ぶ（§3.2 [v1.7]）。穴埋めは空欄にできる文だけが候補
    static func pickExample(_ w: WordSnapshot, forCloze: Bool, using rng: inout some RandomNumberGenerator) -> ExampleSentence? {
        let candidates = w.examples.filter { !$0.en.isEmpty && (!forCloze || Cloze.fill($0.en, word: w.word) != nil) }
        return candidates.randomElement(using: &rng)
    }

    /// 形式に応じて1問を作る。cloze が作れない語は meaning にフォールバック
    static func make(_ w: WordSnapshot, format: WordFormat, pool: [WordSnapshot],
                     using rng: inout some RandomNumberGenerator) -> QuizQuestion? {
        switch format {
        case .meaning:
            guard w.distractors.count >= 3 else { return nil }
            let ex = pickExample(w, forCloze: false, using: &rng)
            let (choices, correct) = ChoiceShuffler.shuffle([w.meaning] + Array(w.distractors.prefix(3)),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .meaning, categoryName: w.category,
                                prompt: w.word, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, example: ex, speechText: ex?.en)
        case .cloze:
            guard let ex = pickExample(w, forCloze: true, using: &rng),
                  let blanked = Cloze.fill(ex.en, word: w.word) else {
                return make(w, format: .meaning, pool: pool, using: &rng)
            }
            let others = distractorWords(for: w, pool: pool, using: &rng)
            guard others.count == 3 else { return make(w, format: .meaning, pool: pool, using: &rng) }
            let (choices, correct) = ChoiceShuffler.shuffle([w.word] + others.map(\.word),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .cloze, categoryName: w.category,
                                prompt: blanked, promptJa: ex.ja, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, example: ex, speechText: ex.en)
        case .jaToEn:
            let others = distractorWords(for: w, pool: pool, using: &rng)
            guard others.count == 3 else { return make(w, format: .meaning, pool: pool, using: &rng) }
            let ex = pickExample(w, forCloze: false, using: &rng)
            let (choices, correct) = ChoiceShuffler.shuffle([w.word] + others.map(\.word),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .jaToEn, categoryName: w.category,
                                prompt: w.meaning, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, example: ex, speechText: ex?.en)
        }
    }
}
