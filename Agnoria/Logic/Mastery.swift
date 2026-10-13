import Foundation

/// 1問の習得段階（§4.6 [v1.2]）。Priority の判定をそのまま4段階に写す
nonisolated enum Mastery: CaseIterable, Hashable, Sendable {
    case unseen       // 未学習
    case struggling   // 苦手: 直近3回に不正解あり
    case learning     // 学習中: 回答済みで不正解なし、まだ3回連続正解に届かない
    case mastered     // 習得: 直近3回すべて正解

    var title: String {
        switch self {
        case .unseen: "未学習"
        case .struggling: "苦手"
        case .learning: "学習中"
        case .mastered: "習得"
        }
    }

    static func of(_ p: ProgressSnapshot?) -> Mastery {
        guard let p, !p.recentResults.isEmpty else { return .unseen }
        if Priority.hasRecentMistake(p.recentResults) { return .struggling }
        if Priority.isGraduated(p.recentResults) { return .mastered }
        return .learning
    }
}

/// 集計結果。ホームのカード・タイル・進捗画面で共用
nonisolated struct MasterySummary: Hashable, Sendable {
    var counts: [Mastery: Int] = [:]
    var answered: Int = 0        // 累計回答数
    var correct: Int = 0         // 累計正解数
    var dueForReview: Int = 0    // 習得後 7 日以上経過（復習のころあい）

    var total: Int { Mastery.allCases.reduce(0) { $0 + (counts[$1] ?? 0) } }
    subscript(_ m: Mastery) -> Int { counts[m] ?? 0 }

    var masteredRatio: Double { total == 0 ? 0 : Double(self[.mastered]) / Double(total) }
    var masteredPercent: Int { Int((masteredRatio * 100).rounded()) }
    var accuracyPercent: Int? {
        answered == 0 ? nil : Int((Double(correct) / Double(answered) * 100).rounded())
    }

    mutating func add(_ p: ProgressSnapshot?, now: Date) {
        let m = Mastery.of(p)
        counts[m, default: 0] += 1
        guard let p else { return }
        answered += p.totalAnswered
        correct += p.totalCorrect
        if Priority.isDueForReview(p, now: now) { dueForReview += 1 }
    }

    static func + (a: MasterySummary, b: MasterySummary) -> MasterySummary {
        var out = a
        for (k, v) in b.counts { out.counts[k, default: 0] += v }
        out.answered += b.answered
        out.correct += b.correct
        out.dueForReview += b.dueForReview
        return out
    }
}

/// 1日分の学習量（進捗画面の棒グラフ用）
nonisolated struct DayStat: Hashable, Sendable, Identifiable {
    var date: Date
    var answered: Int
    var correct: Int
    var id: Date { date }
}

nonisolated enum MasteryStats {
    static func summarize(items: [(id: String, category: String)],
                          progress: [String: ProgressSnapshot], now: Date = .now) -> MasterySummary {
        items.reduce(into: MasterySummary()) { $0.add(progress[$1.id], now: now) }
    }

    static func byCategory(items: [(id: String, category: String)],
                           progress: [String: ProgressSnapshot], now: Date = .now) -> [String: MasterySummary] {
        var out: [String: MasterySummary] = [:]
        for item in items {
            var s = out[item.category] ?? MasterySummary()
            s.add(progress[item.id], now: now)
            out[item.category] = s
        }
        return out
    }

    /// 直近 days 日分（今日を含む、古い順）。セットの無い日は 0 で埋める
    static func daily(sessions: [(finishedAt: Date, results: [SessionResult])], days: Int = 14,
                      today: Date = .now, calendar: Calendar = .current) -> [DayStat] {
        let todayStart = calendar.startOfDay(for: today)
        var byDay: [Date: (answered: Int, correct: Int)] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.finishedAt)
            var acc = byDay[day] ?? (0, 0)
            acc.answered += s.results.count
            acc.correct += s.results.filter(\.isCorrect).count
            byDay[day] = acc
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let v = byDay[day] ?? (0, 0)
            return DayStat(date: day, answered: v.answered, correct: v.correct)
        }
    }

    static func wrongCount(itemIDs: [String], progress: [String: ProgressSnapshot]) -> Int {
        itemIDs.filter { Priority.hasRecentMistake(progress[$0]?.recentResults ?? []) }.count
    }

    static func bookmarkCount(itemIDs: [String], progress: [String: ProgressSnapshot]) -> Int {
        itemIDs.filter { progress[$0]?.isBookmarked ?? false }.count
    }
}
