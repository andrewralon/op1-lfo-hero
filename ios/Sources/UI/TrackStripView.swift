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
        let v     = Int((app.volumes[track] ?? 90).rounded())

        VStack(spacing: 0) {

            // ── Mute button (colored header) ──────────────────────────────────
            Button { app.toggleMute(track: track) } label: {
                Text("\(track)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(muted ? color.opacity(0.2) : color)
                    .foregroundColor(muted ? color : .black)
            }
            .buttonStyle(.plain)

            // ── Pan knob ──────────────────────────────────────────────────────
            PanKnobView(value: pan) { app.setPan(track: track, value: $0) }
                .padding(.horizontal, 12)
                .frame(height: 62)
                .padding(.vertical, 6)

            // No divider here — pan knob flows directly into fader area

            // ── Fader + 2-digit volume display (digits at center of fader) ────
            ZStack(alignment: .center) {
                VolumeFaderView(value: vol) { app.setVolume(track: track, value: $0) }
                    .padding(.vertical, 8)

                // Always 2 digits: "09", "90", "00"
                HStack(alignment: .bottom, spacing: 0) {
                    Text(tensDigit(v))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(C.text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 7)
                    Text(unitsDigit(v))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(C.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 7)
                }
                .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: "#181818"))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(C.bg3, lineWidth: 0.5))
        )
        .padding(.horizontal, 2)
    }

    // Always render two digits: 5 → "0" + "5", 90 → "9" + "0"
    private func tensDigit(_ v: Int) -> String { String(v / 10) }
    private func unitsDigit(_ v: Int) -> String { String(v % 10) }
}

struct TracksView: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { TrackStripView(track: $0) }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
