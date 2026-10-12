import Foundation

/// 10問セットの生成（§3.2）。入力はすべて値型なのでユニットテスト可能
enum SetBuilder {
    static let setSize = 10

    struct Candidate: Hashable, Sendable {
        var id: String
        var category: String
        var level: Int
        var progress: ProgressSnapshot?
    }

    /// 条件に合う候補に絞る
    static func eligible(_ all: [Candidate], config: QuizConfig, enabledLevels: Set<Int>) -> [Candidate] {
        all.filter { c in
            if let cat = config.category, c.category != cat { return false }
            if !enabledLevels.contains(c.level) { return false }
            if let only = config.restrictTo, !only.contains(c.id) { return false }
            switch config.filter {
            case .all: return true
            case .wrongOnly: return Priority.hasRecentMistake(c.progress?.recentResults ?? [])
            case .bookmarked: return c.progress?.isBookmarked ?? false
            }
        }
    }

    /// 優先度を重みにして最大 setSize 件を抽出
    static func pick(from candidates: [Candidate], count: Int = setSize,
                     using rng: inout some RandomNumberGenerator) -> [Candidate] {
        let weighted = candidates.map { c in
            (item: c, weight: Priority.score(recentResults: c.progress?.recentResults ?? []))
        }
        return WeightedSampler.sample(weighted, count: count, using: &rng)
    }

    /// 単語セットを QuizQuestion に変換。format が nil なら1問ごとにランダム
    static func wordQuestions(_ picked: [WordSnapshot], format: WordFormat?, pool: [WordSnapshot],
                              using rng: inout some RandomNumberGenerator) -> [QuizQuestion] {
        picked.compactMap { w in
            let f = format ?? (WordFormat.allCases.randomElement(using: &rng) ?? .meaning)
            return WordQuestionFactory.make(w, format: f, pool: pool, using: &rng)
        }
    }

    static func grammarQuestions(_ picked: [GrammarSnapshot],
                                 using rng: inout some RandomNumberGenerator) -> [QuizQuestion] {
        picked.map { GrammarQuestionFactory.make($0, using: &rng) }
    }
}
