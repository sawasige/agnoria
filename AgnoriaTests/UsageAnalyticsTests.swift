import Foundation
import Testing
@testable import Agnoria

@Suite("利用状況の計測")
struct UsageAnalyticsTests {
    @Test("イベント名とパラメータ: 問題の内容は含めず、条件は短い文字列にする") func eventParams() {
        let auto = UsageAnalytics.Event.setStart(.auto)
        #expect(auto.name == "set_start")
        #expect(auto.params["mode"] as? String == "auto")
        #expect(auto.params["category"] as? String == "mix")
        #expect(auto.params["format"] as? String == "random")
        #expect(auto.params["filter"] as? String == "all")

        var retry = QuizConfig(mode: .word, category: "business", format: .cloze, filter: .wrongOnly)
        retry.restrictTo = ["w-001"]
        let finish = UsageAnalytics.Event.setFinish(retry, count: 10, correct: 7, durationSec: 95)
        #expect(finish.name == "set_finish")
        #expect(finish.params["mode"] as? String == "word")
        #expect(finish.params["format"] as? String == "cloze")
        #expect(finish.params["filter"] as? String == "retry")
        #expect(finish.params["count"] as? Int == 10)
        #expect(finish.params["correct"] as? Int == 7)
        #expect(finish.params["duration_sec"] as? Int == 95)
        #expect(finish.params["itemID"] == nil)

        let top = UsageAnalytics.Event.stageClear(Stage.Clear(mode: .grammar, cleared: 600, next: nil))
        #expect(top.params["level"] as? Int == 600)
        #expect(top.params["next"] as? Int == 0)
        #expect(top.params["mode"] as? String == "grammar")
        #expect(UsageAnalytics.Event.bookmarkToggled(on: true).params["on"] as? Int == 1)
        #expect(UsageAnalytics.Event.settingsChanged(key: "soundEffects").params["key"] as? String == "soundEffects")
        #expect(UsageAnalytics.Event.rephraseUsed.params.isEmpty)
        #expect(UsageAnalytics.Event.reviewRequested(.highScore).params["trigger"] as? String == "high_score")
    }

    @Test("Firebase の制約: イベント名は 40 字以内、パラメータ名は 40 字以内") func firebaseLimits() {
        let events: [UsageAnalytics.Event] = [
            .setStart(.auto), .setFinish(.auto, count: 1, correct: 1, durationSec: 1), .setAbort(.auto, answered: 0),
            .stageClear(Stage.Clear(mode: .grammar, cleared: 450, next: 500)), .rephraseUsed, .practiceUsed, .speakTapped,
            .bookmarkToggled(on: false), .historyReset, .settingsChanged(key: "autoSpeak"),
            .reviewRequested(.stageClear), .reviewRequested(.highScore), .reviewLinkOpened,
        ]
        for e in events {
            #expect(e.name.count <= 40 && e.name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" })
            for key in e.params.keys { #expect(key.count <= 40) }
        }
    }

    @Test("設定ファイルの無いビルドでは unconfigured で、ログしても何も起きない") @MainActor func unconfigured() {
        let defaults = UserDefaults(suiteName: "UsageAnalyticsTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let a = UsageAnalytics(settings: settings, defaults: defaults, configured: false)
        #expect(a.state == .unconfigured)
        a.log(.historyReset)
        a.syncUserProperties()
        #expect(a.state == .unconfigured)
    }

    @Test("起動引数 -analytics NO は設定より優先で、Firebase を初期化しない") @MainActor func disabledByLaunch() {
        let defaults = UserDefaults(suiteName: "UsageAnalyticsTests-\(UUID().uuidString)")!
        defaults.set(false, forKey: "analytics")
        let settings = AppSettings(defaults: defaults)
        let a = UsageAnalytics(settings: settings, defaults: defaults, configured: true)
        #expect(a.state == .disabledByLaunch)
        a.log(.setStart(.auto))
        #expect(a.state == .disabledByLaunch)
    }
}
