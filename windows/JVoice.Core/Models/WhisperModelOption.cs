namespace JVoice.Core.Models;

/// Ports Swift WhisperModelOption. On Windows we map to GGML (whisper.cpp) files
/// instead of WhisperKit CoreML folders. See overview §2.5 for the mapping table.
public enum WhisperModelOption
{
    Tiny,
    Base,
    Small,
    LargeTurbo,
}

public static class WhisperModelOptionExtensions
{
    public static string DisplayName(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "Tiny",
        WhisperModelOption.Base => "Base",
        WhisperModelOption.Small => "Small",
        WhisperModelOption.LargeTurbo => "Large",
        _ => "Tiny",
    };

    /// GGML model filename (downloaded from Hugging Face ggerganov/whisper.cpp).
    public static string GgmlFileName(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "ggml-tiny.bin",
        WhisperModelOption.Base => "ggml-base.bin",
        WhisperModelOption.Small => "ggml-small.bin",
        WhisperModelOption.LargeTurbo => "ggml-large-v3-turbo-q5_0.bin",
        _ => "ggml-tiny.bin",
    };

    /// One-line picker caption (ports VoiceCoordinator.WhisperModelChoice.guidance,
    /// with sizes/wording adjusted for the Windows GGML download).
    public static string Guidance(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "Fastest · smallest download · least accurate",
        WhisperModelOption.Base => "Fast · balanced accuracy",
        WhisperModelOption.Small => "Slower · more accurate",
        WhisperModelOption.LargeTurbo => "Most accurate · ~550 MB download · GPU-accelerated when available",
        _ => "",
    };
}
