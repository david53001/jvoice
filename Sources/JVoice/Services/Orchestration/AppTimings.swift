import SwiftUI

/// Timing tokens used across the dictation flow and UI. Refer to these instead
/// of writing literal delays / animation durations inline.
public enum AppTimings {
    /// PasteManager: how long to delay before restoring the prior pasteboard.
    public static let pasteRestoreDelay: TimeInterval = 0.30
    /// PasteManager: how long to wait after activating the front app before pasting.
    /// Only paid when the paste target is NOT already frontmost (it nearly always
    /// is — the user dictates into the app they're in), see `finishTranscription`.
    public static let pasteActivationDelay: TimeInterval = 0.08
    /// StreamingTranscriptionSession: how often the growing WAV is re-read for a
    /// completed chunk. Was 1 s; at 250 ms a finished chunk's decode starts up to
    /// 750 ms sooner, shrinking the backlog `finish()` must drain on the stop
    /// press. A poll is a tail read + RMS windows over ≤ 25 s of audio (≈1 ms) —
    /// negligible at 4 Hz. Mirrors the Windows port's `StreamingPollMs`.
    public static let streamingPoll: TimeInterval = 0.25

    /// Motion tokens — durations and curves used across the UI.
    public enum Motion {
        public static let pressFeedback: TimeInterval = 0.10
        public static let press = Animation.easeOut(duration: pressFeedback)
    }
}
