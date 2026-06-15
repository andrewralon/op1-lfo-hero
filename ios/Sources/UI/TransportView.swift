import SwiftUI

// Horizontal transport bar — buttons use maxHeight: .infinity so ContentView controls height
struct TransportBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {

            Spacer()

            TransBtn(symbol: "play.fill",  active: app.isPlaying) { app.play() }
            TransBtn(symbol: "stop.fill",  active: false)          { app.stop() }

            Sep()

            TransBtn(symbol: "backward.end.fill", active: false) { app.tapePrev() }
            TransBtn(symbol: "forward.end.fill",  active: false) { app.tapeNext() }

            Sep()

            // Clock master/slave toggle — whole group is blue (op1) or green (app)
            Button {
                if app.isClockMaster { app.disableClock() } else { app.enableClock() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "metronome")
                        .font(.system(size: 32, weight: .regular))
                        .scaleEffect(x: 0.65, y: 1.05, anchor: .center)
                    Text(app.isClockMaster ? "app" : "op1")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .frame(width: 42)
                .frame(maxHeight: .infinity)
                .foregroundColor(app.isClockMaster ? C.green : C.track(1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            // BPM scrubber — compact fixed width with uniform 6pt margin
            BpmScrubber()
                .frame(width: 82)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            Spacer()
        }
        .background(C.bg2)
    }
}

// MARK: - BPM scrubber
// Drag up/down = ±0.1 BPM per point. Double-tap or long-press opens keyboard for direct entry.

private struct BpmScrubber: View {
    @EnvironmentObject var app: AppState
    @State  private var base: Double  = 120
    @GestureState private var drag: CGSize = .zero
    @State  private var editing   = false
    @State  private var editText  = ""
    @FocusState private var focused: Bool

    private func precisionFactor(_ ortho: CGFloat) -> Double {
        1.0 / max(1.0, Double(abs(ortho)) / 50.0)
    }

    private var live: Double {
        let delta = Double(drag.height) * 0.05 * precisionFactor(drag.width)
        return max(20, min(300, base - delta))
    }

    private var strokeColor: Color {
        if editing       { return C.green.opacity(0.8) }
        if drag != .zero { return C.green.opacity(0.6) }
        return .clear
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor, lineWidth: 1))

            if editing {
                TextField("", text: $editText)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(C.green)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .onSubmit { commitEdit() }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { commitEdit() }
                        }
                    }
            } else {
                Text(String(format: "%.1f", live))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(drag != .zero ? C.green : .white)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($drag) { g, state, _ in
                    guard !editing else { return }
                    state = g.translation
                }
                .onEnded { g in
                    guard !editing else { return }
                    let delta   = Double(g.translation.height) * 0.05 * precisionFactor(g.translation.width)
                    let raw     = max(20, min(300, base - delta))
                    let rounded = (raw * 10).rounded() / 10
                    base = rounded
                    app.setBpm(rounded)
                }
        )
        .onTapGesture(count: 2) { startEditing() }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in startEditing() }
        )
        .onAppear { base = app.bpm }
        .onChange(of: app.bpm) { _, v in if drag == .zero && !editing { base = v } }
    }

    private func startEditing() {
        guard !editing else { return }
        editText = String(format: "%.1f", live)
        editing  = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func commitEdit() {
        if let val = Double(editText) {
            let rounded = ((max(20, min(300, val))) * 10).rounded() / 10
            base = rounded
            app.setBpm(rounded)
        }
        editing = false
        focused = false
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
                .frame(width: 44)
                .frame(maxHeight: .infinity)
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
