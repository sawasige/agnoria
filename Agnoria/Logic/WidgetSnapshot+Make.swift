import Foundation

nonisolated extension WidgetSnapshot {
    /// 学習状況からウィジェット用の写しを作る（純粋関数。AppModel.refreshWidgetSnapshot が呼ぶ）
    static func make(stage: AppModel.StageState, sessionDates: [Date], now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let lastDay = sessionDates.map { calendar.startOfDay(for: $0) }.max()
        // 最終日を基準にした連続日数（表示側で今日・昨日かを見て 0 にする）
        let streak = lastDay.map { Streak.compute(sessionDates: sessionDates, today: $0, calendar: calendar).days } ?? 0
        let levels = Stage.levels.map { level in
            let s = stage.byLevel[level] ?? MasterySummary()
            return LevelProgress(level: level, masteredRatio: s.masteredRatio, cleared: Stage.isCleared(s))
        }
        return WidgetSnapshot(lastStudyDay: lastDay, streakDays: streak, unlockedLevel: stage.unlocked,
                              currentLevel: stage.current, levels: levels, updatedAt: now)
    }
}
