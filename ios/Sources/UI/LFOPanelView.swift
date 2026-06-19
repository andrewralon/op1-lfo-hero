import SwiftUI

private let ctrlFontSizePhone: CGFloat = 15  // base size; all control elements scale from this via ctrlBase

// Propagates scale factor from LFOPanelView down to CompactPicker and ScrubValue.
// 1.0 = phone, 1.6 = iPad landscape, 1.8 = iPad portrait.
private struct ControlScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1.0 }
extension EnvironmentValues {
    fileprivate var controlScale: CGFloat {
        get { self[ControlScaleKey.self] }
        set { self[ControlScaleKey.self] = newValue }
    }
}

struct LFOPanelView: View {
    var needsCombinedLfoRow: Bool = false  // true for iPad (both) + all landscape
    var needsSideBySide: Bool = false      // true for iPad (both) + all landscape

    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedLfoID: UUID? = nil
    @State private var showDeleteConfirm = false
    @State private var showHelp = false
    @State private var showSettings = false

    private var isPad: Bool { hSize == .regular }
    private var isIpadPortrait: Bool { isPad && !needsCombinedLfoRow }
    // All control element sizes derive from this; avoids separate isPad ? X : Y pairs.
    private var ctrlBase: CGFloat { isIpadPortrait ? 1.8 : isPad ? 1.6 : 1.0 }

    private var previewLfos: [LfoClip] {
        if let id = selectedLfoID, let lfo = app.activeLfos.first(where: { $0.id == id }) {
            return [lfo]
        }
        return []
    }

    // Snaps lfoCenter to the OP-1's current value for the selected parameter/track.
    private func snapCenter() {
        if app.lfoParam == .tempo {
            app.lfoCenter = app.bpm
            return
        }
        guard let track = (1...4).first(where: { (app.trackOn[$0] ?? 0) > 0 }) else { return }
        switch app.lfoParam {
        case .volume:
            app.lfoCenter = app.volumes[track] ?? 90
        case .pan:
            app.lfoCenter = midiToUI(Double((app.pans[track] ?? 0) + 64))
        case .mute:
            app.lfoCenter = (app.mutes[track] ?? false) ? 99 : 0
        default:
            break  // fx/lfo params not tracked in AppState
        }
    }

    private func cycleNext<T: CaseIterable & Equatable>(_ value: T) -> T {
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: value) else { return value }
        return all[(idx + 1) % all.count]
    }

    // (color, isInverted) per enabled track/master — each draws its own waveform
    private var waveTracks: [(Color, Bool)] {
        // Must mirror TrackToggleButton/MasterToggleButton's `disabled` conditions exactly —
        // a button's stale on/inverted state shouldn't draw a waveform while it's disabled.
        let trackDisabled = app.lfoParam.isMasterOnly || app.masterOn > 0
        let masterDisabled = !app.lfoParam.isMasterCapable
        var result: [(Color, Bool)] = []
        if !trackDisabled {
            for t in 1...4 {
                let s = app.trackOn[t] ?? 0
                if s > 0 { result.append((C.track(t), s == 2)) }
            }
        }
        if !masterDisabled && app.masterOn > 0 {
            result.append((C.green, app.masterOn == 2))
        }
        return result.isEmpty ? [(C.green, false)] : result
    }

    // MARK: - Extracted sub-views (shared between portrait and landscape branches)

    @ViewBuilder private var paramRow: some View {
        HStack(spacing: 9 * ctrlBase) {
            Button { app.lfoParam = cycleNext(app.lfoParam) } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24 * ctrlBase))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }
            .buttonStyle(.plain)
            CompactPicker(options: Array(Parameter.allCases), selection: $app.lfoParam)
        }
    }

    @ViewBuilder private var waveRow: some View {
        HStack(spacing: 9 * ctrlBase) {
            Button { app.lfoWave = cycleNext(app.lfoWave) } label: {
                Image(systemName: "waveform.path")
                    .font(.system(size: 24 * ctrlBase))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }
            .buttonStyle(.plain)
            CompactPicker(options: Array(LfoWave.allCases), selection: $app.lfoWave)
        }
    }

    @ViewBuilder private var rateBox: some View {
        HStack(spacing: 9 * ctrlBase) {
            Image(systemName: "timer")
                .font(.system(size: 24 * ctrlBase))
                .foregroundColor(Color(hex: "#aaaaaa"))
            ScrubValue(value: Binding(
                get: { Double(app.lfoRate) },
                set: { app.lfoRate = max(1, min(8, Int($0.rounded()))) }
            ), range: 1...8, sensitivity: 0.04)
            .frame(width: 40 * ctrlBase)
        }
    }

    @ViewBuilder private var depthBox: some View {
        HStack(spacing: 9 * ctrlBase) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: 24 * ctrlBase))
                .foregroundColor(Color(hex: "#aaaaaa"))
            ScrubValue(value: $app.lfoDepth, range: 0...99)
                .frame(width: 58 * ctrlBase)
        }
    }

    @ViewBuilder private var centerBox: some View {
        HStack(spacing: 9 * ctrlBase) {
            Image(systemName: "arrow.up.and.down.circle")
                .font(.system(size: 24 * ctrlBase))
                .foregroundColor(Color(hex: "#aaaaaa"))
            ScrubValue(value: $app.lfoCenter,
                       range: app.lfoParam == .tempo ? 20...300 : 0...99,
                       decimals: app.lfoParam == .tempo ? 1 : 0)
                .frame(width: 74 * ctrlBase)
            Button { snapCenter() } label: {
                Image(systemName: "scope")
                    .font(.system(size: 13 * ctrlBase))
                    .foregroundColor(Color(hex: "#aaaaaa"))
                    .frame(width: 28 * ctrlBase, height: 36 * ctrlBase)
                    .background(C.bg3)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var repeatBtn: some View {
        Button { app.lfoStart(loop: true) } label: {
            Image(systemName: "repeat").font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.green.opacity(0.25))
                .foregroundColor(C.green)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var oneShotBtn: some View {
        Button { app.lfoStart(loop: false) } label: {
            Image(systemName: "arrow.forward.to.line").font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3)
                .foregroundColor(C.text)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var trashBtn: some View {
        Button {
            if app.activeLfos.isEmpty { return }
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash").font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.red.opacity(0.18))
                .foregroundColor(C.red)
        }
        .buttonStyle(.plain)
        .confirmationDialog("delete all active LFOs?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("delete all", role: .destructive) {
                app.stopAllLfos(); selectedLfoID = nil
            }
        }
    }

    @ViewBuilder private var lfoListScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(app.activeLfos) { lfo in
                    ActiveLfoChip(lfo: lfo, selected: selectedLfoID == lfo.id) {
                        selectedLfoID = selectedLfoID == lfo.id ? nil : lfo.id
                    } onStop: {
                        if selectedLfoID == lfo.id { selectedLfoID = nil }
                        app.stopLfo(lfo)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.leading, 5)
        }
    }

    @ViewBuilder private var helpBtn: some View {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3)
                .foregroundColor(C.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("helpButton")
    }

    @ViewBuilder private var settingsBtn: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape").font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3)
                .foregroundColor(C.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsButton")
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Track + master buttons — centered row ──────────────────────
            HStack(spacing: isIpadPortrait ? 12 : 8) {
                ForEach(1...4, id: \.self) { t in
                    TrackToggleButton(track: t,
                                      state: app.trackOn[t] ?? 0,
                                      size: isIpadPortrait ? 90 : nil,
                                      disabled: app.lfoParam.isMasterOnly || app.masterOn > 0) {
                        app.cycleTrack(t)
                    }
                }
                MasterToggleButton(state: app.masterOn,
                                   size: isIpadPortrait ? 90 : nil,
                                   disabled: !app.lfoParam.isMasterCapable) {
                    app.cycleMaster()
                }
                PreviewToggleButton(active: app.isPreview,
                                    size: isIpadPortrait ? 90 : nil) {
                    app.togglePreview()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isIpadPortrait ? 20 : (isPad ? 10 : 4))

            // ── 2+3. Param + wave + rate/depth/center controls ────────────────
            if needsCombinedLfoRow {
                // All controls in one row (all landscape)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    paramRow
                    Spacer(minLength: 12 * ctrlBase)
                    waveRow
                    Spacer(minLength: 16 * ctrlBase)
                    rateBox
                    Spacer(minLength: 10 * ctrlBase)
                    depthBox
                    Spacer(minLength: 10 * ctrlBase)
                    centerBox
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6 * ctrlBase)
            } else {
                // Two-row layout (iPhone portrait + iPad portrait)
                HStack(spacing: 30 * ctrlBase) {
                    Spacer()
                    paramRow
                    waveRow
                    Spacer()
                }
                .padding(.vertical, 6 * ctrlBase)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    rateBox
                    Spacer(minLength: 20 * ctrlBase)
                    depthBox
                    Spacer(minLength: 20 * ctrlBase)
                    centerBox
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6 * ctrlBase)
            }

            // ── 4+5. Waveform + action buttons + LFO list ─────────────────────
            if needsSideBySide {
                HStack(spacing: 0) {
                    MultiWaveformView(
                        lfos: previewLfos,
                        wave: app.lfoWave,
                        rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                        depth: app.lfoDepth,
                        tracks: waveTracks
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(C.bg2)
                    .cornerRadius(3)
                    .padding(8)

                    Rectangle().fill(C.bg3).frame(width: 1)

                    // Action column (left) + LFO list (middle) + help/settings column (right)
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            repeatBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            oneShotBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            trashBtn
                        }
                        .frame(width: 76)

                        Rectangle().fill(C.bg3).frame(width: 1)

                        lfoListScroll
                            .frame(maxHeight: .infinity)

                        Rectangle().fill(C.bg3).frame(width: 1)

                        VStack(spacing: 0) {
                            helpBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            settingsBtn
                        }
                        .frame(width: 44)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Original: fixed-height waveform, then action+LFOs fills remaining space
                MultiWaveformView(
                    lfos: previewLfos,
                    wave: app.lfoWave,
                    rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                    depth: app.lfoDepth,
                    tracks: waveTracks
                )
                .frame(height: isPad ? 140 : 90)
                .frame(maxWidth: .infinity)
                .padding(8)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        repeatBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        oneShotBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        trashBtn
                    }
                    .frame(width: 76)

                    Rectangle().fill(C.bg3).frame(width: 1)

                    lfoListScroll

                    Rectangle().fill(C.bg3).frame(width: 1)

                    VStack(spacing: 0) {
                        helpBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        settingsBtn
                    }
                    .frame(width: 44)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            }

            Rectangle().fill(C.bg3).frame(height: 1)
        }
        .background(C.bg)
        .environment(\.controlScale, ctrlBase)
        .onChange(of: app.lfoParam)  { _, _ in app.updatePreviewIfActive() }
        .onChange(of: app.lfoWave)   { _, _ in app.updatePreviewIfActive() }
        .onChange(of: app.lfoRate)   { _, _ in app.updatePreviewIfActive() }
        .onChange(of: app.lfoDepth)  { _, _ in app.updatePreviewIfActive() }
        .onChange(of: app.lfoCenter) { _, _ in app.updatePreviewIfActive() }
        .sheet(isPresented: Binding(
            get: { hSize != .regular && showHelp },
            set: { if !$0 { showHelp = false } }
        )) { HelpView() }
        .fullScreenCover(isPresented: Binding(
            get: { hSize == .regular && showHelp },
            set: { if !$0 { showHelp = false } }
        )) { HelpView() }
        .sheet(isPresented: Binding(
            get: { hSize != .regular && showSettings },
            set: { if !$0 { showSettings = false } }
        )) { SettingsView() }
        .fullScreenCover(isPresented: Binding(
            get: { hSize == .regular && showSettings },
            set: { if !$0 { showSettings = false } }
        )) { SettingsView() }
    }
}

// MARK: - Compact picker (replaces Menu to get tight item spacing)
// Button sizes itself to the widest option via invisible ZStack overlay.
// Sheet height is computed from item count so it fits without scrolling.

private struct CompactPicker<T>: View
    where T: Identifiable & RawRepresentable & Hashable,
          T.RawValue == String
{
    let options: [T]
    @Binding var selection: T
    @State private var show = false
    @Environment(\.controlScale) private var ctrlScale
    private var fontSize: CGFloat { ctrlFontSizePhone * ctrlScale }

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 4) {
                // ZStack sizes to widest option; only current selection is visible
                ZStack(alignment: .leading) {
                    ForEach(options) { opt in
                        Text(opt.rawValue).opacity(0)
                    }
                    Text(selection.rawValue)
                        .foregroundColor(.white)
                }
                .font(.system(size: fontSize, weight: .bold))
            }
            .padding(.horizontal, 11 * ctrlScale)
            .padding(.vertical, 8 * ctrlScale)
            .background(C.bg3)
            .cornerRadius(5)
        }
        .foregroundColor(.accentColor)
        .popover(isPresented: $show) {
            // On iPad: anchored popover near the button.
            // On iPhone: automatically falls back to a bottom sheet.
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        selection = opt
                        show = false
                    } label: {
                        // Text fills full width (tap anywhere on the row) and is centered.
                        // Checkmark overlaid on trailing edge so it doesn't shift text off-center.
                        Text(opt.rawValue)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundColor(selection == opt ? .accentColor : C.text)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10 * ctrlScale)
                            .contentShape(Rectangle())
                            .overlay(alignment: .trailing) {
                                if selection == opt {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                        .padding(.trailing, 20)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    if idx < options.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(minWidth: 200)
            .padding(.vertical, 6)
            .presentationDetents([.height(CGFloat(options.count) * 44 + 40)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Scrubable number control
// Drag up to increase, down to decrease — matches BpmScrubber direction.
// sensitivity = units per point of drag.

private struct ScrubValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var sensitivity: Double = 0.15
    var decimals: Int = 0
    @Environment(\.controlScale) private var ctrlScale
    private var fontSize: CGFloat { ctrlFontSizePhone * ctrlScale }

    @GestureState private var isActive: Bool = false
    @State private var base: Double = 0
    @State private var accumulated: Double = 0  // integrated vertical delta
    @State private var prevHeight: CGFloat = 0
    @State private var dragStarted = false

    private let precisionScrubHalvingPt: Double = 25
    private func precisionFactor(_ ortho: CGFloat) -> Double {
        1.0 / max(1.0, Double(abs(ortho)) / precisionScrubHalvingPt)
    }

    private var live: Double {
        max(range.lowerBound, min(range.upperBound, base - accumulated))
    }

    private var displayText: String {
        decimals > 0 ? String(format: "%.\(decimals)f", live) : String(Int(live.rounded()))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isActive ? C.green.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .frame(height: 36 * ctrlScale)
            Text(displayText)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? C.green : .white)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($isActive) { _, state, _ in state = true }
                .onChanged { g in
                    // Skip the first event — use it to anchor prevHeight so there's no initial jump.
                    guard dragStarted else {
                        dragStarted = true
                        prevHeight = g.translation.height
                        return
                    }
                    let dh = g.translation.height - prevHeight
                    accumulated += dh * sensitivity * precisionFactor(g.translation.width)
                    prevHeight = g.translation.height
                    value = live
                }
                .onEnded { _ in
                    var newVal = live
                    if decimals == 0 { newVal = newVal.rounded() }
                    base = newVal
                    value = newVal
                    accumulated = 0
                    prevHeight = 0
                    dragStarted = false
                }
        )
        .onAppear { base = value }
        .onChange(of: value) { _, v in if !isActive { base = v } }
    }
}

// MARK: - Active LFO chip

private struct ActiveLfoChip: View {
    let lfo: LfoClip
    let selected: Bool
    let onSelect: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(lfo.track == 0 ? C.green : C.track(lfo.track))
                .frame(width: 6, height: 6)
            Text(lfo.shortLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            Button { onStop() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundColor(C.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(C.bg3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(selected ? C.green.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(3)
        .onTapGesture { onSelect() }
    }
}

// MARK: - Track toggle button
// OFF (0): track-color text, dark bg
// ON  (1): track-color bg, black text
// INV (2): same as ON but text rotated 180°

private struct TrackToggleButton: View {
    let track: Int
    let state: Int
    var size: CGFloat? = nil
    let disabled: Bool
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    private var btnSize: CGFloat { size ?? (isPad ? 70 : 46) }
    private var fontSize: CGFloat { size.map { $0 * 0.38 } ?? (isPad ? 28 : C.trackLabelSize) }

    private var color: Color { C.track(track) }

    var body: some View {
        Button(action: action) {
            Text("\(track)")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: btnSize, height: btnSize)
                .background(color.opacity(state == 0 ? (disabled ? 0.1 : 0.2) : (disabled ? 0.4 : 1.0)))
                .foregroundColor(state == 0 ? color : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Master toggle button
// Same state logic, green instead of track color

private struct MasterToggleButton: View {
    let state: Int
    var size: CGFloat? = nil
    let disabled: Bool
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    private var btnSize: CGFloat { size ?? (isPad ? 70 : 46) }
    private var fontSize: CGFloat { size.map { $0 * 0.38 } ?? (isPad ? 28 : C.trackLabelSize) }

    var body: some View {
        Button(action: action) {
            Text("m")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: btnSize, height: btnSize)
                .background(C.green.opacity(state == 0 ? (disabled ? 0.1 : 0.2) : (disabled ? 0.4 : 1.0)))
                .foregroundColor(state == 0 ? C.green : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
    }
}

// MARK: - Preview toggle button
// "p" — light purple; active = solid fill, inactive = tinted outline

private struct PreviewToggleButton: View {
    let active: Bool
    var size: CGFloat? = nil
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    private var btnSize: CGFloat { size ?? (isPad ? 70 : 46) }
    private var fontSize: CGFloat { size.map { $0 * 0.38 } ?? (isPad ? 28 : C.trackLabelSize) }

    var body: some View {
        Button(action: action) {
            Text("p")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .frame(width: btnSize, height: btnSize)
                .background(C.purple.opacity(active ? 1.0 : 0.2))
                .foregroundColor(active ? .black : C.purple)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
    }
}
