import SwiftUI

private let ctrlFontSize: CGFloat = 15  // dropdowns + scrub boxes always match

struct LFOPanelView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedLfoID: UUID? = nil
    @State private var showDevicePicker = false

    private var previewLfos: [LfoClip] {
        if let id = selectedLfoID, let lfo = app.activeLfos.first(where: { $0.id == id }) {
            return [lfo]
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Track + master buttons — centered row ──────────────────────
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { t in
                    TrackToggleButton(track: t,
                                      state: app.trackOn[t] ?? 0,
                                      disabled: app.lfoParam.isMasterOnly) {
                        app.cycleTrack(t)
                    }
                }
                MasterToggleButton(state: app.masterOn,
                                   disabled: !app.lfoParam.isMasterCapable) {
                    app.cycleMaster()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 2. Param + wave dropdowns — fitted width, centered ────────────
            HStack(spacing: 6) {
                Spacer()
                Image(systemName: "umbrella").font(.system(size: 16)).foregroundColor(C.dim)
                Menu {
                    // Reversed so most-used params appear at top of the menu
                    ForEach(Parameter.allCases.reversed()) { p in
                        Button(p.rawValue) { app.lfoParam = p }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.lfoParam.rawValue)
                            .font(.system(size: ctrlFontSize, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(C.bg3)
                    .cornerRadius(5)
                }
                .foregroundColor(.accentColor)

                Spacer()

                Image(systemName: "waveform.path").font(.system(size: 16)).foregroundColor(C.dim)
                Menu {
                    ForEach(LfoWave.allCases.reversed()) { w in
                        Button(w.rawValue) { app.lfoWave = w }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.lfoWave.rawValue)
                            .font(.system(size: ctrlFontSize, weight: .medium))
                            .frame(minWidth: 72, alignment: .leading)  // wide enough for "triangle"
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(C.bg3)
                    .cornerRadius(5)
                }
                .foregroundColor(.accentColor)

                Spacer()
            }
            .padding(.vertical, 6)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 3. Rate / depth / center — centered as a group ────────────────
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                // Rate stepper
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    HStack(spacing: 0) {
                        Button { app.lfoRate = max(1, app.lfoRate - 1) } label: {
                            Image(systemName: "minus").frame(width: 28, height: 36)
                        }
                        .buttonStyle(.plain).foregroundColor(Color(hex: "#aaaaaa"))

                        Text(RATE_LABELS[app.lfoRate - 1])
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 32)

                        Button { app.lfoRate = min(8, app.lfoRate + 1) } label: {
                            Image(systemName: "plus").frame(width: 28, height: 36)
                        }
                        .buttonStyle(.plain).foregroundColor(Color(hex: "#aaaaaa"))
                    }
                    .background(C.bg3).cornerRadius(4)
                }

                Spacer(minLength: 20)

                // Depth
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    ScrubValue(value: $app.lfoDepth, range: 0...99)
                        .frame(width: 58)
                }

                Spacer(minLength: 20)

                // Center
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.circle")
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    ScrubValue(value: $app.lfoCenter, range: 0...99)
                        .frame(width: 58)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 4. Waveform preview — full width ──────────────────────────────
            MultiWaveformView(
                lfos: previewLfos,
                wave: app.lfoWave,
                rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                depth: app.lfoDepth
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)

            // Active LFO chips (only when running)
            if !app.activeLfos.isEmpty {
                Rectangle().fill(C.bg3).frame(height: 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(app.activeLfos) { lfo in
                            ActiveLfoChip(lfo: lfo, selected: selectedLfoID == lfo.id) {
                                selectedLfoID = selectedLfoID == lfo.id ? nil : lfo.id
                            } onStop: {
                                if selectedLfoID == lfo.id { selectedLfoID = nil }
                                app.stopLfo(lfo)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }
            }

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 5. Start buttons ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Button { app.lfoStart(loop: true) } label: {
                    Label("∞ Loop", systemImage: "repeat")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(C.green.opacity(0.25))
                        .foregroundColor(C.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button { app.lfoStart(loop: false) } label: {
                    Label("1× Shot", systemImage: "play.circle")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(C.bg3)
                        .foregroundColor(C.text)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button { app.stopAllLfos(); selectedLfoID = nil } label: {
                    Label("Stop All", systemImage: "xmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(C.red.opacity(0.18))
                        .foregroundColor(C.red)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 6. Status bar — at the bottom (matches Python layout) ─────────
            Button { showDevicePicker = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.isConnected ? C.green : C.orange)
                        .frame(width: 7, height: 7)
                    Text(app.connectionLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(app.isConnected ? C.text : C.orange)
                        .lineLimit(1)
                    Spacer()
                    Text("tempo: \(app.isClockMaster ? "app (midi sync)" : "op-1")")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(C.dim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .background(C.bg2)
        }
        .background(C.bg)
        .sheet(isPresented: $showDevicePicker) { DevicePickerView() }
    }
}

// MARK: - Scrubable number control
// Drag left to decrease, right to increase — 1pt of drag = 0.5 units

private struct ScrubValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    @GestureState private var drag: CGFloat = 0
    @State private var base: Double = 0

    private var live: Double {
        max(range.lowerBound, min(range.upperBound, base + Double(drag) * 0.5))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(drag != 0 ? C.green.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .frame(height: 36)
            Text(String(Int(live)))
                .font(.system(size: ctrlFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(drag != 0 ? C.green : .white)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($drag) { g, state, _ in state = g.translation.width }
                .onEnded { g in
                    let newVal = max(range.lowerBound,
                                    min(range.upperBound,
                                        (base + Double(g.translation.width) * 0.5).rounded()))
                    base = newVal
                    value = newVal
                }
        )
        .onAppear { base = value }
        .onChange(of: value) { _, v in if drag == 0 { base = v } }
    }
}

// MARK: - Active LFO chip

private struct ActiveLfoChip: View {
    let lfo: LfoClip
    let selected: Bool
    let onSelect: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(lfo.track == 0 ? C.green : C.track(lfo.track))
                .frame(width: 5, height: 5)
            Text(lfo.shortLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(selected ? C.text : C.dim)
            Button { onStop() } label: {
                Image(systemName: "xmark").font(.system(size: 7)).foregroundColor(C.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(selected ? C.bg3 : C.bg2)
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
    let disabled: Bool
    let action: () -> Void

    private var color: Color { C.track(track) }

    var body: some View {
        Button(action: action) {
            Text("\(track)")
                .font(.system(size: C.trackLabelSize, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: 42, height: 42)
                .background(state == 0 ? C.bg3 : color)
                .foregroundColor(state == 0 ? color : .black)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.6 : 1)
        .disabled(disabled)
    }
}

// MARK: - Master toggle button
// Same state logic, green instead of track color

private struct MasterToggleButton: View {
    let state: Int
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("m")
                .font(.system(size: C.trackLabelSize, weight: .bold, design: .monospaced))
                .rotationEffect(state == 2 ? .degrees(180) : .degrees(0))
                .frame(width: 42, height: 42)
                .background(state == 0 ? C.bg3 : C.green)
                .foregroundColor(state == 0 ? C.green : .black)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.6 : 1)
        .disabled(disabled)
    }
}
