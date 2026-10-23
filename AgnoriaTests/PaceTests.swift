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

    @Test("やり直した日時より前のセットと習得は数えない。それ以後にセットがなければ日数は出さない") func sinceRestart() {
        var sessions: [Date] = []
        for d in 0..<14 { sessions += daysAgo(d, count: 5) }
        // やり直しで習得の記録が消えた状態（習得 0、セット 70）をそのまま数えると perSet = 18 / 80 = 0.225 → 356 セット・72 日
        let naive = Pace.estimate(remaining: 80, masteredDates: [], sessionDates: sessions, now: now, calendar: calendar)
        #expect(naive == Pace.Estimate(sets: 356, days: 72))
        // 3 日前にやり直し: それ以後のセット 15、習得 12 → perSet = (12 + 18) / (15 + 10) = 1.2 → 67 セット。5 セット/日 → 14 日
        let restart = calendar.date(byAdding: .hour, value: -1, to: daysAgo(2)[0])!
        let e = Pace.estimate(remaining: 80, masteredDates: daysAgo(1, count: 12), sessionDates: sessions, since: restart,
                              now: now, calendar: calendar)
        #expect(e == Pace.Estimate(sets: 67, days: 14))
        // やり直した直後（それ以後のセットなし）は既定値でセット数だけ
        let justNow = Pace.estimate(remaining: 80, masteredDates: [], sessionDates: sessions, since: now.addingTimeInterval(1), now: now, calendar: calendar)
        #expect(justNow == Pace.Estimate(sets: 45, days: nil)) // 80 / 1.8 = 44.4
    }

    @Test("日数の表示は 60 日から月に切り替わる") func text() {
        #expect(Pace.daysText(1) == "約 1 日")
        #expect(Pace.daysText(59) == "約 59 日")
        #expect(Pace.daysText(60) == "約 2 か月")
        #expect(Pace.daysText(100) == "約 3 か月")
    }
}
