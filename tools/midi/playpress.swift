import CoreMIDI
import Foundation

// End-to-end confirmation: replays the exact byte sequences ClockEngine.play() emits for three
// consecutive presses, and measures the resulting tape speed after each.
//
// The bytes here are transcribed from ClockEngine/DeviceProfiles rather than computed, so if the
// app's logic and this test ever disagree, this fails instead of quietly agreeing.
//
//   press 1  FB                    -> forward at the device's own rate
//   press 2  B0 12 38, E0 64 4B    -> reverse: CC 18 = 56, bend 9700
//   press 3  E0 00 40, B0 12 40, FB-> forward: release trim, release CC 18, continue
//
// Expect ~44 ticks/s in all three phases.

func str(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &s) == noErr, let v = s else { return "" }
    return v.takeRetainedValue() as String
}

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TP-7"
var src: MIDIEndpointRef = 0, dest: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()) { src = e; break }
}
for i in 0..<MIDIGetNumberOfDestinations() {
    let e = MIDIGetDestination(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()) { dest = e; break }
}
guard src != 0, dest != 0 else { print("NO TP-7 endpoint"); exit(1) }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func tick() { lock.lock(); n += 1; lock.unlock() }
    func drain() -> Int { lock.lock(); defer { n = 0; lock.unlock() }; return n }
}
let c = Counter()

var client = MIDIClientRef(); MIDIClientCreate("playpress" as CFString, nil, nil, &client)
var inPort = MIDIPortRef()
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
    print("    -> " + b.map { String(format: "%02X", $0) }.joined(separator: " ")); fflush(stdout)
}

/// Settle the motor, then average over a long enough window that tick-boundary aliasing
/// (~43.8 vs ~44.8 in one-second windows) washes out.
func measure(_ label: String) -> Double {
    Thread.sleep(forTimeInterval: 2.0)
    _ = c.drain()
    let t0 = Date()
    Thread.sleep(forTimeInterval: 8.0)
    let rate = Double(c.drain()) / Date().timeIntervalSince(t0)
    print(String(format: "  %@: %.2f ticks/s  x%.3f", label, rate, rate / 44.0)); fflush(stdout)
    return rate
}

print("replaying ClockEngine.play() x3 — tape stopped, mid-file. starting in 5s"); fflush(stdout)
Thread.sleep(forTimeInterval: 5)

print("press 1 — play")
send([0xFB])
let fwd1 = measure("forward ")

print("press 2 — reverse")
send([0xB0, 0x12, 0x38])          // CC 18 = 56
send([0xE0, 0x64, 0x4B])          // bend 9700
let rev = measure("reverse ")

print("press 3 — forward again")
send([0xE0, 0x00, 0x40])          // bend -> centre
send([0xB0, 0x12, 0x40])          // CC 18 -> 64
send([0xFB])
let fwd2 = measure("forward ")

print("stopping")
send([0xB0, 0x12, 0x40])
send([0xFC])

let fwd = (fwd1 + fwd2) / 2
print("")
print(String(format: "forward avg : %.2f ticks/s", fwd))
print(String(format: "reverse     : %.2f ticks/s", rev))
print(String(format: "difference  : %+.2f%%", (rev / fwd - 1) * 100))
print(abs(rev / fwd - 1) < 0.02
      ? "=> PASS: reverse matches forward within 2%."
      : "=> FAIL: reverse does not match forward.")
