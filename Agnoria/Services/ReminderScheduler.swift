import Foundation
import UserNotifications

/// 学習のリマインダー通知（§4.9 [v1.8]）。ローカル通知だけで、サーバーは使わない。
/// 予定は Reminder.plan が作り、ここは許可の確認と予約の置き換えだけを行う。通知の受け口（デリゲート）も兼ねる
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    /// 通知をタップしてアプリを開いたとき（計測用。AppModel が設定する）
    var onOpen: (() -> Void)?

    /// テスト中は通知センターに触れない（ホストアプリの予約や許可を変えない）
    static var isAvailable: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] == nil && env["XCTestSessionIdentifier"] == nil
    }

    private var center: UNUserNotificationCenter { .current() }

    /// アプリ起動時に呼ぶ。通知のタップを受け取るため、起動直後にデリゲートを設定しておく
    func activate() {
        guard Self.isAvailable else { return }
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard Self.isAvailable else { return .notDetermined }
        return await center.notificationSettings().authorizationStatus
    }

    /// OS の許可ダイアログを出す。すでに決まっていればダイアログは出ず、その結果を返す
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 予約を置き換える。オフ・未許可なら消すだけ
    func reschedule(enabled: Bool, minutes: Int, sessionDates: [Date]) async {
        guard Self.isAvailable else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Reminder.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let calendar = Calendar.current
        for p in Reminder.plan(sessionDates: sessionDates, minutes: minutes, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// アプリを使っている最中は出さない（もう学習している）
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier.hasPrefix(Reminder.idPrefix) else { return }
        await MainActor.run { onOpen?() }
    }
}
