// The guided tour's step state machine (Sources/JVoice/Tours/Kit/TourEngine.swift), ported from
// BetterScreenshot's TourKit tests and adapted to JVoice's events. This suite is the authority (CI);
// `scripts/run-logic-tests.sh` (the "Tours" section) mirrors it as the local smoke check — change both.
#if canImport(Testing)
import Testing
@testable import JVoice

/// explain a · try b (a choice) · explain c · try d (recording started) · explain e
private let engineTour = Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: [
    TourStep(anchor: "settings.a", kind: .explain, title: "A", body: "A."),
    TourStep(anchor: "settings.b", kind: .tryIt(advanceOn: .choiceMade("settings.model")), title: "B", body: "Pick b."),
    TourStep(anchor: "settings.c", kind: .explain, title: "C", body: "C."),
    TourStep(anchor: "settings.d", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)), title: "D", body: "Record d."),
    TourStep(anchor: "settings.e", kind: .explain, title: "E", body: "E."),
], handsOverTo: .welcome)

/// Try "record" · explain · explain "stop it" (requires the recording) · explain.
private let requiresTour = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill), steps: [
    TourStep(anchor: "pill.a", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)), title: "Record", body: "Press."),
    TourStep(anchor: "pill.b", kind: .explain, title: "Box", body: "Look."),
    TourStep(anchor: "pill.c", kind: .explain, title: "Stop", body: "Stop.", requires: .action(TourEventName.recordingStarted)),
    TourStep(anchor: "pill.d", kind: .explain, title: "Styles", body: "Styles."),
])

private let all: (String) -> Bool = { _ in true }
private let none: (String) -> Bool = { _ in false }
private func except(_ missing: String...) -> (String) -> Bool { { !missing.contains($0) } }
private func progress(_ e: TourEngine, _ isPresent: (String) -> Bool) -> String? {
    e.progress(isPresent: isPresent).map { "\($0.number)/\($0.total)" }
}

@Suite struct TourEngineTests {
    @Test func startsAtFirstStep() {
        var e = TourEngine(tour: engineTour)
        #expect(e.start(isPresent: all) == .show(step: 0))
        #expect(e.status == .running)
        #expect(e.next(isPresent: all) == .show(step: 1))
    }

    @Test func nextIsIgnoredOnTryStep() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 1, isPresent: all)
        #expect(e.next(isPresent: all) == .none)
        #expect(e.current == 1)
    }

    @Test func tryStepAdvancesOnlyOnItsExactEvent() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 1, isPresent: all)
        #expect(e.handle(.choiceMade("settings.voiceStyle"), isPresent: all) == .none)
        #expect(e.handle(.action(TourEventName.recordingStarted), isPresent: all) == .none)
        #expect(e.handle(.menuOpened("settings.model"), isPresent: all) == .none)
        #expect(e.current == 1)
        #expect(e.handle(.choiceMade("settings.model"), isPresent: all) == .show(step: 2))
    }

    @Test func eventsDoNothingOnExplainStepsButAlreadyDoneTryStepsAreSkipped() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        #expect(e.handle(.choiceMade("settings.model"), isPresent: all) == .none)
        #expect(e.current == 0)
        #expect(e.next(isPresent: all) == .show(step: 2))   // step 1 done early → skipped silently
    }

    @Test func skipStepMovesOnFromTryStep() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 1, isPresent: all)
        #expect(e.skipStep(isPresent: all) == .show(step: 2))
    }

    @Test func missingAnchorsAreSkipped() {
        var e = TourEngine(tour: engineTour)
        #expect(e.start(isPresent: except("settings.a", "settings.b")) == .show(step: 2))
        #expect(e.next(isPresent: except("settings.d")) == .show(step: 4))
    }

    @Test func anchorVanishingMidStepSkipsIt() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 2, isPresent: all)
        #expect(e.skipIfAnchorMissing(isPresent: all) == .none)
        #expect(e.skipIfAnchorMissing(isPresent: except("settings.c")) == .show(step: 3))
    }

    @Test func startWithNothingPresentChangesNothing() {
        var e = TourEngine(tour: engineTour)
        #expect(e.start(isPresent: none) == .nothingToShow)
        #expect(e.status == .idle)
        var empty = TourEngine(tour: Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: []))
        #expect(empty.start(isPresent: all) == .nothingToShow)
    }

    @Test func lastNextFinishesWithHandOver() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 4, isPresent: all)
        #expect(e.next(isPresent: all) == .finished(handsOverTo: .welcome))
        #expect(e.status == .finished)
        #expect(e.next(isPresent: all) == .none)
    }

    @Test func finishingByTryEventOnLastStep() {
        let last = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
            TourStep(anchor: "welcome.a", kind: .explain, title: "A", body: "A."),
            TourStep(anchor: "welcome.b", kind: .tryIt(advanceOn: .action(TourEventName.dictationPasted)), title: "B", body: "Dictate."),
        ], handsOverTo: .recordingPill)
        var e = TourEngine(tour: last)
        _ = e.start(isPresent: all)
        _ = e.next(isPresent: all)
        #expect(e.handle(.action(TourEventName.dictationPasted), isPresent: all) == .finished(handsOverTo: .recordingPill))
    }

    @Test func trailingMissingAnchorsFinish() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 3, isPresent: all)
        #expect(e.skipStep(isPresent: except("settings.e")) == .finished(handsOverTo: .welcome))
    }

    @Test func skipTourFromRunningOrPaused() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        #expect(e.skipTour() == .skipped)
        #expect(e.status == .skipped)
        #expect(e.next(isPresent: all) == .none)
        var p = TourEngine(tour: engineTour)
        _ = p.start(isPresent: all)
        _ = p.pause()
        #expect(p.skipTour() == .skipped)
    }

    @Test func pauseKeepsIndexAndResumeReturnsThere() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        _ = e.next(isPresent: all)
        _ = e.skipStep(isPresent: all)
        #expect(e.pause() == .paused(at: 2))
        #expect(e.handle(.action(TourEventName.recordingStarted), isPresent: all) == .none)
        #expect(e.next(isPresent: all) == .none)
        #expect(e.resume(isPresent: all) == .show(step: 2))
        #expect(e.status == .running)
    }

    @Test func resumeSkipsStepsNowMissing() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 2, isPresent: all)
        _ = e.pause()
        #expect(e.resume(isPresent: except("settings.c")) == .show(step: 3))
    }

    @Test func resumeWithNothingPresentStaysPaused() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 2, isPresent: all)
        _ = e.pause()
        #expect(e.resume(isPresent: none) == .nothingToShow)
        #expect(e.status == .paused)
        #expect(e.current == 2)
    }

    @Test func startAtPersistedIndexAndOutOfRangeFallsBackToZero() {
        var e = TourEngine(tour: engineTour)
        #expect(e.start(at: 3, isPresent: all) == .show(step: 3))
        var f = TourEngine(tour: engineTour)
        #expect(f.start(at: 99, isPresent: all) == .show(step: 0))
        var g = TourEngine(tour: engineTour)
        #expect(g.start(at: -1, isPresent: all) == .show(step: 0))
    }

    @Test func pauseAndResumeWhenIdleDoNothing() {
        var e = TourEngine(tour: engineTour)
        #expect(e.pause() == .none)
        #expect(e.resume(isPresent: all) == .none)
    }

    // MARK: requires

    @Test func aStepWhoseRequirementWasNeverSeenIsSkipped() {
        var e = TourEngine(tour: requiresTour)
        #expect(e.start(isPresent: all) == .show(step: 0))
        #expect(e.skipStep(isPresent: all) == .show(step: 1))
        #expect(e.next(isPresent: all) == .show(step: 3))
    }

    @Test func aStepWhoseRequirementWasSeenIsShown() {
        var e = TourEngine(tour: requiresTour)
        _ = e.start(isPresent: all)
        #expect(e.handle(.action(TourEventName.recordingStarted), isPresent: all) == .show(step: 1))
        #expect(e.next(isPresent: all) == .show(step: 2))
    }

    @Test func aRequirementSeenOnAnExplainStepCountsToo() {
        var e = TourEngine(tour: requiresTour)
        _ = e.start(isPresent: all)
        _ = e.skipStep(isPresent: all)
        _ = e.handle(.action(TourEventName.recordingStarted), isPresent: all)
        #expect(e.next(isPresent: all) == .show(step: 2))
    }

    @Test func startingAtAStepWhoseRequirementIsMissingSkipsIt() {
        var e = TourEngine(tour: requiresTour)
        #expect(e.start(at: 2, isPresent: all) == .show(step: 3))
        var carried = TourEngine(tour: requiresTour, observed: [.action(TourEventName.recordingStarted)])
        #expect(carried.start(at: 2, isPresent: all) == .show(step: 2))
    }

    @Test func aTrailingUnmetRequirementFinishesTheTour() {
        let short = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill), steps: [
            TourStep(anchor: "pill.a", kind: .tryIt(advanceOn: .action(TourEventName.recordingStarted)), title: "A", body: "Start."),
            TourStep(anchor: "pill.b", kind: .tryIt(advanceOn: .action(TourEventName.recordingStopped)), title: "B",
                     body: "Stop.", requires: .action(TourEventName.recordingStarted)),
        ])
        var e = TourEngine(tour: short)
        _ = e.start(isPresent: all)
        #expect(e.skipStep(isPresent: all) == .finished(handsOverTo: nil))
    }

    // MARK: progress — "n of m"

    @Test func progressCountsEveryStepWhenAllShow() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        #expect(progress(e, all) == "1/5")
        _ = e.next(isPresent: all)
        #expect(progress(e, all) == "2/5")
    }

    @Test func progressNeverSkipsANumberForMissingControls() {
        let ten = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill),
                       steps: (1...10).map { TourStep(anchor: "pill.s\($0)", kind: .explain, title: "S", body: "S.") })
        let present = except("pill.s2", "pill.s5")
        var e = TourEngine(tour: ten)
        var seen: [String] = []
        var effect = e.start(isPresent: present)
        while case .show = effect {
            seen.append(progress(e, present) ?? "nil")
            effect = e.next(isPresent: present)
        }
        #expect(seen == ["1/8", "2/8", "3/8", "4/8", "5/8", "6/8", "7/8", "8/8"])
    }

    @Test func progressTotalFollowsControlsComingAndGoing() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        #expect(progress(e, except("settings.c", "settings.e")) == "1/3")
        #expect(progress(e, all) == "1/5")
    }

    @Test func progressLeavesOutTryStepsAlreadyDone() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(isPresent: all)
        _ = e.handle(.action(TourEventName.recordingStarted), isPresent: all)
        #expect(progress(e, all) == "1/4")
    }

    @Test func progressExpectsARequirementATryStepAheadWillMeet() {
        var e = TourEngine(tour: requiresTour)
        _ = e.start(isPresent: all)
        #expect(progress(e, all) == "1/4")
        _ = e.skipStep(isPresent: all)
        #expect(progress(e, all) == "2/3")
    }

    @Test func progressOfAResumedRunCountsTheEarlierRunsSteps() {
        var e = TourEngine(tour: engineTour)
        _ = e.start(at: 2, isPresent: all)
        #expect(progress(e, all) == "3/5")
        #expect(progress(e, except("settings.a")) == "2/4")
    }

    @Test func progressIsNilWhenNotRunning() {
        var e = TourEngine(tour: engineTour)
        #expect(progress(e, all) == nil)
        _ = e.start(at: 4, isPresent: all)
        _ = e.next(isPresent: all)
        #expect(progress(e, all) == nil)
    }
}
#endif
