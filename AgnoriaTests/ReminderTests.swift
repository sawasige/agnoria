import Foundation
import Testing
@testable import Agnoria

@Suite("リマインダーの予定")
struct ReminderTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }
    /// 2026-10-20 の h:m（東京）
    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    @Test("今日まだなら今日から 7 日分。連続中なら今日の分は日数入り、明日以降は途切れた扱い") func notDoneToday() {
        let sessions = [at(19, 9), at(18, 9)]   // 昨日・一昨日
        let plan = Reminder.plan(sessionDates: sessions, minutes: 20 * 60, now: at(20, 12), calendar: cal)
        #expect(plan.count == 7)
        #expect(plan[0].fireDate == at(20, 20))
        #expect(plan[0].id == "reminder-2026-10-20")
        #expect(plan[0].title == "連続 2 日")
        #expect(plan[0].body.contains("3 日目"))
        #expect(plan[1].title == "今日の 10 問")
        #expect(plan.last?.fireDate == at(26, 20))
    }

    @Test("今日もう完走していれば今日の分は予約せず、明日の分に今日までの連続日数を出す") func doneToday() {
        let sessions = [at(20, 8), at(19, 9)]
        let plan = Reminder.plan(sessionDates: sessions, minutes: 21 * 60 + 30, now: at(20, 12), calendar: cal)
        #expect(plan.count == 6)
        #expect(plan[0].fireDate == at(21, 21, 30))
        #expect(plan[0].title == "連続 2 日")
        #expect(plan[1].title == "今日の 10 問")
    }

    @Test("時刻を過ぎていれば今日の分は予約しない。学習したことがなければ日数を出さない") func pastTimeAndNoHistory() {
        let plan = Reminder.plan(sessionDates: [], minutes: 20 * 60, now: at(20, 20, 1), calendar: cal)
        #expect(plan.count == 6)
        #expect(plan[0].fireDate == at(21, 20))
        #expect(plan.allSatisfy { $0.title == "今日の 10 問" })
        #expect(Reminder.timeText(20 * 60) == "20:00")
        #expect(Reminder.timeText(7 * 60 + 5) == "7:05")
    }
}
