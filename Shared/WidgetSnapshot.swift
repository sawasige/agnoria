import Foundation

/// ウィジェットに渡す学習状況の写し（§4.6 [v1.6]）。アプリがセット完走・履歴リセット・起動時に App Group の UserDefaults へ書き、
/// ウィジェット拡張はこれだけを読む（拡張は SwiftData も CloudKit も開かない）。アプリと拡張の両方のターゲットに入れる
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct LevelProgress: Codable, Equatable, Sendable {
        var level: Int
        /// 習得率 0.0〜1.0
        var masteredRatio: Double
        var cleared: Bool
    }

    /// 1 つの軸（単語 / 文法）の帯の進み [v1.8]
    struct Track: Codable, Equatable, Sendable {
        /// 表示名（「単語」など）
        var title: String
        /// 到達帯
        var unlockedLevel: Int
        /// 今取り組む帯
        var currentLevel: Int
        /// 450 → 600 の順
        var levels: [LevelProgress]

        var current: LevelProgress? { levels.first { $0.level == currentLevel } }
    }

    /// 最後に学習した日（その日の 0 時）。一度も学習していなければ nil
    var lastStudyDay: Date?
    /// lastStudyDay を最終日とする連続日数
    var streakDays: Int
    /// 軸ごとの帯の進み（単語 → 文法の順）
    var tracks: [Track]
    var updatedAt: Date

    static let appGroup = "group.com.himatsubu.Agnoria"
    static let key = "widgetSnapshot"

    /// 今日もう学習したか。日付が変わると自動的に false になる
    func isDoneToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastStudyDay else { return false }
        return calendar.isDate(lastStudyDay, inSameDayAs: now)
    }

    /// 表示する連続日数。今日か昨日が最終日なら続いている扱い、それより前なら 0
    func displayStreak(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let lastStudyDay else { return 0 }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return (calendar.isDate(lastStudyDay, inSameDayAs: today) || calendar.isDate(lastStudyDay, inSameDayAs: yesterday)) ? streakDays : 0
    }

    // MARK: - 保存

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load(from defaults: UserDefaults? = WidgetSnapshot.defaults) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        // 1.7 までの形（帯が 1 本）は読めずに nil になり、アプリの次の起動で書き直される
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = WidgetSnapshot.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    static func clear(from defaults: UserDefaults? = WidgetSnapshot.defaults) {
        defaults?.removeObject(forKey: key)
    }
}
