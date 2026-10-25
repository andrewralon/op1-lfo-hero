import CoreMIDI
import Foundation

// Slowly sweeps pitch bend or one CC across chosen MIDI channels, so you can HEAR which channel a
// device responds to. A smooth sweep is far easier to catch by ear than a jump between extremes,
// and announcing each channel removes the "which one was that?" ambiguity.
//
//   ./sweep <device> bend <channels> [seconds]
//   ./sweep <device> cc <cc> <channels> [seconds]
//
//   channels  1-based, as the device labels them: `1`, `1,3`, `1-4`, or `all` (1-16)
//   seconds   length of ONE sweep, default 6 (centre -> top -> bottom -> centre)
//
//   ./sweep OP-1 bend 1-4         # does bend land per track, or only on one channel?
//   ./sweep OP-1 cc 90 1          # master eq low: which way does it go, is 64 flat?
//   ./sweep OP-1 bend all 4
//
// Hold a note or play the tape while it runs. Bend is silent on a drum or a parked tape.
// Every sweep ends back at centre (bend 8192 / CC 64), including on Ctrl-C, so a stray bend is
// never left on the device. A CC has no known "previous" value to restore, so 64 is a guess —
// reset knobs yourself if the device was not sitting at 64.

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

func usage() -> Never {
    print("""
    usage: sweep <device> bend <channels> [seconds]
           sweep <device> cc <cc> <channels> [seconds]
      channels: 1-based — `1`, `1,3`, `1-4` or `all`
    """)
    exit(1)
}

func parseChannels(_ s: String) -> [Int] {
    if s == "all" { return Array(1...16) }
    var out: [Int] = []
    for part in s.split(separator: ",") {
        let r = part.split(separator: "-").compactMap { Int($0) }
        if r.count == 2, r[0] <= r[1] { out += Array(r[0]...r[1]) }
        else if r.count == 1 { out.append(r[0]) }
        else { usage() }
    }
    guard !out.isEmpty, out.allSatisfy({ (1...16).contains($0) }) else { usage() }
    return out
}

let args = CommandLine.arguments
guard args.count >= 4 else { usage() }
let target = args[1]
let kind = args[2]

var cc = 0
var channels: [Int] = []
var seconds = 6.0
switch kind {
case "bend":
    channels = parseChannels(args[3])
    if args.count > 4 { seconds = Double(args[4]) ?? 6 }
case "cc":
    guard args.count >= 5, let n = Int(args[3]), (0...127).contains(n) else { usage() }
    cc = n
    channels = parseChannels(args[4])
    if args.count > 5 { seconds = Double(args[5]) ?? 6 }
default:
    usage()
}
if !seconds.isFinite || seconds <= 0 { seconds = 6 }   // "nan"/"inf" would trap in Int(...) below

func find(_ count: Int, _ get: (Int) -> MIDIEndpointRef) -> MIDIEndpointRef {
    var fallback: MIDIEndpointRef = 0
    for i in 0..<count {
        let e = get(i)
        guard str(e, kMIDIPropertyDisplayName).lowercased().contains(target.lowercased()) else { continue }
        if !isOffline(e) { return e }
        if fallback == 0 { fallback = e }
    }
    return fallback
}
let dest = find(MIDIGetNumberOfDestinations(), MIDIGetDestination)
guard dest != 0 else { print("NO \(target) destination — run ./mididiag"); exit(1) }

var client = MIDIClientRef(); MIDIClientCreate("sweep" as CFString, nil, nil, &client)
var outPort = MIDIPortRef(); MIDIOutputPortCreate(client, "out" as CFString, &outPort)
func send(_ b: [UInt8]) {
    // The list must really be as large as the size handed to MIDIPacketListAdd; a bare
    // MIDIPacketList() is only ~268 bytes.
    let size = 1024
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIPacketList>.alignment)
    defer { raw.deallocate() }
    let pkt = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
    let p = MIDIPacketListInit(pkt)
    _ = MIDIPacketListAdd(pkt, size, p, 0, b.count, b)
    MIDISend(outPort, dest, pkt)
}
func say(_ s: String) { print(s); fflush(stdout) }

var interrupted = false
signal(SIGINT) { _ in interrupted = true }

let bendCentre = 8192
func setBend(ch: Int, _ v: Int) {
    let c = max(0, min(16383, v))
    send([UInt8(0xE0 | (ch - 1)), UInt8(c & 0x7F), UInt8((c >> 7) & 0x7F)])
}
func setCC(ch: Int, _ v: Int) {
    send([UInt8(0xB0 | (ch - 1)), UInt8(cc), UInt8(max(0, min(127, v)))])
}
func put(ch: Int, _ unit: Double) {          // unit: 0...1 across the whole range
    if kind == "bend" { setBend(ch: ch, Int((unit * 16383).rounded())) }
    else { setCC(ch: ch, Int((unit * 127).rounded())) }
}
func recentre(ch: Int) {
    if kind == "bend" { setBend(ch: ch, bendCentre) } else { setCC(ch: ch, 64) }
}

// Triangle: centre -> top -> bottom -> centre, in 20 ms steps.
func sweep(ch: Int) {
    // At least one step per leg: 0 divides by zero below, and a NaN/inf trap on Int(...).
    let stepsPerLeg = max(1, Int(seconds / 0.02 / 4))
    var path: [Double] = []
    for i in 0...stepsPerLeg { path.append(0.5 + 0.5 * Double(i) / Double(stepsPerLeg)) }
    for i in 0...(2 * stepsPerLeg) { path.append(1.0 - Double(i) / Double(stepsPerLeg)) }
    for i in 0...stepsPerLeg { path.append(Double(i) / Double(stepsPerLeg) * 0.5) }
    for u in path {
        if interrupted { break }
        put(ch: ch, u)
        Thread.sleep(forTimeInterval: 0.02)
    }
    recentre(ch: ch)
}

let what = kind == "bend" ? "pitch bend" : "CC \(cc)"
say("sweeping \(what) on channel(s) \(channels.map(String.init).joined(separator: ", ")) — \(Int(seconds))s each")
say("order: centre -> top -> bottom -> centre. Ctrl-C recentres and stops.")
say("starting in 3s")
Thread.sleep(forTimeInterval: 3)

for (i, ch) in channels.enumerated() {
    if interrupted { break }
    say("")
    say(">>> channel \(ch)  (\(i + 1) of \(channels.count))  — listen now")
    sweep(ch: ch)
    if i < channels.count - 1 && !interrupted {
        say("    done, recentred. next in 3s")
        Thread.sleep(forTimeInterval: 3)
    }
}
// A Ctrl-C can land mid-leg; make sure every channel we touched is back at centre.
for ch in channels { recentre(ch: ch) }
say("")
say(interrupted ? "interrupted — all swept channels recentred." : "done — all swept channels recentred.")
