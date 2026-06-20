import SwiftUI

// Horizontal transport bar — buttons use maxHeight: .infinity so ContentView controls height
struct TransportBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        HStack(spacing: 0) {

            Spacer()

            TransBtn(symbol: "play.fill",  active: app.isPlaying, disabled: !app.isClockMaster) { app.play() }
            TransBtn(symbol: "stop.fill",  active: false)                                        { app.stop() }

            Sep()

            TransBtn(symbol: "arrow.left",  active: false) { app.tapePrev() }
            TransBtn(symbol: "arrow.right", active: false) { app.tapeNext() }

            Sep()

            // Clock master/slave toggle — whole group is blue (op1) or green (app)
            Button {
                if app.isClockMaster { app.disableClock() } else { app.enableClock() }
            } label: {
                VStack(spacing: -2) {
                    Image(systemName: "metronome")
                        .font(.system(size: isPad ? 52 : 32, weight: .regular))
                        .scaleEffect(x: 0.50, y: 1.05, anchor: .center)
                    Text(app.isClockMaster ? "app" : "op1")
                        .font(.system(size: isPad ? 22 : 13, weight: .semibold, design: .monospaced))
                }
                .frame(width: isPad ? 72 : 42)
                .frame(maxHeight: .infinity)
                .foregroundColor(app.isClockMaster ? C.green : C.track(1))
            }
            .buttonStyle(.plain)
            .padding(.leading, isPad ? 14 : 10)

            // BPM scrubber — compact fixed width with uniform 6pt margin
            BpmScrubber()
                .frame(width: isPad ? 130 : 82)
                .frame(maxHeight: .infinity)
                .padding(.vertical, isPad ? 8 : 6)
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
    @Environment(\.metrics) private var m
    @State  private var base: Double  = 120
    @GestureState private var isActive: Bool = false
    @State  private var editing     = false
    @State  private var editText    = ""
    @State  private var accumulated: Double = 0
    @State  private var prevHeight: CGFloat = 0
    @State  private var dragStarted = false
    @FocusState private var focused: Bool

    private let precisionScrubHalvingPt: Double = 40
    private func precisionFactor(_ ortho: CGFloat) -> Double {
        1.0 / max(1.0, Double(abs(ortho)) / precisionScrubHalvingPt)
    }

    private var live: Double {
        max(20, min(300, base - accumulated))
    }

    private var strokeColor: Color {
        if editing  { return C.green.opacity(0.8) }
        if isActive { return C.green.opacity(0.6) }
        return .clear
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(strokeColor, lineWidth: 1))

            if editing {
                TextField("", text: $editText)
                    .font(.system(size: m.transportBpmFont, weight: .bold, design: .monospaced))
                    .foregroundColor(C.green)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .onSubmit { commitEdit() }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("done") { commitEdit() }
                        }
                    }
            } else {
                let noData = !app.isClockMaster && app.bpm < 1.0
                let t = app.slaveTicksReceived
                let displayText = noData
                    ? (t == 0 ? "no clk" : t < 9 ? "sync.." : "err?\(t)")
                    : String(format: "%.1f", live)
                Text(displayText)
                    .font(.system(size: m.transportBpmFont, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? C.green : .white)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($isActive) { _, state, _ in
                    guard !editing else { return }
                    state = true
                }
                .onChanged { g in
                    guard !editing else { return }
                    guard dragStarted else {
                        dragStarted = true
                        prevHeight = g.translation.height
                        return
                    }
                    let dh = g.translation.height - prevHeight
                    accumulated += dh * 0.05 * precisionFactor(g.translation.width)
                    prevHeight = g.translation.height
                }
                .onEnded { _ in
                    guard !editing else { return }
                    let rounded = (live * 10).rounded() / 10
                    base = rounded
                    app.setBpm(rounded)
                    accumulated = 0
                    prevHeight = 0
                    dragStarted = false
                }
        )
        .onTapGesture(count: 2) { startEditing() }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in startEditing() }
        )
        .onAppear { base = app.bpm }
        .onChange(of: app.bpm) { _, v in if !isActive && !editing { base = v } }
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

// // Hold (≥350ms) scrubs tape continuously at 10 steps/sec; quick tap steps once.
// private struct TapeBtn: View {
//     let symbol: String
//     let action: () -> Void

//     @GestureState private var pressing = false
//     @State private var scrubTimer: DispatchSourceTimer? = nil
//     @State private var didScrub = false

//     var body: some View {
//         Image(systemName: symbol)
//             .font(.system(size: 20, weight: .regular))
//             .frame(width: 44)
//             .frame(maxHeight: .infinity)
//             .background(didScrub ? C.green.opacity(0.18) : Color.clear)
//             .foregroundColor(didScrub ? C.green : C.text)
//             .contentShape(Rectangle())
//             .gesture(
//                 DragGesture(minimumDistance: 0)
//                     .updating($pressing) { _, state, _ in state = true }
//                     .onEnded { _ in
//                         scrubTimer?.cancel()
//                         scrubTimer = nil
//                         if !didScrub { action() }
//                         didScrub = false
//                     }
//             )
//             .onChange(of: pressing) { _, isNowPressed in
//                 guard isNowPressed else { return }
//                 didScrub = false
//                 let t = DispatchSource.makeTimerSource(queue: .main)
//                 scrubTimer = t
//                 t.schedule(deadline: .now() + 0.35, repeating: 0.1)
//                 t.setEventHandler { [self] in
//                     didScrub = true
//                     action()
//                 }
//                 t.resume()
//             }
//             .onDisappear {
//                 scrubTimer?.cancel()
//                 scrubTimer = nil
//             }
//     }
// }

// MARK: - Transport column (landscape layouts: transport as 5th column beside the mixer)

struct TransportColumnView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.metrics) private var m

    var body: some View {
        VStack(spacing: 0) {
            // 2×2 button grid — top half
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TransColBtn(symbol: "play.fill",  active: app.isPlaying, disabled: !app.isClockMaster) { app.play() }
                    Rectangle().fill(C.bg3).frame(width: 1)
                    TransColBtn(symbol: "stop.fill",  active: false) { app.stop() }
                }
                .frame(maxHeight: .infinity)
                Rectangle().fill(C.bg3).frame(height: 1)
                HStack(spacing: 0) {
                    TransColBtn(symbol: "arrow.left",  active: false) { app.tapePrev() }
                    Rectangle().fill(C.bg3).frame(width: 1)
                    TransColBtn(symbol: "arrow.right", active: false) { app.tapeNext() }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(C.bg3).frame(height: 1)

            // Clock toggle + BPM — bottom half
            VStack(spacing: 4) {
                Button {
                    if app.isClockMaster { app.disableClock() } else { app.enableClock() }
                } label: {
                    VStack(spacing: -2) {
                        Image(systemName: "metronome")
                            .font(.system(size: m.transportMetronomeSize, weight: .regular))
                            .scaleEffect(x: 0.50, y: 1.05, anchor: .center)
                        Text(app.isClockMaster ? "app" : "op1")
                            .font(.system(size: m.transportMetronomeLabel, weight: .semibold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(app.isClockMaster ? C.green : C.track(1))
                }
                .buttonStyle(.plain)

                BpmScrubber()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
        }
        .background(C.bg2)
    }
}

private struct TransColBtn: View {
    let symbol: String
    let active: Bool
    var disabled: Bool = false
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: isPad ? 20 : 16, weight: .regular))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(active && !disabled ? C.green.opacity(0.18) : Color.clear)
                .foregroundColor(disabled ? C.dim : active ? C.green : C.text)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
    }
}

private struct TransBtn: View {
    let symbol: String
    var weight: Font.Weight = .regular
    let active: Bool
    var disabled: Bool = false
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: isPad ? 32 : 20, weight: weight))
                .frame(width: isPad ? 68 : 44)
                .frame(maxHeight: .infinity)
                .background(active && !disabled ? C.green.opacity(0.18) : Color.clear)
                .foregroundColor(disabled ? C.dim : active ? C.green : C.text)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
    }
}

private struct Sep: View {
    @Environment(\.horizontalSizeClass) private var hSize
    var body: some View {
        Rectangle()
            .fill(C.bg3)
            .frame(width: 1, height: hSize == .regular ? 44 : 26)
            .padding(.horizontal, 4)
    }
}
