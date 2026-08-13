import XCTest

/// Multi-device UI: track strips, the target-button row and the parameter picker all come
/// from the active `DeviceProfile`, so these drive each profile and check the layout adapts.
///
/// `--uitest-profile <id>` pins the device, so none of this needs hardware attached.
final class MultiDeviceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(profile: String, orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-profile", profile]
        app.launch()
        XCTAssertTrue(app.buttons["helpButton"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String, landscape: Bool = false) throws {
        let raw = XCUIScreen.main.screenshot()
        let path = "/tmp/claude-ss/\(name).png"
        if landscape {
            let image = Snapshot.fixLandscapeOrientation(image: raw.image)
            try image.pngData()?.write(to: URL(fileURLWithPath: path))
        } else {
            try raw.pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Track count

    @MainActor func testOP1ShowsFourTracks() throws {
        let app = launch(profile: "op1")
        for t in 1...4 {
            XCTAssertTrue(app.buttons["track\(t)Button"].exists, "track \(t) should exist on op-1")
        }
        XCTAssertFalse(app.buttons["track5Button"].exists, "op-1 has no track 5")
        XCTAssertFalse(app.buttons["track6Button"].exists, "op-1 has no track 6")
    }

    @MainActor func testTX6ShowsSixTracks() throws {
        let app = launch(profile: "tx6")
        for t in 1...6 {
            XCTAssertTrue(app.buttons["track\(t)Button"].exists, "track \(t) should exist on tx-6")
        }
        XCTAssertTrue(app.buttons["masterButton"].exists)
        XCTAssertTrue(app.buttons["previewButton"].exists)
    }

    @MainActor func testTP7ShowsSixTracks() throws {
        let app = launch(profile: "tp7")
        for t in 1...6 {
            XCTAssertTrue(app.buttons["track\(t)Button"].exists, "track \(t) should exist on tp-7")
        }
    }

    /// Every target button must still meet Apple's 44pt minimum after wrapping to two rows.
    @MainActor func testSixTrackToggleButtonsMeetMinimumTouchTarget() throws {
        let app = launch(profile: "tx6")
        for id in (1...6).map({ "track\($0)Button" }) + ["masterButton", "previewButton"] {
            let f = app.buttons[id].frame
            XCTAssertGreaterThanOrEqual(f.width, 43.0, "\(id) width \(f.width)")
            XCTAssertGreaterThanOrEqual(f.height, 43.0, "\(id) height \(f.height)")
        }
    }

    /// Nothing may be pushed off-screen by the extra columns.
    @MainActor func testSixTrackLayoutStaysOnScreen() throws {
        let app = launch(profile: "tx6")
        let screen = app.frame
        for id in (1...6).map({ "track\($0)Button" }) + ["masterButton", "previewButton"] {
            let f = app.buttons[id].frame
            XCTAssertGreaterThanOrEqual(f.minX, -0.5, "\(id) starts off the left edge")
            XCTAssertLessThanOrEqual(f.maxX, screen.width + 0.5, "\(id) runs past the right edge")
        }
    }

    // MARK: - Capabilities

    /// The TP-7 is a recorder with no pan, so the knob is hidden and the fader takes the space.
    @MainActor func testTP7HidesPanKnobButOP1ShowsIt() throws {
        let op1 = launch(profile: "op1")
        XCTAssertTrue(op1.otherElements["panKnob1"].exists || op1.images["panKnob1"].exists
                      || op1.descendants(matching: .any)["panKnob1"].exists,
                      "op-1 should show a pan knob")
        op1.terminate()

        let tp7 = launch(profile: "tp7")
        XCTAssertFalse(tp7.descendants(matching: .any)["panKnob1"].exists,
                       "tp-7 has no pan and must not show the knob")
    }

    // MARK: - Parameter picker

    /// The regression test for the popover-scroll bug: the TX-6's list is ~33 items, and
    /// before the fix the tail was unreachable in portrait.
    @MainActor func testTX6ParamPickerReachesLastItemInPortrait() throws {
        let app = launch(profile: "tx6")
        let picker = app.buttons["paramPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        let last = app.buttons["fx2 track"]
        XCTAssertTrue(last.waitForExistence(timeout: 3), "last parameter must be in the picker")
        // Scroll until it is actually on screen and tappable.
        // Pick the popover's own scroll view — the LFO chip list is also a scroll view,
        // and `firstMatch` finds that one instead.
        let list = app.scrollViews.containing(.button, identifier: "eq high").firstMatch
        XCTAssertTrue(list.exists, "the parameter list should be scrollable")
        var tries = 0
        while !last.isHittable && tries < 15 {
            list.swipeUp()
            tries += 1
        }
        XCTAssertTrue(last.isHittable, "last parameter must be reachable by scrolling")
        last.tap()
        XCTAssertTrue(app.buttons["paramPicker"].waitForExistence(timeout: 3))
    }

    /// Parameter names come from the profile, so each device shows its own vocabulary.
    @MainActor func testEachDeviceShowsItsOwnParameters() throws {
        let tx6 = launch(profile: "tx6")
        tx6.buttons["paramPicker"].tap()
        XCTAssertTrue(tx6.buttons["eq high"].waitForExistence(timeout: 3), "tx-6 has an eq")
        XCTAssertFalse(tx6.buttons["par 1"].exists, "tx-6 has no op-1 synth params")
        tx6.terminate()

        let tp7 = launch(profile: "tp7")
        tp7.buttons["paramPicker"].tap()
        XCTAssertTrue(tp7.buttons["input gain"].waitForExistence(timeout: 3), "tp-7 has input gain")
        XCTAssertFalse(tp7.buttons["eq high"].exists, "tp-7 has no eq")
    }

    // MARK: - Device switching

    /// Switching devices and back must not lose the first device's chips — per-device state
    /// is banked rather than reset.
    @MainActor func testChipsSurviveDeviceRoundTrip() throws {
        let app = launch(profile: "op1")
        app.buttons["repeatButton"].tap()          // create a looping LFO chip
        sleep(1)

        selectDevice(app, "tx-6")
        XCTAssertTrue(app.buttons["track6Button"].waitForExistence(timeout: 5),
                      "should now be on the 6-track tx-6")

        selectDevice(app, "op-1 field")

        XCTAssertFalse(app.buttons["track5Button"].exists, "back to the 4-track op-1")
        XCTAssertTrue(app.buttons["trashButton"].isEnabled,
                      "the op-1's chip should have come back with it")
    }

    /// Open settings and pick a device. A segmented-control tap made while the sheet is still
    /// animating in is silently dropped by UIKit, so this confirms the selection actually took
    /// and retries if it did not.
    @MainActor
    private func selectDevice(_ app: XCUIApplication, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["settingsButton"].tap()
        let picker = app.segmentedControls["deviceOverridePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "settings did not open", file: file, line: line)

        let segment = picker.buttons[label]
        var tries = 0
        while !segment.isSelected && tries < 5 {
            sleep(1)
            segment.tap()
            tries += 1
        }
        XCTAssertTrue(segment.isSelected, "could not select '\(label)'", file: file, line: line)

        app.buttons["done"].tap()
        sleep(2)
    }

    // MARK: - Screenshots

    @MainActor func testTX6PortraitScreenshot() throws {
        let app = launch(profile: "tx6")
        sleep(1)
        try shot(app, "tx6_portrait")
    }

    @MainActor func testTX6LandscapeScreenshot() throws {
        let app = launch(profile: "tx6", orientation: .landscapeLeft)
        sleep(1)
        try shot(app, "tx6_landscape", landscape: true)
    }

    @MainActor func testTP7PortraitScreenshot() throws {
        let app = launch(profile: "tp7")
        sleep(1)
        try shot(app, "tp7_portrait")
    }
}
