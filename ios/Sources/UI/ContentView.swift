import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var showDevicePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            StatusBarView(showPicker: $showDevicePicker)
                .frame(height: 34)

            Rectangle().fill(C.bg3).frame(height: 1)

            // Transport column + 4 track strips (expands to fill available space)
            HStack(spacing: 0) {
                TransportView()
                    .frame(width: 52)

                Rectangle().fill(C.bg3).frame(width: 1)

                TracksView()
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(C.bg3).frame(height: 1)

            // LFO panel — fixed height, scrollable content
            LFOPanelView()
                .frame(height: 310)
        }
        .background(C.bg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerView()
        }
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @EnvironmentObject var app: AppState
    @Binding var showPicker: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Connection indicator — tap to open picker
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(app.isConnected ? C.green : C.dim)
                        .frame(width: 6, height: 6)
                    Text(app.connectionLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(app.isConnected ? C.text : C.dim)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // BPM pill
            HStack(spacing: 2) {
                Text("BPM")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(C.dim)
                Text(String(format: "%.1f", app.bpm))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(C.text)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(C.bg2)
    }
}

// MARK: - Device picker sheet

struct DevicePickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Discovered Devices") {
                    if app.ble.discovered.isEmpty {
                        Label("Scanning for BLE MIDI devices…", systemImage: "wave.3.right")
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
                    Button("Disconnect") {
                        app.ble.disconnect()
                        dismiss()
                    }
                    .foregroundColor(C.red)
                }
            }
            .navigationTitle("BLE MIDI Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
