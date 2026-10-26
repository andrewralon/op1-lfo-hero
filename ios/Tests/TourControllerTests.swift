import XCTest
@testable import op1_lfo_hero

/// The first-run tutorial's state: which steps a device gets, and what skip / later / next
/// leave behind for the next launch.
@MainActor
final class TourControllerTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "TourControllerTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A fresh controller over the same store, as the next launch would see it.
    private func launch(version: Int = TourController.currentVersion,
                        arguments: [String] = []) -> TourController {
        TourController(defaults: defaults, version: version, replayDelay: 0, arguments: arguments)
    }

    private let op1 = DeviceProfile.op1Field.caps
    private let tp7 = DeviceProfile.tp7.caps

    // MARK: - Steps per device

    func testOP1HasPanAndTempoModeSteps() {
        let steps = TourAnchor.steps(for: op1)
        XCTAssertTrue(steps.contains(.panKnob))
        XCTAssertTrue(steps.contains(.tempoMode))
        XCTAssertEqual(steps.count, TourAnchor.allCases.count)
        XCTAssertEqual(steps.first, .welcome)
        // Screen order: the tempo source (metronome) sits left of the bpm box.
        XCTAssertLessThan(steps.firstIndex(of: .tempoMode)!, steps.firstIndex(of: .bpm)!)
    }

    func testTP7HasNoPanStep() {
        let steps = TourAnchor.steps(for: tp7)
        XCTAssertFalse(steps.contains(.panKnob))
        XCTAssertEqual(steps.count, TourAnchor.allCases.count - 1)
    }

    func testDeviceThatCannotBeClockMasterHasNoTempoModeStep() {
        let caps = DeviceCapabilities(hasPan: false, canBeClockMaster: false)
        let steps = TourAnchor.steps(for: caps)
        XCTAssertFalse(steps.contains(.tempoMode))
        XCTAssertFalse(steps.contains(.panKnob))
    }

    // MARK: - Buttons

    func testFreshInstallStartsAtStepOne() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        XCTAssertEqual(tour.currentStep, .welcome)
        XCTAssertEqual(tour.stepIndex, 0)
        XCTAssertTrue(tour.isFirstStep)
    }

    func testSkipEndsForGood() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.next()
        tour.skip()
        XCTAssertNil(tour.currentStep)
        XCTAssertEqual(tour.status, .completed)

        let again = launch()
        again.startIfNeeded(caps: op1)
        XCTAssertNil(again.currentStep)
    }

    func testLaterRestartsAtTheFirstStepNextLaunch() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.next(); tour.next()
        XCTAssertNotEqual(tour.currentStep, .welcome)
        tour.later()
        XCTAssertNil(tour.currentStep)
        XCTAssertEqual(tour.status, .deferred)

        let again = launch()
        again.startIfNeeded(caps: op1)
        XCTAssertEqual(again.currentStep, .welcome)
    }

    /// An older build saved the step **later** was pressed on. Nothing reads it now, and
    /// `later()` clears it.
    func testAStaleResumeStepFromAnOlderBuildIsIgnored() {
        defaults.set(TourController.currentVersion, forKey: TourController.versionKey)
        defaults.set(TourController.Status.deferred.rawValue, forKey: TourController.statusKey)
        defaults.set(TourAnchor.panKnob.rawValue, forKey: TourController.resumeStepKey)

        let tour = launch()
        tour.startIfNeeded(caps: op1)
        XCTAssertEqual(tour.currentStep, .welcome)

        tour.next()
        tour.later()
        XCTAssertNil(defaults.string(forKey: TourController.resumeStepKey))
    }

    func testBackGoesToThePreviousStepAndStopsAtTheFirst() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.back()
        XCTAssertEqual(tour.currentStep, .welcome)
        tour.next(); tour.next()
        XCTAssertEqual(tour.currentStep, .mutePad)
        tour.back()
        XCTAssertEqual(tour.currentStep, .statusBar)
    }

    /// The step list differs per device, so back skips a step that doesn't apply.
    func testBackSkipsAStepTheDeviceDoesNotHave() {
        let tour = launch()
        tour.startIfNeeded(caps: tp7)
        while tour.currentStep != .volumeFader { tour.next() }
        tour.back()
        XCTAssertEqual(tour.currentStep, .mutePad)
    }

    func testNextOnLastStepCompletes() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        for _ in 0 ..< tour.steps.count - 1 { tour.next() }
        XCTAssertTrue(tour.isLastStep)
        XCTAssertEqual(tour.currentStep, .helpSettings)
        tour.next()
        XCTAssertNil(tour.currentStep)
        XCTAssertEqual(tour.status, .completed)
    }

    // MARK: - Outside changes

    func testProfileChangeKeepsTheCurrentStep() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        while tour.currentStep != .bpm { tour.next() }
        tour.profileChanged(tp7)
        XCTAssertEqual(tour.currentStep, .bpm)
        XCTAssertEqual(tour.steps.count, TourAnchor.allCases.count - 1)
    }

    func testProfileChangeMovesOffAStepThatNoLongerApplies() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        while tour.currentStep != .panKnob { tour.next() }
        tour.profileChanged(tp7)
        XCTAssertEqual(tour.currentStep, .volumeFader)
    }

    func testVersionBumpReshowsTheTour() {
        let tour = launch(version: 1)
        tour.startIfNeeded(caps: op1)
        tour.skip()

        let same = launch(version: 1)
        same.startIfNeeded(caps: op1)
        XCTAssertNil(same.currentStep)

        let bumped = launch(version: 2)
        bumped.startIfNeeded(caps: op1)
        XCTAssertEqual(bumped.currentStep, .welcome)
    }

    func testAnOpenSheetBlocksTheStart() {
        let tour = launch()
        tour.sheet(true)
        tour.startIfNeeded(caps: op1)
        XCTAssertNil(tour.currentStep)
        XCTAssertEqual(tour.status, .notStarted)
    }

    func testASheetOpeningMidTourActsLikeLater() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.next()
        tour.sheet(true)
        XCTAssertNil(tour.currentStep)
        XCTAssertEqual(tour.status, .deferred)
    }

    func testReplayWaitsForTheSheetToClose() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.skip()

        tour.sheet(true)        // settings opens
        tour.replay()           // replay pressed inside it
        XCTAssertNil(tour.currentStep)
        tour.sheet(false)       // settings closes
        XCTAssertEqual(tour.currentStep, .welcome)
    }

    func testMissingAnchorSkipsOnlyTheCurrentStep() {
        let tour = launch()
        tour.startIfNeeded(caps: op1)
        tour.next()                     // past the welcome card
        tour.skipMissing(.waveform)     // stale: not the current step
        XCTAssertEqual(tour.currentStep, .statusBar)
        tour.skipMissing(.statusBar)
        XCTAssertEqual(tour.currentStep, .mutePad)
    }

    // MARK: - Launch arguments

    func testUITestResetMarksTheTourDone() {
        let tour = launch(arguments: ["--uitest-reset"])
        tour.startIfNeeded(caps: op1)
        XCTAssertNil(tour.currentStep)
    }

    func testUITestTourForcesItOnEvenWithReset() {
        launch().skip()
        let tour = launch(arguments: ["--uitest-reset", "--uitest-tour"])
        tour.startIfNeeded(caps: op1)
        XCTAssertEqual(tour.currentStep, .welcome)
    }
}
