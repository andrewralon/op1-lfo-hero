import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launch()

        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 8))
        sleep(1)

        // 1. Main UI — fresh state
        try save("01_main")

        // Build chip 1: track 1, volume, square, speed 4, center 90 (default), depth 10
        // After --uitest-reset, track 1 is already ON (state 1 = normal)
        selectPicker(app, picker: "wavePicker", option: "square")
        bumpRate(app, by: 2)  // index 3 -> 5 (displayed "4")
        scrub(app, identifier: "depthScrub", to: 10)
        app.buttons["repeatButton"].tap()
        sleep(2)

        // Build chip 2: track 2 normal + track 4 inverted, pan, sine, speed 2, center 50, depth 30
        app.buttons["track1Button"].tap()           // 1 -> 2 (inverted)
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["track1Button"].tap()           // 2 -> 0 (off)
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["track2Button"].tap()           // 0 -> 1 (normal)
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["track4Button"].tap()           // 0 -> 1
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["track4Button"].tap()           // 1 -> 2 (inverted)
        Thread.sleep(forTimeInterval: 0.4)
        selectPicker(app, picker: "paramPicker", option: "pan")
        selectPicker(app, picker: "wavePicker", option: "sine")
        bumpRate(app, by: 2)  // index 5 -> 7 (displayed "2")
        scrub(app, identifier: "centerScrub", to: 50)
        scrub(app, identifier: "depthScrub", to: 30)
        app.buttons["repeatButton"].tap()
        sleep(2)

        // 2. Active chips — t1·vol·squ alongside t2/t4·pan·sine
        try save("02_chips_active")

        // 3. Help screen
        helpButton.tap()
        XCTAssertTrue(app.navigationBars["help"].waitForExistence(timeout: 5))
        try save("03_help")
        app.buttons["done"].tap()
        Thread.sleep(forTimeInterval: 0.3)

        // 4. Settings screen
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["settings"].waitForExistence(timeout: 5))
        try save("04_settings")
        app.buttons["done"].tap()
    }

    // MARK: - Helpers

    private func save(_ name: String) throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try FileManager.default.createDirectory(atPath: "/tmp/claude-ss", withIntermediateDirectories: true)
        let path = "/tmp/claude-ss/ss_\(device)_\(name).png"
        let raw = XCUIScreen.main.screenshot()
        try raw.pngRepresentation.write(to: URL(fileURLWithPath: path))
    }

    private func selectPicker(_ app: XCUIApplication, picker: String, option: String) {
        app.buttons[picker].tap()
        let opt = app.buttons[option]
        XCTAssertTrue(opt.waitForExistence(timeout: 3))
        opt.tap()
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func bumpRate(_ app: XCUIApplication, by steps: Int) {
        let btn = app.buttons["rateStepButton"]
        for _ in 0..<steps {
            btn.tap()
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    private func scrub(_ app: XCUIApplication, identifier: String, to target: Int, sensitivity: Double = 0.15) {
        let el = app.otherElements[identifier]
        XCTAssertTrue(el.waitForExistence(timeout: 3))
        let fudge: CGFloat = 4
        for _ in 0..<8 {
            guard let valueStr = el.value as? String, let current = Int(valueStr) else { break }
            let delta = current - target
            if delta == 0 { break }
            let rawDh = CGFloat(Double(delta) / sensitivity)
            let dh = rawDh + (delta > 0 ? fudge : -fudge)
            let start = el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: dh))
            start.press(forDuration: 0.1, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}
