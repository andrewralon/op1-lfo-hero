import CoreBluetooth
import SwiftUI

// MARK: - Layout metrics (single source of truth for all dimensional values)

struct LayoutMetrics {
    let screen: CGSize
    let isLandscape: Bool
    let isIpad: Bool

    // ── Tier 1: structural — how the screen is divided into zones ───────────

    /// Width of the transport column in landscape — sized so all 5 columns have equal content width.
    var transportColW: CGFloat { (screen.width - 5 * trackGapUnit) / 5 }

    /// Height of the mixer + track strips row.
    var tracksH: CGFloat {
        if isLandscape { return screen.height * 0.38 }  // landscape: same ratio for iPhone + iPad
        if !isIpad     { return screen.height * 0.25 }  // iPhone portrait: shorter mixer row
        return screen.height * 0.30
    }

    /// Height of the portrait transport bar (play/stop/BPM row).
    var transportBarH: CGFloat { screen.height * 0.10 }

    /// Width of a single track column (4 tracks share the mixer width).
    var trackColW: CGFloat {
        let mixerW = isLandscape ? screen.width - transportColW : screen.width
        return mixerW / 4
    }

    // ── Tier 2: LFO panel content ───────────────────────────────────────

    /// Vertical padding above/below the portrait transport bar — gives the 6pt gap unit on iPhone.
    var transportVPad: CGFloat { isLandscape ? trackGapUnit : 3 * trackGapUnit }

    /// Horizontal padding left/right of transport bar. Portrait gets extra breathing room.
    var transportHPad: CGFloat { isLandscape ? trackGapUnit : screen.width * 0.030 }

    /// Total height available to LFOPanelView (below tracks+transport, above status bar).
    var lfoH: CGFloat {
        let transportH = isLandscape ? 0 : (transportBarH + 2 * transportVPad)
        let h = screen.height - tracksH - transportH - statusBarH
        return max(h, 100)
    }

    // Landscape uses larger fractions: single combined row means more lfoH per element.
    var toggleBtnSize: CGFloat    {
        if isLandscape { return max(lfoH * 0.22, 44) }
        if isIpad      { return max(lfoH * 0.13, 44) }
        // iPhone portrait: fit 6 buttons + 5 gaps + 2 side margins within screen width
        let margin  = 3 * trackGapUnit
        let spacing = max(lfoH * 0.012, 6)
        return max((screen.width - 2 * margin - 5 * spacing) / 6, 44)
    }
    /// Horizontal padding on the toggle button row — iPhone portrait only, to give side margins.
    var toggleBtnHPad: CGFloat    { !isLandscape && !isIpad ? 3 * trackGapUnit : 0 }
    var toggleBtnFont: CGFloat    { toggleBtnSize * 0.38 }
    var toggleBtnSpacing: CGFloat { max(lfoH * 0.012, 6) }
    var toggleBtnVPad: CGFloat    { isLandscape ? max(lfoH * 0.011, 2.5) : (isIpad ? max(lfoH * 0.030, 8) : 0) }
    /// Top padding of the toggle buttons row. Portrait = 0 (transport bottom gap already gives 6pt).
    var toggleBtnTopPad: CGFloat  { isLandscape ? toggleBtnVPad : 0 }

    /// Height of a ScrubValue / CompactPicker box.
    var scrubH: CGFloat           { isLandscape ? max(lfoH * 0.18, 36) : max(lfoH * 0.10, 36) }
    var rateW: CGFloat            { scrubH * 1.1 }
    var depthW: CGFloat           { scrubH * 1.6 }
    var centerW: CGFloat          { scrubH * 2.0 }

    var iconSize: CGFloat         { isLandscape ? max(lfoH * 0.08, 20) : max(lfoH * 0.06, 20) }
    var pickerFont: CGFloat       { isLandscape ? max(lfoH * 0.058, 14) : max(lfoH * 0.04, 14) }
    var controlVPad: CGFloat      { max(lfoH * 0.011, 2.5) }
    var controlHSpacing: CGFloat  { max(lfoH * 0.018, 8) }

    /// Waveform fixed height in portrait (landscape uses landscapeWaveH cap instead).
    var waveformH: CGFloat        { lfoH * 0.18 }

    /// Max height of the waveform+LFO section in landscape — prevents it consuming all remaining space.
    var landscapeWaveH: CGFloat   { lfoH * 0.47 }

    // Landscape: iPhone ref 39.2pt → 4.65% screenW. Portrait: screen.height avoids 2.65× width scaling; iPad needs separate fraction.
    var actionColW: CGFloat { isLandscape ? screen.width * 0.0465 : (isIpad ? screen.height * 0.07 : screen.height * 0.05) }
    var helpColW: CGFloat   { isLandscape ? screen.width * 0.0465 : (isIpad ? screen.height * 0.07 : screen.height * 0.05) }
    /// Icon size inside repeat/1x/trash/help/settings buttons — larger on iPad to fill the taller cells.
    var actionIconSize: CGFloat   { isIpad ? max(lfoH * 0.06, 24) : max(lfoH * 0.04, 16) }

    // Transport column — all landscape: 3 equal rows, metronome+BPM share row 3.
    var transportColBtnSize: CGFloat     { max(tracksH * 0.09, 18) }
    var transportMetronomeSize: CGFloat  { isLandscape ? max(tracksH * 0.14, 24) : 22 }
    var transportMetronomeLabel: CGFloat { isLandscape ? max(tracksH * 0.035, 10) : (isIpad ? 14 : 11) }
    var transportBpmFont: CGFloat        { isLandscape ? max(tracksH * 0.07, 13) : (isIpad ? 30 : 18) }

    // Active LFO chip text — bigger on iPad landscape for readability.
    var lfoChipFont: CGFloat     { isIpad && isLandscape ? max(lfoH * 0.038, 18) : (isIpad ? max(lfoH * 0.022, 14) : 12) }
    var lfoChipIconSize: CGFloat { isIpad && isLandscape ? max(lfoH * 0.028, 14) : (isIpad ? max(lfoH * 0.016, 11) : 11) }
    /// Outer padding around bordered waveform/chip panel boxes in the LFO section.
    var lfoPanelPad: CGFloat { isLandscape && !isIpad ? screen.width * 0.007 : 8 }
    /// Inner content padding of the chip scroll area.
    var lfoScrollPad: CGFloat { isLandscape && !isIpad ? screen.width * 0.004 : 5 }

    // Status bar (connection + tempo row at the very bottom of the screen).
    var statusBarFont: CGFloat { isIpad ? 12 : 9 }
    var statusBarVPad: CGFloat { isIpad ? 4 : 1 }
    // Estimated rendered height; used to size lfoH correctly.
    var statusBarH: CGFloat    { statusBarFont + 2 * statusBarVPad + 8 }

    // ── Tier 2: track strip content ─────────────────────────────────────

    /// Mute button number label font size.
    var volValueFont: CGFloat    { isIpad ? 58 : 28 }
    var volValueSpacing: CGFloat { volValueFont * 0.25 }

    /// Gap unit between track columns: total visual gap = 3 × trackGapUnit (right pad + spacing + left pad).
    /// Portrait: 0.5% of width → ~2pt iPhone, ~5pt iPad. Landscape: 0.24% → ~2pt iPhone, ~3pt iPad.
    var trackGapUnit: CGFloat   { isLandscape ? screen.width * 0.0024 : screen.width * 0.005 }

    var muteLabelFont: CGFloat  { pickerFont }

    /// Vertical padding inside the mute button.
    var muteVPad: CGFloat       { tracksH * 0.025 }

    /// Pan knob square size in portrait (fits column width, capped by track height).
    var panKnobPortrait: CGFloat  { min(trackColW - 24, tracksH * 0.30) }

    /// Pan knob square size in landscape (height is the tight constraint).
    var panKnobLandscape: CGFloat { min(tracksH * 0.52, trackColW * 0.38) }

    /// Horizontal padding on either side of the pan knob in portrait.
    var panHPad: CGFloat        { trackColW * 0.12 }

    /// Top padding above the pan knob in portrait.
    var panVPadTop: CGFloat     { tracksH * 0.04 }

    // iPhone portrait reference: tracksH ≈ 253pt → trackW=6pt (2.37%), thumbW=20pt (7.90%), thumbH=12pt (4.74%)
    var faderTrackW: CGFloat { max(tracksH * 0.0237, 4) }
    var faderThumbW: CGFloat { max(tracksH * 0.0790, 14) }
    var faderThumbH: CGFloat { max(tracksH * 0.0474, 8) }
}

struct LayoutMetricsKey: EnvironmentKey {
    static let defaultValue = LayoutMetrics(
        screen: CGSize(width: 390, height: 844), isLandscape: false, isIpad: false)
}
extension EnvironmentValues {
    var metrics: LayoutMetrics {
        get { self[LayoutMetricsKey.self] }
        set { self[LayoutMetricsKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { geo in
            let isLandscape         = geo.size.width > geo.size.height
            let isIpad              = hSize == .regular
            let needsCombinedLfoRow = isLandscape
            let needsSideBySide     = isLandscape
            let m = LayoutMetrics(screen: geo.size, isLandscape: isLandscape, isIpad: isIpad)

            VStack(spacing: 0) {
                if isLandscape {
                    HStack(spacing: 0) {
                        TracksView(isLandscape: true)
                        TransportColumnView()
                            .frame(width: m.transportColW)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(C.border, lineWidth: 0.5))
                            .padding(.horizontal, m.transportHPad)
                    }
                    .frame(height: m.tracksH)
                } else {
                    TracksView(isLandscape: false)
                        .frame(height: m.tracksH)
                    TransportBarView()
                        .frame(height: m.transportBarH)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(C.border, lineWidth: 0.5))
                        .padding(.vertical, m.transportVPad)
                        .padding(.horizontal, m.transportHPad)
                }

                LFOPanelView(needsCombinedLfoRow: needsCombinedLfoRow, needsSideBySide: needsSideBySide)
                    .frame(maxHeight: .infinity)

                StatusBarView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.metrics, m)
            .background(C.bg)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Status bar (connection + tempo mode) — always at the root level so it can't be clipped

struct StatusBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.metrics) private var m
    @State private var showDevicePicker = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showDevicePicker = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.isConnected ? C.green : C.yellow)
                        .frame(width: 7, height: 7)
                    Text(app.connectionLabel)
                        .font(.system(size: m.statusBarFont, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                if app.isClockMaster { app.disableClock() } else { app.enableClock() }
            } label: {
                HStack(spacing: 0) {
                    Text("tempo: ")
                        .foregroundColor(.white)
                    Text(app.isClockMaster ? "app (midi sync)" : "op1 (beat match)")
                        .foregroundColor(app.isClockMaster ? C.green : C.track(1))
                }
                .font(.system(size: m.statusBarFont, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, m.statusBarVPad)
        .background(C.bg2)
        .sheet(isPresented: $showDevicePicker) { DevicePickerView() }
    }
}

// MARK: - Device picker sheet (used by StatusBarView)


struct DevicePickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: USB / Network MIDI
                    Text("usb / network midi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(C.dim)
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    if app.usb.discovered.isEmpty {
                        Text("no usb midi devices found")
                            .foregroundColor(C.dim)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(app.usb.discovered, id: \.self) { name in
                            Button {
                                app.usb.connectTo(name)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "cable.connector").foregroundColor(C.text)
                                    Text(name)
                                        .foregroundColor(C.text)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(C.dim)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }

                    // MARK: BLE MIDI
                    Divider().padding(.top, 8)

                    Text("bluetooth midi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(C.dim)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    if app.ble.discovered.isEmpty {
                        Group {
                            switch app.ble.state {
                            case .scanning:
                                Label("scanning for ble midi devices…", systemImage: "wave.3.right")
                            case .off:
                                Label("bluetooth is off", systemImage: "wifi.slash")
                            default:
                                Label("no ble midi devices found", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .foregroundColor(C.dim)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    } else {
                        ForEach(app.ble.discovered, id: \.identifier) { p in
                            Button {
                                app.usb.disconnect()   // yield routing priority to BLE
                                app.ble.connect(p)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(C.text)
                                    Text(p.name ?? p.identifier.uuidString)
                                        .foregroundColor(C.text)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(C.dim)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }

                    Divider().padding(.top, 8)

                    Button("disconnect") {
                        app.ble.disconnect()
                        app.usb.disconnect()
                        dismiss()
                    }
                    .foregroundColor(C.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(C.bg)
            .navigationTitle("midi device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            app.usb.rescan()
            // Restart BLE scan if it timed out before the picker was opened
            if case .notFound = app.ble.state { app.ble.startScan() }
        }
    }
}

// MARK: - Help sheet (used by LFOPanelView)

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var wavePhase: Double = 0

    private let sections: [(String, Text)] = [
        ("mute", Text("tap a track's colored number pad to mute/unmute it. bright colored background = unmuted; dark background = muted.")),
        ("pan", Text("drag up/down on a knob to pan right/left. release near top dead center to snap to center. [vertical scrubbing for horizontal controls like pan are hard. i'm open to better ideas...]")),
        ("volume", Text("drag up/down on a fader to set that track's volume. drag to the side for fine scrubbing.")),
        ("transport", Text("play/stop control op1 tape playback (play only works when the app is the clock master). left/right arrow buttons step the op1 tape position backward/forward.")),
        ("metronome & tempo mode", Text("tap the metronome icon to switch the clock source. then change the op1 to match.\n\(Text("op1 (beat match)").foregroundColor(C.track(1))) — op1 is master\n· app's lfos follow op1's tempo.\n\(Text("app (midi sync)").foregroundColor(C.green)) — app is master\n· app controls op1 tape transport (play/stop/back/forward).\n\(Text("· note: ").bold())tempo control requires 'app (midi sync)' mode and usb-c; bluetooth does not send high-resolution tempo changes.")),
        ("tempo & bpm", Text("drag up/down to scrub the tempo. double-tap or long-press the box to type an exact bpm.\n\(Text("· note: ").bold())tempo control requires 'app (midi sync)' mode and usb-c; bluetooth does not send high-resolution tempo changes.")),
        ("track & master", Text("tap to cycle off → on → inverted. tracks apply the lfo to that single track; master applies it to the selected master-capable parameter (e.g. tempo) across all tracks.")),
        ("preview (p)", Text("enables live preview: the current editor settings are sent to the op-1 in real time as you adjust them, so you can hear the effect while dialing in speed, depth, center, and wave shape. no chip is created — press repeat or 1x to create an lfo.")),
        ("parameter & curve", Text("choose which parameter the lfo modulates, and which waveform shape it follows. tap the icons to step to the next option without opening the picker.")),
        ("speed & center & depth", Text("drag up/down on a box to scrub its value. tap the speed (timer) icon to step to the next speed value one at a time. speed sets lfo speed, depth sets its range, center sets its midpoint.")),
        ("waveform preview", Text("when no lfo chips are running, shows the current editor settings as a preview. when chips are active, shows all running lfo curves overlaid, colored per track.")),
        ("repeat & one-shot & delete", Text("start the lfo looping, start it once, or delete all currently active lfos.")),
        ("active lfos", Text("lfos are shown as 'chips' showing 'track/master·parameter·wave·speed·center±depth·repeat/loop'.\n\(Text("tap").bold()) — toggle the lfo on/off without stopping it.\n\(Text("long-press").bold()) — enter edit mode; adjust controls to update the chip live, then long-press again to commit.\n\(Text("×").bold()) — stop and remove that lfo.\n\(Text("tap empty space").bold()) — cancel the current edit.")),
        ("status bar", Text("shows the current midi connection and clock source; tap it to choose a ble midi device."))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header: logo + title
                    HStack(spacing: 12) {
                        Image("AppIconArt")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.border, lineWidth: 0.5))
                        Text("op1 lfo hero")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(C.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                    Divider()

                    ForEach(sections, id: \.0) { title, body in
                        VStack(alignment: .leading, spacing: isPad ? 10 : 6) {
                            Text(title)
                                .font(.system(size: isPad ? 18 : 13, weight: .semibold))
                                .foregroundColor(C.text)
                                .padding(.top, isPad ? 28 : 20)
                                .padding(.horizontal, isPad ? 24 : 16)
                            body
                                .font(.system(size: isPad ? 17 : 15))
                                .foregroundColor(C.text)
                                .padding(.horizontal, isPad ? 24 : 16)
                                .padding(.bottom, isPad ? 18 : 12)
                            Divider()
                        }
                    }

                    // Wave footer
                    ColorfulSplashWave(phase: wavePhase)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                }
            }
            .background(C.bg)
            .navigationTitle("help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    wavePhase = 1
                }
            }
        }
        .presentationDetents(isPad ? [.fraction(0.92)] : [.large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings sheet (used by LFOPanelView)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var wavePhase: Double = 0

    @AppStorage("chipPauseAction")         private var chipPauseAction: String = "previous"
    @AppStorage("oneShotFinishAction")     private var oneShotFinishAction: String = "hold"
    @AppStorage("cleanupOneShots")         private var cleanupOneShots: Bool = false

    @State private var quantumSync     = false
    @State private var defiantJazzMode = false
    @State private var yoloVelocity    = false
    @State private var retrograde      = false
    @State private var cowbell         = true
    @State private var aiVibeCheck     = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header: logo + title
                    HStack(spacing: 12) {
                        Image("AppIconArt")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.border, lineWidth: 0.5))
                        Text("op1 lfo hero")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(C.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                    Divider()

                    settingRowPicker(
                        "lfo chip: on pause",
                        "what to send to the op-1 when any lfo chip is manually paused: previous = original value before lfo started. center = lfo center value. hold = send nothing, op-1 keeps last lfo value.",
                        $chipPauseAction,
                        ["previous", "center", "hold"]
                    )

                    settingRowPicker(
                        "one-shot lfo chip: on finish",
                        "what to send to the op-1 when a one-shot lfo chip finishes or is paused: previous = original value before lfo started. center = lfo center value. hold = send nothing, op-1 keeps last lfo value.",
                        $oneShotFinishAction,
                        ["previous", "center", "hold"]
                    )

                    settingRow(
                        "clean up one-shot lfo chips",
                        "when a one-shot lfo chip finishes, delete it from the list. off = keep it in a paused state; tap it to run it again.",
                        $cleanupOneShots
                    )

                    settingRow(
                        "quantum tempo sync",
                        "no cap — aligns your bpm with the fabric of the universe. slay or get slayed.",
                        $quantumSync
                    )
                    settingRow(
                        "defiant jazz mode",
                        "randomly replaces your notes with more sophisticated ones. ritualistic dancing is encouraged.",
                        $defiantJazzMode
                    )
                    settingRow(
                        "yolo velocity",
                        "sends every midi message at velocity 127. the era of nuance is dead and buried.",
                        $yoloVelocity
                    )
                    settingRow(
                        "retrograde playback",
                        "reverses tape direction in ways the op-1 doesn't actually support. understood the assignment.",
                        $retrograde
                    )
                    settingRow(
                        "cowbell boost",
                        "too much is never enough. periodt.",
                        $cowbell
                    )
                    settingRow(
                        "ai vibe check",
                        "your aura is being evaluated rn. bestie is not impressed and your rizz is cooked.",
                        $aiVibeCheck
                    )
                    // Wave footer
                    ColorfulSplashWave(phase: wavePhase)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                }
            }
            .background(C.bg)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    wavePhase = 1
                }
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
        .presentationDetents(isPad ? [.fraction(0.92)] : [.large])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func settingRowPicker(_ title: String, _ desc: String, _ selection: Binding<String>, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: isPad ? 6 : 4) {
                Text(title)
                    .font(.system(size: isPad ? 18 : 13, weight: .semibold))
                    .foregroundColor(C.text)
                Text(desc)
                    .font(.system(size: isPad ? 17 : 15))
                    .foregroundColor(C.text)
                Picker("", selection: selection) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            }
            .padding(.top, isPad ? 24 : 18)
            .padding(.horizontal, isPad ? 24 : 16)
            .padding(.bottom, isPad ? 18 : 12)
            Divider()
        }
    }

    @ViewBuilder
    private func settingRow(_ title: String, _ desc: String, _ isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: isPad ? 6 : 4) {
                    Text(title)
                        .font(.system(size: isPad ? 18 : 13, weight: .semibold))
                        .foregroundColor(C.text)
                    Text(desc)
                        .font(.system(size: isPad ? 17 : 15))
                        .foregroundColor(C.text)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(C.green)
            }
            .padding(.top, isPad ? 24 : 18)
            .padding(.horizontal, isPad ? 24 : 16)
            .padding(.bottom, isPad ? 18 : 12)
            Divider()
        }
    }
}
