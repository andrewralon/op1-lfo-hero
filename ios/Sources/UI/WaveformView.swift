import SwiftUI

// Draws one waveform path per (color, inverted) pair, overlaid on a shared canvas.
// When multiple tracks share the same inversion state (identical shape), a single
// path is drawn with alternating solid color segments — no gaps, no transparency.
struct WaveformView: View {
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double
    let tracks: [(color: Color, inverted: Bool)]

    var body: some View {
        Canvas { ctx, size in
            let nCycles = Double(8 * PPQN) / (Double(rateTicks) * wave.cycleMultiplier)
            let w       = size.width
            let midY    = size.height / 2
            let amp     = midY * 0.88
            let steps   = Int(w * 1.5)
            let waveStroke = StrokeStyle(lineWidth: size.height * 0.012, lineCap: .round, lineJoin: .round)

            var center = Path()
            center.move(to: CGPoint(x: 0, y: midY))
            center.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

            // Process normal and inverted groups independently
            let normalGroup   = tracks.filter { !$0.inverted }
            let invertedGroup = tracks.filter {  $0.inverted }

            for (inverted, group) in [(false, normalGroup), (true, invertedGroup)] {
                guard !group.isEmpty else { continue }

                // Build shared point array — same shape for every track in this group
                var pts = [CGPoint]()
                pts.reserveCapacity(steps + 1)
                var prevStep = -1; var stepY = 0.0
                for i in 0...steps {
                    let t     = Double(i) / Double(steps)
                    let phase = (t * nCycles).truncatingRemainder(dividingBy: 1.0)
                    var y: Double
                    if wave == .random {
                        let globalStep = Int(t * nCycles * 2)
                        if globalStep != prevStep {
                            let hh = UInt32(bitPattern: Int32(bitPattern: UInt32(globalStep + 1) &* 2654435761))
                            stepY = Double(hh) / Double(UInt32.max) * 2.0 - 1.0
                            prevStep = globalStep
                        }
                        y = stepY
                    } else {
                        y = wave.value(at: phase)
                    }
                    if inverted { y = -y }
                    pts.append(CGPoint(x: CGFloat(t) * w,
                                      y: midY - CGFloat(y) * amp))
                }

                strokeStriped(&ctx, points: pts, colors: group.map(\.color), style: waveStroke)
            }
        }
        .background(C.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// Editor-state preview (lfos empty) or active-LFO overlay.
struct MultiWaveformView: View {
    let lfos: [LfoClip]
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double
    var tracks: [(Color, Bool)] = [(C.green, false)]
    var bpm: Double = 120.0  // used to display free-rate clip waveforms

    var body: some View {
        if lfos.isEmpty {
            WaveformView(wave: wave, rateTicks: rateTicks, depth: depth, tracks: tracks)
        } else {
            Canvas { ctx, size in
                let midY = size.height / 2
                let waveStroke = StrokeStyle(lineWidth: size.height * 0.012, lineCap: .round, lineJoin: .round)
                var center = Path()
                center.move(to: CGPoint(x: 0, y: midY))
                center.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

                // LFOs that draw the same curve (same wave, speed and direction, whatever the
                // parameter or track) would paint over one another and leave only the last color
                // visible, so they share one path that alternates their colors, as the editor
                // curve does for several selected tracks.
                var order: [CurveKey] = []
                var colors: [CurveKey: [Color]] = [:]
                var sample: [CurveKey: LfoClip] = [:]
                for lfo in lfos {
                    let key = CurveKey(wave: lfo.wave, ticks: displayTicks(lfo), inverted: lfo.inverted)
                    if colors[key] == nil { order.append(key); sample[key] = lfo }
                    let c = lfo.track == 0 ? C.green : C.track(lfo.track)
                    if !(colors[key] ?? []).contains(c) { colors[key, default: []].append(c) }
                }
                for key in order {
                    guard let lfo = sample[key], let cs = colors[key] else { continue }
                    strokeStriped(&ctx, points: buildPoints(lfo: lfo, size: size), colors: cs,
                                  style: waveStroke)
                }
            }
            .background(C.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private struct CurveKey: Hashable {
        let wave: LfoWave
        let ticks: Int
        let inverted: Bool
    }

    private func displayTicks(_ lfo: LfoClip) -> Int {
        if let secs = lfo.freeRatePeriod {
            return max(1, Int(secs * max(AppState.minBpm, bpm) * Double(PPQN) / 60.0))
        }
        return lfo.rateTicks
    }

    private func buildPoints(lfo: LfoClip, size: CGSize) -> [CGPoint] {
        let nCycles = Double(8 * PPQN) / (Double(displayTicks(lfo)) * lfo.wave.cycleMultiplier)
        let amplitude = size.height / 2 * 0.88
        let steps = Int(size.width * 1.5)
        var pts = [CGPoint]()
        pts.reserveCapacity(steps + 1)
        var prevStep = -1; var stepY = 0.0

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let phase = (t * nCycles).truncatingRemainder(dividingBy: 1.0)
            var y: Double
            if lfo.wave == .random {
                let globalStep = Int(t * nCycles * 2)
                if globalStep != prevStep {
                    let h = UInt32(bitPattern: Int32(bitPattern: UInt32(globalStep + 1) &* 2654435761))
                    stepY = Double(h) / Double(UInt32.max) * 2.0 - 1.0
                    prevStep = globalStep
                }
                y = stepY
            } else {
                y = lfo.wave.value(at: phase)
            }
            if lfo.inverted { y = -y }
            pts.append(CGPoint(x: CGFloat(t) * size.width,
                               y: size.height / 2 - CGFloat(y) * amplitude))
        }
        return pts
    }
}

/// Strokes `points` in one color, or in solid alternating segments when several tracks share the
/// curve. Each segment starts at the last point of the previous one so there is never a break.
private func strokeStriped(_ ctx: inout GraphicsContext, points pts: [CGPoint], colors: [Color],
                           style: StrokeStyle) {
    guard pts.count > 1, let first = colors.first else { return }
    if colors.count == 1 {
        var path = Path()
        for (i, pt) in pts.enumerated() {
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(first), style: style)
        return
    }
    // Target ~50 pt per color segment; points are ~1.5 per pt.
    let segLen = max(1, Int(waveformSegmentPt * 1.5))
    var start = 0; var ci = 0
    while start < pts.count - 1 {
        let end = min(start + segLen, pts.count - 1)
        var path = Path()
        for i in start...end {
            if i == start { path.move(to: pts[i]) } else { path.addLine(to: pts[i]) }
        }
        ctx.stroke(path, with: .color(colors[ci % colors.count]), style: style)
        ci += 1
        start = end   // overlap by 1 pt — prevents pixel-level gaps
    }
}

private let waveformSegmentPt: Double = 50  // pt per color segment when multiple same-state tracks are shown
