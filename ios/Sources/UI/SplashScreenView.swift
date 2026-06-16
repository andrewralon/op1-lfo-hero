import SwiftUI

// Shown briefly at launch: app icon, name, and a little animated LFO wave for fun.
struct SplashScreenView: View {
    @State private var wavePhase: Double = 0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            // Full-resolution 1024×1024 source art (not the small system-generated icon
            // file, which looks blurry once stretched up to this size).
            Image("AppIconArt")
                .resizable()
                .interpolation(.high)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(C.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

            Text("op1 lfo hero")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(C.white)

            Spacer()

            SplashWave(phase: wavePhase)
                .frame(width: 240, height: 52)
                .padding(.top, 6)

            Text("make music fun")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(C.dim)

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

// Small green sine wave that scrolls continuously — a wink at the LFO waveform
// preview elsewhere in the app.
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
