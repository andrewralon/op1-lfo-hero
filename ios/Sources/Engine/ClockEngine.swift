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
    private var masterTickCount = 0
    private var masterBpm: Double = 100.0
    private let masterQueue = DispatchQueue(label: "clock.master", qos: .userInteractive)

    // MARK: - Transport state
    // sppPos is in MIDI Song Position Pointer units (1/16 notes = 6 ticks at 24 PPQN)
    private var sppPos = 0

    // Controls how far each arrow press moves the tape.
    // .measure = 16 SPP units (1 bar in 4/4) | .scrub = 4 SPP units (1 quarter note)
    enum TapeArrowMode { case measure, scrub }
    var tapeArrowMode: TapeArrowMode = .scrub
    private var tapeArrowStep: Int { tapeArrowMode == .measure ? 16 : 4 }

    weak var router: MidiRouter? {
        didSet { wireRouter() }
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
        lock.lock(); slaveTick = 0; lock.unlock()
        isPlaying = true
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

    func disableClock() {
        masterTimer?.cancel()
        masterTimer = nil
        lock.lock()
        isClockMaster = false
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

    func play() {
        // SPP to current position + 0xFB (Continue) is more reliable on OP-1 Field
        // than 0xFA (Start) alone, which some firmware versions ignore after a Stop.
        sendSPP(isCurrentlyPlaying: true)
        isPlaying = true
    }

    func stop() {
        router?.send([0xFC])
        isPlaying = false
    }

    func tapePrev(isCurrentlyPlaying: Bool) {
        sppPos = max(0, sppPos - tapeArrowStep)
        sendSPP(isCurrentlyPlaying: isCurrentlyPlaying)
    }

    func tapeNext(isCurrentlyPlaying: Bool) {
        sppPos += tapeArrowStep
        sendSPP(isCurrentlyPlaying: isCurrentlyPlaying)
    }

    private func sendSPP(isCurrentlyPlaying: Bool) {
        let lo = UInt8(sppPos & 0x7F)
        let hi = UInt8((sppPos >> 7) & 0x7F)
        router?.send([0xF2, lo, hi])
        if isCurrentlyPlaying { router?.send([0xFB]) }
    }
}
