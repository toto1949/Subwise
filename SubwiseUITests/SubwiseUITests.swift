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
}
