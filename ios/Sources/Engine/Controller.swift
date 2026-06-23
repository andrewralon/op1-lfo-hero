import Foundation

final class Controller {
    weak var router: MidiRouter?

    private let CC_VOLUME    = 7
    private let CC_MUTE      = 9
    private let CC_PAN       = 10
    private let CC_OCTAVE    = 79
    private let CC_PAR_BASE   = 46
    private let CC_ENV_BASE   = 50
    private let CC_FX_BASE    = 54
    private let CC_LFO_BASE   = 58
    private let CC_MFX_BASE  = 70
    private let CC_MCOMP_BASE = 74

    private var muteState = [Int: Bool]()
    private let lock = NSLock()

    init(router: MidiRouter) {
        self.router = router
    }

    func setVolume(track: Int, value: Int) {
        sendCC(ch: track - 1, cc: CC_VOLUME, val: value)
    }

    func setPan(track: Int, value: Int) {
        sendCC(ch: track - 1, cc: CC_PAN, val: value)
    }

    // Returns the new mute state
    @discardableResult
    func toggleMute(track: Int) -> Bool {
        lock.lock()
        let now = !(muteState[track] ?? false)
        muteState[track] = now
        lock.unlock()
        sendCC(ch: track - 1, cc: CC_MUTE, val: now ? 127 : 0)
        return now
    }

    func mute(track: Int) {
        lock.lock(); muteState[track] = true; lock.unlock()
        sendCC(ch: track - 1, cc: CC_MUTE, val: 127)
    }

    func unmute(track: Int) {
        lock.lock(); muteState[track] = false; lock.unlock()
        sendCC(ch: track - 1, cc: CC_MUTE, val: 0)
    }

    func isMuted(_ track: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return muteState[track] ?? false
    }

    func setPar(track: Int, param: Int, value: Int) {
        sendCC(ch: max(0, track - 1), cc: CC_PAR_BASE + param - 1, val: value)
    }

    func setEnv(track: Int, param: Int, value: Int) {
        sendCC(ch: max(0, track - 1), cc: CC_ENV_BASE + param - 1, val: value)
    }

    func setFx(track: Int, param: Int, value: Int) {
        let cc = track == 0 ? CC_MFX_BASE + param - 1 : CC_FX_BASE + param - 1
        sendCC(ch: max(0, track - 1), cc: cc, val: value)
    }

    func setPatchLfo(track: Int, param: Int, value: Int) {
        let cc = track == 0 ? CC_MCOMP_BASE + param - 1 : CC_LFO_BASE + param - 1
        sendCC(ch: max(0, track - 1), cc: cc, val: value)
    }

    func octaveUp()   { router?.send([0xB0, UInt8(CC_OCTAVE), 127]) }
    func octaveDown() { router?.send([0xB0, UInt8(CC_OCTAVE), 0])   }

    private func sendCC(ch: Int, cc: Int, val: Int) {
        let v = max(0, min(127, val))
        router?.send([UInt8(0xB0 | (ch & 0x0F)), UInt8(cc), UInt8(v)])
    }
}
