import XCTest

final class WalletUITests: XCTestCase {
    @MainActor
    func testWalletOverviewActivityAndInsights() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestWallet"]
        app.launch()
        XCTAssertTrue(app.segmentedControls.buttons["Activity"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Posted charges · this month"].exists)
        capture("Wallet Overview", app: app)
        app.segmentedControls.buttons["Activity"].tap()
        XCTAssertTrue(app.textFields["Search merchant or description"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Netflix"].firstMatch.exists)
        capture("Wallet Activity", app: app)
        app.segmentedControls.buttons["Insights"].tap()
        XCTAssertTrue(app.buttons["Review recurring charges"].waitForExistence(timeout: 3))
        capture("Wallet Insights", app: app)
        app.buttons["Review recurring charges"].tap()
        XCTAssertTrue(app.navigationBars["Review results"].waitForExistence(timeout: 5))
        capture("Wallet Review", app: app)
    }
    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
