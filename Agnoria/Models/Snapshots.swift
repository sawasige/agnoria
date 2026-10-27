import Foundation

/// 例文 1 つ（英文と和訳）[v1.7]
nonisolated struct ExampleSentence: Codable, Hashable, Sendable {
    var en: String
    var ja: String
    /// [v2.2] 穴埋めで空欄にする語（例文中の形のまま。shipped など）。無ければ `Cloze.fill` の推測に任せる
    var blank: String?
    /// [v2.2] 穴埋めの誤答 3 つ。`blank` と同じ活用形にそろえてある（packed / ordered / returned）
    var distractors: [String]?

    init(en: String, ja: String, blank: String? = nil, distractors: [String]? = nil) {
        self.en = en; self.ja = ja; self.blank = blank; self.distractors = distractors
    }
}

/// バンドル JSON の 1 要素 / SwiftData から切り出した値型。actor 間を安全に渡せる。
/// [v1.7] 例文は 1 語につき 3 つ（`examples`）。`example` / `exampleJa` は 1 つ目の別名
nonisolated struct WordSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var word: String
    var pos: String
    var meaning: String
    var examples: [ExampleSentence]
    var distractors: [String]
    var category: String
    var level: Int
    /// [v2.2] 日→英の誤答（英単語の原形 3 つ）。3 つの例文のどれにも入らない語を人手で選んである
    var enDistractors: [String]?

    var example: String {
        get { examples.first?.en ?? "" }
        set { if examples.isEmpty { examples = [ExampleSentence(en: newValue, ja: "")] } else { examples[0].en = newValue } }
    }
    var exampleJa: String {
        get { examples.first?.ja ?? "" }
        set { if examples.isEmpty { examples = [ExampleSentence(en: "", ja: newValue)] } else { examples[0].ja = newValue } }
    }

    init(id: String, word: String, pos: String, meaning: String, examples: [ExampleSentence],
         distractors: [String], category: String, level: Int, enDistractors: [String]? = nil) {
        self.id = id; self.word = word; self.pos = pos; self.meaning = meaning; self.examples = examples
        self.distractors = distractors; self.category = category; self.level = level; self.enDistractors = enDistractors
    }

    /// 例文 1 つで作る（テストと旧データ用）
    init(id: String, word: String, pos: String, meaning: String, example: String, exampleJa: String,
         distractors: [String], category: String, level: Int, enDistractors: [String]? = nil) {
        self.init(id: id, word: word, pos: pos, meaning: meaning, examples: [ExampleSentence(en: example, ja: exampleJa)],
                  distractors: distractors, category: category, level: level, enDistractors: enDistractors)
    }

    enum CodingKeys: String, CodingKey {
        case id, word, pos, meaning, examples, distractors, category, level
        case enDistractors = "en_distractors"
    }
}

nonisolated struct GrammarSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var category: String
    var question: String
    /// 空欄を正解で埋めた文の和訳 [v1.7]
    var questionJa: String
    var choices: [String]
    var answer: Int
    var explanation: String
    var level: Int

    enum CodingKeys: String, CodingKey {
        case id, category, question, choices, answer, explanation, level
        case questionJa = "question_ja"
    }
}

/// リスニング（Part 2 形式の応答問題）の 1 問 [v1.9]。問いかけ 1 文と応答 3 つ。音声は端末の合成音声で作る
nonisolated struct ListeningSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var category: String
    var question: String
    var questionJa: String
    var choices: [String]
    var choicesJa: [String]
    var answer: Int
    var explanation: String
    var level: Int

    enum CodingKeys: String, CodingKey {
        case id, category, question, choices, answer, explanation, level
        case questionJa = "question_ja"
        case choicesJa = "choices_ja"
    }
}

nonisolated struct ProgressSnapshot: Hashable, Sendable {

    var itemID: String
    var recentResults: [Bool] = []
    var totalCorrect: Int = 0
    var totalAnswered: Int = 0
    var isBookmarked: Bool = false
    var lastAnsweredAt: Date? = nil
    var masteredAt: Date? = nil

    /// 過去に一度でも習得したか [v1.4]
    var wasMastered: Bool { masteredAt != nil }
}
