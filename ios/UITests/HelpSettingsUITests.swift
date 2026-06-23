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

    func testParamPickerLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launch()
        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 8))
        let paramPicker = app.buttons["paramPicker"]
        XCTAssertTrue(paramPicker.waitForExistence(timeout: 3))
        paramPicker.tap()
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/param_picker_landscape_\(name).png"))
    }

    func testParamPickerOpens() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        // Wait past splash, then tap the parameter picker button (bold text label)
        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 5))

        // The param picker button has a stable accessibilityIdentifier
        let paramPicker = app.buttons["paramPicker"]
        XCTAssertTrue(paramPicker.waitForExistence(timeout: 3))
        paramPicker.tap()

        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/param_picker_\(name).png"))
    }

    func testSettingsModalOpensAndDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["settings"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/settings_modal.png"))

        app.buttons["done"].tap()
        XCTAssertFalse(app.navigationBars["settings"].waitForExistence(timeout: 2))
    }

    func testLandscapeLayout() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launch()
        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 8))
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/landscape_\(device).png"))
    }

    func testPortraitLayout() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 8))
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/claude-ss/portrait_\(device).png"))
    }
}
