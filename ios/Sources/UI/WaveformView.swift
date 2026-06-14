import SwiftUI

struct WaveformView: View {
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double    // 0-99 display units
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let nCycles = Double(8 * PPQN) / Double(rateTicks)
            let w = size.width
            let h = size.height
            let midY = h / 2
            let amplitude = midY * 0.82 * (depth / 99.0)
            let steps = Int(w * 1.5)

            var path = Path()
            var prevStep = -1
            var stepY: Double = 0

            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let phase = t * nCycles
                let p = phase.truncatingRemainder(dividingBy: 1.0)

                let y: Double
                if wave == .random {
                    let step = Int(p * 8) % 8
                    if step != prevStep {
                        let hh = UInt32(bitPattern: Int32(bitPattern: UInt32(step + 1) &* 2654435761))
                        stepY = Double(hh) / Double(UInt32.max) * 2.0 - 1.0
                        prevStep = step
                    }
                    y = stepY
                } else {
                    y = wave.value(at: p)
                }

                let px = CGFloat(t) * w
                let py = midY - CGFloat(y) * amplitude

                if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                else       { path.addLine(to: CGPoint(x: px, y: py)) }
            }

            // Center line
            var center = Path()
            center.move(to: CGPoint(x: 0, y: midY))
            center.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .background(C.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// Preview with multiple active LFOs overlaid
struct MultiWaveformView: View {
    let lfos: [LfoClip]  // empty = show editor-state wave
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double

    var body: some View {
        if lfos.isEmpty {
            WaveformView(wave: wave, rateTicks: rateTicks, depth: depth, color: C.green)
        } else {
            Canvas { ctx, size in
                let midY = size.height / 2
                var center = Path()
                center.move(to: CGPoint(x: 0, y: midY))
                center.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

                for lfo in lfos {
                    let color = lfo.track == 0 ? C.green : C.track(lfo.track)
                    let path  = buildPath(lfo: lfo, size: size)
                    ctx.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            .background(C.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func buildPath(lfo: LfoClip, size: CGSize) -> Path {
        let nCycles = Double(8 * PPQN) / Double(lfo.rateTicks)
        let amplitude = size.height / 2 * 0.82
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
