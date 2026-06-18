import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    // MARK: - Engine objects
    let router      = MidiRouter()
    var ble: BLEMidi { router.ble }   // convenience for DevicePickerView
    let clock       = ClockEngine()
    let automation  = AutomationEngine()
    let controller: Controller

    // MARK: - Connection
    @Published var connectionLabel = "scanning…"
    @Published var isConnected = false

    // MARK: - Transport
    @Published var bpm: Double = 100.0
    @Published var isClockMaster = false
    @Published var isPlaying = false
    @Published var slaveTicksReceived: Int = 0  // diagnostic: counts ticks from OP-1

    // MARK: - Track state  (volume: 0-99 display, pan: -63..+63)
    @Published var volumes: [Int: Double] = [1: 90, 2: 90, 3: 90, 4: 90]
    @Published var pans:    [Int: Int]    = [1: 0,  2: 0,  3: 0,  4: 0]
    @Published var mutes:   [Int: Bool]   = [1: false, 2: false, 3: false, 4: false]

    // MARK: - LFO editor
    @Published var lfoWave  = LfoWave.sine
    @Published var lfoParam = Parameter.volume {
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

    // Displayed lfo range (derived)
    var lfoRange: String {
        let lo = max(0, lfoCenter - lfoDepth)
        let hi = min(99, lfoCenter + lfoDepth)
        return "\(Int(lo))-\(Int(hi))"
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Persisted settings

    private struct Settings: Codable {
        var lfoWave: LfoWave = .sine
        var lfoParam: Parameter = .volume
        var lfoRate: Int = 3
        var lfoDepth: Double = 10.0
        var lfoCenter: Double = 90.0
        var trackOn: [Int: Int] = [1: 1, 2: 0, 3: 0, 4: 0]
        var masterOn: Int = 0
        var isClockMaster: Bool = true
        var bpm: Double = 100.0
        var activeLfos: [LfoClip] = []
    }

    private let settingsKey = "AppSettings"

    private func loadSettings() {
        let s: Settings
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            s = decoded
        } else {
            s = Settings()
        }
        lfoWave   = s.lfoWave
        lfoRate   = s.lfoRate
        lfoDepth  = s.lfoDepth
        lfoCenter = s.lfoCenter
        trackOn   = s.trackOn
        masterOn  = s.masterOn
        bpm       = s.bpm
        lfoParam  = s.lfoParam  // set last — didSet may adjust masterOn
        if s.isClockMaster { enableClock() } else { disableClock() }
        for lfo in s.activeLfos where lfo.loop {
            automation.add(lfo)
            activeLfos.append(lfo)
        }
    }

    private func saveSettings() {
        let s = Settings(lfoWave: lfoWave, lfoParam: lfoParam,
                         lfoRate: lfoRate, lfoDepth: lfoDepth, lfoCenter: lfoCenter,
                         trackOn: trackOn, masterOn: masterOn,
                         isClockMaster: isClockMaster, bpm: bpm,
                         activeLfos: activeLfos.filter { $0.loop })
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
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
                    // USB MIDI devices visible but OP-1 name not matched — show what was found
                    self.connectionLabel = usbState.label
                    self.isConnected = false
                } else {
                    self.connectionLabel = bleState.label
                    self.isConnected = bleState.isConnected
                }
            }
            .store(in: &cancellables)

        // BPM from clock engine
        clock.bpmCallback = { [weak self] newBpm in
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
                switch param {
                case .volume:
                    self.volumes[track] = midiToUI(midiVal)
                case .pan:
                    self.pans[track] = Int(midiVal) - 64
                case .mute:
                    self.mutes[track] = midiVal >= 64
                case .tempo:
                    self.clock.updateMasterBpm(midiVal)
                    self.bpm = midiVal
                default:
                    break
                }
            }
        }

        // One-shot LFO completed
        automation.finishedCallback = { [weak self] lfo in
            DispatchQueue.main.async {
                self?.activeLfos.removeAll { $0.id == lfo.id }
            }
        }

        // CC from OP-1 → sync UI sliders/knobs (router forwards from whichever transport is active)
        router.onCC = { [weak self] channel, cc, value in
            let track = channel + 1
            guard (1...4).contains(track) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                switch cc {
                case 7:
                    let v = midiToUI(Double(value))
                    if self.volumes[track] != v { self.volumes[track] = v }
                case 9:
                    let m = value >= 64
                    if self.mutes[track] != m { self.mutes[track] = m }
                case 10:
                    let p = value - 64
                    if self.pans[track] != p { self.pans[track] = p }
                default: break
                }
            }
        }
    }

    // MARK: - Transport actions

    func play() {
        clock.play()
    }

    func stop() {
        isPlaying = false
        clock.stop()
    }

    func tapePrev() { clock.tapePrev() }
    func tapeNext() { clock.tapeNext() }

    func enableClock() {
        isClockMaster = true
        let startBpm = bpm > 1.0 ? bpm : 100.0  // handle sentinel (0) from OP-1 mode
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
        let now = controller.toggleMute(track: track)
        mutes[track] = now
    }

    // MARK: - LFO actions

    func lfoStart(loop: Bool) {
        let rt = RATE_TICKS[lfoRate] ?? (4 * PPQN)
        let isTempo = lfoParam == .tempo
        let depthMidi  = isTempo ? lfoDepth  : Double(uiToMidi(lfoDepth))
        let centerMidi = isTempo ? lfoCenter : Double(uiToMidi(lfoCenter))

        if lfoParam.isMasterCapable && masterOn != 0 {
            addLfo(track: 0, rateTicks: rt, depth: depthMidi, center: centerMidi,
                   inverted: masterOn == 2, loop: loop)
        } else {
            for (t, state) in trackOn.sorted(by: { $0.key < $1.key }) where state != 0 {
                addLfo(track: t, rateTicks: rt, depth: depthMidi, center: centerMidi,
                       inverted: state == 2, loop: loop)
            }
        }
    }

    private func addLfo(track: Int, rateTicks: Int, depth: Double, center: Double,
                        inverted: Bool, loop: Bool) {
        // Don't add a duplicate loop LFO — same config already running continuously.
        // One-shots (loop: false) are allowed to stack since their timing differs.
        if loop && activeLfos.contains(where: {
            $0.loop && $0.track == track && $0.parameter == lfoParam &&
            $0.wave == lfoWave && $0.rateTicks == rateTicks &&
            $0.depth == depth && $0.centerValue == center && $0.inverted == inverted
        }) { return }

        let lfo = LfoClip(track: track, parameter: lfoParam, wave: lfoWave,
                          rateTicks: rateTicks, depth: depth, centerValue: center,
                          inverted: inverted, loop: loop)
        automation.add(lfo)
        activeLfos.append(lfo)
    }

    func stopLfo(_ lfo: LfoClip) {
        automation.remove(lfo)
        activeLfos.removeAll { $0.id == lfo.id }
    }

    func stopAllLfos() {
        automation.clearAll()
        activeLfos.removeAll()
    }

    // MARK: - Track button cycle (0→1→2→0)

    func cycleTrack(_ t: Int) {
        let cur = trackOn[t] ?? 0
        if lfoParam.isMasterOnly || masterOn > 0 { return }
        trackOn[t] = (cur + 1) % 3
    }

    func cycleMaster() {
        guard lfoParam.isMasterCapable else { return }
        if lfoParam.isMasterOnly {
            // Master-only param — never allowed to land on "off", just alternate normal/inverted.
            masterOn = masterOn == 1 ? 2 : 1
        } else {
            masterOn = (masterOn + 1) % 3
        }
    }
}
