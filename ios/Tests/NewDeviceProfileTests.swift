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
        // Measured at 32.00 ticks/s against a device reading 80 BPM, with clock SRC internal
        // and clock out enabled. An earlier capture saw none, but that was the default config.
        XCTAssertTrue(profile.caps.canBeClockMaster, "streams clock when clock out is enabled")
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

    /// −/+ nudge tempo via the relative encoder on CC 47, in two's complement: 1...63 count up,
    /// 127...65 count down. NOT centred on 64 — sending 65/63 for ±1 made the device read -63
    /// and +63, so a press lurched the tempo hugely the wrong way (reported as "+ halves the
    /// bpm, - doubles it"). Confirmed by the TP-7's wheel: 1,2,3 clockwise, 125,126,127 counter.
    func testTempoNudgeUsesTwosComplementRelative() {
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB6, 47, 1]], "one step up")

        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB6, 47, 127]], "one step down = -1")
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

    /// The TP-7 has no tempo CC and does not follow incoming MIDI clock (measured twice: 60 and
    /// 130 BPM streamed at a rolling memo left its own clock at 36 ticks/s), so it has no tempo
    /// parameter. See notes/TP7_VS_TP7MIDI.md, test 10.
    func testCapabilities() {
        XCTAssertFalse(profile.caps.hasTempoParam)
        XCTAssertFalse(profile.caps.followsClock)
        // TE's docs: "TP-7 never reports its state via MIDI" — nothing to mirror.
        XCTAssertFalse(profile.caps.mirrorsIncomingCC)
    }

    /// Both 6-channel devices can be the tempo source, but only once configured for it — and
    /// the configuration differs: the TP-7 needs `sync` midi mode, the TX-6 needs internal clock
    /// SRC plus clock `out`. Neither does it by default, so the app stays master until asked.
    ///
    /// Both were originally marked `false` from captures taken in the default configuration.
    /// "It sent nothing while I watched" is not the same as "it cannot send".
    func testBothSixChannelDevicesCanBeTheTempoSource() {
        XCTAssertTrue(DeviceProfile.tp7.caps.canBeClockMaster, "streams clock in `sync` mode")
        XCTAssertTrue(DeviceProfile.tx6.caps.canBeClockMaster, "streams clock when clock out is on")
        XCTAssertTrue(DeviceProfile.op1Field.caps.canBeClockMaster)
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

    /// Measured 2026-10-16: the OP-1 Field transmits no CC when its controls move and does not
    /// echo CC it receives (USB and BLE), so there is nothing to mirror. This pins the flag to
    /// that measurement; see notes/RESEARCH.md before changing it.
    func testOP1DoesNotMirrorIncomingCC() {
        XCTAssertFalse(DeviceProfile.op1Field.caps.mirrorsIncomingCC)
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
    /// From a parked tape there is no dead zone, so at the default 2x the offset is 4 * 2 = 8.
    func testSeekIsBipolarAroundSixtyFour() {
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 72]], "forward = 64 + offset")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 56]], "reverse = 64 - offset")
    }

    /// While the tape is rolling the device's own +1x transport is inside every CC 18 reading, so
    /// the parked formula does not apply. Reverse needs the forward 1x cancelled first (see
    /// `testReverseWhilePlayingUsesTheMeasuredSlope`); this keeps the parked case above honest.
    func testReverseWhilePlayingDoesNotUseTheParkedFormula() {
        clock.play()
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 53]], "reverse 2x while rolling: 64 - round(3.76 * 3)")
    }

    /// Forward while rolling is NOT the dead-zone formula. The tape's own 1x adds to the CC, so
    /// speed = 1 + (CC - 64) / 4.26 and CC = 64 + 4.26 * (speed - 1). Measured on a TP-7 on
    /// 2026-10-16: CC 68 / 72 / 76 / 80 gave 1.94x / 2.87x / 3.81x / 4.75x (the old formula sent 76
    /// for 2x, which is 3.81x). See notes/TP7_VS_TP7MIDI.md.
    /// Reverse while rolling has its own slope: speed = (64 - CC) / 3.76 - 1. Measured on a TP-7 on
    /// 2026-10-16 with the counter counting down: CC 56 / 52 / 48 gave 1.13x / 2.19x / 3.25x (the
    /// old formula sent exactly those for 1x / 2x / 3x, 9 to 13% over).
    func testReverseWhilePlayingUsesTheMeasuredSlope() {
        clock.play()
        func prev(at speed: Double) -> [[UInt8]] {
            clock.transportSpeed = speed
            destination.reset()
            clock.tapePrev()
            return destination.packets
        }
        XCTAssertEqual(prev(at: 0.25), [[0xB0, 18, 59]], "64 - round(4.7): about 0.33x reverse")
        XCTAssertEqual(prev(at: 1.0), [[0xB0, 18, 56]], "64 - round(7.52); the nearest step to 1x is 1.13x")
        XCTAssertEqual(prev(at: 2.0), [[0xB0, 18, 53]], "64 - round(11.28): 1.93x")
        XCTAssertEqual(prev(at: 3.0), [[0xB0, 18, 49]], "64 - round(15.04): 2.99x")
        XCTAssertEqual(prev(at: 14.0), [[0xB0, 18, 8]], "the top of the ramp, 13.9x")
    }

    func testForwardWhilePlayingUsesTheMeasuredAdditiveFormula() {
        clock.play()
        func next(at speed: Double) -> [[UInt8]] {
            clock.transportSpeed = speed
            destination.reset()
            clock.tapeNext()
            return destination.packets
        }
        XCTAssertEqual(next(at: 0.25), [[0xB0, 18, 61]], "slower than 1x sits under 64")
        XCTAssertEqual(next(at: 1.0), [[0xB0, 18, 64]], "1x is plain playback")
        XCTAssertEqual(next(at: 2.0), [[0xB0, 18, 68]], "2x (the default): 1.94x measured")
        XCTAssertEqual(next(at: 3.0), [[0xB0, 18, 73]], "64 + round(8.52); 72 measured 2.87x")
        XCTAssertEqual(next(at: 14.0), [[0xB0, 18, 119]], "the top of the scrub ramp, inside range")
    }

    /// A tape the device itself is rolling (sync mode, clock arriving) is rolling too, even though
    /// the app never pressed play.
    func testSeekWhileTheDeviceIsRollingKeepsTheDeadZone() {
        clock.router?.onClock?()           // a tick arrives: the tape is moving
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "forward 2x while rolling")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 53]], "reverse 2x while rolling")
    }

    /// Speed is a multiple of normal playback, not a raw CC offset, and the mapping is affine:
    /// `offset = deadZone + unitSpeed * multiplier`. Measured against the sync-mode clock —
    /// offset 4 is inside the dead zone (x0.06), and 1x lands at ~7.5, so 8 is the nearest step.
    func testSpeedIsAMultipleOfNormalPlayback() {
        clock.transportSpeed = 1.0            // 1x
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "64 + 4 = forward at 1x, parked")
        destination.reset()
        clock.tapePrev()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 60]], "64 - 4 = reverse at 1x, parked")
    }

    /// The default is 2x — a fast-forward, matching the "chipmunks" heard at CC 18 = 72.
    func testDefaultSpeedIsDoubleNormal() {
        XCTAssertEqual(clock.transportSpeed, 2.0)
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 72]], "64 + 8 = forward at 2x, parked")
    }

    func testHalfSpeed() {
        clock.transportSpeed = 0.5
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 66]], "64 + 2 = forward at 0.5x, parked")
    }

    /// Speed must never push CC 18 out of range, and never round down to zero — an offset of 0
    /// would read as "stopped" no matter which direction was asked for.
    func testSpeedIsClampedAndNeverRoundsToZero() {
        clock.transportSpeed = 99
        XCTAssertEqual(clock.transportSpeed, 16.0, "clamped to 16x — CC 18 saturates before that")
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
        XCTAssertEqual(send("tp7.pitchbend", 0),   [[0xE0, 0, 0]], "slowest = x0.25")
        XCTAssertEqual(send("tp7.pitchbend", 127), [[0xE0, 127, 127]], "fastest = x2.0")
    }

    /// Mid-scale must land at pitch-bend centre, which the device treats as normal speed.
    func testSpeedMidScaleIsAboutCentre() {
        let p = send("tp7.pitchbend", 64)[0]
        let value = Int(p[1]) | Int(p[2]) << 7
        XCTAssertEqual(p[0], 0xE0)
        XCTAssertEqual(Double(value), 8192, accuracy: 100, "64 should sit at x1.0 (8192)")
    }

    func testSpeedIsMasterOnlyAndTargetable() {
        let spec = DeviceProfile.tp7.param("tp7.pitchbend")!
        XCTAssertTrue(spec.isMasterOnly)
        XCTAssertTrue(spec.lfoTargetable, "speed is exactly the kind of thing to modulate")
    }

    // MARK: - Direction

    /// Direction must NOT be a raw CC. CC 18 is additive, so a fixed value lands on x1.13 or
    /// ~3x depending on which way the device was already going — state the app cannot read.
    /// Going through ClockEngine gets the stop/continue resync instead.
    func testDirectionIsATransportBindingNotARawCC() {
        let spec = DeviceProfile.tp7.param("tp7.direction")!
        guard case .transport(let onOps, let offOps, _)? = DeviceProfile.tp7.binding(spec, track: 0) else {
            return XCTFail("direction must be a .transport binding, not a raw CC")
        }
        XCTAssertEqual(onOps,  [.setDirection(forward: true)])
        XCTAssertEqual(offOps, [.setDirection(forward: false)])
        XCTAssertTrue(spec.isMasterOnly)
    }

    /// Absolute, not momentary: high is forward and low is reverse, whatever the current state.
    /// That is what makes a square LFO play forward on the high half and reverse on the low.
    func testDirectionIsAbsoluteAndSnapsAtTheThreshold() {
        let spec = DeviceProfile.tp7.param("tp7.direction")!
        guard case .transport(let onOps, let offOps, let threshold)? =
                DeviceProfile.tp7.binding(spec, track: 0) else { return XCTFail("not transport") }
        XCTAssertEqual(threshold, 64)
        // Every value resolves to one of exactly two op lists — never an intermediate speed.
        for v in stride(from: 0.0, through: 127.0, by: 1.0) {
            let ops = Int(v.rounded()) >= threshold ? onOps : offOps
            XCTAssertTrue(ops == [.setDirection(forward: true)] || ops == [.setDirection(forward: false)],
                          "value \(v) produced \(ops)")
        }
    }

    // MARK: - Tempo

    /// There is no TP-7 tempo parameter: it would only retune the app's own clock, because the
    /// device ignores incoming clock. The OP-1's tempo parameter stays master-only.
    func testTheTP7HasNoTempoParameter() {
        XCTAssertNil(DeviceProfile.tp7.param("tp7.tempo"))
        XCTAssertFalse(DeviceProfile.tp7.params.contains { $0.role == .tempo },
                       "no parameter on the TP-7 may retune the app's clock")
        XCTAssertTrue(DeviceProfile.op1Field.param("tempo")!.isMasterOnly)
    }

    func testSpeedAndDirectionAppearInThePickerButTempoDoesNot() {
        let ids = DeviceProfile.tp7.pickerParams.map(\.id)
        XCTAssertTrue(ids.contains("tp7.pitchbend"))
        XCTAssertTrue(ids.contains("tp7.direction"))
        XCTAssertFalse(ids.contains("tp7.tempo"))
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

    /// Every play press restarts the LFOs: the first, the ones that reverse, and the ones that go
    /// forward again. Seen on a TP-7 on 2026-10-18: reverse presses restarted them by accident (the
    /// device answered the stop/continue resync with a Start) and the forward-again press did not.
    /// An LFO driving the play parameter presses play on each rising edge. That press must not restart
    /// the LFOs, or the LFO restarts itself, climbs back to its threshold and fires again at a
    /// fraction of its period.
    func testAnLFODrivenPlayPressDoesNotRestartTheLFOs() {
        var restarts = 0
        clock.onPlay = { restarts += 1 }
        clock.runOps([.pressPlay])                 // forward: the first press
        clock.runOps([.pressPlay])                 // reverse: a press while rolling
        clock.runOps([.pressPlay])                 // forward again
        XCTAssertEqual(restarts, 0)
        XCTAssertTrue(clock.isPlaying, "the press itself still did its job")
        clock.play()                               // a press by the user does restart them
        XCTAssertEqual(restarts, 1)
    }

    func testEveryPlayPressRestartsTheLFOsIncludingTheReversingOnes() {
        var restarts = 0
        clock.onPlay = { restarts += 1 }
        for press in 1...6 {          // forward, reverse, forward, reverse, forward, reverse
            clock.play()
            XCTAssertEqual(restarts, press, "press \(press) must restart the LFOs")
        }
    }

    /// First play rolls the tape; a second press while rolling reverses, matching the
    /// TP-7's own play button rather than re-sending play.
    func testSecondPlayReversesInsteadOfReplaying() {
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "first press plays")

        // Reverse first forces a known direction (CC 18 to centre, stop, continue) because CC 18
        // adds to the device's own direction and the device never reports it — without this, a
        // tape already reversing from the hardware button would stack to ~3x. Then CC 18 at the
        // measured 1x offset, then a bend trim, because CC 18 alone cannot express 1x.
        destination.reset()
        clock.play()
        let trim = clock.reverseTrimBend
        XCTAssertEqual(destination.packets,
                       [[0xB0, 18, 64], [0xFC], [0xFB],
                        [0xB0, 18, 56],
                        [0xE0, UInt8(trim & 0x7F), UInt8((trim >> 7) & 0x7F)]],
                       "second press resyncs direction, then reverses via CC 18 plus the trim")
        XCTAssertEqual(clock.transportDirection, -1)

        // Forward hands control back to the device's own transport rather than driving CC 18,
        // so playback is at exactly the normal rate instead of an approximation of it. The trim
        // must be released first, or it would pitch-shift forward playback.
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xE0, 0, 64], [0xB0, 18, 64], [0xFB]],
                       "forward releases the bend trim and CC 18, then lets the device play")
    }

    /// Reversal is gated on *playing*, not on direction: a stopped tape must always play
    /// forward, however it was moving before it was stopped. This works only because `stop()`
    /// resets `transportDirection` to 0 — without that the engine would still believe it was
    /// reversing, and the next play would take the release-and-continue path instead of playing.
    func testPlayAfterStopAlwaysPlaysForward() {
        clock.play()                 // forward
        clock.play()                 // reverse
        clock.stop()
        XCTAssertEqual(clock.transportDirection, 0, "stop must clear the direction")
        XCTAssertFalse(clock.isPlaying)

        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]],
                       "a stopped tape plays forward — it must not reverse or re-send CC 18")

        // And the cycle restarts cleanly: the next press reverses again.
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets[0], [0xB0, 18, 64], "second press resyncs, then reverses")
        XCTAssertTrue(destination.packets.contains([0xB0, 18, 56]), "and engages reverse")
    }

    /// Stopping mid-reverse must hand the machine back in a neutral state. Bend persists across
    /// stop/play with no on-screen feedback, so a trim left applied would silently pitch-shift
    /// the next playback with no visible cause.
    func testStopWhileReversingReleasesTheBendTrim() {
        clock.play()
        clock.play()                 // reversing, trim applied
        destination.reset()
        clock.stop()
        XCTAssertEqual(destination.packets, [[0xE0, 0, 64], [0xB0, 18, 64], [0xFC]],
                       "release the trim, then CC 18, then stop")
    }

    /// A tape started from the device itself must not cost the user a button press. In `sync`
    /// mode the TP-7 sends clock only while rolling, so an arriving tick is proof it is playing —
    /// the only state signal this device emits.
    func testIncomingClockMakesTheFirstPressReverse() {
        XCTAssertFalse(clock.isPlaying, "the app does not know the device was started by hand")
        destination.onClock?()                 // one tick from the device
        XCTAssertTrue(clock.deviceIsRolling)

        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets.first, [0xB0, 18, 64],
                       "first press reverses instead of re-asserting play")
        XCTAssertTrue(destination.packets.contains([0xB0, 18, 56]))
        XCTAssertEqual(clock.transportDirection, -1)
    }

    /// Without a tick the app must assume nothing: `0xFC` on a genuinely stopped tape rewinds the
    /// TP-7 to zero, so the resync may only run when the tape is known to be moving.
    func testNoClockMeansFirstPressJustPlays() {
        XCTAssertFalse(clock.deviceIsRolling)
        destination.reset()
        clock.play()
        XCTAssertEqual(destination.packets, [[0xFB]], "no evidence of rolling — just play")
    }

    // MARK: - Absolute direction

    /// Reverse must go through the same resync as a play-press: recentre CC 18, stop, continue,
    /// then engage CC 18 and trim. Without it, CC 18 is additive and stacks on whatever the
    /// device was doing.
    func testSetDirectionReverseResyncsThenEngages() {
        clock.play()                 // rolling forward
        destination.reset()
        clock.setDirection(forward: false)
        let trim = clock.reverseTrimBend
        XCTAssertEqual(destination.packets,
                       [[0xB0, 18, 64], [0xFC], [0xFB],
                        [0xB0, 18, 56],
                        [0xE0, UInt8(trim & 0x7F), UInt8((trim >> 7) & 0x7F)]])
        XCTAssertEqual(clock.transportDirection, -1)
    }

    /// Forward releases the trim and hands the transport back, so the tape runs at the device's
    /// own rate rather than an approximation.
    func testSetDirectionForwardReleasesAndContinues() {
        clock.play()
        clock.setDirection(forward: false)
        destination.reset()
        clock.setDirection(forward: true)
        XCTAssertEqual(destination.packets, [[0xE0, 0, 64], [0xB0, 18, 64], [0xFB]])
        XCTAssertEqual(clock.transportDirection, 0)
    }

    /// Idempotent. An LFO holding a value must not re-send the stop/continue resync — that
    /// would stutter the tape on every clock tick.
    func testSetDirectionIsIdempotent() {
        clock.play()
        clock.setDirection(forward: false)
        destination.reset()
        clock.setDirection(forward: false)
        clock.setDirection(forward: false)
        XCTAssertEqual(destination.packets, [], "already reversing — nothing to send")

        clock.setDirection(forward: true)
        destination.reset()
        clock.setDirection(forward: true)
        XCTAssertEqual(destination.packets, [], "already forward — nothing to send")
    }

    /// The OP-1 has no directional transport, so this must do nothing at all rather than
    /// emitting CC 18 at a device that has no such control.
    func testSetDirectionIsANoOpWithoutADirectionalTransport() {
        let c = ClockEngine()
        c.router = destination
        c.transport = DeviceProfile.op1Field.transport
        destination.reset()
        c.setDirection(forward: false)
        c.setDirection(forward: true)
        XCTAssertEqual(destination.packets, [])
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

    /// Holding starts at the ramp's start speed rather than jumping straight to the top.
    func testScrubStartsAtTheRampStartSpeed() {
        XCTAssertEqual(clock.scrubStartSpeed, 1.0)
        destination.reset()
        clock.beginScrub(forward: true)
        XCTAssertEqual(destination.packets, [[0xB0, 18, 68]], "64 + 4*1 = 1x from a parked tape")
        clock.endScrub()
    }

    /// The top of the ramp must stay inside CC 18's range. Rolling reverse reaches the floor first
    /// (64 - 3.76 * (speed + 1) >= 0 up to about 16x, forward rolling up to about 15.8x), and the
    /// old dead-zone limit of 14.75x is kept as a conservative ceiling for the ramp.
    func testMaxScrubSpeedStaysWithinCC18Range() {
        XCTAssertLessThanOrEqual(clock.maxScrubSpeed, 14.75, "beyond this CC 18 saturates")
        clock.play()
        clock.transportSpeed = clock.maxScrubSpeed
        destination.reset()
        clock.tapePrev()
        let value = destination.packets[0][2]
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertEqual(value, 8, "reverse 64 - round(3.76 * 15) = 8, inside the floor")
    }

    func testMaxScrubSpeedFromAParkedTapeHasMoreHeadroom() {
        clock.transportSpeed = clock.maxScrubSpeed
        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB0, 18, 120]], "64 + 4*14 = 120, no dead zone")
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
        XCTAssertEqual(destination.packets, [[0xB0, 83, 127]], "one nudge: the CC alone, no SPP")
    }
}

/// A `direction` LFO driven through the real chain: AutomationEngine -> Controller ->
/// ClockEngine -> destination. Reproduces "the direction LFO does nothing" end to end.
final class TP7DirectionLfoTests: XCTestCase {

    private var destination: RecordingDestination!
    private var clock: ClockEngine!
    private var ctrl: Controller!
    private var automation: AutomationEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tp7.transport
        ctrl = Controller(router: destination)
        ctrl.setProfile(.tp7)
        ctrl.transportRunner = { [weak clock] ops in clock?.runOps(ops) }
        automation = AutomationEngine()
        automation.controller = ctrl
        automation.setProfile(.tp7)
    }

    /// A square wave spanning the threshold must flip the tape both ways as it cycles.
    func testSquareLfoOnDirectionFlipsTheTape() {
        clock.play()                       // rolling forward
        let clip = LfoClip(deviceId: "tp7", track: 0, paramId: "tp7.direction",
                           wave: .square, rateTicks: 24, depth: 50, centerValue: 64,
                           inverted: false, loop: true, originalValue: 64)
        automation.add(clip)

        destination.reset()
        var sawReverse = false, sawForward = false
        for t in 1...96 {
            automation.onTick(t)
            if destination.packets.contains([0xB0, 18, 56]) { sawReverse = true }
            if destination.packets.contains([0xE0, 0, 64]) { sawForward = true }
        }
        XCTAssertTrue(sawReverse, "the low half of the square must engage reverse")
        XCTAssertTrue(sawForward, "the high half must return to forward")
    }
}

/// Where a new LFO starts. Most parameters have no privileged value and keep whatever the user
/// had; pitch bend does, and the global default of 90 is badly wrong for it.
final class DefaultCentreTests: XCTestCase {

    /// 90 in display units is MIDI 116, which is bend ~14963 — roughly 1.9x speed. A fresh chip
    /// would start the tape at nearly double speed and leave it pitched up when stopped, with
    /// nothing on the device to show why.
    func testPitchBendCentresNearNeutral() {
        let spec = DeviceProfile.tp7.param("tp7.pitchbend")!
        let centre = try! XCTUnwrap(spec.defaultCenter)
        XCTAssertEqual(centre, 49)

        // Display 49 -> MIDI 63 -> bend 8126, within 1% of true centre (8192).
        let midi = uiToMidi(centre)
        XCTAssertEqual(midi, 63)
        let bend = Int((Double(midi) * 16383.0 / 127.0).rounded())
        XCTAssertLessThan(abs(bend - 8192), 100, "should sit within ~1% of neutral bend")
    }

    /// Only parameters with a real neutral point declare one — otherwise selecting a parameter
    /// would yank the centre away from wherever the user had put it.
    func testOnlyPitchBendDeclaresACentre() {
        for p in DeviceRegistry.all {
            for spec in p.params where spec.defaultCenter != nil {
                guard case .pitchBend? = spec.master else {
                    return XCTFail("\(p.id) '\(spec.id)' declares a centre but is not pitch bend")
                }
            }
        }
    }
}

/// Tempo nudges have to reach whoever owns the clock. While the app is master the TX-6 is slaved
/// to it, so its internal tempo is ignored and sending CC 47 changes a number nothing is using —
/// which is exactly how it looked on hardware: the buttons did nothing over BLE.
final class TempoNudgeRoutingTests: XCTestCase {

    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.transport = DeviceProfile.tx6.transport
    }

    func testNudgesTheAppTempoWhileAppIsMaster() {
        clock.enableClock(bpm: 120)
        var nudges: [Double] = []
        clock.appTempoNudge = { nudges.append($0) }

        destination.reset()
        clock.tapeNext()
        clock.tapePrev()
        XCTAssertEqual(nudges, [1, -1])
        // The master clock is running, so 0xF8 ticks are expected here — what must not appear is
        // a CC to a device whose own tempo is being ignored.
        let ccs = destination.packets.filter { $0.count == 3 && $0[0] & 0xF0 == 0xB0 }
        XCTAssertEqual(ccs, [], "must not send CC to a device that is slaved to us")
        clock.disableClock()
    }

    func testSendsTheRelativeCCWhenTheDeviceOwnsTheClock() {
        clock.disableClock()
        var nudged = false
        clock.appTempoNudge = { _ in nudged = true }

        destination.reset()
        clock.tapeNext()
        XCTAssertEqual(destination.packets, [[0xB6, 47, 1]], "one step up, two's complement")
        XCTAssertFalse(nudged, "the device owns the tempo — do not move the app's")
    }

    /// Scoping: only the TX-6 nudges tempo from these buttons. The OP-1 seeks tape by SPP and the
    /// TP-7 scrubs with CC 18, so neither can reach this path however the clock mode is set.
    func testOnlyTheTX6UsesRelativeNudges() {
        for p in DeviceRegistry.all where p.id != "tx6" {
            let ops = p.transport.prev + p.transport.next
            XCTAssertFalse(ops.contains { if case .ccRelative = $0 { return true } else { return false } },
                           "\(p.id) must not use .ccRelative")
        }
        let tx6Ops = DeviceProfile.tx6.transport.prev + DeviceProfile.tx6.transport.next
        XCTAssertTrue(tx6Ops.contains { if case .ccRelative = $0 { return true } else { return false } })
    }
}

/// What happens to a parameter when preview stops targeting it. Preview sweeps the real
/// parameter, so leaving it where the LFO last put it silently changes the user's mix.
final class PreviewRestoreTests: XCTestCase {

    private var destination: RecordingDestination!
    private var ctrl: Controller!
    private var engine: AutomationEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        ctrl = Controller(router: destination)
        ctrl.setProfile(.op1Field)
        engine = AutomationEngine()
        engine.setProfile(.op1Field)
        engine.controller = ctrl
    }

    private func clip(_ paramId: String, track: Int, original: Double) -> LfoClip {
        LfoClip(deviceId: "op1", track: track, paramId: paramId, wave: .sine, rateTicks: 96,
                depth: 20, centerValue: 64, inverted: false, loop: true, originalValue: original)
    }

    func testTurningPreviewOffPutsTheParameterBack() {
        engine.setPreview([clip("volume", track: 1, original: 80)])
        destination.reset()
        engine.clearPreview()
        XCTAssertEqual(destination.packets, [[0xB0, 7, 80]])
    }

    func testSwitchingParameterRestoresTheOldOneAndNotTheNew() {
        engine.setPreview([clip("fx 1", track: 0, original: 100)])
        destination.reset()
        engine.setPreview([clip("fx 2", track: 0, original: 50)])
        XCTAssertEqual(destination.packets, [[0xB0, 70, 100]], "fx 1 goes back; fx 2 is untouched")
    }

    func testTurningOffOneTrackRestoresOnlyThatTrack() {
        engine.setPreview([clip("volume", track: 1, original: 80), clip("volume", track: 2, original: 90)])
        destination.reset()
        engine.setPreview([clip("volume", track: 2, original: 90)])
        XCTAssertEqual(destination.packets, [[0xB0, 7, 80]])
    }

    /// Every slider tweak rebuilds the preview clips with new UUIDs. That must neither restore
    /// nor forget the value recorded before the preview first touched the parameter.
    func testRebuildingTheSameTargetSendsNothingAndKeepsTheFirstOriginal() {
        engine.setPreview([clip("volume", track: 1, original: 80)])
        destination.reset()
        engine.setPreview([clip("volume", track: 1, original: 99)])   // an LFO-driven value
        XCTAssertTrue(destination.packets.isEmpty)
        engine.clearPreview()
        XCTAssertEqual(destination.packets, [[0xB0, 7, 80]], "restores the value from before preview")
    }

    func testNothingIsRestoredWhileAnEnabledChipDrivesTheParameter() {
        engine.add(clip("volume", track: 1, original: 80))
        engine.setPreview([clip("volume", track: 1, original: 80)])
        destination.reset()
        engine.clearPreview()
        XCTAssertTrue(destination.packets.isEmpty, "the chip owns it; a restore would only glitch it")
    }

    /// A chip created while preview is running must remember the value from before the preview,
    /// not whatever the preview had driven the app's state to.
    func testPreviewOriginalValueIsTheOneFromBeforePreview() {
        XCTAssertNil(engine.previewOriginalValue(track: 1, paramId: "volume"))
        engine.setPreview([clip("volume", track: 1, original: 15)])
        engine.setPreview([clip("volume", track: 1, original: 95)])   // rebuilt mid-sweep
        XCTAssertEqual(engine.previewOriginalValue(track: 1, paramId: "volume"), 15)
        XCTAssertNil(engine.previewOriginalValue(track: 2, paramId: "volume"))
        engine.clearPreview()
        XCTAssertNil(engine.previewOriginalValue(track: 1, paramId: "volume"))
    }

    func testClearingWithNothingPreviewedSendsNothing() {
        engine.clearPreview()
        XCTAssertTrue(destination.packets.isEmpty)
    }
}

/// Play restarts every active LFO from the start of its cycle.
final class LfoRestartOnPlayTests: XCTestCase {

    /// `Controller` is main-actor isolated, and releasing one as a local variable at the end of
    /// a test method crashes the Swift runtime (`swift_task_deinitOnExecutor`). Keep them in a
    /// stored property so they live as long as the test case, like the other test classes do.
    private var keepAlive: [AnyObject] = []

    private func makeEngine() -> (AutomationEngine, RecordingDestination) {
        let dest = RecordingDestination()
        let ctrl = Controller(router: dest)
        ctrl.setProfile(.op1Field)
        let engine = AutomationEngine()
        engine.setProfile(.op1Field)
        engine.controller = ctrl
        keepAlive += [ctrl, dest, engine]
        return (engine, dest)
    }

    private func clip(loop: Bool = true) -> LfoClip {
        LfoClip(deviceId: "op1", track: 1, paramId: "volume", wave: .saw, rateTicks: 96,
                depth: 40, centerValue: 64, inverted: false, loop: loop, originalValue: 64)
    }

    /// What a chip sends on its very first tick: the start of its wave.
    private func firstPacket(preview: Bool = false) -> [UInt8] {
        let (engine, dest) = makeEngine()
        if preview { engine.setPreview([clip()]) } else { engine.add(clip()) }
        dest.reset()
        engine.onTick(0)
        return dest.packets.first ?? []
    }

    func testRestartPutsAChipBackAtTheStartOfItsCycle() {
        let start = firstPacket()
        XCTAssertFalse(start.isEmpty)

        let (engine, dest) = makeEngine()
        engine.add(clip())
        for t in 0..<50 { engine.onTick(t) }      // part-way through the cycle
        dest.reset()
        engine.onTick(50)
        XCTAssertNotEqual(dest.packets.first ?? [], start, "mid-cycle is not the start")

        engine.restartAll()
        dest.reset()
        engine.onTick(51)
        XCTAssertEqual(dest.packets.first ?? [], start, "restart goes back to the start of the wave")
    }

    func testRestartResendsEvenWhenTheValueHasNotChanged() {
        let (engine, dest) = makeEngine()
        engine.add(clip())
        engine.onTick(0)
        engine.restartAll()
        dest.reset()
        engine.onTick(96)      // would be the same phase as before without the restart
        XCTAssertFalse(dest.packets.isEmpty, "the restart must always emit its first value")
    }

    func testPausedChipsAreNotRestarted() {
        let c = clip()
        let (engine, dest) = makeEngine()
        engine.add(c)
        engine.setEnabled(c.id, enabled: false)
        engine.restartAll()
        dest.reset()
        engine.onTick(10)
        XCTAssertTrue(dest.packets.isEmpty, "a paused chip stays silent")
        engine.setEnabled(c.id, enabled: true)
        engine.onTick(11)
        XCTAssertFalse(dest.packets.isEmpty)
    }

    func testRestartReachesPreviewToo() {
        let start = firstPacket(preview: true)
        XCTAssertFalse(start.isEmpty)

        let (engine, dest) = makeEngine()
        engine.setPreview([clip()])
        for t in 0..<50 { engine.onTick(t) }
        engine.restartAll()
        dest.reset()
        engine.onTick(50)
        XCTAssertEqual(dest.packets.first ?? [], start)
    }
}

/// Which row of the device picker gets the green "connected" box.
final class DevicePickerHighlightTests: XCTestCase {

    func testOnlyTheConnectedDeviceOnTheActiveTransportIsHighlighted() {
        XCTAssertTrue(DevicePickerView.isConnectedRow("OP-1", connectedName: "OP-1", transportIsActive: true))
        XCTAssertFalse(DevicePickerView.isConnectedRow("TX-6", connectedName: "OP-1", transportIsActive: true))
    }

    func testNothingIsHighlightedWhenDisconnectedOrTheTransportIsNotActive() {
        XCTAssertFalse(DevicePickerView.isConnectedRow("OP-1", connectedName: nil, transportIsActive: true))
        XCTAssertFalse(DevicePickerView.isConnectedRow("OP-1", connectedName: "OP-1", transportIsActive: false),
                       "a device connected on the other transport must not light up this list")
    }

    /// BLE rows match on the peripheral, not its name, which can change between discovery and
    /// connection.
    func testBluetoothRowsMatchOnPeripheralIdentity() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(DevicePickerView.isConnectedRow(a, connectedID: a, transportIsActive: true))
        XCTAssertFalse(DevicePickerView.isConnectedRow(b, connectedID: a, transportIsActive: true))
        XCTAssertFalse(DevicePickerView.isConnectedRow(a, connectedID: nil, transportIsActive: true))
        XCTAssertFalse(DevicePickerView.isConnectedRow(a, connectedID: a, transportIsActive: false))
    }

    /// An OP-1 in midi sync sends nothing, so the router never claims a transport for an
    /// auto-connected device. The picker must still show it as connected.
    func testAnAutoConnectedDeviceStillCountsWhenNothingHasClaimedTheRouter() {
        XCTAssertEqual(MidiRouter.effectiveTransport(active: nil, usbConnected: false, bleConnected: true), .ble)
        XCTAssertEqual(MidiRouter.effectiveTransport(active: nil, usbConnected: true, bleConnected: false), .usb)
        XCTAssertEqual(MidiRouter.effectiveTransport(active: nil, usbConnected: true, bleConnected: true), .usb,
                       "matches send(): usb wins when nothing is claimed")
        XCTAssertNil(MidiRouter.effectiveTransport(active: nil, usbConnected: false, bleConnected: false))
    }

    func testAClaimedTransportAlwaysWins() {
        XCTAssertEqual(MidiRouter.effectiveTransport(active: .ble, usbConnected: true, bleConnected: true), .ble)
        XCTAssertEqual(MidiRouter.effectiveTransport(active: .usb, usbConnected: true, bleConnected: true), .usb)
    }

    func testNameMatchIgnoresCase() {
        XCTAssertTrue(DevicePickerView.isConnectedRow("op-1", connectedName: "OP-1", transportIsActive: true))
    }
}

/// Opening the device picker must not make a working Bluetooth link look lost.
final class BleScanGuardTests: XCTestCase {
    func testNoScanWhileTheLinkIsUp() {
        XCTAssertFalse(BLEMidi.shouldScan(linkIsUp: true))
    }
    func testScansWhenThereIsNoLink() {
        XCTAssertTrue(BLEMidi.shouldScan(linkIsUp: false))
    }
}

/// When to tell the user their LFOs are stuck waiting for a clock that isn't coming.
final class LfosWaitingForClockTests: XCTestCase {
    private func waiting(master: Bool = false, lfos: Bool = true, age: Double?) -> Bool {
        AppState.lfosWaitingForClock(isClockMaster: master, hasLfos: lfos, secondsSinceTick: age)
    }

    func testNeverWaitingWhenTheAppIsTheClock() {
        XCTAssertFalse(waiting(master: true, age: nil))
        XCTAssertFalse(waiting(master: true, age: 60))
    }

    func testNothingToWaitForWithoutLFOs() {
        XCTAssertFalse(waiting(lfos: false, age: nil))
    }

    func testSlavedWithNoClockEverReceivedIsWaiting() {
        XCTAssertTrue(waiting(age: nil), "e.g. the op-1 is in the wrong tempo mode")
    }

    func testAClockThatIsArrivingIsNotWaiting() {
        XCTAssertFalse(waiting(age: 0.03))
        XCTAssertFalse(waiting(age: 1.4))
    }

    func testAClockThatHasGoneQuietIsWaiting() {
        XCTAssertTrue(waiting(age: 1.6), "e.g. a stopped TP-7, which sends clock only while its tape moves")
        XCTAssertTrue(waiting(age: 30))
    }
}

/// The status bar must show a connected device even when nothing has claimed the router: an OP-1 in
/// midi sync sends no MIDI, so the router never claims a transport for it.
final class ConnectionStatusTests: XCTestCase {

    private func status(active: MidiRouter.Transport? = nil, usb: USBMidi.State = .disconnected,
                        ble: BLEMidi.State = .scanning) -> (label: String, isConnected: Bool) {
        AppState.connectionStatus(active: active, usb: usb, ble: ble)
    }

    func testAConnectedUSBDeviceShowsEvenWhenNothingHasClaimedTheRouter() {
        let s = status(usb: .connected("OP-1"), ble: .notFound)
        XCTAssertEqual(s.label, "OP-1 (usb)")
        XCTAssertTrue(s.isConnected, "was reading Bluetooth's \"no device found\" while USB worked")
    }

    func testAConnectedBluetoothDeviceShowsWhenNothingHasClaimedTheRouter() {
        let s = status(usb: .disconnected, ble: .connected("OP-1"))
        XCTAssertEqual(s.label, "OP-1 (ble)")
        XCTAssertTrue(s.isConnected)
    }

    func testUSBWinsWhenNothingIsClaimedAndBothAreConnected() {
        XCTAssertEqual(status(usb: .connected("OP-1"), ble: .connected("OP-1")).label, "OP-1 (usb)",
                       "the same rule MidiRouter.send uses")
    }

    func testAClaimedTransportAlwaysWins() {
        XCTAssertEqual(status(active: .ble, usb: .connected("OP-1"), ble: .connected("OP-1")).label, "OP-1 (ble)")
        XCTAssertEqual(status(active: .usb, usb: .connected("OP-1"), ble: .connected("OP-1")).label, "OP-1 (usb)")
    }

    func testNothingConnectedStillReportsScanningAndNoDevice() {
        XCTAssertEqual(status(ble: .scanning).label, "scanning…")
        XCTAssertFalse(status(ble: .scanning).isConnected)
        XCTAssertEqual(status(ble: .notFound).label, "no device found")
    }

    func testUnmatchedUSBDevicesAreListedWhenNothingIsConnected() {
        let s = status(usb: .found(["Some Synth"]), ble: .scanning)
        XCTAssertEqual(s.label, "Some Synth")
        XCTAssertFalse(s.isConnected)
    }
}

/// The layout (profile) must follow the same transport as the status text and the MIDI routing.
/// Seen broken 2026-10-17: an OP-1 on BLE and a TX-6 plugged into USB-C showed `op-1 (ble)` with
/// the TX-6's 6-track layout, and MIDI kept going to the OP-1.
final class ProfileFollowsTheRoutedTransportTests: XCTestCase {

    private func id(active: MidiRouter.Transport? = nil, usb: String? = nil, ble: String? = nil,
                    usbUp: Bool = false, bleUp: Bool = false) -> String? {
        AppState.profileId(active: active, usbProfile: usb, bleProfile: ble,
                           usbConnected: usbUp, bleConnected: bleUp)
    }

    /// The reported case: BLE already carries the OP-1, a TX-6 then appears on USB.
    func testAClaimedBluetoothDeviceKeepsItsLayoutWhenAnotherDeviceAppearsOnUSB() {
        XCTAssertEqual(id(active: .ble, usb: "tx6", ble: "op1", usbUp: true, bleUp: true), "op1",
                       "was \"tx6\" (usb always won) while the status said op-1 (ble)")
    }

    func testPickingTheUSBDeviceMovesTheLayoutWithTheRouting() {
        XCTAssertEqual(id(active: .usb, usb: "tx6", ble: "op1", usbUp: true, bleUp: true), "tx6")
    }

    /// Nothing claimed: `MidiRouter.send` uses USB when it is connected, so the layout does too.
    func testWhenNothingIsClaimedUSBWinsLikeSend() {
        XCTAssertEqual(id(usb: "tx6", ble: "op1", usbUp: true, bleUp: true), "tx6")
    }

    func testWhenNothingIsClaimedAndOnlyBluetoothIsConnectedItsDeviceWins() {
        XCTAssertEqual(id(ble: "op1", bleUp: true), "op1")
    }

    func testAnUnrecognisedClaimedDeviceDoesNotBorrowTheOtherTransportsLayout() {
        XCTAssertNil(id(active: .ble, usb: "tx6", ble: nil, usbUp: true, bleUp: true),
                     "the routed device is unrecognised: keep the last layout, don't switch to the one we are not talking to")
    }

    func testNothingConnectedFallsBackToWhateverMatchedLast() {
        XCTAssertEqual(id(usb: "tx6", ble: "op1"), "tx6")
        XCTAssertNil(id())
    }
}

/// An active connection is never taken over by a new one; when it goes away the other takes over.
final class RoutingOwnershipTests: XCTestCase {

    private func owner(_ current: MidiRouter.Transport?, usb: Bool, ble: Bool) -> MidiRouter.Transport? {
        MidiRouter.transportAfterChange(current: current, usbConnected: usb, bleConnected: ble)
    }

    func testTheFirstTransportToConnectClaimsTheRoutingImmediately() {
        XCTAssertEqual(owner(nil, usb: false, ble: true), .ble, "no need to wait for a message")
        XCTAssertEqual(owner(nil, usb: true, ble: false), .usb)
    }

    /// Round 2 of 2026-10-17: a TX-6 on USB, then the picker's scan auto-connected the OP-1 on BLE.
    func testALateConnectionNeverTakesOverAnActiveOne() {
        XCTAssertEqual(owner(.usb, usb: true, ble: true), .usb)
        XCTAssertEqual(owner(.ble, usb: true, ble: true), .ble, "round 1: the TX-6 arriving on USB changes nothing")
    }

    func testWhenTheOwnerDisconnectsTheOtherConnectedTransportTakesOver() {
        XCTAssertEqual(owner(.usb, usb: false, ble: true), .ble)
        XCTAssertEqual(owner(.ble, usb: true, ble: false), .usb)
    }

    func testWhenTheOwnerDisconnectsWithNothingElseTheClaimIsReleased() {
        XCTAssertNil(owner(.usb, usb: false, ble: false))
        XCTAssertNil(owner(.ble, usb: false, ble: false))
    }

    /// Seen 2026-10-17: tapping the OP-1's row while a TX-6 was active flickered to 4 tracks and
    /// straight back, because the claim was judged on "connected" while BLE was still "connecting".
    func testAnExplicitPickSurvivesTheConnectingPhase() {
        XCTAssertEqual(MidiRouter.transportAfterChange(current: .ble, usbConnected: true,
                                                       bleConnected: false, bleConnecting: true), .ble)
    }

    func testAFailedConnectionFallsBackToTheWorkingDevice() {
        XCTAssertEqual(MidiRouter.transportAfterChange(current: .ble, usbConnected: true,
                                                       bleConnected: false, bleConnecting: false), .usb,
                       "no longer connecting and never connected: the claim is dropped")
    }

    func testAConnectingTransportNeverClaimsOnItsOwn() {
        XCTAssertNil(MidiRouter.transportAfterChange(current: nil, usbConnected: false,
                                                     bleConnected: false, bleConnecting: true),
                     "only a claim already made is kept while connecting; nothing claims until connected")
    }

    func testAnUnconnectedClaimantNeverKeepsTheClaim() {
        XCTAssertEqual(owner(.ble, usb: true, ble: false), .usb, "ble claimed but is no longer connected")
    }
}

/// The picker lists what is available now: a device that stops advertising drops off the list.
final class StaleBluetoothDevicesTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testADeviceNotSeenForLongerThanTheWindowIsStale() {
        let stale = BLEMidi.staleIds(lastSeen: [a: 100, b: 104], now: 106, staleAfter: 5, keep: [])
        XCTAssertEqual(stale, [a], "a was last seen 6 s ago, b 2 s ago")
    }

    func testADeviceSeenWithinTheWindowStays() {
        XCTAssertTrue(BLEMidi.staleIds(lastSeen: [a: 100], now: 104.9, staleAfter: 5, keep: []).isEmpty)
    }

    func testTheConnectedDeviceIsNeverStaleBecauseItStopsAdvertising() {
        XCTAssertTrue(BLEMidi.staleIds(lastSeen: [a: 0], now: 1000, staleAfter: 5, keep: [a]).isEmpty)
    }

    func testOnlyTheQuietOnesAreDropped() {
        let stale = Set(BLEMidi.staleIds(lastSeen: [a: 0, b: 99, c: 0], now: 100, staleAfter: 5, keep: [c]))
        XCTAssertEqual(stale, [a])
    }
}

/// The tempo shown while slaved to a device must not flicker with the ticks' arrival jitter.
final class SlaveTempoStabilityTests: XCTestCase {

    /// Seen 2026-10-18 with a TX-6 at 80 BPM (clock out on): the readout flipped between 79.9,
    /// 80.0 and 80.1 and could not be read.
    func testAJitteryReadingAroundAWholeTempoShowsItExactly() {
        var shown = 80.0
        for reading in [79.93, 80.04, 80.11, 79.88, 80.07, 80.13, 79.91, 80.02] {
            shown = ClockEngine.stabilizedBpm(candidate: reading, current: shown)
            XCTAssertEqual(shown, 80.0, "reading \(reading) must not move the display")
        }
    }

    func testTheFirstReadingIsShownRounded() {
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 79.94, current: 0), 80.0)
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 120.06, current: 0), 120.0)
    }

    func testARealTempoChangeComesThroughAtOnce() {
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 90.02, current: 80.0), 90.0)
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 79.0, current: 80.0), 79.0)
    }

    /// A TX-6 was measured at exactly 400 BPM over Bluetooth; the app showed 300.0 because a reading above
    /// 300 was ignored. The single ceiling covers every TE device, and still rejects nonsense.
    func testATempoFromADeviceIsAcceptedUpToTheHighestTEMaximum() {
        XCTAssertTrue(AppState.acceptsIncomingBpm(400))
        XCTAssertTrue(AppState.acceptsIncomingBpm(440), "an OP-1 Field at its 440 maximum")
        XCTAssertFalse(AppState.acceptsIncomingBpm(640_000), "the old timestamp bug read this")
        XCTAssertFalse(AppState.acceptsIncomingBpm(19.9))
        XCTAssertEqual(AppState.maxBpm, 440, "one ceiling, the highest of TE's own limits")
    }

    func testAGenuineFractionalTempoIsNotForcedToAWholeNumber() {
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 119.5, current: 0), 119.5)
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 80.3, current: 80.0), 80.3)
    }

    /// The thresholds scale with the tempo: +/-0.3 BPM is ordinary jitter at 400 and must not flicker.
    func testJitterAtAFastTempoStaysPut() {
        var shown = 400.0
        for reading in [399.7, 400.3, 399.8, 400.2, 399.6, 400.35] {
            shown = ClockEngine.stabilizedBpm(candidate: reading, current: shown)
            XCTAssertEqual(shown, 400.0)
        }
    }

    func testARealChangeAtAFastTempoStillComesThrough() {
        XCTAssertEqual(ClockEngine.stabilizedBpm(candidate: 410.0, current: 400.0), 410.0)
    }

    func testJitterAroundAFractionalTempoStaysPut() {
        var shown = 80.3
        for reading in [80.22, 80.36, 80.28, 80.33] {
            shown = ClockEngine.stabilizedBpm(candidate: reading, current: shown)
            XCTAssertEqual(shown, 80.3)
        }
    }
}

/// Over Bluetooth the tempo is read from the sender's own tick timestamps, not from when the ticks
/// happened to arrive. Measured 2026-10-18 with a TX-6 at 80 BPM: arrival timing spread 5.7 ms per
/// tick (tempo +/-0.2 BPM, one stall of 537 ms), the TX-6's stamps 0.4 ms.
final class SenderStampedClockTests: XCTestCase {

    /// Stored properties, never locals: `ClockEngine` is main-actor isolated, and releasing one as a
    /// local at the end of a test method crashes the Swift runtime (swift_task_deinitOnExecutor), the
    /// same as `Controller` did. They live as long as the test case, like the other test classes.
    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.disableClock()                           // slaved to the device
        clock.antiJitter = true                        // these exercise the smoothing, which is off by default
    }

    // MARK: the interval between two stamps

    func testTheIntervalIsTheDifferenceOfTheStampsInSeconds() {
        XCTAssertEqual(ClockEngine.senderInterval(stampMs: 1281, lastMs: 1250)!, 0.031, accuracy: 1e-9)
    }

    func testTheThirteenBitCounterWrapsAt8192() {
        XCTAssertEqual(ClockEngine.senderInterval(stampMs: 20, lastMs: 8180)!, 0.032, accuracy: 1e-9)
    }

    func testStampsThatCannotBeATempoAreNotTrusted() {
        XCTAssertNil(ClockEngine.senderInterval(stampMs: 100, lastMs: nil), "no previous stamp")
        XCTAssertNil(ClockEngine.senderInterval(stampMs: 500, lastMs: 500), "a device that stamps everything 0")
        XCTAssertNil(ClockEngine.senderInterval(stampMs: 501, lastMs: 500), "1 ms is a stamp that barely moves")
        XCTAssertNotNil(ClockEngine.senderInterval(stampMs: 505, lastMs: 500), "5 ms is 500 BPM and is accepted")
        XCTAssertNil(ClockEngine.senderInterval(stampMs: 3000, lastMs: 500), "2.5 s is ~1 BPM")
    }

    // MARK: the stamp reaches the clock

    func testAParsedBluetoothPacketDeliversTheTimestampOfEveryTick() {
        var stamps: [Int] = []
        var ticks = 0
        // header 0x89 = top bits of 1234 (9), then (timestamp 0xD2 = low 82, message 0xF8), twice;
        // the second tick is 15 ms later: timestamp low 97 -> 1249
        let packet = Data([0x89, 0xD2, 0xF8, 0xE1, 0xF8])
        BleMidiPacket.parse(packet, onClock: { ticks += 1 }, onStart: nil, onStop: nil,
                            onClockStamp: { stamps.append($0) }, onCC: nil)
        XCTAssertEqual(stamps, [1234, 1249])
        XCTAssertEqual(ticks, 2)
    }

    /// 80 BPM is a tick every 31.25 ms. The stamps below are that, floored to whole milliseconds, and
    /// the ticks are fed back to back, so their arrival intervals are microseconds: the old
    /// arrival-timed code ignores every one of them. The stamps must give exactly 80.
    /// 400 BPM is a tick every 6.25 ms, so 1 ms stamps give intervals of 5, 6 and 7 ms. The 5 ms ones
    /// used to be thrown away as "arrival bursts", biasing the tempo low (the app showed 397.4 to
    /// 400.0, never above). Measured 2026-10-18 on a TX-6 over Bluetooth.
    func testAFastTempoIsNotBiasedByTheFiveMillisecondIntervals() {
        var t = 0.0
        for k in 0..<2000 {                       // alternating 5 and 7 ms: a mean of 6 ms = 416.67 BPM
            t += (k % 2 == 0) ? 5 : 7
            destination.onClockStamp?(Int(t) % 8192)
            destination.onClock?()
        }
        XCTAssertEqual(clock.bpm, 416.67, accuracy: 1.0, "was ~410 when the 5 ms intervals were dropped")
    }

    /// A real change must show at once, not ramp over the window: 80 then 90 BPM by the senders' stamps.
    func testATempoChangeShowsWithinAFewTicksNotAfterTheWholeWindow() {
        var t = 0.0
        for _ in 0..<200 { t += 31.25; destination.onClockStamp?(Int(t) % 8192); destination.onClock?() }
        XCTAssertEqual(clock.bpm, 80.0)
        let ms = 60_000.0 / (24 * 90)                       // 90 BPM: 27.78 ms per tick
        for _ in 0..<30 { t += ms; destination.onClockStamp?(Int(t) % 8192); destination.onClock?() }
        XCTAssertEqual(clock.bpm, 90.0, accuracy: 1.5, "30 ticks (0.8 s) after the change; the long window took 3 s")
    }

    // MARK: how often the BPM box is told

    func testTheFirstTempoIsShownAtOnce() {
        XCTAssertTrue(ClockEngine.shouldPublishBpm(now: 10, lastPublishTime: 0, current: 120, lastPublished: 0))
    }

    func testNothingIsPublishedWhenTheTempoHasNotChanged() {
        XCTAssertFalse(ClockEngine.shouldPublishBpm(now: 99, lastPublishTime: 1, current: 120, lastPublished: 120))
    }

    /// A tempo that is moving must not redraw the box on every tick: 4 updates a second at most.
    func testASmallChangeWaitsForTheDisplayInterval() {
        XCTAssertFalse(ClockEngine.shouldPublishBpm(now: 10.10, lastPublishTime: 10.0, current: 120.4, lastPublished: 120),
                       "0.1 s since the last update")
        XCTAssertTrue(ClockEngine.shouldPublishBpm(now: 10.26, lastPublishTime: 10.0, current: 120.4, lastPublished: 120),
                      "0.26 s: due")
    }

    func testADeliberateJumpIsShownAtOnce() {
        XCTAssertTrue(ClockEngine.shouldPublishBpm(now: 10.01, lastPublishTime: 10.0, current: 160, lastPublished: 120),
                      "33% is a jump, not jitter")
    }

    func testFourHundredBPMReadsFourHundred() {
        for k in 0..<3000 {
            destination.onClockStamp?(Int(Double(k) * 6.25) % 8192)
            destination.onClock?()
        }
        XCTAssertEqual(clock.bpm, 400.0)
    }

    func testTheTempoComesFromTheSendersStampsNotFromArrival() {
        for k in 0..<200 {
            destination.onClockStamp?(Int(Double(k) * 31.25) % 8192)
            destination.onClock?()
        }
        XCTAssertEqual(clock.bpm, 80.0, "was 0 (ignored) with arrival timing")
    }
}

/// With the anti-jitter smoothing off (the default), a sender-stamped tick's own interval is the tempo.
/// Measured on a TX-6 over Bluetooth, 2026-10-18: the stamps are accurate to 0.4 ms, so the smoothing only
/// added lag, and the display locks onto a new tempo at once.
final class RawStampedTempoTests: XCTestCase {
    private var destination: RecordingDestination!
    private var clock: ClockEngine!

    override func setUp() {
        super.setUp()
        destination = RecordingDestination()
        clock = ClockEngine()
        clock.router = destination
        clock.disableClock()
        XCTAssertFalse(clock.antiJitter, "off by default")
    }

    func testEachTicksOwnStampedIntervalIsTheTempo() {
        var t = 0
        func tick(_ interval: Int) {
            t += interval
            destination.onClockStamp?(t % 8192)
            destination.onClock?()
        }
        for _ in 0..<10 { tick(31) }
        XCTAssertEqual(clock.bpm, 80.6, "60 / (24 * 0.031): nothing averaged")
        tick(32)
        XCTAssertEqual(clock.bpm, 78.1, "the very next tick moves it: no window, no hysteresis")
    }

    /// The display limit stays: the box is told once, however many ticks arrive in an instant.
    func testTheDisplayIsStillLimitedToFourUpdatesASecond() {
        var told = 0
        clock.bpmCallback = { _ in told += 1 }
        var t = 0
        for k in 0..<200 {
            t += (k % 2 == 0) ? 31 : 32
            destination.onClockStamp?(t % 8192)
            destination.onClock?()
        }
        XCTAssertEqual(told, 1, "the ticks were fed back to back, well inside one 0.25 s interval")
    }

    func testTheSmoothingCanBeSwitchedBackOn() {
        clock.antiJitter = true
        var t = 0
        for k in 0..<200 {
            t += (k % 2 == 0) ? 31 : 32
            destination.onClockStamp?(t % 8192)
            destination.onClock?()
        }
        XCTAssertEqual(clock.bpm, 80.0, accuracy: 1.0, "averaged: 31.5 ms is 79.4 BPM, snapped and held")
    }
}
