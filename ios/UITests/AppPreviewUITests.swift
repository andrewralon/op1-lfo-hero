import XCTest

// Demo test designed for recording as an App Store Preview video (OP-1 Field, 4 tracks).
// App Store Connect wants 15-30 s, max 30 fps, H.264, 886x1920 for the large iPhone sizes.
// Rotate nothing: the demo is portrait. Record with:
//   xcrun simctl io <udid> recordVideo --codec h264 /tmp/claude-ss/preview.mov
// run this test, then stop the recording with Ctrl+C (SIGINT). The recording starts before the
// app launches, so trim the lead-in with ffmpeg (see CLAUDE.md).
//
// One continuous take, paced so every change is visible before the next one starts:
//   Scene 1: track 1 · volume · square · depth 10 → repeat. A chip appears.
//   Scene 2: track 2 on, track 4 inverted · pan · sine · depth 30 → repeat. Chips appear for
//            tracks 1 + 2 + 4 and the pans sweep in opposite directions.
//   Final:   a long hold with nothing changing, so the end state can be read.
final class AppPreviewUITests: XCTestCase {

    /// Gap after each action, so the viewer sees what just changed. Everything is multiplied by
    /// this; raise it to slow the whole demo down, lower it to speed it up.
    private let pace = 0.7
    private let finalHold: TimeInterval = 6

    override func setUpWithError() throws {
        continueAfterFailure = false
        try ScreenshotDir.ensureExists()
    }

    @MainActor func testAppPreviewDemo() throws {
        let app = XCUIApplication()
        // --uitest-spoof-connected: the simulator has no Bluetooth, so show an OP-1 Field on BLE.
        app.launchArguments = ["--uitest-reset", "--uitest-profile", "op1", "--uitest-spoof-connected"]
        app.launch()

        XCTAssertTrue(app.buttons["helpButton"].waitForExistence(timeout: 10))
        beat(2.0)                                   // the starting screen, untouched

        // Scene 1: chip 1 — track 1 (already on), volume (default), square, depth 10
        selectPicker(app, picker: "wavePicker", option: "square")
        scrub(app, identifier: "depthScrub", to: 10)
        beat(0.8)
        app.buttons["repeatButton"].tap()
        beat(2.0)                                   // chip 1 running

        // Scene 2: chip 2 — tracks 1 + 2 normal, track 4 inverted · pan · sine · depth 30
        app.buttons["track2Button"].tap()           // off -> normal
        beat(0.8)
        app.buttons["track4Button"].tap()           // off -> normal
        beat(0.6)
        app.buttons["track4Button"].tap()           // normal -> inverted
        beat(0.9)
        selectPicker(app, picker: "paramPicker", option: "pan")
        selectPicker(app, picker: "wavePicker", option: "sine")
        scrub(app, identifier: "depthScrub", to: 30)
        beat(0.8)
        app.buttons["repeatButton"].tap()

        // Final state: no taps, nothing changes except the LFOs running.
        Thread.sleep(forTimeInterval: finalHold)
        try snapshot("final_state", app: app)
    }

    // MARK: - Helpers

    @MainActor private func snapshot(_ name: String, app: XCUIApplication) throws {
        let raw = XCUIScreen.main.screenshot()
        let image = Snapshot.fixLandscapeOrientation(image: raw.image)
        let path = "/tmp/claude-ss/apppreview_\(name).png"
        try image.pngData()?.write(to: URL(fileURLWithPath: path))
    }

    /// A pause long enough to read the screen, scaled by `pace`.
    private func beat(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds * pace) }

    @MainActor private func selectPicker(_ app: XCUIApplication, picker: String, option: String) {
        app.buttons[picker].tap()
        let opt = app.buttons[option]
        XCTAssertTrue(opt.waitForExistence(timeout: 3))
        beat(0.8)                                   // the open list stays on screen
        opt.tap()
        beat(0.8)
    }

    // The rate stepper button increments app.lfoRate by 1 per tap (wraps 25 -> 1).
    @MainActor private func bumpRate(_ app: XCUIApplication, by steps: Int) {
        let btn = app.buttons["rateStepButton"]
        for _ in 0..<steps {
            btn.tap()
            beat(0.7)
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
            Thread.sleep(forTimeInterval: 0.15)
        }
    }
}
