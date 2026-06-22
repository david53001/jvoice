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

    // ===== Swift-parity vectors (fast config: 0.5 s min / 1.0 s max chunks) =====

    private static readonly ChunkPlanner.Config FastCfg =
        new() { MinChunkSeconds = 0.5, MaxChunkSeconds = 1.0 };

    private static short[] LoudN(int n)
    {
        var s = new short[n];
        for (int i = 0; i < n; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000);
        return s;
    }
    private static short[] SilenceN(int n) => new short[n];

    private sealed class Counter
    {
        private readonly object _lock = new();
        public List<int> Calls { get; } = new();
        public Task<string> Next(float[] samples)
        {
            lock (_lock) { Calls.Add(samples.Length); return Task.FromResult($"piece{Calls.Count}"); }
        }
    }

    private sealed class IndexedEmptyMock
    {
        private readonly int _emptyAt;
        private readonly object _lock = new();
        private int _call;
        public IndexedEmptyMock(int emptyAt) => _emptyAt = emptyAt;
        public Task<string> Next(float[] _)
        {
            lock (_lock) { _call++; return Task.FromResult(_call == _emptyAt ? "" : $"piece{_call}"); }
        }
    }

    private static void DeleteWithRetry(string path)
    {
        for (int i = 0; i < 50; i++)
        {
            try { File.Delete(path); return; }
            catch (IOException) { System.Threading.Thread.Sleep(10); }
        }
    }

    // The crown jewel: chunks + tail are transcribed in order, every piece stays within the
    // single-window cap, and NO samples are lost or duplicated (sum == total). Mirrors Swift
    // transcribesChunksAndTailInOrder.
    [Fact]
    public async Task TranscribesChunksAndTail_InOrder_NoLossNoDuplication()
    {
        string path = WriteTemp(LoudN(41600)); // 2.6 s of speech-level audio
        try
        {
            var counter = new Counter();
            var session = new StreamingTranscriptionSession(counter.Next, FastCfg, FastPollMs);
            session.Start(path);
            await Task.Delay(300); // let the poll loop drain the streamable chunks
            var result = await session.Finish();

            Assert.NotNull(result);
            int n = counter.Calls.Count;
            Assert.True(n >= 2); // at least one streamed chunk + the tail
            Assert.Equal(string.Join(" ", Enumerable.Range(1, n).Select(i => $"piece{i}")), result);
            Assert.All(counter.Calls, c => Assert.True(c <= 16000 + 1600)); // within the 1.0 s cap (+slack)
            Assert.Equal(41600, counter.Calls.Sum());                       // nothing lost, nothing duplicated
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task TranscriberThrows_FailsToNull()
    {
        string path = WriteTemp(LoudN(32000)); // 2 s
        try
        {
            var session = new StreamingTranscriptionSession(
                _ => Task.FromException<string>(new InvalidOperationException("boom")), FastCfg, FastPollMs);
            session.Start(path);
            await Task.Delay(150);
            Assert.Null(await session.Finish()); // error → fall back to whole-file
        }
        finally { File.Delete(path); }
    }

    // Only the 2nd transcribed chunk returns empty; the session must fail (not emit a transcript
    // missing that ~1 s of speech). Mirrors Swift oneEmptyChunkAnywhereForcesWholeFileFallback.
    [Fact]
    public async Task OneEmptyChunkAnywhere_ForcesWholeFileFallback()
    {
        string path = WriteTemp(LoudN(41600)); // 2.6 s → several chunks
        try
        {
            var mock = new IndexedEmptyMock(emptyAt: 2);
            var session = new StreamingTranscriptionSession(mock.Next, FastCfg, FastPollMs);
            session.Start(path);
            await Task.Delay(300);
            Assert.Null(await session.Finish());
        }
        finally { File.Delete(path); }
    }

    // A genuinely silent region is dropped (never transcribed) and must NOT fail the session;
    // the speech still streams through. Mirrors Swift silentRegionIsDroppedNotTreatedAsDataLoss.
    [Fact]
    public async Task SilentRegion_IsDropped_NotDataLoss()
    {
        string path = WriteTemp(Concat(LoudN(19200), SilenceN(19200))); // 1.2 s speech + 1.2 s silence
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("speech"), FastCfg, FastPollMs);
            session.Start(path);
            await Task.Delay(300);
            var result = await session.Finish();
            Assert.NotNull(result);
            Assert.Contains("speech", result!);
        }
        finally { File.Delete(path); }
    }

    // File vanishes mid-recording (failure teardown): the next poll's read returns null → the
    // session fails → finish() returns null. Mirrors Swift vanishedFileFailsSessionSafely.
    [Fact]
    public async Task VanishedFile_FailsSafely_ReturnsNull()
    {
        string path = WriteTemp(LoudN(32000)); // 2 s
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), FastCfg, FastPollMs);
            session.Start(path);
            await Task.Delay(80);
            DeleteWithRetry(path);
            await Task.Delay(150);
            Assert.Null(await session.Finish());
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
