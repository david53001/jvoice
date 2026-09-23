import Foundation

/// Pure decisions extracted from `VoiceCoordinator` so they are test-locked.
/// Foundation-only on purpose: verified by both the swift-testing suite and
/// scripts/run-logic-tests.sh.
public enum CoordinatorDecisions {
    /// May a hotkey press (with no recording active) START a new recording?
    ///
    /// A pending transcript outranks a new start request. `isTranscribing` must
    /// cover the WHOLE post-stop pipeline (model-preparation wait, the streaming
    /// session's `finish()`, the whole-file decode, the paste) — not just the
    /// whole-file decode: the start branch cancels `currentTranscriptionTask`, so
    /// a press that slips through while the dictation is still being finished
    /// destroys it. Ported from the Windows port's `CoordinatorDecisions.CanStartRecording`
    /// (docs/HANDOFF-WINDOWS.md §7 #44: a hotkey re-fire 313 ms after the stop
    /// press cancelled a finished 165 s dictation's transcription).
    public static func canStartRecording(isStartingRecording: Bool, isTranscribing: Bool) -> Bool {
        !isStartingRecording && !isTranscribing
    }

    /// What a hotkey / menu / pill-stop press does.
    public enum PressAction: Equatable, Sendable {
        /// Idle: open the microphone.
        case start
        /// Recording: stop and transcribe.
        case stop
        /// The microphone is still opening (the pill is already up): end the
        /// recording as soon as it opens instead of dropping the press.
        case stopOnceOpened
        /// A stop is already running, or the previous dictation is still being
        /// transcribed/pasted — the press is ignored (and logged).
        case ignore
    }

    /// The single decision behind `VoiceCoordinator.toggleRecording`.
    /// `isRecording` wins over `isStartingRecording` (both are briefly true at
    /// the end of a start), so a press right after the mic opened is a stop.
    public static func pressAction(isRecording: Bool,
                                   isStartingRecording: Bool,
                                   isStoppingRecording: Bool,
                                   isTranscribing: Bool) -> PressAction {
        if isRecording { return isStoppingRecording ? .ignore : .stop }
        if isStartingRecording { return .stopOnceOpened }
        return canStartRecording(isStartingRecording: false, isTranscribing: isTranscribing) ? .start : .ignore
    }
}
