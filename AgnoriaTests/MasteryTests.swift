import Foundation
import Testing
@testable import Agnoria

@Suite("習得段階の集計")
struct MasteryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("4分類") func classify() {
        #expect(Mastery.of(nil) == .unseen)
        #expect(Mastery.of(ProgressSnapshot(itemID: "a")) == .unseen)
        #expect(Mastery.of(ProgressSnapshot(itemID: "a", recentResults: [true, false, true])) == .struggling)
        #expect(Mastery.of(ProgressSnapshot(itemID: "a", recentResults: [true])) == .learning)
        #expect(Mastery.of(ProgressSnapshot(itemID: "a", recentResults: [true, true])) == .learning)
        #expect(Mastery.of(ProgressSnapshot(itemID: "a", recentResults: [true, true, true])) == .mastered)
    }

    @Test("件数・比率・復習のころあい") func summarize() {
        let items: [(id: String, category: String)] = [("a", "品詞"), ("b", "品詞"), ("c", "語彙"), ("d", "語彙")]
        let progress: [String: ProgressSnapshot] = [
            "a": ProgressSnapshot(itemID: "a", recentResults: [true, true, true], totalCorrect: 3, totalAnswered: 3,
                                  lastAnsweredAt: now.addingTimeInterval(-10 * 86_400)),
            "b": ProgressSnapshot(itemID: "b", recentResults: [false], totalCorrect: 0, totalAnswered: 1, lastAnsweredAt: now),
            "c": ProgressSnapshot(itemID: "c", recentResults: [true], totalCorrect: 1, totalAnswered: 1, lastAnsweredAt: now),
        ]
        let s = MasteryStats.summarize(items: items, progress: progress, now: now)
        #expect(s.total == 4)
        #expect(s[.mastered] == 1 && s[.struggling] == 1 && s[.learning] == 1 && s[.unseen] == 1)
        #expect(s.masteredPercent == 25)
        #expect(s.answered == 5 && s.correct == 4)
        #expect(s.accuracyPercent == 80)
        #expect(s.dueForReview == 1)

        let byCat = MasteryStats.byCategory(items: items, progress: progress, now: now)
        #expect(byCat["品詞"]?.total == 2)
        #expect(byCat["語彙"]?[.unseen] == 1)
        #expect((byCat["品詞"]! + byCat["語彙"]!) == s)
        #expect(MasterySummary().accuracyPercent == nil)
        #expect(MasterySummary().masteredRatio == 0)
    }

    @Test("日別集計は days 日分を 0 埋めで古い順に返す") func daily() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 15))!
        let r = { (ok: Bool) in SessionResult(itemID: "x", isCorrect: ok, chosenIndex: 0, elapsedMs: 100) }
        let sessions: [(finishedAt: Date, results: [SessionResult])] = [
            (cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 0, minute: 10))!, [r(true), r(false)]),
            (cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 23, minute: 50))!, [r(true)]),
            (cal.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!, [r(true)]),   // 範囲外（14日より前）
            (cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!, [r(false), r(false)]),
        ]
        let days = MasteryStats.daily(sessions: sessions, days: 14, today: today, calendar: cal)
        #expect(days.count == 14)
        #expect(days.first?.date == cal.date(from: DateComponents(year: 2026, month: 9, day: 30)))
        #expect(days.last?.date == cal.startOfDay(for: today))
        #expect(days.last?.answered == 3 && days.last?.correct == 2)
        let oct5 = days.first { cal.component(.day, from: $0.date) == 5 }
        #expect(oct5?.answered == 2 && oct5?.correct == 0)
        #expect(days.filter { $0.answered == 0 }.count == 12)
    }

    @Test("days: 1 の末尾は今日で、今日のセッションだけを数える（ホームの「今日」カード）") func todayOnly() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
        let r = { (ok: Bool) in SessionResult(itemID: "x", isCorrect: ok, chosenIndex: 0, elapsedMs: 100) }
        let sessions: [(finishedAt: Date, results: [SessionResult])] = [
            (cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 59))!, [r(true), r(true)]),
            (cal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 0, minute: 1))!, [r(true), r(false), r(false)]),
        ]
        let days = MasteryStats.daily(sessions: sessions, days: 1, today: today, calendar: cal)
        #expect(days.count == 1)
        #expect(days.last?.date == cal.startOfDay(for: today))
        #expect(days.last?.answered == 3 && days.last?.correct == 1)
        #expect(MasteryStats.daily(sessions: [], days: 1, today: today, calendar: cal).last?.answered == 0)
    }

    @Test("今日・今週・先週に新しく習得した数を masteredAt で数える。週の始まりはカレンダーに従う") func gains() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        cal.firstWeekday = 2  // 月曜始まり
        func d(_ day: Int, _ hour: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let today = d(28, 20)  // 水曜
        let dates = [d(28, 9), d(28, 0), d(27), d(26, 0), d(25, 23), d(19), d(18), d(12)]
        let g = MasteryStats.gains(masteredDates: dates, today: today, calendar: cal)
        #expect(g.today == 2)
        #expect(g.thisWeek == 4, "26 日（月）0 時から")
        #expect(g.lastWeek == 2, "19 日（月）〜25 日（日）")
        cal.firstWeekday = 1  // 日曜始まりなら 25 日も今週
        #expect(MasteryStats.gains(masteredDates: dates, today: today, calendar: cal).thisWeek == 5)
        #expect(MasteryStats.gains(masteredDates: [], today: today, calendar: cal) == MasteryGains())
    }

    @Test("1 セットで増えた習得: 開始後にはじめて習得した数と、あと 1 回の正解で習得になる数") func setGain() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func p(_ id: String, _ results: [Bool], mastered: Date? = nil) -> ProgressSnapshot {
            ProgressSnapshot(itemID: id, recentResults: results, masteredAt: mastered)
        }
        let progress: [String: ProgressSnapshot] = [
            "new": p("new", [true, true, true], mastered: start.addingTimeInterval(60)),
            "old": p("old", [true, true, true], mastered: start.addingTimeInterval(-86_400)),  // 前から習得
            "near": p("near", [false, true, true]),
            "near2": p("near2", [true, true]),
            "one": p("one", [true]),
            "relapsed": p("relapsed", [true, false, true], mastered: start.addingTimeInterval(-86_400)),  // 再習得は数えない
        ]
        let ids = ["new", "new", "old", "near", "near2", "one", "relapsed", "missing"]
        let g = MasteryStats.setGain(itemIDs: ids, progress: progress, since: start)
        #expect(g.newlyMastered == 1)
        #expect(g.nearlyMastered == 2)
    }
}
