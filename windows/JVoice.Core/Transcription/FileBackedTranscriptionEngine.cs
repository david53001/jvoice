namespace JVoice.Core.Transcription;

/// Test/no-whisper fallback: treats the "audio" file as UTF-8 text.
/// Faithful port of FileBackedTranscriptionEngine. Used by Core tests and the
/// coordinator's no-engine path.
public sealed class FileBackedTranscriptionEngine : ITranscriptionEngine
{
    public async Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)
    {
        if (!File.Exists(audioPath))
            throw TranscriptionException.AudioFileMissing(audioPath);

        await Task.Yield();

        string transcript;
        try { transcript = await File.ReadAllTextAsync(audioPath, ct); }
        catch (Exception) { throw TranscriptionException.UnsupportedAudioFile(audioPath); }

        string trimmed = transcript.Trim();
        if (trimmed.Length == 0) throw TranscriptionException.EmptyTranscript();
        return trimmed;
    }
}
