import CoreMIDI
import Foundation

// Maps CC 18 across transport states, to settle a disagreement between this repo's model and
// lucidyan/tp7-midi. See notes/TP7_VS_TP7MIDI.md.
//
//   ./cc18map <device> control          what the app sends TODAY, measured — the control group
//   ./cc18map <device> stopped          test 1: is there a dead zone with the tape parked?
//   ./cc18map <device> playing          test 2: the +708 null point, tape rolling
//   ./cc18map <device> engage           test 3: does CC 18 "engage", or does 64 just add zero?
//   ./cc18map <device> bend             test 4: the pitch bend curve, forward and reversed
//   ./cc18map <device> extremes         test 9: CC 18 = 0 and 127
//   ./cc18map <device> hold <v> <secs>  send one CC 18 value and wait — for reading the display
//   ./cc18map <device> bendhold <v> <secs>  hold one bend value while ALREADY PLAYING and wait —
//                                            for reading the counter against exact elapsed time
//
// THE DISAGREEMENT. Both projects measured the same slope, 4 MIDI units per 1x. They differ on
// the intercept by exactly one 1x:
//
//   theirs (app.js, speed = (value - 64) / 4):   1x fwd at 68, 1x rev at 60, no dead zone
//   ours   (deadZone 4 + unitSpeed 4):           1x fwd at 71.5, 1x rev at 56.5
//
// Our offset table was measured with a file PLAYING, so the internal transport's +44 ticks/s is
// baked into every row — the "dead zone at 3.76" is that transport cancelling out, not a motor
// threshold (RESEARCH.md:629-632 says so itself). Their table describes a PARKED tape. If that
// is the whole story, both are right and the app's unconditional deadZone: 4 is wrong whenever
// the tape is stopped.
//
// At CC 18 = 68 the two predictions differ 17x, so one measurement decides it.
//
// SAFETY. The stopped-tape modes must never send 0xFC: a stop while already stopped rewinds the
// TP-7 to zero. Their cleanup is CC 18 = 64 plus centred bend, and nothing else.

func str(_ e: MIDIObjectRef, _ p: CFString) -> String {
    var s: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(e, p, &s) == noErr, let v = s else { return "" }
    return v.takeRetainedValue() as String
}

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TP-7"
let mode = args.count > 2 ? args[2] : "stopped"

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
guard src != 0, dest != 0 else { print("NO \(target) endpoint"); exit(1) }
print("src offline=\(isOffline(src))  dest offline=\(isOffline(dest))")

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

var client = MIDIClientRef(); MIDIClientCreate("cc18map" as CFString, nil, nil, &client)
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

func cc18(_ v: Int) { send([0xB0, 0x12, UInt8(max(0, min(127, v)))]) }
/// 14-bit bend, 8192 = centre.
func bend(_ v: Int) {
    let x = max(0, min(16383, v))
    send([0xE0, UInt8(x & 0x7F), UInt8((x >> 7) & 0x7F)])
}
let centre = 64
let centreBend = 8192

func measure(_ label: String, settle: Double = 2.0, window: Double = 8.0) -> Double {
    Thread.sleep(forTimeInterval: settle)
    _ = c.drain()
    let t0 = Date()
    Thread.sleep(forTimeInterval: window)
    let r = Double(c.drain()) / Date().timeIntervalSince(t0)
    say(String(format: "  %-28@ %7.2f ticks/s   x%.2f", label as NSString, r, r / 44.0))
    return r
}

/// Least squares on (offset, rate). Returns slope and intercept.
func fit(_ pts: [(Double, Double)]) -> (k: Double, c: Double) {
    guard pts.count > 1 else { return (0, 0) }
    let n = Double(pts.count)
    let sx = pts.reduce(0) { $0 + $1.0 }, sy = pts.reduce(0) { $0 + $1.1 }
    let sxx = pts.reduce(0) { $0 + $1.0 * $1.0 }, sxy = pts.reduce(0) { $0 + $1.0 * $1.1 }
    let d = n * sxx - sx * sx
    guard abs(d) > 1e-9 else { return (0, 0) }
    let k = (n * sxy - sx * sy) / d
    return (k, (sy - k * sx) / n)
}

// `raw` bypasses the countdown/precondition preamble entirely — a fast diagnostic single send,
// for isolating "does this exact proven connection reach the device at all" from "is this
// specific mode's logic correct." Bytes are decimal, e.g. `raw 176 120 127` = B0 78 7F.
if mode == "raw" {
    guard args.count > 5, let b0 = UInt8(args[3]), let b1 = UInt8(args[4]), let b2 = UInt8(args[5]) else {
        say("usage: raw <byte0> <byte1> <byte2>  (decimal, e.g. 176 120 127)")
        exit(1)
    }
    send([b0, b1, b2])
    exit(0)
}

let stoppedModes = ["control", "stopped", "extremes", "hold"]
let needsParked = stoppedModes.contains(mode)

/// Stopped modes must not leave a 0xFC behind — a stop on an already-stopped tape rewinds to zero.
func cleanup(sendStop: Bool) {
    cc18(centre)
    bend(centreBend)
    if sendStop { send([0xFC]) }
    say(sendStop ? "cleaned up: CC 18 released, bend centred, stopped once"
                 : "cleaned up: CC 18 released, bend centred — NO stop sent (tape was parked)")
}

say("")
say("mode: \(mode)")
if needsParked {
    say("PRECONDITION: midi mode `sync`, tape STOPPED (parked). Nothing should be moving.")
    say("This mode never sends 0xFC, so it cannot rewind you.")
} else {
    say("PRECONDITION: midi mode `sync`, tape PLAYING FORWARD under its own transport.")
}
say("starting in 6s")
Thread.sleep(forTimeInterval: 6)
say("")

// ---------------------------------------------------------------------------------------------
// Precondition check. The guard runs in opposite directions depending on the mode: revsync's
// `bail if no clock` is right only when the tape is supposed to be rolling.
// ---------------------------------------------------------------------------------------------

_ = c.drain()
let t0 = Date()
Thread.sleep(forTimeInterval: 3.0)
let idle = Double(c.drain()) / Date().timeIntervalSince(t0)
say(String(format: "precondition check: %.2f ticks/s", idle))

if needsParked, idle > 1 {
    say("")
    say("TAPE IS ROLLING — this mode needs it parked, and measuring now would fold the")
    say("transport's own +44 ticks/s into every reading (which is exactly the confound we are")
    say("here to remove). Stop the tape on the device, confirm the reel is still, and rerun.")
    say("Nothing was sent.")
    exit(2)
}
if !needsParked, idle <= 1 {
    say("")
    say("NO CLOCK — the tape is not rolling, so there is nothing to measure. Start playback on")
    say("the device, confirm the reel is moving, then rerun.")
    say("Nothing was sent. No verdict.")
    exit(2)
}

// ---------------------------------------------------------------------------------------------

switch mode {

// -- test 1a: the control group -----------------------------------------------------------
case "control":
    say("CONTROL GROUP — replaying exactly what ClockEngine sends today, from a parked tape.")
    say("offset = deadZone(4) + unitSpeed(4) * transportSpeed, so the app believes:")
    say("")
    let cases: [(String, Int, Double)] = [
        ("prev/next @ 2.0 (default)", 76, 2.0),
        ("scrub start @ 1.0",         72, 1.0),
        ("scrub max @ 14.0",         124, 14.0),
    ]
    var rows: [(String, Int, Double, Double)] = []
    for (label, v, claimed) in cases {
        cc18(v)
        let r = measure("CC 18 = \(v)")
        rows.append((label, v, claimed, r / 44.0))
        cc18(centre)
        _ = measure("  (parked again)", settle: 1.5, window: 2.0)
    }
    say("")
    say("  what the app calls it            CC 18   claims   measured")
    for (label, v, claimed, actual) in rows {
        say(String(format: "  %-30@   %3d    %5.2fx   %6.2fx", label as NSString, v, claimed, actual))
    }
    say("")
    say("If measured tracks claimed, the current constants are right for a parked tape.")
    say("If measured runs consistently ~1x high, deadZone: 4 is being applied where it does not")
    say("belong — see test `stopped`.")
    cleanup(sendStop: false)

// -- test 1: the decisive one ---------------------------------------------------------------
case "stopped":
    say("TEST 1 — is there a dead zone with the tape parked?")
    say("")
    say("First: can the clock even see a CC-18-driven tape? Sending CC 18 = 76, which is moving")
    say("under either model (+3x theirs, +2x ours).")
    cc18(76)
    let probe = measure("CC 18 = 76 (clock probe)", settle: 2.0, window: 4.0)
    cc18(centre)
    _ = measure("  (parked again)", settle: 1.5, window: 2.0)

    if probe <= 1 {
        say("")
        say("NO CLOCK while CC 18 drives the tape. The instrument is blind in this state, so")
        say("this tool cannot produce a verdict. Fall back to the position display:")
        say("")
        say("  1. note the position counter")
        say("  2. ./cc18map \(target) hold 68 10")
        say("  3. read the counter again")
        say("")
        say("  ~10s of travel  => 1x at CC 18 = 68  => NO dead zone (their model)")
        say("  ~0-1s of travel => stalled at 68     => dead zone (our model)")
        cleanup(sendStop: false)
        exit(3)
    }

    say("")
    say("Clock is live while CC 18 drives. Sweeping, parking between every point.")
    say("")
    var fwd: [(Double, Double)] = []
    var rev: [(Double, Double)] = []
    for v in [65, 66, 68, 70, 72] {
        cc18(v)
        let r = measure("CC 18 = \(v)  (offset +\(v - centre))")
        fwd.append((Double(v - centre), r))
        cc18(centre)
        let parked = measure("  (parked again)", settle: 1.5, window: 2.0)
        if parked > 5 { say("  ⚠️  did not park — CC 18 = 64 left it moving. Note this, it matters.") }
    }
    for v in [63, 62, 60, 58, 56] {
        cc18(v)
        let r = measure("CC 18 = \(v)  (offset -\(centre - v))")
        rev.append((Double(centre - v), r))
        cc18(centre)
        let parked = measure("  (parked again)", settle: 1.5, window: 2.0)
        if parked > 5 { say("  ⚠️  did not park — CC 18 = 64 left it moving. Note this, it matters.") }
    }

    let f = fit(fwd), r = fit(rev)
    say("")
    say(String(format: "forward fit:  rate = %.2f * offset + %.1f", f.k, f.c))
    say(String(format: "reverse fit:  rate = %.2f * offset + %.1f", r.k, r.c))
    say("")
    say("  theirs (no dead zone):   k ~ 11.0,  c ~ 0     => 1x at 68 / 60")
    say("  ours   (deadZone 4):     k ~ 11.7,  c ~ -44   => 1x at 71.5 / 56.5")
    say("")
    let at68 = fwd.first(where: { $0.0 == 4 })?.1 ?? -1
    say(String(format: "the separator — CC 18 = 68 measured %.2f ticks/s (x%.2f)", at68, at68 / 44.0))
    if at68 > 25 {
        say("=> NO DEAD ZONE. Their model is right for a parked tape: 68 is about 1x.")
        say("   deadZone is not a device constant — it is the internal transport's own")
        say("   contribution, and the app must not apply it when the tape is stopped.")
        say("   Every prev/next/scrub from a parked tape is currently one whole 1x too fast.")
    } else if at68 < 10 {
        say("=> DEAD ZONE CONFIRMED. Our model holds even with the tape parked, so deadZone: 4")
        say("   is a real motor threshold and the profile is correct as shipped.")
        say("   Their 68 = 1x row is then wrong on this firmware.")
    } else {
        say("=> INCONCLUSIVE. 68 landed between the two predictions. Report the fit above; do not")
        say("   change the profile on this run.")
    }
    cleanup(sendStop: false)

// -- test 2: the +708 null point ------------------------------------------------------------
case "playing":
    say("TEST 2 — the stop point during playback, and whether the +708 workaround is real.")
    say("The clock is unsigned, so DIRECTION needs your eyes: watch the reel and the counter.")
    say("")
    let base = measure("baseline (playing forward)")
    guard base > 1 else { say("lost the clock — aborting"); cleanup(sendStop: true); exit(2) }

    cc18(61)
    let a = measure("CC 18 = 61")
    cc18(60)
    let b = measure("CC 18 = 60")
    say("  ^^ WATCH THE REEL: forward or reverse at 60?")
    bend(8900)
    let d = measure("CC 18 = 60 + bend 8900")
    say("  ^^ WATCH THE COUNTER: is it standing still?")
    bend(centreBend)
    cc18(centre)
    let back = measure("CC 18 = 64, bend centred")

    say("")
    say(String(format: "baseline %.1f | 61 -> %.1f | 60 -> %.1f | 60+bend -> %.1f | released -> %.1f",
               base, a, b, d, back))
    say("predictions from OUR OWN additive model (which reproduces their claim):")
    say("  61 ~ 8.9 fwd    60 ~ 2.8 rev    60+bend ~ 0.7 (stopped)    released ~ 44 fwd")
    say("")
    if d < 5 && b < 10 {
        say("=> CONFIRMED. The null really does sit between 60 and 61 while playing, and +708 of")
        say("   bend lands on it. RESEARCH.md:508-512 currently calls this wrong — that")
        say("   correction should be retracted and rewritten as a confirmation.")
    } else if b > 30 {
        say("=> NOT CONFIRMED. 60 is a real reverse speed, not a stall — our published correction")
        say("   stands. Keep RESEARCH.md:508-512 as written.")
    } else {
        say("=> INCONCLUSIVE. Report the numbers; do not rewrite the correction on this run.")
    }
    cleanup(sendStop: true)

// -- test 3: does CC 18 "engage"? -------------------------------------------------------------
case "engage":
    say("TEST 3 — does CC 18 need to 'engage', or does 64 simply add zero velocity?")
    say("")
    let base = measure("baseline (playing forward)")
    guard base > 1 else { say("lost the clock — aborting"); cleanup(sendStop: true); exit(2) }

    say("sending CC 18 = 64 three times — both models predict no change")
    cc18(centre); cc18(centre); cc18(centre)
    let flat = measure("after 64 x3")

    cc18(70)
    let up = measure("CC 18 = 70")
    cc18(centre)
    let after = measure("CC 18 = 64 again")

    say("")
    say(String(format: "baseline %.1f | 64x3 -> %.1f | 70 -> %.1f | back to 64 -> %.1f",
               base, flat, up, after))
    say("  additive: 64 removes the offset, transport keeps rolling  => back to ~44")
    say("  engage:   64 means zero speed once engaged                => stops")
    say("")
    if after > 25 {
        say("=> ADDITIVE. 64 adds zero rather than commanding a stop. The engage/release framing")
        say("   in RESEARCH.md:471-484 is unnecessary and can be deleted — a strictly simpler")
        say("   model fits the same data.")
    } else if after < 10 {
        say("=> ENGAGE MODEL HOLDS. 64 really does stop an engaged tape. Keep the framing.")
    } else {
        say("=> INCONCLUSIVE.")
    }
    cleanup(sendStop: true)

// -- test 4: the bend curve -------------------------------------------------------------------
case "bend":
    say("TEST 4 — the pitch bend curve, forward then reversed.")
    say("Also settles an inconsistency in our OWN notes: RESEARCH.md:588 says +40 ticks/s at full")
    say("positive (x1.91), but the table at :584 records x2.14.")
    say("")
    let base = measure("baseline, bend centred")
    guard base > 1 else { say("lost the clock — aborting"); cleanup(sendStop: true); exit(2) }

    say("forward sweep:")
    var fwd: [(Int, Double)] = []
    for v in [0, 4096, 8192, 12288, 16383] {
        bend(v)
        fwd.append((v, measure("bend \(v) (\(v - 8192) signed)")))
    }
    bend(centreBend)

    say("")
    say("now reversed — CC 18 = 56. If bend is a signed VELOCITY, its sense flips here;")
    say("a magnitude multiplier could not do that.")
    cc18(56)
    var rev: [(Int, Double)] = []
    for v in [0, 8192, 16383] {
        bend(v)
        rev.append((v, measure("rev, bend \(v)")))
    }
    bend(centreBend)
    cc18(centre)

    say("")
    say("  bend        forward      ours     theirs")
    let oursFwd = [0: "x0.54", 4096: "x0.77", 8192: "x1.00", 12288: "x1.45", 16383: "x1.91-2.14"]
    let theirsFwd = [0: "x0.25", 4096: "x0.63", 8192: "x1.00", 12288: "x1.50", 16383: "x2.00"]
    for (v, r) in fwd {
        say(String(format: "  %5d    %7.2f = x%.2f    %-6@   %@",
                   v, r, r / 44.0,
                   (oursFwd[v] ?? "") as NSString, (theirsFwd[v] ?? "") as NSString))
    }
    say("")
    say("  reversed (CC 18 = 56):")
    for (v, r) in rev { say(String(format: "  %5d    %7.2f = x%.2f", v, r, r / 44.0)) }
    say("")
    let low = fwd.first(where: { $0.0 == 0 })?.1 ?? -1
    say(String(format: "the separator — bend 0 measured x%.2f (ours x0.54, theirs x0.25)", low / 44.0))
    if rev.count == 3, rev[0].1 > rev[2].1 {
        say("=> the sense FLIPS in reverse: bend up slows a reversing tape. Velocity model holds.")
    } else {
        say("=> no flip observed — re-examine the velocity model.")
    }
    cleanup(sendStop: true)

// -- test 9: the extremes ----------------------------------------------------------------------
case "extremes":
    say("TEST 9 — CC 18 = 127 and 0, from a parked tape.")
    say("Their model predicts about +15.75x / -16x (~690 ticks/s). Check whether the clock even")
    say("survives that rate before trusting the app's maxScrubSpeed = 14.0 ceiling.")
    say("SHORT windows — this eats tape fast.")
    say("")
    cc18(127)
    let hi = measure("CC 18 = 127", settle: 1.0, window: 3.0)
    cc18(centre)
    _ = measure("  (parked again)", settle: 1.5, window: 2.0)
    cc18(0)
    let lo = measure("CC 18 = 0", settle: 1.0, window: 3.0)
    cc18(centre)
    _ = measure("  (parked again)", settle: 1.5, window: 2.0)
    say("")
    say(String(format: "127 -> %.1f ticks/s (x%.2f)   0 -> %.1f ticks/s (x%.2f)",
               hi, hi / 44.0, lo, lo / 44.0))
    say("if these read far below ~690, either the clock saturates or the motor does — say which")
    say("by watching the reel, because the app's 14x ceiling depends on it.")
    cleanup(sendStop: false)

// -- the display fallback ----------------------------------------------------------------------
case "hold":
    let v = args.count > 3 ? (Int(args[3]) ?? 68) : 68
    let secs = args.count > 4 ? (Double(args[4]) ?? 10) : 10
    say("HOLD — sending CC 18 = \(v) for \(secs)s, then releasing. No stop is sent.")
    say("Note the position counter NOW. Read it again when this finishes.")
    say("")
    cc18(v)
    let r = measure("CC 18 = \(v)", settle: 0.5, window: secs)
    cc18(centre)
    say("")
    say(String(format: "clock said %.2f ticks/s (x%.2f) — 0 means the clock cannot see this state",
               r, r / 44.0))
    say("Read the counter: ~\(Int(secs))s of travel = 1x. ~0 = stalled.")
    cleanup(sendStop: false)

// -- precise bend readout, playing tape, counter cross-check ----------------------------------
case "bendhold":
    let v = args.count > 3 ? (Int(args[3]) ?? 8192) : 8192
    let secs = args.count > 4 ? (Double(args[4]) ?? 10) : 10
    say("BENDHOLD — tape must ALREADY be PLAYING FORWARD. Bend does nothing on a stopped tape.")
    say("Sending bend = \(v) (\(v - 8192) signed) for \(secs)s, then releasing to centre (8192).")
    say("CC 18 and the transport are never touched by this mode.")
    say("Note the position counter NOW, as precisely as you can.")
    say("")
    _ = c.drain()
    let t0 = Date()
    bend(v)
    Thread.sleep(forTimeInterval: secs)
    let ticks = c.drain()
    let elapsed = Date().timeIntervalSince(t0)
    bend(centreBend)
    say("")
    say(String(format: "released after %.3fs elapsed (asked for %.1fs)", elapsed, secs))
    if ticks > 1 {
        say(String(format: "clock: %d ticks over %.3fs = %.2f ticks/s = x%.3f",
                   ticks, elapsed, Double(ticks) / elapsed, Double(ticks) / elapsed / 44.0))
    } else {
        say("clock saw no usable ticks in this window — rely on the counter alone")
    }
    say(String(format: "READ THE COUNTER NOW. seconds of tape travel / %.3fs elapsed = your measured multiplier",
               elapsed))
    say("bend left at centre (8192). CC 18 and transport untouched — tape should still be rolling normally.")

default:
    say("unknown mode '\(mode)'")
    say("modes: control | stopped | playing | engage | bend | extremes | hold <value> <secs> | bendhold <value> <secs>")
    exit(1)
}
