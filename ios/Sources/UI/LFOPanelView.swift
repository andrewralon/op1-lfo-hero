import SwiftUI

private let ctrlFontSize: CGFloat = 15  // dropdowns + scrub boxes always match

struct LFOPanelView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedLfoID: UUID? = nil
    @State private var showDevicePicker = false
    @State private var showDeleteConfirm = false

    private var previewLfos: [LfoClip] {
        if let id = selectedLfoID, let lfo = app.activeLfos.first(where: { $0.id == id }) {
            return [lfo]
        }
        return []
    }

    // Snaps lfoCenter to the OP-1's current value for the selected parameter/track.
    private func snapCenter() {
        if app.lfoParam == .tempo {
            app.lfoCenter = app.bpm
            return
        }
        guard let track = (1...4).first(where: { (app.trackOn[$0] ?? 0) > 0 }) else { return }
        switch app.lfoParam {
        case .volume:
            app.lfoCenter = app.volumes[track] ?? 90
        case .pan:
            app.lfoCenter = midiToUI(Double((app.pans[track] ?? 0) + 64))
        case .mute:
            app.lfoCenter = (app.mutes[track] ?? false) ? 99 : 0
        default:
            break  // fx/lfo params not tracked in AppState
        }
    }

    // (color, isInverted) per enabled track/master — each draws its own waveform
    private var waveTracks: [(Color, Bool)] {
        let trackDisabled = app.lfoParam.isMasterOnly
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

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Track + master buttons — centered row ──────────────────────
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { t in
                    TrackToggleButton(track: t,
                                      state: app.trackOn[t] ?? 0,
                                      disabled: app.lfoParam.isMasterOnly || app.masterOn > 0) {
                        app.cycleTrack(t)
                    }
                }
                MasterToggleButton(state: app.masterOn,
                                   disabled: !app.lfoParam.isMasterCapable) {
                    app.cycleMaster()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 2. Param + wave dropdowns — fitted width, centered ────────────
            HStack(spacing: 30) {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 20)).foregroundColor(Color(hex: "#aaaaaa"))
                    CompactPicker(options: Array(Parameter.allCases),
                                  selection: $app.lfoParam)
                }
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path").font(.system(size: 20)).foregroundColor(Color(hex: "#aaaaaa"))
                    CompactPicker(options: Array(LfoWave.allCases),
                                  selection: $app.lfoWave)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 3. Rate / depth / center — centered as a group ────────────────
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                // Rate scrubber (1–8, horizontal drag matches depth/center)
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    ScrubValue(value: Binding(
                        get: { Double(app.lfoRate) },
                        set: { app.lfoRate = max(1, min(8, Int($0.rounded()))) }
                    ), range: 1...8, sensitivity: 0.04)
                    .frame(width: 40)
                }

                Spacer(minLength: 20)

                // Depth
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    ScrubValue(value: $app.lfoDepth, range: 0...99)
                        .frame(width: 58)
                }

                Spacer(minLength: 20)

                // Center
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#aaaaaa"))

                    ScrubValue(value: $app.lfoCenter,
                               range: app.lfoParam == .tempo ? 20...300 : 0...99,
                               decimals: app.lfoParam == .tempo ? 1 : 0)
                        .frame(width: 74)

                    Button { snapCenter() } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#aaaaaa"))
                            .frame(width: 28, height: 36)
                            .background(C.bg3)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 4. Waveform preview — full width ──────────────────────────────
            MultiWaveformView(
                lfos: previewLfos,
                wave: app.lfoWave,
                rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                depth: app.lfoDepth,
                tracks: waveTracks
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 5. Start buttons (left column) + Active LFOs (right column) ───
            HStack(spacing: 0) {
                // Left: three action buttons stacked vertically
                VStack(spacing: 0) {
                    Button { app.lfoStart(loop: true) } label: {
                        Image(systemName: "repeat").font(.system(size: 16))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(C.green.opacity(0.25))
                            .foregroundColor(C.green)
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(C.bg3).frame(height: 1)

                    Button { app.lfoStart(loop: false) } label: {
                        Image(systemName: "arrow.forward.to.line").font(.system(size: 16))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(C.bg3)
                            .foregroundColor(C.text)
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(C.bg3).frame(height: 1)

                    Button {
                        if app.activeLfos.isEmpty { return }
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash").font(.system(size: 16))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(C.red.opacity(0.18))
                            .foregroundColor(C.red)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("delete all active LFOs?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                        Button("delete all", role: .destructive) {
                            app.stopAllLfos(); selectedLfoID = nil
                        }
                    }
                }
                .frame(width: 76)

                Rectangle().fill(C.bg3).frame(width: 1)

                // Right: active LFO chips — scrollable, fills remaining width
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.activeLfos) { lfo in
                            ActiveLfoChip(lfo: lfo, selected: selectedLfoID == lfo.id) {
                                selectedLfoID = selectedLfoID == lfo.id ? nil : lfo.id
                            } onStop: {
                                if selectedLfoID == lfo.id { selectedLfoID = nil }
                                app.stopLfo(lfo)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.leading, 5)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 6. Status bar — at the bottom (matches Python layout) ─────────
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
        }
        .background(C.bg)
        .sheet(isPresented: $showDevicePicker) { DevicePickerView() }
    }
}

// MARK: - Compact picker (replaces Menu to get tight item spacing)
// Button sizes itself to the widest option via invisible ZStack overlay.
// Sheet height is computed from item count so it fits without scrolling.

private struct CompactPicker<T>: View
    where T: Identifiable & RawRepresentable & Hashable,
          T.RawValue == String
{
    let options: [T]
    @Binding var selection: T
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 4) {
                // ZStack sizes to widest option; only current selection is visible
                ZStack(alignment: .leading) {
                    ForEach(options) { opt in
                        Text(opt.rawValue).opacity(0)
                    }
                    Text(selection.rawValue)
                        .foregroundColor(.white)
                }
                .font(.system(size: ctrlFontSize, weight: .bold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(C.bg3)
            .cornerRadius(5)
        }
        .foregroundColor(.accentColor)
        .sheet(isPresented: $show) {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        selection = opt
                        show = false
                    } label: {
                        // Text fills full width (tap anywhere on the row) and is centered.
                        // Checkmark overlaid on trailing edge so it doesn't shift text off-center.
                        Text(opt.rawValue)
                            .font(.system(size: ctrlFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(selection == opt ? .accentColor : C.text)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
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
                    if idx < options.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 6)
            .presentationDetents([.height(CGFloat(options.count) * 40 + 40)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Scrubable number control
// Drag up to increase, down to decrease — matches BpmScrubber direction.
// sensitivity = units per point of drag.

private struct ScrubValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var sensitivity: Double = 0.15
    var decimals: Int = 0

    @GestureState private var isActive: Bool = false
    @State private var base: Double = 0
    @State private var accumulated: Double = 0  // integrated vertical delta
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
        decimals > 0 ? String(format: "%.\(decimals)f", live) : String(Int(live.rounded()))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(C.bg3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isActive ? C.green.opacity(0.6) : Color.clear, lineWidth: 1)
                )
                .frame(height: 36)
            Text(displayText)
                .font(.system(size: ctrlFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? C.green : .white)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($isActive) { _, state, _ in state = true }
                .onChanged { g in
                    // Skip the first event — use it to anchor prevHeight so there's no initial jump.
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
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(lfo.track == 0 ? C.green : C.track(lfo.track))
                .frame(width: 6, height: 6)
            Text(lfo.shortLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            Button { onStop() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundColor(C.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(C.bg3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(selected ? C.green.opacity(0.7) : Color.clear, lineWidth: 1)
        )
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
                .frame(width: 46, height: 46)
                .background((state == 0 ? C.bg3 : color).opacity(disabled ? 0.4 : 1.0))
                .foregroundColor(state == 0 ? color : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
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
                .frame(width: 46, height: 46)
                .background((state == 0 ? C.bg3 : C.green).opacity(disabled ? 0.4 : 1.0))
                .foregroundColor(state == 0 ? C.green : .black)
                .cornerRadius(7)
        }
        .buttonStyle(ImmediateButtonStyle())
        .disabled(disabled)
    }
}
