namespace JVoice.Core.Models;

public sealed record SettingsState(
    int SchemaVersion,
    ToneStyle Mode,
    WhisperModelOption Model,
    TranscriptionLanguage Language,
    IReadOnlyList<string> CustomWords,
    bool RemoveFillerWords,
    IReadOnlyList<CorrectionRule> Corrections,
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
        GameMode: GameDetectionMode.Balanced,
        DeveloperTerms: true);
}
