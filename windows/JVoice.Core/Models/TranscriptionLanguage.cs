namespace JVoice.Core.Models;

public enum TranscriptionLanguage
{
    English,
    Romanian,
}

public static class TranscriptionLanguageExtensions
{
    public static string DisplayName(this TranscriptionLanguage l) => l switch
    {
        TranscriptionLanguage.English => "English",
        TranscriptionLanguage.Romanian => "Romanian",
        _ => "English",
    };

    /// whisper.cpp language code.
    public static string WhisperCode(this TranscriptionLanguage l) => l switch
    {
        TranscriptionLanguage.English => "en",
        TranscriptionLanguage.Romanian => "ro",
        _ => "en",
    };
}
