import Foundation

// The device profile literals. Each is a plain data description of one Teenage Engineering
// field-system device — see DeviceProfile.swift for what the types mean.
//
// CC numbers come from the official MIDI references:
//   OP-1 Field — see README.md
//   TP-7       — https://teenage.engineering/guides/tp-7#midi-reference
//   TX-6       — https://teenage.engineering/guides/tx-6#midi-reference

// MARK: - OP-1 Field

extension DeviceProfile {

    /// Four tracks on MIDI channels 0-3, master FX/compressor on channel 0, 0-99 display scale.
    ///
    /// The parameter ids here are deliberately the raw values of the old `Parameter` enum, so
    /// LFO clips saved by earlier builds keep resolving after the multi-device refactor.
    /// **Never rename one.** See `legacyParamIdMap` in AppState for the migration hook.
    static let op1Field = DeviceProfile(
        id: "op1",
        displayName: "op-1 field",
        nameTokens: ["op-1", "op1"],
        trackCount: 4,
        masterChannel: 0,
        params: op1Params,
        defaultParamId: "volume",
        defaultVolume: 90,
        transport: TransportMap(
            play: [.midiStartOrContinue],
            stop: [.midiStop],
            // Tape prev/next bar: CC nudge + Song Position Pointer seek.
            prev: [.tapeSeek(cc: 82, steps: -1)],
            next: [.tapeSeek(cc: 83, steps: +1)],
            prevSymbol: "arrow.left",
            nextSymbol: "arrow.right"
        ),
        caps: DeviceCapabilities(
            hasPan: true,
            canBeClockMaster: true,
            followsClock: true,
            hasTempoParam: true,
            clockLabel: "op1"
        )
    )

    private static let op1Params: [ParamSpec] = {
        /// A per-track-only parameter on a track-relative CC.
        func trackOnly(_ id: String, _ short: String, cc: Int, role: ParamRole = .generic) -> ParamSpec {
            ParamSpec(id: id, name: id, short: short,
                      track: .cc(cc: cc, channel: .trackRelative(offset: 0), encoding: .continuous),
                      master: nil, role: role)
        }
        /// A parameter that exists on tracks and on master, but in a different CC bank.
        /// Master always lands on channel 0 — the OP-1 addresses its master bus there.
        func trackAndMaster(_ id: String, _ short: String, cc: Int, masterCC: Int) -> ParamSpec {
            ParamSpec(id: id, name: id, short: short,
                      track: .cc(cc: cc, channel: .trackRelative(offset: 0), encoding: .continuous),
                      master: .cc(cc: masterCC, channel: .pinned(0), encoding: .continuous))
        }

        var p: [ParamSpec] = [
            trackOnly("volume", "vol", cc: 7, role: .volume),
            trackOnly("pan", "pan", cc: 10, role: .pan),
            ParamSpec(id: "mute", name: "mute", short: "mut",
                      track: .cc(cc: 9, channel: .trackRelative(offset: 0),
                                 encoding: .switching(SwitchEncoding())),
                      master: nil, role: .mute),
            // Tempo has no CC — it retunes the app's own clock.
            ParamSpec(id: "tempo", name: "tempo", short: "tmp",
                      track: nil, master: .virtualTempo, role: .tempo),
        ]

        // Synth-engine parameters. Track-only: the OP-1 has no master equivalent.
        for i in 1...4 { p.append(trackOnly("par \(i)", "p\(i)", cc: 45 + i)) }

        let envNames = ["A", "D", "S", "R"]
        for (i, n) in envNames.enumerated() {
            p.append(trackOnly("env \(n)", "e\(n)", cc: 50 + i))
        }

        // fx 1-4: per-track patch FX (CC 54-57), master FX (CC 70-73).
        for i in 1...4 { p.append(trackAndMaster("fx \(i)", "fx\(i)", cc: 53 + i, masterCC: 69 + i)) }

        // lfo 1-4: per-track patch LFO (CC 58-61). On master these are the master COMPRESSOR
        // (CC 74-77) — a long-standing intentional overload of the same UI parameter.
        for i in 1...4 { p.append(trackAndMaster("lfo \(i)", "l\(i)", cc: 57 + i, masterCC: 73 + i)) }

        return p
    }()
}

// MARK: - Shared builders

private func perTrack(_ id: String, _ name: String, _ short: String, cc: Int,
                      role: ParamRole = .generic,
                      encoding: ValueEncoding = .continuous,
                      tracks: ClosedRange<Int>? = nil) -> ParamSpec {
    ParamSpec(id: id, name: name, short: short,
              track: .cc(cc: cc, channel: .trackRelative(offset: 0), encoding: encoding),
              master: nil, role: role, availableTracks: tracks)
}

/// A control that lives on a fixed channel of its own rather than on a track — the TX-6's
/// master bus and FX sends, the TP-7's global record/loop. These surface under the master (m)
/// target, which is why they carry a `master` binding and no `track` binding.
private func masterOnly(_ id: String, _ name: String, _ short: String,
                        cc: Int, channel: Int,
                        encoding: ValueEncoding = .continuous,
                        lfoTargetable: Bool = true) -> ParamSpec {
    ParamSpec(id: id, name: name, short: short,
              track: nil,
              master: .cc(cc: cc, channel: .pinned(channel), encoding: encoding),
              lfoTargetable: lfoTargetable)
}

/// A master-level pitch-bend control (the TP-7's playback speed).
private func masterPitchBend(_ id: String, _ name: String, _ short: String,
                             channel: Int) -> ParamSpec {
    ParamSpec(id: id, name: name, short: short,
              track: nil, master: .pitchBend(channel: .pinned(channel)))
}

/// TE's documented on/off convention for the 6-channel devices: 0-63 off, 64-127 on.
private let teSwitch = ValueEncoding.switching(SwitchEncoding(onValue: 127, offValue: 0, threshold: 64))

// MARK: - TX-6

extension DeviceProfile {

    /// Six mixer channels on MIDI channels 0-5, master bus on channel 6, and the two FX buses
    /// on channels 7 and 8. The FX buses have no track of their own, so they appear as
    /// master-only parameters under the (m) target.
    static let tx6 = DeviceProfile(
        id: "tx6",
        displayName: "tx-6",
        nameTokens: ["tx-6", "tx6"],
        trackCount: 6,
        masterChannel: 6,
        params: tx6Params,
        defaultParamId: "tx6.vol",
        defaultVolume: 90,
        transport: TransportMap(
            // CC 46 is a single stateless toggle, so each op only fires in the matching state.
            play: [.toggleCC(ch: 6, cc: 46, value: 127, whenPlaying: false), .midiStartOrContinue],
            stop: [.toggleCC(ch: 6, cc: 46, value: 127, whenPlaying: true), .midiStop],
            // CC 47 is a relative tempo encoder — nudge down/up rather than seek.
            prev: [.ccRelative(ch: 6, cc: 47, delta: -1)],
            next: [.ccRelative(ch: 6, cc: 47, delta: +1)],
            prevSymbol: "minus",
            nextSymbol: "plus"
        ),
        caps: DeviceCapabilities(
            hasPan: true,
            // The TX-6 guide documents no MIDI clock output, so the app stays master.
            canBeClockMaster: false,
            followsClock: true,     // UNVERIFIED — see notes/RESEARCH.md
            hasTempoParam: false,
            clockLabel: "tx6",
            // Verified on hardware: in controller mode the TX-6 transmits its own map on
            // channel 1 (encoder CC 31, FX I/II CC 33/34, knobs CC 7-24), which overlaps the
            // receive map on different meanings. Do not mirror it into the mixer UI.
            mirrorsIncomingCC: false
        ),
        // Verified on hardware: a default TX-6 ignores the app entirely until both are set.
        setupSteps: [
            "set `midi control` to `in` — until you do, the tx-6 ignores everything the app sends. note this also stops the tx-6 sending its own knob/fader messages.",
            "set `clock SRC` to `usb` — otherwise it won't follow the app's tempo.",
            "while an lfo drives a channel, moving that channel's fader on the tx-6 will fight the lfo rather than take over. pause the chip first.",
        ]
    )

    private static let tx6Params: [ParamSpec] = {
        var p: [ParamSpec] = [
            perTrack("tx6.vol",      "volume",     "vol", cc: 7,  role: .volume),
            perTrack("tx6.pan",      "pan",        "pan", cc: 8,  role: .pan),
            perTrack("tx6.gain",     "gain",       "gn",  cc: 9),
            // CC 120 is standard MIDI "all sound off" — TE reuses it per channel for mute.
            perTrack("tx6.mute",     "mute",       "mut", cc: 120, role: .mute, encoding: teSwitch),
            perTrack("tx6.filter",   "filter",     "flt", cc: 74),
            perTrack("tx6.eqHi",     "eq high",    "eqh", cc: 85),
            perTrack("tx6.eqMid",    "eq mid",     "eqm", cc: 86),
            perTrack("tx6.eqLo",     "eq low",     "eql", cc: 87),
            perTrack("tx6.comp",     "comp",       "cmp", cc: 93),
            perTrack("tx6.synWave",  "syn wave",   "sw",  cc: 3),
            perTrack("tx6.synFreq",  "syn freq",   "sf",  cc: 89),
            perTrack("tx6.synLen",   "syn len",    "sl",  cc: 90),
            perTrack("tx6.synDet",   "syn detune", "sd",  cc: 95),
            perTrack("tx6.fx1Send",  "fx1 send",   "f1s", cc: 91),
            perTrack("tx6.auxSend",  "aux send",   "ax1", cc: 92),
            perTrack("tx6.aux2Send", "aux2 send",  "ax2", cc: 94),
            perTrack("tx6.seqPat",   "seq pattern","seq", cc: 14),
        ]

        // Master bus — MIDI channel 7 (0-based 6).
        p += [
            masterOnly("tx6.mainVol",  "main vol",  "mvo", cc: 7,   channel: 6),
            masterOnly("tx6.auxVol",   "aux vol",   "avo", cc: 14,  channel: 6),
            masterOnly("tx6.cueVol",   "cue vol",   "cvo", cc: 15,  channel: 6),
            masterOnly("tx6.localCtl", "local ctl", "loc", cc: 122, channel: 6, encoding: teSwitch),
        ]

        // FX I and FX II — MIDI channels 8 and 9 (0-based 7 and 8). Same CC layout on each
        // bus, told apart only by channel, so the labels carry the bus number.
        for (n, ch) in [(1, 7), (2, 8)] {
            p += [
                masterOnly("tx6.fx\(n).en",  "fx\(n) en",  "f\(n)e", cc: 82, channel: ch, encoding: teSwitch),
                masterOnly("tx6.fx\(n).eng", "fx\(n) eng", "f\(n)g", cc: 15, channel: ch),
                masterOnly("tx6.fx\(n).p1",  "fx\(n) p1",  "f\(n)a", cc: 12, channel: ch),
                masterOnly("tx6.fx\(n).p2",  "fx\(n) p2",  "f\(n)b", cc: 13, channel: ch),
                masterOnly("tx6.fx\(n).p3",  "fx\(n) p3",  "f\(n)c", cc: 14, channel: ch),
            ]
        }
        // The one control each FX bus does not share with the other.
        p.append(masterOnly("tx6.fx1.ret", "fx1 return", "f1r", cc: 7, channel: 7))
        p.append(masterOnly("tx6.fx2.trk", "fx2 track",  "f2t", cc: 9, channel: 8))

        // Deliberately absent: CC 47 (tempo relative). It is a relative encoder, so an LFO on
        // it would drift the tempo in one direction forever instead of oscillating. It is
        // reachable through the transport −/+ buttons only.
        return p
    }()
}

// MARK: - TP-7

extension DeviceProfile {

    /// A field recorder, not a mixer: six mix channels and input gain on the first three, with
    /// record/cue/loop as global controls under the master target. No pan.
    static let tp7 = DeviceProfile(
        id: "tp7",
        displayName: "tp-7",
        nameTokens: ["tp-7", "tp7"],
        trackCount: 6,
        masterChannel: 0,
        params: tp7Params,
        defaultParamId: "tp7.vol",
        defaultVolume: 90,
        transport: TransportMap(
            // Real-time transport only. CC 14 is the TP-7's RECORD control, not play — sending
            // it here would arm recording every time the user pressed play, over a take.
            // Verified on hardware: 0xFA/0xFB/0xFC drive the tape directly (in any midi mode
            // except `ctrl`), so no CC is needed. Record stays available as the `tp7.rec` param.
            // Stop must send BOTH: CC 18 = 64 zeroes the speed, 0xFC stops the transport.
            // Verified on hardware — CC 18 takes over the transport once given any value other
            // than 64, and 0xFC alone will NOT release it (a seeking tape keeps rolling).
            // Stopping holds position; it does not rewind. See notes/RESEARCH.md.
            play: [.midiStartOrContinue],
            stop: [.directionalTransport(ch: 0, cc: 18, center: 64, deadZone: 4, unitSpeed: 4, direction: 0), .midiStop],
            // CC 18 is a persistent bipolar speed control, not a nudge: below 64 plays
            // backwards, above 64 forwards. Speed comes from ClockEngine.transportSpeed, mapped
            // through the measured dead zone — offset 4 is barely moving, 1x is offset ~7.5.
            prev: [.directionalTransport(ch: 0, cc: 18, center: 64, deadZone: 4, unitSpeed: 4, direction: -1)],
            next: [.directionalTransport(ch: 0, cc: 18, center: 64, deadZone: 4, unitSpeed: 4, direction: +1)],
            prevSymbol: "backward.fill",
            nextSymbol: "forward.fill"
        ),
        caps: DeviceCapabilities(
            hasPan: false,
            // Verified on hardware: in `sync` midi mode the TP-7 streams 24 PPQN continuously
            // (~1769 ticks in 40 s ≈ 110 BPM), so the app can slave to it. The published MIDI
            // reference documents no clock output — this was only found by listening.
            canBeClockMaster: true,
            followsClock: true,     // UNVERIFIED — see notes/RESEARCH.md
            hasTempoParam: true,
            clockLabel: "tp7",
            // TE's own docs: "TP-7 never reports its state via MIDI." There is nothing to
            // mirror, and in `ctrl` mode what it does send is its own button map.
            // The TP-7's own play button reverses the tape when pressed while already playing.
            playReversesWhenPlaying: true,
            mirrorsIncomingCC: false
        ),
        setupSteps: [
            "any midi mode except `ctrl` works. `ctrl` turns the tp-7 into a midi controller for other gear — it stops playback and stops accepting anything the app sends.",
            "use `sync` if you want the app to follow the tp-7's tempo — it streams midi clock in that mode. volume/mute/gain control works in `off` and `sync` alike.",
        ]
    )

    private static let tp7Params: [ParamSpec] = [
        perTrack("tp7.vol",  "mix volume", "vol", cc: 7,   role: .volume),
        perTrack("tp7.mute", "mix mute",   "mut", cc: 120, role: .mute, encoding: teSwitch),
        // CC 9 is the preamp for the three physical INPUT JACKS, which sit upstream of the mix
        // channels: jack -> gain -> mix. So it is addressed per jack, not per track, and
        // changing it does nothing audible unless a signal is actually arriving on that jack.
        // Verified on hardware. Modelled as master-level controls because a track number would
        // wrongly imply gain 1 belongs to track 1. See notes/RESEARCH.md.
        masterOnly("tp7.in1Gain", "in1 gain", "g1", cc: 9, channel: 0),
        masterOnly("tp7.in2Gain", "in2 gain", "g2", cc: 9, channel: 1),
        masterOnly("tp7.in3Gain", "in3 gain", "g3", cc: 9, channel: 2),
        // Verified on hardware: CC 14 ARMS record (blinking light, 0s, no audio) rather than
        // starting it, and it is absolute — sending 127 twice leaves it armed, it does not
        // toggle. The arm persists indefinitely; 0xFC cancels it.
        //
        // Not LFO-targetable. Arming/disarming at LFO rates has no musical use, and record is
        // the one parameter where automation can destroy a take rather than merely sound wrong.
        // Excluded on the precautionary principle: CC 14 alone could not be made to capture
        // audio in testing, but "could not" is not "cannot".
        masterOnly("tp7.rec",    "record",  "rec", cc: 14, channel: 0, encoding: teSwitch,
                   lfoTargetable: false),

        // Playback speed. Measured against the sync-mode clock: bend is a *signed velocity
        // offset* of about -20..+40 ticks/s, added to whatever CC 18 and the transport are
        // already doing — not a magnitude multiplier. Playing forward that reads as x0.54 at 0,
        // x1.0 at centre and x2.14 at full; while reversing the sense flips (bend up slows the
        // reverse), which is what proves it is signed rather than scaling.
        // NOTE: it persists across stop/play with no on-screen feedback, so a stray value
        // silently pitch-shifts everything until returned to centre.
        masterPitchBend("tp7.speed", "speed", "spd", channel: 0),

        // Direction, behaving like mute: a two-state control on CC 18. Above the threshold
        // plays forward, below plays reverse. CC 18 takes over the transport as soon as it is
        // sent. The values are offset 8 either side of centre, not 4: measurement showed offset
        // 4 is inside the dead zone and barely moves the tape (x0.06), while 8 is x1.13.
        ParamSpec(id: "tp7.direction", name: "direction", short: "dir",
                  track: nil,
                  master: .cc(cc: 18, channel: .pinned(0),
                              encoding: .switching(SwitchEncoding(onValue: 72, offValue: 56,
                                                                  threshold: 64)))),

        // The play *button*, as a parameter. Each rising edge is one press, so it inherits the
        // button's behaviour exactly — including play-while-playing reversing the tape. Falling
        // edges do nothing: a press is a press, not a hold.
        //
        // This is `.pressPlay` rather than a list of bytes precisely so it delegates to
        // ClockEngine.play(). A square wave on this alternates forward and reverse.
        ParamSpec(id: "tp7.playPress", name: "play", short: "ply",
                  track: nil,
                  master: .transport(onOps: [.pressPlay], offOps: [])),

        // Transport as a gate, which is a different thing: above the threshold plays, below
        // stops. Edge-triggered in Controller, so a sustained LFO value does not re-fire
        // transport every clock tick. A square wave on this gates playback in rhythm rather
        // than flipping direction.
        ParamSpec(id: "tp7.play", name: "play/stop", short: "p/s",
                  track: nil,
                  master: .transport(onOps: [.midiStartOrContinue], offOps: [.midiStop])),

        // Record, as the full physical sequence: stop (only if already playing), arm, then
        // play — which is what actually starts a recording.
        //
        // DESTRUCTIVE. This can capture over a take. Kept out of the LFO picker: the sequence
        // is edge-triggered so it will not fire continuously, but an LFO crossing the threshold
        // would still start recordings unattended.
        ParamSpec(id: "tp7.recSeq", name: "rec seq", short: "rsq",
                  track: nil,
                  master: .transport(
                      onOps: [.toggleCC(ch: 0, cc: 18, value: 64, whenPlaying: true),
                              .midiStop,
                              .cc(ch: 0, cc: 14, value: 127),
                              .midiStartOrContinue],
                      offOps: [.midiStop, .cc(ch: 0, cc: 14, value: 0)]),
                  lfoTargetable: false),

        // Tempo. The TP-7 has no tempo control of its own, but it follows MIDI clock in `sync`
        // mode — so retuning the app's clock retunes the device too, as well as the LFO rate.
        // Same mechanism the OP-1 uses; sends no CC of its own.
        ParamSpec(id: "tp7.tempo", name: "tempo", short: "tmp",
                  track: nil, master: .virtualTempo, role: .tempo),
        // No observable effect on hardware — sent 127 x4 and 0 x2 with the tape playing, and
        // nothing changed on the display or in the audio. Recorded as unverified rather than
        // broken: the TP-7 never reports its state, so "silently working" and "doing nothing"
        // are indistinguishable. Not LFO-targetable — toggling a mode-enable at LFO rates is
        // not musical, and an unverifiable control is worse than an absent one.
        masterOnly("tp7.cueRec", "cue rec", "cue", cc: 16, channel: 0, encoding: teSwitch,
                   lfoTargetable: false),
        // off / in / out — but a STATE MACHINE, not three independent values: `in` must be set
        // before `out`, and once a loop is active only `off` releases it. Verified on hardware:
        // sending `out` with no prior `in` is silently discarded.
        //
        // Not LFO-targetable as a result. An LFO sweeping 0-127 would map cyclically onto
        // 0/1/2, so most of the sweep would be discarded and the rest would drop loop points at
        // arbitrary moments — noise, not modulation.
        masterOnly("tp7.loop", "loop", "lp", cc: 17, channel: 0,
                   encoding: .enumerated(count: 3), lfoTargetable: false),
    ]
}
