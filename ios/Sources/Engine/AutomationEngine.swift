import Foundation

final class AutomationEngine {
    weak var controller: Controller?

    // Called on clock thread with (track, parameter, midiValue)
    var updateCallback:   ((Int, Parameter, Double) -> Void)?
    // Called on clock thread when a one-shot LFO completes
    var finishedCallback: ((LfoClip) -> Void)?

    private var lfos: [LfoClip] = []
    private let lock = NSLock()

    // Per-clip mutable state tracked by UUID (all accessed under lock)
    private var startTicks:   [UUID: Int]    = [:]
    private var lastSent:     [UUID: Double] = [:]
    private var randomPhase:  [UUID: Double] = [:]
    private var randomValue:  [UUID: Double] = [:]

    // Preview LFOs — run continuously, never appear in activeLfos
    private var previewLfos:      [LfoClip] = []
    private var previewStartTicks: [UUID: Int]    = [:]
    private var previewLastSent:   [UUID: Double] = [:]
    private var previewRandPhase:  [UUID: Double] = [:]
    private var previewRandValue:  [UUID: Double] = [:]

    func add(_ lfo: LfoClip) {
        lock.lock(); lfos.append(lfo); lock.unlock()
    }

    func remove(_ lfo: LfoClip) {
        lock.lock()
        lfos.removeAll { $0.id == lfo.id }
        startTicks.removeValue(forKey: lfo.id)
        lastSent.removeValue(forKey: lfo.id)
        randomPhase.removeValue(forKey: lfo.id)
        randomValue.removeValue(forKey: lfo.id)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        lfos.removeAll()
        startTicks.removeAll(); lastSent.removeAll()
        randomPhase.removeAll(); randomValue.removeAll()
        lock.unlock()
    }

    func setPreview(_ clips: [LfoClip]) {
        lock.lock()
        previewLfos = clips
        let ids = Set(clips.map { $0.id })
        previewStartTicks = previewStartTicks.filter { ids.contains($0.key) }
        previewLastSent   = previewLastSent.filter   { ids.contains($0.key) }
        previewRandPhase  = previewRandPhase.filter  { ids.contains($0.key) }
        previewRandValue  = previewRandValue.filter  { ids.contains($0.key) }
        lock.unlock()
    }

    func clearPreview() {
        lock.lock()
        previewLfos.removeAll()
        previewStartTicks.removeAll(); previewLastSent.removeAll()
        previewRandPhase.removeAll();  previewRandValue.removeAll()
        lock.unlock()
    }

    func snapshot() -> [LfoClip] {
        lock.lock(); defer { lock.unlock() }
        return lfos
    }

    // MARK: - Tick evaluation (called on clock thread)

    func onTick(_ tickCount: Int) {
        lock.lock()
        let current = lfos  // snapshot while locked
        // Record start tick for newly added clips
        for lfo in current where startTicks[lfo.id] == nil {
            startTicks[lfo.id] = tickCount
        }
        lock.unlock()

        var finished = [LfoClip]()

        for lfo in current {
            lock.lock()
            let start = startTicks[lfo.id] ?? tickCount
            lock.unlock()

            let elapsed = tickCount - start

            // One-shot: auto-remove after 8 beats (one full cycle at slowest useful rate)
            if !lfo.loop {
                let oneCycle = lfo.rateTicks
                if elapsed >= oneCycle {
                    finished.append(lfo)
                    continue
                }
            }

            let phase = Double(tickCount % (8 * PPQN)) / Double(lfo.rateTicks)
            let value = evaluate(lfo, phase: phase)

            lock.lock()
            let prev = lastSent[lfo.id]
            guard prev != value else { lock.unlock(); continue }
            lastSent[lfo.id] = value
            lock.unlock()

            dispatch(lfo: lfo, value: value)
        }

        for lfo in finished {
            remove(lfo)
            finishedCallback?(lfo)
        }

        // Preview LFOs — continuous, never finish or appear in activeLfos
        lock.lock()
        let currentPreview = previewLfos
        for lfo in currentPreview where previewStartTicks[lfo.id] == nil {
            previewStartTicks[lfo.id] = tickCount
        }
        lock.unlock()

        for lfo in currentPreview {
            lock.lock()
            let pStart = previewStartTicks[lfo.id] ?? tickCount
            lock.unlock()

            let pPhase = Double((tickCount - pStart) % (8 * PPQN)) / Double(lfo.rateTicks)
            let pValue = evaluatePreview(lfo, phase: pPhase)

            lock.lock()
            let pPrev = previewLastSent[lfo.id]
            guard pPrev != pValue else { lock.unlock(); continue }
            previewLastSent[lfo.id] = pValue
            lock.unlock()

            dispatch(lfo: lfo, value: pValue)
        }
    }

    // MARK: - Private

    private func evaluatePreview(_ lfo: LfoClip, phase: Double) -> Double {
        var y: Double
        if lfo.wave == .random {
            let p = phase.truncatingRemainder(dividingBy: 1.0)
            lock.lock()
            let prev = previewRandPhase[lfo.id] ?? -1
            if prev < 0 || p < prev {
                let step = Int(p * 8) % 8
                let h = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
                previewRandValue[lfo.id] = Double(h) / Double(UInt32.max) * 2.0 - 1.0
            }
            previewRandPhase[lfo.id] = p
            y = previewRandValue[lfo.id] ?? 0
            lock.unlock()
        } else {
            y = lfo.wave.value(at: phase)
        }
        if lfo.inverted { y = -y }
        if lfo.parameter == .tempo {
            return max(20, min(300, lfo.centerValue + y * lfo.depth))
        }
        return max(0, min(127, (lfo.centerValue + y * lfo.depth).rounded()))
    }

    private func evaluate(_ lfo: LfoClip, phase: Double) -> Double {
        var y: Double
        if lfo.wave == .random {
            let p = phase.truncatingRemainder(dividingBy: 1.0)
            lock.lock()
            let prev = randomPhase[lfo.id] ?? -1
            if prev < 0 || p < prev {
                let step = Int(p * 8) % 8
                let h = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
                randomValue[lfo.id] = Double(h) / Double(UInt32.max) * 2.0 - 1.0
            }
            randomPhase[lfo.id] = p
            y = randomValue[lfo.id] ?? 0
            lock.unlock()
        } else {
            y = lfo.wave.value(at: phase)
        }

        if lfo.inverted { y = -y }

        if lfo.parameter == .tempo {
            return max(20, min(300, lfo.centerValue + y * lfo.depth))
        }
        return max(0, min(127, (lfo.centerValue + y * lfo.depth).rounded()))
    }

    private func dispatch(lfo: LfoClip, value: Double) {
        guard let ctrl = controller else { return }
        let iv = Int(value)
        switch lfo.parameter {
        case .volume: ctrl.setVolume(track: lfo.track, value: iv)
        case .pan:    ctrl.setPan(track: lfo.track, value: iv)
        case .mute:   iv >= 64 ? ctrl.mute(track: lfo.track) : ctrl.unmute(track: lfo.track)
        case .tempo:  break  // tempo modulation handled in AppState via updateCallback
        case .fx1:    ctrl.setFx(track: lfo.track, param: 1, value: iv)
        case .fx2:    ctrl.setFx(track: lfo.track, param: 2, value: iv)
        case .fx3:    ctrl.setFx(track: lfo.track, param: 3, value: iv)
        case .fx4:    ctrl.setFx(track: lfo.track, param: 4, value: iv)
        case .lfo1:   ctrl.setPatchLfo(track: lfo.track, param: 1, value: iv)
        case .lfo2:   ctrl.setPatchLfo(track: lfo.track, param: 2, value: iv)
        case .lfo3:   ctrl.setPatchLfo(track: lfo.track, param: 3, value: iv)
        case .lfo4:   ctrl.setPatchLfo(track: lfo.track, param: 4, value: iv)
        }
        updateCallback?(lfo.track, lfo.parameter, value)
    }
}
