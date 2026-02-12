import XCTest

final class EliAIUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesWithoutModel() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launchArguments.append("-disableAutoModelLoad")
        app.launch()

        XCTAssertTrue(app.staticTexts["EliAI"].waitForExistence(timeout: 10))
    }
}
