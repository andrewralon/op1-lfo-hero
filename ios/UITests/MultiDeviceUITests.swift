import XCTest

/// Multi-device UI: track strips, the target-button row and the parameter picker all come
/// from the active `DeviceProfile`, so these drive each profile and check the layout adapts.
///
/// `--uitest-profile <id>` pins the device, so none of this needs hardware attached.
final class MultiDeviceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try ScreenshotDir.ensureExists()
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
        XCTAssertTrue(tp7.buttons["gain 1"].waitForExistence(timeout: 3), "tp-7 has per-jack input gain")
        XCTAssertFalse(tp7.buttons["eq high"].exists, "tp-7 has no eq")
    }

    // MARK: - OP-1 global controls

    /// The OP-1's rec level, master EQ, sustain and pitch bend are global: each is offered in the
    /// picker, forces the master (m) target, and the ones with a neutral point start their centre
    /// A long picker list must show a scroll bar the moment it opens (the system one only appears
    /// while scrolling), and a short list that fits must not draw one.
    @MainActor func testPickerShowsAScrollBarOnlyWhenTheListOverflows() throws {
        let app = launch(profile: "op1")
        let thumb = app.descendants(matching: .any)["pickerScrollThumb"]

        let params = app.buttons["paramPicker"]
        XCTAssertTrue(params.waitForExistence(timeout: 5))
        params.tap()
        XCTAssertTrue(app.buttons["rec level"].waitForExistence(timeout: 3))
        sleep(1)
        try shot(app, "picker_scrollbar")
        XCTAssertTrue(thumb.waitForExistence(timeout: 3), "the long parameter list must show a scroll bar")
        app.buttons["rec level"].tap()

        let waves = app.buttons["wavePicker"]
        XCTAssertTrue(waves.waitForExistence(timeout: 3))
        waves.tap()
        XCTAssertTrue(app.buttons["sine"].waitForExistence(timeout: 3))
        XCTAssertFalse(thumb.exists, "a list that fits has nothing to scroll, so no bar")
    }

    // MARK: - Waveform: the LFO being edited vs the running LFOs

    /// "editor" while the waveform draws the editor's own curve, "running" while it draws the
    /// chips that are running.
    @MainActor private func waveformMode(_ app: XCUIApplication) -> String? {
        app.descendants(matching: .any)["waveform"].value as? String
    }

    @MainActor func testWaveformShowsRunningLfosUnlessYouAreEditing() throws {
        let app = launch(profile: "op1")
        XCTAssertEqual(waveformMode(app), "editor", "nothing running: the editor curve, not an empty box")

        app.buttons["repeatButton"].tap()
        XCTAssertEqual(waveformMode(app), "running", "a running LFO is shown")

        // Changing a setting starts a draft: the curve you are shaping, not the running chip.
        app.buttons["wavePicker"].tap()
        app.buttons["square"].tap()
        XCTAssertEqual(waveformMode(app), "editor")

        // Tapping the empty chip area accepts the draft; back to what is running.
        app.descendants(matching: .any)["lfoChipArea"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        XCTAssertEqual(waveformMode(app), "running")

        // Preview is editing too.
        app.buttons["previewButton"].tap()
        XCTAssertEqual(waveformMode(app), "editor")
        app.buttons["previewButton"].tap()
        XCTAssertEqual(waveformMode(app), "running")

        // A selected chip is the LFO being edited; committing it returns to the running ones.
        let chip = app.descendants(matching: .any)["lfoChip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
        chip.press(forDuration: 0.8)
        XCTAssertEqual(waveformMode(app), "editor")
        chip.press(forDuration: 0.8)
        XCTAssertEqual(waveformMode(app), "running", "committing a chip edit is not a draft")
    }

    /// A paused chip is not drawn, so with only that one the waveform falls back to the editor.
    @MainActor func testWaveformLeavesOutAPausedLfo() throws {
        let app = launch(profile: "op1")
        app.buttons["repeatButton"].tap()
        XCTAssertEqual(waveformMode(app), "running")
        app.descendants(matching: .any)["lfoChip"].firstMatch.tap()    // tap pauses it
        XCTAssertEqual(waveformMode(app), "editor")
        app.descendants(matching: .any)["lfoChip"].firstMatch.tap()    // and again resumes it
        XCTAssertEqual(waveformMode(app), "running")
    }

    // MARK: - Picker interaction: tap opens, drag scrubs

    /// Drags `element` vertically by `dy` points (negative = up) from its centre.
    @MainActor private func drag(_ element: XCUIElement, dy: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// The speed box opens its 25-item list on a tap, like the param and wave boxes, and the
    /// list is long enough to need the always-visible scroll bar.
    @MainActor func testTappingTheSpeedBoxOpensTheListWithAScrollBar() throws {
        let app = launch(profile: "op1")
        let rate = app.descendants(matching: .any)["rateScrub"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap()

        XCTAssertTrue(app.buttons["f17"].waitForExistence(timeout: 3) || app.buttons["f1"].waitForExistence(timeout: 3),
                      "the speed list must open")
        let thumb = app.descendants(matching: .any)["pickerScrollThumb"]
        XCTAssertTrue(thumb.waitForExistence(timeout: 3), "25 speeds overflow the popover, so a bar shows")

        let list = app.scrollViews.containing(.button, identifier: "8").firstMatch
        var tries = 0
        while !app.buttons["f17"].isHittable && tries < 10 && list.exists { list.swipeUp(); tries += 1 }
        app.buttons["f17"].tap()
        XCTAssertEqual(rate.value as? String, "f17", "picking from the list sets the speed")
    }

    /// Centre and depth are values to drag, not lists: a tap does nothing.
    @MainActor func testTappingCenterOrDepthOpensNothing() throws {
        let app = launch(profile: "op1")
        for id in ["centerScrub", "depthScrub"] {
            let box = app.descendants(matching: .any)[id]
            XCTAssertTrue(box.waitForExistence(timeout: 5))
            let before = box.value as? String
            box.tap()
            sleep(1)
            XCTAssertFalse(app.descendants(matching: .any)["pickerScrollThumb"].exists, id)
            XCTAssertFalse(app.buttons["f1"].exists, "\(id) must not open a list")
            XCTAssertEqual(box.value as? String, before, id)
        }
    }

    /// A drag on the wave box steps through the shapes; up goes to later ones, as on the speed box.
    @MainActor func testDraggingTheWaveBoxStepsThroughTheShapes() throws {
        let app = launch(profile: "op1")
        let waves = app.buttons["wavePicker"]
        XCTAssertTrue(waves.waitForExistence(timeout: 5))
        let first = waves.label
        drag(waves, dy: -70)
        XCTAssertNotEqual(waves.label, first, "dragging up must move to another shape")
        drag(waves, dy: 70)
        XCTAssertEqual(waves.label, first, "and dragging back down returns to where it began")
    }

    /// The center box follows the parameter you let go on, not the ones passed over on the way.
    @MainActor func testDraggingTheParamBoxRecentresOnTheOneYouLandOn() throws {
        let app = launch(profile: "op1")
        let params = app.buttons["paramPicker"]
        let center = app.descendants(matching: .any)["centerScrub"]
        XCTAssertTrue(params.waitForExistence(timeout: 5))
        XCTAssertEqual(center.value as? String, "90")

        // Pitch bend is the last item, so enough upward drags land on it (and stay: it is clamped).
        var tries = 0
        while params.label != "pitch bend" && tries < 6 { drag(params, dy: -300); tries += 1 }
        XCTAssertEqual(params.label, "pitch bend")
        XCTAssertEqual(center.value as? String, "49", "released on bend: center jumps to bend's rest")

        // Back out past the EQ and sustain (which also centre at 49 or not at all) to a plain one.
        tries = 0
        while params.label == "pitch bend" || (center.value as? String) == "49" {
            drag(params, dy: 300); tries += 1
            if tries >= 6 { break }
        }
        XCTAssertEqual(center.value as? String, "90", "released on a plain parameter: back to the default")
    }

    /// on it. The simulator has no MIDI, so this checks the layout and the state only.
    @MainActor func testOP1GlobalControlsAreOfferedAndForceTheMasterTarget() throws {
        let app = launch(profile: "op1")
        let cases: [(name: String, centre: String?)] = [
            ("rec level", "74"), ("eq low", "49"), ("eq mid", "49"),
            ("eq high", "49"), ("sustain", nil), ("pitch bend", "49"),
        ]
        for c in cases {
            let picker = app.buttons["paramPicker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            let option = app.buttons[c.name]
            XCTAssertTrue(option.waitForExistence(timeout: 3), "'\(c.name)' must be in the OP-1's picker")
            let list = app.scrollViews.containing(.button, identifier: c.name).firstMatch
            var tries = 0
            while !option.isHittable && tries < 15 && list.exists { list.swipeUp(); tries += 1 }
            XCTAssertTrue(option.isHittable, "'\(c.name)' must be reachable by scrolling")
            option.tap()

            XCTAssertTrue(app.buttons["masterButton"].isEnabled, "\(c.name) targets master")
            for t in 1...4 {
                XCTAssertFalse(app.buttons["track\(t)Button"].isEnabled,
                               "\(c.name) is global, so track \(t) must not be selectable")
            }
            if let centre = c.centre {
                let value = app.descendants(matching: .any)["centerScrub"].value as? String
                XCTAssertEqual(value, centre, "\(c.name): a new LFO must start centred on its neutral point")
            }
            if c.name == "pitch bend" { try shot(app, "op1_bend_live") }
        }
    }

    // MARK: - Slaved to a clock that never arrives

    /// Switching the clock source to a device that isn't sending clock freezes every LFO. The
    /// only sign used to be a small "no clk" in the BPM box; the LFO panel now says so, and a tap
    /// switches to the app's clock. No MIDI in the simulator, so the clock never arrives.
    @MainActor func testLfosWaitingForClockAreFlaggedWhereTheLfosAre() throws {
        let app = launch(profile: "op1")
        let banner = app.buttons["clockWaitingBanner"]
        XCTAssertFalse(banner.exists, "app is the clock: nothing to wait for")

        app.buttons["repeatButton"].tap()                       // a running LFO chip
        app.buttons["tempoModeButton"].tap()                    // slave to the op-1's clock
        XCTAssertTrue(banner.waitForExistence(timeout: 6), "slaved, LFOs running, no clock")
        try shot(app, "lfo_waiting_for_clock")

        banner.tap()                                            // use the app clock
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: banner)
        waitForExpectations(timeout: 4)
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
