import QuartzCore
import Combine
import CoreBluetooth
import Foundation

private let bleMIDIServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
private let bleMIDICharUUID    = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

/// The device picker's Bluetooth list, as pure rules (no CoreBluetooth), so they can be tested as a state
/// machine. `BLEMidi` only feeds it events and publishes what it holds. The rules:
/// - the pinned device (connected or connecting) is always a row: it stops advertising once linked, so
///   nothing could ever put it back;
/// - a fresh scan empties the list except for that row;
/// - an unpinned device (disconnect, failed connect) stays a row until it has been silent for
///   `staleAfter`, counted from the unpin plus a grace so it has time to advertise again;
/// - every other device drops after `staleAfter` seconds without an advertisement.
struct BleDeviceList {
    private(set) var order: [UUID] = []
    private var seen: [UUID: Double] = [:]
    private(set) var pinned: UUID?

    /// An advertisement. True if the device is new to the list.
    mutating func sawAdvertisement(_ id: UUID, now: Double) -> Bool {
        seen[id] = now
        guard !order.contains(id) else { return false }
        order.append(id)
        return true
    }

    /// The device is connecting or connected: it is a row, and stays one.
    mutating func pin(_ id: UUID, now: Double) {
        pinned = id
        seen[id] = now
        if !order.contains(id) { order.append(id) }
    }

    /// The device is no longer connecting or connected. It stays listed for `grace` seconds beyond the usual
    /// silence window; it then drops unless it has advertised again.
    mutating func unpin(_ id: UUID, now: Double, grace: Double) {
        if pinned == id { pinned = nil }
        seen[id] = now + grace
        if !order.contains(id) { order.append(id) }
    }

    /// A new scan: forget everything but the pinned device.
    mutating func startFreshScan() {
        let keep = pinned
        order = order.filter { $0 == keep }
        seen = seen.filter { $0.key == keep }
    }

    /// Drop devices that have gone quiet. Returns the ones dropped.
    @discardableResult
    mutating func removeStale(now: Double, staleAfter: Double) -> [UUID] {
        let keep = Set([pinned].compactMap { $0 })
        let gone = BLEMidi.staleIds(lastSeen: seen, now: now, staleAfter: staleAfter, keep: keep)
        guard !gone.isEmpty else { return [] }
        order.removeAll { gone.contains($0) }
        for id in gone { seen.removeValue(forKey: id) }
        return gone
    }
}

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
            case .notFound:            return "no device found; tap to connect"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var isConnecting: Bool {
            if case .connecting = self { return true }
            return false
        }
    }

    @Published var state: State = .scanning
    @Published var discovered: [CBPeripheral] = []
    /// Profile id matched from the connected peripheral's name, nil when nothing matched.
    @Published var matchedProfileId: String?
    /// The peripheral the link is actually up with. The device list matches on this, not on the
    /// name: CoreBluetooth can report a different name before and after connecting.
    @Published var connectedPeripheralID: UUID?
    /// Asked before connecting to a known device on discovery. The router answers false while
    /// another transport already has a connection.
    var shouldAutoConnect: () -> Bool = { true }

    // Callbacks — invoked on the BLE queue (background thread)
    var onClock:    (() -> Void)?
    var onStart:    (() -> Void)?
    var onContinue: (() -> Void)?
    /// The sender's timestamp of a clock tick (13-bit ms), delivered just before `onClock`.
    var onClockStamp: ((Int) -> Void)?
    var onStop:     (() -> Void)?
    var onCC:       ((Int, Int, Int) -> Void)?   // channel, cc, value

    /// Launch/foreground scan: a single visible window, long enough for someone to walk over,
    /// power on a TE device and put it into BLE mode. If nothing is found by then, scanning
    /// stops and the UI shows "not found" rather than retrying forever unseen in the background.
    private static let launchScanTimeout: TimeInterval = 60.0
    /// What to do about reconnecting to a known device at the start of a scan.
    enum ReconnectPlan: Equatable { case none, connectNow(UUID), pending(UUID) }
    /// A device already linked at the OS level does not advertise, so a scan can never find it: connect to
    /// it directly. Otherwise ask the system to connect to the remembered device whenever it appears: a
    /// pending connect needs no scan and no timeout. Nothing at all when the user disconnected on purpose
    /// or another transport is active.
    static func reconnectPlan(osConnected: [UUID], remembered: UUID?, suppressed: Bool,
                              mayAutoConnect: Bool, alreadyPending: Bool) -> ReconnectPlan {
        guard !suppressed, mayAutoConnect else { return .none }
        if let id = osConnected.first(where: { $0 == remembered }) ?? osConnected.first { return .connectNow(id) }
        guard let remembered, !alreadyPending else { return .none }
        return .pending(remembered)
    }
    private static let lastPeripheralKey = "ble.lastPeripheralID"
    /// Set when the user pressed disconnect: nothing reconnects by itself until they pick a device.
    private var suppressAutoConnect = false          // guarded by `queue`
    /// A connect issued for the remembered device that has not completed (guarded by `queue`).
    private var pendingReconnect: CBPeripheral?

    /// Per-attempt connect handshake timeout — unrelated to how long scanning itself runs.
    private static let connectHandshakeTimeout: TimeInterval = 5.0

    private var central: CBCentralManager!
    private var midiChar: CBCharacteristic?
    private var peripheral: CBPeripheral?
    private let queue = DispatchQueue(label: "ble.midi", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<Void>()
    private var onQueue: Bool { DispatchQueue.getSpecific(key: queueKey) != nil }
    private var scanTimeout: DispatchWorkItem?
    private var connectTimeout: DispatchWorkItem?
    /// When each listed peripheral was last seen advertising (guarded by `queue`). CoreBluetooth
    /// reports a device being found but never being lost, so "gone" has to be inferred from silence.
    private var list = BleDeviceList()                // guarded by `queue`
    private var known: [UUID: CBPeripheral] = [:]      // guarded by `queue`
    private var pruneTimer: DispatchSourceTimer?
    /// A listed device not seen for this long is dropped from the picker.
    static let staleAfter: Double = 2.0

    /// The listed devices that have gone quiet. Whatever is in `keep` (the connected or connecting
    /// peripheral, which stops advertising) is never stale.
    static func staleIds(lastSeen: [UUID: Double], now: Double, staleAfter: Double, keep: Set<UUID>) -> [UUID] {
        lastSeen.filter { !keep.contains($0.key) && now - $0.value > staleAfter }.map(\.key)
    }

    private func pruneStale() {
        if !list.removeStale(now: CACurrentMediaTime(), staleAfter: BLEMidi.staleAfter).isEmpty { publishList() }
    }

    /// Publishes the list to the UI, in the order it was found. Call on `queue`.
    private func publishList() {
        let items = list.order.compactMap { known[$0] }
        DispatchQueue.main.async { self.discovered = items }
    }

    /// While the picker is open (continuous scan), check once a second for devices that went quiet.
    private func startPruning() {
        guard pruneTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self, self.continuousScan else { return }
            self.pruneStale()
        }
        t.resume()
        pruneTimer = t
    }

    /// True while the connection menu is open: scanning restarts on its own timeout forever
    /// and never surfaces `.notFound`, instead of giving up after the launch window.
    private var continuousScan = false

    override init() {
        super.init()
        queue.setSpecific(key: queueKey, value: ())
        central = CBCentralManager(delegate: self, queue: queue)
    }

    /// What `startScan` does. While the link is up a scan must not touch the status or empty the list (see
    /// `startScan`), but the open picker still needs to see *other* devices, so a continuous scan runs
    /// "quietly"; a non-continuous one has nothing to do and stops any scan left from the picker.
    enum ScanPlan: Equatable { case normal, quiet, stop }
    static func scanPlan(linkIsUp: Bool, continuous: Bool) -> ScanPlan {
        guard linkIsUp else { return .normal }
        return continuous ? .quiet : .stop
    }

    /// Only a fresh normal scan empties the picker's list.
    static func clearsList(plan: ScanPlan, isRestart: Bool) -> Bool { plan == .normal && !isRestart }

    /// A device that just disconnected is kept listed this long (seconds, on top of `staleAfter`) so it has
    /// time to start advertising again; if it never does, it was not available and drops off.
    static let disconnectGrace: Double = 3.0

    // MARK: - Public API

    /// Starts (or restarts) scanning. `continuous: true` is for the open connection menu:
    /// scanning keeps going with no visible "not found" flicker for as long as the caller keeps
    /// it continuous. `continuous: false` (app launch/foreground) gives up after a single
    /// `launchScanTimeout` window and shows "not found" instead of retrying silently forever.
    func startScan(continuous: Bool = false) {
        // The picker's list and the scan state belong to `queue`; callers on the main thread hop onto it.
        guard onQueue else { queue.async { self.startScan(continuous: continuous) }; return }
        let isRestart = continuous && continuousScan
        continuousScan = continuous
        // Already linked: a normal scan would set the status to "scanning" and empty the device list,
        // and a connected peripheral may not advertise again to put either back — so a working
        // connection would look lost every time the device picker opens or closes. A quiet scan (picker
        // open) changes neither; it only lets other devices be found and listed.
        let plan = BLEMidi.scanPlan(linkIsUp: peripheral?.state == .connected, continuous: continuous)
        if plan == .stop {
            scanTimeout?.cancel()
            central.stopScan()
            return
        }
        scanTimeout?.cancel()
        if BLEMidi.clearsList(plan: plan, isRestart: isRestart) {
            // A fresh scan (not an internal continuous-mode restart) clears prior results.
            // Restarting the window under continuous mode keeps `discovered` as-is so the
            // picker's list doesn't flicker empty every cycle while the menu is open. A quiet scan (link
            // up) never clears: the connected device does not advertise, so it would not come back.
            list.startFreshScan()      // keeps the pinned (connecting/connected) device
            publishList()
        }
        guard central.state == .poweredOn else { return }
        if plan == .normal { reconnectRemembered() }
        if plan == .normal { DispatchQueue.main.async { self.state = .scanning } }
        // While the picker is open, ask for every advertisement, not just the first, so a device
        // that is switched off can be told apart from one that is still there.
        central.scanForPeripherals(withServices: [bleMIDIServiceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: continuous])
        if continuous { startPruning() }
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

    /// Tries the two ways of reaching a known device without waiting for it to advertise.
    private func reconnectRemembered() {
        guard peripheral == nil else { return }
        let osConnected = central.retrieveConnectedPeripherals(withServices: [bleMIDIServiceUUID])
            .filter { DeviceRegistry.profile(forEndpointName: $0.name ?? "") != nil }
        let remembered = UserDefaults.standard.string(forKey: BLEMidi.lastPeripheralKey).flatMap(UUID.init)
        switch BLEMidi.reconnectPlan(osConnected: osConnected.map(\.identifier), remembered: remembered,
                                     suppressed: suppressAutoConnect, mayAutoConnect: shouldAutoConnect(),
                                     alreadyPending: pendingReconnect != nil) {
        case .none: break
        case .connectNow(let id):
            if let p = osConnected.first(where: { $0.identifier == id }) { connectNow(p) }
        case .pending(let id):
            guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
            pendingReconnect = p
            known[p.identifier] = p
            central.connect(p)       // no timeout on purpose: the system completes it when the device appears
        }
    }

    /// A deliberate connection (a tap in the picker).
    func connect(_ p: CBPeripheral) {
        guard onQueue else { queue.async { self.connect(p) }; return }
        suppressAutoConnect = false
        connectNow(p)
    }

    private func connectNow(_ p: CBPeripheral) {
        scanTimeout?.cancel()
        if let pending = pendingReconnect, pending.identifier != p.identifier {
            central.cancelPeripheralConnection(pending)      // the user chose another device
            pendingReconnect = nil
        }
        connectTimeout?.cancel()
        central.stopScan()
        peripheral = p
        known[p.identifier] = p
        list.pin(p.identifier, now: CACurrentMediaTime())
        publishList()
        DispatchQueue.main.async { self.state = .connecting(p.name ?? "device") }
        central.connect(p)
        // CoreBluetooth connect() has no timeout — if the OP-1 goes away mid-handshake
        // (e.g. BLE restarted on the device), cancel and rescan so we pick it up fresh.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let p = self.peripheral {
                self.central.cancelPeripheralConnection(p)
                self.list.unpin(p.identifier, now: CACurrentMediaTime(), grace: 0)
                self.publishList()
            }
            self.startScan(continuous: self.continuousScan)
        }
        connectTimeout = timeout
        queue.asyncAfter(deadline: .now() + BLEMidi.connectHandshakeTimeout, execute: timeout)
    }

    /// A deliberate disconnect: the device is not grabbed again until the user picks one.
    func disconnect() {
        queue.async {
            self.suppressAutoConnect = true
            if let p = self.peripheral { self.central.cancelPeripheralConnection(p) }
            if let p = self.pendingReconnect { self.central.cancelPeripheralConnection(p); self.pendingReconnect = nil }
        }
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
        BleMidiPacket.parse(data, onClock: onClock, onStart: onStart, onStop: onStop,
                            onContinue: onContinue, onClockStamp: onClockStamp, onCC: onCC)
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
                      onContinue: (() -> Void)? = nil,
                      onClockStamp: ((Int) -> Void)? = nil,
                      onCC: ((Int, Int, Int) -> Void)?) {
        guard data.count >= 3 else { return }   // header + timestamp + at least one status
        var i = 1                               // skip the header
        var status: UInt8 = 0                   // running status, survives between messages
        let stampHigh = Int(data[0] & 0x3F) << 7    // the header carries the top 6 bits of the timestamp
        var stampMs = 0

        while i < data.count {
            // Exactly one timestamp byte precedes every message, including real-time ones.
            if data[i] & 0x80 != 0 {
                stampMs = stampHigh | Int(data[i] & 0x7F)   // this message's timestamp (13-bit ms)
                i += 1
                guard i < data.count else { return }
            }

            var b = data[i]
            if b & 0x80 != 0 {
                // System real-time: one byte, no data, and it does not disturb running status.
                if b >= 0xF8 {
                    switch b {
                    case 0xF8:
                        onClockStamp?(stampMs)
                        onClock?()
                    case 0xFA: onStart?()
                    case 0xFB: onContinue?()
                    case 0xFC: onStop?()
                    default: break              // 0xFE sensing, 0xFF reset
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
        // The launch scan's deadline is fixed from when it started: discovering a device lists it but
        // does not extend or cancel the scan.
        known[p.identifier] = p
        guard list.sawAdvertisement(p.identifier, now: CACurrentMediaTime()) else { return }
        publishList()
        // Auto-connect to the first known TE device found. Everything discovered is still
        // listed in `discovered`, so an unrecognised peripheral can be picked by hand.
        // `matchedProfileId` (and therefore app layout) is not set here — only a name match
        // is known at this point, not an actual connection. It is set in `didConnect`.
        // Only when nothing else is connected: a device found while another is active is listed in
        // the picker and left for the user to choose, never connected over the top.
        if DeviceRegistry.profile(forEndpointName: p.name ?? "") != nil, shouldAutoConnect(), !suppressAutoConnect {
            connectNow(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        // A pending reconnect can complete long after it was issued: only take it if nothing else has the
        // link, otherwise let it go.
        if peripheral == nil, !shouldAutoConnect() { central.cancelPeripheralConnection(p); pendingReconnect = nil; return }
        connectTimeout?.cancel()
        pendingReconnect = nil
        peripheral = p
        known[p.identifier] = p
        list.pin(p.identifier, now: CACurrentMediaTime())
        publishList()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: BLEMidi.lastPeripheralKey)
        // Connected: the scan has done its job. (The open picker keeps its quiet scan to list other devices.)
        scanTimeout?.cancel()
        if !continuousScan { central.stopScan() }
        p.delegate = self
        p.discoverServices([bleMIDIServiceUUID])
        // The device is actually connected now — safe to commit the profile match, which
        // drives the app's layout (track count, etc).
        if let profile = DeviceRegistry.profile(forEndpointName: p.name ?? "") {
            DispatchQueue.main.async { self.matchedProfileId = profile.id }
        }
        DispatchQueue.main.async {
            self.connectedPeripheralID = p.identifier
            self.state = .connected(p.name ?? "device")
        }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        midiChar = nil
        peripheral = nil
        if pendingReconnect?.identifier == p.identifier { pendingReconnect = nil }
        // Still listed: a disconnect says nothing about whether the device is still there. It drops off
        // by the usual silence rule, with a grace period for it to start advertising again.
        known[p.identifier] = p
        list.unpin(p.identifier, now: CACurrentMediaTime(), grace: BLEMidi.disconnectGrace)
        publishList()
        DispatchQueue.main.async {
            self.state = .disconnected(p.name ?? "device")
            self.connectedPeripheralID = nil
            self.matchedProfileId = nil
        }
        startScan(continuous: continuousScan)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if pendingReconnect?.identifier == p.identifier { pendingReconnect = nil }
        list.unpin(p.identifier, now: CACurrentMediaTime(), grace: 0)
        publishList()
        DispatchQueue.main.async {
            self.connectedPeripheralID = nil
            self.state = .scanning
        }
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
