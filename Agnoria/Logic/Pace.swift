import Foundation

/// 今の帯をクリアするまでの目安（§4.1 [v1.4]）。純粋関数のみ。
/// 「1 セットで何問習得できるか」は直近 14 日の実績に既定値（シミュレーション値）を混ぜて求め、
/// 日数は直近 14 日（学習を始めてそれに満たないなら始めた日から）の 1 日あたりセット数で割る
nonisolated enum Pace {
    struct Estimate: Equatable, Sendable {
        /// あと何セット
        var sets: Int
        /// 今のペースなら何日。直近 14 日に学習がなければ nil
        var days: Int?
    }

    /// 1 セットあたりの習得数の既定値。正答率 60〜95% の学習者のシミュレーション（SPEC-REVIEW I11）で 1.6〜2.0
    static let defaultMasteredPerSet = 1.8
    /// 既定値の重み（セット数換算）。実績がこの程度たまると実績が優勢になる
    static let priorWeight = 10.0
    static let windowDays = 14

    /// - Parameters:
    ///   - remaining: クリアまであと何問の習得か（`Stage.remainingToClear`）。0 なら nil
    ///   - masteredDates: 習得した日時（全帯。`ItemProgress.masteredAt`）
    ///   - sessionDates: セット完走の日時（`StudySession.finishedAt`）
    ///   - share: この軸が 1 セットに占める割合の見込み（§3.4 [v1.8]）。既定値（1 セットの習得数）に掛ける。
    ///     masteredDates もその軸の問題の分だけを渡す
    static func estimate(remaining: Int, masteredDates: [Date], sessionDates: [Date], share: Double = 1,
                         now: Date = .now, calendar: Calendar = .current) -> Estimate? {
        guard remaining > 0 else { return nil }
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: todayStart) else { return nil }
        let recentSessions = sessionDates.filter { $0 >= windowStart }
        let recentMastered = masteredDates.filter { $0 >= windowStart }.count

        let perSet = (Double(recentMastered) + defaultMasteredPerSet * share * priorWeight)
            / (Double(recentSessions.count) + priorWeight)
        let sets = max(1, Int((Double(remaining) / max(perSet, 0.01)).rounded(.up)))

        guard let first = recentSessions.min() else { return Estimate(sets: sets, days: nil) }
        let firstDay = calendar.startOfDay(for: first)
        let span = (calendar.dateComponents([.day], from: firstDay, to: todayStart).day ?? 0) + 1
        let setsPerDay = Double(recentSessions.count) / Double(span)
        let days = max(1, Int((Double(sets) / setsPerDay).rounded(.up)))
        return Estimate(sets: sets, days: days)
    }

    /// 表示用: 「約 N 日」、60 日以上は「約 N か月」
    static func daysText(_ days: Int) -> String {
        days < 60 ? "約 \(days) 日" : "約 \(Int((Double(days) / 30).rounded())) か月"
    }
}
