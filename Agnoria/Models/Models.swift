import Foundation
import SwiftData

@Model
final class GrammarQuestion {
    @Attribute(.unique) var id: String
    var category: String
    var question: String
    var choices: [String]
    var answer: Int
    var explanation: String
    var level: Int
    var isArchived: Bool

    init(_ s: GrammarSnapshot) {
        id = s.id
        category = s.category
        question = s.question
        choices = s.choices
        answer = s.answer
        explanation = s.explanation
        level = s.level
        isArchived = false
    }

    func apply(_ s: GrammarSnapshot) {
        category = s.category
        question = s.question
        choices = s.choices
        answer = s.answer
        explanation = s.explanation
        level = s.level
        isArchived = false
    }

    var snapshot: GrammarSnapshot {
        GrammarSnapshot(id: id, category: category, question: question, choices: choices,
                        answer: answer, explanation: explanation, level: level)
    }
}

@Model
final class Word {
    @Attribute(.unique) var id: String
    var word: String
    var pos: String
    var meaning: String
    var example: String
    var exampleJa: String
    var distractors: [String]
    var category: String
    var level: Int
    var isArchived: Bool

    init(_ s: WordSnapshot) {
        id = s.id
        word = s.word
        pos = s.pos
        meaning = s.meaning
        example = s.example
        exampleJa = s.exampleJa
        distractors = s.distractors
        category = s.category
        level = s.level
        isArchived = false
    }

    func apply(_ s: WordSnapshot) {
        word = s.word
        pos = s.pos
        meaning = s.meaning
        example = s.example
        exampleJa = s.exampleJa
        distractors = s.distractors
        category = s.category
        level = s.level
        isArchived = false
    }

    var snapshot: WordSnapshot {
        WordSnapshot(id: id, word: word, pos: pos, meaning: meaning, example: example,
                     exampleJa: exampleJa, distractors: distractors, category: category, level: level)
    }
}

/// 学習履歴。問題の id（itemID）に紐づく独立したレコード。
/// 問題本文を更新・アーカイブしても履歴は残る。
@Model
final class ItemProgress {
    @Attribute(.unique) var itemID: String
    var recentResults: [Bool]     // 直近3回。古い順
    var totalCorrect: Int
    var totalAnswered: Int
    var isBookmarked: Bool
    var lastAnsweredAt: Date?

    init(itemID: String) {
        self.itemID = itemID
        recentResults = []
        totalCorrect = 0
        totalAnswered = 0
        isBookmarked = false
        lastAnsweredAt = nil
    }

    func record(isCorrect: Bool, at date: Date = .now) {
        recentResults.append(isCorrect)
        if recentResults.count > Priority.recentWindow {
            recentResults.removeFirst(recentResults.count - Priority.recentWindow)
        }
        totalAnswered += 1
        if isCorrect { totalCorrect += 1 }
        lastAnsweredAt = date
    }

    var snapshot: ProgressSnapshot {
        ProgressSnapshot(itemID: itemID, recentResults: recentResults, totalCorrect: totalCorrect,
                         totalAnswered: totalAnswered, isBookmarked: isBookmarked,
                         lastAnsweredAt: lastAnsweredAt)
    }
}

/// 1セット（10問）の記録。完走したセットのみ保存する（途中離脱は保存しない）
@Model
final class StudySession {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var mode: String            // DrillMode.rawValue。おまかせは "auto"
    var category: String?       // nil = ミックス
    var questionFormat: String? // 単語のとき WordFormat.rawValue。ランダムなら nil
    var results: [SessionResult]

    static let autoMode = "auto"

    init(startedAt: Date, finishedAt: Date, mode: DrillMode?, category: String?,
         questionFormat: WordFormat?, results: [SessionResult]) {
        id = UUID()
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode?.rawValue ?? Self.autoMode
        self.category = category
        self.questionFormat = questionFormat?.rawValue
        self.results = results
    }
}

nonisolated struct SessionResult: Codable, Hashable, Sendable {
    var itemID: String
    var isCorrect: Bool
    var chosenIndex: Int
    var elapsedMs: Int
}

nonisolated enum AgnoriaSchema {
    static let models: [any PersistentModel.Type] = [
        GrammarQuestion.self, Word.self, ItemProgress.self, StudySession.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: [config])
    }
}
