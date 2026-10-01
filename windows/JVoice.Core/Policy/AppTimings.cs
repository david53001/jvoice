namespace JVoice.Core;

public static class AppTimings
{
    /// PasteManager: wait after pasting before restoring the prior clipboard.
    public static readonly TimeSpan PasteRestoreDelay = TimeSpan.FromMilliseconds(300);
    /// PasteManager: shorter restore delay used when the paste FAILED (macOS used 0.05 s).
    public const int PasteRestoreDelayFailureMs = 50;
    /// VoiceCoordinator: wait after re-activating the target window before SendInput.
    public static readonly TimeSpan PasteActivationDelay = TimeSpan.FromMilliseconds(80);
    /// HotKeyManager debounce.
    public const int HotkeyDebounceMs = 150;
    /// SettingsStore debounce.
    public const int SettingsDebounceMs = 500;
    /// StreamingTranscriptionSession poll cadence: 100 ms, as the Mac (parity row 2). Each poll
    /// first checks the WAV's length on an open handle and skips the read when it hasn't grown (the
    /// recorder flushes every ~250 ms), so the 10 Hz cadence costs ~nothing — and the speculative
    /// tail decode notices a pause within ~0.1 s.
    public const int StreamingPollMs = 100;
    /// Trailing silence after which the pending audio is decoded speculatively (Mac 0.4 s, row 3).
    public const int SpeculativeTailPauseMs = 400;
    /// HUD auto-dismiss after a terminal state.
    public static readonly TimeSpan HudResetDelay = TimeSpan.FromMilliseconds(1000);
    /// HUD auto-dismiss after an error.
    public static readonly TimeSpan HudErrorResetDelay = TimeSpan.FromMilliseconds(3000);
    /// Settings → Recent Transcripts: how long the Copy button shows a checkmark
    /// before flipping back to the copy icon.
    public static readonly TimeSpan CopyFeedbackDuration = TimeSpan.FromMilliseconds(1200);
}
