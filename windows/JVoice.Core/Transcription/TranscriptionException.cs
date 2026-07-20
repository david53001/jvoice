namespace JVoice.Core.Transcription;

public enum TranscriptionErrorKind
{
    AudioFileMissing,
    UnsupportedAudioFile,
    EmptyTranscript,
    ModelLoadFailed,
    // Windows-only (§7 #42): a chunk decode produced a phrase loop; the streaming session
    // treats the throw as a chunk failure → lossless whole-file fallback, where the
    // engine's witness re-decode heals the loop.
    DegenerateDecode,
}

public sealed class TranscriptionException : Exception
{
    public TranscriptionErrorKind Kind { get; }

    private TranscriptionException(TranscriptionErrorKind kind, string message) : base(message)
        => Kind = kind;

    public static TranscriptionException AudioFileMissing(string path)
        => new(TranscriptionErrorKind.AudioFileMissing, $"Audio file not found at {path}.");
    public static TranscriptionException UnsupportedAudioFile(string path)
        => new(TranscriptionErrorKind.UnsupportedAudioFile, $"Unsupported audio file at {path}.");
    public static TranscriptionException EmptyTranscript(string? detail = null)
        => new(TranscriptionErrorKind.EmptyTranscript,
            detail is null ? "No transcript was produced." : $"No transcript was produced. ({detail})");
    public static TranscriptionException ModelLoadFailed(string message)
        => new(TranscriptionErrorKind.ModelLoadFailed, message);
    public static TranscriptionException DegenerateDecode(string detail)
        => new(TranscriptionErrorKind.DegenerateDecode, $"Decode degenerated into a repetition loop. ({detail})");
}
