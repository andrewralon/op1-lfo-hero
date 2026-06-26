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
            let nCycles = Double(8 * PPQN) / Double(rateTicks)
            let w       = size.width
            let midY    = size.height / 2
            let amp     = midY * 0.88
            let steps   = Int(w * 1.5)
            // Target ~60 pt per color segment; steps are ~1.5 per pt so multiply directly.
            let segLen  = max(1, Int(waveformSegmentPt * Double(steps) / Double(w)))

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

                if group.count == 1 {
                    // Single track — one solid path
                    var path = Path()
                    for (i, pt) in pts.enumerated() {
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    ctx.stroke(path, with: .color(group[0].color), style: solidStroke)
                } else {
                    // Multiple tracks — solid alternating color segments, no gaps.
                    // Each segment starts at the last point of the previous one so
                    // there is never a break in the line.
                    var start = 0; var ci = 0
                    while start < pts.count - 1 {
                        let end = min(start + segLen, pts.count - 1)
                        var path = Path()
                        for i in start...end {
                            if i == start { path.move(to: pts[i]) }
                            else          { path.addLine(to: pts[i]) }
                        }
                        ctx.stroke(path, with: .color(group[ci % group.count].color),
                                   style: solidStroke)
                        ci    += 1
                        start  = end   // overlap by 1 pt — prevents pixel-level gaps
                    }
                }
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

    var body: some View {
        if lfos.isEmpty {
            WaveformView(wave: wave, rateTicks: rateTicks, depth: depth, tracks: tracks)
        } else {
            Canvas { ctx, size in
                let midY = size.height / 2
                var center = Path()
                center.move(to: CGPoint(x: 0, y: midY))
                center.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

                for lfo in lfos {
                    let c = lfo.track == 0 ? C.green : C.track(lfo.track)
                    ctx.stroke(buildPath(lfo: lfo, size: size), with: .color(c),
                               style: solidStroke)
                }
            }
            .background(C.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func buildPath(lfo: LfoClip, size: CGSize) -> Path {
        let nCycles = Double(8 * PPQN) / Double(lfo.rateTicks)
        let amplitude = size.height / 2 * 0.88
        let steps = Int(size.width * 1.5)
        var path = Path()
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
            let px = CGFloat(t) * size.width
            let py = size.height / 2 - CGFloat(y) * amplitude
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
            else       { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        return path
    }
}

private let solidStroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
private let waveformSegmentPt: Double = 50  // pt per color segment when multiple same-state tracks are shown
