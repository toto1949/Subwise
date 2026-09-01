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

    @MainActor
    func testDiscoverySourcesAndManualFlowAreReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSkipOnboarding", "-internalDevelopmentMode"]
        app.launch()

        let discover = app.buttons["Find subscriptions"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.tap()

        XCTAssertTrue(app.staticTexts["Connect your bank or card"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple Wallet accounts"].exists)
        XCTAssertTrue(app.staticTexts["Apple subscriptions"].exists)
        XCTAssertTrue(app.staticTexts["Add manually"].exists)

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add manually'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["Subscription name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Price"].exists)
        XCTAssertTrue(app.buttons["Billing cycle, Monthly"].exists || app.staticTexts["Billing cycle"].exists)
    }
}
