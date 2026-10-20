import SwiftUI

/// Timing tokens used across the dictation flow and UI. Refer to these instead
/// of writing literal delays / animation durations inline.
public enum AppTimings {
    /// PasteManager: how long to delay before restoring the prior pasteboard.
    /// Chromium/Electron apps (the Claude desktop app, browsers) read the
    /// clipboard only when their page gets to the Cmd+V; while it is busy (e.g.
    /// streaming a reply) that took longer than the old 0.30 s, so they pasted the
    /// RESTORED clipboard instead of the dictation (reproduced 2026-10-20: a page
    /// busy 600 ms pasted the old clipboard at 0.30 s, the dictation at 1.5 s).
    public static let pasteRestoreDelay: TimeInterval = 1.5
    /// PasteManager: how long to wait after activating the front app before pasting.
    /// Only paid when the paste target is NOT already frontmost (it nearly always
    /// is — the user dictates into the app they're in), see `finishTranscription`.
    public static let pasteActivationDelay: TimeInterval = 0.08
    /// StreamingTranscriptionSession: how often the growing WAV is checked for
    /// new audio. Was 1 s (2026-09-12: 250 ms, then 100 ms). AVAudioRecorder
    /// flushes in ~320 ms bursts, so the session first stats the file and skips
    /// the read when nothing arrived; a real poll is a tail read + RMS windows
    /// over ≤ 25 s of audio (≈1 ms). The cadence bounds how late a pause is
    /// noticed for the speculative tail decode (`speculativeTailPause`).
    public static let streamingPoll: TimeInterval = 0.1
    /// StreamingTranscriptionSession: trailing silence after which the pending
    /// audio is decoded speculatively, betting the user is about to press stop
    /// (a hit makes the stop→paste wait ≈ 0). Shorter = more wasted decodes on
    /// mid-sentence pauses; longer = less head start before the press.
    public static let speculativeTailPause: TimeInterval = 0.4
    /// AI Polish: hard deadline on the whole polish attempt (key read + request + reply). Past it
    /// the local text is pasted unchanged — the polish is never worth more than this wait.
    public static let aiPolishTimeout: TimeInterval = 3.0

    /// Motion tokens — durations and curves used across the UI.
    public enum Motion {
        public static let pressFeedback: TimeInterval = 0.10
        public static let press = Animation.easeOut(duration: pressFeedback)
    }
}
