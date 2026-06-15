import SwiftUI

// Draws one waveform path per (color, inverted) pair, overlaid on a shared canvas.
struct WaveformView: View {
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double
    let tracks: [(color: Color, inverted: Bool)]

    var body: some View {
        Canvas { ctx, size in
            let nCycles = Double(8 * PPQN) / Double(rateTicks)
            let w = size.width
            let h = size.height
            let midY = h / 2
            let amplitude = midY * 0.88
            let steps = Int(w * 1.5)
            let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

            var center = Path()
            center.move(to: CGPoint(x: 0, y: midY))
            center.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

            for (color, inverted) in tracks {
                var path = Path()
                var prevStep = -1
                var stepY = 0.0
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let phase = (t * nCycles).truncatingRemainder(dividingBy: 1.0)
                    var y: Double
                    if wave == .random {
                        let step = Int(phase * 8) % 8
                        if step != prevStep {
                            let hh = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
                            stepY = Double(hh) / Double(UInt32.max) * 2.0 - 1.0
                            prevStep = step
                        }
                        y = stepY
                    } else {
                        y = wave.value(at: phase)
                    }
                    if inverted { y = -y }
                    let px = CGFloat(t) * w
                    let py = midY - CGFloat(y) * amplitude
                    if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                    else       { path.addLine(to: CGPoint(x: px, y: py)) }
                }
                ctx.stroke(path, with: .color(color), style: strokeStyle)
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
                    let path = buildPath(lfo: lfo, size: size)
                    ctx.stroke(path, with: .color(c),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
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
                let step = Int(phase * 8) % 8
                if step != prevStep {
                    let h = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
                    stepY = Double(h) / Double(UInt32.max) * 2.0 - 1.0
                    prevStep = step
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
