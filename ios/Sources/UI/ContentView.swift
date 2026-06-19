import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { geo in
            let isLandscape          = geo.size.width > geo.size.height
            let isIpad               = hSize == .regular
            let needsCombinedLfoRow  = isIpad || isLandscape
            let needsSideBySide      = isLandscape   // side-by-side only in landscape; iPad portrait uses stacked
            let transportColW: CGFloat = isIpad ? 240 : 120

            // Track section height — shorter in landscape to reclaim vertical space
            let tracksH: CGFloat = {
                if isLandscape && !isIpad { return min(max(160, geo.size.height * 0.40), 200) }  // iPhone landscape
                if isLandscape            { return min(max(320, geo.size.height * 0.40), 460) }  // iPad landscape
                return min(max(220, geo.size.height * 0.28), 340)                                // portrait — shorter sliders, more room for transport
            }()

            let transportH = min(max(80, geo.size.height * 0.10), 120)

            VStack(spacing: 0) {
                if isLandscape {
                    // Landscape: transport as 5th column beside the mixer
                    HStack(spacing: 0) {
                        TracksView(isLandscape: true)
                        Rectangle().fill(C.bg3).frame(width: 1)
                        TransportColumnView()
                            .frame(width: transportColW)
                    }
                    .frame(height: tracksH)
                } else {
                    // Portrait: original stacked layout
                    TracksView(isLandscape: false)
                        .frame(height: tracksH)
                        .padding(.bottom, 5)
                    Rectangle().fill(C.bg3).frame(height: 1)
                    TransportBarView()
                        .frame(height: transportH)
                }

                LFOPanelView(needsCombinedLfoRow: needsCombinedLfoRow, needsSideBySide: needsSideBySide)
                    .frame(maxHeight: .infinity)

                StatusBarView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(C.bg)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Status bar (connection + tempo mode) — always at the root level so it can't be clipped

struct StatusBarView: View {
    @EnvironmentObject var app: AppState
    @State private var showDevicePicker = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showDevicePicker = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.isConnected ? C.green : C.yellow)
                        .frame(width: 7, height: 7)
                    Text(app.connectionLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 0) {
                Text("tempo: ")
                    .foregroundColor(.white)
                Text(app.isClockMaster ? "app (midi sync)" : "op1 (beat match)")
                    .foregroundColor(app.isClockMaster ? C.green : C.track(1))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
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
                        Label("scanning for ble midi devices…", systemImage: "wave.3.right")
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
    }
}

// MARK: - Help sheet (used by LFOPanelView)

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var wavePhase: Double = 0

    private let sections: [(String, Text)] = [
        ("mute buttons", Text("tap a track's colored number to mute/unmute it. bright colored background = unmuted; dark background = muted.")),
        ("pan knobs", Text("drag up/down on a knob to pan right/left. release near the top to snap to center. [vertical scrubbing for a horizontal control like pan is weird. i'm open to better ideas...]")),
        ("volume faders", Text("drag up/down on a fader to set that track's volume; the digits below update live while dragging.")),
        ("transport buttons", Text("play/stop control op1 tape playback (play only works when the app is the clock master). left/right arrow buttons step the op1 tape position backward/forward.")),
        ("metronome / tempo mode", Text("tap the metronome icon to switch the clock source. then change the op1 to match.\n\(Text("op1 (beat match)").foregroundColor(C.track(1))) — op1 is master\n· app's lfos follow op1's tempo.\n\(Text("app (midi sync)").foregroundColor(C.green)) — app is master\n· app controls op1 tape transport (play/stop/back/forward).\n\(Text("· note: ").bold())tempo control requires 'app (midi sync)' mode and usb-c; bluetooth does not send high-resolution tempo changes.")),
        ("tempo / bpm", Text("drag up/down to scrub the tempo. double-tap or long-press the box to type an exact bpm.\n\(Text("· note: ").bold())tempo control requires 'app (midi sync)' mode and usb-c; bluetooth does not send high-resolution tempo changes.")),
        ("track / master buttons", Text("tap to cycle off → on → inverted. tracks apply the lfo to that single track; master applies it to the selected master-capable parameter (e.g. tempo) across all tracks.")),
        ("parameter / wave", Text("choose which parameter the lfo modulates, and which waveform shape it follows.")),
        ("rate / depth / center", Text("drag up/down on a box to scrub its value. rate sets lfo speed, depth sets its range, center sets its midpoint.")),
        ("waveform preview", Text("shows the shape of the lfo that will be sent, colored per active track/master.")),
        ("repeat / 1x / trash", Text("start the lfo looping, start it once, or delete all currently active lfos.")),
        ("active lfos", Text("tap an entry to preview it on the waveform; tap the x to stop just that one.")),
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
