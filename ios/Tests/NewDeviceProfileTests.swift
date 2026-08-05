import XCTest
@testable import op1_lfo_hero

/// TX-6 wire format, checked against the CC table transcribed from
/// https://teenage.engineering/guides/tx-6#midi-reference
///
/// The expectations here are written out independently of `DeviceProfiles.swift` so a typo in
/// the profile can't hide behind a test that reads the same table it is checking.
final class TX6ProfileTests: XCTestCase {

    private let profile = DeviceProfile.tx6
    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tx6)
    }

    private func bytes(_ id: String, track: Int, value: Double = 100) -> [UInt8] {
        guard let spec = profile.param(id) else {
            XCTFail("no such parameter '\(id)'"); return []
        }
        destination.reset()
        ctrl.send(spec: spec, track: track, value: value)
        return destination.packets.first ?? []
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

    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tx6.transport
    }

    /// CC 46 toggles, so play must only send it when the app believes it is stopped —
    /// otherwise pressing play twice would stop the device.
    func testPlaySendsToggleOnlyWhenStopped() {
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xB6, 46, 127], [0xFB]])

        destination.reset()
        clock.play()   // already playing
        XCTAssertEqual(destination.packets, [[0xFB]], "the toggle must not fire again")
    }

    func testStopSendsToggleOnlyWhenPlaying() {
        clock.play()
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xB6, 46, 127], [0xFC]])

        destination.reset()
        clock.stop()   // already stopped
        XCTAssertEqual(destination.packets, [[0xFC]], "the toggle must not fire again")
    }

    /// −/+ nudge tempo via the relative encoder on CC 47, centred at 64.
    func testTempoNudgeUsesRelativeEncoder() {
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB6, 47, 65]], "one step up")

        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB6, 47, 63]], "one step down")
    }
}

/// TP-7 wire format, checked against
/// https://teenage.engineering/guides/tp-7#midi-reference
final class TP7ProfileTests: XCTestCase {

    private let profile = DeviceProfile.tp7
    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
    }

    private func bytes(_ id: String, track: Int, value: Double = 100) -> [UInt8] {
        guard let spec = profile.param(id) else {
            XCTFail("no such parameter '\(id)'"); return []
        }
        destination.reset()
        ctrl.send(spec: spec, track: track, value: value)
        return destination.packets.first ?? []
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

    /// CC 9 is the preamp for the three physical input jacks, which feed the mix channels:
    /// jack -> gain -> mix. Addressed per jack rather than per track, so it is master-level.
    /// Verified on hardware — gain only changed audio once a source was patched into that jack.
    func testInputGainsAreMasterLevelOnePerJack() {
        for (n, ch) in [(1, 0), (2, 1), (3, 2)] {
            let spec = profile.param("tp7.in\(n)Gain")
            XCTAssertNotNil(spec, "input \(n) gain should exist")
            XCTAssertTrue(spec!.isMasterOnly, "input gain is not a track parameter")
            XCTAssertEqual(bytes("tp7.in\(n)Gain", track: 0), [UInt8(0xB0 | ch), 9, 100],
                           "input \(n) gain on channel \(ch + 1)")
        }
    }

    /// There is no fourth input, and no gain on the mix channels.
    func testThereIsNoGainBeyondThreeInputs() {
        XCTAssertNil(profile.param("tp7.in4Gain"))
        XCTAssertNil(profile.param("tp7.gain"), "the old per-track gain must be gone")
        for track in 1...6 {
            XCTAssertNil(profile.params.first { $0.role == .generic && $0.name.contains("gain") }?
                            .track.flatMap { _ in Optional(track) },
                         "no gain parameter should be track-addressable")
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

    /// hasTempoParam is true even though the TP-7 has no tempo CC: it *follows* MIDI clock in
    /// `sync` mode, so retuning the app's clock retunes the device.
    func testCapabilities() {
        XCTAssertTrue(profile.caps.hasTempoParam)
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

    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tp7.transport
    }

    func testPlayResumesAndSendsNoCC() {
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "play must resume, and must not send any CC")
    }

    /// Stopping a normally-playing tape must NOT send CC 18 — the device reads a redundant
    /// stop as "stop while already stopped" and rewinds to zero, losing the user's position.
    /// Verified on hardware: one 0xFC stops and holds; a second rewinds.
    func testStopWhileMerelyPlayingSendsOnlyStop() {
        clock.play()
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xFC]], "must not recentre CC 18 when it never engaged")
    }

    /// The safety property: no transport action may ever emit CC 14 (record).
    func testTransportNeverSendsRecordCC() {
        clock.play(); clock.stop(); clock.tapePrev(); clock.tapeNext()
        for p in destination.packets where p.count == 3 {
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
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 72]], "forward = 64 + speed")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 56]], "reverse = 64 - speed")
    }

    /// Speed is a multiple of normal playback, not a raw CC offset. unitSpeed 4 = 1x on the
    /// TP-7, verified by ear: 60 (=64-4) played reverse at about normal speed.
    func testSpeedIsAMultipleOfNormalPlayback() {
        clock.transportSpeed = 1.0            // 1x
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "64 + 4 = forward at 1x")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 60]], "64 - 4 = reverse at 1x")
    }

    /// The default is 2x — a fast-forward, matching the "chipmunks" heard at CC 18 = 72.
    func testDefaultSpeedIsDoubleNormal() {
        XCTAssertEqual(clock.transportSpeed, 2.0)
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 72]], "64 + 8 = forward at 2x")
    }

    func testHalfSpeed() {
        clock.transportSpeed = 0.5
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 66]], "64 + 2 = forward at 0.5x")
    }

    /// Speed must never push CC 18 out of range, and never round down to zero — an offset of 0
    /// would read as "stopped" no matter which direction was asked for.
    func testSpeedIsClampedAndNeverRoundsToZero() {
        clock.transportSpeed = 99
        XCTAssertEqual(clock.transportSpeed, 8.0, "clamped to 8x")
        destination.reset()
        clock.tapeNext()
        XCTAssertLessThanOrEqual(Int(destination.packets[0][2]), 127)

        clock.transportSpeed = 0.01
        XCTAssertEqual(clock.transportSpeed, 0.25, "clamped to 0.25x")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 63]], "0.25x = offset 1, the slowest crawl")
    }

    /// But stopping a tape that IS seeking under CC 18 must recentre it — 0xFC alone will not
    /// release the grab, so the tape would keep rolling. Verified on hardware.
    func testStopWhileSeekingRecentresFirst() {
        clock.tapeNext()          // CC 18 now has the transport
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 64], [0xFC]],
                       "a seeking tape needs CC 18 = 64 before 0xFC")
    }

    /// And having released once, a second stop must not send CC 18 again.
    func testSecondStopDoesNotResendCentre() {
        clock.tapeNext()
        clock.stop()
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xFC]], "grab already released")
    }

    /// The engine tracks which way it last told the tape to go.
    func testDirectionIsTracked() {
        clock.tapeNext(); XCTAssertEqual(clock.transportDirection, 1)
        clock.tapePrev(); XCTAssertEqual(clock.transportDirection, -1)
        clock.stop();     XCTAssertEqual(clock.transportDirection, 0)
    }
}

/// TP-7 loop (CC 17) is a state machine, verified on hardware: `out` (2) sent with no prior
/// `in` (1) is silently discarded, and once a loop is active only `off` (0) releases it.
final class TP7LoopStateMachineTests: XCTestCase {

    /// Because of that, loop must not be an LFO target — a sweep would map cyclically onto
    /// 0/1/2, discarding most values and dropping loop points at arbitrary moments.
    func testLoopIsNotLfoTargetable() {
        let loop = DeviceProfile.tp7.param("tp7.loop")
        XCTAssertNotNil(loop)
        XCTAssertFalse(loop!.lfoTargetable, "loop is a state machine, not a modulatable value")
    }

    /// And therefore must not appear in the parameter picker.
    func testLoopIsAbsentFromThePicker() {
        XCTAssertFalse(DeviceProfile.tp7.pickerParams.contains { $0.id == "tp7.loop" })
    }

    // Held as stored properties, not locals: Controller.router is a weak var, so a local
    // RecordingDestination can be released out from under it mid-test.
    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
    }

    /// It still encodes correctly if something does send it deliberately.
    func testLoopStillEncodesItsThreeStates() {
        let loop = DeviceProfile.tp7.param("tp7.loop")!
        for (input, expected) in [(0.0, 0), (64.0, 1), (127.0, 2)] {
            destination.reset()
            ctrl.send(spec: loop, track: 0, value: input)
            XCTAssertEqual(destination.packets, [[0xB0, 17, UInt8(expected)]])
        }
    }
}

/// Controls that exist in the TP-7's MIDI table but are not offered as LFO targets, each for a
/// different reason. See notes/RESEARCH.md.
final class TP7NonModulatableControlsTests: XCTestCase {

    // Stored, not local: Controller.router is weak, so a local would be released mid-test.
    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
    }

    /// loop: a state machine — `out` without `in` is discarded, so a sweep produces noise.
    func testLoopIsNotTargetable() {
        XCTAssertFalse(DeviceProfile.tp7.param("tp7.loop")!.lfoTargetable)
    }

    /// cue rec: no observable effect on hardware, and no way to verify on a device that never
    /// reports its state.
    func testCueRecIsNotTargetable() {
        XCTAssertFalse(DeviceProfile.tp7.param("tp7.cueRec")!.lfoTargetable)
    }

    /// record: arms rather than records, and automating it risks a take. Precautionary.
    func testRecordIsNotTargetable() {
        XCTAssertFalse(DeviceProfile.tp7.param("tp7.rec")!.lfoTargetable)
    }

    /// None of the three reaches the parameter picker.
    func testNoneAppearInThePicker() {
        let ids = DeviceProfile.tp7.pickerParams.map(\.id)
        XCTAssertFalse(ids.contains("tp7.loop"))
        XCTAssertFalse(ids.contains("tp7.cueRec"))
        XCTAssertFalse(ids.contains("tp7.rec"))
    }

    /// CC 14 is absolute, not a toggle — verified on hardware by sending 127 twice and watching
    /// the arm persist. So the same value twice must produce the same bytes twice.
    func testRecordIsAbsoluteNotAToggle() {
        let rec = DeviceProfile.tp7.param("tp7.rec")!
        ctrl.send(spec: rec, track: 0, value: 127)
        ctrl.send(spec: rec, track: 0, value: 127)
        XCTAssertEqual(destination.packets, [[0xB0, 14, 127], [0xB0, 14, 127]])
    }

    /// But the mixer controls that were verified on hardware are still offered.
    func testVerifiedControlsRemainTargetable() {
        let ids = DeviceProfile.tp7.pickerParams.map(\.id)
        XCTAssertTrue(ids.contains("tp7.vol"), "mix volume — verified audibly")
        XCTAssertTrue(ids.contains("tp7.mute"), "mix mute — verified audibly")
        XCTAssertTrue(ids.contains("tp7.in1Gain"), "input gain — verified audibly")
    }
}

/// The requested TP-7 playback parameters: speed, direction and tempo.
final class TP7PlaybackParamsTests: XCTestCase {

    private var destination: RecordingDestination!
    private var ctrl: Controller!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
    }

    private func send(_ id: String, _ value: Double) -> [[UInt8]] {
        destination.reset()
        ctrl.send(spec: DeviceProfile.tp7.param(id)!, track: 0, value: value)
        return destination.packets
    }

    // MARK: - Speed (pitch bend)

    /// Pitch bend is 14-bit, but parameters are always 0-127, so the value must be mapped
    /// across the full range — otherwise an LFO would only ever reach the slowest speeds.
    func testSpeedMapsAcrossTheFullPitchBendRange() {
        XCTAssertEqual(send("tp7.speed", 0),   [[0xE0, 0, 0]], "slowest = x0.25")
        XCTAssertEqual(send("tp7.speed", 127), [[0xE0, 127, 127]], "fastest = x2.0")
    }

    /// Mid-scale must land at pitch-bend centre, which the device treats as normal speed.
    func testSpeedMidScaleIsAboutCentre() {
        let p = send("tp7.speed", 64)[0]
        let value = Int(p[1]) | Int(p[2]) << 7
        XCTAssertEqual(p[0], 0xE0)
        XCTAssertEqual(Double(value), 8192, accuracy: 100, "64 should sit at x1.0 (8192)")
    }

    func testSpeedIsMasterOnlyAndTargetable() {
        let spec = DeviceProfile.tp7.param("tp7.speed")!
        XCTAssertTrue(spec.isMasterOnly)
        XCTAssertTrue(spec.lfoTargetable, "speed is exactly the kind of thing to modulate")
    }

    // MARK: - Direction

    /// Behaves like mute: a two-state control, forward above the threshold, reverse below.
    /// 68 and 60 are 1x in each direction — both verified by ear on hardware.
    func testDirectionSnapsForwardOrReverse() {
        XCTAssertEqual(send("tp7.direction", 127), [[0xB0, 18, 68]], "forward at 1x")
        XCTAssertEqual(send("tp7.direction", 64),  [[0xB0, 18, 68]], "threshold is forward")
        XCTAssertEqual(send("tp7.direction", 63),  [[0xB0, 18, 60]], "below threshold reverses")
        XCTAssertEqual(send("tp7.direction", 0),   [[0xB0, 18, 60]], "reverse at 1x")
    }

    /// A square-wave LFO on direction should alternate cleanly between the two, never landing
    /// on an intermediate speed.
    func testDirectionNeverEmitsAnIntermediateValue() {
        for v in stride(from: 0.0, through: 127.0, by: 1.0) {
            let byte = send("tp7.direction", v)[0][2]
            XCTAssertTrue(byte == 68 || byte == 60, "value \(v) produced \(byte)")
        }
    }

    // MARK: - Tempo

    /// The TP-7 has no tempo CC, but it follows MIDI clock — so tempo retunes the app's clock,
    /// which the device tracks. Sends no MIDI of its own, exactly like the OP-1's tempo.
    func testTempoSendsNothingButIsAvailable() {
        let spec = DeviceProfile.tp7.param("tp7.tempo")!
        XCTAssertEqual(spec.role, .tempo)
        XCTAssertTrue(spec.isMasterOnly)
        XCTAssertEqual(send("tp7.tempo", 120), [], "virtual tempo emits no MIDI")
    }

    /// Tempo is master-only, so selecting it must force the master target on — the same
    /// behaviour the OP-1 relies on.
    func testTempoIsMasterOnlyLikeTheOP1() {
        XCTAssertTrue(DeviceProfile.tp7.param("tp7.tempo")!.isMasterOnly)
        XCTAssertTrue(DeviceProfile.op1Field.param("tempo")!.isMasterOnly)
    }

    func testAllThreeAppearInThePicker() {
        let ids = DeviceProfile.tp7.pickerParams.map(\.id)
        XCTAssertTrue(ids.contains("tp7.speed"))
        XCTAssertTrue(ids.contains("tp7.direction"))
        XCTAssertTrue(ids.contains("tp7.tempo"))
    }
}

/// Play/stop and record exposed as parameters, via the `.transport` binding.
final class TP7TransportParamsTests: XCTestCase {

    private var destination: RecordingDestination!
    private var ctrl: Controller!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tp7.transport
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
        ctrl.transportRunner = { [weak clock] ops in clock?.runOps(ops) }
    }

    private func send(_ id: String, _ value: Double) -> [[UInt8]] {
        destination.reset()
        ctrl.send(spec: DeviceProfile.tp7.param(id)!, track: 0, value: value)
        return destination.packets
    }

    /// Above the threshold plays, below stops.
    func testPlayParamGatesTransport() {
        XCTAssertEqual(send("tp7.play", 127), [[0xFB]], "plays")
        XCTAssertEqual(send("tp7.play", 0), [[0xFC]], "stops")
    }

    /// Edge-triggered: a sustained value must not re-fire every tick. An LFO sends a value on
    /// every clock tick (~40 Hz), so without this, holding "on" would spam transport messages.
    func testTransportParamsAreEdgeTriggered() {
        _ = send("tp7.play", 127)
        XCTAssertEqual(send("tp7.play", 127), [], "same state must not re-fire")
        XCTAssertEqual(send("tp7.play", 120), [], "still above threshold, still no re-fire")
        XCTAssertEqual(send("tp7.play", 0), [[0xFC]], "crossing the threshold fires once")
        XCTAssertEqual(send("tp7.play", 10), [], "and does not repeat")
    }

    /// The record sequence mirrors the physical one: stop if playing, arm, then roll.
    func testRecordSequenceArmsThenPlays() {
        clock.play()                       // transport running
        let packets = send("tp7.recSeq", 127)
        XCTAssertEqual(packets, [[0xB0, 18, 64],   // release CC 18 (only fires while playing)
                                 [0xFC],           // stop
                                 [0xB0, 14, 127],  // arm
                                 [0xFB]])          // roll — recording begins
    }

    /// Turning it off stops and disarms, so it cannot be left recording.
    func testRecordSequenceOffStopsAndDisarms() {
        clock.play()
        _ = send("tp7.recSeq", 127)
        XCTAssertEqual(send("tp7.recSeq", 0), [[0xFC], [0xB0, 14, 0]])
    }

    /// Record is destructive, so it stays out of the LFO picker even though it is edge-triggered.
    func testRecordSequenceIsNotLfoTargetable() {
        XCTAssertFalse(DeviceProfile.tp7.param("tp7.recSeq")!.lfoTargetable)
        XCTAssertFalse(DeviceProfile.tp7.pickerParams.contains { $0.id == "tp7.recSeq" })
    }

    /// Play/stop is safe to modulate, so it does appear.
    func testPlayIsLfoTargetable() {
        XCTAssertTrue(DeviceProfile.tp7.pickerParams.contains { $0.id == "tp7.play" })
    }
}

/// Play-reverses-when-playing, and momentary scrubbing with a speed ramp.
final class TP7ScrubAndReverseTests: XCTestCase {

    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tp7.transport
        clock.playTogglesDirection = DeviceProfile.tp7.caps.playReversesWhenPlaying
    }

    // MARK: - Play reverses

    /// First play rolls the tape; a second press while rolling reverses, matching the
    /// TP-7's own play button rather than re-sending play.
    func testSecondPlayReversesInsteadOfReplaying() {
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "first press plays")

        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 60]], "second press reverses")
        XCTAssertEqual(clock.transportDirection, -1)

        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "and back to forward")
    }

    /// The OP-1 has no such behaviour — play must keep meaning play.
    func testOP1PlayDoesNotReverse() {
        let c = ClockEngine()
        c.router = destination
        c.transport = DeviceProfile.op1Field.transport
        c.playTogglesDirection = DeviceProfile.op1Field.caps.playReversesWhenPlaying
        c.play()
        destination.reset()
        c.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "OP-1 play always plays")
    }

    // MARK: - Momentary scrub

    /// The TP-7 seeks via a persistent speed state, so scrubbing is press-and-hold.
    func testTP7HasMomentaryScrubButOP1DoesNot() {
        XCTAssertTrue(clock.hasMomentaryScrub)
        let c = ClockEngine()
        c.transport = DeviceProfile.op1Field.transport
        XCTAssertFalse(c.hasMomentaryScrub, "the OP-1 seeks by SPP nudge, not a held speed")
    }

    /// Holding starts the reel at about 1x rather than jumping straight to the configured speed.
    func testScrubStartsAtNormalSpeed() {
        destination.reset()
        clock.beginScrub(forward: true)
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "64 + 4 = forward at 1x")
        clock.endScrub()
    }

    /// Releasing must return CC 18 to centre, or the tape keeps rolling after the finger lifts.
    func testReleasingScrubStopsTheReel() {
        clock.beginScrub(forward: true)
        destination.reset()
        clock.endScrub()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 64]], "centre = stopped")
    }

    /// And the user's configured seek speed survives a scrub.
    func testScrubRestoresTheConfiguredSpeed() {
        clock.transportSpeed = 4.0
        clock.beginScrub(forward: false)
        clock.endScrub()
        XCTAssertEqual(clock.transportSpeed, 4.0, accuracy: 0.001)
    }

    /// On a nudge-style device, "begin scrub" just fires the nudge once — there is no held state.
    func testScrubFallsBackToASingleNudgeOnOP1() {
        let c = ClockEngine()
        c.router = destination
        c.transport = DeviceProfile.op1Field.transport
        destination.reset()
        c.beginScrub(forward: true)
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127], [0xF2, 16, 0]], "one tape seek")
    }
}
