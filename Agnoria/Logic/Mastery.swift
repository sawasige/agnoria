import Foundation

/// 1問の習得段階（§4.6 [v1.2]）。Priority の判定をそのまま4段階に写す
nonisolated enum Mastery: CaseIterable, Hashable, Sendable {
    case unseen       // 未学習
    case struggling   // 苦手: 直近3回に不正解あり（一度も習得していない問題）
    case learning     // 学習中: 回答済みで不正解なし、まだ3回連続正解に届かない。または習得済みだったが直近で間違えた [v1.4]
    case mastered     // 習得: 直近3回すべて正解、または 過去に習得済みで直近が正解 [v1.4]

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
        if Priority.isGraduated(p) { return .mastered }
        if Priority.hasRecentMistake(p.recentResults) { return p.wasMastered ? .learning : .struggling }
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

    static func byLevel(items: [(id: String, level: Int)],
                        progress: [String: ProgressSnapshot], now: Date = .now) -> [Int: MasterySummary] {
        var out: [Int: MasterySummary] = [:]
        for item in items {
            var s = out[item.level] ?? MasterySummary()
            s.add(progress[item.id], now: now)
            out[item.level] = s
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

    /// 今日・今週・先週に新しく習得した問題の数（§4.1 / §4.6 [v2.4]）。`masteredAt`（はじめて習得した日時）で数えるので、
    /// 学習中に戻って再び習得したものは数え直さない。週の始まりはカレンダーの設定に従う
    static func gains(masteredDates: [Date], today: Date = .now, calendar: Calendar = .current) -> MasteryGains {
        let todayStart = calendar.startOfDay(for: today)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today),
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) else {
            return MasteryGains()
        }
        var out = MasteryGains()
        for d in masteredDates {
            if d >= todayStart { out.today += 1 }
            if d >= week.start { out.thisWeek += 1 } else if d >= lastWeekStart { out.lastWeek += 1 }
        }
        return out
    }

    /// 1 セットで増えた習得（結果画面 §4.3 [v2.4]）。
    /// - newlyMastered: セット開始後にはじめて習得した問題（`masteredAt` が開始以後）
    /// - nearlyMastered: 一度も習得していず、直近 2 回正解で、あと 1 回の正解で習得になる問題
    static func setGain(itemIDs: [String], progress: [String: ProgressSnapshot], since start: Date) -> (newlyMastered: Int, nearlyMastered: Int) {
        var newly = 0, nearly = 0
        for id in Set(itemIDs) {
            guard let p = progress[id] else { continue }
            if let m = p.masteredAt {
                if m >= start { newly += 1 }
            } else if p.recentResults.count >= Priority.recentWindow - 1,
                      p.recentResults.suffix(Priority.recentWindow - 1).allSatisfy({ $0 }) {
                nearly += 1
            }
        }
        return (newly, nearly)
    }
}

/// 期間ごとに新しく習得した問題の数（§4.1 / §4.6 [v2.4]）
nonisolated struct MasteryGains: Hashable, Sendable {
    var today = 0
    var thisWeek = 0
    var lastWeek = 0
}
