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

            // ── Mute button (colored header) ──────────────────────────────
            Button { app.toggleMute(track: track) } label: {
                Text("\(track)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(muted ? color.opacity(0.2) : color)
                    .foregroundColor(muted ? color : .black)
            }
            .buttonStyle(.plain)

            // ── Pan knob (large, prominent) ───────────────────────────────
            PanKnobView(value: pan) { app.setPan(track: track, value: $0) }
                .padding(.horizontal, 5)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)

            // L / R tick labels
            HStack {
                Text("L").font(.system(size: 7, weight: .medium)).foregroundColor(C.dim)
                Spacer()
                Text("R").font(.system(size: 7, weight: .medium)).foregroundColor(C.dim)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 6)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── Fader + split digit volume display ────────────────────────
            ZStack(alignment: .bottom) {
                // Thin fader (red line + diamond thumb) fills full height
                VolumeFaderView(value: vol) { app.setVolume(track: track, value: $0) }
                    .padding(.vertical, 8)

                // Split digits: "9" | red line | "0"  (desktop-style)
                // Wide gap so the fader line is clearly visible between the two digits
                HStack(alignment: .bottom, spacing: 0) {
                    Text(tensStr(v))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(C.text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 7)
                    Text(unitsStr(v))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(C.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 7)
                }
                .padding(.bottom, 8)
                .allowsHitTesting(false)   // pass touch events through to fader
            }
            .frame(maxHeight: .infinity)
        }
        // Card background matching the desktop track strip style
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: "#181818"))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(C.bg3, lineWidth: 0.5))
        )
        .padding(.horizontal, 2)
    }

    // "90" → tens = "9", units = "0"
    // " 5" → tens = " ", units = "5"
    private func tensStr(_ v: Int) -> String { v >= 10 ? String(v / 10) : " " }
    private func unitsStr(_ v: Int) -> String { String(v % 10) }
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
