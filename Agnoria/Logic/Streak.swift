import Foundation

/// 連続学習日数（1日1セット以上で継続）
enum Streak {
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
}

/// レベル称号（§4.5）。演出のみ
enum Rank {
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
