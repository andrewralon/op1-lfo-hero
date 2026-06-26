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
    private var startTicks:      [UUID: Int]    = [:]
    private var lastSent:        [UUID: Double] = [:]
    private var randomStep:      [UUID: Int]    = [:]   // last step index (0-7)
    private var randomState:     [UUID: UInt64] = [:]   // xorshift64 PRNG state, seeded per clip
    private var randomValue:     [UUID: Double] = [:]   // held output for current step
    private var disabledClipIDs: Set<UUID>      = []

    // Preview LFOs — run continuously, never appear in activeLfos
    private var previewLfos:     [LfoClip] = []
    private var previewLastSent: [UUID: Double] = [:]
    private var previewRandStep:  [UUID: Int]    = [:]
    private var previewRandState: [UUID: UInt64] = [:]
    private var previewRandValue: [UUID: Double] = [:]

    func add(_ lfo: LfoClip) {
        lock.lock(); lfos.append(lfo); lock.unlock()
    }

    func remove(_ lfo: LfoClip) {
        lock.lock()
        lfos.removeAll { $0.id == lfo.id }
        startTicks.removeValue(forKey: lfo.id)
        lastSent.removeValue(forKey: lfo.id)
        randomStep.removeValue(forKey: lfo.id)
        randomState.removeValue(forKey: lfo.id)
        randomValue.removeValue(forKey: lfo.id)
        disabledClipIDs.remove(lfo.id)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        lfos.removeAll()
        startTicks.removeAll(); lastSent.removeAll()
        randomStep.removeAll(); randomState.removeAll(); randomValue.removeAll()
        disabledClipIDs.removeAll()
        lock.unlock()
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        if enabled { disabledClipIDs.remove(id) }
        else        { disabledClipIDs.insert(id) }
    }

    func sendRestore(lfo: LfoClip, value: Double) {
        dispatch(lfo: lfo, value: value)
    }

    func setPreview(_ clips: [LfoClip]) {
        lock.lock()
        previewLfos = clips
        let ids = Set(clips.map { $0.id })
        previewLastSent   = previewLastSent.filter   { ids.contains($0.key) }
        previewRandStep   = previewRandStep.filter   { ids.contains($0.key) }
        previewRandState  = previewRandState.filter  { ids.contains($0.key) }
        previewRandValue  = previewRandValue.filter  { ids.contains($0.key) }
        lock.unlock()
    }

    func clearPreview() {
        lock.lock()
        previewLfos.removeAll()
        previewLastSent.removeAll()
        previewRandStep.removeAll(); previewRandState.removeAll(); previewRandValue.removeAll()
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
            let isDisabled = disabledClipIDs.contains(lfo.id)
            let start = startTicks[lfo.id] ?? tickCount
            lock.unlock()

            if isDisabled { continue }  // phase advances implicitly; re-enable picks up at correct phase

            let elapsed = tickCount - start

            // One-shot: auto-remove after 8 beats (one full cycle at slowest useful rate)
            if !lfo.loop {
                let oneCycle = lfo.rateTicks
                if elapsed >= oneCycle {
                    finished.append(lfo)
                    continue
                }
            }

            let phase = Double(tickCount % lfo.rateTicks) / Double(lfo.rateTicks)
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

        // Preview LFOs — continuous, never finish or appear in activeLfos.
        // Phase uses the same global-clock formula as active looping chips (tickCount % period),
        // so it's always non-negative and survives slaveTick resets without any phase glitch.
        lock.lock()
        let currentPreview = previewLfos
        lock.unlock()

        for lfo in currentPreview {
            let pPhase = Double(tickCount % lfo.rateTicks) / Double(lfo.rateTicks)
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
            let curStep = Int(p * 2) % 2
            lock.lock()
            if curStep != (previewRandStep[lfo.id] ?? -1) {
                var state = previewRandState[lfo.id] ?? UInt64.random(in: 1...UInt64.max)
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                previewRandState[lfo.id] = state
                previewRandStep[lfo.id]  = curStep
                previewRandValue[lfo.id] = Double(state) / Double(UInt64.max) * 2.0 - 1.0
            }
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
            let curStep = Int(p * 2) % 2
            lock.lock()
            if curStep != (randomStep[lfo.id] ?? -1) {
                var state = randomState[lfo.id] ?? UInt64.random(in: 1...UInt64.max)
                state ^= state << 13; state ^= state >> 7; state ^= state << 17
                randomState[lfo.id] = state
                randomStep[lfo.id]  = curStep
                randomValue[lfo.id] = Double(state) / Double(UInt64.max) * 2.0 - 1.0
            }
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
        case .tempo:      break  // tempo modulation handled in AppState via updateCallback
        case .par1:       ctrl.setPar(track: lfo.track, param: 1, value: iv)
        case .par2:       ctrl.setPar(track: lfo.track, param: 2, value: iv)
        case .par3:       ctrl.setPar(track: lfo.track, param: 3, value: iv)
        case .par4:       ctrl.setPar(track: lfo.track, param: 4, value: iv)
        case .envA: ctrl.setEnv(track: lfo.track, param: 1, value: iv)
        case .envD: ctrl.setEnv(track: lfo.track, param: 2, value: iv)
        case .envS: ctrl.setEnv(track: lfo.track, param: 3, value: iv)
        case .envR: ctrl.setEnv(track: lfo.track, param: 4, value: iv)
        case .fx1:        ctrl.setFx(track: lfo.track, param: 1, value: iv)
        case .fx2:        ctrl.setFx(track: lfo.track, param: 2, value: iv)
        case .fx3:        ctrl.setFx(track: lfo.track, param: 3, value: iv)
        case .fx4:        ctrl.setFx(track: lfo.track, param: 4, value: iv)
        case .lfo1:       ctrl.setPatchLfo(track: lfo.track, param: 1, value: iv)
        case .lfo2:       ctrl.setPatchLfo(track: lfo.track, param: 2, value: iv)
        case .lfo3:       ctrl.setPatchLfo(track: lfo.track, param: 3, value: iv)
        case .lfo4:       ctrl.setPatchLfo(track: lfo.track, param: 4, value: iv)
        }
        updateCallback?(lfo.track, lfo.parameter, value)
    }
}
