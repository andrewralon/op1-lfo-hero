import CoreMIDI
import Foundation

// Two tests of the additive-velocity model, both starting from the tape ALREADY REVERSING under
// its own transport (press play twice on the TP-7 itself).
//
//   ./revsync <device> model    does CC 18 stack on top of the device's own direction?
//   ./revsync <device> fix      does 0xFB force the internal transport forward?
//
// model: baseline native reverse, then CC 18 = 56 on top.
//        additive model predicts ~132 ticks/s (3x); an absolute model predicts ~49 (1.13x).
//        These are far enough apart that one run decides it.
//
// fix:   baseline native reverse, then 0xFB alone, then 0xFB + CC 18 = 56 + bend.
//        if 0xFB forces forward, phase 2 reads ~+44 and phase 3 reads ~44 — meaning the app can
//        force a known direction instead of assuming one, and stay in sync with the hardware.
//
// The clock is unsigned, so it measures speed and never direction. Watch the reel to tell which
// way it is going; the magnitudes alone still separate the two hypotheses.

func str(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &s) == noErr, let v = s else { return "" }
    return v.takeRetainedValue() as String
}

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TP-7"
let mode = args.count > 2 ? args[2] : "model"

// Unplugging leaves a stale endpoint behind with the same name, so matching on name alone can
// bind input to a dead one while output goes to the live device — which reads as "no clock" even
// though the tape is plainly moving. Skip anything marked offline.
func isOffline(_ e: MIDIEndpointRef) -> Bool {
    var v: Int32 = 0
    guard MIDIObjectGetIntegerProperty(e, kMIDIPropertyOffline, &v) == noErr else { return false }
    return v != 0
}
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
let src = find(MIDIGetNumberOfSources(), MIDIGetSource)
let dest = find(MIDIGetNumberOfDestinations(), MIDIGetDestination)
guard src != 0, dest != 0 else { print("NO TP-7 endpoint"); exit(1) }
print("src offline=\(isOffline(src))  dest offline=\(isOffline(dest))")

// The tape has been seen moving while this reported no clock at all. List every candidate so a
// duplicate endpoint (or a device that simply is not transmitting) is visible rather than
// silently producing zeros.
print("all matching sources:")
for i in 0..<MIDIGetNumberOfSources() {
    let e = MIDIGetSource(i)
    let n = str(e, kMIDIPropertyDisplayName)
    if n.lowercased().contains(target.lowercased()) {
        print("  [\(i)] '\(n)'  offline=\(isOffline(e))\(e == src ? "   <- listening here" : "")")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func tick() { lock.lock(); n += 1; lock.unlock() }
    func drain() -> Int { lock.lock(); defer { n = 0; lock.unlock() }; return n }
}
let c = Counter()

var client = MIDIClientRef(); MIDIClientCreate("revsync" as CFString, nil, nil, &client)
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
func say(_ s: String) { print(s); fflush(stdout) }

/// Short windows on purpose: if the additive model is right, phase 2 of `model` runs at 3x and
/// eats tape fast.
func measure(_ label: String, settle: Double = 1.5, window: Double = 4.0) -> Double {
    Thread.sleep(forTimeInterval: settle)
    _ = c.drain()
    let t0 = Date()
    Thread.sleep(forTimeInterval: window)
    let r = Double(c.drain()) / Date().timeIntervalSince(t0)
    say(String(format: "  %-24@ %7.2f ticks/s   x%.2f", label as NSString, r, r / 44.0))
    return r
}

say("mode: \(mode)   — tape must ALREADY be reversing under its own transport")
say("starting in 6s")
Thread.sleep(forTimeInterval: 6)

// `ear` modes skip measurement entirely — the sync clock is currently not transmitting, and the
// difference between 1x and 3x reverse is obvious by ear anyway.
let byEar = mode.hasSuffix("ear")

// Does the TP-7 *receive* CC 30, or is the wheel transmit-only? It appears in the controller-mode
// map, where the device drives other gear; nothing says it listens. If it does listen, a stream
// of small deltas should jog the tape — 1..63 one way, 127..65 the other (127 = -1).
if mode == "wheelear" {
    say("BY EAR. tape STOPPED, mid-file. does incoming CC 30 move the tape?")
    say("")
    for (label, value) in [("forward (+2, 60x)", 2), ("reverse (-2, 60x)", 126)] {
        say("sending CC 30 = \(value) — \(label)")
        for _ in 0..<60 {
            send([0xB0, 0x1E, UInt8(value)])
            Thread.sleep(forTimeInterval: 0.02)
        }
        say("  (watch the reel and the position)")
        Thread.sleep(forTimeInterval: 3)
    }
    say("done — did the tape move at all, and did the two bursts move it opposite ways?")
    exit(0)
}

// Did the app's CC 18 actually take control, or did the device simply carry on with its own
// reverse and ignore the burst? Both sound like unchanged normal-speed reverse. This settles it:
// after the burst, send CC 18 = 64 on its own. Once engaged, 64 means zero speed and the tape
// stops; if CC 18 never engaged, 64 does nothing and the tape keeps reversing.
if mode == "probeear" {
    say("BY EAR. tape must ALREADY be reversing under its own transport.")
    say("")
    say("step 1: the app's resync burst, back to back")
    send([0xB0, 0x12, 0x40])
    send([0xFC])
    send([0xFB])
    send([0xB0, 0x12, 0x38])
    send([0xE0, 0x64, 0x4B])
    Thread.sleep(forTimeInterval: 7)

    say("step 2: CC 18 = 64 ALONE — no 0xFC. does the tape stop?")
    say("        stops  -> CC 18 had the transport, the resync is real")
    say("        keeps going -> CC 18 never engaged, the burst was ignored")
    send([0xB0, 0x12, 0x40])
    Thread.sleep(forTimeInterval: 7)

    say("cleaning up")
    send([0xE0, 0x00, 0x40])
    send([0xFC])
    say("done — did it stop at step 2, or keep reversing?")
    exit(0)
}

// Same resync as fix2ear, but with no pauses between the transport messages — the app would
// send them back to back. If the device still registers the stop, the fix costs nothing; if it
// needs settling time, every direction flip gets an audible gap.
if mode == "fastear" {
    say("BY EAR — resync sent back to back, no delays. listen for the reverse speed.")
    say("")
    say("sending: CC 18 = 64, 0xFC, 0xFB, CC 18 = 56, bend 9700 — all at once")
    send([0xB0, 0x12, 0x40])
    send([0xFC])
    send([0xFB])
    send([0xB0, 0x12, 0x38])
    send([0xE0, 0x64, 0x4B])
    Thread.sleep(forTimeInterval: 8)

    say("releasing and stopping")
    send([0xB0, 0x12, 0x40])
    send([0xE0, 0x00, 0x40])
    send([0xFC])
    say("done — was the reverse normal speed, or fast?")
    say("normal = the fix is free. fast = the device needs settling time between messages.")
    exit(0)
}

if byEar {
    say("BY EAR — no measurement. listen for the speed after each step.")
    say("")
    say("step 1: stopping (releases CC 18 first, then one 0xFC)")
    send([0xB0, 0x12, 0x40])
    send([0xFC])
    Thread.sleep(forTimeInterval: 3)

    say("step 2: play — should roll FORWARD from a known state. listen.")
    send([0xFB])
    Thread.sleep(forTimeInterval: 6)

    say("step 3: reverse — CC 18 = 56 + bend 9700. THIS is the question:")
    say("        normal-speed reverse = fixable.  fast reverse = still stacking.")
    send([0xB0, 0x12, 0x38])
    send([0xE0, 0x64, 0x4B])
    Thread.sleep(forTimeInterval: 8)

    say("releasing and stopping")
    send([0xB0, 0x12, 0x40])
    send([0xE0, 0x00, 0x40])
    send([0xFC])
    say("done — was step 3 normal speed, or fast?")
    exit(0)
}

let base = measure("native reverse (baseline)")

// No clock means the tape is not rolling. Bail out before sending anything: continuing would
// both produce a verdict from an empty measurement and leave a stray 0xFC on a stopped tape,
// which rewinds the TP-7 to zero.
guard base > 1 else {
    say("")
    say("NO CLOCK — the tape is not rolling, so there is nothing to measure.")
    say("Start it reversing on the device (play twice), confirm the reel is moving, then rerun.")
    say("Nothing was sent. No verdict.")
    exit(2)
}

switch mode {
case "model":
    say("sending CC 18 = 56 on top of the device's own reverse")
    send([0xB0, 0x12, 0x38])
    let stacked = measure("native reverse + CC 18")
    say("")
    say(String(format: "baseline %.1f  ->  %.1f ticks/s  (x%.2f of baseline)",
               base, stacked, stacked / max(1, base)))
    say("additive model predicts ~132 (x3.0 of 1x). absolute predicts ~49 (x1.13).")
    if stacked > 100 {
        say("=> ADDITIVE: CC 18 stacks on the device's own direction. The app cannot assume")
        say("   the transport is going forward — it has to force it.")
    } else if stacked > 30 {
        say("=> ABSOLUTE: CC 18 overrides direction. Then the fast reverse has another cause.")
    } else {
        say("=> neither — unexpected, needs a closer look.")
    }

case "fix":
    say("sending 0xFB alone — does Continue force the internal transport forward?")
    send([0xFB])
    let afterPlay = measure("after 0xFB")
    say("watch the reel: is it now going FORWARD?")

    say("now the app's full reverse on top: CC 18 = 56 + bend 9700")
    send([0xB0, 0x12, 0x38])
    send([0xE0, 0x64, 0x4B])
    let reversed = measure("0xFB then CC 18 + bend")
    say("")
    say(String(format: "baseline %.1f | after 0xFB %.1f | app reverse %.1f",
               base, afterPlay, reversed))
    if abs(reversed - 44.0) < 6 {
        say("=> FIXABLE: forcing 0xFB first makes reverse land on 1x regardless of what the")
        say("   device was doing. The app can resync itself without ever reading device state.")
    } else {
        say("=> NOT FIXABLE this way: 0xFB does not reset the internal direction.")
        say("   Reverse stays dependent on hardware state the app cannot see — document it.")
    }

case "fix2":
    // 0xFB alone did nothing, because Continue is a no-op on a tape that is already rolling.
    // A stop is a state the device certainly acts on, so stop first, then play forward from a
    // known direction, then reverse. Costs a brief pause on every flip.
    say("stopping first — Continue only means something from a stopped state")
    send([0xB0, 0x12, 0x40])          // release CC 18 before stopping
    send([0xFC])
    Thread.sleep(forTimeInterval: 1.0)

    say("now play — should roll FORWARD from a known state")
    send([0xFB])
    let forward = measure("after stop then play")
    say("watch the reel: is it going FORWARD now?")

    say("now reverse on top: CC 18 = 56 + bend 9700")
    send([0xB0, 0x12, 0x38])
    send([0xE0, 0x64, 0x4B])
    let reversed = measure("stop, play, then reverse")
    say("")
    say(String(format: "baseline %.1f | after stop+play %.1f | reverse %.1f",
               base, forward, reversed))
    if abs(reversed - 44.0) < 6 {
        say("=> FIXABLE: stop-then-play forces a known direction, so reverse lands on 1x no")
        say("   matter what the device was doing. Costs a brief pause on each flip.")
    } else {
        say("=> STILL STACKING: even a stop does not clear the internal direction.")
        say("   The app cannot resync — document it as a limitation.")
    }

default:
    say("unknown mode")
}

// Leave it clean: release CC 18 and bend, stop exactly once.
send([0xB0, 0x12, 0x40])
send([0xE0, 0x00, 0x40])
send([0xFC])
say("stopped, CC 18 and bend released")
