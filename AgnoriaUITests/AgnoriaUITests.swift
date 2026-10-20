import XCTest

extension XCUIApplication {
    /// 効果音と自動読み上げを切って起動する。UserDefaults の引数ドメインに入るだけなので、設定としては保存されない。
    /// UI テスト（画面確認用の一時テストも含む）はこれで起動して、テスト中に Mac から音を出さない
    @discardableResult
    static func launchQuiet() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-soundEffects", "NO", "-autoSpeak", "NO", "-analytics", "NO", "-cloudSync", "NO", "-reviewPrompt", "NO", "-reminderPrompt", "NO"]
        app.launch()
        return app
    }
}

final class AgnoriaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 起動してホームが出る。設定を開くと、起動引数で効果音と読み上げが切れている
    @MainActor
    func testLaunchQuiet() throws {
        let app = XCUIApplication.launchQuiet()
        let auto = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'おまかせで10問'")).firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 30))

        let gear = app.buttons["設定"].firstMatch
        #if os(macOS)
        gear.click()
        #else
        gear.tap()
        #endif
        // macOS の Switch はラベルを持たない（隣の StaticText）ので識別子で探す
        let sound = app.switches["soundEffectsToggle"].firstMatch
        XCTAssertTrue(sound.waitForExistence(timeout: 10))
        // value は iOS では "0"、macOS では 0（NSNumber）
        XCTAssertEqual("\(sound.value ?? "")", "0")
        XCTAssertEqual("\(app.switches["autoSpeakToggle"].firstMatch.value ?? "")", "0")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication.launchQuiet()
        }
    }
}
