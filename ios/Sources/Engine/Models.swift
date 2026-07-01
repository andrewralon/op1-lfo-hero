import Foundation

let PPQN = 24

// Rate spinbox value (1-8) → ticks per LFO cycle.
// Index 1 = 8× (fastest), index 8 = 16b (slowest), matching the displayed labels 8→1.
let RATE_TICKS: [Int: Int] = [
    1: PPQN / 8,    // 8×
    2: PPQN / 4,    // 4×
    3: PPQN / 2,    // 2×
    4: PPQN,        // 1b
    5: 2  * PPQN,   // 2b
    6: 4  * PPQN,   // 4b
    7: 8  * PPQN,   // 8b
    8: 16 * PPQN,   // 16b
]

let RATE_LABELS = ["8×", "4×", "2×", "1b", "2b", "4b", "8b", "16b"]

// Free rates (f1–f17): fixed-time, tempo-independent. Rate indices 9–25.
// Period in seconds, log-spaced from FREE_RATE_MIN_S to FREE_RATE_MAX_S.
let FREE_RATE_MIN_S = 0.02
let FREE_RATE_MAX_S = 15.0
let FREE_RATE_SECONDS: [Int: Double] = {
    var d: [Int: Double] = [:]
    let n = 17
    let logMin = log(FREE_RATE_MIN_S), logMax = log(FREE_RATE_MAX_S)
    for i in 0..<n {
        // Exponent < 1 gives larger steps near the fast end (f1-f3) and
        // smaller steps near the slow end (f15-f17) vs pure log spacing.
        let u = i == 0 ? 0.0 : pow(Double(i) / Double(n - 1), 0.75)
        d[9 + i] = exp(logMin + u * (logMax - logMin))
    }
    return d
}()

// Label shown in the rate scrub widget (e.g. "8", "f1", "f17").
// Tempo-relative indices 1–8 display as 8→1 (fast to slow); free rates display as f1→f17.
func rateScrubLabel(for index: Int) -> String {
    index <= 8 ? String(9 - index) : "f\(index - 8)"
}

// Label shown on LFO chips (e.g. "8", "1", "f1", "f17").
func rateChipLabel(for index: Int) -> String {
    if index >= 1 && index <= 8 { return "\(9 - index)" }
    guard index >= 9 && index <= 25 else { return "?" }
    return "f\(index - 8)"
}

// MARK: - LfoWave

enum LfoWave: String, CaseIterable, Identifiable, Codable {
    case sine, triangle, saw, square, log, exp
    case sweepUp = "sweep up"
    case sweepDn = "sweep dn"
    case random

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .sine:     return "sin"
        case .triangle: return "tri"
        case .saw:      return "saw"
        case .square:   return "squ"
        case .log:      return "log"
        case .exp:      return "exp"
        case .sweepUp:  return "swu"
        case .sweepDn:  return "swd"
        case .random:   return "rnd"
        }
    }

    func value(at phase: Double) -> Double {
        let p = phase.truncatingRemainder(dividingBy: 1.0)
        switch self {
        case .sine:
            return sin(2 * .pi * p)
        case .triangle:
            if p < 0.25 { return 4 * p }
            if p < 0.75 { return 2 - 4 * p }
            return 4 * p - 4
        case .saw:
            return 2 * p - 1
        case .square:
            return p < 0.5 ? 1 : -1
        case .log:
            if p < 0.5 {
                return 2 * Foundation.log1p(p * 2 * 9) / Foundation.log(10) - 1
            } else {
                return 1 - 2 * Foundation.log1p((p - 0.5) * 2 * 9) / Foundation.log(10)
            }
        case .exp:
            if p < 0.5 {
                return 2 * (pow(10, p * 2) - 1) / 9 - 1
            } else {
                return 1 - 2 * (pow(10, (p - 0.5) * 2) - 1) / 9
            }
        case .sweepUp:
            return sin(2 * .pi * 5 * p * p * p)
        case .sweepDn:
            let q = 1 - p
            return sin(2 * .pi * 5 * (1 - q * q * q))
        case .random:
            // Not called directly — AutomationEngine.evaluate() handles random with per-clip
            // stateful PRNG (xorshift64) so each clip and each cycle produces different values.
            return 0
        }
    }
}

// MARK: - Parameter

enum Parameter: String, CaseIterable, Identifiable, Codable {
    case volume, pan, mute, tempo
    case par1 = "par 1", par2 = "par 2", par3 = "par 3", par4 = "par 4"
    case envA = "env A", envD = "env D", envS = "env S", envR = "env R"
    case fx1 = "fx 1", fx2 = "fx 2", fx3 = "fx 3", fx4 = "fx 4"
    case lfo1 = "lfo 1", lfo2 = "lfo 2", lfo3 = "lfo 3", lfo4 = "lfo 4"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .volume: return "vol"
        case .pan:    return "pan"
        case .mute:   return "mut"
        case .tempo:  return "tmp"
        case .par1:   return "p1"
        case .par2:   return "p2"
        case .par3:   return "p3"
        case .par4:   return "p4"
        case .envA:   return "eA"
        case .envD:   return "eD"
        case .envS:   return "eS"
        case .envR:   return "eR"
        case .fx1:    return "fx1"
        case .fx2:    return "fx2"
        case .fx3:    return "fx3"
        case .fx4:    return "fx4"
        case .lfo1:   return "l1"
        case .lfo2:   return "l2"
        case .lfo3:   return "l3"
        case .lfo4:   return "l4"
        }
    }

    var isMasterOnly: Bool { self == .tempo }

    var isMasterCapable: Bool {
        switch self {
        case .tempo, .fx1, .fx2, .fx3, .fx4, .lfo1, .lfo2, .lfo3, .lfo4: return true
        default: return false
        }
    }
}

// MARK: - LfoClip

struct LfoClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var track: Int           // 0 = master, 1-4 = per track
    var parameter: Parameter
    var wave: LfoWave
    var rateTicks: Int
    var freeRatePeriod: Double? = nil  // non-nil → free rate (fixed seconds, not tempo-dependent)
    var depth: Double        // MIDI units (0-127), or BPM for tempo
    var centerValue: Double  // MIDI units (0-127), or BPM for tempo
    var inverted: Bool
    let loop: Bool           // set at creation; not editable
    var isEnabled: Bool = true   // false = paused; chip stays in list but sends no MIDI
    let originalValue: Double    // MIDI value of parameter captured at clip creation (for restore-on-disable)

    var rateIndex: Int {
        if let secs = freeRatePeriod {
            return FREE_RATE_SECONDS.min(by: { abs($0.value - secs) < abs($1.value - secs) })?.key ?? 9
        }
        return RATE_TICKS.first(where: { $0.value == rateTicks })?.key ?? 3
    }

    var rateLabel: String { rateChipLabel(for: rateIndex) }
}

// MARK: - Conversion helpers

func midiToUI(_ v: Double) -> Double {
    (v * 99 / 127).rounded(.down)
}

func uiToMidi(_ v: Double) -> Int {
    (Int(v) * 127 + 98) / 99
}
