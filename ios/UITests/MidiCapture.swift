import CoreMIDI
import Foundation

/// A second, independent CoreMIDI client that listens to the same physical MIDI source the
/// app-under-test is talking to. Runs inside the XCUITest runner process — a separate OS
/// process from the app under test — but CoreMIDI allows multiple simultaneous input-port
/// connections to one source, so this does not interfere with the app's own connection (see
/// USBMidi.swift's identical setup on the app side).
///
/// Deliberately re-implemented here rather than shared with USBMidi.swift: that file imports
/// UIKit and carries app-lifecycle assumptions (foregrounding, manual reconnect) that don't
/// belong in a test target. tools/midi/anymidi.swift already duplicates the same CoreMIDI
/// listen pattern standalone for the same reason.
final class MidiCapture {

    enum Event: Equatable {
        case cc(channel: UInt8, cc: UInt8, value: UInt8)
        case pitchBend(channel: UInt8, value: UInt16)
        case clock, start, stop
    }

    private var client  = MIDIClientRef()
    private var inPort  = MIDIPortRef()
    private var srcRef  = MIDIEndpointRef()
    private var thread: Thread?
    private var runLoop: RunLoop?

    private let lock = NSLock()
    private var events: [Event] = []

    /// Enumerates current CoreMIDI sources and returns true if any non-offline source's name
    /// contains one of the given substrings (case-insensitive). Synchronous — safe to call
    /// before deciding whether to XCTSkip, without starting the listener thread.
    static func hasMatchingSource(nameTokens: [String]) -> Bool {
        matchingSource(nameTokens: nameTokens) != 0
    }

    private static func matchingSource(nameTokens: [String]) -> MIDIEndpointRef {
        let lowered = nameTokens.map { $0.lowercased() }
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyOffline, &offline)
            guard offline == 0 else { continue }
            var prop: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &prop) == noErr,
                  let name = prop?.takeRetainedValue() as String? else { continue }
            let lower = name.lowercased()
            if lowered.contains(where: { lower.contains($0) }) {
                return src
            }
        }
        return 0
    }

    /// Starts a dedicated CoreMIDI thread (mirrors USBMidi's midiRunLoop pattern — CoreMIDI
    /// only keeps delivering data to a thread with an actively-pumping run loop), connects to
    /// the first source whose name matches `nameTokens`, and begins recording events.
    func start(nameTokens: [String]) {
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = RunLoop.current
            RunLoop.current.add(Port(), forMode: .default)
            RunLoop.current.perform { [weak self] in self?.setup(nameTokens: nameTokens) }
            RunLoop.current.run()
        }
        thread.name = "MidiCapture.CoreMIDI"
        thread.start()
        self.thread = thread
    }

    private func setup(nameTokens: [String]) {
        MIDIClientCreateWithBlock("MidiCapture" as CFString, &client) { _ in }
        MIDIInputPortCreateWithBlock(client, "MidiCaptureIn" as CFString, &inPort) { [weak self] pktList, _ in
            // Iterate via a pointer into the original packet list memory — copying MIDIPacket
            // to the stack then calling MIDIPacketNext on the copy crashes (see USBMidi.swift).
            let raw = UnsafeMutableRawPointer(mutating: pktList)
                .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet) ?? 8)
            var pkt = raw.assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<Int(pktList.pointee.numPackets) {
                let n = Int(pkt.pointee.length)
                withUnsafeBytes(of: pkt.pointee.data) { self?.parseBytes(Array($0.prefix(n))) }
                pkt = MIDIPacketNext(pkt)
            }
        }
        let src = Self.matchingSource(nameTokens: nameTokens)
        guard src != 0 else { return }
        srcRef = src
        MIDIPortConnectSource(inPort, src, nil)
    }

    private func parseBytes(_ bytes: [UInt8]) {
        var i = 0
        var newEvents: [Event] = []
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0xF8: newEvents.append(.clock); i += 1
            case 0xFA: newEvents.append(.start); i += 1
            case 0xFB:                           i += 1  // continue — not tracked, matches USBMidi
            case 0xFC: newEvents.append(.stop);  i += 1
            default:
                guard b & 0x80 != 0 else { i += 1; continue }
                let ch = b & 0x0F
                switch b & 0xF0 {
                case 0xB0 where i + 2 < bytes.count:
                    newEvents.append(.cc(channel: ch, cc: bytes[i + 1], value: bytes[i + 2]))
                    i += 3
                case 0xE0 where i + 2 < bytes.count:
                    let value = UInt16(bytes[i + 1]) | (UInt16(bytes[i + 2]) << 7)
                    newEvents.append(.pitchBend(channel: ch, value: value))
                    i += 3
                case 0x80, 0x90, 0xA0, 0xE0:
                    i += i + 2 < bytes.count ? 3 : 1
                case 0xC0, 0xD0:
                    i += i + 1 < bytes.count ? 2 : 1
                default:
                    i += 1
                }
            }
        }
        guard !newEvents.isEmpty else { return }
        lock.lock()
        events.append(contentsOf: newEvents)
        lock.unlock()
    }

    /// Polls recorded events up to `timeout`, returning true the first time a matching CC
    /// event appears. Plain polling (not Combine/async) keeps this file dependency-free.
    func waitForCC(channel: UInt8, cc: UInt8, value: UInt8, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let target = Event.cc(channel: channel, cc: cc, value: value)
        while Date() < deadline {
            lock.lock()
            let found = events.contains(target)
            lock.unlock()
            if found { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// Disconnects the source and disposes CoreMIDI resources. Call from tearDown.
    func stop() {
        runLoop?.perform { [weak self] in
            guard let self else { return }
            if self.srcRef != 0 { MIDIPortDisconnectSource(self.inPort, self.srcRef); self.srcRef = 0 }
            if self.inPort != 0 { MIDIPortDispose(self.inPort); self.inPort = MIDIPortRef() }
            if self.client != 0 { MIDIClientDispose(self.client); self.client = MIDIClientRef() }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}
