import Combine
import Foundation

/// One stop on the first-run tutorial. Declaration order is the tour order, and it is also
/// how a step that no longer applies is replaced: by the next case after it that does.
enum TourAnchor: String, CaseIterable {
    /// The opening card. Points at nothing: it sits mid-screen over a full dim.
    case welcome
    case statusBar, mutePad, panKnob, volumeFader, transport, tempoMode, bpm
    case trackToggle, masterToggle, preview
    case paramPicker, wavePicker, speedBox, centerBox, depthBox, waveform
    case startButtons, chipArea, helpSettings

    /// The steps that apply to a device: no pan step on a device without pan, no tempo-mode
    /// step on one that can never be the clock.
    static func steps(for caps: DeviceCapabilities) -> [TourAnchor] {
        allCases.filter {
            switch $0 {
            case .panKnob:   return caps.hasPan
            case .tempoMode: return caps.canBeClockMaster
            default:         return true
            }
        }
    }
}

/// State of the first-run tutorial: which step is showing, and whether it should show at all.
///
/// Persisted in `UserDefaults`, not the Keychain settings blob. It isn't a secret, and being
/// wiped with the app is right: a reinstall should see the tour again.
@MainActor
final class TourController: ObservableObject {

    enum Status: String { case notStarted, deferred, completed }

    /// Bump to re-show the tour to everyone after a big UI change.
    static let currentVersion = 1

    static let statusKey     = "tour.status"
    static let resumeStepKey = "tour.resumeStep"
    static let versionKey    = "tour.version"

    /// nil = hidden.
    @Published private(set) var currentStep: TourAnchor?
    @Published private(set) var steps: [TourAnchor] = TourAnchor.steps(for: DeviceCapabilities())

    var isActive: Bool { currentStep != nil }
    var stepIndex: Int { currentStep.flatMap { steps.firstIndex(of: $0) } ?? 0 }
    var isFirstStep: Bool { currentStep != nil && currentStep == steps.first }
    var isLastStep: Bool { currentStep != nil && currentStep == steps.last }

    private let defaults: UserDefaults
    private let version: Int
    /// Delay before a replay starts once the last sheet has closed, so it doesn't arrive
    /// mid-dismissal. Tests pass 0, which starts it synchronously.
    private let replayDelay: TimeInterval
    private var openSheets = 0
    private var pendingReplay = false

    init(defaults: UserDefaults = .standard,
         version: Int = TourController.currentVersion,
         replayDelay: TimeInterval = 0.4,
         arguments: [String] = CommandLine.arguments) {
        self.defaults = defaults
        self.version = version
        self.replayDelay = replayDelay
        applyLaunchArguments(arguments)
    }

    /// Must stay nonisolated. Under the project's default MainActor isolation the synthesized
    /// deinit is isolated, which on a 17.6 target goes through the Swift runtime's back-deploy
    /// shim (`swift_task_deinitOnExecutorMainActorBackDeploy`); that aborts in malloc when the
    /// controller is released, and took down the test host on every TourControllerTests case.
    /// Nothing here needs the main actor to tear down.
    nonisolated deinit {}

    /// `--uitest-reset` marks the tour done, so it can't block every existing UI test.
    /// `--uitest-tour` forces it back on; it is checked second so it wins when both are passed.
    private func applyLaunchArguments(_ args: [String]) {
        if args.contains("--uitest-reset") { write(.completed) }
        if args.contains("--uitest-tour")  { write(.notStarted) }
    }

    /// A status saved by an older tour version reads as `notStarted`, so a version bump re-shows it.
    var status: Status {
        guard defaults.integer(forKey: Self.versionKey) >= version,
              let raw = defaults.string(forKey: Self.statusKey),
              let s = Status(rawValue: raw)
        else { return .notStarted }
        return s
    }

    // MARK: - Starting

    /// Called once the splash has gone. A tour that was never finished starts at step 1, whether
    /// it was never started or **later** closed it part-way: it does not resume.
    func startIfNeeded(caps: DeviceCapabilities) {
        steps = TourAnchor.steps(for: caps)
        guard openSheets == 0, currentStep == nil else { return }
        switch status {
        case .completed:
            return
        case .deferred, .notStarted:
            currentStep = steps.first
        }
    }

    /// Settings / help: start again from step 1 once whatever sheet it was pressed in has closed.
    func replay() {
        pendingReplay = true
        if openSheets == 0 { beginReplay() }
    }

    private func beginReplay() {
        let start = { [weak self] in
            guard let self, self.pendingReplay, self.openSheets == 0 else { return }
            self.pendingReplay = false
            self.currentStep = self.steps.first
        }
        if replayDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + replayDelay) { start() }
        } else {
            start()
        }
    }

    // MARK: - Card buttons

    func next() {
        guard let cur = currentStep, let i = steps.firstIndex(of: cur) else { return }
        if i + 1 < steps.count {
            currentStep = steps[i + 1]
        } else {
            finish()
        }
    }

    /// One step back. Does nothing on the first step.
    func back() {
        guard let cur = currentStep, let i = steps.firstIndex(of: cur), i > 0 else { return }
        currentStep = steps[i - 1]
    }

    /// Ends the tour for good.
    func skip() { finish() }

    /// Closes the tour without finishing it; the next launch starts it again from step 1.
    /// Clears the step an older build saved here, which nothing reads any more.
    func later() {
        guard currentStep != nil else { return }
        write(.deferred)
        defaults.removeObject(forKey: Self.resumeStepKey)
        currentStep = nil
    }

    /// The overlay calls this when a step's control isn't in the current layout, rather than
    /// pointing at nothing.
    func skipMissing(_ step: TourAnchor) {
        guard currentStep == step else { return }
        next()
    }

    private func finish() {
        write(.completed)
        defaults.removeObject(forKey: Self.resumeStepKey)
        currentStep = nil
    }

    // MARK: - Outside changes

    /// The step list depends on the device, so keep the current step by id, or move to the
    /// next one that still applies.
    func profileChanged(_ caps: DeviceCapabilities) {
        steps = TourAnchor.steps(for: caps)
        guard let cur = currentStep else { return }
        if let step = validStep(atOrAfter: cur) {
            currentStep = step
        } else {
            finish()
        }
    }

    /// Every view that presents a sheet or full-screen cover reports it here. The tour never
    /// sits over a sheet: one opening mid-tour acts like **later**.
    func sheet(_ presented: Bool) {
        if presented {
            openSheets += 1
            if isActive { later() }
        } else {
            openSheets = max(0, openSheets - 1)
            if openSheets == 0 && pendingReplay { beginReplay() }
        }
    }

    // MARK: - Helpers

    private func validStep(atOrAfter id: TourAnchor) -> TourAnchor? {
        if steps.contains(id) { return id }
        let all = TourAnchor.allCases
        guard let i = all.firstIndex(of: id) else { return nil }
        return all[(i + 1)...].first { steps.contains($0) }
    }

    private func write(_ status: Status) {
        defaults.set(status.rawValue, forKey: Self.statusKey)
        defaults.set(version, forKey: Self.versionKey)
    }
}
