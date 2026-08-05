import Foundation
import QuartzCore

final class ClockEngine {

    // MARK: - Shared state (protected by lock)
    private let lock = NSLock()
    private(set) var bpm: Double = 100.0
    private(set) var isPlaying = false
    private(set) var isClockMaster = false

    // MARK: - Callbacks (set before use; called on background thread)
    var tickCallback: ((Int) -> Void)?
    var bpmCallback:  ((Double) -> Void)?

    // MARK: - Slave (listening) state
    private var slaveTick = 0
    private var bpmHistory: [Double] = []
    private let smoothN = 96  // larger window = smoother BPM display over BLE/USB jitter
    private var lastTickTime: Double = 0

    // MARK: - Master (generating) state
    private var masterTimer: DispatchSourceTimer?
    private var masterTimerSuspended = false
    private var masterTickCount = 0
    private var masterBpm: Double = 100.0
    private let masterQueue = DispatchQueue(label: "clock.master", qos: .userInteractive)

    // MARK: - Transport state
    // sppPos is in MIDI Song Position Pointer units (1/16 notes = 6 ticks at 24 PPQN)
    private var sppPos = 0
    // Play always sends Continue (0xFB) so the tape picks up where it left off — the same
    // behaviour as the hardware's own play button. Only an explicit rewind makes the next play
    // send Start (0xFA), which per the MIDI spec restarts from position zero.
    //
    // Verified on a TP-7: 0xFA rewound to 0, 0xFB resumed. Sending Start on the first play of a
    // session (the old behaviour) therefore rewound the user's tape once, unasked.
    //
    // Set by rewindToStart(), which the double-stop feature should call — see notes/FEATURES.md.
    private var rewindPending = false

    /// Seek speed as a **multiple of normal playback**, used by `.directionalTransport`.
    /// 1.0 = normal speed, 2.0 = double (the TP-7's "chipmunks"), 0.5 = half.
    ///
    /// Expressed as a multiplier rather than a raw CC offset because the device holds this as a
    /// persistent playback speed, and because the offset that means "1x" is device-specific
    /// (the op's `unitSpeed` carries it). Defaults to 2x so the seek buttons feel like a
    /// fast-forward rather than plain playback.
    var transportSpeed: Double = 2.0 {
        didSet { transportSpeed = max(0.25, min(8.0, transportSpeed)) }
    }

    /// Last direction sent by a `.directionalTransport` op: -1 reverse, 0 stopped, +1 forward.
    private(set) var transportDirection = 0

    // Controls how far each arrow press moves the tape.
    // .measure = 16 SPP units (1 bar in 4/4) | .scrub = 4 SPP units (1 quarter note)
    enum TapeArrowMode { case measure, scrub }
    var tapeArrowMode: TapeArrowMode = .measure
    private var tapeArrowStep: Int { tapeArrowMode == .measure ? 16 : 4 }

    weak var router: (any MidiDestination)? {
        didSet { wireRouter() }
    }

    deinit {
        // A resumed DispatchSourceTimer traps in libdispatch if it is released while active,
        // and a suspended one traps if cancelled without resuming first. Both timers have to
        // be shut down explicitly.
        scrubTimer?.cancel()
        if masterTimerSuspended { masterTimer?.resume() }
        masterTimer?.cancel()
    }

    private func wireRouter() {
        router?.onClock = { [weak self] in self?.handleSlaveTick() }
        router?.onStart = { [weak self] in self?.handleStart() }
        router?.onStop  = { [weak self] in self?.handleStop()  }
    }

    // MARK: - Slave mode

    private func handleSlaveTick() {
        guard !isClockMaster else { return }
        let now = CACurrentMediaTime()
        lock.lock()
        slaveTick += 1
        let tick = slaveTick
        // Track tape position in real time: 1 SPP unit = 6 ticks at 24 PPQN
        if isPlaying && slaveTick % 6 == 0 { sppPos += 1 }
        if lastTickTime > 0 {
            let interval = now - lastTickTime
            bpmHistory.append(interval)
            if bpmHistory.count > smoothN { bpmHistory.removeFirst() }
            if bpmHistory.count >= 8 {
                let avg = bpmHistory.reduce(0, +) / Double(bpmHistory.count)
                let newBpm = 60.0 / (Double(PPQN) * avg)
                // Only publish when the change is visible at 1-decimal display precision
                if abs(newBpm - bpm) >= 0.05 {
                    bpm = newBpm
                    lock.unlock()
                    bpmCallback?(newBpm)
                } else {
                    lock.unlock()
                }
            } else {
                lock.unlock()
            }
        } else {
            lock.unlock()
        }
        lastTickTime = now
        tickCallback?(tick)
    }

    private func handleStart() {
        isPlaying = true
        // slaveTick is intentionally NOT reset here. Resetting it causes the LFO phase formula
        // (tickCount % rateTicks) to jump to ~0 on every loop boundary, snapping LFOs to
        // their center value. slaveTick stays monotonic so phases continue smoothly.
    }

    private func handleStop() {
        isPlaying = false
    }

    // MARK: - Master mode

    func enableClock(bpm startBpm: Double) {
        disableClock()
        lock.lock()
        isClockMaster = true
        masterBpm = max(20, min(300, startBpm))
        bpm = masterBpm
        masterTickCount = 0
        lock.unlock()
        scheduleMasterTimer(bpm: masterBpm)
        bpmCallback?(masterBpm)
    }

    func suspendMasterTimer() {
        guard isClockMaster, let t = masterTimer, !masterTimerSuspended else { return }
        t.suspend()
        masterTimerSuspended = true
    }

    func resumeMasterTimerIfSuspended() {
        guard masterTimerSuspended, let t = masterTimer else { return }
        t.resume()
        masterTimerSuspended = false
    }

    func disableClock() {
        // DispatchSourceTimer must not be cancelled while suspended — resume first.
        if masterTimerSuspended { masterTimer?.resume(); masterTimerSuspended = false }
        masterTimer?.cancel()
        masterTimer = nil
        lock.lock()
        isClockMaster = false
        bpm = 0   // sentinel: no slave data; cleared when first OP-1 ticks arrive
        bpmHistory.removeAll()
        lastTickTime = 0
        slaveTick = 0
        lock.unlock()
    }

    func setMasterBpm(_ newBpm: Double) {
        guard isClockMaster else { return }
        let clamped = max(20, min(300, newBpm))
        lock.lock(); masterBpm = clamped; bpm = clamped; lock.unlock()
        scheduleMasterTimer(bpm: clamped)
        bpmCallback?(clamped)
    }

    /// Updates the stored BPM without restarting the timer — safe to call at LFO tick rate.
    /// The running timer adapts its period on the next tick via fireMasterTick.
    func updateMasterBpm(_ newBpm: Double) {
        guard isClockMaster else { return }
        let clamped = max(20, min(300, newBpm))
        lock.lock(); masterBpm = clamped; bpm = clamped; lock.unlock()
        bpmCallback?(clamped)
    }

    // nextFireTime tracks the absolute intended fire time so rescheduling never
    // adds handler execution latency to the period (only accessed on masterQueue).
    private var nextFireTime: DispatchTime = .now()
    private var lastTickNs = 0

    private func scheduleMasterTimer(bpm: Double) {
        masterTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: masterQueue)
        masterTimer = t
        let ns = Int(60_000_000_000 / (bpm * Double(PPQN)))
        nextFireTime = .now()
        lastTickNs = 0  // force period sync on first tick
        t.schedule(deadline: nextFireTime, repeating: .nanoseconds(ns), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.fireMasterTick() }
        t.resume()
    }

    private func fireMasterTick() {
        router?.send([0xF8])
        lock.lock()
        masterTickCount += 1
        let tick = masterTickCount
        let currentBpm = masterBpm
        // Track tape position in real time: 1 SPP unit = 6 ticks at 24 PPQN
        if isPlaying && masterTickCount % 6 == 0 { sppPos += 1 }
        lock.unlock()

        let ns = Int(60_000_000_000 / (currentBpm * Double(PPQN)))
        // Always advance by the current period so nextFireTime stays on the ideal grid.
        // Only reschedule the timer when the period actually changes — and use the
        // absolute nextFireTime so handler latency never accumulates into the clock.
        nextFireTime = nextFireTime + .nanoseconds(ns)
        if ns != lastTickNs {
            lastTickNs = ns
            masterTimer?.schedule(deadline: nextFireTime,
                                  repeating: .nanoseconds(ns),
                                  leeway: .microseconds(200))
        }

        tickCallback?(tick)
    }

    // MARK: - Transport commands

    /// What the transport buttons send. The OP-1 uses MIDI start/stop plus tape SPP seeks;
    /// other devices use their own CCs. Set from the active profile by AppState.
    var transport: TransportMap = DeviceProfile.op1Field.transport

    /// When true, pressing play while already playing reverses direction instead of
    /// re-sending play — matching the TP-7's own play button. Set from the device profile.
    var playTogglesDirection = false

    func play() {
        // Matches the hardware: on a device whose play button reverses, a second press while
        // rolling flips direction rather than restarting playback.
        if playTogglesDirection && isPlaying {
            reverseDirection()
            return
        }
        // Ops run before `isPlaying` flips, so a `.toggleCC(whenPlaying:)` op sees the state
        // the button was pressed in.
        run(transport.play)
        isPlaying = true
    }

    /// Flip the tape direction using whichever `.directionalTransport` op the profile defines.
    /// No-op on devices that have no directional transport.
    ///
    /// Always at 1x: this is a *playback* direction change, not a seek, so it should sound like
    /// playing backwards rather than rewinding. The user's seek speed is left untouched.
    func reverseDirection() {
        let newDirection = transportDirection >= 0 ? -1 : 1
        let ops = (newDirection > 0 ? transport.next : transport.prev).filter {
            if case .directionalTransport = $0 { return true } else { return false }
        }
        guard !ops.isEmpty else { return }
        let saved = transportSpeed
        transportSpeed = 1.0
        run(ops)
        transportSpeed = saved
    }

    func stop() {
        run(transport.stop)
        isPlaying = false
    }

    /// Arm a rewind: the next play sends Start (0xFA) instead of Continue, so the device
    /// restarts from zero. Intended for the double-stop gesture.
    func rewindToStart() {
        lock.lock(); rewindPending = true; sppPos = 0; lock.unlock()
    }

    func tapePrev() { run(transport.prev) }
    func tapeNext() { run(transport.next) }

    // MARK: - Momentary scrubbing
    //
    // On devices whose seek is a persistent speed state (the TP-7's CC 18), holding a scrub
    // button should move the reel only while held, and move faster the longer it is held —
    // rather than latching a speed the user then has to cancel.

    private var scrubTimer: DispatchSourceTimer?
    private var scrubHeldSeconds = 0.0
    private var speedBeforeScrub: Double?

    /// True when the active profile seeks via a persistent speed state rather than a nudge.
    var hasMomentaryScrub: Bool {
        (transport.prev + transport.next).contains {
            if case .directionalTransport = $0 { return true } else { return false }
        }
    }

    /// Begin scrubbing. Speed starts near 1x and ramps toward 8x over a few seconds of holding.
    func beginScrub(forward: Bool) {
        guard hasMomentaryScrub else {
            // Nudge-style devices have nothing to hold; fire once.
            forward ? tapeNext() : tapePrev()
            return
        }
        endScrub(resend: false)
        speedBeforeScrub = transportSpeed
        scrubHeldSeconds = 0
        transportSpeed = 1.0
        run(forward ? transport.next : transport.prev)

        let t = DispatchSource.makeTimerSource(queue: masterQueue)
        t.schedule(deadline: .now() + 0.15, repeating: .milliseconds(150))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.scrubHeldSeconds += 0.15
            // Ramp 1x -> 8x over ~3s held, then hold at the top.
            let ramped = min(8.0, 1.0 + self.scrubHeldSeconds * 2.3)
            guard abs(ramped - self.transportSpeed) > 0.05 else { return }
            self.transportSpeed = ramped
            self.run(forward ? self.transport.next : self.transport.prev)
        }
        t.resume()
        scrubTimer = t
    }

    /// Release: stop the reel and restore the speed the user had configured.
    func endScrub(resend: Bool = true) {
        scrubTimer?.cancel()
        scrubTimer = nil
        scrubHeldSeconds = 0
        if resend, hasMomentaryScrub, transportDirection != 0 {
            // Return CC 18 to centre so the tape stops when the finger lifts.
            run(transport.stop.filter {
                if case .directionalTransport = $0 { return true } else { return false }
            })
        }
        if let s = speedBeforeScrub { transportSpeed = s; speedBeforeScrub = nil }
    }

    /// Run an arbitrary op list — used by `.transport` parameters as well as the buttons.
    func runOps(_ ops: [TransportOp]) { run(ops) }

    private func run(_ ops: [TransportOp]) {
        for op in ops {
            switch op {
            case .midiStartOrContinue:
                if rewindPending {
                    sppPos = 0
                    router?.send([0xFA])   // Start = play from zero
                    rewindPending = false
                } else {
                    router?.send([0xFB])   // Continue = resume from current position
                }
            case .midiStop:
                router?.send([0xFC])
            case .tapeSeek(let cc, let steps):
                sppPos = max(0, sppPos + steps * tapeArrowStep)
                router?.send([0xB0, UInt8(cc), 127])
                router?.send([0xF2, UInt8(sppPos & 0x7F), UInt8((sppPos >> 7) & 0x7F)])
                if isPlaying { router?.send([0xFB]) }
            case .cc(let ch, let cc, let value):
                sendCC(ch: ch, cc: cc, val: value)
            case .ccRelative(let ch, let cc, let delta):
                sendCC(ch: ch, cc: cc, val: 64 + delta)
            case .directionalTransport(let ch, let cc, let center, let unitSpeed, let direction):
                // direction 0 releases the grab. Only send it if this control actually HAS the
                // transport: on a TP-7 a redundant stop is read as "stop while already stopped",
                // which rewinds to zero — so sending it unconditionally would lose the user's
                // position every time they pressed stop on a normally-playing tape.
                if direction == 0 && transportDirection == 0 { break }
                // Persistent state — the device keeps moving at this speed until told otherwise.
                let offset = Int((Double(unitSpeed) * transportSpeed).rounded())
                sendCC(ch: ch, cc: cc, val: center + direction * max(1, offset))
                transportDirection = direction
            case .toggleCC(let ch, let cc, let value, let whenPlaying):
                if isPlaying == whenPlaying { sendCC(ch: ch, cc: cc, val: value) }
            }
        }
    }

    private func sendCC(ch: Int, cc: Int, val: Int) {
        router?.send([UInt8(0xB0 | (ch & 0x0F)), UInt8(cc), UInt8(max(0, min(127, val)))])
    }
}
