import XCTest
@testable import op1_lfo_hero

/// TX-6 wire format, checked against the CC table transcribed from
/// https://teenage.engineering/guides/tx-6#midi-reference
///
/// The expectations here are written out independently of `DeviceProfiles.swift` so a typo in
/// the profile can't hide behind a test that reads the same table it is checking.
final class TX6ProfileTests: XCTestCase {

    private let profile = DeviceProfile.tx6
    private var sink: RecordingSink!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        sink = RecordingSink()
        ctrl = Controller(router: sink)
        ctrl.setProfile(.tx6)
    }

    private func bytes(_ id: String, track: Int, value: Double = 100) -> [UInt8] {
        guard let spec = profile.param(id) else {
            XCTFail("no such parameter '\(id)'"); return []
        }
        sink.reset()
        ctrl.send(spec: spec, track: track, value: value)
        return sink.packets.first ?? []
    }

    func testSixTracksOnChannelsZeroToFive() {
        XCTAssertEqual(profile.trackCount, 6)
        for track in 1...6 {
            XCTAssertEqual(bytes("tx6.vol", track: track), [UInt8(0xB0 | (track - 1)), 7, 100],
                           "volume track \(track)")
        }
    }

    /// Every documented per-channel CC, on an arbitrary track.
    func testPerTrackCCNumbers() {
        let expected: [String: UInt8] = [
            "tx6.vol": 7, "tx6.pan": 8, "tx6.gain": 9, "tx6.seqPat": 14,
            "tx6.filter": 74, "tx6.eqHi": 85, "tx6.eqMid": 86, "tx6.eqLo": 87,
            "tx6.comp": 93, "tx6.synWave": 3, "tx6.synFreq": 89, "tx6.synLen": 90,
            "tx6.synDet": 95, "tx6.fx1Send": 91, "tx6.auxSend": 92, "tx6.aux2Send": 94,
        ]
        for (id, cc) in expected {
            XCTAssertEqual(bytes(id, track: 3), [0xB2, cc, 100], "\(id) on track 3")
        }
    }

    /// Mute is CC 120 (which is standard MIDI "all sound off" — TE reuses it per channel).
    func testMuteUsesCC120AndSnapsOnOff() {
        XCTAssertEqual(bytes("tx6.mute", track: 1, value: 127), [0xB0, 120, 127])
        XCTAssertEqual(bytes("tx6.mute", track: 1, value: 0),   [0xB0, 120, 0])
        XCTAssertEqual(bytes("tx6.mute", track: 1, value: 63),  [0xB0, 120, 0],  "0-63 is off")
        XCTAssertEqual(bytes("tx6.mute", track: 1, value: 64),  [0xB0, 120, 127], "64-127 is on")
    }

    /// Master bus is MIDI channel 7 (0-based 6) and is reachable only from the master target.
    func testMasterBusOnChannelSix() {
        XCTAssertEqual(bytes("tx6.mainVol", track: 0), [0xB6, 7, 100])
        XCTAssertEqual(bytes("tx6.auxVol",  track: 0), [0xB6, 14, 100])
        XCTAssertEqual(bytes("tx6.cueVol",  track: 0), [0xB6, 15, 100])
        for id in ["tx6.mainVol", "tx6.auxVol", "tx6.cueVol", "tx6.localCtl"] {
            XCTAssertTrue(profile.param(id)!.isMasterOnly, "\(id) must be master-only")
        }
    }

    /// The two FX buses live on channels 8 and 9 (0-based 7 and 8) and share a CC layout —
    /// only the channel tells them apart. This is the case the profile's pinned channels exist for.
    func testFxBusesAreDistinguishedOnlyByChannel() {
        XCTAssertEqual(bytes("tx6.fx1.en",  track: 0, value: 127), [0xB7, 82, 127])
        XCTAssertEqual(bytes("tx6.fx2.en",  track: 0, value: 127), [0xB8, 82, 127])
        XCTAssertEqual(bytes("tx6.fx1.eng", track: 0), [0xB7, 15, 100])
        XCTAssertEqual(bytes("tx6.fx2.eng", track: 0), [0xB8, 15, 100])
        XCTAssertEqual(bytes("tx6.fx1.p1",  track: 0), [0xB7, 12, 100])
        XCTAssertEqual(bytes("tx6.fx1.p2",  track: 0), [0xB7, 13, 100])
        XCTAssertEqual(bytes("tx6.fx1.p3",  track: 0), [0xB7, 14, 100])
        XCTAssertEqual(bytes("tx6.fx2.p1",  track: 0), [0xB8, 12, 100])
        XCTAssertEqual(bytes("tx6.fx2.p2",  track: 0), [0xB8, 13, 100])
        XCTAssertEqual(bytes("tx6.fx2.p3",  track: 0), [0xB8, 14, 100])
        // The one control each bus does not share.
        XCTAssertEqual(bytes("tx6.fx1.ret", track: 0), [0xB7, 7, 100])
        XCTAssertEqual(bytes("tx6.fx2.trk", track: 0), [0xB8, 9, 100])
    }

    /// FX *bus* parameters (ids `tx6.fx1.*` / `tx6.fx2.*`) are folded into the master (m)
    /// target and have no per-track form. Not to be confused with the per-track FX *send*
    /// (`tx6.fx1Send`, CC 91), which is a normal channel parameter.
    func testFxBusParamsAreMasterOnly() {
        let busParams = profile.params.filter { $0.id.hasPrefix("tx6.fx1.") || $0.id.hasPrefix("tx6.fx2.") }
        XCTAssertEqual(busParams.count, 12, "6 controls on each of the two FX buses")
        for spec in busParams {
            XCTAssertTrue(spec.isMasterOnly, "\(spec.id) should only exist on master")
            XCTAssertEqual(bytes(spec.id, track: 2), [], "\(spec.id) must send nothing on a track")
        }
    }

    /// The per-track FX send is a channel parameter, not part of the FX bus.
    func testFxSendIsPerTrack() {
        let send = profile.param("tx6.fx1Send")!
        XCTAssertFalse(send.isMasterOnly)
        XCTAssertEqual(bytes("tx6.fx1Send", track: 2), [0xB1, 91, 100])
    }

    /// CC 47 is a relative encoder — an LFO on it would drift the tempo one way forever.
    func testTempoRelativeIsNotAnLfoTarget() {
        XCTAssertFalse(profile.params.contains { $0.name.contains("tempo") },
                       "tempo relative must not be an automatable parameter")
    }

    func testCapabilities() {
        XCTAssertTrue(profile.caps.hasPan)
        XCTAssertFalse(profile.caps.canBeClockMaster, "no documented clock output")
        XCTAssertFalse(profile.caps.hasTempoParam)
    }
}

/// TX-6 transport: a single stateless start/stop toggle plus a relative tempo encoder.
final class TX6TransportTests: XCTestCase {

    private var sink: RecordingSink!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        sink = RecordingSink()
        clock = ClockEngine()
        clock.router = sink
        clock.transport = DeviceProfile.tx6.transport
    }

    /// CC 46 toggles, so play must only send it when the app believes it is stopped —
    /// otherwise pressing play twice would stop the device.
    func testPlaySendsToggleOnlyWhenStopped() {
        sink.reset()
        clock.play()
        XCTAssertEqual(sink.packets, [[0xB6, 46, 127], [0xFB]])

        sink.reset()
        clock.play()   // already playing
        XCTAssertEqual(sink.packets, [[0xFB]], "the toggle must not fire again")
    }

    func testStopSendsToggleOnlyWhenPlaying() {
        clock.play()
        sink.reset()
        clock.stop()
        XCTAssertEqual(sink.packets, [[0xB6, 46, 127], [0xFC]])

        sink.reset()
        clock.stop()   // already stopped
        XCTAssertEqual(sink.packets, [[0xFC]], "the toggle must not fire again")
    }

    /// −/+ nudge tempo via the relative encoder on CC 47, centred at 64.
    func testTempoNudgeUsesRelativeEncoder() {
        sink.reset()
        clock.tapeNext()
        XCTAssertEqual(sink.packets, [[0xB6, 47, 65]], "one step up")

        sink.reset()
        clock.tapePrev()
        XCTAssertEqual(sink.packets, [[0xB6, 47, 63]], "one step down")
    }
}

/// TP-7 wire format, checked against
/// https://teenage.engineering/guides/tp-7#midi-reference
final class TP7ProfileTests: XCTestCase {

    private let profile = DeviceProfile.tp7
    private var sink: RecordingSink!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        sink = RecordingSink()
        ctrl = Controller(router: sink)
        ctrl.setProfile(.tp7)
    }

    private func bytes(_ id: String, track: Int, value: Double = 100) -> [UInt8] {
        guard let spec = profile.param(id) else {
            XCTFail("no such parameter '\(id)'"); return []
        }
        sink.reset()
        ctrl.send(spec: spec, track: track, value: value)
        return sink.packets.first ?? []
    }

    func testMixVolumeOnAllSixChannels() {
        XCTAssertEqual(profile.trackCount, 6)
        for track in 1...6 {
            XCTAssertEqual(bytes("tp7.vol", track: track), [UInt8(0xB0 | (track - 1)), 7, 100])
        }
    }

    func testMixMuteUsesCC120() {
        XCTAssertEqual(bytes("tp7.mute", track: 2, value: 127), [0xB1, 120, 127])
        XCTAssertEqual(bytes("tp7.mute", track: 2, value: 0),   [0xB1, 120, 0])
    }

    /// Input gain exists only on the three physical inputs — channels 4-6 are playback.
    func testInputGainOnlyOnFirstThreeChannels() {
        let gain = profile.param("tp7.gain")!
        for track in 1...3 {
            XCTAssertTrue(gain.isAvailable(onTrack: track), "gain should exist on \(track)")
            XCTAssertEqual(bytes("tp7.gain", track: track), [UInt8(0xB0 | (track - 1)), 9, 100])
        }
        for track in 4...6 {
            XCTAssertFalse(gain.isAvailable(onTrack: track), "gain should not exist on \(track)")
        }
    }

    /// Record/cue/loop are global, so they hang off the master target on channel 1.
    func testGlobalControlsAreMasterOnly() {
        XCTAssertEqual(bytes("tp7.rec",    track: 0, value: 127), [0xB0, 14, 127])
        XCTAssertEqual(bytes("tp7.cueRec", track: 0, value: 127), [0xB0, 16, 127])
        for id in ["tp7.rec", "tp7.cueRec", "tp7.loop"] {
            XCTAssertTrue(profile.param(id)!.isMasterOnly, "\(id) must be master-only")
        }
    }

    /// Loop is a 3-state control (off/in/out), not a continuous value — an LFO sweeping
    /// 0-127 must land on 0, 1 or 2 and never anything else.
    func testLoopQuantisesToThreeStates() {
        XCTAssertEqual(bytes("tp7.loop", track: 0, value: 0),   [0xB0, 17, 0])
        XCTAssertEqual(bytes("tp7.loop", track: 0, value: 64),  [0xB0, 17, 1])
        XCTAssertEqual(bytes("tp7.loop", track: 0, value: 127), [0xB0, 17, 2])
        for v in stride(from: 0.0, through: 127.0, by: 1.0) {
            let b = bytes("tp7.loop", track: 0, value: v)
            XCTAssertTrue([0, 1, 2].contains(Int(b[2])), "value \(v) produced \(b[2])")
        }
    }

    /// The TP-7 is a recorder with no pan — the strip hides the knob entirely.
    func testHasNoPan() {
        XCTAssertFalse(profile.caps.hasPan)
        XCTAssertNil(profile.param(role: .pan))
    }

    /// Measured on hardware, contradicting the published MIDI reference: in `sync` mode the
    /// TP-7 streams 24 PPQN continuously (~1769 ticks in 40 s). The guide documents no clock
    /// output at all, so this can only be known by listening. See notes/RESEARCH.md.
    func testCanBeClockMasterBecauseItActuallySendsClock() {
        XCTAssertTrue(profile.caps.canBeClockMaster,
                      "the TP-7 does send MIDI clock in sync mode — verified on hardware")
    }

    func testCapabilities() {
        XCTAssertFalse(profile.caps.hasTempoParam)
        // TE's docs: "TP-7 never reports its state via MIDI" — nothing to mirror.
        XCTAssertFalse(profile.caps.mirrorsIncomingCC)
    }

    /// The TX-6 genuinely never sends clock; the TP-7 does. Same manufacturer, opposite
    /// behaviour — a reminder not to generalise one TE device's behaviour to another.
    func testClockBehaviourDiffersFromTheTX6() {
        XCTAssertTrue(DeviceProfile.tp7.caps.canBeClockMaster)
        XCTAssertFalse(DeviceProfile.tx6.caps.canBeClockMaster)
    }
}

/// Detection: endpoint names as they actually appear in CoreMIDI. Verified against a Mac's
/// CoreMIDI database, where all three devices report `name`/`model` exactly as below with
/// manufacturer "teenage engineering".
final class DeviceDetectionTests: XCTestCase {

    func testRealEndpointNamesResolveToTheRightProfile() {
        XCTAssertEqual(DeviceRegistry.profile(forEndpointName: "OP-1")?.id, "op1")
        XCTAssertEqual(DeviceRegistry.profile(forEndpointName: "TX-6")?.id, "tx6")
        XCTAssertEqual(DeviceRegistry.profile(forEndpointName: "TP-7")?.id, "tp7")
    }

    func testMatchingIsCaseAndFormatInsensitive() {
        for (name, id) in [("tx-6", "tx6"), ("TX6", "tx6"), ("tp-7", "tp7"), ("TP7", "tp7"),
                           ("op1", "op1"), ("OP-1 Field", "op1")] {
            XCTAssertEqual(DeviceRegistry.profile(forEndpointName: name)?.id, id, name)
        }
    }

    func testUnrelatedGearDoesNotMatch() {
        for name in ["Akai Network - MIDI", "IAC Driver Bus 1", "Oxygen 49", "MPC One+", ""] {
            XCTAssertNil(DeviceRegistry.profile(forEndpointName: name), name)
        }
    }

    /// Every profile must be reachable by its own id, since that is what gets persisted.
    func testEveryProfileResolvesById() {
        for p in DeviceRegistry.all {
            XCTAssertEqual(DeviceRegistry.profile(id: p.id).id, p.id)
        }
    }

    /// Parameter ids must be globally unique, not just unique per profile — a saved clip
    /// carries its id and a stale one must not silently resolve against another device.
    func testParamIdsAreUniqueAcrossProfiles() {
        var seen: [String: String] = [:]
        for p in DeviceRegistry.all {
            for spec in p.params {
                if let owner = seen[spec.id] {
                    XCTAssertEqual(owner, p.id, "'\(spec.id)' is claimed by both \(owner) and \(p.id)")
                }
                seen[spec.id] = p.id
            }
        }
    }
}

/// Findings from listening to a real TX-6 over USB MIDI. See notes/RESEARCH.md.
final class TX6HardwareFindingsTests: XCTestCase {

    /// The TX-6's controller-mode transmit map and its receive map are different namespaces
    /// that overlap: transmitted CC 7 on channel 1 is "upper knob 1", but the receive map
    /// reads CC 7 on channel 1 as "track 1 volume". Mirroring incoming CC into the mixer UI
    /// would therefore show knob moves as volume changes.
    func testTx6DoesNotMirrorIncomingCC() {
        XCTAssertFalse(DeviceProfile.tx6.caps.mirrorsIncomingCC)
    }

    /// The OP-1 does echo its mixer on the CCs it accepts, so mirroring stays on there.
    func testOP1DoesMirrorIncomingCC() {
        XCTAssertTrue(DeviceProfile.op1Field.caps.mirrorsIncomingCC)
    }

    /// Documents the observed collision so it cannot be reintroduced by a table edit:
    /// these CCs are what a real TX-6 transmitted, and they resolve to unrelated parameters.
    func testObservedTransmitCCsCollideWithReceiveMap() {
        let observed: [(cc: Int, control: String)] = [
            (7,  "upper knob 1"),
            (13, "middle knob 1"),
            (19, "lower knob 1"),
            (31, "encoder turn"),
            (33, "fx I button"),
            (34, "fx II button"),
            (35, "shift button"),
        ]
        // Channel 1 (0-based 0) is track 1 in the receive map.
        let collisions = observed.filter { DeviceProfile.tx6.inboundTarget(channel: 0, cc: $0.cc) != nil }
        XCTAssertFalse(collisions.isEmpty,
                       "expected transmit/receive overlap — that is why mirroring is off")
        for c in collisions {
            let hit = DeviceProfile.tx6.inboundTarget(channel: 0, cc: c.cc)!
            XCTAssertNotEqual(hit.spec.name, c.control,
                              "CC \(c.cc) means '\(c.control)' outbound but '\(hit.spec.name)' inbound")
        }
    }
}

/// The exact transmit/receive collision set measured on a real TX-6, pinned so a future edit
/// to the parameter table cannot silently reintroduce the misread. See notes/RESEARCH.md.
final class TX6TransmitReceiveCollisionTests: XCTestCase {

    /// (transmitted CC on ch 1, what the TX-6 control surface calls it,
    ///  what the receive map would call it)
    private let collisions: [(cc: Int, transmit: String, receive: String)] = [
        (3,  "fader 3",       "syn wave"),
        (7,  "upper knob 1",  "volume"),
        (8,  "upper knob 2",  "pan"),
        (9,  "upper knob 3",  "gain"),
        (14, "middle knob 2", "seq pattern"),
    ]

    /// Every one of these resolves to the *wrong* meaning if incoming CC is mirrored.
    func testKnownCollisionsStillResolveToTheReceiveMeaning() {
        for c in collisions {
            let hit = DeviceProfile.tx6.inboundTarget(channel: 0, cc: c.cc)
            XCTAssertEqual(hit?.spec.name, c.receive,
                           "cc \(c.cc) receive meaning changed — recheck the collision analysis")
            XCTAssertEqual(hit?.track, 1)
        }
    }

    /// Which is exactly why mirroring is disabled for this device.
    func testMirroringIsOffSoCollisionsCannotReachTheUI() {
        XCTAssertFalse(DeviceProfile.tx6.caps.mirrorsIncomingCC)
    }

    /// The TX-6's faders transmit CC 1-6. Five of those six mean nothing in the receive map, so
    /// the hardware fader positions are invisible to the app — a known gap, not a surprise.
    /// The exception is fader 3 (CC 3), which the receive map calls "syn wave": that one is a
    /// collision, covered above.
    func testFaderTransmitCCsAreMostlyAbsentFromTheReceiveMap() {
        for cc in [1, 2, 4, 5, 6] {
            XCTAssertNil(DeviceProfile.tx6.inboundTarget(channel: 0, cc: cc),
                         "cc \(cc) (a fader) unexpectedly resolves in the receive map")
        }
        XCTAssertEqual(DeviceProfile.tx6.inboundTarget(channel: 0, cc: 3)?.spec.name, "syn wave",
                       "fader 3 collides with syn wave — see the collision table")
    }
}

/// TP-7 transport. Real-time messages only — CC 14 is *record* on this device, so putting it in
/// the transport map would arm recording on every play. Caught during hardware testing.
final class TP7TransportTests: XCTestCase {

    private var sink: RecordingSink!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        sink = RecordingSink()
        clock = ClockEngine()
        clock.router = sink
        clock.transport = DeviceProfile.tp7.transport
    }

    func testPlayResumesAndSendsNoCC() {
        sink.reset()
        clock.play()
        XCTAssertEqual(sink.packets, [[0xFB]], "play must resume, and must not send any CC")
    }

    /// Stopping a normally-playing tape must NOT send CC 18 — the device reads a redundant
    /// stop as "stop while already stopped" and rewinds to zero, losing the user's position.
    /// Verified on hardware: one 0xFC stops and holds; a second rewinds.
    func testStopWhileMerelyPlayingSendsOnlyStop() {
        clock.play()
        sink.reset()
        clock.stop()
        XCTAssertEqual(sink.packets, [[0xFC]], "must not recentre CC 18 when it never engaged")
    }

    /// The safety property: no transport action may ever emit CC 14 (record).
    func testTransportNeverSendsRecordCC() {
        clock.play(); clock.stop(); clock.tapePrev(); clock.tapeNext()
        for p in sink.packets where p.count == 3 {
            XCTAssertFalse(p[0] & 0xF0 == 0xB0 && p[1] == 14,
                           "transport emitted CC 14 (record): \(p)")
        }
    }

    /// Record is still reachable — as an explicit parameter, not a side effect of play.
    func testRecordIsAvailableAsAParameter() {
        let rec = DeviceProfile.tp7.param("tp7.rec")
        XCTAssertNotNil(rec)
        XCTAssertTrue(rec!.isMasterOnly)
    }

    /// CC 18 is a persistent bipolar speed control: below 64 reverse, 64 stop, above forward.
    func testSeekIsBipolarAroundSixtyFour() {
        sink.reset()
        clock.tapeNext()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 72]], "forward = 64 + speed")
        sink.reset()
        clock.tapePrev()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 56]], "reverse = 64 - speed")
    }

    /// Speed is a multiple of normal playback, not a raw CC offset. unitSpeed 4 = 1x on the
    /// TP-7, verified by ear: 60 (=64-4) played reverse at about normal speed.
    func testSpeedIsAMultipleOfNormalPlayback() {
        clock.transportSpeed = 1.0            // 1x
        sink.reset()
        clock.tapeNext()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 68]], "64 + 4 = forward at 1x")
        sink.reset()
        clock.tapePrev()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 60]], "64 - 4 = reverse at 1x")
    }

    /// The default is 2x — a fast-forward, matching the "chipmunks" heard at CC 18 = 72.
    func testDefaultSpeedIsDoubleNormal() {
        XCTAssertEqual(clock.transportSpeed, 2.0)
        sink.reset()
        clock.tapeNext()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 72]], "64 + 8 = forward at 2x")
    }

    func testHalfSpeed() {
        clock.transportSpeed = 0.5
        sink.reset()
        clock.tapeNext()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 66]], "64 + 2 = forward at 0.5x")
    }

    /// Speed must never push CC 18 out of range, and never round down to zero — an offset of 0
    /// would read as "stopped" no matter which direction was asked for.
    func testSpeedIsClampedAndNeverRoundsToZero() {
        clock.transportSpeed = 99
        XCTAssertEqual(clock.transportSpeed, 8.0, "clamped to 8x")
        sink.reset()
        clock.tapeNext()
        XCTAssertLessThanOrEqual(Int(sink.packets[0][2]), 127)

        clock.transportSpeed = 0.01
        XCTAssertEqual(clock.transportSpeed, 0.25, "clamped to 0.25x")
        sink.reset()
        clock.tapePrev()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 63]], "0.25x = offset 1, the slowest crawl")
    }

    /// But stopping a tape that IS seeking under CC 18 must recentre it — 0xFC alone will not
    /// release the grab, so the tape would keep rolling. Verified on hardware.
    func testStopWhileSeekingRecentresFirst() {
        clock.tapeNext()          // CC 18 now has the transport
        sink.reset()
        clock.stop()
        XCTAssertEqual(sink.packets, [[0xB0, 18, 64], [0xFC]],
                       "a seeking tape needs CC 18 = 64 before 0xFC")
    }

    /// And having released once, a second stop must not send CC 18 again.
    func testSecondStopDoesNotResendCentre() {
        clock.tapeNext()
        clock.stop()
        sink.reset()
        clock.stop()
        XCTAssertEqual(sink.packets, [[0xFC]], "grab already released")
    }

    /// The engine tracks which way it last told the tape to go.
    func testDirectionIsTracked() {
        clock.tapeNext(); XCTAssertEqual(clock.transportDirection, 1)
        clock.tapePrev(); XCTAssertEqual(clock.transportDirection, -1)
        clock.stop();     XCTAssertEqual(clock.transportDirection, 0)
    }
}
