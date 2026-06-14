import SwiftUI

struct TrackStripView: View {
    let track: Int
    @EnvironmentObject var app: AppState

    var body: some View {
        let color = C.track(track)
        let muted = app.mutes[track] ?? false
        let vol   = Binding(get: { app.volumes[track] ?? 90 },
                            set: { app.setVolume(track: track, value: $0) })
        let pan   = Binding(get: { app.pans[track] ?? 0 },
                            set: { app.setPan(track: track, value: $0) })

        VStack(spacing: 0) {
            // Mute button (colored header)
            Button {
                app.toggleMute(track: track)
            } label: {
                Text("\(track)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(muted ? color.opacity(0.25) : color)
                    .foregroundColor(muted ? color : .black)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            // Volume fader (fills available space)
            VolumeFaderView(value: vol) { app.setVolume(track: track, value: $0) }
                .frame(maxHeight: .infinity)

            // Volume value label
            Text("\(Int((app.volumes[track] ?? 90).rounded()))")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(C.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            Divider().background(C.bg3)

            // Pan knob + L/R labels
            HStack(spacing: 2) {
                Text("L")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(C.dim)
                PanKnobView(value: pan) { app.setPan(track: track, value: $0) }
                    .frame(width: 32, height: 32)
                Text("R")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(C.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TracksView: View {
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...4, id: \.self) { t in
                TrackStripView(track: t)
                if t < 4 {
                    Divider().background(C.bg3)
                }
            }
        }
    }
}
