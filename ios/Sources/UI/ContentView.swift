import CoreBluetooth
import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geo in
            // Match iPhone proportions on every screen size:
            //   tracksH   ≈ 37% of usable height (280pt on iPhone, ~412pt on iPad 11")
            //   transportH ≈ 7.6% of usable height (58pt on iPhone, ~85pt on iPad 11")
            let tracksH    = min(max(280, geo.size.height * 0.37), 500)
            let transportH = min(max(58,  geo.size.height * 0.076), 90)
            VStack(spacing: 0) {
                TracksView()
                    .frame(height: tracksH)
                    .padding(.bottom, 5)

                Rectangle().fill(C.bg3).frame(height: 1)

                TransportBarView()
                    .frame(height: transportH)

                LFOPanelView()
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(C.bg)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Device picker sheet (used by LFOPanelView)

struct DevicePickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("discovered devices") {
                    if app.ble.discovered.isEmpty {
                        Label("scanning for BLE MIDI devices…", systemImage: "wave.3.right")
                            .foregroundColor(C.text)
                    } else {
                        ForEach(app.ble.discovered, id: \.identifier) { p in
                            Button {
                                app.ble.connect(p)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "pianokeys")
                                    Text(p.name ?? p.identifier.uuidString)
                                        .foregroundColor(C.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(C.text)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("disconnect") {
                        app.ble.disconnect()
                        dismiss()
                    }
                    .foregroundColor(C.red)
                }
            }
            .navigationTitle("BLE MIDI device")
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

    private let sections: [(String, Text)] = [
        ("mute buttons", Text("tap a track's colored number to mute/unmute it. bright colored background = unmuted; dark background = muted.")),
        ("pan knobs", Text("drag up/down on a knob to pan right/left. release near the top to snap to center. [vertical scrubbing for a horizontal control like pan is weird. i'm open to better ideas...]")),
        ("volume faders", Text("drag up/down on a fader to set that track's volume; the digits below update live while dragging.")),
        ("transport buttons", Text("play/stop start and stop playback (play only works when the app is the clock master). the left/right arrows step the op1's tape position backward/forward.")),
        ("metronome / tempo mode",
            Text("tap the metronome icon to switch the clock source: ")
            + Text("app (midi sync)").foregroundColor(C.green)
            + Text(" drives tempo from this app over MIDI sync; ")
            + Text("op1 (beat match)").foregroundColor(C.track(1))
            + Text(" follows the op1 tempo instead.")
        ),
        ("bpm", Text("drag up/down to scrub the tempo. double-tap or long-press the box to type an exact BPM.")),
        ("track / master buttons", Text("tap to cycle off → on → inverted. tracks apply the LFO to that single track; master applies it to the selected master-capable parameter (e.g. tempo) across all tracks.")),
        ("parameter / wave", Text("choose which parameter the LFO modulates, and which waveform shape it follows.")),
        ("rate / depth / center", Text("drag up/down on a box to scrub its value. rate sets LFO speed, depth sets its range, center sets its midpoint.")),
        ("waveform preview", Text("shows the shape of the LFO that will be sent, colored per active track/master.")),
        ("repeat / 1x / trash", Text("start the LFO looping, start it once, or delete all currently active LFOs.")),
        ("active LFOs", Text("tap an entry to preview it on the waveform; tap the x to stop just that one.")),
        ("status bar", Text("shows the current MIDI connection and clock source; tap it to choose a BLE device."))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                }
                .padding(.bottom, 20)
            }
            .background(C.bg)
            .navigationTitle("help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings sheet (used by LFOPanelView)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("no settings yet").foregroundColor(C.text)
            }
            .navigationTitle("settings")
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
