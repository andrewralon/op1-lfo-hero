import XCTest

// Demo test designed for recording as an App Store Preview video.
// Run on a fresh simulator (or any device — --uitest-reset clears saved state).
// The test forces portrait orientation. Record with:
//   xcrun simctl io <udid> recordVideo --codec h264 /tmp/claude-ss/preview.mov
// then immediately run this test. Stop recording with Ctrl+C (SIGINT) when done.
final class AppPreviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - App Store Preview demo
    //
    // Scene 1: App launches. Dark UI: 4 track strips, waveform view, LFO controls.
    //
    // Scene 2: Build chip 1 — track 1 · volume · square · speed 4 · center 90 · depth 10.
    //          Tap repeat (↻) — chip appears: t1·vol·squ·s4·90±10·↻
    //
    // Scene 3: Turn track 1 off. Enable track 2 (normal) and track 4 (inverted).
    //          Switch to pan · sine · speed 2 · center 50 · depth 30.
    //          Tap repeat (↻) — two chips appear (t2 normal, t4 inverted pan/sine),
    //          pans sweep in opposite directions. Hold a few seconds to show the motion.

    @MainActor func testAppPreviewDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launch()

        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 10))
        sleep(2)

        // Scene 1: Initial state
        try snapshot("01_launch", app: app)

        // Scene 2: Chip 1 — track 1, volume, square, speed 4, center 80, depth 10
        // After --uitest-reset, trackOn defaults to [1:1, ...] so track 1 is already ON (state 1 = normal).
        // param defaults to "volume" — no picker tap needed
        selectPicker(app, picker: "wavePicker", option: "square")
        bumpRate(app, by: 2)                        // index 3 -> 5 (displayed "4")
        // center defaults to 90 — no scrub needed
        scrub(app, identifier: "depthScrub", to: 10)
        try snapshot("02_chip1_configured", app: app)

        app.buttons["repeatButton"].tap()
        sleep(2)
        try snapshot("03_chip1_created", app: app)

        // Scene 3: Track 1 off, track 2 normal, track 4 inverted, pan, sine, speed 2, center 50, depth 30
        // Track 1 is at state 1 (on, normal) — cycle 1→2→0 to turn it off.
        app.buttons["track1Button"].tap()          // 1 -> 2 (inverted)
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["track1Button"].tap()          // 2 -> 0 (off)
        Thread.sleep(forTimeInterval: 0.5)

        app.buttons["track2Button"].tap()          // 0 -> 1 (on, normal)
        Thread.sleep(forTimeInterval: 0.5)

        app.buttons["track4Button"].tap()          // 0 -> 1 (on)
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["track4Button"].tap()          // 1 -> 2 (inverted)
        Thread.sleep(forTimeInterval: 0.5)

        selectPicker(app, picker: "paramPicker", option: "pan")
        selectPicker(app, picker: "wavePicker", option: "sine")
        bumpRate(app, by: 2)                        // index 5 -> 7 (displayed "2")
        scrub(app, identifier: "centerScrub", to: 50)
        scrub(app, identifier: "depthScrub", to: 30)
        try snapshot("04_chip2_configured", app: app)

        app.buttons["repeatButton"].tap()
        sleep(6)
        try snapshot("05_chip2_created", app: app)
    }

    // MARK: - Helpers

    @MainActor private func snapshot(_ name: String, app: XCUIApplication) throws {
        let raw = XCUIScreen.main.screenshot()
        let image = Snapshot.fixLandscapeOrientation(image: raw.image)
        let path = "/tmp/claude-ss/apppreview_\(name).png"
        try image.pngData()?.write(to: URL(fileURLWithPath: path))
    }

    @MainActor private func selectPicker(_ app: XCUIApplication, picker: String, option: String) {
        app.buttons[picker].tap()
        let opt = app.buttons[option]
        XCTAssertTrue(opt.waitForExistence(timeout: 3))
        opt.tap()
        Thread.sleep(forTimeInterval: 0.3)
    }

    // The rate stepper button increments app.lfoRate by 1 per tap (wraps 25 -> 1).
    @MainActor private func bumpRate(_ app: XCUIApplication, by steps: Int) {
        let btn = app.buttons["rateStepButton"]
        for _ in 0..<steps {
            btn.tap()
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    // ScrubValue has no direct-entry API — only a vertical drag gesture. Reads the
    // current displayed value via accessibilityValue, computes the drag distance
    // needed (gesture maps dh * sensitivity = delta, dragging down decreases value),
    // and re-reads/corrects up to a few times to land exactly on target.
    //
    // Extra 4pt fudge: DragGesture(minimumDistance:2) drops the first onChanged
    // delta (it establishes prevHeight and returns), so ~3-4pt of drag is lost.
    // Without fudge, 1-unit corrections (≈6.7pt) never converge.
    @MainActor private func scrub(_ app: XCUIApplication, identifier: String, to target: Int, sensitivity: Double = 0.15) {
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
