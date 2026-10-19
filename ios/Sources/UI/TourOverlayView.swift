import SwiftUI

// MARK: - Anchors

/// Collects the bounds of every control the walkthrough can point at.
///
/// A list per id rather than one anchor: some steps cover several views that can't be wrapped
/// in one container without changing the layout (the landscape transport column's rows each
/// take an equal share of its height), so each piece is tagged and the overlay takes the union.
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourAnchor: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [TourAnchor: [Anchor<CGRect>]],
                       nextValue: () -> [TourAnchor: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

extension View {
    /// Marks this view as (part of) a walkthrough step. `when: false` tags nothing, which keeps
    /// the view's identity the same for the one instance per type that is tagged (track 1 only).
    func tourAnchor(_ id: TourAnchor, when tagged: Bool = true) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { tagged ? [id: [$0]] : [:] }
    }
}

// MARK: - Overlay

/// Resolves the current step's anchors and draws the overlay over them. Applied by ContentView
/// with `overlayPreferenceValue`, so it shares the main screen's coordinate space.
struct TourOverlayLayer: View {
    let anchors: [TourAnchor: [Anchor<CGRect>]]
    @EnvironmentObject private var tour: TourController

    var body: some View {
        if let step = tour.currentStep {
            GeometryReader { proxy in
                let rects = (anchors[step] ?? []).map { proxy[$0] }
                if step == .welcome {
                    // Points at nothing by design: centered over a full dim.
                    TourOverlayView(step: step, target: nil, proxy: proxy)
                } else if let first = rects.first {
                    TourOverlayView(step: step,
                                    target: rects.dropFirst().reduce(first) { $0.union($1) },
                                    proxy: proxy)
                } else {
                    // Not in this layout. Give it a moment (a rotation can briefly drop an
                    // anchor), then move on; the task is cancelled if the anchor turns up.
                    TouchBlocker()
                        .task(id: step) {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            if !Task.isCancelled { tour.skipMissing(step) }
                        }
                }
            }
        }
    }
}

/// Catches every touch, so nothing under the tour — mute, play, a fader — can send MIDI.
private struct TouchBlocker: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {}
            .gesture(DragGesture(minimumDistance: 0))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Full-screen dim with a real hole cut around the target (even-odd fill), so the control
/// shows through at full brightness. Animatable so the hole glides between steps.
private struct SpotlightShape: Shape {
    var hole: CGRect
    let outer: CGRect
    let radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(hole.origin.x, hole.origin.y), .init(hole.size.width, hole.size.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in _: CGRect) -> Path {
        var p = Path()
        p.addRect(outer)
        p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
        return p
    }
}

private struct TourOverlayView: View {
    let step: TourAnchor
    /// nil = no control to point at (the welcome card): no hole, card centered.
    let target: CGRect?
    let proxy: GeometryProxy

    @EnvironmentObject private var tour: TourController
    @EnvironmentObject private var app: AppState
    @Environment(\.metrics) private var m
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size  = proxy.size
        let inset = proxy.safeAreaInsets
        // With no target the hole collapses to a point mid-screen, so moving to and from the
        // welcome card animates the same way as moving between controls.
        let hole  = target?.insetBy(dx: -m.tourSpotlightInset, dy: -m.tourSpotlightInset)
            ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        // Drawn in this view's coordinates but reaching past them into the safe area, so the
        // notch and home-indicator strips are dimmed too.
        let outer = CGRect(x: -inset.leading, y: -inset.top,
                           width: size.width + inset.leading + inset.trailing,
                           height: size.height + inset.top + inset.bottom)
        let below = size.height - hole.maxY >= hole.minY

        ZStack(alignment: .topLeading) {
            TouchBlocker()

            SpotlightShape(hole: hole, outer: outer, radius: m.tourSpotlightRadius)
                .fill(C.bg.opacity(0.75), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if target != nil {
                RoundedRectangle(cornerRadius: m.tourSpotlightRadius)
                    .stroke(C.green, lineWidth: 1)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Card sits flush against the hole on whichever side has more room, so it needs
            // no arrow. Horizontally it follows the target, clamped inside the screen.
            VStack(spacing: 0) {
                if target == nil {
                    Spacer(minLength: 0)
                    card(width: size.width)
                    Spacer(minLength: 0)
                } else if below {
                    Color.clear.frame(height: hole.maxY + m.tourCardGap)
                    card(width: size.width)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    card(width: size.width)
                    Color.clear.frame(height: size.height - hole.minY + m.tourCardGap)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        .onAppear(perform: announce)
        .onChange(of: step) { _, _ in announce() }
    }

    private func card(width screenW: CGFloat) -> some View {
        let w = min(m.tourCardW, screenW - 2 * m.tourCardGap)
        let half = w / 2
        let x = min(max(target?.midX ?? screenW / 2, half + m.tourCardGap),
                    screenW - half - m.tourCardGap)
        let nextLabel = step == .welcome ? "start" : (tour.isLastStep ? "done" : "next")

        return VStack(alignment: .leading, spacing: m.tourCardPad * 0.6) {
            // counter | title (centered) | skip. The two sides share one fixed width so the
            // title is centered on the card, not on the space between them.
            HStack(alignment: .center, spacing: 0) {
                Text("\(tour.stepIndex + 1) / \(tour.steps.count)")
                    .font(.system(size: m.tourCounterFont, weight: .medium, design: .monospaced))
                    .foregroundColor(C.dim)
                    .accessibilityIdentifier("tourCounter")
                    .frame(width: m.tourCardSideW, alignment: .leading)
                Text(HelpCopy.tourTitle(step))
                    .font(.system(size: m.tourTitleFont, weight: .semibold, design: .monospaced))
                    .foregroundColor(C.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("tourTitle")
                    .frame(maxWidth: .infinity)
                cardButton("skip", id: "tourSkipButton", color: C.dim) { tour.skip() }
                    .frame(width: m.tourCardSideW, alignment: .trailing)
            }
            Text(HelpCopy.tourText(step, device: app.tourDevice))
                .font(.system(size: m.tourBodyFont))
                .foregroundColor(C.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                cardButton("later", id: "tourLaterButton", color: C.dim) { tour.later() }
                Spacer(minLength: 0)
                cardButton("back", id: "tourBackButton",
                           color: tour.isFirstStep ? C.dim.opacity(0.4) : C.text) { tour.back() }
                    .disabled(tour.isFirstStep)
                Spacer(minLength: 0)
                cardButton(nextLabel, id: "tourNextButton", color: C.green) { tour.next() }
            }
        }
        .padding(m.tourCardPad)
        .frame(width: w, alignment: .leading)
        .background(C.bg2)
        .clipShape(RoundedRectangle(cornerRadius: m.tourSpotlightRadius))
        .overlay(RoundedRectangle(cornerRadius: m.tourSpotlightRadius).stroke(C.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tourCard")
        .offset(x: x - half)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardButton(_ label: String, id: String, color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: m.tourBtnFont, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// VoiceOver reads the new card rather than staying on the old one.
    private func announce() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}
