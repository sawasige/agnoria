import Foundation
import Testing
@testable import Agnoria

@Suite("クリアまでの目安")
struct PaceTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_400_000) // 2025-10-14 頃の正午前後

    private func daysAgo(_ n: Int, count: Int = 1) -> [Date] {
        let d = calendar.date(byAdding: .day, value: -n, to: now)!
        return Array(repeating: d, count: count)
    }

    @Test("履歴がなければ既定値でセット数だけ。日数は出さない") func noHistory() {
        let e = Pace.estimate(remaining: 118, masteredDates: [], sessionDates: [], now: now, calendar: calendar)
        #expect(e == Pace.Estimate(sets: 66, days: nil)) // 118 / 1.8 = 65.6
    }

    @Test("クリア済みなら nil") func cleared() {
        #expect(Pace.estimate(remaining: 0, masteredDates: [], sessionDates: daysAgo(0), now: now, calendar: calendar) == nil)
    }

    @Test("14 日間毎日 5 セット、100 問習得なら 1 日 5 セットのペース") func steady() {
        var sessions: [Date] = []
        for d in 0..<14 { sessions += daysAgo(d, count: 5) }
        let mastered = daysAgo(3, count: 100)
        let e = Pace.estimate(remaining: 60, masteredDates: mastered, sessionDates: sessions, now: now, calendar: calendar)
        // perSet = (100 + 18) / (70 + 10) = 1.475 → 60 / 1.475 = 40.7 → 41 セット。5 セット/日 → 8.2 → 9 日
        #expect(e == Pace.Estimate(sets: 41, days: 9))
    }

    @Test("始めて 3 日なら 3 日で割る。少ない実績は既定値に引っ張られる") func justStarted() {
        let sessions = daysAgo(2, count: 3) + daysAgo(1, count: 3) + daysAgo(0, count: 3)
        let e = Pace.estimate(remaining: 116, masteredDates: daysAgo(0, count: 4), sessionDates: sessions, now: now, calendar: calendar)
        // perSet = (4 + 18) / (9 + 10) = 1.158 → 101 セット。3 セット/日 → 34 日
        #expect(e == Pace.Estimate(sets: 101, days: 34))
    }

    @Test("14 日より前の履歴は見ない") func window() {
        let old = daysAgo(20, count: 50)
        let e = Pace.estimate(remaining: 118, masteredDates: daysAgo(20, count: 90), sessionDates: old, now: now, calendar: calendar)
        #expect(e == Pace.Estimate(sets: 66, days: nil))
    }

    @Test("日数の表示は 60 日から月に切り替わる") func text() {
        #expect(Pace.daysText(1) == "約 1 日")
        #expect(Pace.daysText(59) == "約 59 日")
        #expect(Pace.daysText(60) == "約 2 か月")
        #expect(Pace.daysText(100) == "約 3 か月")
    }
}
