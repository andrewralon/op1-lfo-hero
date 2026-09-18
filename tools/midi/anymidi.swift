import CoreMIDI
import Foundation

// Passive: shows whether the TP-7 is transmitting ANYTHING, not just clock.
//
// Distinguishes "the tape is not rolling" from "the device is not transmitting" — the clock
// counters cannot tell those apart, and both read as zero.
//
//   ./anymidi <device> [seconds]

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
let seconds = args.count > 2 ? Int(args[2])! : 15

var src: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) {
        src = e; break
    }
}
guard src != 0 else { print("NO SOURCE named \(target)"); exit(1) }

final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var total = 0
    func bump(_ k: String) { lock.lock(); counts[k, default: 0] += 1; total += 1; lock.unlock() }
    func snapshot() -> ([String: Int], Int) { lock.lock(); defer { lock.unlock() }; return (counts, total) }
}
let t = Tally()

var client = MIDIClientRef(); MIDIClientCreate("anymidi" as CFString, nil, nil, &client)
var port = MIDIPortRef()
MIDIInputPortCreateWithBlock(client, "in" as CFString, &port) { pkts, _ in
    for p in pkts.unsafeSequence() {
        let mp = UnsafeMutableRawPointer(mutating: p).advanced(by: 10).assumingMemoryBound(to: UInt8.self)
        var bytes: [UInt8] = []
        for i in 0..<Int(p.pointee.length) { bytes.append(mp[i]) }
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0xF8: t.bump("clock 0xF8"); i += 1
            case 0xFA: t.bump("start 0xFA"); i += 1
            case 0xFB: t.bump("continue 0xFB"); i += 1
            case 0xFC: t.bump("stop 0xFC"); i += 1
            case 0xFE: t.bump("active sensing"); i += 1
            case 0xF2: t.bump("song position"); i += 3
            default:
                if b & 0xF0 == 0xB0, i + 2 < bytes.count {
                    t.bump("cc \(bytes[i + 1]) (ch \((b & 0x0F) + 1))"); i += 3
                } else if b & 0xF0 == 0xE0 { t.bump("pitch bend"); i += 3 }
                else if b & 0xF0 == 0x90 || b & 0xF0 == 0x80 { t.bump("note"); i += 3 }
                else { t.bump(String(format: "other 0x%02X", b)); i += 1 }
            }
        }
    }
}
MIDIPortConnectSource(port, src, nil)

print("listening to '\(str(src, kMIDIPropertyDisplayName))' for \(seconds)s")
print("start the tape PART WAY THROUGH this window — the per-second counts show exactly when")
print("traffic starts, which a single total cannot.")
fflush(stdout)

// Live per-second output. A blind window cannot distinguish "the device is silent" from "the
// tape was not rolling at the time", which has now cost several runs.
// `kick` sends a single 0xFB partway through: does the device only start transmitting clock
// once it has received a transport message? Every successful clock reading so far came after
// transport had been sent, and a reboot would clear that.
let kick = args.count > 3 && args[3] == "kick"
var kickDest: MIDIEndpointRef = 0
var outPort = MIDIPortRef()
if kick {
    for n in 0..<MIDIGetNumberOfDestinations() {
        let e = MIDIGetDestination(n)
        if str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()), !isOffline(e) {
            kickDest = e; break
        }
    }
    MIDIOutputPortCreate(client, "kick" as CFString, &outPort)
    print("will send one 0xFB at 4s")
}

var last = 0
for sec in 1...seconds {
    Thread.sleep(forTimeInterval: 1.0)
    if kick && sec == 4 && kickDest != 0 {
        var pkt = MIDIPacketList()
        let p = MIDIPacketListInit(&pkt)
        _ = MIDIPacketListAdd(&pkt, 1024, p, 0, 1, [0xFB])
        MIDISend(outPort, kickDest, &pkt)
        print("   -> sent FB"); fflush(stdout)
    }
    let (_, total) = t.snapshot()
    let delta = total - last
    last = total
    print(String(format: "  %2ds  %4d msgs %@", sec, delta,
                 delta == 0 ? "(silent)" : String(repeating: "#", count: min(50, delta / 2))))
    fflush(stdout)
}

let (counts, total) = t.snapshot()
print("")
if total == 0 {
    print("NOTHING RECEIVED at all.")
    print("The device is not transmitting: check the midi mode is `sync` (re-select it — the")
    print("setting may not survive a replug), and that this is the data port, not a charge-only")
    print("cable. `ctrl` mode transmits buttons but no clock; `off` and `cue` transmit nothing.")
} else {
    print("received \(total) messages:")
    for (k, v) in counts.sorted(by: { $0.value > $1.value }) {
        print(String(format: "  %-22@ %6d", k as NSString, v))
    }
}
