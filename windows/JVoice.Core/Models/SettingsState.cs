namespace JVoice.Core.Models;

public sealed record SettingsState(
    int SchemaVersion,
    ToneStyle Mode,
    WhisperModelOption Model,
    TranscriptionLanguage Language,
    IReadOnlyList<string> CustomWords,
    bool RemoveFillerWords,
    IReadOnlyList<CorrectionRule> Corrections,
    HotkeyChord Hotkey,
    GameDetectionMode GameMode = GameDetectionMode.Balanced,
    bool DeveloperTerms = true,
    // ── v3 (Windows-only dictation features; no macOS counterpart) ──
    // Paste target: when true, dictation copies to the clipboard instead of auto-pasting.
    bool CopyToClipboardOnly = false,
    // Opt-in "undo last paste" chord. null = disabled (any registered global chord is swallowed
    // system-wide, so there is deliberately no default — the user assigns a rare chord).
    HotkeyChord? UndoHotkey = null,
    // Whisper "translate" task: output English regardless of the spoken/source Language.
    bool TranslateToEnglish = false,
    // Master toggle for app-aware modes (auto-switch tone by foreground app; built-in code apps).
    bool AppAwareModes = true,
    // User per-app rules (built-in code apps are implicit in AppModeResolver, not persisted).
    // Nullable param + normalized property so a defaulted/positional construction never yields null.
    IReadOnlyList<AppModeRule>? AppModeRules = null,
    // ── v4 (Windows-only) ──
    // Automatically check GitHub for a newer JVoice release and offer an in-app update. On by
    // default; the check is a single anonymous GET to the GitHub API that sends no user data (the
    // second and only other network call besides the one-time model download). No macOS counterpart.
    bool CheckForUpdates = true)
{
    public const int CurrentSchemaVersion = 4;

    public IReadOnlyList<AppModeRule> AppModeRules { get; init; } = AppModeRules ?? Array.Empty<AppModeRule>();

    public static SettingsState Default => new(
        SchemaVersion: CurrentSchemaVersion,
        Mode: ToneStyle.Casual,
        // Windows-only divergence from macOS (which defaults to .tiny — see
        // ../../../Sources/JVoice/Models/SettingsState.swift). On Windows the default is the
        // most-accurate model: with GPU acceleration Large ("large-v3-turbo") is both the best
        // and fast, so it is the right out-of-the-box choice. The Settings "Whisper Model" card
        // shows a warning advising the user to keep this on Large unless they know they need a
        // smaller model. Kept in sync with SettingsStateJson.ParseModel's fallback so any
        // unspecified-model path lands on the same default.
        Model: WhisperModelOption.LargeTurbo,
        Language: TranscriptionLanguage.English,
        CustomWords: Array.Empty<string>(),
        RemoveFillerWords: true,
        Corrections: Array.Empty<CorrectionRule>(),
        // Windows-only: the global hotkey chord. On macOS the KeyboardShortcuts library
        // persists this in its own UserDefaults key, outside SettingsState; the Windows
        // port folds it into settings.json like the other Windows-only fields. Default is
        // Ctrl+Shift+Space (HotkeyChord.Default).
        Hotkey: HotkeyChord.Default,
        GameMode: GameDetectionMode.Balanced,
        DeveloperTerms: true,
        CopyToClipboardOnly: false,
        UndoHotkey: null,
        TranslateToEnglish: false,
        AppAwareModes: true,
        AppModeRules: Array.Empty<AppModeRule>(),
        CheckForUpdates: true);
}
