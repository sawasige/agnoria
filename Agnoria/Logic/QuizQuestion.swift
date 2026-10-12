import Foundation

/// 画面に出す1問。値型。SwiftData には依存しない
struct QuizQuestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let itemID: String
    let mode: DrillMode
    let wordFormat: WordFormat?
    let categoryName: String
    let prompt: String
    let choices: [String]
    let correctIndex: Int
    /// 文法: explanation / 単語: 意味（例文は word から）
    let explanation: String
    let word: WordSnapshot?
    /// 読み上げる英文（例文）。無ければ nil
    let speechText: String?
    /// Foundation Models で生成した練習問題。履歴に記録しない
    var isPractice: Bool = false

    init(itemID: String, mode: DrillMode, wordFormat: WordFormat?, categoryName: String,
         prompt: String, choices: [String], correctIndex: Int, explanation: String,
         word: WordSnapshot?, speechText: String?, isPractice: Bool = false) {
        id = UUID()
        self.itemID = itemID
        self.mode = mode
        self.wordFormat = wordFormat
        self.categoryName = categoryName
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.word = word
        self.speechText = speechText
        self.isPractice = isPractice
    }

    static let choiceLabels = ["A", "B", "C", "D"]
}

enum GrammarQuestionFactory {
    static func make(_ g: GrammarSnapshot, using rng: inout some RandomNumberGenerator) -> QuizQuestion {
        let (choices, correct) = ChoiceShuffler.shuffle(g.choices, correctIndex: g.answer, using: &rng)
        return QuizQuestion(itemID: g.id, mode: .grammar, wordFormat: nil, categoryName: g.category,
                            prompt: g.question, choices: choices, correctIndex: correct,
                            explanation: g.explanation, word: nil,
                            speechText: g.question.replacingOccurrences(of: Cloze.blank, with: g.choices[g.answer]))
    }
}

enum WordQuestionFactory {
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

    /// 形式に応じて1問を作る。cloze が作れない語は meaning にフォールバック
    static func make(_ w: WordSnapshot, format: WordFormat, pool: [WordSnapshot],
                     using rng: inout some RandomNumberGenerator) -> QuizQuestion? {
        switch format {
        case .meaning:
            guard w.distractors.count >= 3 else { return nil }
            let (choices, correct) = ChoiceShuffler.shuffle([w.meaning] + Array(w.distractors.prefix(3)),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .meaning, categoryName: w.category,
                                prompt: w.word, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, speechText: w.example)
        case .cloze:
            guard let blanked = Cloze.fill(w.example, word: w.word) else {
                return make(w, format: .meaning, pool: pool, using: &rng)
            }
            let others = distractorWords(for: w, pool: pool, using: &rng)
            guard others.count == 3 else { return make(w, format: .meaning, pool: pool, using: &rng) }
            let (choices, correct) = ChoiceShuffler.shuffle([w.word] + others.map(\.word),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .cloze, categoryName: w.category,
                                prompt: blanked, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, speechText: w.example)
        case .jaToEn:
            let others = distractorWords(for: w, pool: pool, using: &rng)
            guard others.count == 3 else { return make(w, format: .meaning, pool: pool, using: &rng) }
            let (choices, correct) = ChoiceShuffler.shuffle([w.word] + others.map(\.word),
                                                            correctIndex: 0, using: &rng)
            return QuizQuestion(itemID: w.id, mode: .word, wordFormat: .jaToEn, categoryName: w.category,
                                prompt: w.meaning, choices: choices, correctIndex: correct,
                                explanation: w.meaning, word: w, speechText: w.example)
        }
    }
}
