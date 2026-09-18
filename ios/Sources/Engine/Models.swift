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

// MARK: - LfoClip

/// One running LFO. `paramId` and `deviceId` reference a `ParamSpec` in a `DeviceProfile`
/// rather than naming a parameter directly, so the same clip type serves every device.
///
/// This is persisted, so `init(from:)` below is hand-written: it defaults every missing key
/// instead of throwing. Swift's synthesized `Decodable` ignores property default values, which
/// means a synthesized decoder turns any added field into "all saved clips silently vanish".
struct LfoClip: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Which device profile `paramId` belongs to — guards against dispatching a clip to the
    /// wrong hardware across a profile switch.
    var deviceId: String = "op1"
    var track: Int           // 0 = master, 1...trackCount = per track
    var paramId: String      // ParamSpec.id within `deviceId`'s profile
    var wave: LfoWave
    var rateTicks: Int
    var freeRatePeriod: Double? = nil  // non-nil → free rate (fixed seconds, not tempo-dependent)
    var depth: Double        // MIDI units (0-127), or BPM for tempo
    var centerValue: Double  // MIDI units (0-127), or BPM for tempo
    var inverted: Bool
    let loop: Bool           // set at creation; not editable
    var isEnabled: Bool = true   // false = paused; chip stays in list but sends no MIDI
    let originalValue: Double    // MIDI value of parameter captured at clip creation (for restore-on-disable)

    init(id: UUID = UUID(), deviceId: String = "op1", track: Int, paramId: String,
         wave: LfoWave, rateTicks: Int, freeRatePeriod: Double? = nil,
         depth: Double, centerValue: Double, inverted: Bool, loop: Bool,
         isEnabled: Bool = true, originalValue: Double) {
        self.id = id
        self.deviceId = deviceId
        self.track = track
        self.paramId = paramId
        self.wave = wave
        self.rateTicks = rateTicks
        self.freeRatePeriod = freeRatePeriod
        self.depth = depth
        self.centerValue = centerValue
        self.inverted = inverted
        self.loop = loop
        self.isEnabled = isEnabled
        self.originalValue = originalValue
    }

    enum CodingKeys: String, CodingKey {
        // "parameter" is the pre-multi-device key; still read so old saves survive.
        case id, deviceId, track, paramId, parameter, wave, rateTicks, freeRatePeriod
        case depth, centerValue, inverted, loop, isEnabled, originalValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = (try? c.decodeIfPresent(UUID.self,   forKey: .id))    .flatMap { $0 } ?? UUID()
        deviceId = (try? c.decodeIfPresent(String.self, forKey: .deviceId)).flatMap { $0 } ?? "op1"
        track    = (try? c.decodeIfPresent(Int.self,    forKey: .track)) .flatMap { $0 } ?? 1
        // New key first, then the legacy `parameter` raw string. The OP-1 profile's parameter
        // ids are deliberately those same raw values, so no translation table is needed.
        paramId  = (try? c.decodeIfPresent(String.self, forKey: .paramId)).flatMap { $0 }
                ?? (try? c.decodeIfPresent(String.self, forKey: .parameter)).flatMap { $0 }
                ?? "volume"
        wave     = (try? c.decodeIfPresent(LfoWave.self, forKey: .wave)).flatMap { $0 } ?? .sine
        rateTicks      = (try? c.decodeIfPresent(Int.self,    forKey: .rateTicks)).flatMap { $0 } ?? PPQN
        freeRatePeriod = (try? c.decodeIfPresent(Double.self, forKey: .freeRatePeriod)).flatMap { $0 }
        depth          = (try? c.decodeIfPresent(Double.self, forKey: .depth)).flatMap { $0 } ?? 10
        centerValue    = (try? c.decodeIfPresent(Double.self, forKey: .centerValue)).flatMap { $0 } ?? 64
        inverted       = (try? c.decodeIfPresent(Bool.self,   forKey: .inverted)).flatMap { $0 } ?? false
        loop           = (try? c.decodeIfPresent(Bool.self,   forKey: .loop)).flatMap { $0 } ?? true
        isEnabled      = (try? c.decodeIfPresent(Bool.self,   forKey: .isEnabled)).flatMap { $0 } ?? true
        originalValue  = (try? c.decodeIfPresent(Double.self, forKey: .originalValue)).flatMap { $0 }
                      ?? centerValue
    }

    /// Hand-written because `CodingKeys` carries the legacy `parameter` key, which has no
    /// property to synthesize from. Only the current keys are written.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(track, forKey: .track)
        try c.encode(paramId, forKey: .paramId)
        try c.encode(wave, forKey: .wave)
        try c.encode(rateTicks, forKey: .rateTicks)
        try c.encodeIfPresent(freeRatePeriod, forKey: .freeRatePeriod)
        try c.encode(depth, forKey: .depth)
        try c.encode(centerValue, forKey: .centerValue)
        try c.encode(inverted, forKey: .inverted)
        try c.encode(loop, forKey: .loop)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(originalValue, forKey: .originalValue)
    }

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
