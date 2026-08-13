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
    /// The ceiling is 16x because CC 18 runs out of room before that: at `deadZone 4 +
    /// unitSpeed 4` the offset reaches its maximum of 63 at about 14.75x, and anything beyond
    /// saturates rather than going faster.
    var transportSpeed: Double = 2.0 {
        didSet { transportSpeed = max(0.25, min(16.0, transportSpeed)) }
    }

    /// Scrub ramp shape. Holding a seek button starts at `scrubStartSpeed` and reaches
    /// `maxScrubSpeed` after `scrubRampSeconds`, then holds there. 14x is just under the point
    /// where CC 18 saturates, so the top of the ramp is the fastest the tape can actually go.
    var scrubStartSpeed = 1.0
    var maxScrubSpeed = 14.0
    var scrubRampSeconds = 1.5

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

    /// When the device last sent a clock tick. Recorded for every tick, including while the app
    /// is clock master — `handleSlaveTick` discards those, and the TP-7 forces app-master mode.
    private var lastExternalTickTime: Double = 0

    /// Whether the device's tape is rolling right now.
    ///
    /// In `sync` mode the TP-7 transmits clock only while the tape moves, so an arriving tick is
    /// a direct "it is playing" signal — the only state this device ever reveals, since it
    /// answers no queries. At 1x that is a tick every ~23 ms, so 250 ms of silence means stopped.
    ///
    /// This also makes the direction resync safe: its `0xFC` would rewind a *stopped* tape to
    /// zero, and a live tick proves the tape is not stopped.
    ///
    /// False whenever the device is not in `sync` mode — there is no clock to hear, so the app
    /// falls back to assuming nothing.
    var deviceIsRolling: Bool {
        lastExternalTickTime > 0 && CACurrentMediaTime() - lastExternalTickTime < 0.25
    }

    private func wireRouter() {
        router?.onClock = { [weak self] in
            self?.lastExternalTickTime = CACurrentMediaTime()
            self?.handleSlaveTick()
        }
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
        //
        // `deviceIsRolling` covers the case where the tape was started from the device itself:
        // without it the app believes it is stopped, so the first press is spent re-asserting
        // play on an already-playing tape and appears to do nothing.
        if playTogglesDirection && (isPlaying || deviceIsRolling) {
            isPlaying = true
            reverseDirection()
            return
        }
        // Ops run before `isPlaying` flips, so a `.toggleCC(whenPlaying:)` op sees the state
        // the button was pressed in.
        run(transport.play)
        isPlaying = true
    }

    /// Pitch-bend value that trims reverse playback to exactly 1x.
    ///
    /// CC 18 is too coarse to hit 1x on its own: 1x reverse falls at offset 7.5, and the nearest
    /// integers are 14% slow (7) and 13% fast (8) — both audible, and both reported as such by
    /// ear before being confirmed by measurement. Bend is the finer control, so reverse uses
    /// offset 8 and pulls it back down with bend. Measured: offset 8 alone is 49.7 ticks/s,
    /// bend 9700 brings it to 43.95 against a 44.0 target (0.1% error).
    ///
    /// Forward needs no equivalent — it releases CC 18 and sends Continue, so the device plays at
    /// its own rate exactly.
    var reverseTrimBend = 9700

    /// Bend value meaning "no change", released when returning to forward.
    private let centreBend = 8192

    /// Whether `reverseTrimBend` is currently applied. Only release the bend if this engine set
    /// it: bend is shared with the user-facing speed parameter, so recentring unconditionally
    /// would silently undo a speed the user dialled in.
    private var trimEngaged = false

    /// Flip the tape direction. No-op on devices without a directional transport.
    ///
    /// Forward hands control back to the device's own transport rather than driving CC 18, so
    /// it plays at exactly the normal rate. Reverse uses CC 18, since there is no other way to
    /// play backwards.
    func reverseDirection() {
        guard hasMomentaryScrub else { return }   // no directional transport on this device

        if transportDirection < 0 {
            // Currently reversing -> go forward. Release the reverse trim first, then CC 18, and
            // let the device play at its own rate.
            releaseTrim()
            run(transport.stop.filter {
                if case .directionalTransport = $0 { return true } else { return false }
            })
            router?.send([0xFB])
            isPlaying = true
        } else {
            // Currently forward or stopped -> reverse via CC 18 at 1x, then trim with bend.
            let ops = transport.prev.filter {
                if case .directionalTransport = $0 { return true } else { return false }
            }
            guard case .directionalTransport(let ch, let cc, let center, _, _, _) = ops.first else { return }

            // Force a known direction first. CC 18 *adds* to whatever the transport is already
            // doing, and the device never reports its state — so if the user reversed with the
            // hardware play button, reversing again here would stack to about 3x rather than 1x.
            // Stop-and-continue resets the internal transport to forward. Verified on hardware:
            // sent back to back with no settling delay, and with no audible gap.
            sendCC(ch: ch, cc: cc, val: center)
            router?.send([0xFC])
            router?.send([0xFB])

            let saved = transportSpeed
            transportSpeed = 1.0
            run(ops)
            transportSpeed = saved
            // Only exact at 1x. A user-automated speed parameter writes the same bend channel
            // and will overwrite this, which is the intended precedence.
            sendBend(reverseTrimBend)
            trimEngaged = true
        }
    }

    func stop() {
        // Bend persists across stop/play with no on-screen feedback, so a trim left applied
        // would silently pitch-shift the next playback.
        releaseTrim()
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

    /// Begin scrubbing. Speed starts at `scrubStartSpeed` and ramps to `maxScrubSpeed`.
    func beginScrub(forward: Bool) {
        guard hasMomentaryScrub else {
            // Nudge-style devices have nothing to hold; fire once.
            forward ? tapeNext() : tapePrev()
            return
        }
        endScrub(resend: false)
        speedBeforeScrub = transportSpeed
        scrubHeldSeconds = 0
        transportSpeed = scrubStartSpeed
        run(forward ? transport.next : transport.prev)

        let t = DispatchSource.makeTimerSource(queue: masterQueue)
        t.schedule(deadline: .now() + 0.15, repeating: .milliseconds(150))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.scrubHeldSeconds += 0.15
            // Ramp start -> max over scrubRampSeconds held, then hold at the top.
            let perSecond = (self.maxScrubSpeed - self.scrubStartSpeed) / self.scrubRampSeconds
            let ramped = min(self.maxScrubSpeed,
                             self.scrubStartSpeed + self.scrubHeldSeconds * perSecond)
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
            case .pressPlay:
                // Delegate, never duplicate: this is the same entry point the UI button uses, so
                // the parameter and the button cannot diverge. Safe from recursion because
                // `transport.play` contains no `.pressPlay`.
                play()
            case .tapeSeek(let cc, let steps):
                sppPos = max(0, sppPos + steps * tapeArrowStep)
                router?.send([0xB0, UInt8(cc), 127])
                router?.send([0xF2, UInt8(sppPos & 0x7F), UInt8((sppPos >> 7) & 0x7F)])
                if isPlaying { router?.send([0xFB]) }
            case .cc(let ch, let cc, let value):
                sendCC(ch: ch, cc: cc, val: value)
            case .ccRelative(let ch, let cc, let delta):
                sendCC(ch: ch, cc: cc, val: 64 + delta)
            case .directionalTransport(let ch, let cc, let center, let deadZone, let unitSpeed, let direction):
                // direction 0 releases the grab. Only send it if this control actually HAS the
                // transport: on a TP-7 a redundant stop is read as "stop while already stopped",
                // which rewinds to zero — so sending it unconditionally would lose the user's
                // position every time they pressed stop on a normally-playing tape.
                if direction == 0 && transportDirection == 0 { break }
                // Persistent state — the device keeps moving at this speed until told otherwise.
                // Affine, not proportional: the dead zone has to be cleared before any speed
                // registers, so a plain `unitSpeed * multiplier` lands far too slow (offset 4 is
                // x0.06, not x1).
                let offset = deadZone + Int((Double(unitSpeed) * transportSpeed).rounded())
                sendCC(ch: ch, cc: cc, val: center + direction * max(1, offset))
                transportDirection = direction
            case .toggleCC(let ch, let cc, let value, let whenPlaying):
                if isPlaying == whenPlaying { sendCC(ch: ch, cc: cc, val: value) }
            }
        }
    }

    /// Return bend to centre, but only if this engine applied the reverse trim.
    private func releaseTrim() {
        guard trimEngaged else { return }
        trimEngaged = false
        sendBend(centreBend)
    }

    /// 14-bit pitch bend on channel 1, the TP-7's fine playback-speed control.
    private func sendBend(_ v: Int) {
        let b = max(0, min(16383, v))
        router?.send([0xE0, UInt8(b & 0x7F), UInt8((b >> 7) & 0x7F)])
    }

    private func sendCC(ch: Int, cc: Int, val: Int) {
        router?.send([UInt8(0xB0 | (ch & 0x0F)), UInt8(cc), UInt8(max(0, min(127, val)))])
    }
}
