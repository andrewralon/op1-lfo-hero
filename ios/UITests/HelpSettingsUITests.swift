import XCTest

final class HelpSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHelpModalOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))
        helpButton.tap()

        XCTAssertTrue(app.navigationBars["help"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/help_modal_ipad.png"))

        app.buttons["done"].tap()
        XCTAssertFalse(app.navigationBars["help"].waitForExistence(timeout: 2))
    }

    func testSettingsModalOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["settings"].waitForExistence(timeout: 5))

        app.buttons["done"].tap()
        XCTAssertFalse(app.navigationBars["settings"].waitForExistence(timeout: 2))
    }
}
