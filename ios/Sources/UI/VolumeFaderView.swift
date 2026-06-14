import SwiftUI

struct VolumeFaderView: View {
    @Binding var value: Double  // 0-99
    let onChange: (Double) -> Void

    private let thumbH: CGFloat = 20
    private let trackW: CGFloat = 13

    @GestureState private var drag: CGFloat = 0
    @State private var base: Double = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let travel = max(1, h - thumbH)
            let display = max(0, min(99, base - Double(drag / travel * 99)))
            let thumbY  = CGFloat(1.0 - display / 99.0) * travel

            ZStack(alignment: .top) {
                // Track above thumb (dark)
                Capsule()
                    .fill(C.bg3)
                    .frame(width: trackW, height: max(2, thumbY + thumbH / 2))
                    .frame(maxWidth: .infinity)

                // Red fill below thumb
                let fillH = max(0, h - thumbY - thumbH / 2)
                if fillH > 0 {
                    Capsule()
                        .fill(C.red)
                        .frame(width: trackW, height: fillH)
                        .offset(y: thumbY + thumbH / 2)
                        .frame(maxWidth: .infinity)
                }

                // Thumb
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: trackW + 8, height: thumbH)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: thumbY)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($drag) { g, state, _ in state = g.translation.height }
                    .onEnded { g in
                        let delta = Double(g.translation.height / travel * 99)
                        let newVal = max(0, min(99, base - delta))
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
    }
}
