using JVoice.Core.Transcription;
using Xunit;

namespace JVoice.Tests;

public class FileBackedEngineTests
{
    [Fact]
    public async Task ReadsTextFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(path, "  hello there  ");
        try
        {
            // Typed as the interface so the default interface methods are reachable.
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine();
            Assert.Equal("hello there", await engine.TranscribeAsync(path));
            Assert.True(await engine.IsReadyAsync());
            Assert.Null(await engine.MakeStreamingSessionAsync());
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task MissingFile_Throws()
    {
        ITranscriptionEngine engine = new FileBackedTranscriptionEngine();
        var ex = await Assert.ThrowsAsync<TranscriptionException>(
            () => engine.TranscribeAsync("C:/does/not/exist.txt"));
        Assert.Equal(TranscriptionErrorKind.AudioFileMissing, ex.Kind);
    }

    [Fact]
    public async Task EmptyFile_ThrowsEmptyTranscript()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(path, "   ");
        try
        {
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine();
            var ex = await Assert.ThrowsAsync<TranscriptionException>(() => engine.TranscribeAsync(path));
            Assert.Equal(TranscriptionErrorKind.EmptyTranscript, ex.Kind);
        }
        finally { File.Delete(path); }
    }

    // Swift uses strict UTF-8 (String(data:encoding:.utf8) returns nil for invalid bytes ->
    // unsupportedAudioFile). The C# port read leniently (ReadAllText replaces bad bytes with U+FFFD),
    // so the UnsupportedAudioFile path was dead and a non-UTF-8 file yielded garbage text - bug #5.
    [Fact]
    public async Task InvalidUtf8File_ThrowsUnsupportedAudioFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.bin");
        await File.WriteAllBytesAsync(path, new byte[] { 0x41, 0xFF, 0x42 }); // 'A', invalid byte, 'B'
        try
        {
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine();
            var ex = await Assert.ThrowsAsync<TranscriptionException>(() => engine.TranscribeAsync(path));
            Assert.Equal(TranscriptionErrorKind.UnsupportedAudioFile, ex.Kind);
        }
        finally { File.Delete(path); }
    }

    // Valid UTF-8 with non-ASCII content still decodes (round-trips through strict UTF-8).
    [Fact]
    public async Task ValidUtf8_NonAscii_Decodes()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(path, "  caf\u00e9 r\u0103u  "); // valid UTF-8 with non-ASCII
        try
        {
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine();
            Assert.Equal("caf\u00e9 r\u0103u", await engine.TranscribeAsync(path));
        }
        finally { File.Delete(path); }
    }
}
