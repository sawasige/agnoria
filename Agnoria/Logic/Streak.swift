import Foundation

/// 連続学習日数（1日1セット以上で継続）
nonisolated enum Streak {
    struct Result: Equatable, Sendable {
        var days: Int
        var doneToday: Bool
    }

    static func compute(sessionDates: [Date], today: Date = .now, calendar: Calendar = .current) -> Result {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)
        let doneToday = days.contains(todayStart)
        // 今日やっていなければ昨日からさかのぼる（まだ途切れていない扱い）
        var cursor = doneToday ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return Result(days: count, doneToday: doneToday)
    }

    /// これまでの最長の連続日数（今の連続も含む）[v2.4]
    static func longest(sessionDates: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// この日数以上あいて開いたら、ホームの連続カードで「おかえりなさい」と迎える [v2.4]
    static let welcomeBackDays = 3

    /// 最後に学習した日から今日までの日数（今日学習済みなら 0）。記録が無ければ nil [v2.4]
    static func daysAway(sessionDates: [Date], today: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let last = sessionDates.max() else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: today)).day
    }
}

/// レベル称号（§4.5）。演出のみ
nonisolated enum Rank {
    static func title(totalCorrect: Int) -> String {
        switch totalCorrect {
        case ..<100: "Kore"
        case ..<300: "Kore, Learning"
        case ..<600: "Persephone"
        default: "Persephone, in Spring"
        }
    }

    static func subtitle(totalCorrect: Int) -> String {
        switch totalCorrect {
        case ..<100: "世間知らずの娘"
        case ..<300: "学びはじめた娘"
        case ..<600: "冥界の女王、まだ冬"
        default: "春を取り戻した女王"
        }
    }
}
