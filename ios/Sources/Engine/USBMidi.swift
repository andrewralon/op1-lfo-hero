import Combine
import CoreMIDI
import Foundation

/// CoreMIDI USB MIDI transport. Auto-detects the OP-1 Field when plugged in via USB-C.
/// Sends raw MIDI bytes (no BLE timestamp wrapper). Calls the same onClock/onStart/onStop/onCC
/// callbacks as BLEMidi so MidiRouter can treat both transports uniformly.
final class USBMidi: NSObject, ObservableObject {

    enum State: Equatable {
        case disconnected
        case found([String])     // MIDI destinations exist but none matched OP-1
        case connected(String)

        var label: String {
            switch self {
            case .disconnected:        return "no USB MIDI"
            case .found(let names):    return names.prefix(2).joined(separator: " | ")
            case .connected(let name): return "\(name) (usb)"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // Virtual/network MIDI endpoints that are never real hardware — filter from found list.
    private static let virtualEndpointNames = ["network session", "bluetooth", "iac driver"]

    @Published var state: State = .disconnected

    var onClock: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?
    var onCC:    ((Int, Int, Int) -> Void)?

    private var client     = MIDIClientRef()
    private var outPort    = MIDIPortRef()
    private var inPort     = MIDIPortRef()
    private var destRef    = MIDIEndpointRef()
    private var srcRef     = MIDIEndpointRef()
    private var pollTimer:    DispatchSourceTimer?
    private var midiThread:   Thread?
    private var midiRunLoop:  RunLoop?

    override init() {
        super.init()
        // CoreMIDI only keeps delivering setup-changed/object-added/object-removed
        // notifications (and refreshing the destination/source cache that
        // MIDIGetNumberOfDestinations() etc. read from) to a thread with an
        // actively-pumping run loop. A throwaway DispatchQueue.global() worker thread
        // exits the instant its block returns, so hot-plug/unplug events silently
        // stop being delivered forever once that thread is gone — the cache then
        // stays frozen at whatever it was when the client was created. Run all
        // CoreMIDI setup on a dedicated thread whose run loop we keep alive for the
        // life of the app instead.
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.midiRunLoop = RunLoop.current
            self.setupMIDI()
            RunLoop.current.add(Port(), forMode: .default)
            RunLoop.current.run()
        }
        thread.name = "USBMidi.CoreMIDI"
        thread.start()
        midiThread = thread
        // Retry scans in case iOS hasn't fully enumerated the USB device yet.
        // Run on global queue — scanForOP1() dispatches state changes to main internally.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 1.0) { self.scanForOP1() }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 1.5) { self.scanForOP1() }
        startPolling()
    }

    // Even with a persistent run loop, CoreMIDI's add/remove notifications have proven
    // unreliable across repeated connect/disconnect cycles on-device — they fire
    // sometimes and not others, with no obvious trigger. Rather than depend on them
    // while we're searching for the OP-1, force a full client teardown/recreate on every
    // tick: that's the one thing that has reliably produced a correct, fresh snapshot in
    // every test (it's exactly what a cold launch does). Only do this while disconnected
    // — recreating the client while actively connected would interrupt the MIDI stream.
    private func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in
            guard let self, !self.state.isConnected else { return }
            self.midiRunLoop?.perform { self.recreateClient() }
        }
        t.resume()
        pollTimer = t
    }

    // Tears down and recreates the CoreMIDI client/ports from scratch, forcing a fresh
    // enumeration from MIDIServer instead of whatever this process's object cache
    // currently (possibly stale) reflects. Must run on midiRunLoop's thread so the new
    // client's notifications stay tied to the persistent run loop.
    private func recreateClient() {
        if inPort != 0  { MIDIPortDispose(inPort);  inPort  = MIDIPortRef() }
        if outPort != 0 { MIDIPortDispose(outPort); outPort = MIDIPortRef() }
        if client != 0  { MIDIClientDispose(client); client = MIDIClientRef() }
        destRef = 0
        srcRef = 0
        setupMIDI()
    }

    private func setupMIDI() {
        MIDIClientCreateWithBlock("LFOHeroUSB" as CFString, &client) { [weak self] notifPtr in
            let id = notifPtr.pointee.messageID
            guard id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved else { return }
            // MIDIGetNumberOfDestinations() inside scanForOP1() is a blocking IPC call to
            // MIDIServer. If MIDIServer is still starting up it can block for 5–15 seconds.
            // Run on background queue to keep the main thread free.
            let q = DispatchQueue.global(qos: .userInteractive)
            q.asyncAfter(deadline: .now() + 0.15) { self?.scanForOP1() }
            q.asyncAfter(deadline: .now() + 0.50) { self?.scanForOP1() }
        }
        MIDIOutputPortCreate(client, "LFOHeroOut" as CFString, &outPort)
        // MIDIInputPortCreateWithBlock is deprecated in iOS 14 but provides simple
        // MIDI 1.0 byte-stream access; avoids UMP parsing overhead for our use case.
        MIDIInputPortCreateWithBlock(client, "LFOHeroIn" as CFString, &inPort) { [weak self] pktList, _ in
            // Iterate via a pointer into the original packet list memory.
            // Copying MIDIPacket to the stack then calling MIDIPacketNext on &copy
            // crashes: MIDIPacketNext does pointer arithmetic from the copy's stack
            // address, not the list, producing an invalid pointer on the next .pointee.
            let raw = UnsafeMutableRawPointer(mutating: pktList)
                .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet) ?? 8)
            var pkt = raw.assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<Int(pktList.pointee.numPackets) {
                let n = Int(pkt.pointee.length)
                withUnsafeBytes(of: pkt.pointee.data) { self?.parseBytes(Array($0.prefix(n))) }
                pkt = MIDIPacketNext(pkt)
            }
        }
        scanForOP1()
    }

    // MARK: - Device discovery

    private func scanForOP1() {
        var otherNames: [String] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let dest = MIDIGetDestination(i)
            guard let name = midiName(dest) else { continue }
            if isOP1(name) {
                if destRef != dest {
                    destRef = dest
                    DispatchQueue.main.async { self.state = .connected(name) }
                }
                connectSource()
                return
            }
            // Skip known virtual/network endpoints — they're never real hardware.
            let lower = name.lowercased()
            let isVirtual = USBMidi.virtualEndpointNames.contains { lower.contains($0) }
            if !isVirtual { otherNames.append(name) }
        }
        // OP-1 not found — clear refs and report what we did find (if anything).
        srcRef = 0
        if destRef != 0 { destRef = 0 }
        let names = otherNames
        DispatchQueue.main.async {
            self.state = names.isEmpty ? .disconnected : .found(names)
        }
    }

    private func connectSource() {
        // Primary: entity-based discovery.
        // Once we have the destination endpoint, ask CoreMIDI which entity owns it,
        // then connect ALL source endpoints in that entity. This catches dedicated
        // clock ports whose display name may not contain "op-1".
        if destRef != 0 {
            var entity = MIDIEntityRef()
            if MIDIEndpointGetEntity(destRef, &entity) == noErr {
                let count = MIDIEntityGetNumberOfSources(entity)
                if count > 0 {
                    if srcRef != 0 { MIDIPortDisconnectSource(inPort, srcRef); srcRef = 0 }
                    for i in 0..<count {
                        let src = MIDIEntityGetSource(entity, i)
                        guard src != 0 else { continue }
                        MIDIPortConnectSource(inPort, src, nil)
                        if srcRef == 0 { srcRef = src }
                    }
                    return
                }
            }
        }
        // Fallback: name-based search (original behavior).
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard let name = midiName(src), isOP1(name) else { continue }
            if srcRef != src {
                if srcRef != 0 { MIDIPortDisconnectSource(inPort, srcRef) }
                srcRef = src
                MIDIPortConnectSource(inPort, src, nil)
            }
            return
        }
    }

    private func midiName(_ ep: MIDIEndpointRef) -> String? {
        var prop: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &prop) == noErr else { return nil }
        return prop?.takeRetainedValue() as String?
    }

    private func isOP1(_ name: String) -> Bool {
        let l = name.lowercased()
        return l.contains("op-1") || l.contains("op1")
    }

    // MARK: - Send

    func send(_ bytes: [UInt8]) {
        guard destRef != 0, outPort != 0 else { return }
        var list = MIDIPacketList()
        var pkt  = MIDIPacketListInit(&list)
        pkt = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, pkt, 0, bytes.count, bytes)
        MIDISend(outPort, destRef, &list)
    }

    // MARK: - Incoming MIDI parser (raw bytes, same logic as BLEMidi)

    private func parseBytes(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0xF8: onClock?(); i += 1
            case 0xFA: onStart?(); i += 1
            case 0xFB:             i += 1
            case 0xFC: onStop?();  i += 1
            default:
                guard b & 0x80 != 0 else { i += 1; continue }
                let ch = Int(b & 0x0F)
                switch b & 0xF0 {
                case 0xB0 where i + 2 < bytes.count:
                    onCC?(ch, Int(bytes[i + 1]), Int(bytes[i + 2])); i += 3
                case 0x80, 0x90, 0xA0, 0xE0:
                    i += i + 2 < bytes.count ? 3 : 1
                case 0xC0, 0xD0:
                    i += i + 1 < bytes.count ? 2 : 1
                default:
                    i += 1
                }
            }
        }
    }
}
