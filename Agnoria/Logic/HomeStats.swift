import Foundation

/// ホームのタイルに出す集計
struct CategoryStats: Hashable, Sendable {
    var total: Int = 0
    var graduated: Int = 0
    var answered: Int = 0
    var correct: Int = 0

    var accuracyPercent: Int? {
        answered == 0 ? nil : Int((Double(correct) / Double(answered) * 100).rounded())
    }
}

enum HomeStats {
    static func byCategory(items: [(id: String, category: String)],
                           progress: [String: ProgressSnapshot]) -> [String: CategoryStats] {
        var out: [String: CategoryStats] = [:]
        for item in items {
            var s = out[item.category] ?? CategoryStats()
            s.total += 1
            if let p = progress[item.id] {
                s.answered += p.totalAnswered
                s.correct += p.totalCorrect
                if Priority.isGraduated(p.recentResults) { s.graduated += 1 }
            }
            out[item.category] = s
        }
        return out
    }

    static func overall(_ stats: [String: CategoryStats]) -> CategoryStats {
        stats.values.reduce(into: CategoryStats()) { acc, s in
            acc.total += s.total; acc.graduated += s.graduated
            acc.answered += s.answered; acc.correct += s.correct
        }
    }

    static func wrongCount(itemIDs: [String], progress: [String: ProgressSnapshot]) -> Int {
        itemIDs.filter { Priority.hasRecentMistake(progress[$0]?.recentResults ?? []) }.count
    }

    static func bookmarkCount(itemIDs: [String], progress: [String: ProgressSnapshot]) -> Int {
        itemIDs.filter { progress[$0]?.isBookmarked ?? false }.count
    }
}
