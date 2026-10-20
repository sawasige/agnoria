import Foundation

/// 学習のリマインダー通知の予定（§4.9 [v1.8]）。純粋関数のみ。
/// 通知の時点で「今日やったか」は判定できないので、繰り返し通知は使わず、今日から数日分を 1 日 1 件ずつ予約する。
/// セット完走・起動・設定の変更のたびに予約し直すので、学習した日の分は消え、文面の連続日数も最新になる
nonisolated enum Reminder {
    /// 既定の時刻（0 時からの分）。20:00
    static let defaultMinutes = 20 * 60
    /// 何日先まで予約するか
    static let daysAhead = 7
    /// 予約の識別子の接頭辞。予約し直すときはこれで始まるものを消す
    static let idPrefix = "reminder-"

    struct Planned: Equatable, Sendable {
        var id: String
        var fireDate: Date
        var title: String
        var body: String
    }

    /// - Parameters:
    ///   - sessionDates: セット完走の日時（`StudySession.finishedAt`）
    ///   - minutes: 通知する時刻（0 時からの分）
    static func plan(sessionDates: [Date], minutes: Int, now: Date = .now, calendar: Calendar = .current) -> [Planned] {
        let streak = Streak.compute(sessionDates: sessionDates, today: now, calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset in
            // 今日もう完走していれば今日の分は要らない
            if offset == 0, streak.doneToday { return nil }
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: day),
                  fire > now else { return nil }
            // その日まで学習しなかったとして、その日の朝の時点で続いている連続日数。
            // 今日の分は昨日までの連続、明日の分は今日やっていれば今日までの連続。それより先は途切れている
            let running: Int = switch offset {
            case 0: streak.days
            case 1: streak.doneToday ? streak.days : 0
            default: 0
            }
            let (title, body) = text(streak: running)
            return Planned(id: idPrefix + dayKey(day, calendar: calendar), fireDate: fire, title: title, body: body)
        }
    }

    /// 文面。連続中なら日数を出し、途切れていれば短く誘う
    static func text(streak: Int) -> (title: String, body: String) {
        if streak > 0 {
            return ("連続 \(streak) 日", "今日の 10 問で \(streak + 1) 日目。3 分で終わります")
        }
        return ("今日の 10 問", "1 セット 3 分。今日の分を始めましょう")
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 設定の表示用「20:00」
    static func timeText(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
