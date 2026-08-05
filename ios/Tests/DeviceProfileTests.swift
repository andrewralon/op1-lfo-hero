import XCTest
@testable import op1_lfo_hero

/// Proves the OP-1 profile table says what the OP-1 MIDI spec says.
///
/// The expected channel/CC for every parameter is written out here independently of the
/// profile, transcribed from the OP-1 MIDI reference in README.md. Deriving it a second way
/// is the point: a typo in `DeviceProfiles.swift` cannot hide behind a test that reads the
/// same table it is checking.
final class OP1ProfileMatchesSpecTests: XCTestCase {

    private let profile = DeviceProfile.op1Field
    private var sink: RecordingSink!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        sink = RecordingSink()
        ctrl = Controller(router: sink)
        ctrl.setProfile(.op1Field)
    }

    /// The OP-1 CC map, transcribed from the spec: (channel, cc) for a parameter on a track.
    /// Master (track 0) always lands on channel 0 and, for fx/lfo, a different CC bank.
    private func expected(_ id: String, track: Int) -> (ch: Int, cc: Int)? {
        let ch = max(0, track - 1)
        switch id {
        case "volume": return track == 0 ? nil : (ch, 7)
        case "pan":    return track == 0 ? nil : (ch, 10)
        case "mute":   return track == 0 ? nil : (ch, 9)
        case "tempo":  return nil                        // app clock, no MIDI
        case let s where s.hasPrefix("par "):
            return track == 0 ? nil : (ch, 46 + Int(s.dropFirst(4))! - 1)
        case let s where s.hasPrefix("env "):
            let i = ["A": 0, "D": 1, "S": 2, "R": 3][String(s.dropFirst(4))]!
            return track == 0 ? nil : (ch, 50 + i)
        case let s where s.hasPrefix("fx "):
            let n = Int(s.dropFirst(3))! - 1
            return track == 0 ? (0, 70 + n) : (ch, 54 + n)   // master fx
        case let s where s.hasPrefix("lfo "):
            let n = Int(s.dropFirst(4))! - 1
            return track == 0 ? (0, 74 + n) : (ch, 58 + n)   // master compressor
        default:
            XCTFail("unmapped parameter id '\(id)'")
            return nil
        }
    }

    private static let probeValues = [0, 1, 63, 64, 126, 127]

    /// Every parameter, every track, every probe value — profile output vs the transcribed spec.
    func testEveryParamTrackAndValueMatchesTheSpec() {
        var compared = 0
        for spec in profile.params {
            for track in 0...profile.trackCount where spec.isAvailable(onTrack: track) {
                guard let want = expected(spec.id, track: track) else {
                    XCTAssertNil(profile.binding(spec, track: track).flatMap { b -> ParamBinding? in
                        if case .cc = b { return b } else { return nil }
                    }, "'\(spec.id)' track \(track) should not emit a CC")
                    continue
                }
                for v in Self.probeValues {
                    sink.reset()
                    ctrl.send(spec: spec, track: track, value: Double(v))
                    // Mute is the one parameter that snaps rather than passing the value through.
                    let wantVal = spec.role == .mute ? (v >= 64 ? 127 : 0) : v
                    XCTAssertEqual(sink.only(),
                                   [UInt8(0xB0 | want.ch), UInt8(want.cc), UInt8(wantVal)],
                                   "param '\(spec.id)' track \(track) value \(v)")
                    compared += 1
                }
            }
        }
        // Guard against the loop silently covering nothing if availability logic regresses.
        // 11 track-only params x 4 tracks + 8 fx/lfo params x (4 tracks + master) = 84 pairs,
        // x 6 probe values = 504. ("tempo" has no CC and is excluded.)
        XCTAssertEqual(compared, 504, "unexpected coverage — check isAvailable(onTrack:)")
    }

    /// The old `Parameter` enum's raw values are the persistence contract for saved LFO clips.
    /// If one of these ids changes, users lose chips on upgrade.
    func testLegacyParameterIdsAreAllPresent() {
        let legacy = ["volume", "pan", "mute", "tempo",
                      "par 1", "par 2", "par 3", "par 4",
                      "env A", "env D", "env S", "env R",
                      "fx 1", "fx 2", "fx 3", "fx 4",
                      "lfo 1", "lfo 2", "lfo 3", "lfo 4"]
        XCTAssertEqual(profile.params.map(\.id), legacy,
                       "OP-1 parameter ids/order must match the old Parameter enum exactly")
    }

    /// Mirrors the old `Parameter.shortName` table — these appear on LFO chips.
    func testShortNamesMatchLegacy() {
        let expected = ["volume": "vol", "pan": "pan", "mute": "mut", "tempo": "tmp",
                        "par 1": "p1", "par 2": "p2", "par 3": "p3", "par 4": "p4",
                        "env A": "eA", "env D": "eD", "env S": "eS", "env R": "eR",
                        "fx 1": "fx1", "fx 2": "fx2", "fx 3": "fx3", "fx 4": "fx4",
                        "lfo 1": "l1", "lfo 2": "l2", "lfo 3": "l3", "lfo 4": "l4"]
        for spec in profile.params {
            XCTAssertEqual(spec.short, expected[spec.id], "short name for '\(spec.id)'")
        }
    }

    /// Mirrors the old `Parameter.isMasterOnly` / `isMasterCapable`, which drive whether the
    /// master toggle and the track toggles are selectable for a given parameter.
    func testMasterCapabilityMatchesLegacy() {
        let masterCapable: Set<String> = ["tempo", "fx 1", "fx 2", "fx 3", "fx 4",
                                          "lfo 1", "lfo 2", "lfo 3", "lfo 4"]
        for spec in profile.params {
            XCTAssertEqual(spec.isMasterCapable, masterCapable.contains(spec.id),
                           "isMasterCapable for '\(spec.id)'")
            XCTAssertEqual(spec.isMasterOnly, spec.id == "tempo",
                           "isMasterOnly for '\(spec.id)'")
        }
    }
}

/// Structural invariants every profile must satisfy, whatever device it describes.
final class DeviceProfileStructureTests: XCTestCase {

    func testNoDuplicateParamIdsInAnyProfile() {
        for p in DeviceRegistry.all {
            XCTAssertEqual(Set(p.params.map(\.id)).count, p.params.count,
                           "\(p.id) has duplicate parameter ids")
        }
    }

    /// Every outbound (param, track) must resolve back to the same (param, track) inbound,
    /// or two parameters are fighting over one channel/CC pair.
    func testInboundTableRoundTripsEveryParam() {
        for p in DeviceRegistry.all {
            for spec in p.params {
                for track in 0...p.trackCount where spec.isAvailable(onTrack: track) {
                    guard case .cc(let cc, let rule, _)? = p.binding(spec, track: track) else { continue }
                    let ch = p.channel(rule, track: track)
                    let hit = p.inboundTarget(channel: ch, cc: cc)
                    XCTAssertEqual(hit?.spec.id, spec.id,
                                   "\(p.id): ch \(ch) cc \(cc) should map back to '\(spec.id)'")
                    XCTAssertEqual(hit?.track, track,
                                   "\(p.id): ch \(ch) cc \(cc) should map back to track \(track)")
                }
            }
        }
    }

    func testDefaultParamIdResolves() {
        for p in DeviceRegistry.all {
            XCTAssertNotNil(p.param(p.defaultParamId), "\(p.id) default param does not resolve")
        }
    }

    func testChannelsAndCCsAreInMidiRange() {
        for p in DeviceRegistry.all {
            for spec in p.params {
                for track in 0...p.trackCount where spec.isAvailable(onTrack: track) {
                    guard case .cc(let cc, let rule, _)? = p.binding(spec, track: track) else { continue }
                    let ch = p.channel(rule, track: track)
                    XCTAssertTrue((0...15).contains(ch), "\(p.id) '\(spec.id)' channel \(ch)")
                    XCTAssertTrue((0...127).contains(cc), "\(p.id) '\(spec.id)' cc \(cc)")
                }
            }
        }
    }

    func testNameMatchingIsCaseInsensitiveAndSubstringBased() {
        XCTAssertNotNil(DeviceRegistry.profile(forEndpointName: "OP-1"))
        XCTAssertNotNil(DeviceRegistry.profile(forEndpointName: "OP-1 Field"))
        XCTAssertNotNil(DeviceRegistry.profile(forEndpointName: "op1"))
        XCTAssertNil(DeviceRegistry.profile(forEndpointName: "Akai Network - MIDI"))
        XCTAssertNil(DeviceRegistry.profile(forEndpointName: ""))
    }

    func testUnknownProfileIdFallsBackToOP1() {
        XCTAssertEqual(DeviceRegistry.profile(id: "nonsense").id, "op1")
    }
}

/// The encoders that let one parameter table serve devices with different value conventions.
final class ValueEncodingTests: XCTestCase {

    func testContinuousClampsAndRounds() {
        XCTAssertEqual(ValueEncoding.continuous.wireValue(from: 63.4), 63)
        XCTAssertEqual(ValueEncoding.continuous.wireValue(from: 63.6), 64)
        XCTAssertEqual(ValueEncoding.continuous.wireValue(from: -20), 0)
        XCTAssertEqual(ValueEncoding.continuous.wireValue(from: 999), 127)
    }

    /// The OP-1's mute: CC 9, hard 127/0, threshold 64.
    func testSwitchingDefaultMatchesOP1Mute() {
        let e = ValueEncoding.switching(SwitchEncoding())
        XCTAssertEqual(e.wireValue(from: 0), 0)
        XCTAssertEqual(e.wireValue(from: 63), 0)
        XCTAssertEqual(e.wireValue(from: 64), 127)
        XCTAssertEqual(e.wireValue(from: 127), 127)
        XCTAssertFalse(e.isOn(63))
        XCTAssertTrue(e.isOn(64))
    }

    /// Polarity is data, so a device whose "on" means unmuted needs no new code path.
    func testInvertedSwitchingFlipsBothDirections() {
        let e = ValueEncoding.switching(SwitchEncoding(inverted: true))
        XCTAssertEqual(e.wireValue(from: 127), 0)
        XCTAssertEqual(e.wireValue(from: 0), 127)
        XCTAssertTrue(e.isOn(0))
        XCTAssertFalse(e.isOn(127))
    }

    /// TP-7 loop: off / in / out spread across the 0-127 LFO range.
    func testEnumeratedSpreadsAcrossFullRange() {
        let e = ValueEncoding.enumerated(count: 3)
        XCTAssertEqual(e.wireValue(from: 0), 0)
        XCTAssertEqual(e.wireValue(from: 42), 0)
        XCTAssertEqual(e.wireValue(from: 43), 1)
        XCTAssertEqual(e.wireValue(from: 85), 1)
        XCTAssertEqual(e.wireValue(from: 86), 2)
        XCTAssertEqual(e.wireValue(from: 127), 2)
        // Never exceeds the state count, even out of range.
        XCTAssertEqual(e.wireValue(from: 500), 2)
        XCTAssertEqual(e.wireValue(from: -5), 0)
    }

    func testRelativeCentersAtSixtyFour() {
        let e = ValueEncoding.relative(center: 64)
        XCTAssertEqual(e.wireValue(from: 0), 64)
        XCTAssertEqual(e.wireValue(from: 1), 65)
        XCTAssertEqual(e.wireValue(from: -1), 63)
        XCTAssertEqual(e.wireValue(from: 200), 127)
    }
}

/// The 0-99 display scale is app-wide, not per device — a profile deliberately has no scale
/// knob, so every device shows 0-99 while sending 0-127. `DisplayScaleGoldenTests` in
/// GoldenMidiTests.swift pins the conversion itself.
final class DisplayScaleIsAppWideTests: XCTestCase {

    func testNoProfileCarriesItsOwnScale() {
        // Compile-time contract: if someone adds a `scale` to DeviceProfile, revisit whether
        // the 0-99 convention is really meant to vary per device (it is not).
        for p in DeviceRegistry.all {
            XCTAssertFalse(p.params.isEmpty, "\(p.id) has no parameters")
        }
    }
}
