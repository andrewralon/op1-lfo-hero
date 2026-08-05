import Foundation

// Describes a Teenage Engineering field-system device as data rather than code: which MIDI
// channels it uses, which CCs each parameter lives on, how values are encoded on the wire,
// and what transport it understands. Adding a device means adding a profile literal in
// DeviceProfiles.swift — no new branches in the engine or the UI.

// MARK: - Channel resolution

/// How a parameter's MIDI channel is derived from the UI track number.
enum ChannelRule: Hashable {
    /// Channel follows the track: `(track - 1) + offset`. Track 0 (master) uses the profile's
    /// `masterChannel` instead. This is the OP-1's whole model, and the TX-6/TP-7 per-track model.
    case trackRelative(offset: Int)
    /// A fixed 0-based channel regardless of track — the TX-6's master (ch 6) and FX buses
    /// (ch 7/8), and the TP-7's global record/loop controls.
    case pinned(Int)
}

// MARK: - Value encoding

/// A two-state parameter's wire encoding. The OP-1 mutes with a hard 127/0 on CC 9; the
/// TX-6/TP-7 use CC 120 with the "0-63 off, 64-127 on" convention from the TE guides.
struct SwitchEncoding: Hashable {
    var onValue  = 127
    var offValue = 0
    /// Incoming values >= this read as "on".
    var threshold = 64
    /// true → the MIDI "on" state means *unmuted* rather than muted. Verified false on the
    /// TX-6 (CC 120 = 127 mutes, 0 unmutes, absolute not toggle); unverified on the TP-7.
    /// See notes/RESEARCH.md.
    var inverted = false
}

/// How an app-side value (always MIDI units, 0-127) becomes the byte on the wire.
enum ValueEncoding: Hashable {
    case continuous
    case switching(SwitchEncoding)
    /// Relative encoder: 64 means "no change", values either side are deltas. Never an LFO
    /// target — an LFO on a relative encoder drifts monotonically instead of oscillating.
    case relative(center: Int)
    /// A small set of discrete states spread across 0-127 (TP-7 loop = off/in/out).
    case enumerated(count: Int)

    /// Convert an app-side 0-127 value into the byte actually sent.
    func wireValue(from v: Double) -> Int {
        switch self {
        case .continuous:
            return clamp7(Int(v.rounded()))
        case .switching(let e):
            let on = Int(v.rounded()) >= e.threshold
            return clamp7((on != e.inverted) ? e.onValue : e.offValue)
        case .relative(let center):
            return clamp7(center + Int(v.rounded()))
        case .enumerated(let count):
            guard count > 1 else { return 0 }
            let step = Int(v / 128.0 * Double(count))
            return max(0, min(count - 1, step))
        }
    }

    /// Interpret an incoming byte as a boolean, for switch-typed parameters.
    func isOn(_ value: Int) -> Bool {
        guard case .switching(let e) = self else { return value >= 64 }
        return (value >= e.threshold) != e.inverted
    }
}

private func clamp7(_ v: Int) -> Int { max(0, min(127, v)) }

// MARK: - Parameter

/// How a parameter reaches the wire.
enum ParamBinding: Hashable {
    case cc(cc: Int, channel: ChannelRule, encoding: ValueEncoding)
    /// Reserved for the TP-7's playback-speed rocker. Declared now so adding it later is not
    /// a second persistence migration.
    case pitchBend(channel: ChannelRule)
    /// App-internal BPM — no MIDI CC. The OP-1's "tempo" parameter drives ClockEngine directly.
    case virtualTempo
    /// A two-state control that fires transport op lists rather than a CC — for parameters
    /// whose effect is a real-time message (play/stop) or a multi-step sequence (record).
    /// Above `threshold` runs `onOps`, below runs `offOps`. Edge-triggered by the caller so a
    /// held state does not re-fire every tick.
    case transport(onOps: [TransportOp], offOps: [TransportOp], threshold: Int = 64)
}

/// What the app semantically knows about a parameter, beyond "it's a CC". Only these four
/// roles are mirrored in the mixer UI; everything else is generic and LFO-only.
enum ParamRole: String, Hashable {
    case generic, volume, pan, mute, tempo
}

/// One automatable parameter on one device.
///
/// `track` and `master` are separate bindings because a parameter can exist in both places on
/// different CCs (OP-1 fx 1 = CC 54 per track, CC 70 on master) or in only one (the TX-6's FX
/// buses are master-only; its per-channel EQ is track-only). A nil binding means "not available
/// there", which is what drives `isMasterOnly` / `isMasterCapable`.
struct ParamSpec: Identifiable, Hashable {
    /// Stable persistence id — written into saved LFO clips. Never rename one of these.
    let id: String
    /// Picker label. Lowercase, per the project's UI convention.
    let name: String
    /// Short label shown on LFO chips.
    let short: String
    let track:  ParamBinding?
    let master: ParamBinding?
    var role: ParamRole = .generic
    /// Restricts the parameter to a subset of tracks (the TP-7's input gain is inputs 1-3 only).
    /// nil = every track the profile has.
    var availableTracks: ClosedRange<Int>? = nil
    /// Center value (MIDI units) a new LFO on this parameter starts at.
    var defaultCenter: Double = 90
    /// false → hidden from the LFO parameter picker (relative encoders).
    var lfoTargetable = true

    var isMasterOnly: Bool    { track  == nil }
    var isMasterCapable: Bool { master != nil }

    func isAvailable(onTrack track: Int) -> Bool {
        if track == 0 { return master != nil }
        guard self.track != nil else { return false }
        guard let r = availableTracks else { return true }
        return r.contains(track)
    }

    /// Interpret an incoming byte as on/off, using this parameter's own switch encoding.
    func isOn(_ value: Int) -> Bool {
        guard case .cc(_, _, let enc) = (track ?? master) ?? .virtualTempo else { return value >= 64 }
        return enc.isOn(value)
    }
}

// Note: there is deliberately no per-device display scale. The app always shows 0-99 while
// sending 0-127, on every device — see `midiToUI` / `uiToMidi` in Models.swift. Keeping that
// app-wide rather than a profile knob is what stops the two from diverging per device.

// MARK: - Transport

/// One step of a transport button's action. A button is a list of these, sent in order.
enum TransportOp: Hashable {
    /// 0xFA the first time, 0xFB to resume — ClockEngine tracks which.
    case midiStartOrContinue
    case midiStop
    /// OP-1 tape seek: a CC nudge, then a Song Position Pointer, then resume if playing.
    case tapeSeek(cc: Int, steps: Int)
    case cc(ch: Int, cc: Int, value: Int)
    /// Relative encoder nudge — sends `64 + delta`. For genuine relative encoders only
    /// (the TX-6's tempo CC 47), where each message is an independent increment.
    case ccRelative(ch: Int, cc: Int, delta: Int)
    /// A persistent bipolar transport state: `center` stops, below plays backwards, above
    /// plays forwards, and distance from centre is speed. The TP-7's CC 18 works this way —
    /// it is a *setting*, not an event, so it keeps moving the tape until something changes it.
    ///
    /// Speed is **affine, not proportional**: there is a dead zone near `center` where the tape
    /// does not move at all, and speed rises linearly only beyond it. So
    ///
    ///     offset = deadZone + unitSpeed * multiplier
    ///
    /// where `deadZone` is the offset at which motion starts and `unitSpeed` is the additional
    /// offset per 1x of playback. The multiplier comes from `ClockEngine.transportSpeed`.
    ///
    /// On the TP-7 both are 4, measured rather than guessed: driving CC 18 while counting the
    /// sync-mode MIDI clock (whose tick rate is derived from tape speed) gives
    /// `rate = 11.69 * offset - 44 ticks/s` across offsets 4-8, so motion begins at offset ~3.76
    /// and 1x lands at ~7.5. Rounding to integers costs ~13%, which `ClockEngine.reverseTrimBend`
    /// removes with pitch bend. See notes/RESEARCH.md.
    ///
    /// `direction` is -1 (reverse), 0 (release/stop) or +1 (forward).
    case directionalTransport(ch: Int, cc: Int, center: Int, deadZone: Int, unitSpeed: Int, direction: Int)
    /// Send only when the app's play state matches `whenPlaying`. Used for the TX-6's single
    /// start/stop toggle (CC 46), which has no separate play and stop messages.
    case toggleCC(ch: Int, cc: Int, value: Int, whenPlaying: Bool)
}

struct TransportMap: Hashable {
    var play: [TransportOp]
    var stop: [TransportOp]
    var prev: [TransportOp]
    var next: [TransportOp]
    var prevSymbol = "arrow.left"
    var nextSymbol = "arrow.right"
}

// MARK: - Capabilities

struct DeviceCapabilities: Hashable {
    var hasPan = true
    /// Hardware emits MIDI clock, so the app may slave to it. false → the app is always master.
    var canBeClockMaster = true
    /// Hardware acts on incoming 0xF8. Verified true on the TX-6 (needs `clock SRC = usb` on
    /// the device); unverified on the TP-7. See notes/RESEARCH.md.
    var followsClock = true
    var hasTempoParam = true
    /// Label on the tempo-source toggle when the device, not the app, is the clock.
    var clockLabel = "op1"

    /// Pressing play while already playing reverses the tape instead of re-sending play —
    /// the TP-7's own play button behaves this way.
    var playReversesWhenPlaying = false

    /// Whether what the device *transmits* uses the same CC map it *receives* on.
    ///
    /// The OP-1 echoes its mixer on the same CCs it accepts (move its volume, get CC 7 back),
    /// so the app can mirror the hardware in its UI. The TX-6 does not: in controller mode it
    /// sends a separate map on channel 1 where CC 7 is "upper knob 1", which the receive map
    /// reads as "track 1 volume". Verified on hardware — see notes/RESEARCH.md.
    ///
    /// false → incoming CC is ignored for UI mirroring rather than being misread.
    var mirrorsIncomingCC = true
}

// MARK: - Profile

struct DeviceProfile: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Lowercase substrings matched against a MIDI endpoint's display name.
    let nameTokens: [String]
    let trackCount: Int
    /// 0-based MIDI channel used when a `.trackRelative` parameter is addressed to track 0.
    let masterChannel: Int
    /// Flat and ordered — drives the picker list and the cycle button's order.
    let params: [ParamSpec]
    let defaultParamId: String
    /// Starting volume in display units.
    let defaultVolume: Double
    let transport: TransportMap
    let caps: DeviceCapabilities
    /// Settings the user must change **on the device** before the app can drive it. Surfaced in
    /// help, because a device in its default state can look like a broken app.
    let setupSteps: [String]

    private let byId: [String: ParamSpec]
    /// Reverse map for incoming CC, keyed `channel << 8 | cc`. Built from the same `params`
    /// array as the outbound path so the two directions can never drift apart.
    private let inbound: [Int: InboundTarget]

    struct InboundTarget: Hashable {
        let spec: ParamSpec
        let track: Int
    }

    init(id: String,
         displayName: String,
         nameTokens: [String],
         trackCount: Int,
         masterChannel: Int,
         params: [ParamSpec],
         defaultParamId: String,
         defaultVolume: Double,
         transport: TransportMap,
         caps: DeviceCapabilities = DeviceCapabilities(),
         setupSteps: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.nameTokens = nameTokens
        self.trackCount = trackCount
        self.masterChannel = masterChannel
        self.params = params
        self.defaultParamId = defaultParamId
        self.defaultVolume = defaultVolume
        self.transport = transport
        self.caps = caps
        self.setupSteps = setupSteps

        self.byId = Dictionary(params.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var table: [Int: InboundTarget] = [:]
        for spec in params {
            for track in 0...trackCount where spec.isAvailable(onTrack: track) {
                guard case .cc(let cc, let rule, _)? = (track == 0 ? spec.master : spec.track)
                else { continue }
                let ch = Self.channel(rule, track: track, masterChannel: masterChannel)
                let key = ch << 8 | cc
                // First writer wins, so profile order decides ties deterministically.
                if table[key] == nil { table[key] = InboundTarget(spec: spec, track: track) }
            }
        }
        self.inbound = table

        #if DEBUG
        assert(byId.count == params.count,
               "\(id): duplicate ParamSpec ids — \(params.map(\.id))")
        #endif
    }

    var trackIndices: [Int] { trackCount >= 1 ? Array(1...trackCount) : [] }

    /// Parameters offered in the LFO picker.
    var pickerParams: [ParamSpec] { params.filter(\.lfoTargetable) }

    func param(_ id: String) -> ParamSpec? { byId[id] }

    func param(role: ParamRole) -> ParamSpec? { params.first { $0.role == role } }

    func binding(_ spec: ParamSpec, track: Int) -> ParamBinding? {
        track == 0 ? spec.master : spec.track
    }

    func channel(_ rule: ChannelRule, track: Int) -> Int {
        Self.channel(rule, track: track, masterChannel: masterChannel)
    }

    private static func channel(_ rule: ChannelRule, track: Int, masterChannel: Int) -> Int {
        switch rule {
        case .pinned(let ch):
            return ch
        case .trackRelative(let offset):
            // Master has no track number of its own — it borrows the profile's master channel.
            return track == 0 ? masterChannel : (track - 1) + offset
        }
    }

    func inboundTarget(channel: Int, cc: Int) -> InboundTarget? {
        inbound[channel << 8 | cc]
    }

    /// Clamp an LFO's raw output into the range this parameter can actually take.
    func clamp(_ spec: ParamSpec, track: Int, raw: Double) -> Double {
        if spec.role == .tempo { return Swift.max(20, Swift.min(300, raw)) }
        return Swift.max(0, Swift.min(127, raw.rounded()))
    }

    func matches(endpointName: String) -> Bool {
        let n = endpointName.lowercased()
        return nameTokens.contains { n.contains($0) }
    }
}

// MARK: - Registry

enum DeviceRegistry {
    /// Order is the tie-break when an endpoint name somehow matches more than one profile
    /// (e.g. a hub exposing several TE devices at once).
    static let all: [DeviceProfile] = [.op1Field, .tx6, .tp7]

    static func profile(forEndpointName name: String) -> DeviceProfile? {
        all.first { $0.matches(endpointName: name) }
    }

    static func profile(id: String) -> DeviceProfile {
        all.first { $0.id == id } ?? .op1Field
    }
}
