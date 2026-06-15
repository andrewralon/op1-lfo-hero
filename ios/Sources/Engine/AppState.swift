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

    // MARK: - Track state  (volume: 0-99 display, pan: -63..+63)
    @Published var volumes: [Int: Double] = [1: 90, 2: 90, 3: 90, 4: 90]
    @Published var pans:    [Int: Int]    = [1: 0,  2: 0,  3: 0,  4: 0]
    @Published var mutes:   [Int: Bool]   = [1: false, 2: false, 3: false, 4: false]

    // MARK: - LFO editor
    @Published var lfoWave  = LfoWave.sine
    @Published var lfoParam = Parameter.volume {
        didSet {
            if lfoParam == .tempo {
                masterOn = 1
            } else if oldValue == .tempo {
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

    init() {
        controller = Controller(router: router)
        automation.controller = controller
        clock.router = router

        wireCallbacks()

        // Start in master clock mode so transport buttons work out of the box
        enableClock()
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

        // Clock tick → automation engine
        clock.tickCallback = { [weak self] tick in
            self?.automation.onTick(tick)
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
        clock.enableClock(bpm: bpm)
    }

    func disableClock() {
        isClockMaster = false
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
        if !lfoParam.isMasterCapable { return }
        masterOn = (masterOn + 1) % 3
    }
}
