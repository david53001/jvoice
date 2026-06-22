using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class StreamingSessionTests
{
    // Fast poll so tests don't sleep a real second.
    private const int FastPollMs = 20;
    private static readonly ChunkPlanner.Config Cfg = new();

    private static byte[] BuildWav(short[] samples)
    {
        var ms = new MemoryStream();
        void U32(int v) => ms.Write(BitConverter.GetBytes((uint)v));
        void U16(int v) => ms.Write(BitConverter.GetBytes((ushort)v));
        void A(string s) => ms.Write(System.Text.Encoding.ASCII.GetBytes(s));
        A("RIFF"); U32(0); A("WAVE");
        A("fmt "); U32(16); U16(1); U16(1); U32(16000); U32(32000); U16(2); U16(16);
        A("data"); U32(samples.Length * 2);
        foreach (var s in samples) ms.Write(BitConverter.GetBytes(s));
        return ms.ToArray();
    }

    private static short[] Loud(int seconds)
    {
        var s = new short[seconds * 16000];
        for (int i = 0; i < s.Length; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000);
        return s;
    }
    private static short[] Silence(int seconds) => new short[seconds * 16000];
    private static short[] Concat(params short[][] p) => p.SelectMany(x => x).ToArray();

    private static string WriteTemp(short[] samples)
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvstream-{Guid.NewGuid():N}.wav");
        File.WriteAllBytes(path, BuildWav(samples));
        return path;
    }

    [Fact]
    public async Task HappyPath_JoinsNonEmptyPieces()
    {
        // 16s loud, 2s silence, 5s loud → at least one chunk + tail, all decode "x".
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(300); // let the poll loop run a few iterations
            var result = await session.Finish();
            Assert.NotNull(result);
            Assert.Contains("x", result!);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task NonSilentChunkDecodesEmpty_FailsToNull()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            // A non-silent chunk that decodes to "" must fail the session (no silent drop).
            var session = new StreamingTranscriptionSession(_ => Task.FromResult(""), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(300);
            var result = await session.Finish();
            Assert.Null(result); // caller falls back to whole-file
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Finish_IsIdempotent()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(150);
            await session.Finish();
            Assert.Null(await session.Finish()); // second finish returns null
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Cancel_ThenFinish_ReturnsNull()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await session.Cancel();
            Assert.Null(await session.Finish());
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task NeverStarted_FinishReturnsNull()
    {
        var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
        Assert.Null(await session.Finish());
    }
}
