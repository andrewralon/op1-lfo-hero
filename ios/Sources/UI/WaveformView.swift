import SwiftUI

struct WaveformView: View {
    let wave: LfoWave
    let rateTicks: Int
    let depth: Double    // 0-99 display units
    let colors: [Color]  // 1 color = solid line; 2+ = banded segments per color
    var inverted: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let nCycles = Double(8 * PPQN) / Double(rateTicks)
            let w = size.width
            let h = size.height
            let midY = h / 2
            let amplitude = midY * 0.88
            let steps = Int(w * 1.5)

            // Precompute all (px, py) points
            var points = [(CGFloat, CGFloat)]()
            points.reserveCapacity(steps + 1)
            var prevStep = -1
            var stepY: Double = 0

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
                points.append((CGFloat(t) * w, midY - CGFloat(y) * amplitude))
            }

            // Center line
            var center = Path()
            center.move(to: CGPoint(x: 0, y: midY))
            center.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(center, with: .color(C.groove), lineWidth: 1)

            let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

            if colors.count == 1 {
                var path = Path()
                for (i, (px, py)) in points.enumerated() {
                    if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                    else       { path.addLine(to: CGPoint(x: px, y: py)) }
                }
                ctx.stroke(path, with: .color(colors[0]), style: strokeStyle)
            } else {
                // Banded: alternating color segments every segW points along x
                let segW: CGFloat = 18
                let n = colors.count
                for (ci, color) in colors.enumerated() {
                    var path = Path()
                    var open = false
                    for (_, (px, py)) in points.enumerated() {
                        let active = (Int(px / segW) % n) == ci
                        if active {
                            if !open { path.move(to: CGPoint(x: px, y: py)); open = true }
                            else     { path.addLine(to: CGPoint(x: px, y: py)) }
                        } else {
                            open = false
                        }
                    }
                    ctx.stroke(path, with: .color(color), style: strokeStyle)
                }
            }
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
    var inverted: Bool = false
    var colors: [Color] = [C.green]

    var body: some View {
        if lfos.isEmpty {
            WaveformView(wave: wave, rateTicks: rateTicks, depth: depth,
                         colors: colors, inverted: inverted)
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
