import SwiftUI

/// Shown over the waveform when the app is slaved to a device that is sending no clock: in slave
/// mode the device's ticks drive every LFO, so without them they all stop with no other sign. A tap
/// switches to the app's own clock. Lives here, not only in the BPM box's small "no clk", because
/// this is where someone looks when their LFOs aren't moving.
private struct ClockWaitingBanner: ViewModifier {
    @EnvironmentObject var app: AppState
    @Environment(\.metrics) private var m

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if app.lfosWaitingForClock {
                Button { app.enableClock() } label: {
                    // Say why: not connected at all is a different fix from connected but silent
                    // (an op-1 in the wrong tempo mode).
                    let device = app.profile.caps.clockLabel
                    Text(app.isConnected
                         ? "lfos paused — no clock from \(device). tap to use the app clock"
                         : "lfos paused — \(device) not connected. tap to use the app clock")
                        .font(.system(size: m.lfoChipFont, weight: .semibold, design: .monospaced))
                        .foregroundColor(C.yellow)
                        .multilineTextAlignment(.center)
                        .padding(m.lfoPanelPad)
                        .frame(maxWidth: .infinity)
                        .background(C.bg.opacity(0.88))
                        .overlay(Rectangle().stroke(C.yellow.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clockWaitingBanner")
            }
        }
    }
}

private extension View {
    func clockWaitingBanner() -> some View { modifier(ClockWaitingBanner()) }
}

/// The coordinate space `ContentView` names for the whole screen, and the frame of the LFO controls
/// in it, so a touch can be sorted into "on the controls" or "anywhere else".
let onDeckSpace = "onDeckScreen"

struct OnDeckControlsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct LFOPanelView: View {
    var needsCombinedLfoRow: Bool = false
    var needsSideBySide: Bool = false

    @EnvironmentObject var app: AppState
    @EnvironmentObject private var tour: TourController
    @Environment(\.metrics) private var m
    @State private var selectedLfoID: UUID? = nil
    @State private var editorSnapshot: EditorSnapshot? = nil
    @State private var chipSnapshot: LfoClip? = nil
    @State private var showDeleteConfirm = false
    @State private var showHelp = false
    @State private var showSettings = false
    /// Choose the parameter an LFO will drive with the cycle button (the picker goes through
    /// `recentre` itself, so that a drag only re-centers where it lands).
    ///
    /// A parameter with a neutral point (bend, the OP-1's EQ and record level) starts a new LFO
    /// centred there rather than at the global default of 90, which for bend would start a new
    /// chip at roughly 1.9x pitch and leave it there when it stops. Not while a chip is being
    /// edited: its own centre has to survive a change of parameter.
    private func selectParam(_ new: ParamSpec) {
        let old = app.lfoParam
        app.lfoParam = new
        recentre(from: old, to: new)
    }

    /// The centering half of `selectParam`, for the picker's drag: it assigns the parameter as
    /// the drag goes and calls this once, with the parameter it started on and the one it was
    /// released on.
    private func recentre(from old: ParamSpec, to new: ParamSpec) {
        guard new != old, selectedLfoID == nil else { return }
        if let centre = new.defaultCenter {
            app.lfoCenter = centre
        } else if old.defaultCenter != nil {
            // Leaving a neutral-centred parameter: its centre (49 for bend) means nothing here.
            app.lfoCenter = AppState.defaultLfoCenter
        }
    }

    private func snapCenter() {
        if app.lfoParam.role == .tempo {
            app.lfoCenter = app.bpm
            return
        }
        // A declared neutral point wins, and must be applied before the track lookup below —
        // master-only parameters (pitch bend among them) have no track and would return early.
        if let centre = app.lfoParam.defaultCenter {
            app.lfoCenter = centre
            return
        }
        guard let track = app.profile.trackIndices.first(where: { (app.trackOn[$0] ?? 0) > 0 })
        else { return }
        switch app.lfoParam.role {
        case .volume: app.lfoCenter = app.volumes[track] ?? app.profile.defaultVolume
        case .pan:    app.lfoCenter = (Double((app.pans[track] ?? 0) + 64) * 99 / 127).rounded()
        case .mute:   app.lfoCenter = (app.mutes[track] ?? false) ? 99 : 0
        case .tempo, .generic: break
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

    /// Parameters come from the active device's profile rather than a fixed enum, so the
    /// cycle button steps through that list instead of `CaseIterable`.
    private func cycleNextParam(_ value: ParamSpec) -> ParamSpec {
        let all = app.profile.pickerParams
        guard !all.isEmpty else { return value }
        guard let idx = all.firstIndex(of: value) else { return all[0] }
        return all[(idx + 1) % all.count]
    }

    /// What the waveform draws. While an LFO is being set up (a chip is selected, preview is on,
    /// or a control has been touched since the last touch elsewhere) it is empty, which makes
    /// `MultiWaveformView` draw the editor's own curve: that is the LFO on deck, since `loadEditor`
    /// fills the editor from a selected chip and `saveChipEdits` keeps it live. Otherwise every
    /// LFO that is running, so paused and finished chips drop out; with none running it is empty
    /// again rather than drawing an empty box.
    private var waveformLfos: [LfoClip] {
        if selectedLfoID != nil || app.isPreview || app.onDeckTouched { return [] }
        return app.activeLfos.filter(\.isEnabled)
    }

    private var waveTracks: [(Color, Bool)] {
        let trackDisabled = app.lfoParam.isMasterOnly || app.masterOn > 0
        let masterDisabled = !app.lfoParam.isMasterCapable
        var result: [(Color, Bool)] = []
        if !trackDisabled {
            for t in app.profile.trackIndices {
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
            Button { selectParam(cycleNextParam(app.lfoParam)) } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            // The binding writes the parameter at once, so preview, a selected chip and the
            // label all follow a drag. Re-centering waits for the settle: passing over bend on
            // the way to another parameter must not move the center box.
            CompactPicker(options: app.profile.pickerParams,
                          selection: Binding(get: { app.lfoParam }, set: { app.lfoParam = $0 }),
                          label: { $0.name }, accessibilityId: "paramPicker",
                          onSettle: { recentre(from: $0, to: $1) })
        }
        .tourAnchor(.paramPicker)
    }

    @ViewBuilder private var waveRow: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { app.lfoWave = cycleNext(app.lfoWave) } label: {
                Image(systemName: "waveform.path")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            CompactPicker(options: Array(LfoWave.allCases), selection: $app.lfoWave,
                          label: { $0.rawValue }, accessibilityId: "wavePicker")
        }
        .tourAnchor(.wavePicker)
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
               accessibilityId: "rateScrub",
               tapOptions: (1...25).map { rateScrubLabel(for: $0) })
            .frame(width: m.rateW)
        }
        .tourAnchor(.speedBox)
    }

    @ViewBuilder private var centerBox: some View {
        HStack(spacing: m.controlHSpacing) {
            Button { snapCenter() } label: {
                Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up")
                    .font(.system(size: m.iconSize))
                    .foregroundColor(Color(hex: "#aaaaaa"))
            }.buttonStyle(.plain)
            ScrubValue(value: $app.lfoCenter,
                       range: app.lfoParam.role == .tempo ? 20...300 : 0...99,
                       decimals: app.lfoParam.role == .tempo ? 1 : 0,
                       accessibilityId: "centerScrub")
                .frame(width: m.depthW)
        }
        .tourAnchor(.centerBox)
    }

    @ViewBuilder private var depthBox: some View {
        HStack(spacing: m.controlHSpacing) {
            Image(systemName: "arrow.up.and.down")
                .font(.system(size: m.iconSize))
                .foregroundColor(Color(hex: "#aaaaaa"))
            ScrubValue(value: $app.lfoDepth, range: 0...99, accessibilityId: "depthScrub")
                .frame(width: m.depthW)
        }
        .tourAnchor(.depthBox)
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
                    // Resolve the parameter here so the chip view stays independent of profiles.
                    let spec = app.profile.param(lfo.paramId)
                    ActiveLfoChip(lfo: lfo,
                                  paramShort: spec?.short ?? lfo.paramId,
                                  isTempo: spec?.role == .tempo,
                                  valueMax: spec?.valueMax ?? 127,
                                  selected: selectedLfoID == lfo.id) {
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
            .padding(.vertical, m.lfoScrollPad).padding(.leading, m.lfoScrollPad)
        }
        .contentShape(Rectangle())
        .onTapGesture { cancelChipEdit() }
        .accessibilityIdentifier("lfoChipArea")
        .tourAnchor(.chipArea)
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

    // MARK: - Toggle button row layout

    /// One button in the LFO target row.
    private enum ToggleSlot: Hashable {
        case track(Int), master, preview
    }

    /// The target buttons, chunked into however many rows the current layout needs.
    /// Master and preview always trail the last row.
    private var toggleButtonRows: [[ToggleSlot]] {
        let slots = app.profile.trackIndices.map { ToggleSlot.track($0) } + [.master, .preview]
        let perRow = max(1, m.toggleBtnPerRow)
        return stride(from: 0, to: slots.count, by: perRow).map {
            Array(slots[$0 ..< min($0 + perRow, slots.count)])
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Sections 1-3 are the LFO's controls. `ContentView` watches touches against this frame:
            // one inside puts the LFO on deck on the waveform, one outside takes it off.
            VStack(spacing: 0) {
                // ── 1. Track + master toggle buttons ─────────────────────────────
                // Wraps onto a second row when a 6-track device won't fit one row at the
                // 44pt minimum touch target (iPhone portrait) — see LayoutMetrics.toggleBtnRows.
                VStack(spacing: m.toggleBtnSpacing) {
                    ForEach(Array(toggleButtonRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: m.toggleBtnSpacing) {
                            ForEach(row, id: \.self) { slot in
                                switch slot {
                                case .track(let t):
                                    TrackToggleButton(track: t,
                                                      state: app.trackOn[t] ?? 0,
                                                      disabled: app.lfoParam.isMasterOnly || app.masterOn > 0) {
                                        app.cycleTrack(t)
                                    }
                                    .tourAnchor(.trackToggle)
                                case .master:
                                    MasterToggleButton(state: app.masterOn,
                                                       disabled: !app.lfoParam.isMasterCapable) {
                                        app.cycleMaster()
                                    }
                                    .tourAnchor(.masterToggle)
                                case .preview:
                                    PreviewToggleButton(active: app.isPreview) {
                                        app.togglePreview()
                                    }
                                    .tourAnchor(.preview)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, m.toggleBtnTopPad)
                .padding(.bottom, m.toggleBtnVPad)
                .padding(.horizontal, m.toggleBtnHPad)

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
            }
            .background(GeometryReader { g in
                Color.clear.preference(key: OnDeckControlsKey.self,
                                       value: g.frame(in: .named(onDeckSpace)))
            })

            // ── 4+5. Waveform + action buttons + LFO list ─────────────────────
            if needsSideBySide {
                HStack(spacing: 0) {
                    MultiWaveformView(
                        lfos: waveformLfos, wave: app.lfoWave,
                        rateTicks: app.lfoDisplayRateTicks,
                        depth: app.lfoDepth, tracks: waveTracks,
                        bpm: app.bpm
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("waveform")
                    .accessibilityValue(waveformLfos.isEmpty ? "editor" : "running")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(C.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                    .clockWaitingBanner()
                    .tourAnchor(.waveform)
                    .padding(m.lfoPanelPad)

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            repeatBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            oneShotBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            trashBtn
                        }
                        .frame(width: m.actionColW)
                        .tourAnchor(.startButtons)

                        Rectangle().fill(C.bg3).frame(width: 1)
                        lfoListScroll.frame(maxHeight: .infinity)
                        Rectangle().fill(C.bg3).frame(width: 1)

                        VStack(spacing: 0) {
                            helpBtn
                            Rectangle().fill(C.bg3).frame(height: 1)
                            settingsBtn
                        }
                        .frame(width: m.helpColW)
                        .tourAnchor(.helpSettings)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                    .padding(.trailing, m.lfoPanelPad)
                    .padding(.vertical, m.lfoPanelPad)
                }
                .frame(maxHeight: .infinity)
            } else {
                MultiWaveformView(
                    lfos: waveformLfos, wave: app.lfoWave,
                    rateTicks: app.lfoDisplayRateTicks,
                    depth: app.lfoDepth, tracks: waveTracks,
                    bpm: app.bpm
                )
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("waveform")
                .accessibilityValue(waveformLfos.isEmpty ? "editor" : "running")
                .frame(height: m.waveformH)
                .frame(maxWidth: .infinity)
                .background(C.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                .clockWaitingBanner()
                .tourAnchor(.waveform)
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
                    .tourAnchor(.startButtons)

                    Rectangle().fill(C.bg3).frame(width: 1)
                    lfoListScroll
                    Rectangle().fill(C.bg3).frame(width: 1)

                    VStack(spacing: 0) {
                        helpBtn
                        Rectangle().fill(C.bg3).frame(height: 1)
                        settingsBtn
                    }
                    .frame(width: m.helpColW)
                    .tourAnchor(.helpSettings)
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
        // The tutorial never sits over a sheet, and replay waits for these to close.
        .onChange(of: showHelp)     { _, shown in tour.sheet(shown) }
        .onChange(of: showSettings) { _, shown in tour.sheet(shown) }
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

// MARK: - Option list popover

/// The list that opens from a picker or from the speed box: every option on one scrolling,
/// tappable column, opened on the current one. Takes plain labels so the parameter, wave and
/// speed lists share it, and with them the always-visible scroll bar.
private struct OptionListPopover: View {
    let labels: [String]
    let selectedIndex: Int
    /// Fit the width to the labels, for a list of short ones (the speeds): the fixed width suits
    /// parameter names but leaves a column of "f1"…"f17" lost in the middle of a wide popover.
    var snug = false
    let onPick: (Int) -> Void
    @Environment(\.metrics) private var m
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad

    /// The widest label, plus a gutter each side that clears the checkmark on the selected row.
    private var snugWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: m.pickerFont, weight: .bold)
        let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(widest + 2 * m.pickerFont * 2.2)
    }

    var body: some View {
        let w: CGFloat = snug ? snugWidth : (isPad ? 260 : 220)
        let itemList = VStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, text in
                Button {
                    onPick(idx)
                } label: {
                    Text(text)
                        .font(.system(size: m.pickerFont, weight: .bold))
                        .foregroundColor(idx == selectedIndex ? .accentColor : C.text)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .overlay(alignment: .trailing) {
                            if idx == selectedIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                                    .padding(.trailing, 20)
                            }
                        }
                }
                .buttonStyle(.plain)
                .id(idx)
                if idx < labels.count - 1 { Divider() }
            }
        }
        .padding(.vertical, 8)

        // Cap the popover so a long list (the TX-6 has ~30 parameters) can never grow past
        // the screen — without this the tail of the list is unreachable in portrait.
        let naturalH = CGFloat(labels.count) * 44 + 40
        let cappedH  = min(naturalH, m.screen.height * 0.6)

        Group {
            if m.isLandscape {
                // Landscape: UIKit caps to available height; ScrollView lets user reach cut-off items
                ScrollViewReader { proxy in
                    AlwaysVisibleScroll { itemList.frame(minWidth: w - 20) }
                        .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
                }
                .frame(minWidth: w, idealWidth: w, maxWidth: w,
                       idealHeight: naturalH, maxHeight: naturalH)
            } else if naturalH <= cappedH {
                // Portrait / iPad, short list: VStack has a natural height — UIHostingController
                // measures it directly, so UIKit sizes the popover to exactly fit the
                // content with no blank space.
                itemList.frame(width: w)
            } else {
                // Portrait, long list: same scrolling treatment as landscape.
                ScrollViewReader { proxy in
                    AlwaysVisibleScroll { itemList.frame(minWidth: w - 20) }
                        .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
                }
                .frame(minWidth: w, idealWidth: w, maxWidth: w,
                       idealHeight: cappedH, maxHeight: cappedH)
            }
        }
        .presentationCompactAdaptation(.popover)
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// Shows `OptionListPopover` from this view, and closes it after a pick.
    func optionListPopover(isPresented: Binding<Bool>, labels: [String], selectedIndex: Int,
                           snug: Bool = false,
                           onPick: @escaping (Int) -> Void) -> some View {
        popover(isPresented: isPresented) {
            OptionListPopover(labels: labels, selectedIndex: selectedIndex, snug: snug) { idx in
                onPick(idx)
                isPresented.wrappedValue = false
            }
        }
    }
}

// MARK: - Compact picker

/// Options are supplied with a label closure rather than constrained to a String-backed enum,
/// so device-specific parameter lists (`[ParamSpec]`) work alongside `LfoWave`.
///
/// A tap opens the list; a vertical drag steps through the options, the same gesture as the
/// speed, center and depth boxes. `onSettle` reports where a choice ended up, not every step of
/// a drag: it is for effects (like re-centering) that must not fire on options merely passed over.
private struct CompactPicker<T>: View where T: Identifiable & Hashable {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var accessibilityId: String? = nil
    /// Called once per choice with the selection from before it and the final one: when a drag
    /// is released, or when an option is picked from the list.
    var onSettle: ((_ from: T, _ to: T) -> Void)? = nil
    @State private var show = false
    @State private var dragActive = false
    @State private var dragFrom: T? = nil
    @Environment(\.metrics) private var m

    /// The selection as a position in `options`, so `ScrubDrag` can move it like any number.
    /// Writes back only when the position changes, so a drag that stays on one option is silent.
    private var position: Binding<Double> {
        Binding(
            get: { Double(options.firstIndex(of: selection) ?? 0) },
            set: { v in
                guard !options.isEmpty else { return }
                let i = max(0, min(options.count - 1, Int(v.rounded())))
                if options[i] != selection { selection = options[i] }
            })
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(options) { opt in Text(label(opt)).opacity(0) }
            Text(label(selection)).foregroundColor(.white)
        }
        .font(.system(size: m.pickerFont, weight: .bold))
        .padding(.horizontal, m.scrubH * 0.31)
        .frame(height: m.scrubH)
        .background(C.bg3)
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke(dragActive ? C.green.opacity(0.6) : C.dim, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { show = true }
        .modifier(ScrubDrag(value: position,
                            range: 0...Double(max(0, options.count - 1)),
                            sensitivity: 0.04, isActive: $dragActive,
                            onBegan: { dragFrom = selection },
                            onEnded: {
                                if let from = dragFrom { onSettle?(from, selection) }
                                dragFrom = nil
                            }))
        // A tap gesture is not a Button, so say it is one: the UI tests (and VoiceOver) look
        // for `buttons[accessibilityId]`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(selection))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityId ?? "")
        .optionListPopover(isPresented: $show, labels: options.map(label),
                           selectedIndex: options.firstIndex(of: selection) ?? -1) { idx in
            let from = selection
            selection = options[idx]
            onSettle?(from, options[idx])
        }
    }
}

// MARK: - Always-visible scroll bar

/// The system scroll indicator only appears while a list is moving, so a popover that opens with
/// part of its list cut off gives no hint that more is above or below. This draws its own thumb,
/// which stays on screen whenever the content is taller than the viewport.
private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
}

private struct AlwaysVisibleScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var metrics = ScrollMetrics()
    @State private var viewport: CGFloat = 0
    @Environment(\.metrics) private var m
    private let space = "alwaysVisibleScroll"

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Written straight into state: a PreferenceKey never reached the enclosing view from
            // inside a popover, which left the bar permanently hidden.
            content.background(
                GeometryReader { g in
                    let offset = -g.frame(in: .named(space)).minY
                    let height = g.size.height
                    Color.clear
                        .onAppear { metrics = ScrollMetrics(offset: offset, content: height) }
                        .onChange(of: offset) { _, v in metrics.offset = v }
                        .onChange(of: height) { _, v in metrics.content = v }
                })
        }
        .coordinateSpace(name: space)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { viewport = g.size.height }
                    .onChange(of: g.size.height) { _, h in viewport = h }
            })
        .overlay(alignment: .topLeading) { thumb }
    }

    @ViewBuilder private var thumb: some View {
        let overflow = metrics.content - viewport
        if viewport > 0, overflow > 1 {
            let inset = m.pickerFont * 0.3
            let track = max(viewport - inset * 2, 1)
            let height = min(track, max(m.pickerFont * 1.5, track * viewport / metrics.content))
            let progress = min(max(metrics.offset / overflow, 0), 1)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: m.pickerFont * 0.2, height: height)
                    .offset(y: inset + (track - height) * progress)
                    .padding(.trailing, m.pickerFont * 0.15)
                    .accessibilityIdentifier("pickerScrollThumb")
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Scrub drag

/// A vertical drag that moves a number: up raises it, `sensitivity` is value per point, and
/// moving sideways away from the box slows it down for fine control. The state it needs
/// (where the drag began, how far it has gone) lives here, so every box that scrubs shares it.
private struct ScrubDrag: ViewModifier {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var sensitivity: Double = 0.15
    /// Snap to a whole number when the drag ends.
    var rounds = true
    /// True while a finger is dragging, for the green border.
    @Binding var isActive: Bool
    var onBegan: () -> Void = {}
    var onEnded: () -> Void = {}

    @GestureState private var gestureActive = false
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

    /// Also runs when the system cancels a drag, which never reaches `onEnded`; leaving
    /// `accumulated` behind would make the next drag start from the wrong place.
    private func finish() {
        guard dragStarted else { return }
        var newVal = live
        if rounds { newVal = newVal.rounded() }
        base = newVal
        value = newVal
        accumulated = 0
        prevHeight = 0
        dragStarted = false
        onEnded()
    }

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($gestureActive) { _, state, _ in state = true }
                    .onChanged { g in
                        guard dragStarted else {
                            dragStarted = true
                            prevHeight = g.translation.height
                            onBegan()
                            return
                        }
                        let dh = g.translation.height - prevHeight
                        accumulated += dh * sensitivity * precisionFactor(g.translation.width)
                        prevHeight = g.translation.height
                        value = live
                    }
                    .onEnded { _ in finish() }
            )
            .onAppear { base = value }
            .onChange(of: value) { _, v in if !gestureActive { base = v } }
            .onChange(of: gestureActive) { _, active in
                isActive = active
                if !active { finish() }
            }
    }
}

// MARK: - Scrub value

/// A box that shows a number and scrubs it by dragging. With `tapOptions` a tap also opens a list
/// of labels, one per whole value in `range` starting at its lower bound.
private struct ScrubValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var sensitivity: Double = 0.15
    var decimals: Int = 0
    var labelForValue: ((Int) -> String)? = nil
    var accessibilityId: String? = nil
    var tapOptions: [String]? = nil
    @Environment(\.metrics) private var m

    @State private var isActive = false
    @State private var showOptions = false

    private var displayText: String {
        if let label = labelForValue { return label(Int(value.rounded())) }
        return decimals > 0 ? String(format: "%.\(decimals)f", value) : String(Int(value.rounded()))
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
        .contentShape(Rectangle())
        .modifier(TapToOpen(isEnabled: tapOptions != nil) { showOptions = true })
        .modifier(ScrubDrag(value: $value, range: range, sensitivity: sensitivity,
                            rounds: decimals == 0, isActive: $isActive))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityId ?? "")
        .accessibilityValue(displayText)
        // Scrub boxes hold numbers, so their lists are short labels that fit a narrow popover.
        .optionListPopover(isPresented: $showOptions, labels: tapOptions ?? [],
                           selectedIndex: Int((value - range.lowerBound).rounded()),
                           snug: true) { idx in
            value = range.lowerBound + Double(idx)
        }
    }
}

/// Adds a tap only when asked. A box with nothing to open must not carry a tap gesture at all:
/// it would be exposed as something to activate, and centre and depth should stay plain values.
private struct TapToOpen: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled { content.onTapGesture(perform: action) } else { content }
    }
}

// MARK: - Active LFO chip

private struct ActiveLfoChip: View {
    let lfo: LfoClip
    /// Resolved by the caller from the active profile — the chip does not look up parameters.
    let paramShort: String
    let isTempo: Bool
    /// Native top of the parameter (127, or 16383 for bend) so the chip can show centre and depth
    /// on the same 0-99 scale as the sliders.
    let valueMax: Double
    let selected: Bool
    let onSelect: () -> Void
    let onToggleEnabled: () -> Void
    let onStop: () -> Void
    @Environment(\.metrics) private var m

    private func chipLabel() -> Text {
        let t = lfo.track == 0 ? "m" : "\(lfo.track)"
        let dCenter = isTempo ? Int(lfo.centerValue.rounded()) : Int(nativeToUI(lfo.centerValue, valueMax: valueMax))
        let dDepth  = isTempo ? Int(lfo.depth.rounded())       : Int(nativeToUI(lfo.depth, valueMax: valueMax))
        var result = Text(t)
        if lfo.inverted { result = result + Text(Image(systemName: "arrow.up.arrow.down")) }
        result = result + Text("·\(paramShort)·\(lfo.wave.shortName)")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lfoChip")
        .gesture(
            LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
                .onEnded { _ in onSelect() }
                .exclusively(before: TapGesture().onEnded { onToggleEnabled() })
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
