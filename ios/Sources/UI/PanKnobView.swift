import SwiftUI

struct PanKnobView: View {
    @Binding var value: Int   // -63..+63, 0 = center
    let onChange: (Int) -> Void

    @GestureState private var drag: CGFloat = 0
    @State private var base: Int = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // Knob body
                Circle()
                    .fill(C.bg2)
                    .overlay(Circle().stroke(C.groove, lineWidth: 1))

                // Indicator line: orange at center, white off-center
                let angle = Double(value) / 63.0 * 135.0  // ±135° from 12 o'clock
                let rad   = (angle - 90) * .pi / 180
                let r     = size / 2 * 0.62
                let cx    = size / 2 + CGFloat(cos(rad)) * r
                let cy    = size / 2 + CGFloat(sin(rad)) * r
                Path { p in
                    p.move(to: CGPoint(x: size / 2, y: size / 2))
                    p.addLine(to: CGPoint(x: cx, y: cy))
                }
                .stroke(value == 0 ? C.orange : C.text, lineWidth: 2)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($drag) { g, state, _ in state = g.translation.height }
                    .onEnded { g in
                        let delta = Int(-g.translation.height / 1.2)
                        let newVal = max(-63, min(63, base + delta))
                        base = newVal
                        value = newVal
                        onChange(newVal)
                    }
            )
            .onAppear { base = value }
            .onChange(of: value) { newVal in
                if drag == 0 { base = newVal }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
