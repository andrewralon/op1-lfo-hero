import Foundation
import QuartzCore

final class AutomationEngine {
    weak var controller: Controller?

    // Called on clock thread with (track, parameter, midiValue)
    var updateCallback:   ((Int, ParamSpec, Double) -> Void)?
    // Called on clock thread when a one-shot LFO completes
    var finishedCallback: ((LfoClip) -> Void)?

    private var lfos: [LfoClip] = []
    private let lock = NSLock()

    // Active device profile. Kept under its own lock because `lock` is already held while
    // evaluating clips, and the profile is read from inside those critical sections.
    private var _profile: DeviceProfile = .op1Field
    private let profileLock = NSLock()

    var profile: DeviceProfile {
        profileLock.lock(); defer { profileLock.unlock() }
        return _profile
    }

    func setProfile(_ p: DeviceProfile) {
        profileLock.lock(); _profile = p; profileLock.unlock()
    }

    /// True when this clip drives the app's own tempo rather than a MIDI CC.
    private func isTempo(_ lfo: LfoClip, _ p: DeviceProfile) -> Bool {
        p.param(lfo.paramId)?.role == .tempo
    }

    // Per-clip mutable state tracked by UUID (all accessed under lock)
    private var startTicks:      [UUID: Int]    = [:]
    private var freeRateStart:   [UUID: Double] = [:]  // wall-clock start for free-rate clips
    private var lastSent:        [UUID: Double] = [:]
    private var randomStep:      [UUID: Int]    = [:]   // last step index (0-7)
    private var randomState:     [UUID: UInt64] = [:]   // xorshift64 PRNG state, seeded per clip
    private var randomValue:     [UUID: Double] = [:]   // held output for current step
    private var disabledClipIDs: Set<UUID>      = []

    /// Clock tick at which each chip's cycle begins. Absent means 0, i.e. the cycle is locked to
    /// the clock grid (`tickCount % rateTicks`). A play event re-origins every active chip so it
    /// starts again from the beginning of its wave; the global tick counter is never reset
    /// (resetting it snapped LFOs to their centre — see ClockEngine.handleStart).
    private var chipPhaseOrigin: [UUID: Int] = [:]
    private var previewPhaseOrigin = 0
    private var restartPending = false

    // Preview LFOs — run continuously, never appear in activeLfos
    private var previewLfos:        [LfoClip] = []
    private var previewLastSent:    [UUID: Double] = [:]
    private var freePreviewStart:   [UUID: Double] = [:]  // wall-clock for free-rate previews
    private var previewRandStep:    [UUID: Int]    = [:]
    private var previewRandState:   [UUID: UInt64] = [:]
    private var previewRandValue:   [UUID: Double] = [:]

    /// The first preview clip seen for each (track, parameter). Its `originalValue` is what the
    /// parameter should go back to when preview stops targeting it. Kept across the clip
    /// rebuilds that every slider tweak causes (each rebuild mints new UUIDs), so the value
    /// recorded is the one from *before* the preview first touched the parameter.
    private struct PreviewTarget: Hashable { let track: Int; let paramId: String }
    private var previewOriginals: [PreviewTarget: LfoClip] = [:]

    func add(_ lfo: LfoClip) {
        lock.lock(); lfos.append(lfo); lock.unlock()
    }

    func remove(_ lfo: LfoClip) {
        lock.lock()
        lfos.removeAll { $0.id == lfo.id }
        startTicks.removeValue(forKey: lfo.id)
        freeRateStart.removeValue(forKey: lfo.id)
        lastSent.removeValue(forKey: lfo.id)
        randomStep.removeValue(forKey: lfo.id)
        randomState.removeValue(forKey: lfo.id)
        randomValue.removeValue(forKey: lfo.id)
        chipPhaseOrigin.removeValue(forKey: lfo.id)
        disabledClipIDs.remove(lfo.id)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        lfos.removeAll()
        startTicks.removeAll(); freeRateStart.removeAll(); lastSent.removeAll()
        randomStep.removeAll(); randomState.removeAll(); randomValue.removeAll()
        chipPhaseOrigin.removeAll()
        disabledClipIDs.removeAll()
        lock.unlock()
    }

    /// Restart every active LFO from the start of its cycle on the next clock tick. Called when
    /// play is pressed on the app (app is master) or arrives from the device (device is master).
    /// Paused chips are left alone, and a one-shot that already finished is no longer in the
    /// engine, so neither is replayed.
    func restartAll() {
        lock.lock(); restartPending = true; lock.unlock()
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
        let targets = Set(clips.map { PreviewTarget(track: $0.track, paramId: $0.paramId) })
        let departing = takeDepartingPreviewTargets(keeping: targets)
        for clip in clips {
            let t = PreviewTarget(track: clip.track, paramId: clip.paramId)
            if previewOriginals[t] == nil { previewOriginals[t] = clip }
        }
        let ids = Set(clips.map { $0.id })
        previewLastSent  = previewLastSent.filter  { ids.contains($0.key) }
        freePreviewStart  = freePreviewStart.filter  { ids.contains($0.key) }
        previewRandStep  = previewRandStep.filter  { ids.contains($0.key) }
        previewRandState = previewRandState.filter { ids.contains($0.key) }
        previewRandValue = previewRandValue.filter { ids.contains($0.key) }
        lock.unlock()
        restore(departing)
    }

    /// Stops previewing and puts every previewed parameter back to the value it had before.
    func clearPreview() {
        lock.lock()
        previewLfos.removeAll()
        previewLastSent.removeAll(); freePreviewStart.removeAll()
        previewRandStep.removeAll(); previewRandState.removeAll(); previewRandValue.removeAll()
        let departing = takeDepartingPreviewTargets(keeping: [])
        lock.unlock()
        restore(departing)
    }

    /// The value `track`'s `paramId` had before preview first touched it, or nil if it isn't
    /// being previewed. The app's live state can't answer this: it follows the running LFO.
    func previewOriginalValue(track: Int, paramId: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return previewOriginals[PreviewTarget(track: track, paramId: paramId)]?.originalValue
    }

    /// Removes and returns the recorded clip for every previewed target not in `keeping`.
    /// Caller holds `lock`. A target an enabled chip is already driving is dropped without a
    /// restore — the chip owns that parameter now, and a restore would only glitch it.
    private func takeDepartingPreviewTargets(keeping: Set<PreviewTarget>) -> [LfoClip] {
        var out: [LfoClip] = []
        for (target, clip) in previewOriginals where !keeping.contains(target) {
            previewOriginals.removeValue(forKey: target)
            let drivenByChip = lfos.contains {
                $0.track == target.track && $0.paramId == target.paramId
                    && !disabledClipIDs.contains($0.id)
            }
            if !drivenByChip { out.append(clip) }
        }
        return out
    }

    private func restore(_ clips: [LfoClip]) {
        for clip in clips { dispatch(lfo: clip, value: clip.originalValue) }
    }

    // Replace a clip's settings in-place without resetting its phase.
    func update(_ lfo: LfoClip) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = lfos.firstIndex(where: { $0.id == lfo.id }) else { return }
        lfos[idx] = lfo
    }

    func snapshot() -> [LfoClip] {
        lock.lock(); defer { lock.unlock() }
        return lfos
    }

    // MARK: - Tick evaluation (called on clock thread)

    func onTick(_ tickCount: Int) {
        let now = CACurrentMediaTime()  // wall-clock for absolute-time clips

        lock.lock()
        let current = lfos  // snapshot while locked
        if restartPending {
            restartPending = false
            for lfo in current where !disabledClipIDs.contains(lfo.id) {
                chipPhaseOrigin[lfo.id] = tickCount
                startTicks[lfo.id] = tickCount
                if lfo.freeRatePeriod != nil { freeRateStart[lfo.id] = now }
                lastSent.removeValue(forKey: lfo.id)   // the first value must be sent even if equal
                randomStep.removeValue(forKey: lfo.id)
                randomState.removeValue(forKey: lfo.id)
                randomValue.removeValue(forKey: lfo.id)
            }
            previewPhaseOrigin = tickCount
            previewLastSent.removeAll(); freePreviewStart.removeAll()
            previewRandStep.removeAll(); previewRandState.removeAll(); previewRandValue.removeAll()
        }
        for lfo in current where startTicks[lfo.id] == nil {
            startTicks[lfo.id] = tickCount
        }
        for lfo in current where lfo.freeRatePeriod != nil && freeRateStart[lfo.id] == nil {
            freeRateStart[lfo.id] = now
        }
        lock.unlock()

        var finished = [LfoClip]()

        for lfo in current {
            lock.lock()
            let isDisabled = disabledClipIDs.contains(lfo.id)
            lock.unlock()

            if isDisabled { continue }  // phase advances implicitly; re-enable picks up at correct phase

            let phase: Double
            if let period = lfo.freeRatePeriod {
                lock.lock()
                let start = freeRateStart[lfo.id] ?? now
                lock.unlock()
                let elapsed = now - start
                if !lfo.loop && elapsed >= period { finished.append(lfo); continue }
                phase = (elapsed / period).truncatingRemainder(dividingBy: 1.0)
            } else {
                lock.lock()
                let start = startTicks[lfo.id] ?? tickCount
                lock.unlock()
                let elapsed = tickCount - start
                if !lfo.loop && elapsed >= lfo.rateTicks { finished.append(lfo); continue }
                lock.lock()
                let origin = chipPhaseOrigin[lfo.id] ?? 0
                lock.unlock()
                phase = Double(cycleTick(tickCount - origin, lfo.rateTicks)) / Double(lfo.rateTicks)
            }

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
        lock.lock()
        let currentPreview = previewLfos
        for lfo in currentPreview where lfo.freeRatePeriod != nil && freePreviewStart[lfo.id] == nil {
            freePreviewStart[lfo.id] = now
        }
        lock.unlock()

        for lfo in currentPreview {
            let pPhase: Double
            if let period = lfo.freeRatePeriod {
                lock.lock()
                let start = freePreviewStart[lfo.id] ?? now
                lock.unlock()
                pPhase = ((now - start) / period).truncatingRemainder(dividingBy: 1.0)
            } else {
                lock.lock()
                let origin = previewPhaseOrigin
                lock.unlock()
                pPhase = Double(cycleTick(tickCount - origin, lfo.rateTicks)) / Double(lfo.rateTicks)
            }
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

    /// `ticks` modulo `cycle`, never negative.
    private func cycleTick(_ ticks: Int, _ cycle: Int) -> Int {
        ((ticks % cycle) + cycle) % cycle
    }

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
        if isTempo(lfo, profile) {
            return max(AppState.minBpm, min(AppState.maxBpm, lfo.centerValue + y * lfo.depth))
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

        if isTempo(lfo, profile) {
            return max(AppState.minBpm, min(AppState.maxBpm, lfo.centerValue + y * lfo.depth))
        }
        return max(0, min(127, (lfo.centerValue + y * lfo.depth).rounded()))
    }

    private func dispatch(lfo: LfoClip, value: Double) {
        let p = profile
        // A clip saved for a different device must never reach this one's MIDI channels —
        // possible for a moment while a profile switch is in flight.
        guard lfo.deviceId == p.id, let spec = p.param(lfo.paramId) else { return }
        // A `.virtualTempo` binding sends nothing; AppState retunes the clock via updateCallback.
        controller?.send(spec: spec, track: lfo.track, value: value, profile: p)
        updateCallback?(lfo.track, spec, value)
    }
}
