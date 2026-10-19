import Foundation
import Testing
@testable import Agnoria

@Suite("ウィジェットの写し")
struct WidgetSnapshotTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from now: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    @Test("連続日数は最終日基準で持ち、表示側で今日・昨日なら続き、それより前なら 0") func streak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var byLevel: [Int: MasterySummary] = [:]
        var s = MasterySummary(); s.counts[.mastered] = 8; s.counts[.unseen] = 2
        byLevel[450] = s
        let stage = AppModel.StageState(current: 500, unlocked: 500, byLevel: byLevel)

        // 3 日連続、最終日が今日
        let today = WidgetSnapshot.make(stage: stage, sessionDates: [day(0, from: now), day(-1, from: now), day(-2, from: now)], now: now, calendar: cal)
        #expect(today.streakDays == 3)
        #expect(today.isDoneToday(now: now, calendar: cal))
        #expect(today.displayStreak(now: now, calendar: cal) == 3)
        #expect(today.levels.first { $0.level == 450 }?.cleared == true)
        #expect(today.levels.first { $0.level == 450 }?.masteredRatio == 0.8)
        #expect(today.current?.level == 500)

        // 最終日が昨日: 今日はまだ、連続は続いている
        let yesterday = WidgetSnapshot.make(stage: stage, sessionDates: [day(-1, from: now), day(-2, from: now)], now: now, calendar: cal)
        #expect(!yesterday.isDoneToday(now: now, calendar: cal))
        #expect(yesterday.displayStreak(now: now, calendar: cal) == 2)
        // 日付が 2 日進むと途切れる
        #expect(yesterday.displayStreak(now: day(2, from: now), calendar: cal) == 0)

        // 一度も学習していない
        let none = WidgetSnapshot.make(stage: stage, sessionDates: [], now: now, calendar: cal)
        #expect(none.lastStudyDay == nil && none.displayStreak(now: now, calendar: cal) == 0 && !none.isDoneToday(now: now, calendar: cal))
    }

    @Test("UserDefaults に JSON で保存して読み戻せる") func roundTrip() {
        let defaults = UserDefaults(suiteName: "WidgetSnapshotTests-\(UUID().uuidString)")!
        let snap = WidgetSnapshot(lastStudyDay: nil, streakDays: 0, unlockedLevel: 450, currentLevel: 450,
                                  levels: [.init(level: 450, masteredRatio: 0.25, cleared: false)], updatedAt: Date(timeIntervalSince1970: 0))
        snap.save(to: defaults)
        #expect(WidgetSnapshot.load(from: defaults) == snap)
        WidgetSnapshot.clear(from: defaults)
        #expect(WidgetSnapshot.load(from: defaults) == nil)
    }
}
