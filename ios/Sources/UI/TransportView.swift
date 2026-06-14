import SwiftUI

// Horizontal transport bar — matches Python desktop layout
// Fixed buttons: 44+44+sep+44+44+sep+44+sep+30+52+30 = 339pt; Spacer fills rest
struct TransportBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {

            // Play / Stop
            TransBtn(symbol: "play.fill",  active: app.isPlaying) { app.play() }
            TransBtn(symbol: "stop.fill",  active: false)          { app.stop() }

            Sep()

            // Tape navigation
            TransBtn(symbol: "backward.end.fill", active: false) { app.tapePrev() }
            TransBtn(symbol: "forward.end.fill",  active: false) { app.tapeNext() }

            Sep()

            // Clock master/slave toggle
            Button {
                if app.isClockMaster { app.disableClock() } else { app.enableClock() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "metronome")
                        .font(.system(size: 12))
                    Text(app.isClockMaster ? "mstr" : "slv")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                }
                .frame(width: 44, height: 50)
                .background(app.isClockMaster ? C.green.opacity(0.18) : Color.clear)
                .foregroundColor(app.isClockMaster ? C.green : C.dim)
            }
            .buttonStyle(.plain)

            Sep()

            // BPM: − value +
            Button { app.setBpm(app.bpm - 1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 50)
                    .background(C.bg3)
                    .foregroundColor(C.text)
            }
            .buttonStyle(.plain)

            Text(String(format: "%.1f", app.bpm))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(C.text)
                .frame(width: 52, height: 50)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Button { app.setBpm(app.bpm + 1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 50)
                    .background(C.bg3)
                    .foregroundColor(C.text)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .background(C.bg2)
    }
}

private struct TransBtn: View {
    let symbol: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 44, height: 50)
                .background(active ? C.green.opacity(0.18) : Color.clear)
                .foregroundColor(active ? C.green : C.text)
        }
        .buttonStyle(.plain)
    }
}

private struct Sep: View {
    var body: some View {
        Rectangle()
            .fill(C.bg3)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 4)
    }
}
