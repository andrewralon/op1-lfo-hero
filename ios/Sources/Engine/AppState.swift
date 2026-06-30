import Combine
import Foundation
import SwiftUI
import UIKit

struct EditorSnapshot {
    let param:    Parameter
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
    @Published var isPreview  = false

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
        if CommandLine.arguments.contains("--uitest-reset") {
            UserDefaults.standard.removeObject(forKey: settingsKey)
        }
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
            if !lfo.isEnabled { automation.setEnabled(lfo.id, enabled: false) }
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
        let isTempo = lfoParam == .tempo
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

    private func addLfo(track: Int, rateTicks: Int, freeRatePeriod: Double?, depth: Double, center: Double,
                        inverted: Bool, loop: Bool) {
        // Dedup: paused/disabled chips also count — re-enable instead of adding a duplicate.
        if activeLfos.contains(where: {
            $0.track == track && $0.parameter == lfoParam &&
            $0.wave == lfoWave && $0.rateTicks == rateTicks && $0.freeRatePeriod == freeRatePeriod &&
            $0.depth == depth && $0.centerValue == center && $0.inverted == inverted
        }) { return }

        // Capture current parameter value (MIDI units) so disabling can restore it.
        let originalValue: Double
        if lfoParam == .tempo {
            originalValue = bpm
        } else {
            switch lfoParam {
            case .volume: originalValue = Double(uiToMidi(volumes[track] ?? 90))
            case .pan:    originalValue = Double((pans[track] ?? 0) + 64)
            case .mute:   originalValue = (mutes[track] ?? false) ? 127.0 : 0.0
            default:      originalValue = center  // not tracked externally; center is best fallback
            }
        }

        let lfo = LfoClip(track: track, parameter: lfoParam, wave: lfoWave,
                          rateTicks: rateTicks, freeRatePeriod: freeRatePeriod,
                          depth: depth, centerValue: center,
                          inverted: inverted, loop: loop, originalValue: originalValue)
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
        let isTempo = lfoParam == .tempo
        let depthMidi  = isTempo ? lfoDepth  : Double(uiToMidi(lfoDepth))
        let centerMidi = isTempo ? lfoCenter : Double(uiToMidi(lfoCenter))
        var clips: [LfoClip] = []
        if lfoParam.isMasterCapable && masterOn != 0 {
            clips.append(LfoClip(track: 0, parameter: lfoParam, wave: lfoWave,
                                 rateTicks: rt, freeRatePeriod: period,
                                 depth: depthMidi, centerValue: centerMidi,
                                 inverted: masterOn == 2, loop: true, originalValue: centerMidi))
        } else {
            for (t, state) in trackOn.sorted(by: { $0.key < $1.key }) where state != 0 {
                clips.append(LfoClip(track: t, parameter: lfoParam, wave: lfoWave,
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
                active.parameter   == preview.parameter &&
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
        if lfo.parameter == .tempo {
            lfoDepth  = lfo.depth
            lfoCenter = lfo.centerValue
        } else {
            lfoDepth  = midiToUI(lfo.depth)
            lfoCenter = midiToUI(lfo.centerValue)
        }
        lfoParam = lfo.parameter  // last — didSet may adjust masterOn
        updatePreviewIfActive()
    }

    func saveChipEdits(id: UUID) {
        guard let idx = activeLfos.firstIndex(where: { $0.id == id }) else { return }
        var lfo = activeLfos[idx]

        lfo.parameter = lfoParam
        lfo.wave      = lfoWave

        if let secs = FREE_RATE_SECONDS[lfoRate] {
            lfo.freeRatePeriod = secs
            lfo.rateTicks = max(1, Int(secs * max(20, bpm) * Double(PPQN) / 60.0))
        } else {
            lfo.freeRatePeriod = nil
            lfo.rateTicks = RATE_TICKS[lfoRate] ?? (4 * PPQN)
        }

        if lfoParam == .tempo {
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
                $0.track == target.track && $0.parameter == primary.parameter &&
                $0.wave == primary.wave && $0.rateTicks == primary.rateTicks &&
                $0.freeRatePeriod == primary.freeRatePeriod &&
                $0.depth == primary.depth && $0.centerValue == primary.centerValue &&
                $0.inverted == target.inverted
            }) { continue }

            let origVal: Double
            switch primary.parameter {
            case .volume: origVal = Double(uiToMidi(volumes[target.track] ?? 90))
            case .pan:    origVal = Double((pans[target.track] ?? 0) + 64)
            case .mute:   origVal = (mutes[target.track] ?? false) ? 127.0 : 0.0
            default:      origVal = primary.centerValue
            }
            let clip = LfoClip(track: target.track, parameter: primary.parameter,
                               wave: primary.wave, rateTicks: primary.rateTicks,
                               freeRatePeriod: primary.freeRatePeriod,
                               depth: primary.depth, centerValue: primary.centerValue,
                               inverted: target.inverted, loop: primary.loop,
                               originalValue: origVal)
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
            $0.parameter   == primary.parameter  &&
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
