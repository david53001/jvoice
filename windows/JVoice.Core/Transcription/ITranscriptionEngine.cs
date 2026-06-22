using JVoice.Core.Audio;

namespace JVoice.Core.Transcription;

public interface ITranscriptionEngine
{
    Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default);

    /// Eagerly load the model so the first transcription isn't a cold start.
    Task PrewarmAsync() => Task.CompletedTask;

    /// Update the user vocabulary used to bias decoding toward custom words.
    Task UpdateVocabularyAsync(IReadOnlyList<string> words) => Task.CompletedTask;

    /// Whether the engine can transcribe immediately (model loaded).
    Task<bool> IsReadyAsync() => Task.FromResult(true);

    /// A streaming session, or null when the engine doesn't support streaming
    /// or hasn't loaded its model yet.
    Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()
        => Task.FromResult<StreamingTranscriptionSession?>(null);
}
