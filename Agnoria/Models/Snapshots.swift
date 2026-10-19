import Foundation

/// バンドル JSON の 1 要素 / SwiftData から切り出した値型。actor 間を安全に渡せる
nonisolated struct WordSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var word: String
    var pos: String
    var meaning: String
    var example: String
    var exampleJa: String
    var distractors: [String]
    var category: String
    var level: Int

    enum CodingKeys: String, CodingKey {
        case id, word, pos, meaning, example, distractors, category, level
        case exampleJa = "example_ja"
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
