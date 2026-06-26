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
    bool DeveloperTerms = true)
{
    public const int CurrentSchemaVersion = 2;

    public static SettingsState Default => new(
        SchemaVersion: CurrentSchemaVersion,
        Mode: ToneStyle.Casual,
        Model: WhisperModelOption.Tiny,
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
        DeveloperTerms: true);
}
