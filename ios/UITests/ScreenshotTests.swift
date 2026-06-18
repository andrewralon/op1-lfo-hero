import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // Wait for splash to clear
        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 8))

        // 1. Main UI — tracks + transport + LFO panel
        snapshot("01_main")

        // 2. Help screen
        helpButton.tap()
        XCTAssertTrue(app.navigationBars["help"].waitForExistence(timeout: 5))
        snapshot("02_help")
        app.buttons["done"].tap()
    }
}
