import CoreMIDI
import Foundation

// Test 7 (TP7_VS_TP7MIDI.md) — is CC 17 (loop) immutable once active?
//
//   ./looptest <device>
//
// RESEARCH.md already confirms in (1) must precede out (2), and out alone is discarded. This
// tool asks the next question: once a loop is active (in+out both set), does sending 1 or 2
// again move the existing marker, or is the state locked until 0 (off) releases it?
//
// Needs the tape PLAYING FORWARD — the original loop finding was verified with playback running
// throughout ("audio repeated"), not from a parked tape.

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
guard dest != 0 else { print("NO \(target) destination"); exit(1) }

var client = MIDIClientRef(); MIDIClientCreate("looptest" as CFString, nil, nil, &client)
var outPort = MIDIPortRef(); MIDIOutputPortCreate(client, "out" as CFString, &outPort)
func send(_ b: [UInt8]) {
    var pkt = MIDIPacketList()
    let p = MIDIPacketListInit(&pkt)
    _ = MIDIPacketListAdd(&pkt, 1024, p, 0, b.count, b)
    MIDISend(outPort, dest, &pkt)
    print("    -> " + b.map { String(format: "%02X", $0) }.joined(separator: " ")); fflush(stdout)
}
func say(_ s: String) { print(s); fflush(stdout) }
func loop(_ v: Int) { send([0xB0, 0x11, UInt8(v)]) }
func pause(_ label: String, _ secs: Double = 4) {
    say("")
    say("  \(label)")
    say("  waiting \(Int(secs))s — read the display now")
    Thread.sleep(forTimeInterval: secs)
}

say("PRECONDITION: midi mode `sync`, tape PLAYING FORWARD.")
say("starting in 6s")
Thread.sleep(forTimeInterval: 6)
say("")

say("Step 1 — CC 17 = 1 (set IN point here)")
loop(1)
pause("Note the IN marker / position.")

say("Step 2 — CC 17 = 2 (set OUT point here) — loop should now be active")
loop(2)
pause("Confirm: does it loop? Note both markers.")

say("Step 3 — CC 17 = 1 again, WITHOUT releasing first — does the IN point move to here?")
loop(1)
pause("Compare the IN marker to step 1. Moved, or unchanged?")

say("Step 4 — CC 17 = 2 again — does the OUT point move to here?")
loop(2)
pause("Compare the OUT marker to step 2. Moved, or unchanged?")

say("Step 5 — CC 17 = 0 (release)")
loop(0)
pause("Confirm: loop released cleanly, playback continues normally?", 3)

say("done. no further cleanup needed (0 leaves loop off, playback untouched).")
