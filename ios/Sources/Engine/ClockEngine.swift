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
    private let smoothN = 48  // double-smoothing for BLE jitter
    private var lastTickTime: Double = 0

    // MARK: - Master (generating) state
    private var masterTimer: DispatchSourceTimer?
    private var masterTickCount = 0
    private var masterBpm: Double = 100.0
    private let masterQueue = DispatchQueue(label: "clock.master", qos: .userInteractive)

    // MARK: - Transport state
    private var sppBeats = 0

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
                bpm = newBpm
                lock.unlock()
                bpmCallback?(newBpm)
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
        router?.send([0xFA])
        isPlaying = true
    }

    func stop() {
        router?.send([0xFC])
        isPlaying = false
    }

    func tapePrevBar() {
        router?.send([0xB0, 82, 127])
        sppBeats = max(0, sppBeats - 4)
        sendSPP()
    }

    func tapeNextBar() {
        router?.send([0xB0, 83, 127])
        sppBeats += 4
        sendSPP()
    }

    private func sendSPP() {
        // Song Position Pointer: position in MIDI beats (6 ticks each), LSB first
        let pos = sppBeats * (PPQN / 6)
        let lo = UInt8(pos & 0x7F)
        let hi = UInt8((pos >> 7) & 0x7F)
        router?.send([0xF2, lo, hi])
        if isPlaying { router?.send([0xFB]) }
    }
}
