import Foundation
import Observation

/// 進行中の1セット
@MainActor
@Observable
final class QuizRun {
    struct Answer: Hashable, Sendable {
        var question: QuizQuestion
        var chosenIndex: Int
        var elapsedMs: Int
        var isCorrect: Bool { chosenIndex == question.correctIndex }
    }

    let config: QuizConfig
    let questions: [QuizQuestion]
    let startedAt: Date
    private(set) var answers: [Answer] = []
    private(set) var index = 0
    private(set) var shownAt: Date

    init(config: QuizConfig, questions: [QuizQuestion], now: Date = .now) {
        self.config = config
        self.questions = questions
        startedAt = now
        shownAt = now
    }

    var current: QuizQuestion { questions[min(index, questions.count - 1)] }
    var currentAnswer: Answer? { answers.indices.contains(index) ? answers[index] : nil }
    var isAnswered: Bool { currentAnswer != nil }
    var isLast: Bool { index == questions.count - 1 }
    var isFinished: Bool { answers.count == questions.count }
    var correctCount: Int { answers.filter(\.isCorrect).count }
    var wrongAnswers: [Answer] { answers.filter { !$0.isCorrect } }

    /// 回答を確定。すでに回答済みなら無視
    @discardableResult
    func answer(_ chosen: Int, now: Date = .now) -> Answer? {
        guard !isAnswered, questions.indices.contains(index) else { return nil }
        let elapsed = Int(now.timeIntervalSince(shownAt) * 1000)
        let a = Answer(question: current, chosenIndex: chosen, elapsedMs: elapsed)
        answers.append(a)
        return a
    }

    func next(now: Date = .now) {
        guard isAnswered, !isLast else { return }
        index += 1
        shownAt = now
    }
}
