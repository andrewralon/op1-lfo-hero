import SwiftUI

struct LFOPanelView: View {
    var needsCombinedLfoRow: Bool = false
    var needsSideBySide: Bool = false

    @EnvironmentObject var app: AppState
    @Environment(\.metrics) private var m
    @State private var selectedLfoID: UUID? = nil
    @State private var editorSnapshot: EditorSnapshot? = nil
    @State private var chipSnapshot: LfoClip? = nil
    @State private var showDeleteConfirm = false
    @State private var showHelp = false
    @State private var showSettings = false

    private func snapCenter() {
        if app.lfoParam == .tempo {
            app.lfoCenter = app.bpm
            return
        }
        guard let track = (1...4).first(where: { (app.trackOn[$0] ?? 0) > 0 }) else { return }
        switch app.lfoParam {
        case .volume: app.lfoCenter = app.volumes[track] ?? 90
        case .pan:    app.lfoCenter = (Double((app.pans[track] ?? 0) + 64) * 99 / 127).rounded()
        case .mute:   app.lfoCenter = (app.mutes[track] ?? false) ? 99 : 0
        default: break
        }
    }

    // MARK: - Chip edit helpers

    private func enterChipEdit(_ lfo: LfoClip) {
        if selectedLfoID != nil { cancelChipEdit() }
        chipSnapshot    = lfo
        if editorSnapshot == nil { editorSnapshot = app.chipEditorSnapshot() }
        selectedLfoID   = lfo.id
        app.loadEditor(from: lfo)
    }

    // Long press on selected chip — keep the chip's current (live-updated) values, restore editor.
    private func commitChipEdit() {
        guard let id = selectedLfoID else { return }
        app.removeChipDuplicates(of: id)           // primary may now match an existing chip
        app.createAdditionalChipsOnCommit(id: id)  // add chips for any extra active tracks
        selectedLfoID = nil   // clear before restoreEditor so liveUpdateChip() becomes a no-op
        chipSnapshot  = nil
        if let snap = editorSnapshot { app.restoreEditor(snap); editorSnapshot = nil }
    }

    // Tap empty area / stop while selected — revert chip to its state at selection time.
    private func cancelChipEdit() {
        selectedLfoID = nil   // clear before revert/restore so liveUpdateChip() becomes a no-op
        if let snap = chipSnapshot { app.revertChipEdits(snap); chipSnapshot = nil }
        if let snap = editorSnapshot { app.restoreEditor(snap); editorSnapshot = nil }
    }

    // Called from every editor-field onChange while a chip is selected — updates chip text live.
    private func liveUpdateChip() {
        guard let id = selectedLfoID else { return }
        app.saveChipEdits(id: id)
    }

    private func cycleNext<T: CaseIterable & Equatable>(_ value: T) -> T {
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: value) else { return value }
        return all[(idx + 1) % all.count]
    }

    private var waveTracks: [(Color, Bool)] {
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

    // MARK: - Control sub-views

    @ViewBuilder private var paramRow: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { app.lfoParam = cycleNext(app.lfoParam) } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            CompactPicker(options: Array(Parameter.allCases), selection: $app.lfoParam, accessibilityId: "paramPicker")
        }
    }

    @ViewBuilder private var waveRow: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { app.lfoWave = cycleNext(app.lfoWave) } label: {
                Image(systemName: "waveform.path")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            CompactPicker(options: Array(LfoWave.allCases), selection: $app.lfoWave, accessibilityId: "wavePicker")
        }
    }

    @ViewBuilder private var rateBox: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { app.lfoRate = app.lfoRate % 25 + 1 } label: {
                Image(systemName: "timer")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            .accessibilityIdentifier("rateStepButton")
            ScrubValue(value: Binding(
                get: { Double(app.lfoRate) },
                set: { app.lfoRate = max(1, min(25, Int($0.rounded()))) }
            ), range: 1...25, sensitivity: 0.04,
               labelForValue: { rateScrubLabel(for: $0) },
               accessibilityId: "rateScrub")
            .frame(width: m.rateW)
        }
    }

    @ViewBuilder private var centerBox: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { snapCenter() } label: {
                Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            ScrubValue(value: $app.lfoCenter,
                       range: app.lfoParam == .tempo ? 20...300 : 0...99,
                       decimals: app.lfoParam == .tempo ? 1 : 0,
                       accessibilityId: "centerScrub")
                .frame(width: m.depthW)
        }
    }

    @ViewBuilder private var depthBox: some View {
        HStack(spacing: m.controlHSpacing) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: m.iconSize))
                .foregroundColor(Color(hex: "#aaaaaa"))
            ScrubValue(value: $app.lfoDepth, range: 0...99, accessibilityId: "depthScrub")
                .frame(width: m.depthW)
        }
    }

    @ViewBuilder private var repeatBtn: some View {
        Button { app.lfoStart(loop: true) } label: {
            Image(systemName: "repeat").font(.system(size: m.actionIconSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.green.opacity(0.25))
                .foregroundColor(C.green)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repeatButton")
    }

    @ViewBuilder private var oneShotBtn: some View {
        Button { app.lfoStart(loop: false) } label: {
            Image(systemName: "arrow.forward.to.line").font(.system(size: m.actionIconSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3)
                .foregroundColor(C.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("oneShotButton")
    }

    @ViewBuilder private var trashBtn: some View {
        Button {
            if app.activeLfos.isEmpty { return }
            showDeleteConfirm = true
        } label: {
            Image(systemName: "delete.left.fill").font(.system(size: m.actionIconSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.red.opacity(0.18))
                .foregroundColor(C.red)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trashButton")
        .confirmationDialog("delete all active LFOs?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("delete all", role: .destructive) {
                cancelChipEdit()
                app.stopAllLfos()
            }
        }
    }

    @ViewBuilder private var lfoListScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(app.activeLfos) { lfo in
                    ActiveLfoChip(lfo: lfo, selected: selectedLfoID == lfo.id) {
                        // Long press: enter edit or commit if already selected
                        if selectedLfoID == lfo.id { commitChipEdit() }
                        else { enterChipEdit(lfo) }
                    } onToggleEnabled: {
                        app.toggleLfoEnabled(lfo)
                    } onStop: {
                        app.stopLfo(lfo)
                        // onChange(of: app.activeLfos) handles cancel+restore if this was selected
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5).padding(.leading, 5)
        }
        .contentShape(Rectangle())
        .onTapGesture { cancelChipEdit() }
    }

    @ViewBuilder private var helpBtn: some View {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark.circle.fill").font(.system(size: m.actionIconSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3).foregroundColor(C.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("helpButton")
    }

    @ViewBuilder private var settingsBtn: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill").font(.system(size: m.actionIconSize))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(C.bg3).foregroundColor(C.text)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsButton")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Track + master toggle buttons ─────────────────────────────
            HStack(spacing: m.toggleBtnSpacing) {
                ForEach(1...4, id: \.self) { t in
                    TrackToggleButton(track: t,
                                      state: app.trackOn[t] ?? 0,
                                      disabled: app.lfoParam.isMasterOnly || app.masterOn > 0) {
                        app.cycleTrack(t)
                    }
                }
                MasterToggleButton(state: app.masterOn, disabled: !app.lfoParam.isMasterCapable) {
                    app.cycleMaster()
                }
                PreviewToggleButton(active: app.isPreview) {
                    app.togglePreview()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, m.toggleBtnTopPad)
            .padding(.bottom, m.toggleBtnVPad)

            // ── 2+3. Param / wave / rate / depth / center controls ────────────
            if needsCombinedLfoRow {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    paramRow
                    Spacer(minLength: m.controlHSpacing * 1.5)
                    waveRow
                    Spacer(minLength: m.controlHSpacing * 2)
                    rateBox
                    Spacer(minLength: m.controlHSpacing * 1.2)
                    centerBox
                    Spacer(minLength: m.controlHSpacing * 1.2)
                    depthBox
                    Spacer(minLength: 0)
                }
                .padding(.vertical, m.controlVPad)
            } else {
                HStack(spacing: m.controlHSpacing * 3) {
                    Spacer()
                    paramRow
                    waveRow
                    Spacer()
                }
                .padding(.vertical, m.controlVPad)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    rateBox
                    Spacer(minLength: m.controlHSpacing * 2)
                    centerBox
                    Spacer(minLength: m.controlHSpacing * 2)
                    depthBox
                    Spacer(minLength: 0)
                }
                .padding(.vertical, m.controlVPad)
            }

            // ── 4+5. Waveform + action buttons + LFO list ─────────────────────
            if needsSideBySide {
                HStack(spacing: 0) {
                    MultiWaveformView(
                        lfos: [], wave: app.lfoWave,
                        rateTicks: app.lfoDisplayRateTicks,
                        depth: app.lfoDepth, tracks: waveTracks,
                        bpm: app.bpm
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(C.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                    .padding(8)

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            repeatBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            oneShotBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            trashBtn
                        }
                        .frame(width: m.actionColW)

                        Rectangle().fill(C.bg3).frame(width: 1)
                        lfoListScroll.frame(maxHeight: .infinity)
                        Rectangle().fill(C.bg3).frame(width: 1)

                        VStack(spacing: 0) {
                            helpBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            settingsBtn
                        }
                        .frame(width: m.helpColW)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity)
            } else {
                MultiWaveformView(
                    lfos: [], wave: app.lfoWave,
                    rateTicks: app.lfoDisplayRateTicks,
                    depth: app.lfoDepth, tracks: waveTracks,
                    bpm: app.bpm
                )
                .frame(height: m.waveformH)
                .frame(maxWidth: .infinity)
                .background(C.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                .padding(8)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        repeatBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        oneShotBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        trashBtn
                    }
                    .frame(width: m.actionColW)

                    Rectangle().fill(C.bg3).frame(width: 1)
                    lfoListScroll
                    Rectangle().fill(C.bg3).frame(width: 1)

                    VStack(spacing: 0) {
                        helpBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        settingsBtn
                    }
                    .frame(width: m.helpColW)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Rectangle().fill(C.bg3).frame(height: 1)
        }
        .background(C.bg)
        .onChange(of: app.lfoParam)  { _, _ in app.updatePreviewIfActive(); liveUpdateChip() }
        .onChange(of: app.lfoWave)   { _, _ in app.updatePreviewIfActive(); liveUpdateChip() }
        .onChange(of: app.lfoRate)   { _, _ in app.updatePreviewIfActive(); liveUpdateChip() }
        .onChange(of: app.lfoDepth)  { _, _ in app.updatePreviewIfActive(); liveUpdateChip() }
        .onChange(of: app.lfoCenter) { _, _ in app.updatePreviewIfActive(); liveUpdateChip() }
        .modifier(TrackToggleLiveUpdateModifier(onUpdate: liveUpdateChip))
        .onChange(of: app.activeLfos) { _, lfos in
            guard let id = selectedLfoID, !lfos.contains(where: { $0.id == id }) else { return }
            chipSnapshot = nil
            if let snap = editorSnapshot { app.restoreEditor(snap); editorSnapshot = nil }
            selectedLfoID = nil
        }
        .sheet(isPresented: Binding(
            get: { !m.isIpad && showHelp },
            set: { if !$0 { showHelp = false } }
        )) { HelpView() }
        .fullScreenCover(isPresented: Binding(
            get: { m.isIpad && showHelp },
            set: { if !$0 { showHelp = false } }
        )) { HelpView() }
        .sheet(isPresented: Binding(
            get: { !m.isIpad && showSettings },
            set: { if !$0 { showSettings = false } }
        )) { SettingsView() }
        .fullScreenCover(isPresented: Binding(
            get: { m.isIpad && showSettings },
            set: { if !$0 { showSettings = false } }
        )) { SettingsView() }
    }
}

// MARK: - Track/master live-update modifier

private struct TrackToggleLiveUpdateModifier: ViewModifier {
    @EnvironmentObject var app: AppState
    let onUpdate: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: app.trackOn)  { _, _ in onUpdate() }
            .onChange(of: app.masterOn) { _, _ in onUpdate() }
    }
}

// MARK: - Compact picker

private struct CompactPicker<T>: View
    where T: Identifiable & RawRepresentable & Hashable,
          T.RawValue == String
{
    let options: [T]
    @Binding var selection: T
    var accessibilityId: String? = nil
    @State private var show = false
    @Environment(\.metrics) private var m
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad

    var body: some View {
        Button { show = true } label: {
            ZStack(alignment: .leading) {
                ForEach(options) { opt in Text(opt.rawValue).opacity(0) }
                Text(selection.rawValue).foregroundColor(.white)
            }
            .font(.system(size: m.pickerFont, weight: .bold))
            .padding(.horizontal, m.scrubH * 0.31)
            .frame(height: m.scrubH)
            .background(C.bg3)
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(C.dim, lineWidth: 1))
        }
        .foregroundColor(.accentColor)
        .accessibilityIdentifier(accessibilityId ?? "")
        .popover(isPresented: $show) {
            let w: CGFloat = isPad ? 260 : 220
            let itemList = VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        selection = opt; show = false
                    } label: {
                        Text(opt.rawValue)
                            .font(.system(size: m.pickerFont, weight: .bold))
                            .foregroundColor(selection == opt ? .accentColor : C.text)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
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
                    .id(opt.id)
                    if idx < options.count - 1 { Divider() }
                }
            }
            .padding(.vertical, 8)

            Group {
                if m.isLandscape {
                    // Landscape: UIKit caps to available height; ScrollView lets user reach cut-off items
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: true) { itemList.frame(minWidth: w - 20) }
                            .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
                    }
                    .frame(minWidth: w, idealWidth: w, maxWidth: w,
                           idealHeight: CGFloat(options.count) * 44 + 40,
                           maxHeight: CGFloat(options.count) * 44 + 40)
                } else {
                    // Portrait / iPad: VStack has a natural height — UIHostingController
                    // measures it directly, so UIKit sizes the popover to exactly fit the
                    // content with no blank space.
                    itemList.frame(width: w)
                }
            }
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Scrub value

private struct ScrubValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var sensitivity: Double = 0.15
    var decimals: Int = 0
    var labelForValue: ((Int) -> String)? = nil
    var accessibilityId: String? = nil
    @Environment(\.metrics) private var m

    @GestureState private var isActive: Bool = false
    @State private var base: Double = 0
    @State private var accumulated: Double = 0
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
        if let label = labelForValue { return label(Int(live.rounded())) }
        return decimals > 0 ? String(format: "%.\(decimals)f", live) : String(Int(live.rounded()))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isActive ? C.green.opacity(0.6) : C.dim, lineWidth: 1)
                )
                .frame(height: m.scrubH)
            Text(displayText)
                .font(.system(size: m.pickerFont, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? C.green : .white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityId ?? "")
        .accessibilityValue(displayText)
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($isActive) { _, state, _ in state = true }
                .onChanged { g in
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
    let onToggleEnabled: () -> Void
    let onStop: () -> Void
    @Environment(\.metrics) private var m

    // Tracks the start of each press; nil = no press active or long press already fired.
    // The timer captures this value and only fires if it still matches (i.e. press not released).
    @State private var pressedAt: Date? = nil

    private func chipLabel() -> Text {
        let t = lfo.track == 0 ? "m" : "t\(lfo.track)"
        let dCenter = lfo.parameter == .tempo ? Int(lfo.centerValue.rounded()) : Int(midiToUI(lfo.centerValue))
        let dDepth  = lfo.parameter == .tempo ? Int(lfo.depth.rounded())       : Int(midiToUI(lfo.depth))
        var result = Text("\(t)·\(lfo.parameter.shortName)·\(lfo.wave.shortName)")
        if lfo.inverted { result = result + Text(Image(systemName: "arrow.up.arrow.down")) }
        result = result + Text("·\(lfo.rateLabel)·\(dCenter)±\(dDepth)·")
        result = result + Text(Image(systemName: lfo.loop ? "repeat" : "arrow.right.to.line"))
        return result
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(lfo.track == 0 ? C.green : C.track(lfo.track))
                .frame(width: 6, height: 6)
            Group {
                chipLabel()
                    .font(.system(size: m.lfoChipFont, design: .monospaced))
                    .foregroundColor(.white)
                Button { onStop() } label: {
                    Image(systemName: "xmark").font(.system(size: m.lfoChipIconSize, weight: .medium)).foregroundColor(C.dim)
                }.buttonStyle(.plain)
            }
            .opacity(lfo.isEnabled ? 1.0 : 0.4)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(C.bg3)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? C.green.opacity(0.7) : Color.clear, lineWidth: 1))
        .cornerRadius(3)
        .onTapGesture { }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Cancel if the user is scrolling
                    if abs(value.translation.height) > 8 || abs(value.translation.width) > 8 {
                        pressedAt = nil
                        return
                    }
                    guard pressedAt == nil else { return }
                    let t = Date()
                    pressedAt = t
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard pressedAt == t else { return } // released or scrolled — skip
                        pressedAt = nil
                        onSelect()
                    }
                }
                .onEnded { value in
                    guard pressedAt != nil else { return } // long press already fired — skip tap
                    pressedAt = nil
                    let moved = max(abs(value.translation.width), abs(value.translation.height))
                    if moved < 10 { onToggleEnabled() }
                }
        )
    }
}

// MARK: - Track toggle button

private struct TrackToggleButton: View {
    let track: Int
    let state: Int
    let disabled: Bool
    let action: () -> Void
    @Environment(\.metrics) private var m

    var body: some View {
        Button(action: action) {
            Text("\(track)")
                .font(.system(size: m.toggleBtnFont, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: m.toggleBtnSize, height: m.toggleBtnSize)
                .background(C.track(track).opacity(state == 0 ? (disabled ? 0.1 : 0.2) : (disabled ? 0.4 : 1.0)))
                .foregroundColor(state == 0 ? C.track(track) : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
        .accessibilityIdentifier("track\(track)Button")
    }
}

// MARK: - Master toggle button

private struct MasterToggleButton: View {
    let state: Int
    let disabled: Bool
    let action: () -> Void
    @Environment(\.metrics) private var m

    var body: some View {
        Button(action: action) {
            Text("m")
                .font(.system(size: m.toggleBtnFont, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: m.toggleBtnSize, height: m.toggleBtnSize)
                .background(C.green.opacity(state == 0 ? (disabled ? 0.1 : 0.2) : (disabled ? 0.4 : 1.0)))
                .foregroundColor(state == 0 ? C.green : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
        .accessibilityIdentifier("masterButton")
    }
}

// MARK: - Preview toggle button

private struct PreviewToggleButton: View {
    let active: Bool
    let action: () -> Void
    @Environment(\.metrics) private var m

    var body: some View {
        Button(action: action) {
            Text("p")
                .font(.system(size: m.toggleBtnFont, weight: .bold, design: .monospaced))
                .frame(width: m.toggleBtnSize, height: m.toggleBtnSize)
                .background(C.purple.opacity(active ? 1.0 : 0.2))
                .foregroundColor(active ? .black : C.purple)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .accessibilityIdentifier("previewButton")
    }
}
