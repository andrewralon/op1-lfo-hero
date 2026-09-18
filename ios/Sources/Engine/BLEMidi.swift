import Combine
import CoreBluetooth
import Foundation

private let bleMIDIServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
private let bleMIDICharUUID    = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

final class BLEMidi: NSObject, ObservableObject {

    enum State: Equatable {
        case off, scanning, connecting(String), connected(String), disconnected(String), notFound

        var label: String {
            switch self {
            case .off:                 return "bluetooth off"
            case .scanning:            return "scanning…"
            case .connecting(let n):   return "connecting to \(n)…"
            case .connected(let n):    return "\(n) (ble)"
            case .disconnected(let n): return "\(n) disconnected"
            case .notFound:            return "no device found"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published var state: State = .scanning
    @Published var discovered: [CBPeripheral] = []
    /// Profile id matched from the connected peripheral's name, nil when nothing matched.
    @Published var matchedProfileId: String?

    // Callbacks — invoked on the BLE queue (background thread)
    var onClock:    (() -> Void)?
    var onStart:    (() -> Void)?
    var onStop:     (() -> Void)?
    var onCC:       ((Int, Int, Int) -> Void)?   // channel, cc, value

    /// Launch/foreground scan: a single visible window, long enough for someone to walk over,
    /// power on a TE device and put it into BLE mode. If nothing is found by then, scanning
    /// stops and the UI shows "not found" rather than retrying forever unseen in the background.
    private static let launchScanTimeout: TimeInterval = 60.0
    /// Per-attempt connect handshake timeout — unrelated to how long scanning itself runs.
    private static let connectHandshakeTimeout: TimeInterval = 5.0

    private var central: CBCentralManager!
    private var midiChar: CBCharacteristic?
    private var peripheral: CBPeripheral?
    private let queue = DispatchQueue(label: "ble.midi", qos: .userInteractive)
    private var scanTimeout: DispatchWorkItem?
    private var connectTimeout: DispatchWorkItem?
    private var discoveredIds = Set<UUID>()   // guarded by `queue`
    /// True while the connection menu is open: scanning restarts on its own timeout forever
    /// and never surfaces `.notFound`, instead of giving up after the launch window.
    private var continuousScan = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Public API

    /// Starts (or restarts) scanning. `continuous: true` is for the open connection menu:
    /// scanning keeps going with no visible "not found" flicker for as long as the caller keeps
    /// it continuous. `continuous: false` (app launch/foreground) gives up after a single
    /// `launchScanTimeout` window and shows "not found" instead of retrying silently forever.
    func startScan(continuous: Bool = false) {
        let isRestart = continuous && continuousScan
        continuousScan = continuous
        scanTimeout?.cancel()
        if !isRestart {
            // A fresh scan (not an internal continuous-mode restart) clears prior results.
            // Restarting the window under continuous mode keeps `discovered` as-is so the
            // picker's list doesn't flicker empty every cycle while the menu is open.
            discoveredIds.removeAll()                          // sync on queue — cleared before scan starts
            DispatchQueue.main.async { self.discovered.removeAll() }
        }
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async { self.state = .scanning }
        central.scanForPeripherals(withServices: [bleMIDIServiceUUID])
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.continuousScan {
                // Menu still open — restart the window instead of giving up or flickering.
                self.startScan(continuous: true)
                return
            }
            self.central.stopScan()
            DispatchQueue.main.async {
                if case .scanning = self.state { self.state = .notFound }
            }
        }
        scanTimeout = timeout
        queue.asyncAfter(deadline: .now() + BLEMidi.launchScanTimeout, execute: timeout)
    }

    func connect(_ p: CBPeripheral) {
        scanTimeout?.cancel()
        connectTimeout?.cancel()
        central.stopScan()
        peripheral = p
        DispatchQueue.main.async { self.state = .connecting(p.name ?? "device") }
        central.connect(p)
        // CoreBluetooth connect() has no timeout — if the OP-1 goes away mid-handshake
        // (e.g. BLE restarted on the device), cancel and rescan so we pick it up fresh.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
            self.startScan(continuous: self.continuousScan)
        }
        connectTimeout = timeout
        queue.asyncAfter(deadline: .now() + BLEMidi.connectHandshakeTimeout, execute: timeout)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    /// Wraps raw MIDI bytes in a BLE MIDI packet and writes without response.
    func send(_ bytes: [UInt8]) {
        guard let c = midiChar, let p = peripheral, p.state == .connected else { return }
        p.writeValue(Data(BleMidiPacket.frame(bytes)), for: c, type: .withoutResponse)
    }

    // MARK: - BLE MIDI packet parser

    /// Parse one BLE-MIDI packet.
    ///
    /// Layout: a header byte, then for each message a **timestamp byte** followed by the MIDI
    /// bytes. Both timestamp and status bytes have the high bit set, so they can only be told
    /// apart by position — a timestamp always comes first, and exactly one precedes each message.
    ///
    /// Consuming that timestamp *before* looking at the byte is essential. Timestamps span
    /// 0x80-0xFF, which includes 0xF8, 0xFA and 0xFC — so an earlier version that tested for
    /// real-time messages first read ordinary timestamps as clock, start and stop. A stream of
    /// CC from a TX-6 injected phantom clock ticks that all landed in the same packet, and the
    /// app computed a BPM from microsecond intervals (observed: 640000 BPM).
    private func parse(_ data: Data) {
        BleMidiPacket.parse(data, onClock: onClock, onStart: onStart, onStop: onStop, onCC: onCC)
    }
}

/// BLE-MIDI packet framing and parsing, split out so it can be tested without CoreBluetooth.
enum BleMidiPacket {

    /// Wrap MIDI bytes in a BLE-MIDI packet: header, timestamp, then the message.
    ///
    /// The timestamp is a **13-bit millisecond counter** — the high 6 bits ride in the header,
    /// the low 7 in the timestamp byte. It is not decoration: the receiver uses it to recover
    /// when each message was meant to happen, because BLE delivers packets in bursts with
    /// unpredictable latency.
    ///
    /// This used to send a constant `[0x80, 0x80]`, i.e. "everything happened at time zero". A
    /// TX-6 receiving the app's 24 PPQN clock therefore saw every tick as simultaneous and
    /// displayed **640000 BPM** on its own screen.
    static func frame(_ bytes: [UInt8], timestampMs: Int? = nil) -> [UInt8] {
        let ms = UInt16(truncatingIfNeeded: timestampMs ?? Int(Date().timeIntervalSince1970 * 1000)) & 0x1FFF
        var pkt: [UInt8] = [UInt8(0x80 | (ms >> 7)), UInt8(0x80 | (ms & 0x7F))]
        pkt.append(contentsOf: bytes)
        return pkt
    }

    static func parse(_ data: Data,
                      onClock: (() -> Void)?,
                      onStart: (() -> Void)?,
                      onStop: (() -> Void)?,
                      onCC: ((Int, Int, Int) -> Void)?) {
        guard data.count >= 3 else { return }   // header + timestamp + at least one status
        var i = 1                               // skip the header
        var status: UInt8 = 0                   // running status, survives between messages

        while i < data.count {
            // Exactly one timestamp byte precedes every message, including real-time ones.
            if data[i] & 0x80 != 0 {
                i += 1
                guard i < data.count else { return }
            }

            var b = data[i]
            if b & 0x80 != 0 {
                // System real-time: one byte, no data, and it does not disturb running status.
                if b >= 0xF8 {
                    switch b {
                    case 0xF8: onClock?()
                    case 0xFA: onStart?()
                    case 0xFC: onStop?()
                    default: break              // 0xFB continue, 0xFE sensing, 0xFF reset
                    }
                    i += 1
                    continue
                }
                // System common has no running status and is not used here — resync on it.
                if b >= 0xF0 { status = 0; i += 1; continue }

                status = b
                i += 1
                guard i < data.count else { return }
                b = data[i]
            }

            // `b` is the first data byte of `status` (possibly running status).
            guard status != 0 else { i += 1; continue }
            switch status & 0xF0 {
            case 0xB0:
                guard i + 1 < data.count else { return }
                onCC?(Int(status & 0x0F), Int(b), Int(data[i + 1]))
                i += 2
            case 0x80, 0x90, 0xA0, 0xE0:
                i += 2
            case 0xC0, 0xD0:
                i += 1
            default:
                i += 1
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEMidi: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            startScan()
        } else {
            DispatchQueue.main.async { self.state = .off }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        scanTimeout?.cancel()
        guard discoveredIds.insert(p.identifier).inserted else { return }
        DispatchQueue.main.async { self.discovered.append(p) }
        // Auto-connect to the first known TE device found. Everything discovered is still
        // listed in `discovered`, so an unrecognised peripheral can be picked by hand.
        // `matchedProfileId` (and therefore app layout) is not set here — only a name match
        // is known at this point, not an actual connection. It is set in `didConnect`.
        if DeviceRegistry.profile(forEndpointName: p.name ?? "") != nil {
            connect(p)
        }
    }

    /// Removes a peripheral from the picker list — called on disconnect/failure so the
    /// connection menu doesn't keep showing devices that are no longer reachable.
    private func forgetDiscovered(_ p: CBPeripheral) {
        discoveredIds.remove(p.identifier)
        DispatchQueue.main.async { self.discovered.removeAll { $0.identifier == p.identifier } }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        connectTimeout?.cancel()
        p.delegate = self
        p.discoverServices([bleMIDIServiceUUID])
        // The device is actually connected now — safe to commit the profile match, which
        // drives the app's layout (track count, etc).
        if let profile = DeviceRegistry.profile(forEndpointName: p.name ?? "") {
            DispatchQueue.main.async { self.matchedProfileId = profile.id }
        }
        DispatchQueue.main.async { self.state = .connected(p.name ?? "device") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        midiChar = nil
        peripheral = nil
        forgetDiscovered(p)
        DispatchQueue.main.async {
            self.state = .disconnected(p.name ?? "device")
            self.matchedProfileId = nil
        }
        startScan(continuous: continuousScan)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        forgetDiscovered(p)
        DispatchQueue.main.async { self.state = .scanning }
        startScan(continuous: continuousScan)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEMidi: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for svc in p.services ?? [] where svc.uuid == bleMIDIServiceUUID {
            p.discoverCharacteristics([bleMIDICharUUID], for: svc)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
        for c in svc.characteristics ?? [] where c.uuid == bleMIDICharUUID {
            midiChar = c
            p.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let data = c.value { parse(data) }
    }
}
