import XCTest

/// The first-run tutorial. `--uitest-reset` keeps it out of every other UI test;
/// `--uitest-tour` forces it back on here.
final class TourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try ScreenshotDir.ensureExists()
    }

    @MainActor
    private func launch(_ args: [String], orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    /// A fresh launch with the tour forced on, waiting until its first card is up.
    @MainActor
    private func launchTour(profile: String = "op1",
                            orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
        let app = launch(["--uitest-reset", "--uitest-tour", "--uitest-profile", profile],
                         orientation: orientation)
        XCTAssertTrue(app.otherElements["tourCard"].waitForExistence(timeout: 8))
        return app
    }

    /// Taps next and waits for the counter to move on, so a tap can't land while the card is
    /// still sliding to its new spot. Fails naming the step that didn't advance.
    @MainActor
    private func tapNext(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let from = counter(app).0
        let title = app.staticTexts["tourTitle"].label
        app.buttons["tourNextButton"].tap()
        let moved = NSPredicate { _, _ in
            !app.otherElements["tourCard"].exists || self.counter(app).0 != from
        }
        let done = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 3) == .completed
        XCTAssertTrue(done, "next didn't advance from step \(from) (\(title))", file: file, line: line)
    }

    /// "3/16" → ("3", "16").
    private func counter(_ app: XCUIApplication) -> (String, String) {
        let parts = app.staticTexts["tourCounter"].label.components(separatedBy: "/")
        return (parts.first ?? "", parts.last ?? "")
    }

    // MARK: - Buttons

    @MainActor func testNextThroughToDoneThenGoneOnRelaunch() throws {
        let app = launchTour()
        let total = Int(counter(app).1) ?? 0
        XCTAssertGreaterThan(total, 1)
        for _ in 1 ..< total { tapNext(app) }
        XCTAssertEqual(app.buttons["tourNextButton"].label, "done")
        app.buttons["tourNextButton"].tap()
        XCTAssertFalse(app.otherElements["tourCard"].waitForExistence(timeout: 1))

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.buttons["helpButton"].waitForExistence(timeout: 8))
        XCTAssertFalse(again.otherElements["tourCard"].waitForExistence(timeout: 3))
    }

    @MainActor func testLaterComesBackAtTheSameStep() throws {
        let app = launchTour()
        tapNext(app)
        tapNext(app)
        XCTAssertEqual(counter(app).0, "3")
        app.buttons["tourLaterButton"].tap()
        XCTAssertFalse(app.otherElements["tourCard"].waitForExistence(timeout: 1))

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.otherElements["tourCard"].waitForExistence(timeout: 8))
        XCTAssertEqual(counter(again).0, "3")
    }

    @MainActor func testWelcomeThenBack() throws {
        let app = launchTour()
        XCTAssertEqual(app.staticTexts["tourTitle"].label, "welcome")
        XCTAssertEqual(app.buttons["tourNextButton"].label, "next")
        XCTAssertFalse(app.buttons["tourBackButton"].isEnabled, "nothing before the first step")
        tapNext(app)
        tapNext(app)
        XCTAssertEqual(counter(app).0, "3")
        app.buttons["tourBackButton"].tap()
        XCTAssertEqual(counter(app).0, "2")
    }

    @MainActor func testSkipStaysGone() throws {
        let app = launchTour()
        app.buttons["tourSkipButton"].tap()
        XCTAssertFalse(app.otherElements["tourCard"].waitForExistence(timeout: 1))

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.buttons["helpButton"].waitForExistence(timeout: 8))
        XCTAssertFalse(again.otherElements["tourCard"].waitForExistence(timeout: 3))
    }

    @MainActor func testReplayFromSettingsRestartsAtStepOne() throws {
        let app = launch(["--uitest-reset"])
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let replay = app.buttons["replayTourButton"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.otherElements["tourCard"].waitForExistence(timeout: 5))
        XCTAssertEqual(counter(app).0, "1")
    }

    // MARK: - Device profile

    @MainActor func testTP7HasNoPanStep() throws {
        let op1 = launchTour(profile: "op1")
        let op1Total = Int(counter(op1).1) ?? 0
        op1.terminate()

        let tp7 = launchTour(profile: "tp7")
        XCTAssertEqual(Int(counter(tp7).1), op1Total - 1)
        // Step 4 on the OP-1 is pan (welcome, status bar, mute, pan); the TP-7 goes straight
        // to volume.
        for _ in 1...3 { tapNext(tp7) }
        XCTAssertEqual(tp7.staticTexts["tourTitle"].label, "volume")
    }

    /// No device connected and none picked in settings: the app only *remembers* a device, so the
    /// tour keeps every step and talks about "the device" instead of naming one.
    @MainActor func testNoKnownDeviceGetsNeutralTour() throws {
        let app = launch(["--uitest-reset", "--uitest-tour"])
        XCTAssertTrue(app.otherElements["tourCard"].waitForExistence(timeout: 8))
        XCTAssertEqual(counter(app).1, "20")
        while app.staticTexts["tourTitle"].label != "transport" { tapNext(app) }
        let body = app.otherElements["tourCard"].staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'the device'")).firstMatch
        XCTAssertTrue(body.exists, "transport hint should say \"the device\", not a model name")
    }

    // MARK: - No MIDI under the tour

    /// The overlay swallows every touch: a tap on the spotlit mute pad must not mute it.
    @MainActor func testTourBlocksTouchesOnControls() throws {
        // Find the mute pad and its state with no tour up; the layout is the same next launch.
        let plain = launch(["--uitest-reset", "--uitest-profile", "op1"])
        let mute = plain.buttons["muteButton1"]
        XCTAssertTrue(mute.waitForExistence(timeout: 8))
        let frame = mute.frame
        let before = mute.value as? String
        plain.terminate()

        let app = launchTour()
        tapNext(app)     // welcome → status bar
        tapNext(app)     // step 3: the mute pad is spotlit
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
        XCTAssertEqual(counter(app).0, "3", "the tap must not move the tour either")
        app.buttons["tourSkipButton"].tap()

        let after = app.buttons["muteButton1"]
        XCTAssertTrue(after.waitForExistence(timeout: 3))
        XCTAssertEqual(after.value as? String, before)
    }

    // MARK: - Screenshots

    /// Every step, for checking card placement near the screen edges. Run on an iPhone and an
    /// iPad simulator; files land in /tmp/claude-ss/tour_<device>_<orientation>_<n>.png.
    @MainActor func testScreenshotEveryStepPortrait() throws { try screenshotEveryStep(.portrait) }
    @MainActor func testScreenshotEveryStepLandscape() throws { try screenshotEveryStep(.landscapeLeft) }

    @MainActor private func screenshotEveryStep(_ orientation: UIDeviceOrientation) throws {
        let app = launchTour(orientation: orientation)
        let landscape = orientation.isLandscape
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        let total = Int(counter(app).1) ?? 0
        for n in 1 ... total {
            sleep(1)    // let the card finish moving
            let raw = XCUIScreen.main.screenshot()
            let path = "/tmp/claude-ss/tour_\(device)_\(landscape ? "landscape" : "portrait")_\(n).png"
            if landscape {
                try Snapshot.fixLandscapeOrientation(image: raw.image).pngData()?
                    .write(to: URL(fileURLWithPath: path))
            } else {
                try raw.pngRepresentation.write(to: URL(fileURLWithPath: path))
            }
            if n < total { tapNext(app) } else { app.buttons["tourNextButton"].tap() }
        }
    }
}
