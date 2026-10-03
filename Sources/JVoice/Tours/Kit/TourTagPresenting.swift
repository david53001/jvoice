import AppKit

/// What the app's `TourCoordinator` needs from the on-screen tag (the outline box + tag bubble + leader
/// line, spec §14.3). `TagOverlayController` is the real one; tests and probes can pass a fake.
@MainActor
public protocol TourTagPresenting: AnyObject {
    /// Explain steps: Next (Return). On the last step the button reads "Done" and also calls this.
    var onNext: (() -> Void)? { get set }
    /// Try steps: "Skip step".
    var onSkipStep: (() -> Void)? { get set }
    /// "Skip tour" (Esc).
    var onSkipTour: (() -> Void)? { get set }

    /// Shows `step` pointing at `anchor` (a view inside `host`), replacing whatever was shown.
    /// `body` has its `{shortcut:…}` placeholders already resolved; `number`/`total` read "2 of 7".
    func show(step: TourStep, body: String, number: Int, total: Int, anchor: NSView, host: NSWindow)
    /// A Try step was just done: a brief "done" state (and VoiceOver announcement) before the next step.
    func showCompleted()
    func hide()
    /// The step on screen keeps its place, but "n of m" changed (a later step's control appeared or went).
    func updateProgress(number: Int, total: Int)
}

public extension TourTagPresenting {
    /// Presenters that only show a counter when a step appears can ignore mid-step changes.
    func updateProgress(number: Int, total: Int) {}
}
