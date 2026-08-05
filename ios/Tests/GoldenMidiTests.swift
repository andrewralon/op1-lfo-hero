import XCTest
@testable import op1_lfo_hero

/// A MidiDestination that records everything sent to it, so tests can assert the exact
/// wire bytes without hardware.
final class RecordingDestination: MidiDestination {
    private(set) var packets: [[UInt8]] = []
    var onClock: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?
    func send(_ bytes: [UInt8]) { packets.append(bytes) }
    func reset() { packets.removeAll() }
    /// The single packet emitted since the last reset — fails if zero or more than one.
    func only(_ file: StaticString = #filePath, _ line: UInt = #line) -> [UInt8] {
        XCTAssertEqual(packets.count, 1, "expected exactly one packet, got \(packets)",
                       file: file, line: line)
        return packets.first ?? []
    }
}

/// The OP-1 Field regression contract.
///
/// These tests pin the exact bytes the app puts on the wire for every parameter, track and
/// value, plus the 0-99 display-scale round trip. They exist so the multi-device
/// `DeviceProfile` refactor can be verified to change nothing for the OP-1: if a byte moves,
/// one of these fails. Do not "fix" a failure by updating the expectation — the expectations
/// ARE the spec. See notes/RESEARCH.md.
final class GoldenMidiTests: XCTestCase {

    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.op1Field)
    }

    // Representative values: rails, the mute/switch threshold either side, and the top pair.
    private static let probeValues = [0, 1, 63, 64, 126, 127]

    private func status(_ channel: Int) -> UInt8 { UInt8(0xB0 | (channel & 0x0F)) }

    /// Send one parameter by its profile id. Expectations below are literal wire bytes, so
    /// this indirection is the only thing that changed when the send path became profile-driven.
    private func send(_ id: String, track: Int, value: Int) {
        guard let spec = DeviceProfile.op1Field.param(id) else {
            return XCTFail("no such parameter '\(id)'")
        }
        ctrl.send(spec: spec, track: track, value: Double(value))
    }

    // MARK: - Per-track continuous parameters

    func testVolumeBytes() {
        for track in 1...4 {
            for v in Self.probeValues {
                destination.reset()
                send("volume", track: track, value: v)
                XCTAssertEqual(destination.only(), [status(track - 1), 7, UInt8(v)],
                               "volume track \(track) value \(v)")
            }
        }
    }

    func testPanBytes() {
        for track in 1...4 {
            for v in Self.probeValues {
                destination.reset()
                send("pan", track: track, value: v)
                XCTAssertEqual(destination.only(), [status(track - 1), 10, UInt8(v)],
                               "pan track \(track) value \(v)")
            }
        }
    }

    /// par/env are CC bases 46 and 50, track-relative, and are NOT master-capable today —
    /// track 0 clamps to channel 0 rather than switching CC bank.
    func testParAndEnvBytes() {
        for track in 1...4 {
            for param in 1...4 {
                destination.reset()
                send("par \(param)", track: track, value: 100)
                XCTAssertEqual(destination.only(), [status(track - 1), UInt8(46 + param - 1), 100],
                               "par \(param) track \(track)")

                destination.reset()
                send("env \(["A","D","S","R"][param - 1])", track: track, value: 100)
                XCTAssertEqual(destination.only(), [status(track - 1), UInt8(50 + param - 1), 100],
                               "env \(param) track \(track)")
            }
        }
    }

    // MARK: - Parameters with a separate master CC bank

    /// fx N: CC 54-57 per track, CC 70-73 (master fx) on track 0 — both on channel `track - 1`,
    /// clamped to 0 for master.
    func testFxBytesTrackAndMaster() {
        for param in 1...4 {
            for track in 1...4 {
                destination.reset()
                send("fx \(param)", track: track, value: 77)
                XCTAssertEqual(destination.only(), [status(track - 1), UInt8(54 + param - 1), 77],
                               "fx \(param) track \(track)")
            }
            destination.reset()
            send("fx \(param)", track: 0, value: 77)
            XCTAssertEqual(destination.only(), [0xB0, UInt8(70 + param - 1), 77],
                           "master fx \(param)")
        }
    }

    /// lfo N: CC 58-61 per track, CC 74-77 (master COMPRESSOR, not an LFO) on track 0.
    /// The master overload is intentional and long-standing — see CLAUDE.md.
    func testPatchLfoBytesTrackAndMaster() {
        for param in 1...4 {
            for track in 1...4 {
                destination.reset()
                send("lfo \(param)", track: track, value: 77)
                XCTAssertEqual(destination.only(), [status(track - 1), UInt8(58 + param - 1), 77],
                               "lfo \(param) track \(track)")
            }
            destination.reset()
            send("lfo \(param)", track: 0, value: 77)
            XCTAssertEqual(destination.only(), [0xB0, UInt8(74 + param - 1), 77],
                           "master comp \(param)")
        }
    }

    // MARK: - Mute

    /// Mute is CC 9 with a hard 127/0 encoding (not a pass-through value).
    func testMuteBytes() {
        for track in 1...4 {
            destination.reset()
            ctrl.setMute(track: track, on: true)
            XCTAssertEqual(destination.only(), [status(track - 1), 9, 127], "mute track \(track)")

            destination.reset()
            ctrl.setMute(track: track, on: false)
            XCTAssertEqual(destination.only(), [status(track - 1), 9, 0], "unmute track \(track)")
        }
    }

    /// `Controller` is stateless about mute — `AppState.mutes` is the only source of truth, so
    /// the same call twice must produce the same bytes twice rather than toggling.
    func testMuteIsStatelessInController() {
        destination.reset()
        ctrl.setMute(track: 2, on: true)
        ctrl.setMute(track: 2, on: true)
        XCTAssertEqual(destination.packets, [[0xB1, 9, 127], [0xB1, 9, 127]])
    }

    /// An LFO driving mute crosses the threshold rather than sending a continuous value.
    func testMuteLfoValuesSnapToOnOff() {
        for (input, expected) in [(0, 0), (63, 0), (64, 127), (127, 127)] {
            destination.reset()
            send("mute", track: 1, value: input)
            XCTAssertEqual(destination.only(), [0xB0, 9, UInt8(expected)], "mute lfo value \(input)")
        }
    }

    // MARK: - Clamping

    /// Out-of-range values are clamped to 0-127, never wrapped — a wrap would emit a byte
    /// with the high bit set and desync the receiver's running status.
    func testValuesAreClampedNotWrapped() {
        destination.reset()
        send("volume", track: 1, value: 300)
        XCTAssertEqual(destination.only(), [0xB0, 7, 127])

        destination.reset()
        send("volume", track: 1, value: -50)
        XCTAssertEqual(destination.only(), [0xB0, 7, 0])
    }

    /// Every emitted packet must be a well-formed 3-byte CC: status high bit set,
    /// data bytes clear. Guards against any future channel/value arithmetic overflowing.
    func testAllEmittedPacketsAreWellFormed() {
        for track in 1...4 {
            for v in Self.probeValues {
                send("volume", track: track, value: v)
                send("pan", track: track, value: v)
                send("fx 1", track: track, value: v)
            }
        }
        for param in 1...4 {
            send("fx \(param)", track: 0, value: 64)
            send("lfo \(param)", track: 0, value: 64)
        }
        XCTAssertFalse(destination.packets.isEmpty)
        for p in destination.packets {
            XCTAssertEqual(p.count, 3, "not a 3-byte CC: \(p)")
            XCTAssertEqual(p[0] & 0xF0, 0xB0, "not a CC status byte: \(p)")
            XCTAssertEqual(p[1] & 0x80, 0, "cc number has high bit set: \(p)")
            XCTAssertEqual(p[2] & 0x80, 0, "value has high bit set: \(p)")
        }
    }

    // MARK: - Octave

    func testOctaveBytes() {
        destination.reset()
        ctrl.octaveUp()
        XCTAssertEqual(destination.only(), [0xB0, 79, 127])

        destination.reset()
        ctrl.octaveDown()
        XCTAssertEqual(destination.only(), [0xB0, 79, 0])
    }
}

/// The OP-1 transport contract: MIDI start/continue/stop plus tape seeks that carry a Song
/// Position Pointer. Transport became profile-driven in this work, so these pin the bytes.
final class OP1TransportGoldenTests: XCTestCase {

    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.op1Field.transport
    }

    /// Play always sends Continue (0xFB) so the tape resumes where it left off — matching the
    /// hardware's own play button. Verified on a TP-7: 0xFA rewinds to zero, 0xFB resumes.
    /// The previous behaviour sent Start on the first play of a session, silently rewinding the
    /// user's tape once.
    func testPlayAlwaysContinues() {
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "the first play must not rewind the tape")

        clock.stop()
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]])
    }

    /// An explicit rewind arms Start (0xFA) for the next play only.
    func testRewindArmsStartForOnePlayOnly() {
        clock.rewindToStart()
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFA]], "after a rewind, play restarts from zero")

        clock.stop()
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "and reverts to resuming afterwards")
    }

    /// A rewind also zeroes the song position, so a later tape seek counts from the start.
    func testRewindResetsSongPosition() {
        clock.tapeNext(); clock.tapeNext()      // move to bar 2
        clock.rewindToStart()
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 16, 0]], "should count from zero")
    }

    func testStopSendsStopByte() {
        clock.play()
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xFC]])
    }

    /// Tape next: CC 83, then an SPP one bar (16 units) forward. Not playing → no resume.
    func testTapeNextSendsCCThenSongPosition() {
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 16, 0]])
    }

    /// Tape prev is CC 82 and clamps the song position at zero rather than going negative.
    func testTapePrevClampsAtZero() {
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 82, 127], [0xF2, 0, 0]])
    }

    func testTapeSeekAccumulatesSongPosition() {
        clock.tapeNext(); clock.tapeNext(); clock.tapeNext()
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 64, 0]], "4 bars = 64 SPP units")
    }

    /// Seeking while playing must resume, or the device sits paused at the new position.
    func testTapeSeekResumesWhilePlaying() {
        clock.play()
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 16, 0], [0xFB]])
    }

    /// Song position is 14-bit across two 7-bit bytes; past 127 units the high byte must carry.
    func testSongPositionSplitsAcrossTwoBytes() {
        for _ in 0..<9 { clock.tapeNext() }   // 9 bars = 144 units > 127
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 160 & 0x7F, 160 >> 7]])
    }

    /// Scrub mode moves a quarter note (4 units) instead of a bar.
    func testScrubModeUsesSmallerStep() {
        clock.tapeArrowMode = .scrub
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 4, 0]])
    }
}

/// The OP-1's on-screen 0-99 scale. `midiToUI` floors, `uiToMidi` is its ceiling inverse,
/// chosen so every UI value round-trips exactly. See notes/RESEARCH.md.
@MainActor
final class DisplayScaleGoldenTests: XCTestCase {

    func testMidiToUIMatchesOP1Formula() {
        for v in 0...127 {
            XCTAssertEqual(midiToUI(Double(v)), Double(v * 99 / 127), "midi \(v)")
        }
    }

    func testUIValuesRoundTripExactly() {
        for ui in 0...99 {
            let midi = uiToMidi(Double(ui))
            XCTAssertEqual(midiToUI(Double(midi)), Double(ui),
                           "ui \(ui) → midi \(midi) → ui \(midiToUI(Double(midi)))")
        }
    }

    func testScaleEndpoints() {
        XCTAssertEqual(midiToUI(0), 0)
        XCTAssertEqual(midiToUI(127), 99)
        XCTAssertEqual(uiToMidi(0), 0)
        XCTAssertEqual(uiToMidi(99), 127)
    }

    func testUiToMidiStaysInRange() {
        for ui in 0...99 {
            let m = uiToMidi(Double(ui))
            XCTAssertTrue((0...127).contains(m), "ui \(ui) produced out-of-range midi \(m)")
        }
    }
}
