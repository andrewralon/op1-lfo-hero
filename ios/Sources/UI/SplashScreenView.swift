import SwiftUI

// Shown briefly at launch: app icon, name, and animated LFO waves for fun.
struct SplashScreenView: View {
    @State private var wavePhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            // Scale proportionally to screen size relative to baseline iPhone dimensions.
            // Works for any device without branching — larger screens get larger elements.
            let s = min(geo.size.width / 390, geo.size.height / 844)
            VStack(spacing: 22 * s) {
                Spacer()

                // Full-resolution 1024×1024 source art (not the small system-generated icon
                // file, which looks blurry once stretched up to this size).
                Image("AppIconArt")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 140 * s, height: 140 * s)
                    .clipShape(RoundedRectangle(cornerRadius: 28 * s))
                    .overlay(RoundedRectangle(cornerRadius: 28 * s).stroke(C.border, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

                Text("op1 lfo hero")
                    .font(.system(size: 40 * s, weight: .bold, design: .monospaced))
                    .foregroundColor(C.white)

                Text("make music fun")
                    .font(.system(size: 18 * s, weight: .medium, design: .monospaced))
                    .foregroundColor(C.text)

                ColorfulSplashWave(phase: wavePhase)
                    .frame(width: 240 * s, height: 52 * s)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(C.bg)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }
        }
    }
}

// Multi-colored segmented sine wave — each segment cycles through the 4 track colors.
struct ColorfulSplashWave: View {
    let phase: Double
    private let colors: [Color] = [C.track(1), C.track(2), C.track(3), C.track(4)]

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let steps = max(1, Int(size.width))
            let segLen = max(1, steps / 10)

            var pts = [CGPoint]()
            pts.reserveCapacity(steps + 1)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let y = sin((t * 2 + phase) * 2 * .pi)
                pts.append(CGPoint(x: CGFloat(t) * size.width, y: midY - CGFloat(y) * midY * 0.85))
            }

            var start = 0; var ci = 0
            while start < pts.count - 1 {
                let end = min(start + segLen, pts.count - 1)
                var seg = Path()
                for i in start...end {
                    if i == start { seg.move(to: pts[i]) } else { seg.addLine(to: pts[i]) }
                }
                ctx.stroke(seg, with: .color(colors[ci % colors.count]),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ci += 1
                start = end
            }
        }
    }
}

// Solid green sine wave that scrolls continuously.
private struct SplashWave: View {
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let steps = max(1, Int(size.width))

            var path = Path()
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let y = sin((t * 2 + phase) * 2 * .pi)
                let pt = CGPoint(x: CGFloat(t) * size.width, y: midY - CGFloat(y) * midY * 0.85)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(C.green), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
