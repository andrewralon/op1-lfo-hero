import CoreMIDI
import Foundation

// Listen-only. Prints the incoming MIDI clock rate once a second.
//
// In `sync` mode the TP-7's clock is derived from tape speed, so this reads out playback rate
// live while the device is driven from its own buttons. Sends nothing, so nothing it reports can
// be an artefact of this tool. This is the instrument that produced the 1x ground truth:
// the device's own reverse measured 44.06 ticks/s over 30 s.
//
//   ./clockrate <device> [seconds]
//
// 44 ticks/s = 110 BPM = 1x playback.
//
// Caveats that cost real time when they were not understood:
//   - the rate is UNSIGNED: it measures speed, never direction.
//   - the device emits no clock at all while the tape is stopped, so 0 means "stopped", not
//     "the motor is not turning".
//   - one-second windows alternate between ~43.8 and ~44.8 as ticks land on window boundaries.
//     Only the average over 10 s or more is meaningful.

func str(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &s) == noErr, let v = s else { return "" }
    return v.takeRetainedValue() as String
}

// Unplugging leaves a stale endpoint with the same name behind; binding to it looks exactly like
// a device that has stopped transmitting.
func isOffline(_ e: MIDIEndpointRef) -> Bool {
    var v: Int32 = 0
    guard MIDIObjectGetIntegerProperty(e, kMIDIPropertyOffline, &v) == noErr else { return false }
    return v != 0
}

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TP-7"
let seconds = args.count > 2 ? Int(args[2])! : 30

var src: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) {
        src = e; break
    }
}
guard src != 0 else { print("NO SOURCE named \(target)"); exit(1) }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func tick() { lock.lock(); n += 1; lock.unlock() }
    func drain() -> Int { lock.lock(); defer { n = 0; lock.unlock() }; return n }
}
let c = Counter()

var client = MIDIClientRef(); MIDIClientCreate("clockrate" as CFString, nil, nil, &client)
var port = MIDIPortRef()
MIDIInputPortCreateWithBlock(client, "in" as CFString, &port) { pkts, _ in
    for p in pkts.unsafeSequence() {
        let mp = UnsafeMutableRawPointer(mutating: p).advanced(by: 10).assumingMemoryBound(to: UInt8.self)
        for i in 0..<Int(p.pointee.length) where mp[i] == 0xF8 { c.tick() }
    }
}
MIDIPortConnectSource(port, src, nil)

print("listening to '\(str(src, kMIDIPropertyDisplayName))' for \(seconds)s — drive the tape from the device")
print("44 ticks/s = 1x.  (idle = tape stopped, or not in `sync` mode)")
fflush(stdout)

var total = 0.0, samples = 0
for s in 1...seconds {
    let t0 = Date()
    Thread.sleep(forTimeInterval: 1.0)
    let rate = Double(c.drain()) / Date().timeIntervalSince(t0)
    if rate > 1 { total += rate; samples += 1 }
    print(String(format: "%3ds  %6.2f ticks/s  x%.2f  %@",
                 s, rate, rate / 44.0,
                 rate < 1 ? "(idle)" : String(repeating: "#", count: min(60, Int(rate / 2)))))
    fflush(stdout)
}

if samples > 0 {
    let avg = total / Double(samples)
    print("")
    print(String(format: "average over %d rolling seconds: %.2f ticks/s  = x%.3f", samples, avg, avg / 44.0))
}
