import XCTest

final class SubwiseUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOnboardingStartsWithValue() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestResetOnboarding")
        app.launch()
        XCTAssertTrue(app.buttons["Find My Savings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Know what your subscriptions really cost."].exists)
    }

    @MainActor
    func testAgentDismissesKeyboardAfterSending() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSkipOnboarding", "-internalDevelopmentMode"]
        app.launch()

        let agentTab = app.tabBars.buttons["Agent"]
        XCTAssertTrue(agentTab.waitForExistence(timeout: 5))
        agentTab.tap()

        let composer = app.textFields["Ask about your subscriptions"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("What renews soon?")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.buttons["Send message"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }
}
