import Foundation
import FirebaseCore
import FirebaseAnalytics

/// 利用状況の計測（§7 [v1.6]）。送るのは機能の利用回数だけで、問題の内容・回答・個人を特定できる情報は送らない。
/// 送る先は Firebase Analytics。View は Firebase を直接呼ばず、必ずここを通す
@MainActor
final class UsageAnalytics {
    /// 送る出来事。name と params は Firebase の制約（名前 40 字以内、文字列値 100 字以内）に収める
    nonisolated enum Event: Equatable, Sendable {
        case setStart(QuizConfig)
        case setFinish(QuizConfig, count: Int, correct: Int, durationSec: Int)
        case setAbort(QuizConfig, answered: Int)
        case stageClear(Stage.Clear)
        case rephraseUsed
        case practiceUsed
        case speakTapped
        case bookmarkToggled(on: Bool)
        case historyReset
        case settingsChanged(key: String)

        var name: String {
            switch self {
            case .setStart: "set_start"
            case .setFinish: "set_finish"
            case .setAbort: "set_abort"
            case .stageClear: "stage_clear"
            case .rephraseUsed: "rephrase_used"
            case .practiceUsed: "practice_used"
            case .speakTapped: "speak_tapped"
            case .bookmarkToggled: "bookmark_toggled"
            case .historyReset: "history_reset"
            case .settingsChanged: "settings_changed"
            }
        }

        var params: [String: Any] {
            switch self {
            case .setStart(let c):
                return Self.configParams(c)
            case .setFinish(let c, let count, let correct, let durationSec):
                return Self.configParams(c).merging(["count": count, "correct": correct, "duration_sec": durationSec]) { a, _ in a }
            case .setAbort(let c, let answered):
                return Self.configParams(c).merging(["answered": answered]) { a, _ in a }
            case .stageClear(let clear):
                return ["level": clear.cleared, "next": clear.next ?? 0]
            case .bookmarkToggled(let on):
                return ["on": on ? 1 : 0]
            case .settingsChanged(let key):
                return ["key": key]
            case .rephraseUsed, .practiceUsed, .speakTapped, .historyReset:
                return [:]
            }
        }

        /// mode: auto / word / grammar、category: 分野 id か mix、format: 単語の形式か random、filter: all / wrong / bookmarked
        static func configParams(_ c: QuizConfig) -> [String: Any] {
            let filter: String = switch c.filter {
            case .all: "all"
            case .wrongOnly: "wrong"
            case .bookmarked: "bookmarked"
            }
            return [
                "mode": c.mode?.rawValue ?? "auto",
                "category": c.category ?? "mix",
                "format": c.format?.rawValue ?? "random",
                "filter": c.restrictTo == nil ? filter : "retry",
            ]
        }
    }

    /// 送らない理由（設定画面の表示と判断に使う）
    enum State: Equatable {
        /// 送っている
        case active
        /// 設定ファイルが無い（Firebase 未設定のビルド）
        case unconfigured
        /// 起動引数 `-analytics NO` か Debug ビルド
        case disabledByLaunch
        /// 設定の「使用状況の送信」が OFF
        case disabledBySetting
    }

    private(set) var state: State
    private let settings: AppSettings

    /// アプリ起動時に 1 回。Firebase の設定ファイルが同梱されていれば configure する。
    /// Debug ビルドは `-analytics YES` を付けたときだけ送る（開発中の操作を本番の計測に混ぜない）。
    /// `-analytics NO` は常に優先（UI テストの launchQuiet が付ける）
    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        let configured = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        let arg = defaults.object(forKey: "analytics") == nil ? nil : defaults.bool(forKey: "analytics")
        #if DEBUG
        let allowedByLaunch = arg == true
        #else
        let allowedByLaunch = arg != false
        #endif
        if !configured {
            state = .unconfigured
        } else if !allowedByLaunch {
            state = .disabledByLaunch
        } else {
            state = settings.usageReporting ? .active : .disabledBySetting
        }
        guard configured, allowedByLaunch else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Analytics.setAnalyticsCollectionEnabled(settings.usageReporting)
        syncUserProperties()
    }

    /// 設定の「使用状況の送信」を反映
    func applySetting() {
        guard state == .active || state == .disabledBySetting else { return }
        state = settings.usageReporting ? .active : .disabledBySetting
        Analytics.setAnalyticsCollectionEnabled(settings.usageReporting)
    }

    func log(_ event: Event) {
        guard state == .active else { return }
        Analytics.logEvent(event.name, parameters: event.params)
    }

    /// 到達帯をユーザープロパティに。帯が変わるたびに呼ぶ
    func syncUserProperties() {
        guard state == .active else { return }
        Analytics.setUserProperty(String(settings.unlockedLevel), forName: "unlocked_level")
    }
}
