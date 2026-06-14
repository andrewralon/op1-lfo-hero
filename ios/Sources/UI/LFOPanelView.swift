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
        ScrollView {
            VStack(spacing: 0) {
                // Top: waveform preview + active LFO list
                HStack(alignment: .top, spacing: 8) {
                    MultiWaveformView(
                        lfos: previewLfos,
                        wave: app.lfoWave,
                        rateTicks: RATE_TICKS[app.lfoRate] ?? (4 * PPQN),
                        depth: app.lfoDepth
                    )
                    .frame(width: 80, height: 60)

                    // Active LFO list
                    VStack(alignment: .leading, spacing: 2) {
                        if app.activeLfos.isEmpty {
                            Text("no active LFOs")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(C.dim)
                        } else {
                            ForEach(app.activeLfos) { lfo in
                                ActiveLfoRow(lfo: lfo, selected: selectedLfoID == lfo.id) {
                                    selectedLfoID = selectedLfoID == lfo.id ? nil : lfo.id
                                } onStop: {
                                    if selectedLfoID == lfo.id { selectedLfoID = nil }
                                    app.stopLfo(lfo)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                SectionDivider(label: "wave & param")
                    .padding(.top, 6)

                // Wave + param pickers
                HStack(spacing: 8) {
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
                }
                .foregroundColor(C.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                SectionDivider(label: "rate / depth / center")

                // Rate + Depth + Center + Range
                HStack(spacing: 6) {
                    // Rate stepper
                    LabeledControl(label: "rate") {
                        HStack(spacing: 0) {
                            Button { app.lfoRate = max(1, app.lfoRate - 1) } label: {
                                Image(systemName: "minus").frame(width: 22, height: 26)
                            }
                            .buttonStyle(.plain)
                            Text(RATE_LABELS[app.lfoRate - 1])
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(C.text)
                                .frame(width: 28)
                            Button { app.lfoRate = min(8, app.lfoRate + 1) } label: {
                                Image(systemName: "plus").frame(width: 22, height: 26)
                            }
                            .buttonStyle(.plain)
                        }
                        .background(C.bg3)
                        .cornerRadius(4)
                    }

                    // Depth slider
                    LabeledControl(label: "depth") {
                        CompactSlider(value: $app.lfoDepth, range: 0...99, step: 1)
                    }

                    // Center slider
                    LabeledControl(label: "center") {
                        CompactSlider(value: $app.lfoCenter, range: 0...99, step: 1)
                    }

                    // Range readout
                    LabeledControl(label: "range") {
                        Text(app.lfoRange)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(C.dim)
                            .frame(height: 26)
                    }
                }
                .foregroundColor(C.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                SectionDivider(label: "target tracks")

                // Track buttons (1-4) + Master
                HStack(spacing: 5) {
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
                .padding(.vertical, 6)

                SectionDivider(label: "start")

                // Start buttons
                HStack(spacing: 8) {
                    Button { app.lfoStart(loop: true) } label: {
                        Label("∞ Loop", systemImage: "repeat")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(C.green.opacity(0.18))
                            .foregroundColor(C.green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button { app.lfoStart(loop: false) } label: {
                        Label("1× Shot", systemImage: "play.circle")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(C.bg3)
                            .foregroundColor(C.text)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button { app.stopAllLfos(); selectedLfoID = nil } label: {
                        Label("Stop All", systemImage: "xmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(C.red.opacity(0.18))
                            .foregroundColor(C.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(C.bg)
    }
}

// MARK: - Sub-components

private struct ActiveLfoRow: View {
    let lfo: LfoClip
    let selected: Bool
    let onSelect: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(lfo.track == 0 ? C.green : C.track(lfo.track))
                .frame(width: 5, height: 5)
            Text(lfo.shortLabel)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(selected ? C.text : C.dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { onStop() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7))
                    .foregroundColor(C.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(selected ? C.bg3 : Color.clear)
        .cornerRadius(3)
        .onTapGesture { onSelect() }
    }
}

private struct TrackToggleButton: View {
    let track: Int
    let state: Int       // 0=off 1=on 2=inv
    let disabled: Bool
    let action: () -> Void

    private var color: Color { C.track(track) }
    private var bg: Color {
        switch state {
        case 1: return color.opacity(0.22)
        case 2: return color.opacity(0.12)
        default: return C.bg3
        }
    }
    private var fg: Color {
        switch state {
        case 0: return C.dim
        default: return color
        }
    }
    private var label: String {
        switch state {
        case 2: return "[\(track)]"
        default: return "\(track)"
        }
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 30, height: 26)
                .background(bg)
                .foregroundColor(fg)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(state != 0 ? color : Color.clear, lineWidth: 1)
                )
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
        case 1: return C.green.opacity(0.22)
        case 2: return C.green.opacity(0.12)
        default: return C.bg3
        }
    }
    private var fg: Color { state == 0 ? C.dim : C.green }
    private var label: String { state == 2 ? "[M]" : "M" }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 30, height: 26)
                .background(bg)
                .foregroundColor(fg)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(state != 0 ? C.green : Color.clear, lineWidth: 1)
                )
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
                        let newVal = max(range.lowerBound, min(range.upperBound,
                                                               stepped.rounded() * step))
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
