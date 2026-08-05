import SwiftUI

struct TrackStripView: View {
    let track: Int
    var isLandscape: Bool = false
    @EnvironmentObject var app: AppState
    @Environment(\.metrics) private var m

    var body: some View {
        let color = C.track(track)
        let muted = app.mutes[track] ?? false
        // Devices without pan (the TP-7 is a recorder, not a mixer) hide the knob entirely
        // and let the fader take the space.
        let hasPan = app.profile.caps.hasPan
        let vol   = Binding(get: { app.volumes[track] ?? app.profile.defaultVolume },
                            set: { app.setVolume(track: track, value: $0) })
        let pan   = Binding(get: { app.pans[track] ?? 0 },
                            set: { app.setPan(track: track, value: $0) })

        VStack(spacing: 0) {

            // ── Mute button ──────────────────────────────────────────────────
            Button { app.toggleMute(track: track) } label: {
                Text("\(track)")
                    .font(.system(size: m.muteLabelFont, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, m.muteVPad)
                    .background(muted ? color.opacity(0.2) : color)
                    .foregroundColor(muted ? color : .black)
            }
            .buttonStyle(ImmediateButtonStyle())

            if isLandscape {
                // ── Landscape: pan knob left of fader, tops aligned ──────────
                let panSize = m.panKnobLandscape
                HStack(alignment: .center, spacing: 0) {
                    if hasPan {
                        PanKnobView(
                            value: pan,
                            onLiveChange: { app.controller.setPan(track: track, value: $0 + 64) }
                        ) { app.setPan(track: track, value: $0) }
                            .frame(width: panSize, height: panSize)
                            .padding(.leading, 6)
                            .padding(.trailing, 4)
                            .accessibilityIdentifier("panKnob\(track)")
                    }

                    VolumeFaderView(
                        value: vol,
                        onLiveChange: { app.controller.setVolume(track: track, value: uiToMidi($0)) }
                    ) { app.setVolume(track: track, value: $0) }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                // ── Portrait: pan above fader ────────────────────────────────
                if hasPan {
                    PanKnobView(
                        value: pan,
                        onLiveChange: { app.controller.setPan(track: track, value: $0 + 64) }
                    ) { app.setPan(track: track, value: $0) }
                        .padding(.horizontal, m.panHPad)
                        .frame(height: m.panKnobPortrait)
                        .padding(.top, m.panVPadTop)
                        .padding(.bottom, m.panVPadTop * 0.5)
                        .accessibilityIdentifier("panKnob\(track)")
                }

                VolumeFaderView(
                    value: vol,
                    onLiveChange: { app.controller.setVolume(track: track, value: uiToMidi($0)) }
                ) { app.setVolume(track: track, value: $0) }
                    .padding(.vertical, 8)
                    .frame(maxHeight: .infinity)
                Spacer(minLength: 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: "#181818"))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(C.border, lineWidth: 0.5))
        )
        .padding(.horizontal, m.trackGapUnit)
    }
}

struct TracksView: View {
    var isLandscape: Bool = false
    @EnvironmentObject private var app: AppState
    @Environment(\.metrics) private var m
    var body: some View {
        HStack(spacing: m.trackGapUnit) {
            ForEach(app.profile.trackIndices, id: \.self) { TrackStripView(track: $0, isLandscape: isLandscape) }
        }
        .padding(.horizontal, m.trackGapUnit)
        .padding(.vertical, 0)
    }
}
