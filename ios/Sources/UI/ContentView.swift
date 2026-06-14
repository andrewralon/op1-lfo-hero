import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var showDevicePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            StatusBarView(showPicker: $showDevicePicker)
                .frame(height: 30)

            Rectangle().fill(C.bg3).frame(height: 1)

            // 4 track strips — fixed height so fader doesn't dominate
            TracksView()
                .frame(height: 280)

            Rectangle().fill(C.bg3).frame(height: 1)

            // Horizontal transport row below tracks (matches desktop layout)
            TransportBarView()
                .frame(height: 50)

            Rectangle().fill(C.bg3).frame(height: 1)

            // LFO panel fills the remaining space
            LFOPanelView()
                .frame(maxHeight: .infinity)
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
            Button { showPicker = true } label: {
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
