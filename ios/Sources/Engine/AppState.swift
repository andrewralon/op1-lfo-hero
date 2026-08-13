import Combine
import Foundation
import SwiftUI
import UIKit

struct EditorSnapshot {
    let param:    ParamSpec
    let wave:     LfoWave
    let rate:     Int
    let center:   Double
    let depth:    Double
    let trackOn:  [Int: Int]
    let masterOn: Int
}

@MainActor
final class AppState: ObservableObject {

    // MARK: - Engine objects
    let router      = MidiRouter()
    var ble: BLEMidi { router.ble }   // convenience for DevicePickerView
    var usb: USBMidi { router.usb }   // convenience for DevicePickerView
    let clock       = ClockEngine()
    let automation  = AutomationEngine()
    let controller: Controller

    // MARK: - Device
    /// The device the app is currently driving. Every CC number, channel and track count comes
    /// from here — see DeviceProfile.swift.
    @Published private(set) var profile: DeviceProfile = .op1Field

    // MARK: - Connection
    @Published var connectionLabel = "scanning…"
    @Published var isConnected = false

    // MARK: - Transport
    @Published var bpm: Double = 100.0
    @Published var isClockMaster = false
    @Published var slaveTicksReceived: Int = 0  // diagnostic: counts ticks from OP-1

    // MARK: - Track state  (volume: 0-99 display, pan: -63..+63)
    @Published var volumes: [Int: Double] = [1: 90, 2: 90, 3: 90, 4: 90]
    @Published var pans:    [Int: Int]    = [1: 0,  2: 0,  3: 0,  4: 0]
    @Published var mutes:   [Int: Bool]   = [1: false, 2: false, 3: false, 4: false]

    // MARK: - LFO editor
    @Published var lfoWave  = LfoWave.sine
    @Published var lfoParam: ParamSpec = DeviceProfile.op1Field.params[0] {
        didSet {
            if lfoParam.isMasterOnly {
                // Master-only param (tempo, etc) — master must be on; don't clobber an
                // existing normal/inverted choice, only kick it on if it was off.
                if masterOn == 0 { masterOn = 1 }
            } else if !lfoParam.isMasterCapable {
                // Track-only param (volume/pan/mute) — master can't apply here, so clear
                // any stale on/inverted state left over from a master-capable param. This
                // also re-enables the track buttons, since they're disabled by masterOn > 0.
                masterOn = 0
            }
        }
    }
    @Published var lfoRate   = 3           // 1-8
    @Published var lfoDepth  = 10.0        // display units (0-99)
    @Published var lfoCenter = 90.0        // display units (0-99)
    @Published var trackOn   = [1: 1, 2: 0, 3: 0, 4: 0]  // 0=off 1=on 2=inv
    @Published var masterOn  = 0                            // 0=off 1=on 2=inv
    @Published var activeLfos: [LfoClip] = []
    @Published var isPreview  = false

    // Displayed lfo range (derived)
    var lfoRange: String {
        let lo = max(0, lfoCenter - lfoDepth)
        let hi = min(99, lfoCenter + lfoDepth)
        return "\(Int(lo))-\(Int(hi))"
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Persisted settings

    /// Everything that is remembered about one device. Each profile gets its own bucket:
    /// an LFO chip's depth/center are in that device's MIDI units and its parameter namespace,
    /// so they are not translatable between devices — and wiping them on every unplug/replug
    /// would cost a session's work.
    ///
    /// Every field decodes with `decodeIfPresent ?? default`. This is deliberate and load-bearing:
    /// Swift's synthesized `Decodable` ignores property defaults, so a synthesized decoder makes
    /// any future added field throw and silently reset the user's entire saved state.
    // internal (not private) so migration can be unit-tested
    struct DeviceState: Codable {
        var lfoWave: LfoWave = .sine
        var lfoParamId: String = "volume"
        var lfoRate: Int = 3
        var lfoDepth: Double = 10.0
        var lfoCenter: Double = 90.0
        var trackOn: [Int: Int] = [1: 1]
        var masterOn: Int = 0
        var isClockMaster: Bool = true
        var bpm: Double = 100.0
        var volumes: [Int: Double] = [:]
        var pans: [Int: Int] = [:]
        var mutes: [Int: Bool] = [:]
        var activeLfos: [LfoClip] = []

        init() {}

        enum CodingKeys: String, CodingKey {
            case lfoWave, lfoParamId, lfoParam, lfoRate, lfoDepth, lfoCenter
            case trackOn, masterOn, isClockMaster, bpm, volumes, pans, mutes, activeLfos
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
                ((try? c.decodeIfPresent(T.self, forKey: k)).flatMap { $0 }) ?? fallback
            }
            lfoWave   = v(.lfoWave, LfoWave.sine)
            // `lfoParam` is the pre-multi-device key (a raw Parameter string).
            lfoParamId = ((try? c.decodeIfPresent(String.self, forKey: .lfoParamId)).flatMap { $0 })
                      ?? ((try? c.decodeIfPresent(String.self, forKey: .lfoParam)).flatMap { $0 })
                      ?? "volume"
            lfoRate   = v(.lfoRate, 3)
            lfoDepth  = v(.lfoDepth, 10.0)
            lfoCenter = v(.lfoCenter, 90.0)
            trackOn   = v(.trackOn, [1: 1])
            masterOn  = v(.masterOn, 0)
            isClockMaster = v(.isClockMaster, true)
            // A tempo saved from a bad clock reading must not survive a relaunch. 0 is the
            // "slaved, no data yet" sentinel and is allowed through.
            let savedBpm = v(.bpm, 100.0)
            bpm = (savedBpm == 0 || (savedBpm >= AppState.minBpm && savedBpm <= AppState.maxBpm))
                ? savedBpm : 100.0
            volumes   = v(.volumes, [:])
            pans      = v(.pans, [:])
            mutes     = v(.mutes, [:])
            activeLfos = v(.activeLfos, [])
        }

        /// Hand-written because `CodingKeys` carries the legacy `lfoParam` key, which has no
        /// property to synthesize from. Only the current keys are written.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(lfoWave, forKey: .lfoWave)
            try c.encode(lfoParamId, forKey: .lfoParamId)
            try c.encode(lfoRate, forKey: .lfoRate)
            try c.encode(lfoDepth, forKey: .lfoDepth)
            try c.encode(lfoCenter, forKey: .lfoCenter)
            try c.encode(trackOn, forKey: .trackOn)
            try c.encode(masterOn, forKey: .masterOn)
            try c.encode(isClockMaster, forKey: .isClockMaster)
            try c.encode(bpm, forKey: .bpm)
            try c.encode(volumes, forKey: .volumes)
            try c.encode(pans, forKey: .pans)
            try c.encode(mutes, forKey: .mutes)
            try c.encode(activeLfos, forKey: .activeLfos)
        }
    }

    struct Settings: Codable {
        var version: Int = 1
        var deviceId: String = "op1"
        var perDevice: [String: DeviceState] = [:]

        init() {}

        enum CodingKeys: String, CodingKey { case version, deviceId, perDevice }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            version  = ((try? c.decodeIfPresent(Int.self, forKey: .version)).flatMap { $0 }) ?? 0
            deviceId = ((try? c.decodeIfPresent(String.self, forKey: .deviceId)).flatMap { $0 }) ?? "op1"
            perDevice = ((try? c.decodeIfPresent([String: DeviceState].self, forKey: .perDevice))
                            .flatMap { $0 }) ?? [:]
            if version == 0 {
                // v0 had no envelope: the whole blob *was* one device's state, always the OP-1.
                // `DeviceState`'s decoder reads the old key names directly, so re-decoding the
                // same container is the entire migration.
                perDevice["op1"] = (try? DeviceState(from: d)) ?? DeviceState()
                version = 1
            }
        }
    }

    private let settingsKey = "AppSettings"

    /// Old `Parameter` raw value → new `ParamSpec.id`. Empty on purpose: the OP-1 profile's ids
    /// *are* the old raw values. Kept as the documented hook if an id ever has to change.
    private static let legacyParamIdMap: [String: String] = [:]

    private func loadSettings() {
        if CommandLine.arguments.contains("--uitest-reset") {
            UserDefaults.standard.removeObject(forKey: settingsKey)
            UserDefaults.standard.removeObject(forKey: Self.profileOverrideKey)
            UserDefaults.standard.removeObject(forKey: "deviceOverrideLabel")
        }
        // --uitest-profile <id> pins the device so tests can exercise a 6-track layout
        // without the hardware attached.
        if let i = CommandLine.arguments.firstIndex(of: "--uitest-profile"),
           i + 1 < CommandLine.arguments.count {
            let id = CommandLine.arguments[i + 1]
            UserDefaults.standard.set(id, forKey: Self.profileOverrideKey)
            // Keep the settings picker's label store in step, or it would read "auto".
            UserDefaults.standard.set(DeviceRegistry.profile(id: id).displayName,
                                      forKey: "deviceOverrideLabel")
        }
        var s = Settings()
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
        }
        // Re-read the override here: a launch argument may have just written it, after the
        // published property took its initial value.
        let override = UserDefaults.standard.string(forKey: Self.profileOverrideKey) ?? "auto"
        let effectiveId = override == "auto" ? s.deviceId : override

        applyDeviceState(s.perDevice[effectiveId] ?? DeviceState(),
                         for: DeviceRegistry.profile(id: effectiveId))

        if profileOverrideId != override { profileOverrideId = override }
    }

    /// Push one saved bucket into the published state, dropping anything the profile can't
    /// express (a parameter it doesn't have, a track it doesn't have).
    private func applyDeviceState(_ st: DeviceState, for newProfile: DeviceProfile) {
        profile = newProfile
        controller.setProfile(newProfile)
        automation.setProfile(newProfile)
        clock.transport = newProfile.transport
        clock.playTogglesDirection = newProfile.caps.playReversesWhenPlaying

        let tracks = newProfile.trackIndices
        volumes = Dictionary(uniqueKeysWithValues: tracks.map { ($0, st.volumes[$0] ?? newProfile.defaultVolume) })
        pans    = Dictionary(uniqueKeysWithValues: tracks.map { ($0, st.pans[$0] ?? 0) })
        mutes   = Dictionary(uniqueKeysWithValues: tracks.map { ($0, st.mutes[$0] ?? false) })

        lfoWave   = st.lfoWave
        lfoRate   = st.lfoRate
        lfoDepth  = st.lfoDepth
        lfoCenter = st.lfoCenter
        masterOn  = st.masterOn
        bpm       = st.bpm

        // Keep only tracks this device has; never end up with nothing selected, or
        // "lowest non-zero track" in lfoStart/saveChipEdits would target a missing track.
        var on = st.trackOn.filter { tracks.contains($0.key) }
        if !on.values.contains(where: { $0 != 0 }) { on[1] = 1 }
        trackOn = Dictionary(uniqueKeysWithValues: tracks.map { ($0, on[$0] ?? 0) })

        let savedId = Self.legacyParamIdMap[st.lfoParamId] ?? st.lfoParamId
        lfoParam = newProfile.param(savedId)
                ?? newProfile.param(newProfile.defaultParamId)
                ?? newProfile.params[0]   // set last — didSet may adjust masterOn

        if st.isClockMaster || !newProfile.caps.canBeClockMaster { enableClock() } else { disableClock() }

        for lfo in st.activeLfos where lfo.loop {
            guard lfo.deviceId == newProfile.id,
                  newProfile.param(lfo.paramId) != nil,
                  lfo.track == 0 || tracks.contains(lfo.track) else {
                #if DEBUG
                print("dropping unresolvable clip: device=\(lfo.deviceId) param=\(lfo.paramId) track=\(lfo.track)")
                #endif
                continue
            }
            automation.add(lfo)
            if !lfo.isEnabled { automation.setEnabled(lfo.id, enabled: false) }
            activeLfos.append(lfo)
        }
    }

    private func currentDeviceState() -> DeviceState {
        var st = DeviceState()
        st.lfoWave    = lfoWave
        st.lfoParamId = lfoParam.id
        st.lfoRate    = lfoRate
        st.lfoDepth   = lfoDepth
        st.lfoCenter  = lfoCenter
        st.trackOn    = trackOn
        st.masterOn   = masterOn
        st.isClockMaster = isClockMaster
        st.bpm        = bpm
        st.volumes    = volumes
        st.pans       = pans
        st.mutes      = mutes
        st.activeLfos = activeLfos.filter { $0.loop }
        return st
    }

    private func saveSettings() {
        var s = Settings()
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded   // preserve other devices' buckets
        }
        s.version  = 1
        s.deviceId = profile.id
        s.perDevice[profile.id] = currentDeviceState()
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Device switching

    /// "auto" (detect from the MIDI port name) or a specific profile id. Persisted separately
    /// from per-device state because it is a global preference.
    ///
    /// Deliberately a plain `@Published` backed by UserDefaults rather than `@AppStorage`:
    /// `@AppStorage` is a `DynamicProperty` meant for views and does not drive
    /// `objectWillChange` from inside an `ObservableObject`.
    static let profileOverrideKey = "deviceProfileOverride"

    /// Mirrors the stored override for display. SettingsView writes UserDefaults directly
    /// (via @AppStorage) and then calls `resolveProfile()`, so this is a read-side mirror
    /// rather than the source of truth.
    @Published private(set) var profileOverrideId: String = UserDefaults.standard
        .string(forKey: AppState.profileOverrideKey) ?? "auto"

    /// True when the profile in use was assumed rather than matched — something is connected
    /// but its name matched no known device. Surfaced in the status bar.
    @Published private(set) var profileIsAssumed = false

    /// Pick the profile: an explicit override wins; otherwise the connected endpoint's name;
    /// otherwise keep whatever is already loaded (never silently reset the user's device).
    func resolveProfile() {
        let stored = UserDefaults.standard.string(forKey: Self.profileOverrideKey) ?? "auto"
        if profileOverrideId != stored { profileOverrideId = stored }

        if stored != "auto" {
            profileIsAssumed = false
            switchProfile(to: DeviceRegistry.profile(id: stored))
            return
        }
        if let id = usb.matchedProfileId ?? ble.matchedProfileId {
            profileIsAssumed = false
            switchProfile(to: DeviceRegistry.profile(id: id))
        } else {
            // Connected to something unrecognised — keep the last profile, but say so.
            profileIsAssumed = isConnected
        }
    }

    /// Swap the active device, banking the current one's state first so switching back and
    /// forth is lossless.
    func switchProfile(to newProfile: DeviceProfile) {
        guard newProfile.id != profile.id else { return }

        // Stop everything that is mid-flight before the parameter namespace changes.
        automation.clearAll()
        automation.clearPreview()
        isPreview = false
        activeLfos.removeAll()

        var s = Settings()
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
        }
        s.perDevice[profile.id] = currentDeviceState()   // bank the outgoing device
        s.version  = 1
        s.deviceId = newProfile.id
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }

        applyDeviceState(s.perDevice[newProfile.id] ?? DeviceState(), for: newProfile)
    }

    private func wireAutoSave() {
        Publishers.MergeMany(
            $lfoWave.map { _ in () }.eraseToAnyPublisher(),
            $lfoParam.map { _ in () }.eraseToAnyPublisher(),
            $lfoRate.map { _ in () }.eraseToAnyPublisher(),
            $lfoDepth.map { _ in () }.eraseToAnyPublisher(),
            $lfoCenter.map { _ in () }.eraseToAnyPublisher(),
            $trackOn.map { _ in () }.eraseToAnyPublisher(),
            $masterOn.map { _ in () }.eraseToAnyPublisher(),
            $isClockMaster.map { _ in () }.eraseToAnyPublisher(),
            $bpm.map { _ in () }.eraseToAnyPublisher(),
            $activeLfos.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
        .sink { [weak self] in self?.saveSettings() }
        .store(in: &cancellables)
    }

    init() {
        controller = Controller(router: router)
        automation.controller = controller
        // `.transport` parameters need ClockEngine, which owns play state and song position.
        controller.transportRunner = { [weak clock] ops in clock?.runOps(ops) }
        clock.router = router

        wireCallbacks()
        wireAutoSave()
        loadSettings()  // restores settings and calls enableClock/disableClock
    }

    private func wireCallbacks() {
        // USB + BLE state → connection label (USB preferred when connected)
        Publishers.CombineLatest(router.ble.$state, router.usb.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bleState, usbState in
                guard let self else { return }
                if usbState.isConnected {
                    self.connectionLabel = usbState.label
                    self.isConnected = true
                } else if case .found = usbState {
                    // USB MIDI devices visible but no known device name matched — show what was found
                    self.connectionLabel = usbState.label
                    self.isConnected = false
                } else {
                    self.connectionLabel = bleState.label
                    self.isConnected = bleState.isConnected
                }
                // Whatever just connected may be a different device than last time.
                self.resolveProfile()
            }
            .store(in: &cancellables)

        // Suspend master clock timer when backgrounded with no device connected —
        // a connected OP-1 still needs the clock for LFO sync even without tape playing.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isClockMaster, !self.isConnected else { return }
                self.clock.suspendMasterTimer()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clock.resumeMasterTimerIfSuspended()
            }
            .store(in: &cancellables)

        // BPM from clock engine
        clock.bpmCallback = { [weak self] newBpm in
            // A measured tempo, so it can be nonsense if the incoming stream is. Ignore rather
            // than clamp: a reading outside musical range is a transport artefact, and pinning
            // it to 300 would show a plausible-looking number that was never real.
            guard newBpm >= Self.minBpm, newBpm <= Self.maxBpm else { return }
            DispatchQueue.main.async { self?.bpm = newBpm }
        }

        // Clock tick → automation engine + slave tick counter
        clock.tickCallback = { [weak self] tick in
            guard let self else { return }
            if !self.clock.isClockMaster {
                // Only update during initial sync (< 9 ticks). After that the BPM display
                // takes over and steady-state 40 Hz main-thread dispatches serve no purpose.
                if self.slaveTicksReceived < 9 {
                    DispatchQueue.main.async { self.slaveTicksReceived += 1 }
                }
            }
            self.automation.onTick(tick)
        }

        // Automation update → fader/knob tracking on UI
        automation.updateCallback = { [weak self] track, param, midiVal in
            guard let self else { return }
            DispatchQueue.main.async {
                switch param.role {
                case .volume:
                    self.volumes[track] = midiToUI(midiVal)
                case .pan:
                    self.pans[track] = Int(midiVal) - 64
                case .mute:
                    self.mutes[track] = param.isOn(Int(midiVal))
                case .tempo:
                    self.clock.updateMasterBpm(midiVal)
                    self.bpm = midiVal
                case .generic:
                    break   // not mirrored in the mixer UI
                }
            }
        }

        // One-shot LFO completed
        automation.finishedCallback = { [weak self] lfo in
            DispatchQueue.main.async {
                guard let self else { return }
                let action = UserDefaults.standard.string(forKey: "oneShotFinishAction") ?? "previous"
                switch action {
                case "center": self.automation.sendRestore(lfo: lfo, value: lfo.centerValue)
                case "hold":   break
                default:       self.automation.sendRestore(lfo: lfo, value: lfo.originalValue)
                }
                let cleanup = UserDefaults.standard.object(forKey: "cleanupOneShots") as? Bool ?? false
                if cleanup {
                    self.activeLfos.removeAll { $0.id == lfo.id }
                } else {
                    if let idx = self.activeLfos.firstIndex(where: { $0.id == lfo.id }) {
                        self.activeLfos[idx].isEnabled = false
                    }
                }
            }
        }

        // CC from the device → sync UI faders/knobs (router forwards from whichever transport
        // is active). The channel/CC pair is resolved through the same parameter table the
        // outbound path uses, so the two directions cannot drift apart.
        router.onCC = { [weak self] channel, cc, value in
            DispatchQueue.main.async {
                guard let self,
                      // Devices whose transmit map differs from their receive map would be
                      // misread here — the TX-6's "upper knob 1" is CC 7, which the receive
                      // map calls "track 1 volume".
                      self.profile.caps.mirrorsIncomingCC,
                      let hit = self.profile.inboundTarget(channel: channel, cc: cc)
                else { return }
                let track = hit.track
                switch hit.spec.role {
                case .volume:
                    let v = midiToUI(Double(value))
                    if self.volumes[track] != v { self.volumes[track] = v }
                case .mute:
                    let m = hit.spec.isOn(value)
                    if self.mutes[track] != m { self.mutes[track] = m }
                case .pan:
                    let p = value - 64
                    if self.pans[track] != p { self.pans[track] = p }
                case .tempo, .generic:
                    break   // not mirrored in the mixer UI
                }
            }
        }
    }

    // MARK: - Transport actions

    func play() {
        clock.play()
    }

    func stop() {
        clock.stop()
    }

    func tapePrev() { clock.tapePrev() }
    func tapeNext() { clock.tapeNext() }

    /// Press-and-hold scrubbing. On devices whose seek is a persistent speed state, the reel
    /// moves only while held and accelerates the longer it is held.
    func beginScrub(forward: Bool) { clock.beginScrub(forward: forward) }
    func endScrub()                { clock.endScrub() }
    var hasMomentaryScrub: Bool    { clock.hasMomentaryScrub }

    /// Musical range for any tempo the app will accept or display. 0 is kept as a separate
    /// sentinel meaning "slaved, no clock data yet", so it is deliberately outside this.
    static let minBpm = 20.0
    static let maxBpm = 300.0

    func enableClock() {
        isClockMaster = true
        // Anything outside musical range is treated as the sentinel: taking over as master with
        // a junk tempo would drive the master timer with it. A bad slave reading used to survive
        // the switch back to app-master this way.
        let startBpm = (bpm >= Self.minBpm && bpm <= Self.maxBpm) ? bpm : 100.0
        bpm = startBpm
        clock.enableClock(bpm: startBpm)
    }

    func disableClock() {
        isClockMaster = false
        slaveTicksReceived = 0
        clock.disableClock()
    }

    func setBpm(_ v: Double) {
        bpm = max(20, min(300, v))
        if isClockMaster { clock.setMasterBpm(bpm) }
    }

    // MARK: - Track actions

    func setVolume(track: Int, value: Double) {
        volumes[track] = value
        controller.setVolume(track: track, value: uiToMidi(value))
    }

    func setPan(track: Int, value: Int) {
        pans[track] = value
        controller.setPan(track: track, value: value + 64)
    }

    func toggleMute(track: Int) {
        // `mutes` is the single source of truth — Controller holds no mute state of its own.
        let now = !(mutes[track] ?? false)
        mutes[track] = now
        controller.setMute(track: track, on: now)
    }

    // MARK: - LFO actions

    // Effective tick count for waveform display (converts free-rate periods using current BPM).
    var lfoDisplayRateTicks: Int {
        if let secs = FREE_RATE_SECONDS[lfoRate] {
            return max(1, Int(secs * max(20, bpm) * Double(PPQN) / 60.0))
        }
        return RATE_TICKS[lfoRate] ?? (4 * PPQN)
    }

    func lfoStart(loop: Bool) {
        let period = FREE_RATE_SECONDS[lfoRate]
        let rt: Int
        if let secs = period {
            rt = max(1, Int(secs * max(20, bpm) * Double(PPQN) / 60.0))
        } else {
            rt = RATE_TICKS[lfoRate] ?? (4 * PPQN)
        }
        let isTempo = lfoParam.role == .tempo
        let depthMidi  = isTempo ? lfoDepth  : Double(uiToMidi(lfoDepth))
        let centerMidi = isTempo ? lfoCenter : Double(uiToMidi(lfoCenter))

        if lfoParam.isMasterCapable && masterOn != 0 {
            addLfo(track: 0, rateTicks: rt, freeRatePeriod: period, depth: depthMidi, center: centerMidi,
                   inverted: masterOn == 2, loop: loop)
        } else {
            for (t, state) in trackOn.sorted(by: { $0.key < $1.key }) where state != 0 {
                addLfo(track: t, rateTicks: rt, freeRatePeriod: period, depth: depthMidi, center: centerMidi,
                       inverted: state == 2, loop: loop)
            }
        }
    }

    /// Current value of a parameter in MIDI units, captured when a clip is created so disabling
    /// the clip can put the parameter back. Only the roles the mixer tracks are knowable;
    /// anything else falls back to the clip's own center.
    private func capturedValue(of spec: ParamSpec, track: Int, fallback: Double) -> Double {
        switch spec.role {
        case .tempo:  return bpm
        case .volume: return Double(uiToMidi(volumes[track] ?? profile.defaultVolume))
        case .pan:    return Double((pans[track] ?? 0) + 64)
        case .mute:   return (mutes[track] ?? false) ? 127.0 : 0.0
        case .generic: return fallback
        }
    }

    private func addLfo(track: Int, rateTicks: Int, freeRatePeriod: Double?, depth: Double, center: Double,
                        inverted: Bool, loop: Bool) {
        // Dedup: paused/disabled chips also count — re-enable instead of adding a duplicate.
        if activeLfos.contains(where: {
            $0.track == track && $0.paramId == lfoParam.id &&
            $0.wave == lfoWave && $0.rateTicks == rateTicks && $0.freeRatePeriod == freeRatePeriod &&
            $0.depth == depth && $0.centerValue == center && $0.inverted == inverted
        }) { return }

        let lfo = LfoClip(deviceId: profile.id, track: track, paramId: lfoParam.id, wave: lfoWave,
                          rateTicks: rateTicks, freeRatePeriod: freeRatePeriod,
                          depth: depth, centerValue: center,
                          inverted: inverted, loop: loop,
                          originalValue: capturedValue(of: lfoParam, track: track, fallback: center))
        automation.add(lfo)
        activeLfos.append(lfo)
        updatePreviewIfActive()
    }

    func stopLfo(_ lfo: LfoClip) {
        automation.remove(lfo)
        activeLfos.removeAll { $0.id == lfo.id }
        updatePreviewIfActive()
    }

    func stopAllLfos() {
        automation.clearAll()
        activeLfos.removeAll()
        updatePreviewIfActive()
    }

    func toggleLfoEnabled(_ lfo: LfoClip) {
        guard let idx = activeLfos.firstIndex(where: { $0.id == lfo.id }) else { return }
        let nowEnabled = !activeLfos[idx].isEnabled
        activeLfos[idx].isEnabled = nowEnabled
        if nowEnabled {
            // Finished one-shots are removed from the engine on finish; re-add so they run again
            if !lfo.loop && !automation.snapshot().contains(where: { $0.id == lfo.id }) {
                automation.add(activeLfos[idx])
            }
            automation.setEnabled(lfo.id, enabled: true)
        } else {
            automation.setEnabled(lfo.id, enabled: false)
            let action = UserDefaults.standard.string(forKey: "chipPauseAction") ?? "previous"
            switch action {
            case "center": automation.sendRestore(lfo: activeLfos[idx], value: lfo.centerValue)
            case "hold":   break  // send nothing; op-1 holds last lfo value
            default:       automation.sendRestore(lfo: activeLfos[idx], value: lfo.originalValue)
            }
        }
        updatePreviewIfActive()
    }

    // MARK: - Preview

    func togglePreview() {
        isPreview.toggle()
        if isPreview {
            automation.setPreview(buildPreviewClips())
        } else {
            automation.clearPreview()
        }
    }

    func updatePreviewIfActive() {
        guard isPreview else { return }
        automation.setPreview(buildPreviewClips())
    }

    private func buildPreviewClips() -> [LfoClip] {
        let period = FREE_RATE_SECONDS[lfoRate]
        let rt: Int
        if let secs = period {
            rt = max(1, Int(secs * max(20, bpm) * Double(PPQN) / 60.0))
        } else {
            rt = RATE_TICKS[lfoRate] ?? (4 * PPQN)
        }
        let isTempo = lfoParam.role == .tempo
        let depthMidi  = isTempo ? lfoDepth  : Double(uiToMidi(lfoDepth))
        let centerMidi = isTempo ? lfoCenter : Double(uiToMidi(lfoCenter))
        var clips: [LfoClip] = []
        if lfoParam.isMasterCapable && masterOn != 0 {
            clips.append(LfoClip(deviceId: profile.id, track: 0, paramId: lfoParam.id, wave: lfoWave,
                                 rateTicks: rt, freeRatePeriod: period,
                                 depth: depthMidi, centerValue: centerMidi,
                                 inverted: masterOn == 2, loop: true, originalValue: centerMidi))
        } else {
            for (t, state) in trackOn.sorted(by: { $0.key < $1.key }) where state != 0 {
                clips.append(LfoClip(deviceId: profile.id, track: t, paramId: lfoParam.id, wave: lfoWave,
                                     rateTicks: rt, freeRatePeriod: period,
                                     depth: depthMidi, centerValue: centerMidi,
                                     inverted: state == 2, loop: true, originalValue: centerMidi))
            }
        }
        // Suppress preview on tracks where an identical enabled chip is already running —
        // avoids two competing LFOs sending to the same parameter simultaneously.
        return clips.filter { preview in
            !activeLfos.contains { active in
                active.isEnabled &&
                active.track       == preview.track &&
                active.paramId     == preview.paramId &&
                active.wave        == preview.wave &&
                active.rateTicks   == preview.rateTicks &&
                active.depth       == preview.depth &&
                active.centerValue == preview.centerValue &&
                active.inverted    == preview.inverted
            }
        }
    }

    // MARK: - Chip editing

    func chipEditorSnapshot() -> EditorSnapshot {
        EditorSnapshot(param: lfoParam, wave: lfoWave, rate: lfoRate,
                       center: lfoCenter, depth: lfoDepth,
                       trackOn: trackOn, masterOn: masterOn)
    }

    func loadEditor(from lfo: LfoClip) {
        trackOn = [1: 0, 2: 0, 3: 0, 4: 0]
        if lfo.track == 0 {
            masterOn = lfo.inverted ? 2 : 1
        } else {
            masterOn = 0
            trackOn[lfo.track] = lfo.inverted ? 2 : 1
        }
        lfoWave   = lfo.wave
        lfoRate   = lfo.rateIndex
        let spec = profile.param(lfo.paramId) ?? lfoParam
        if spec.role == .tempo {
            lfoDepth  = lfo.depth
            lfoCenter = lfo.centerValue
        } else {
            lfoDepth  = midiToUI(lfo.depth)
            lfoCenter = midiToUI(lfo.centerValue)
        }
        lfoParam = spec  // last — didSet may adjust masterOn
        updatePreviewIfActive()
    }

    func saveChipEdits(id: UUID) {
        guard let idx = activeLfos.firstIndex(where: { $0.id == id }) else { return }
        var lfo = activeLfos[idx]

        lfo.deviceId  = profile.id
        lfo.paramId   = lfoParam.id
        lfo.wave      = lfoWave

        if let secs = FREE_RATE_SECONDS[lfoRate] {
            lfo.freeRatePeriod = secs
            lfo.rateTicks = max(1, Int(secs * max(20, bpm) * Double(PPQN) / 60.0))
        } else {
            lfo.freeRatePeriod = nil
            lfo.rateTicks = RATE_TICKS[lfoRate] ?? (4 * PPQN)
        }

        if lfoParam.role == .tempo {
            lfo.depth       = lfoDepth
            lfo.centerValue = lfoCenter
        } else {
            lfo.depth       = Double(uiToMidi(lfoDepth))
            lfo.centerValue = Double(uiToMidi(lfoCenter))
        }

        // Track + inverted: master takes priority; otherwise lowest-indexed non-zero track.
        if masterOn > 0 {
            lfo.track    = 0
            lfo.inverted = masterOn == 2
        } else if let entry = trackOn.sorted(by: { $0.key < $1.key }).first(where: { $0.value > 0 }) {
            lfo.track    = entry.key
            lfo.inverted = entry.value == 2
        }

        activeLfos[idx] = lfo
        automation.update(lfo)
        updatePreviewIfActive()
    }

    // Creates additional chips for all active tracks/master beyond the primary one.
    // Call after the primary chip has already been saved via saveChipEdits / liveUpdateChip.
    func createAdditionalChipsOnCommit(id: UUID) {
        guard let primary = activeLfos.first(where: { $0.id == id }) else { return }

        var targets: [(track: Int, inverted: Bool)] = []
        if masterOn > 0 {
            targets.append((0, masterOn == 2))
        } else {
            for (t, state) in trackOn.sorted(by: { $0.key < $1.key }) where state != 0 {
                targets.append((t, state == 2))
            }
        }
        guard targets.count > 1 else { return }

        for target in targets.dropFirst() {
            if activeLfos.contains(where: {
                $0.track == target.track && $0.paramId == primary.paramId &&
                $0.wave == primary.wave && $0.rateTicks == primary.rateTicks &&
                $0.freeRatePeriod == primary.freeRatePeriod &&
                $0.depth == primary.depth && $0.centerValue == primary.centerValue &&
                $0.inverted == target.inverted
            }) { continue }

            let spec = profile.param(primary.paramId) ?? lfoParam
            let clip = LfoClip(deviceId: primary.deviceId, track: target.track, paramId: primary.paramId,
                               wave: primary.wave, rateTicks: primary.rateTicks,
                               freeRatePeriod: primary.freeRatePeriod,
                               depth: primary.depth, centerValue: primary.centerValue,
                               inverted: target.inverted, loop: primary.loop,
                               originalValue: capturedValue(of: spec, track: target.track,
                                                            fallback: primary.centerValue))
            automation.add(clip)
            activeLfos.append(clip)
        }
        updatePreviewIfActive()
    }

    // Removes any chips (other than `id`) that are now identical to the primary chip,
    // including paused/disabled ones. Called before createAdditionalChipsOnCommit so the
    // dedup there can compare against a clean list.
    func removeChipDuplicates(of id: UUID) {
        guard let primary = activeLfos.first(where: { $0.id == id }) else { return }
        let dupes = activeLfos.filter {
            $0.id != id &&
            $0.track       == primary.track      &&
            $0.paramId     == primary.paramId    &&
            $0.wave        == primary.wave        &&
            $0.rateTicks   == primary.rateTicks   &&
            $0.freeRatePeriod == primary.freeRatePeriod &&
            $0.depth       == primary.depth       &&
            $0.centerValue == primary.centerValue &&
            $0.inverted    == primary.inverted
        }
        guard !dupes.isEmpty else { return }
        let dupeIDs = Set(dupes.map { $0.id })
        for lfo in dupes { automation.remove(lfo) }
        activeLfos.removeAll { dupeIDs.contains($0.id) }
        updatePreviewIfActive()
    }

    func revertChipEdits(_ original: LfoClip) {
        guard let idx = activeLfos.firstIndex(where: { $0.id == original.id }) else { return }
        activeLfos[idx] = original
        automation.update(original)
        updatePreviewIfActive()
    }

    func restoreEditor(_ snap: EditorSnapshot) {
        trackOn   = snap.trackOn
        masterOn  = snap.masterOn
        lfoWave   = snap.wave
        lfoRate   = snap.rate
        lfoCenter = snap.center
        lfoDepth  = snap.depth
        lfoParam  = snap.param  // last — didSet may adjust masterOn
        updatePreviewIfActive()
    }

    // MARK: - Track button cycle (0→1→2→0)

    func cycleTrack(_ t: Int) {
        let cur = trackOn[t] ?? 0
        if lfoParam.isMasterOnly || masterOn > 0 { return }
        trackOn[t] = (cur + 1) % 3
        updatePreviewIfActive()
    }

    func cycleMaster() {
        guard lfoParam.isMasterCapable else { return }
        if lfoParam.isMasterOnly {
            // Master-only param — never allowed to land on "off", just alternate normal/inverted.
            masterOn = masterOn == 1 ? 2 : 1
        } else {
            masterOn = (masterOn + 1) % 3
        }
        updatePreviewIfActive()
    }
}
