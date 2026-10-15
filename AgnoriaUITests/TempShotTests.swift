import XCTest

final class TempShotTests: XCTestCase {
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func playSet(_ app: XCUIApplication, shots: Bool) {
        for i in 0..<10 {
            let a = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'A. '")).firstMatch
            let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'B. '")).firstMatch
            XCTAssertTrue(a.waitForExistence(timeout: 10))
            if shots && i == 0 { sleep(1); shot("03-quiz") }
            (i % 3 == 0 ? b : a).tap()
            if shots && i == 0 { sleep(2); shot("04-answered") }
            let next = app.buttons["次へ"].firstMatch, last = app.buttons["結果を見る"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5) || last.exists)
            if next.exists { next.tap() } else { last.tap() }
        }
        XCTAssertTrue(app.buttons["ホームへ"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testStoreShots() throws {
        let app = XCUIApplication.launchQuiet()
        let auto = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'おまかせで10問'")).firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 30))
        // 進捗を少し作る: 2 セット
        for _ in 0..<2 {
            auto.tap(); playSet(app, shots: false)
            app.buttons["ホームへ"].firstMatch.tap()
            XCTAssertTrue(auto.waitForExistence(timeout: 10))
        }
        sleep(1); shot("01-home")
        app.buttons["分野を選ぶ"].firstMatch.tap(); sleep(1); shot("02-pick")
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ビジネス一般'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.tap()
        playSet(app, shots: true)
        sleep(1); shot("05-result")
        app.buttons["ホームへ"].firstMatch.tap()
        XCTAssertTrue(auto.waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '点帯の習得'")).firstMatch
        if card.waitForExistence(timeout: 5) { card.tap(); sleep(1); shot("06-stats") }
    }
}
