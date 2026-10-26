import CoreBluetooth
import SwiftUI

// MARK: - Layout metrics (single source of truth for all dimensional values)

struct LayoutMetrics {
    let screen: CGSize
    let isLandscape: Bool
    let isIpad: Bool
    /// How many mixer strips the active device has (4 on the OP-1, 6 on the TX-6 / TP-7).
    /// Every column formula below divides by this rather than by a literal.
    var trackCount: Int = 4
    /// Whether the active device has a pan knob. In landscape the knob sits beside the fader and
    /// takes most of the strip, so `faderColW` — and the digit size derived from it — depend on it.
    var hasPan: Bool = true

    // ── Tier 1: structural — how the screen is divided into zones ───────────

    /// Width of the transport column in landscape — sized so every column (tracks + transport)
    /// has equal content width.
    var transportColW: CGFloat {
        let cols = CGFloat(trackCount + 1)
        return (screen.width - cols * trackGapUnit) / cols
    }

    /// Height of the mixer + track strips row.
    var tracksH: CGFloat {
        if isLandscape { return screen.height * 0.38 }  // landscape: same ratio for iPhone + iPad
        if !isIpad     { return screen.height * 0.25 }  // iPhone portrait: shorter mixer row
        return screen.height * 0.30
    }

    /// Height of the portrait transport bar (play/stop/BPM row).
    var transportBarH: CGFloat { screen.height * 0.10 }

    /// Width of a single track column (the device's tracks share the mixer width).
    var trackColW: CGFloat {
        let mixerW = isLandscape ? screen.width - transportColW : screen.width
        return mixerW / CGFloat(max(1, trackCount))
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

    /// Buttons in the LFO target row: one per track, plus master and preview.
    var toggleBtnCount: Int { trackCount + 2 }

    /// iPhone portrait fits at most 6 buttons before the 44pt minimum touch target overflows
    /// the screen width, so a 6-track device wraps onto a second row.
    var toggleBtnRows: Int { (!isLandscape && !isIpad && toggleBtnCount > 6) ? 2 : 1 }

    var toggleBtnPerRow: Int {
        Int((Double(toggleBtnCount) / Double(toggleBtnRows)).rounded(.up))
    }

    // Landscape uses larger fractions: single combined row means more lfoH per element.
    var toggleBtnSize: CGFloat    {
        if isLandscape { return max(lfoH * 0.22, 44) }
        if isIpad      { return max(lfoH * 0.13, 44) }
        // iPhone portrait: fit one row of buttons + gaps + 2 side margins within screen width
        let margin  = 3 * trackGapUnit
        let spacing = max(lfoH * 0.012, 6)
        let n = CGFloat(max(1, toggleBtnPerRow))
        let fit = (screen.width - 2 * margin - (n - 1) * spacing) / n
        // A wrapped row has fewer buttons, which would otherwise make each one much larger.
        // Cap at the width a full 6-button row gives so wrapping adds a row, not bulk.
        let cap = (screen.width - 2 * margin - 5 * spacing) / 6
        return max(min(fit, cap), 44)
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

    // ── Tier 2: first-run tutorial ───────────────────────────────────

    /// Hint card width. Landscape has height to spare beside the target but not above it, so the
    /// card is narrower there; iPad portrait would otherwise stretch a two-line hint to one.
    var tourCardW: CGFloat {
        if isLandscape { return screen.width * (isIpad ? 0.34 : 0.42) }
        return screen.width * (isIpad ? 0.50 : 0.88)
    }
    /// Card text and padding all scale with the card, so the card keeps its proportions.
    var tourCardPad: CGFloat      { tourCardW * 0.045 }
    var tourTitleFont: CGFloat    { tourCardW * 0.046 }
    var tourBodyFont: CGFloat     { tourCardW * 0.042 }
    var tourBtnFont: CGFloat      { tourCardW * 0.042 }
    /// The close x is a bare glyph, so it needs to be much larger than the words beside it to read.
    var tourCloseFont: CGFloat    { tourBtnFont * 1.6 }
    /// Width of the counter (left) and close x (right) either side of the centered title.
    var tourCardSideW: CGFloat    { tourCardW * 0.2 }
    /// How far the spotlight hole extends past the control it frames.
    var tourSpotlightInset: CGFloat  { trackGapUnit * 2 }
    var tourSpotlightRadius: CGFloat { tourSpotlightInset * 2 }
    /// Gap between the hole and the card, and the card's minimum margin to the screen edge —
    /// the standard 6pt zone gap.
    var tourCardGap: CGFloat { isLandscape ? screen.width * 0.007 : screen.width * 0.015 }

    // ── Tier 2: track strip content ─────────────────────────────────────

    /// Clearance between a volume digit and the fader thumb it sits beside — half the thumb, so
    /// the digit stops exactly where the thumb's widest point begins. Derived from the thumb
    /// rather than the font, which is what it is actually protecting against and which breaks
    /// the circular dependency with `volValueFont` below.
    var volValueSpacing: CGFloat { faderThumbW / 2 }

    /// Monospaced digit advance as a fraction of point size. SF Mono is 0.6em; used to work out
    /// whether a digit fits the space it has.
    private var digitAdvance: CGFloat { 0.6 }

    /// Fader digit font size, sized from the width the digits actually get.
    ///
    /// Two digits sit either side of the thumb inside the *fader*, not the track column — in
    /// landscape the pan knob takes most of the column. Sizing this against `trackColW` (which
    /// also ignores the inter-strip gaps) made the digits about twice the available width, so
    /// both glyphs were clipped on their right edge. The caps are unchanged, so any layout with
    /// room to spare looks exactly as before.
    var volValueFont: CGFloat {
        let perDigit = faderColW / 2 - volValueSpacing
        return min(perDigit / digitAdvance, isIpad ? 58 : 28)
    }

    /// Padding between a strip's edge and its contents, and between the pan knob and the fader.
    /// Deliberately tight: this is the width the volume digits are competing for.
    var stripInnerPad: CGFloat { trackGapUnit * 1.4 }
    var panFaderGap: CGFloat   { trackGapUnit * 1.4 }

    /// The width one strip's *content* actually gets. `trackColW` is the nominal column and
    /// ignores the gaps `TracksView` and `TrackStripView` add — about 5% narrower in practice —
    /// so anything sized against it overestimates.
    var stripContentW: CGFloat {
        let mixerW  = isLandscape ? screen.width - transportColW : screen.width
        let n       = CGFloat(max(1, trackCount))
        let perStrip = (mixerW - 2 * trackGapUnit - (n - 1) * trackGapUnit) / n
        return perStrip - 2 * trackGapUnit
    }

    /// Width available to the fader itself. In landscape the pan knob sits beside it; in portrait
    /// the knob is above, so the fader has the whole strip. Devices without pan (the TP-7) give
    /// the fader the strip in both orientations.
    var faderColW: CGFloat {
        guard isLandscape else { return stripContentW }
        guard hasPan else { return stripContentW - 2 * stripInnerPad }
        return stripContentW - panKnobLandscape - 2 * stripInnerPad - panFaderGap
    }

    /// Gap unit between track columns: total visual gap = 3 × trackGapUnit (right pad + spacing + left pad).
    /// Portrait: 0.5% of width → ~2pt iPhone, ~5pt iPad. Landscape: 0.24% → ~2pt iPhone, ~3pt iPad.
    var trackGapUnit: CGFloat   { isLandscape ? screen.width * 0.0024 : screen.width * 0.005 }

    var muteLabelFont: CGFloat  { pickerFont }

    /// Vertical padding inside the mute button.
    var muteVPad: CGFloat       { tracksH * 0.025 }

    /// Pan knob square size in portrait (fits column width, capped by track height).
    /// 0.754 reproduces the previous `trackColW - 24` at the iPhone-portrait reference width.
    var panKnobPortrait: CGFloat  { min(trackColW * 0.754, tracksH * 0.30) }

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
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tour: TourController
    @State private var lfoControlsFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            let isLandscape         = geo.size.width > geo.size.height
            let isIpad              = hSize == .regular
            let needsCombinedLfoRow = isLandscape
            let needsSideBySide     = isLandscape
            let m = LayoutMetrics(screen: geo.size, isLandscape: isLandscape, isIpad: isIpad,
                                  trackCount: app.profile.trackCount,
                                  hasPan: app.profile.caps.hasPan)

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
            .coordinateSpace(name: onDeckSpace)
            .onPreferenceChange(OnDeckControlsKey.self) { lfoControlsFrame = $0 }
            // Simultaneous, so the control that was touched still gets its own gesture. Decided on
            // where the touch began.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(onDeckSpace))
                    .onChanged { g in
                        let onControls = lfoControlsFrame.contains(g.startLocation)
                        if app.onDeckTouched != onControls { app.onDeckTouched = onControls }
                    }
            )
            // While the tour is up, VoiceOver can't reach the controls under it either.
            .accessibilityHidden(tour.isActive)
            .overlayPreferenceValue(TourAnchorKey.self) { TourOverlayLayer(anchors: $0) }
            .environment(\.metrics, m)
            .background(C.bg)
            .preferredColorScheme(.dark)
        }
        .onAppear { tour.profileChanged(app.tourCaps) }
        // Fires when the device changes and when one is first connected or picked, since either
        // can add or remove steps.
        .onChange(of: app.tourDevice?.id) { _, _ in tour.profileChanged(app.tourCaps) }
    }
}

// MARK: - Status bar (connection + tempo mode) — always at the root level so it can't be clipped

struct StatusBarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject private var tour: TourController
    @Environment(\.metrics) private var m
    @State private var showDevicePicker = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showDevicePicker = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.isConnected ? C.green : C.yellow)
                        .frame(width: 7, height: 7)
                    Text(app.connectionLabel.lowercased())   // device names arrive in the device's own case
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
                    Text(app.isClockMaster
                         ? "app (midi sync)"
                         : "\(app.profile.caps.clockLabel) (beat match)")
                        .foregroundColor(app.isClockMaster ? C.green : C.track(1))
                }
                .font(.system(size: m.statusBarFont, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tempoModeButton")
            // Devices that never emit MIDI clock can't be the tempo source, so the app stays master.
            .disabled(!app.profile.caps.canBeClockMaster)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, m.statusBarVPad)
        .background(C.bg2)
        .tourAnchor(.statusBar)
        .sheet(isPresented: $showDevicePicker) { DevicePickerView() }
        .onChange(of: showDevicePicker) { _, shown in tour.sheet(shown) }
    }
}

// MARK: - Device picker sheet (used by StatusBarView)


/// Trailing mark on a device row: "connected" in green when it is the live device, otherwise the
/// usual chevron.
private struct ConnectedBadge: View {
    let connected: Bool
    var body: some View {
        if connected {
            HStack(spacing: 4) {
                Text("connected")
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(C.green)
        } else {
            Image(systemName: "chevron.right").foregroundColor(C.dim)
        }
    }
}

private extension View {
    /// A light green box around the row, so the connected device is obvious at a glance.
    func connectedHighlight(_ on: Bool) -> some View {
        self
            .background(on ? C.green.opacity(0.18) : Color.clear)
            .overlay(Rectangle().stroke(on ? C.green.opacity(0.7) : Color.clear, lineWidth: 1))
            .accessibilityValue(on ? "connected" : "")
    }
}

struct DevicePickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// Whether the list row `rowName` is the device the app is connected to right now. Only the
    /// *active* transport counts: if both are connected, the one that carries MIDI is the one
    /// that gets the highlight. Names are compared exactly as the lists show them.
    static func isConnectedRow(_ rowName: String, connectedName: String?, transportIsActive: Bool) -> Bool {
        guard transportIsActive, let connectedName else { return false }
        return rowName.caseInsensitiveCompare(connectedName) == .orderedSame
    }

    /// Same, for a Bluetooth row: matched by peripheral identity, because a BLE device's name can
    /// differ between the advertisement the list was built from and the connected peripheral.
    static func isConnectedRow(_ rowID: UUID, connectedID: UUID?, transportIsActive: Bool) -> Bool {
        transportIsActive && connectedID == rowID
    }

    private var connectedUSBName: String? {
        if case .connected(let n) = app.usb.state { return n }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: USB / Network MIDI
                    Text("usb / network midi")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(C.text)
                        .padding(.top, 20)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    if app.usb.discovered.isEmpty {
                        Text("no usb midi devices found")
                            .foregroundColor(C.text)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(app.usb.discovered, id: \.self) { name in
                            let connected = Self.isConnectedRow(
                                name, connectedName: connectedUSBName,
                                transportIsActive: app.router.effectiveTransport == .usb)
                            Button {
                                app.usb.connectTo(name)
                                app.router.setActiveTransport(.usb)
                            } label: {
                                HStack {
                                    Image(systemName: "cable.connector").foregroundColor(C.text)
                                    Text(name.lowercased())
                                        .foregroundColor(C.text)
                                    Spacer()
                                    ConnectedBadge(connected: connected)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .connectedHighlight(connected)
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
                        .foregroundColor(C.text)
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
                        .foregroundColor(C.text)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    } else {
                        ForEach(app.ble.discovered, id: \.identifier) { p in
                            let connected = Self.isConnectedRow(
                                p.identifier, connectedID: app.ble.connectedPeripheralID,
                                transportIsActive: app.router.effectiveTransport == .ble)
                            Button {
                                app.ble.connect(p)
                                app.router.setActiveTransport(.ble)
                            } label: {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(C.text)
                                    Text((p.name ?? p.identifier.uuidString).lowercased())
                                        .foregroundColor(C.text)
                                    Spacer()
                                    ConnectedBadge(connected: connected)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .connectedHighlight(connected)
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
            // While the menu is open, scan continuously with no "not found" flicker —
            // the user is actively looking for a device and may take a while to power it on.
            app.ble.startScan(continuous: true)
        }
        .onDisappear {
            // Back to the shorter, give-up-eventually launch scan once the menu is closed.
            app.ble.startScan(continuous: false)
        }
    }
}

// MARK: - Help copy (shared by HelpView and the tutorial)

/// Section titles and short tutorial hints in one place, so the tour and help can't disagree.
/// Help keeps the long text; the tour shows `tourTitle` plus `tourText`.
enum HelpCopy {
    static func title(_ a: TourAnchor) -> String {
        switch a {
        case .welcome:      return "welcome"
        case .statusBar:    return "status bar"
        case .mutePad:      return "mute"
        case .panKnob:      return "pan"
        case .volumeFader:  return "volume"
        case .transport:    return "transport"
        case .bpm:          return "tempo bpm"
        case .tempoMode:    return "tempo source"
        case .trackToggle:  return "tracks"
        case .masterToggle: return "master"
        case .preview:      return "preview"
        case .paramPicker:  return "parameter & curve"
        case .wavePicker:   return "wave shape"
        case .speedBox:     return "speed & center & depth"
        case .centerBox:    return "center"
        case .depthBox:     return "depth"
        case .waveform:     return "waveform preview"
        case .startButtons: return "repeat, 1x, delete"
        case .chipArea:     return "lfo chips"
        case .helpSettings: return "help & settings"
        }
    }

    /// Help covers parameter + wave, and speed + center + depth, in one section each; the tour
    /// gives each control its own step, so those steps get narrower titles.
    static func tourTitle(_ a: TourAnchor) -> String {
        switch a {
        case .paramPicker: return "parameter"
        case .speedBox:    return "speed"
        default:           return title(a)
        }
    }

    /// `device` is nil until the app knows which device the user has (see `AppState.tourDevice`);
    /// the wording is then neutral rather than naming a device that was only remembered.
    static func tourText(_ a: TourAnchor, device: DeviceProfile?) -> String {
        let dev = device?.displayName.lowercased() ?? "device"
        let clk = device?.caps.clockLabel ?? "device"
        switch a {
        case .welcome:
            // Every supported device, not just the connected one: a first-time user may not have
            // connected anything yet. "a, b, or c" from the registry, so a new profile joins in.
            let names = DeviceRegistry.all.map { $0.displayName }
            let list = names.count > 1
                ? names.dropLast().joined(separator: ", ") + ", or " + names.last!
                : names.joined()
            return "op1 lfo hero sends beat-synced lfos to your \(list). this quick tour shows what each control does and how to use it. you can replay it any time from help."
        case .statusBar:
            // Two tap targets: the connection (left) and the tempo mode (right).
            return "two buttons. left: midi connection (usb-c and ble), tap to pick and connect to a device. right: tempo source, tap to switch between app (midi sync) and \(clk) (beat match)."
        case .mutePad:
            return "tap a track's colored number pad to mute or unmute it."
        case .panKnob:
            return "drag up/down on a track's knob to pan right/left."
        case .volumeFader:
            return "drag up/down to set a track's volume. drag sideways while scrubbing for fine control."
        case .transport:
            return "play and stop the \(dev)'s tape. left/right arrows (op-1 field and tp-7) move tape backward and forward. -/+ (tx-6) change tempo bpm."
        case .bpm:
            return "drag up/down to scrub the tempo. double-tap or long-press to type an exact bpm."
        case .tempoMode:
            return "tap to switch the tempo source: app (midi sync) or \(clk) (beat match). then set the \(dev) to match."
        case .trackToggle:
            return "choose which tracks the lfo drives. tap to cycle off → on → inverted."
        case .masterToggle:
            return "applies the lfo parameter to master, not a track. only avilable for some parameters. tap to cycle off → on → inverted."
        case .preview:
            return "preview the lfo live while changing settings, so you can hear the effect before creating an lfo."
        case .paramPicker:
            return "choose what the lfo changes. drag up/down to scrub through the parameters, or tap to open the list. tap the bolt icon to step to the next parameter."
        case .wavePicker:
            return "choose the lfo's wave shape. drag up/down to scrub through the shapes, or tap to open the list. tap the wave icon to step to the next shape. slope is a single ramp over twice the speed, best as 1x on slow free rates. hold sends the center value, use with 1x to reset a parameter."
        case .speedBox:
            return "choose the lfo's speed. 8 to 1 are synced to the tempo, fastest to slowest. f1 to f17 are free and ignore the tempo, slowest to fastest. drag up/down to scrub it, or tap to open the list. tap the timer icon to step to the next speed."
        case .centerBox:
            return "choose the center value the lfo swings around. drag up/down to scrub it, or tap the center icon to snap it to the current value."
        case .depthBox:
            return "choose the depth the lfo swings either side of center. drag up/down to scrub it."
        case .waveform:
            return "shows the lfo you're setting up while you touch its controls, otherwise every running lfo in its track's color."
        case .startButtons:
            return "create an lfo from current settings that loops (repeat) or runs once (1x). or delete all lfos."
        case .chipArea:
            return "lfo chips created as loop or 1x are shown here. tap chips to pause, long-press to edit (and again to save changes), or tap × to delete."
        case .helpSettings:
            return "show descriptions for every control, or replay this tutorial, from help. change options from settings."
        }
    }
}

// MARK: - Help sheet (used by LFOPanelView)

/// Vertical rhythm shared by the help and settings sheets, so the two read as one family.
private enum SheetGap {
    /// Space above an item's title.
    static func itemTop(_ isPad: Bool) -> CGFloat { isPad ? 18 : 14 }
    /// Space below an item's text or control.
    static func itemBottom(_ isPad: Bool) -> CGFloat { isPad ? 18 : 12 }
    /// Space between an item's title and its text.
    static func titleToText(_ isPad: Bool) -> CGFloat { isPad ? 6 : 4 }
    /// Extra space above a button, picker or other control under an item's text.
    static let controlTop: CGFloat = 4
}

/// The frame both sheets share: nav bar (title, "done", optional version), scrolling body with the
/// logo header on top and the wave footer below. A sheet only supplies its items.
private struct SheetScaffold<Content: View>: View {
    let title: String
    var showsVersion = false
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var wavePhase: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 0)

                    content

                    ColorfulSplashWave(phase: wavePhase)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                }
            }
            .background(C.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsVersion {
                    ToolbarItem(placement: .topBarLeading) { VersionLabel() }.withoutBubble()
                }
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

/// One entry in a sheet: a title, its text, then optionally a control underneath (picker, button)
/// or an accessory beside it (toggle). Every entry in help and settings goes through this, which
/// is what keeps their fonts and spacing identical.
private struct SheetItem<TextBody: View, Controls: View, Accessory: View>: View {
    let title: String
    var italic = false
    let text: TextBody
    let controls: Controls
    let accessory: Accessory

    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: SheetGap.titleToText(isPad)) {
                // Titles stay a touch larger than their text on both: 18 over 17 on iPad, 16 over 15
                // on iPhone (it was 13 over 15, which read as smaller than the description).
                Text(title)
                    .font(.system(size: isPad ? 18 : 16, weight: .semibold))
                    .italic(italic)
                    .foregroundColor(C.text)
                text
                    .font(.system(size: isPad ? 17 : 15))
                    .italic(italic)
                    .foregroundColor(C.text)
                if Controls.self != EmptyView.self {
                    controls.padding(.top, SheetGap.controlTop)
                }
            }
            if Accessory.self != EmptyView.self {
                Spacer(minLength: 0)
                accessory
            }
        }
        .padding(.top, SheetGap.itemTop(isPad))
        .padding(.horizontal, isPad ? 24 : 16)
        .padding(.bottom, SheetGap.itemBottom(isPad))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SheetItem where Controls == EmptyView, Accessory == EmptyView {
    fileprivate init(_ title: String, italic: Bool = false, @ViewBuilder text: () -> TextBody) {
        self.title = title; self.italic = italic
        self.text = text(); self.controls = EmptyView(); self.accessory = EmptyView()
    }
}

extension SheetItem where Accessory == EmptyView {
    fileprivate init(_ title: String, italic: Bool = false, @ViewBuilder text: () -> TextBody,
                     @ViewBuilder controls: () -> Controls) {
        self.title = title; self.italic = italic
        self.text = text(); self.controls = controls(); self.accessory = EmptyView()
    }
}

extension SheetItem where Controls == EmptyView {
    fileprivate init(_ title: String, italic: Bool = false, @ViewBuilder text: () -> TextBody,
                     @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.italic = italic
        self.text = text(); self.controls = EmptyView(); self.accessory = accessory()
    }
}

struct HelpView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var tour: TourController
    @Environment(\.dismiss) private var dismiss

    /// Devices that need settings changed on the hardware first — otherwise the app looks broken
    /// through no fault of its own. Shown above everything else, the tutorial included. Computed,
    /// not stored: the copy names the connected device, which is only known at render.
    private var setupSection: (String, Text)? {
        guard !app.profile.setupSteps.isEmpty else { return nil }
        let dev = app.profile.displayName
        var body = Text("before the app can control the \(dev), change these on the device itself:")
        for step in app.profile.setupSteps {
            body = body + Text("\n· ") + Text(step)
        }
        return ("\(dev) setup — do this first", body)
    }

    /// Computed for the same reason: the copy names the connected device.
    private var sections: [(String, Text)] {
        let dev = app.profile.displayName
        let clk = app.profile.caps.clockLabel
        return [
        (HelpCopy.title(.mutePad), Text("tap a track's colored number pad to mute/unmute it. bright colored background = unmuted; dark background = muted.")),
        (HelpCopy.title(.panKnob), Text("drag up/down on a knob to pan right/left. release near top dead center to snap to center.\n[vertical scrubbing for horizontal controls like pan are weird. i'm open to better ideas...]")),
        (HelpCopy.title(.volumeFader), Text("drag up/down on a fader to set that track's volume. drag to the side for fine scrubbing.")),
        (HelpCopy.title(.transport), Text("play/stop control op1 tape playback (play only works when the app is the clock master). play resumes from where the last play stopped, not from where you moved the tape by hand. left/right arrow buttons (op-1 field and tp-7) move the device's tape position backward/forward. -/+ buttons (tx-6) adjust the tempo bpm.")),
        (HelpCopy.title(.tempoMode), app.profile.caps.canBeClockMaster
            ? Text("tap the metronome icon to switch the clock source. then change the \(dev) to match.\n· \(Text("\(clk) (beat match)").foregroundColor(C.track(1))) — \(dev) is master — lfos follow the \(dev)'s tempo.\n· \(Text("app (midi sync)").foregroundColor(C.green)) — app is master — app controls the \(dev)'s transport (play/stop/back/forward).")
            : Text("the \(dev) does not send midi clock, so the app is always the tempo source. its lfos run on the app's own clock and the transport buttons drive the \(dev) over cc.")),
        (HelpCopy.title(.bpm), Text("drag up/down to scrub the tempo. double-tap or long-press the box to type an exact bpm.\n· app tempo control of op-1 field requires 'app (midi sync)' mode and usb-c\n· op-1 field ble midi does not send tempo change messages")),
        (HelpCopy.title(.trackToggle), Text("tap to cycle off → on → inverted. tracks apply the lfo to that single track; master applies it to the selected master-capable parameter (e.g. tempo) across all tracks.")),
        (HelpCopy.title(.preview), Text("enables live preview: the current editor settings are sent to the device in real time as you adjust them, so you can hear the effect while dialing in speed, depth, center, and wave shape. no chip is created — press repeat or 1x to create an lfo.")),
        (HelpCopy.title(.paramPicker), Text("choose which parameter the lfo modulates, and which waveform shape it follows. drag up/down on a box to scrub through its options, or tap it to open the list. tap the icons to step to the next option.\n· \(Text("slope").bold()) — one rising ramp over twice the speed. best as 1x on slow free rates, and it stays at the top.\n· \(Text("hold").bold()) — sends the center value and ignores depth. use with 1x to reset a parameter.")),
        (HelpCopy.title(.speedBox), Text("drag up/down on a box to scrub its value. on speed, tap the box to open the list, or tap the speed (timer) icon to step to the next speed value one at a time. speed sets lfo speed, depth sets its range, center sets its midpoint.")),
        (HelpCopy.title(.waveform), Text("while you set one up (a selected chip, preview on, or after you touch any of the lfo controls, until you touch anywhere else), shows only that lfo. otherwise shows every running lfo overlaid, colored per track, and leaves out paused ones. with none running, it shows the current settings as a preview.")),
        (HelpCopy.title(.startButtons), Text("start the lfo looping (repeat), run it once (one-shot), or delete all lfos.")),
        (HelpCopy.title(.chipArea), Text("lfos are shown as chips with abbreviated names. example: 'track/master·parameter·wave·speed·center±depth·repeat/loop'.\n· \(Text("tap").bold()) — toggle the lfo on/off\n· \(Text("long-press").bold()) — edit the controls for selected chip and hear changes live, then long-press again to save changes.\n· \(Text("tap anywhere else").bold()) — cancel the current edit.\n· \(Text("×").bold()) — stop and delete the lfo.")),
        (HelpCopy.title(.statusBar), Text(app.profile.caps.canBeClockMaster
            ? "· left side: midi device — tap it to connect to a usb or ble device\n· right side: tempo source — tap it to switch the tempo source (same as tapping the metronome icon)"
            : "· left side: midi device — tap it to connect to a usb or ble device\n· right side: tempo source — always set to 'app' on the \(dev)."))
        ]
    }

    var body: some View {
        SheetScaffold(title: "help", showsVersion: true) {
            if let (title, body) = setupSection {
                SheetItem(title) { body }
            }
            SheetItem("tutorial", text: {
                Text("a step-by-step tour of every button and knob: what each one does and how to use it.")
            }, controls: {
                Button("start tutorial") { tour.replay(); dismiss() }
                    .buttonStyle(CapsuleButtonStyle(fill: C.track(1)))
                    .accessibilityIdentifier("replayTourFromHelp")
                    .frame(maxWidth: .infinity)
            })
            ForEach(sections, id: \.0) { title, body in
                SheetItem(title) { body }
            }
        }
    }
}

private extension ToolbarContent {
    /// iOS 26 draws every toolbar item in a rounded glass bubble, which makes plain text look like
    /// a button. The version is information only, so drop the bubble where the system allows it.
    @ToolbarContentBuilder func withoutBubble() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// App version at the top left of the help sheet, opposite "done". Read from the
/// bundle so the project's MARKETING_VERSION stays the only place the number is written down.
private struct VersionLabel: View {
    var body: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Text(v.isEmpty ? "" : "v\(v)")
            .font(.body)
            .italic()
            .foregroundColor(C.text)
            .lineLimit(1)
            .fixedSize()    // a toolbar item otherwise squeezes the text to "v1...."
            .accessibilityIdentifier("versionLabel")
    }
}

// MARK: - Settings sheet (used by LFOPanelView)

struct SettingsView: View {
    /// Stores the *displayed* label, exactly like every other picker here, and maps it to a
    /// profile id in onChange. Binding through `app` or through a tuple-tagged picker both
    /// lose the selection when the view rebuilds mid-gesture.
    @AppStorage("deviceOverrideLabel") private var deviceOverride: String = "auto"

    @EnvironmentObject private var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    @AppStorage("chipPauseAction")         private var chipPauseAction: String = "previous"
    @AppStorage("oneShotFinishAction")     private var oneShotFinishAction: String = "hold"
    @AppStorage("cleanupOneShots")         private var cleanupOneShots: Bool = false

    /// Shown for either joke toggle's forbidden action; nil = no message box on screen.
    @State private var jokeMessage: String?
    /// Always on — cowbell boost cannot be turned off.
    @State private var cowbell         = true

    var body: some View {
        SheetScaffold(title: "settings") {
            SheetItem("device", text: {
                Text("the teenage engineering device connected to the app. display controls change to match. auto detected from the midi connection name. set it manually if using a hub or a generically-named port. or to see what it looks like.")
            }, controls: {
                segmented(["auto"] + DeviceRegistry.all.map(\.displayName), $deviceOverride,
                          accessibilityId: "deviceOverridePicker")
            })

            SheetItem("lfo chip: on pause", text: {
                Text("what to send to the device when any lfo chip is manually paused: previous = original value before lfo started. center = lfo center value. hold = send nothing, the device keeps the last lfo value.")
            }, controls: {
                segmented(["previous", "center", "hold"], $chipPauseAction)
            })

            SheetItem("one-shot lfo chip: on finish", text: {
                Text("what to send to the device when a one-shot lfo chip finishes or is paused: previous = original value before lfo started. center = lfo center value. hold = send nothing, the device keeps the last lfo value.")
            }, controls: {
                segmented(["previous", "center", "hold"], $oneShotFinishAction)
            })

            toggleItem(
                "clean up one-shot lfo chips",
                "when a one-shot lfo chip finishes, delete it from the list. off = keep it in a paused state; tap it to run it again.",
                $cleanupOneShots
            )

            // Deliberately does not touch the tutorial, which lives in help.
            SheetItem("reset settings", text: {
                Text("put all settings back to default values.")
            }, controls: {
                Button("reset to defaults") { resetToDefaults() }
                    .buttonStyle(CapsuleButtonStyle())
                    .frame(maxWidth: .infinity)
            })

            toggleItem(
                "defiant jazz mode",
                "randomly replaces your notes with more sophisticated ones. ritualistic dancing is encouraged.",
                Binding(get: { false }, set: { on in
                    if on { jokeMessage = "The Music Dance Experience is officially canceled." }
                }),
                joke: true
            )
            toggleItem(
                "cowbell boost",
                "too much is never enough. periodt.",
                Binding(get: { true }, set: { on in
                    if !on { jokeMessage = "I gotta have more cowbell, baby!" }
                    cowbell = true
                }),
                joke: true
            )
        }
        // Map the displayed label to a profile id, then tell AppState to pick up the device.
        .onChange(of: deviceOverride) { _, label in
            let id = label == "auto"
                ? "auto"
                : (DeviceRegistry.all.first { $0.displayName == label }?.id ?? "auto")
            UserDefaults.standard.set(id, forKey: AppState.profileOverrideKey)
            app.resolveProfile()
        }
        .overlay {
            if let message = jokeMessage {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { jokeMessage = nil }
                    .overlay {
                        Text(message)
                            .font(.system(size: isPad ? 18 : 15, weight: .semibold))
                            .foregroundColor(C.text)
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .frame(maxWidth: isPad ? 420 : 280)
                            .background(C.bg)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(C.border, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
            }
        }
    }

    private func resetToDefaults() {
        deviceOverride = "auto"
        chipPauseAction = "previous"
        oneShotFinishAction = "hold"
        cleanupOneShots = false
    }

    private func segmented(_ options: [String], _ selection: Binding<String>,
                           accessibilityId: String? = nil) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(accessibilityId ?? "")
    }

    private func toggleItem(_ title: String, _ desc: String, _ isOn: Binding<Bool>,
                            joke: Bool = false) -> some View {
        SheetItem(title, italic: joke, text: { Text(desc) }, accessory: {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(C.green)
        })
    }
}
