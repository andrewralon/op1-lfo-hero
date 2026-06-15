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

    // Callbacks — invoked on the BLE queue (background thread)
    var onClock:    (() -> Void)?
    var onStart:    (() -> Void)?
    var onStop:     (() -> Void)?
    var onCC:       ((Int, Int, Int) -> Void)?   // channel, cc, value

    private var central: CBCentralManager!
    private var midiChar: CBCharacteristic?
    private var peripheral: CBPeripheral?
    private let queue = DispatchQueue(label: "ble.midi", qos: .userInteractive)
    private var scanTimeout: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Public API

    func startScan() {
        scanTimeout?.cancel()
        DispatchQueue.main.async { self.discovered.removeAll() }
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async { self.state = .scanning }
        central.scanForPeripherals(withServices: [bleMIDIServiceUUID])
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Keep scanning — auto-connect still works if an OP-1 appears later.
            // Just change the label so the user sees a clear status instead of "scanning…" forever.
            DispatchQueue.main.async {
                if case .scanning = self.state { self.state = .notFound }
            }
        }
        scanTimeout = timeout
        queue.asyncAfter(deadline: .now() + 5.0, execute: timeout)
    }

    func connect(_ p: CBPeripheral) {
        scanTimeout?.cancel()
        central.stopScan()
        peripheral = p
        DispatchQueue.main.async { self.state = .connecting(p.name ?? "device") }
        central.connect(p)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    /// Wraps raw MIDI bytes in a minimal BLE MIDI single-packet and writes without response.
    func send(_ bytes: [UInt8]) {
        guard let c = midiChar, let p = peripheral, p.state == .connected else { return }
        var pkt: [UInt8] = [0x80, 0x80]
        pkt.append(contentsOf: bytes)
        p.writeValue(Data(pkt), for: c, type: .withoutResponse)
    }

    // MARK: - BLE MIDI packet parser

    private func parse(_ data: Data) {
        guard data.count >= 2 else { return }
        var i = 1  // skip header byte; timestamp byte follows per-message below

        while i < data.count {
            let b = data[i]

            // Single-byte real-time messages (may appear mid-packet)
            switch b {
            case 0xF8: onClock?(); i += 1; continue
            case 0xFA: onStart?(); i += 1; continue
            case 0xFB:             i += 1; continue  // Continue
            case 0xFC: onStop?();  i += 1; continue
            default: break
            }

            // BLE MIDI timestamps have MSB=1 and appear before each status byte
            if b & 0x80 != 0 {
                // Could be a per-message timestamp — peek at next byte
                if i + 1 < data.count && data[i + 1] & 0x80 != 0 {
                    i += 1  // skip timestamp, fall through to parse status
                    continue
                }
            }

            guard b & 0x80 != 0 else { i += 1; continue }  // unexpected data byte

            let ch = Int(b & 0x0F)
            switch b & 0xF0 {
            case 0xB0:
                guard i + 2 < data.count else { i += 1; continue }
                onCC?(ch, Int(data[i + 1]), Int(data[i + 2]))
                i += 3
            case 0x80, 0x90, 0xA0, 0xE0:
                i += i + 2 < data.count ? 3 : 1
            case 0xC0, 0xD0:
                i += i + 1 < data.count ? 2 : 1
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
        guard !discovered.contains(p) else { return }
        DispatchQueue.main.async { self.discovered.append(p) }
        // Auto-connect to first OP-1 found
        if (p.name ?? "").lowercased().contains("op-1") {
            connect(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        p.discoverServices([bleMIDIServiceUUID])
        DispatchQueue.main.async { self.state = .connected(p.name ?? "device") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        midiChar = nil
        DispatchQueue.main.async {
            self.state = .disconnected(p.name ?? "device")
            self.peripheral = nil
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { self.startScan() }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.state = .scanning }
        startScan()
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
