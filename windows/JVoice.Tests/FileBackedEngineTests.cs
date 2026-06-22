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
}
