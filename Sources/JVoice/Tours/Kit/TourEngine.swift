/// One tour's progress, as a pure state machine (spec §14.4 / §14.6). It never touches the screen or
/// UserDefaults: every call returns an `Effect` that the app's `TourCoordinator` carries out (show a
/// tag, persist, hand over). Anchor presence is asked through `isPresent` (the coordinator checks the
/// host window) so the engine stays testable.
///
/// Rules:
/// - A step is shown only if its anchor is present and its `requires` event (if any) was seen during this
///   run; otherwise it is skipped (a "Resize your text" step whose text was never made).
/// - A Try step advances only when its exact `advanceOn` event arrives (or on Skip step) — never on Next.
/// - A Try step whose event was already seen during this run is skipped silently ("already done").
/// - Walking past the last step finishes the tour and reports its hand-over.
/// - `start`/`resume` with no presentable step left report `.nothingToShow` and change nothing, so a
///   surface that hasn't got its anchors yet never burns a tour.
public struct TourEngine: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case idle, running, paused, finished, skipped }

    /// What the caller must do after a call.
    public enum Effect: Equatable, Sendable {
        /// Nothing changed (event not awaited, call not valid in this state).
        case none
        /// Present `tour.steps[step]`.
        case show(step: Int)
        /// Done: mark seen at `tour.version`, clear its pause, hide, then start `handsOverTo`.
        case finished(handsOverTo: TourID?)
        /// Skip tour: mark seen, clear its pause, hide. No hand-over.
        case skipped
        /// Paused: persist `at` as the resume index, hide.
        case paused(at: Int)
        /// `start`/`resume` found no presentable step: leave everything as it was.
        case nothingToShow
    }

    public let tour: Tour
    public private(set) var status: Status = .idle
    /// Index of the step on screen (running) or to resume at (paused).
    public private(set) var current: Int?
    /// Every event seen while running — lets a later Try step the user already did be skipped, and a
    /// step that `requires` one be shown.
    public private(set) var observed: Set<TourEvent> = []
    /// Steps shown in this run (for the "n of m" counter).
    public private(set) var shown: Set<Int> = []
    /// Where this run started: steps before it belong to an earlier run (a resumed tour).
    public private(set) var runStart = 0

    public init(tour: Tour) {
        self.tour = tour
    }

    /// Carries events seen before a pause into the resumed run (the coordinator's own suspensions), so
    /// a step that `requires` one of them still shows.
    public init(tour: Tour, observed: Set<TourEvent>) {
        self.tour = tour
        self.observed = observed
    }

    public var currentStep: TourStep? {
        guard let current, tour.steps.indices.contains(current) else { return nil }
        return tour.steps[current]
    }

    /// Starts at `index` (0, or a persisted pause index; out-of-range → 0).
    public mutating func start(at index: Int = 0, isPresent: (String) -> Bool) -> Effect {
        guard status == .idle || status == .paused else { return .none }
        let from = tour.steps.indices.contains(index) ? index : 0
        guard let first = firstPresentable(from: from, isPresent: isPresent) else { return .nothingToShow }
        status = .running
        current = first
        runStart = from
        shown = [first]
        return .show(step: first)
    }

    /// Explain steps: Next (the last step's "Done"). Ignored on a Try step.
    public mutating func next(isPresent: (String) -> Bool) -> Effect {
        guard status == .running, let step = currentStep, step.kind == .explain else { return .none }
        return advance(isPresent: isPresent)
    }

    /// "Skip step" (any step).
    public mutating func skipStep(isPresent: (String) -> Bool) -> Effect {
        guard status == .running else { return .none }
        return advance(isPresent: isPresent)
    }

    /// "Skip tour" (Esc).
    public mutating func skipTour() -> Effect {
        guard status == .running || status == .paused else { return .none }
        status = .skipped
        current = nil
        return .skipped
    }

    /// Something the user did. Returns `.none` unless it completed the current Try step.
    public mutating func handle(_ event: TourEvent, isPresent: (String) -> Bool) -> Effect {
        guard status == .running else { return .none }
        observed.insert(event)
        guard let step = currentStep, case .tryIt(let awaited) = step.kind, awaited == event else { return .none }
        return advance(isPresent: isPresent)
    }

    /// The current step's anchor vanished (panel hidden, feature off): skip to the next presentable
    /// step. `.none` if it's still there.
    public mutating func skipIfAnchorMissing(isPresent: (String) -> Bool) -> Effect {
        guard status == .running, let step = currentStep, !isPresent(step.anchor) else { return .none }
        return advance(isPresent: isPresent)
    }

    public mutating func pause() -> Effect {
        guard status == .running, let current else { return .none }
        status = .paused
        return .paused(at: current)
    }

    public mutating func resume(isPresent: (String) -> Bool) -> Effect {
        guard status == .paused else { return .none }
        return start(at: current ?? 0, isPresent: isPresent)
    }

    /// "n of m" for the step on screen, counting only steps that show in this run (review 2026-09-26, T2):
    /// - before it: the ones shown in this run — and, for a resumed run, the earlier run's steps whose
    ///   anchor is present now;
    /// - it;
    /// - after it: the ones presentable now (anchor present, Try step not already done, `requires` met),
    ///   where a `requires` also counts as met when a counted Try step before it (this one included)
    ///   waits for that event — the user is expected to do it.
    /// Ask again whenever something may have changed (a new step, an anchor appearing or going): the
    /// numbers never skip, but the total can move. Nil unless running or paused.
    public func progress(isPresent: (String) -> Bool) -> (number: Int, total: Int)? {
        guard status == .running || status == .paused, let current else { return nil }
        var number = 0, total = 0
        var expected = observed
        for (i, step) in tour.steps.enumerated() {
            let counts: Bool
            if i < current {
                counts = shown.contains(i) || (i < runStart && isPresent(step.anchor))
            } else if i == current {
                counts = true
            } else {
                counts = isPresent(step.anchor) && !alreadyDone(step) && requirementMet(step, seen: expected)
            }
            guard counts else { continue }
            total += 1
            if i <= current { number += 1 }
            if i >= current, case .tryIt(let event) = step.kind { expected.insert(event) }
        }
        return (number, total)
    }

    // MARK: - Private

    private mutating func advance(isPresent: (String) -> Bool) -> Effect {
        let from = (current ?? -1) + 1
        if let next = firstPresentable(from: from, isPresent: isPresent) {
            current = next
            shown.insert(next)
            return .show(step: next)
        }
        status = .finished
        current = nil
        return .finished(handsOverTo: tour.handsOverTo)
    }

    private func firstPresentable(from index: Int, isPresent: (String) -> Bool) -> Int? {
        var i = max(0, index)
        while i < tour.steps.count {
            let step = tour.steps[i]
            if isPresent(step.anchor), !alreadyDone(step), requirementMet(step, seen: observed) { return i }
            i += 1
        }
        return nil
    }

    private func alreadyDone(_ step: TourStep) -> Bool {
        if case .tryIt(let event) = step.kind { return observed.contains(event) }
        return false
    }

    private func requirementMet(_ step: TourStep, seen: Set<TourEvent>) -> Bool {
        step.requires.map(seen.contains) ?? true
    }
}
