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
    /// StreamingTranscriptionSession poll cadence. WINDOWS DIVERGENCE (§7 #49): the Swift app
    /// polls every 1000 ms; here 250 ms — the recorder flushes the growing WAV every 250 ms, so a
    /// completed chunk is noticed (and its decode started) up to 750 ms sooner, shrinking the
    /// backlog Finish() must drain at the stop press. The poll itself is a tail read + RMS windows
    /// over ≤ 25 s of audio (≈1 ms) — negligible at 4 Hz.
    public const int StreamingPollMs = 250;
    /// HUD auto-dismiss after a terminal state.
    public static readonly TimeSpan HudResetDelay = TimeSpan.FromMilliseconds(1000);
    /// HUD auto-dismiss after an error.
    public static readonly TimeSpan HudErrorResetDelay = TimeSpan.FromMilliseconds(3000);
    /// Settings → Recent Transcripts: how long the Copy button shows a checkmark
    /// before flipping back to the copy icon.
    public static readonly TimeSpan CopyFeedbackDuration = TimeSpan.FromMilliseconds(1200);
}
