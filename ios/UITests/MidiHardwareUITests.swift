import XCTest

/// Hardware-only. Requires a physical iPad/iPhone with an OP-1 Field connected via USB-C.
/// Drives a real UI action and asserts on the *actual MIDI bytes* the OP-1 receives, via a
/// second CoreMIDI listener (MidiCapture) running inside this test process — closing the gap
/// left by RecordingDestination-based unit tests, which prove the app *would* produce correct
/// bytes but never touch real CoreMIDI plumbing. See "MIDI cannot be tested in the simulator"
/// in CLAUDE.md for why this can't run in the simulator, and why the listener has to live here
/// (on-device) rather than as a Mac-side tools/midi/ tool — the OP-1 is plugged into the iPad,
/// not the Mac.
///
/// Self-skips via XCTSkipUnless when no OP-1 source is present, so it's safe to include in a
/// full `xcodebuild test` run against a simulator or a bare device — it reports "skipped,"
/// never "failed."
///
/// Run:
///   xcrun xctrace list devices                      # find the physical device UDID
///   cd ios
///   xcodebuild test \
///     -project op1-lfo-hero.xcodeproj \
///     -scheme op1-lfo-hero \
///     -destination 'id=<physical-device-udid>' \
///     -only-testing:op1-lfo-heroUITests/MidiHardwareUITests/testTrack1MuteSendsCorrectCCBytes
final class MidiHardwareUITests: XCTestCase {

    private var capture: MidiCapture!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            MidiCapture.hasMatchingSource(nameTokens: ["op-1", "op1"]),
            "No OP-1 MIDI source found — connect an OP-1 Field via USB-C."
        )
        capture = MidiCapture()
        capture.start(nameTokens: ["op-1", "op1"])
    }

    override func tearDownWithError() throws {
        capture?.stop()
    }

    @MainActor
    func testTrack1MuteSendsCorrectCCBytes() throws {
        let app = XCUIApplication()
        // Deliberately NOT --uitest-profile: this exercises the app's real hardware
        // auto-detection against whatever's actually plugged in, not a pinned fake profile.
        app.launchArguments = ["--uitest-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["helpButton"].waitForExistence(timeout: 8))

        app.buttons["muteButton1"].tap()

        // OP-1 track 1 mute-on: DeviceProfiles.swift's mute ParamSpec is CC 9,
        // .trackRelative(offset: 0), .switching(SwitchEncoding()) — track 1 resolves to
        // channel 0, and mute-on always sends the fixed wire value 127.
        XCTAssertTrue(
            capture.waitForCC(channel: 0, cc: 9, value: 127, timeout: 5),
            "Expected [0xB0, 0x09, 0x7F] (track 1 mute-on) was not received by the hardware listener"
        )
    }
}
