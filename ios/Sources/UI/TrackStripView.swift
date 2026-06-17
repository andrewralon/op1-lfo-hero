import SwiftUI

struct TrackStripView: View {
    let track: Int
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        let color = C.track(track)
        let muted = app.mutes[track] ?? false
        let vol   = Binding(get: { app.volumes[track] ?? 90 },
                            set: { app.setVolume(track: track, value: $0) })
        let pan   = Binding(get: { app.pans[track] ?? 0 },
                            set: { app.setPan(track: track, value: $0) })

        VStack(spacing: 0) {

            // ── Mute button ───────────────────────────────────────────────────
            Button { app.toggleMute(track: track) } label: {
                Text("\(track)")
                    .font(.system(size: isPad ? 26 : C.trackLabelSize, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isPad ? 8 : 5)
                    .background(muted ? color.opacity(0.2) : color)
                    .foregroundColor(muted ? color : .black)
            }
            .buttonStyle(ImmediateButtonStyle())

            // ── Pan knob ──────────────────────────────────────────────────────
            PanKnobView(
                value: pan,
                onLiveChange: { app.controller.setPan(track: track, value: $0 + 64) }
            ) { app.setPan(track: track, value: $0) }
                .padding(.horizontal, 12)
                .frame(height: isPad ? 100 : 62)
                .padding(.top, isPad ? 14 : 10)
                .padding(.bottom, isPad ? 7 : 5)

            // ── Fader (digits live-update inside VolumeFaderView) ─────────────
            VolumeFaderView(
                value: vol,
                onLiveChange: { app.controller.setVolume(track: track, value: uiToMidi($0)) }
            ) { app.setVolume(track: track, value: $0) }
                .padding(.vertical, 8)
                .frame(maxHeight: isPad ? 220 : .infinity)
            Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: "#181818"))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(C.border, lineWidth: 0.5))
        )
        .padding(.horizontal, 2)
    }
}

struct TracksView: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { TrackStripView(track: $0) }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
    }
}
