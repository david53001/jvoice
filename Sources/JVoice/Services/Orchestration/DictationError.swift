import Foundation

/// Specific, user-facing dictation failures. One source of truth for the HUD
/// error copy — there is deliberately no generic fallback. Permission failures
/// (microphone / Accessibility) are handled separately by `PermissionError`
/// because they also open the relevant System Settings pane.
///
/// Foundation-only on purpose so the copy is verified by both the swift-testing
/// suite and scripts/run-logic-tests.sh.
public enum DictationError: Equatable, CaseIterable, Sendable {
    case noMicrophone
    case recorderFailedToStart
    case recordingInterrupted
    case recordingTooShort
    case noSpeechHeard
    case noTextFieldFocused
    case modelLoadFailed
    case transcriptionFailed
    case pasteFailed
    case clipboardBusy

    public var message: String {
        switch self {
        case .noMicrophone:
            return "No microphone detected. Connect one and try again."
        case .recorderFailedToStart:
            return "Couldn't start recording. Please try again."
        case .recordingInterrupted:
            return "Recording was interrupted (audio device changed)."
        case .recordingTooShort:
            return "That was too quick — hold the hotkey while you speak."
        case .noSpeechHeard:
            return "We didn't hear anything — check your mic volume and try again."
        case .noTextFieldFocused:
            return "No place to paste — click into a text field first."
        case .modelLoadFailed:
            return "The speech model failed to load. Please restart JVoice."
        case .transcriptionFailed:
            return "Couldn't transcribe that audio. Please try again."
        case .pasteFailed:
            return "Couldn't paste into this app."
        case .clipboardBusy:
            return "Clipboard was busy — try again."
        }
    }
}
