import CoreMIDI
import Foundation

// Does sending clock TO the TP-7 stop it sending clock back?
//
// The app forces itself to be clock master for this device (`canBeClockMaster: false` in the
// profile) and streams 24 PPQN at it. If the device goes quiet when slaved, then
// `ClockEngine.deviceIsRolling` — which detects a hand-started tape from incoming ticks — can
// never fire while the app is running, however correct the code is.
//
//   ./clocksuppress <device> [bpm]
//
// Phase 1 listens without sending, to confirm the device is transmitting at all.
// Phase 2 sends clock while still listening. A drop to zero is suppression.

func str(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &s) == noErr, let v = s else { return "" }
    return v.takeRetainedValue() as String
}
func isOffline(_ e: MIDIEndpointRef) -> Bool {
    var v: Int32 = 0
    guard MIDIObjectGetIntegerProperty(e, kMIDIPropertyOffline, &v) == noErr else { return false }
    return v != 0
}

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TP-7"
let bpm = args.count > 2 ? Double(args[2])! : 120

var src: MIDIEndpointRef = 0, dest: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) { src = e; break }
}
for i in 0..<MIDIGetNumberOfDestinations() {
    let e = MIDIGetDestination(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) { dest = e; break }
}
guard src != 0, dest != 0 else { print("NO TP-7 endpoint"); exit(1) }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func tick() { lock.lock(); n += 1; lock.unlock() }
    func drain() -> Int { lock.lock(); defer { n = 0; lock.unlock() }; return n }
}
let c = Counter()

var client = MIDIClientRef(); MIDIClientCreate("suppress" as CFString, nil, nil, &client)
var inPort = MIDIPortRef()
// Our own clock goes out on a destination endpoint and never comes back on the source, so
// nothing counted here can be our own traffic.
MIDIInputPortCreateWithBlock(client, "in" as CFString, &inPort) { pkts, _ in
    for p in pkts.unsafeSequence() {
        let mp = UnsafeMutableRawPointer(mutating: p).advanced(by: 10).assumingMemoryBound(to: UInt8.self)
        for i in 0..<Int(p.pointee.length) where mp[i] == 0xF8 { c.tick() }
    }
}
MIDIPortConnectSource(inPort, src, nil)

var outPort = MIDIPortRef(); MIDIOutputPortCreate(client, "out" as CFString, &outPort)
func send(_ b: [UInt8]) {
    var pkt = MIDIPacketList()
    let p = MIDIPacketListInit(&pkt)
    _ = MIDIPacketListAdd(&pkt, 1024, p, 0, b.count, b)
    MIDISend(outPort, dest, &pkt)
}

print("tape must be ROLLING in `sync` mode. sending nothing yet.")
print("--- phase 1: listen only (6s) ---"); fflush(stdout)
var phase1: [Int] = []
for s in 1...6 {
    Thread.sleep(forTimeInterval: 1.0)
    let n = c.drain(); phase1.append(n)
    print(String(format: "  %ds  %3d ticks", s, n)); fflush(stdout)
}

print("--- phase 2: now streaming OUR clock at \(Int(bpm)) BPM (8s) ---"); fflush(stdout)
let interval = 60.0 / (bpm * 24.0)
let stop = DispatchQueue(label: "clk")
var running = true
stop.async {
    while running { send([0xF8]); Thread.sleep(forTimeInterval: interval) }
}
var phase2: [Int] = []
for s in 1...8 {
    Thread.sleep(forTimeInterval: 1.0)
    let n = c.drain(); phase2.append(n)
    print(String(format: "  %ds  %3d ticks", s, n)); fflush(stdout)
}
running = false
Thread.sleep(forTimeInterval: 0.3)

let a = phase1.reduce(0, +) / max(1, phase1.count)
// Skip the first second of phase 2: the device may take a moment to react.
let b = phase2.dropFirst().reduce(0, +) / max(1, phase2.count - 1)
print("")
print("listening only     : \(a) ticks/s")
print("while we send clock: \(b) ticks/s")
if a < 1 {
    print("=> the device was not transmitting even in phase 1 — check the midi mode is `sync`")
    print("   and that the tape was rolling. Nothing can be concluded about suppression.")
} else if b < a / 2 {
    print("=> SUPPRESSED. Being slaved stops the TP-7 transmitting, so deviceIsRolling cannot")
    print("   fire while the app is clock master. The app must slave to the TP-7 instead.")
} else {
    print("=> NOT suppressed. The device keeps transmitting while slaved, so deviceIsRolling")
    print("   should work — the first-press failure has another cause.")
}
