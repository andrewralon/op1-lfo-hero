import SwiftUI

struct LFOPanelView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedLfoID: UUID? = nil

    private var previewLfos: [LfoClip] {
        if let id = selectedLfoID, let lfo = app.activeLfos.first(where: { $0.id == id }) {
            return [lfo]
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── 1. Track selection buttons — FIRST, right under transport ─────
            HStack(spacing: 6) {
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
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 2. Param + wave pickers ────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "umbrella")
                    .font(.system(size: 11))
                    .foregroundColor(C.dim)
                    .frame(width: 16)

                Picker("Param", selection: $app.lfoParam) {
                    ForEach(Parameter.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(C.bg3)
                .cornerRadius(4)

                Image(systemName: "waveform.path")
                    .font(.system(size: 11))
                    .foregroundColor(C.dim)
                    .frame(width: 16)

                Picker("Wave", selection: $app.lfoWave) {
                    ForEach(LfoWave.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(C.bg3)
                .cornerRadius(4)
            }
            .foregroundColor(C.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // ── 3. Rate / depth / center ───────────────────────────────────────
            HStack(spacing: 6) {
                // Rate
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundColor(C.dim)

                HStack(spacing: 0) {
                    Button { app.lfoRate = max(1, app.lfoRate - 1) } label: {
                        Image(systemName: "minus").frame(width: 22, height: 28)
                    }
                    .buttonStyle(.plain)
                    Text(RATE_LABELS[app.lfoRate - 1])
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(C.text)
                        .frame(width: 26)
                    Button { app.lfoRate = min(8, app.lfoRate + 1) } label: {
                        Image(systemName: "plus").frame(width: 22, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .background(C.bg3)
                .cornerRadius(4)
                .foregroundColor(C.dim)

                // Depth
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 11))
                    .foregroundColor(C.dim)

                LabeledControl(label: "depth") {
                    CompactSlider(value: $app.lfoDepth, range: 0...99, step: 1)
                }
                .frame(maxWidth: .infinity)

                // Center
                Image(systemName: "arrow.up.and.down.circle")
                    .font(.system(size: 11))
                    .foregroundColor(C.dim)

                LabeledControl(label: "center") {
                    CompactSlider(value: $app.lfoCenter, range: 0...99, step: 1)
                }
                .frame(maxWidth: .infinity)

                // Range readout
                Text(app.lfoRange)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(C.dim)
                    .frame(width: 34)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 4. Waveform preview — FULL WIDTH ──────────────────────────────
            MultiWaveformView(
                lfos: previewLfos,
                wave: app.lfoWave,
                rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                depth: app.lfoDepth
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Rectangle().fill(C.bg3).frame(height: 1)

            // ── 5. Active LFO list (compact, only when non-empty) ─────────────
            if !app.activeLfos.isEmpty {
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                Rectangle().fill(C.bg3).frame(height: 1)
            }

            // ── 6. Start buttons ───────────────────────────────────────────────
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
            .padding(.vertical, 8)
        }
        .background(C.bg)
    }
}

// MARK: - Sub-components

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
                Image(systemName: "xmark")
                    .font(.system(size: 7))
                    .foregroundColor(C.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(selected ? C.bg3 : C.bg2)
        .cornerRadius(3)
        .onTapGesture { onSelect() }
    }
}

private struct TrackToggleButton: View {
    let track: Int
    let state: Int
    let disabled: Bool
    let action: () -> Void

    private var color: Color { C.track(track) }
    private var bg: Color {
        switch state {
        case 1: return color
        case 2: return color.opacity(0.35)
        default: return C.bg3
        }
    }
    private var fg: Color {
        switch state {
        case 0: return C.dim
        case 1: return .black
        default: return color
        }
    }
    private var label: String { state == 2 ? "[\(track)]" : "\(track)" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 36, height: 30)
                .background(bg)
                .foregroundColor(fg)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}

private struct MasterToggleButton: View {
    let state: Int
    let disabled: Bool
    let action: () -> Void

    private var bg: Color {
        switch state {
        case 1: return C.green
        case 2: return C.green.opacity(0.35)
        default: return C.bg3
        }
    }
    private var fg: Color {
        switch state {
        case 0: return C.dim
        case 1: return .black
        default: return C.green
        }
    }
    private var label: String { state == 2 ? "[m]" : "m" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 36, height: 30)
                .background(bg)
                .foregroundColor(fg)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}

private struct LabeledControl<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            content()
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(C.dim)
        }
    }
}

private struct CompactSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @GestureState private var drag: CGFloat = 0
    @State private var base: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let display = max(range.lowerBound, min(range.upperBound,
                                                    base + Double(drag / w) * span))
            let fraction = (display - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule().fill(C.bg3).frame(height: 4)
                Capsule().fill(C.green)
                    .frame(width: max(0, CGFloat(fraction) * w), height: 4)
                Circle()
                    .fill(C.text)
                    .frame(width: 14, height: 14)
                    .offset(x: max(0, CGFloat(fraction) * w - 7))
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($drag) { g, state, _ in state = g.translation.width }
                    .onEnded { g in
                        let delta = Double(g.translation.width / w) * span
                        let stepped = (base + delta) / step
                        let newVal = max(range.lowerBound,
                                         min(range.upperBound, stepped.rounded() * step))
                        base = newVal
                        value = newVal
                    }
            )
            .onAppear { base = value }
            .onChange(of: value) { _, newVal in if drag == 0 { base = newVal } }
        }
        .frame(height: 26)
    }
}
