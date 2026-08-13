import Foundation

/// Turns parameter changes into MIDI bytes using the active `DeviceProfile`.
///
/// There are no CC numbers in this file — they all live in the profile tables, so supporting a
/// new device is a data change rather than a new branch here. Mute state is deliberately *not*
/// tracked: `AppState.mutes` is the single source of truth (a second copy here used to drift
/// out of sync with incoming CC and with mute LFOs).
final class Controller {
    weak var router: (any MidiDestination)?

    private var _profile: DeviceProfile = .op1Field
    private let lock = NSLock()

    init(router: any MidiDestination) {
        self.router = router
    }

    var profile: DeviceProfile {
        lock.lock(); defer { lock.unlock() }
        return _profile
    }

    func setProfile(_ p: DeviceProfile) {
        lock.lock(); _profile = p; lock.unlock()
    }

    // MARK: - Generic send

    /// Send one parameter to one target. `track` 0 is master. `value` is in MIDI units (0-127),
    /// or BPM for a tempo parameter. Pass `profile` explicitly from the automation thread so a
    /// concurrent profile switch cannot split a clip's parameter from its device.
    /// Fires transport ops for a `.transport` binding. Set by AppState so the Controller does
    /// not need to know about ClockEngine's play state or song position.
    var transportRunner: (([TransportOp]) -> Void)?

    /// Last on/off state sent per parameter id, so `.transport` bindings only fire on a change.
    /// Without this an LFO would re-trigger play or record on every clock tick.
    private var lastSwitchState: [String: Bool] = [:]

    func send(spec: ParamSpec, track: Int, value: Double, profile p: DeviceProfile? = nil) {
        let prof = p ?? profile
        guard let binding = prof.binding(spec, track: track) else { return }
        switch binding {
        case .transport(let onOps, let offOps, let threshold):
            let on = Int(value.rounded()) >= threshold
            lock.lock()
            let changed = lastSwitchState[spec.id] != on
            lastSwitchState[spec.id] = on
            lock.unlock()
            // Edge-triggered: a sustained value must not re-fire transport every tick.
            guard changed else { return }
            transportRunner?(on ? onOps : offOps)
        case .virtualTempo:
            // No MIDI — the app's own clock is the target. AppState reacts via updateCallback.
            return
        case .pitchBend(let rule):
            // Parameters are always in MIDI units (0-127); pitch bend is 14-bit (0-16383).
            // Map across the full range so an LFO sweeping 0-127 sweeps the whole bend range,
            // with 64 landing near centre (8192 = no change).
            let ch = prof.channel(rule, track: track)
            let clamped = max(0, min(127, value))
            let v = Int((clamped * 16383.0 / 127.0).rounded())
            router?.send([UInt8(0xE0 | (ch & 0x0F)), UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F)])
        case .cc(let cc, let rule, let encoding):
            sendCC(ch: prof.channel(rule, track: track), cc: cc, val: encoding.wireValue(from: value))
        }
    }

    /// Send whichever parameter fills a semantic role on the active device. Used by the mixer
    /// strip, which knows "volume" but not which CC that is on the attached hardware.
    func send(role: ParamRole, track: Int, value: Double) {
        let prof = profile
        guard let spec = prof.param(role: role) else { return }
        send(spec: spec, track: track, value: value, profile: prof)
    }

    // MARK: - Mixer conveniences

    func setVolume(track: Int, value: Int) { send(role: .volume, track: track, value: Double(value)) }
    func setPan(track: Int, value: Int)    { send(role: .pan,    track: track, value: Double(value)) }
    /// The profile's switch encoding decides the actual bytes, so devices that mute with
    /// CC 9 = 127/0 and devices that mute with CC 120 = 0-63/64-127 both work unchanged.
    func setMute(track: Int, on: Bool)     { send(role: .mute,   track: track, value: on ? 127 : 0) }

    // MARK: - Raw
    // Transport lives in ClockEngine, which already owns the play state, song position and
    // start/continue flag that transport ops depend on.

    /// OP-1 octave shift. Not surfaced in the UI today; kept as a raw helper.
    func octaveUp()   { router?.send([0xB0, 79, 127]) }
    func octaveDown() { router?.send([0xB0, 79, 0])   }

    private func sendCC(ch: Int, cc: Int, val: Int) {
        let v = max(0, min(127, val))
        router?.send([UInt8(0xB0 | (ch & 0x0F)), UInt8(cc), UInt8(v)])
    }
}
