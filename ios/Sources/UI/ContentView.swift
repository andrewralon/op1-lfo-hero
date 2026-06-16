import CoreBluetooth
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            TracksView()
                .frame(height: 280)
                .padding(.bottom, 5)

            Rectangle().fill(C.bg3).frame(height: 1)

            TransportBarView()
                .frame(height: 58)

            LFOPanelView()
                .frame(maxHeight: .infinity)
        }
        .background(C.bg)
        .preferredColorScheme(.dark)
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
                            .foregroundColor(C.dim)
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
                                        .foregroundColor(C.dim)
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

    private let sections: [(String, String)] = [
        ("mute buttons", "tap a track's colored number to mute/unmute it. solid color with black text = unmuted; dim color with colored text = muted."),
        ("pan knobs", "drag up/down on a knob to pan right/left (vertical drag stands in for turning it). release near center to snap back to centered."),
        ("volume faders", "drag up/down on a fader to set that track's volume; the digits below update live while dragging."),
        ("transport buttons", "play/stop start and stop playback (play only works when the app is the clock master). the left/right arrows step the OP-1's tape position backward/forward."),
        ("metronome / tempo mode", "tap the metronome icon to switch the clock source: \"app\" (green) drives tempo from this app over MIDI sync; \"op1\" (blue) follows the OP-1's own tempo instead."),
        ("bpm", "drag up/down to scrub the tempo. double-tap or long-press the box to type an exact BPM."),
        ("track / master buttons", "tap to cycle off → on → inverted. tracks apply the LFO to that single track; master applies it to the selected master-capable parameter (e.g. tempo) across all tracks."),
        ("parameter / wave", "choose which parameter the LFO modulates, and which waveform shape it follows."),
        ("rate / depth / center", "drag up/down on a box to scrub its value. rate sets LFO speed, depth sets its range, center sets its midpoint."),
        ("waveform preview", "shows the shape of the LFO that will be sent, colored per active track/master."),
        ("repeat / 1x / trash", "start the LFO looping, start it once, or delete all currently active LFOs."),
        ("active LFOs", "tap an entry to preview it on the waveform; tap the x to stop just that one."),
        ("status bar", "shows the current MIDI connection and clock source; tap it to choose a BLE device.")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, body in
                    Section(title) {
                        Text(body).foregroundColor(C.text)
                    }
                }
            }
            .navigationTitle("help")
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

// MARK: - Settings sheet (used by LFOPanelView)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("no settings yet").foregroundColor(C.dim)
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
