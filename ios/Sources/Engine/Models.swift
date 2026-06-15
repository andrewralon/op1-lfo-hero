import Foundation

let PPQN = 24

// Rate spinbox value (1-8) → ticks per LFO cycle
let RATE_TICKS: [Int: Int] = [
    1: 16 * PPQN,
    2: 8  * PPQN,
    3: 4  * PPQN,
    4: 2  * PPQN,
    5: PPQN,
    6: PPQN / 2,
    7: PPQN / 4,
    8: PPQN / 8,
]

let RATE_LABELS = ["16b", "8b", "4b", "2b", "1b", "2×", "4×", "8×"]

// MARK: - LfoWave

enum LfoWave: String, CaseIterable, Identifiable {
    case sine, triangle, saw, square, log, exp
    case sweepUp = "sweep up"
    case sweepDn = "sweep dn"
    case random

    var id: String { rawValue }

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
            // Caller must handle stateful random (AutomationEngine tracks step state)
            let step = Int(p * 8) % 8
            let h = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
            return Double(h) / Double(UInt32.max) * 2.0 - 1.0
        }
    }
}

// MARK: - Parameter

enum Parameter: String, CaseIterable, Identifiable {
    case volume, pan, mute, tempo
    case fx1 = "fx 1", fx2 = "fx 2", fx3 = "fx 3", fx4 = "fx 4"
    case lfo1 = "lfo 1", lfo2 = "lfo 2", lfo3 = "lfo 3", lfo4 = "lfo 4"

    var id: String { rawValue }

    var isMasterOnly: Bool { self == .tempo }

    var isMasterCapable: Bool {
        switch self {
        case .tempo, .fx1, .fx2, .fx3, .fx4, .lfo1, .lfo2, .lfo3, .lfo4: return true
        default: return false
        }
    }
}

// MARK: - LfoClip

struct LfoClip: Identifiable {
    let id = UUID()
    let track: Int           // 0 = master, 1-4 = per track
    let parameter: Parameter
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double        // MIDI units (0-127), or BPM for tempo
    let centerValue: Double  // MIDI units (0-127), or BPM for tempo
    let inverted: Bool
    let loop: Bool

    var rateLabel: String {
        let idx = RATE_TICKS.first(where: { $0.value == rateTicks })?.key ?? 3
        return RATE_LABELS[idx - 1]
    }

    var shortLabel: String {
        let t = track == 0 ? "M" : "tr\(track)"
        let inv = inverted ? " [inv]" : ""
        let loopMark = loop ? "∞" : "1×"
        return "\(wave.rawValue) · \(parameter.rawValue) · \(t) · \(rateLabel) \(loopMark)\(inv)"
    }
}

// MARK: - Conversion helpers

func midiToUI(_ v: Double) -> Double {
    (v * 99 / 127).rounded()
}

func uiToMidi(_ v: Double) -> Int {
    (Int(v.rounded()) * 127 + 98) / 99
}
