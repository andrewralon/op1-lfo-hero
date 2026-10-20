import CoreMIDI
import Foundation

// Streams the TP-7's wheel (CC 30) live, to settle how it encodes direction.
//
// notes/RESEARCH.md records CC 30 as "a relative encoder whose value is rotation speed", from
// seeing a steady 1-2 during forward playback. That is what a *signed* encoder looks like if you
// only ever watch one direction: 1..63 are small positive steps and 65..127 are negatives in
// two's complement (127 = -1, 126 = -2). This prints both readings side by side so one spin
// settles it.
//
//   ./wheel <device> [seconds]
//
// The TP-7 only transmits CC 30 in `ctrl` mode — which also refuses incoming MIDI and stops
// playback, so this cannot be used to read direction while the app is driving the device.

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
let seconds = args.count > 2 ? Double(args[2])! : 20

var src: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) {
        src = e; break
    }
}
guard src != 0 else { print("NO SOURCE named \(target)"); exit(1) }

final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var vals: [Int] = []
    func add(_ v: Int) { lock.lock(); vals.append(v); lock.unlock() }
    func drain() -> [Int] { lock.lock(); defer { vals = []; lock.unlock() }; return vals }
}
let log = Log()

var client = MIDIClientRef(); MIDIClientCreate("wheel" as CFString, nil, nil, &client)
var port = MIDIPortRef()
MIDIInputPortCreateWithBlock(client, "in" as CFString, &port) { pkts, _ in
    for p in pkts.unsafeSequence() {
        let mp = UnsafeMutableRawPointer(mutating: p).advanced(by: 10).assumingMemoryBound(to: UInt8.self)
        var bytes: [UInt8] = []
        for i in 0..<Int(p.pointee.length) { bytes.append(mp[i]) }
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0xF2 { i += 3 }
            else if b >= 0xF0 { i += 1 }
            else if b & 0xF0 == 0xB0, i + 2 < bytes.count {
                if bytes[i + 1] == 30 { log.add(Int(bytes[i + 2])) }
                i += 3
            } else if b & 0xF0 == 0xE0 || b & 0xF0 == 0x90 || b & 0xF0 == 0x80 { i += 3 }
            else { i += 1 }
        }
    }
}
MIDIPortConnectSource(port, src, nil)

print("listening to '\(str(src, kMIDIPropertyDisplayName))' for \(Int(seconds))s — `ctrl` mode required")
print("spin the reel ONE WAY for the first half, the OTHER WAY for the second half.")
print("")
print("If signed: one direction gives 1..63, the other 127..65 (127 = -1).")
print("If unsigned speed: both directions give the same range.")
print("")
fflush(stdout)

let end = Date().addingTimeInterval(seconds)
var all: [Int] = []
while Date() < end {
    Thread.sleep(forTimeInterval: 1.0)
    let batch = log.drain()
    all += batch
    guard !batch.isEmpty else { print("  (idle)"); fflush(stdout); continue }
    let lo = batch.filter { $0 < 64 }.count
    let hi = batch.filter { $0 > 64 }.count
    let uniq = Set(batch).sorted()
    let shown = uniq.count > 8 ? "\(uniq.prefix(4))…\(uniq.suffix(4))" : "\(uniq)"
    print(String(format: "  %3d msgs   low(<64): %-4d high(>64): %-4d  values %@",
                 batch.count, lo, hi, shown as NSString))
    fflush(stdout)
}

let lo = all.filter { $0 < 64 }, hi = all.filter { $0 > 64 }
print("")
print("total \(all.count) messages — \(lo.count) below 64, \(hi.count) above 64")
if !lo.isEmpty && !hi.isEmpty {
    print("SIGNED: both ranges appeared, so the value carries DIRECTION, not just speed.")
    print("  low  \(Set(lo).sorted().prefix(6))  -> one way")
    print("  high \(Set(hi).sorted().suffix(6))  -> the other way (127 = -1, 126 = -2)")
    print("notes/RESEARCH.md calls this 'rotation speed' — that needs correcting.")
} else if !all.isEmpty {
    print("Only ONE range appeared. Either the reel only turned one way, or the value really is")
    print("unsigned speed. Spin the other way and rerun before concluding.")
}
