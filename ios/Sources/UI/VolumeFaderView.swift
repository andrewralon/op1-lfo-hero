import SwiftUI

// Fader includes the digit display so digits update live while dragging
// (display is computed from accumulated delta, updated every drag frame)
struct VolumeFaderView: View {
    @Binding var value: Double  // 0-99
    var onLiveChange: ((Double) -> Void)? = nil  // called every drag frame (MIDI only, no state update)
    let onChange: (Double) -> Void               // called on drag end (commits to AppState)
    @Environment(\.metrics) private var m

    private let trackW: CGFloat = 6
    private let thumbW: CGFloat = 20  // rhombus width
    private let thumbH: CGFloat = 12  // rhombus height (squished)

    private let precisionScrubHalvingPt: Double = 30
    private func precisionFactor(_ ortho: CGFloat) -> Double {
        1.0 / max(1.0, Double(abs(ortho)) / precisionScrubHalvingPt)
    }

    @GestureState private var isActive: Bool = false
    @State private var base: Double = 0
    @State private var accumulated: Double = 0
    @State private var prevHeight: CGFloat = 0
    @State private var dragStarted = false

    var body: some View {
        GeometryReader { geo in
            let h       = geo.size.height
            let travel  = max(1, h - thumbH)
            let display = max(0, min(99, base - accumulated))
            let thumbY  = CGFloat(1.0 - display / 99.0) * travel
            let center  = thumbY + thumbH / 2

            ZStack(alignment: .center) {

                // ── Fader track + thumb (top-anchored positioning) ──────────
                ZStack(alignment: .top) {
                    // Gray track — always exactly full height, never changes
                    Capsule()
                        .fill(Color(hex: "#484848"))
                        .frame(width: trackW, height: h)
                        .frame(maxWidth: .infinity)

                    // Red fill from thumb center down to bottom
                    let fillH = max(0, h - center)
                    if fillH > 0 {
                        Capsule()
                            .fill(C.red)
                            .frame(width: trackW, height: fillH)
                            .offset(y: center)
                            .frame(maxWidth: .infinity)
                    }

                    FaderDiamond()
                        .fill(Color.gray)
                        .overlay(FaderDiamond().stroke(Color.black, lineWidth: 1.5))
                        .frame(width: thumbW, height: thumbH)
                        .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
                        .offset(y: thumbY)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: geo.size.width, height: h)

                // ── Live digits — always 2 digits, update every drag frame ──
                HStack(alignment: .bottom, spacing: 0) {
                    Text(String(Int(display) / 10))
                        .font(.system(size: m.volValueFont, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 7)
                    Text(String(Int(display) % 10))
                        .font(.system(size: m.volValueFont, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 7)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($isActive) { _, state, _ in state = true }
                    .onChanged { g in
                        guard dragStarted else {
                            dragStarted = true
                            prevHeight = g.translation.height
                            return
                        }
                        let dh = g.translation.height - prevHeight
                        accumulated += Double(dh / travel * 99) * precisionFactor(g.translation.width)
                        prevHeight = g.translation.height
                        onLiveChange?(max(0, min(99, base - accumulated)))
                    }
                    .onEnded { _ in
                        let newVal = max(0, min(99, base - accumulated))
                        base = newVal
                        value = newVal
                        onChange(newVal)
                        accumulated = 0
                        prevHeight = 0
                        dragStarted = false
                    }
            )
            .onAppear { base = value }
            .onChange(of: value) { _, newVal in if !isActive { base = newVal } }
        }
    }
}

private struct FaderDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
