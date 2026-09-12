using System.Text;

namespace JVoice.Core.Transcription;

/// Test/no-whisper fallback: treats the "audio" file as UTF-8 text.
/// Faithful port of FileBackedTranscriptionEngine. Used by Core tests and the
/// coordinator's no-engine path.
public sealed class FileBackedTranscriptionEngine : ITranscriptionEngine
{
    // Strict UTF-8: throws on invalid bytes (mirrors Swift's String(data:encoding:.utf8) returning
    // nil for non-UTF-8 input). A lenient read would replace bad bytes with U+FFFD and feed a real
    // (non-text) WAV through as garbage instead of reporting it as unsupported.
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    public async Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)
    {
        if (!File.Exists(audioPath))
            throw TranscriptionException.AudioFileMissing(audioPath);

        await Task.Yield();

        byte[] bytes;
        try { bytes = await File.ReadAllBytesAsync(audioPath, ct); }
        catch (Exception) { throw TranscriptionException.UnsupportedAudioFile(audioPath); }

        string transcript;
        try { transcript = StrictUtf8.GetString(bytes); }
        catch (DecoderFallbackException) { throw TranscriptionException.UnsupportedAudioFile(audioPath); }

        string trimmed = transcript.Trim();
        if (trimmed.Length == 0) throw TranscriptionException.EmptyTranscript();
        return trimmed;
    }
}
