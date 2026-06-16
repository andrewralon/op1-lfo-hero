import SwiftUI

// Shown briefly at launch: app icon, name, and a little animated LFO wave for fun.
struct SplashScreenView: View {
    @State private var wavePhase: Double = 0

    private let letterColors: [Color] = [C.track(1), C.track(2), C.track(3), C.track(4)]

    private var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last
        else { return nil }
        return UIImage(named: name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Group {
                if let appIcon {
                    Image(uiImage: appIcon).resizable()
                } else {
                    Rectangle().fill(C.bg3)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(C.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)

            HStack(spacing: 0) {
                ForEach(Array("op1 lfo hero".enumerated()), id: \.offset) { i, ch in
                    Text(String(ch))
                        .foregroundColor(ch == " " ? .clear : letterColors[i % letterColors.count])
                }
            }
            .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text("for OP-1 Field")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(C.dim)

            SplashWave(phase: wavePhase)
                .frame(width: 170, height: 36)
                .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.bg)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }
        }
    }
}

// Small multi-colored sine wave that scrolls continuously — a wink at the LFO waveform
// preview elsewhere in the app.
private struct SplashWave: View {
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
