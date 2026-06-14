import SwiftUI

struct TransportView: View {
    @EnvironmentObject var app: AppState
    @State private var bpmText = ""
    @State private var editingBpm = false

    var body: some View {
        VStack(spacing: 0) {
            // Play
            TransBtn(symbol: "play.fill",  active: app.isPlaying)  { app.play() }
            TransBtn(symbol: "stop.fill",  active: false)           { app.stop() }

            Divider().background(C.bg3)

            // Tape nav
            TransBtn(symbol: "backward.end.fill", active: false) { app.tapePrev() }
            TransBtn(symbol: "forward.end.fill",  active: false) { app.tapeNext() }

            Divider().background(C.bg3)

            // Clock master toggle
            Button {
                if app.isClockMaster { app.disableClock() } else { app.enableClock() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "metronome")
                        .font(.system(size: 12))
                    Text(app.isClockMaster ? "mstr" : "slv")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(app.isClockMaster ? C.green.opacity(0.18) : C.bg3)
                .foregroundColor(app.isClockMaster ? C.green : C.dim)
            }
            .buttonStyle(.plain)

            Divider().background(C.bg3)

            // BPM display + ±1 nudge
            VStack(spacing: 2) {
                Button { app.setBpm(app.bpm + 1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(C.bg3)
                        .foregroundColor(C.text)
                }
                .buttonStyle(.plain)

                Text(String(format: "%.1f", app.bpm))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(C.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)

                Button { app.setBpm(app.bpm - 1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(C.bg3)
                        .foregroundColor(C.text)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            Divider().background(C.bg3)

            // Octave shift
            Button { app.controller.octaveUp()   } label: {
                Image(systemName: "arrow.up.square").font(.system(size: 13))
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundColor(C.dim)
            Button { app.controller.octaveDown() } label: {
                Image(systemName: "arrow.down.square").font(.system(size: 13))
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundColor(C.dim)

            Spacer()
        }
        .background(C.bg)
    }
}

private struct TransBtn: View {
    let symbol: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? C.green.opacity(0.18) : Color.clear)
                .foregroundColor(active ? C.green : C.text)
        }
        .buttonStyle(.plain)
    }
}
