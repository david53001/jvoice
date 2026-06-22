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
    /// StreamingTranscriptionSession poll cadence.
    public const int StreamingPollMs = 1000;
    /// HUD auto-dismiss after a terminal state.
    public static readonly TimeSpan HudResetDelay = TimeSpan.FromMilliseconds(1000);
    /// HUD auto-dismiss after an error.
    public static readonly TimeSpan HudErrorResetDelay = TimeSpan.FromMilliseconds(3000);
}
