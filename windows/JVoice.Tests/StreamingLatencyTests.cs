using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

/// <summary>
/// The Mac's streaming latency layer (parity rows 3, 4, 6; Mac verify-streaming.sh scenarios 9–20) with a
/// mock decoder over a real growing WAV: speculative tail decode (hit / miss / jitter / reuse / soft
/// speech / empty), an in-flight chunk decode surviving the stop press, and local recovery of a failed
/// chunk (region from the last kept piece; >70 % or nothing kept → whole-file; empty recovery →
/// whole-file). Plus the Windows divergence #3 (room-tone check on the remainder).
/// </summary>
public class StreamingLatencyTests
{
    private const int FastPollMs = 20;
    private const int Rate = 16000;
    private static readonly ChunkPlanner.Config Cfg = new();

    private static byte[] Header(int dataSamples)
    {
        var ms = new MemoryStream();
        void U32(int v) => ms.Write(BitConverter.GetBytes((uint)v));
        void U16(int v) => ms.Write(BitConverter.GetBytes((ushort)v));
        void A(string s) => ms.Write(System.Text.Encoding.ASCII.GetBytes(s));
        A("RIFF"); U32(0); A("WAVE");
        A("fmt "); U32(16); U16(1); U16(1); U32(Rate); U32(Rate * 2); U16(2); U16(16);
        A("data"); U32(dataSamples * 2);
        return ms.ToArray();
    }

    private static short[] Loud(double seconds)
    {
        var s = new short[(int)(seconds * Rate)];
        for (int i = 0; i < s.Length; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000);
        return s;
    }

    /// Constant-amplitude "soft" audio: RMS = amplitude / 32768.
    private static short[] Level(double seconds, short amplitude)
    {
        var s = new short[(int)(seconds * Rate)];
        for (int i = 0; i < s.Length; i++) s[i] = (short)(i % 2 == 0 ? amplitude : -amplitude);
        return s;
    }

    private static short[] Silence(double seconds) => new short[(int)(seconds * Rate)];
    private static short[] Concat(params short[][] p) => p.SelectMany(x => x).ToArray();

    private static string Write(short[] samples)
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvlat-{Guid.NewGuid():N}.wav");
        using var fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite);
        fs.Write(Header(samples.Length));
        foreach (var v in samples) fs.Write(BitConverter.GetBytes(v));
        return path;
    }

    /// Append like the recorder does (the header's size field goes stale; the reader ignores it).
    private static void Append(string path, short[] samples)
    {
        using var fs = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
        foreach (var v in samples) fs.Write(BitConverter.GetBytes(v));
    }

    private static bool AllQuiet(float[] s) => s.All(v => Math.Abs(v) < 0.005f);

    /// A mock decoder: "" for all-quiet audio (the model confirming silence), else the label; records
    /// every non-quiet decode's length.
    private sealed class Decoder
    {
        public readonly List<int> Calls = new();
        public Func<float[], int, string>? Label;
        public int DelayMs;

        public async Task<string> Run(float[] s, CancellationToken ct)
        {
            if (DelayMs > 0) await Task.Delay(DelayMs, ct);
            ct.ThrowIfCancellationRequested();
            if (AllQuiet(s)) return "";
            lock (Calls) Calls.Add(s.Length);
            return Label?.Invoke(s, Calls.Count) ?? "A";
        }
    }

    private static StreamingTranscriptionSession Session(Decoder d, Func<short[], Task<string>>? recover = null, double speculate = 0.4) =>
        new(d.Run, recover, Cfg, FastPollMs, speculate);

    private static async Task Until(Func<bool> condition, int timeoutMs = 3000)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!condition() && sw.ElapsedMilliseconds < timeoutMs) await Task.Delay(10);
    }

    // ---- speculative tail decode (row 3)

    [Fact]
    public async Task Speculation_Hit_NoDecodeAfterTheStopPress()
    {
        string path = Write(Concat(Loud(5), Silence(1)));
        try
        {
            var d = new Decoder { Label = (_, n) => $"spec{n}" };
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            await Task.Delay(100);
            Assert.Single(d.Calls);
            Assert.Equal("spec1", await session.Finish());
            Assert.Single(d.Calls); // nothing decoded after the stop press
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Speculation_Miss_WhenSpeechResumes()
    {
        string path = Write(Concat(Loud(5), Silence(1)));
        try
        {
            var d = new Decoder { Label = (s, n) => $"d{n}:{s.Length / Rate}" };
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            Append(path, Loud(2));
            await Task.Delay(150);
            string? text = await session.Finish();
            // Dropped, and nothing was streamed yet: the caller's whole-file decode covers the 8 s
            // (as fast as a tail decode — Mac semantics).
            Assert.Null(text);
            Assert.Single(d.Calls);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Speculation_Kept_WhenOnlyRoomToneFollows()
    {
        string path = Write(Concat(Loud(5), Silence(1)));
        try
        {
            var d = new Decoder();
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            Append(path, Level(0.6, 5)); // ~0.00015 RMS: indistinguishable from the room
            await Task.Delay(150);
            Assert.Equal("A", await session.Finish());
            Assert.Single(d.Calls);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Speculation_Dropped_OnSoftSpeechBelowTheAbsoluteFloor()
    {
        // Windows divergence #3: 0.003 RMS is "silent" by the 0.005 floor but far above a quiet room.
        string path = Write(Concat(Loud(5), Silence(1)));
        try
        {
            var d = new Decoder { Label = (s, n) => $"d{n}:{s.Length * 10 / Rate}" };
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            Append(path, Level(1.0, 100));
            await Task.Delay(150);
            string? text = await session.Finish();
            Assert.Equal(2, d.Calls.Count);
            Assert.Equal("d2:70", text); // re-decoded with the soft second
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task ChunkCut_InsideThePause_ReusesTheSpeculation()
    {
        string path = Write(Concat(Loud(14), Silence(1)));
        try
        {
            var d = new Decoder();
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            Append(path, Silence(1)); // now 16 s → the planner cuts inside the pause
            await Task.Delay(200);
            Assert.Equal("A", await session.Finish());
            Assert.Single(d.Calls); // the chunk was never decoded twice
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task ChunkCut_NotReused_WhenSoftSpeechSitsBetween()
    {
        string path = Write(Concat(Loud(14), Silence(1)));
        try
        {
            var d = new Decoder();
            var session = Session(d);
            session.Start(path);
            await Until(() => d.Calls.Count >= 1);
            Append(path, Level(1.0, 100));
            await Task.Delay(200);
            await session.Finish();
            Assert.True(d.Calls.Count >= 2);
            Assert.Contains(d.Calls, n => n > 15 * Rate); // the chunk was decoded with the soft audio in it
        }
        finally { File.Delete(path); }
    }

    // ---- in-flight decode survives the stop press (row 4)

    [Fact]
    public async Task InFlightChunkDecode_SurvivesFinish_AndIsNotRedone()
    {
        string path = Write(Concat(Loud(16), Silence(1), Loud(2)));
        try
        {
            var d = new Decoder { DelayMs = 500 };
            var session = new StreamingTranscriptionSession(d.Run, recover: null, Cfg, FastPollMs, speculateAfterSeconds: 0);
            session.Start(path);
            await Task.Delay(100); // the chunk decode is running
            string? text = await session.Finish();
            Assert.NotNull(text);
            Assert.Equal(1, d.Calls.Count(n => n > 15 * Rate)); // exactly one decode of the chunk
        }
        finally { File.Delete(path); }
    }

    // ---- local recovery (row 6)

    [Fact]
    public async Task FailedChunk_RecoversLocally_FromTheLastKeptPiece()
    {
        // chunks [0,20.15) [20.15,36.15) ok, [36.15,52.15) fails, tail 3 s.
        string path = Write(Concat(Loud(20), Silence(1), Loud(15), Silence(1), Loud(15), Silence(1), Loud(3)));
        try
        {
            var d = new Decoder { Label = (_, n) => n == 3 ? "" : $"p{n}" };
            int? recovered = null;
            var session = Session(d, recover: pcm => { recovered = pcm.Length; return Task.FromResult("R"); }, speculate: 0);
            session.Start(path);
            await Task.Delay(400);
            string? text = await session.Finish();
            Assert.Equal("p1 R", text);
            Assert.NotNull(recovered);
            Assert.InRange(recovered!.Value / (double)Rate, 35.5, 36.2); // from the 2nd piece's start to the end
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task FailedChunk_WholeFile_WhenTheRegionIsMostOfTheRecording()
    {
        string path = Write(Concat(Loud(16), Silence(1), Loud(15), Silence(1), Loud(3)));
        try
        {
            var d = new Decoder { Label = (_, n) => n == 2 ? "" : $"p{n}" };
            bool called = false;
            var session = Session(d, recover: _ => { called = true; return Task.FromResult("R"); }, speculate: 0);
            session.Start(path);
            await Task.Delay(400);
            Assert.Null(await session.Finish());
            Assert.False(called);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task FailedFirstChunk_WholeFile_NothingKept()
    {
        string path = Write(Concat(Loud(16), Silence(1), Loud(3)));
        try
        {
            var d = new Decoder { Label = (_, _) => "" };
            bool called = false;
            var session = Session(d, recover: _ => { called = true; return Task.FromResult("R"); }, speculate: 0);
            session.Start(path);
            await Task.Delay(300);
            Assert.Null(await session.Finish());
            Assert.False(called);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task EmptyRecovery_FallsBackToWholeFile()
    {
        string path = Write(Concat(Loud(20), Silence(1), Loud(15), Silence(1), Loud(15), Silence(1), Loud(3)));
        try
        {
            var d = new Decoder { Label = (_, n) => n == 3 ? "" : $"p{n}" };
            var session = Session(d, recover: _ => Task.FromResult(""), speculate: 0);
            session.Start(path);
            await Task.Delay(400);
            Assert.Null(await session.Finish());
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task EmptySpeculation_GoesToLocalRecovery()
    {
        // pieces [0,20.15) [20.15,36.15); pending ~4.85 s ends in a pause → speculation decodes "".
        string path = Write(Concat(Loud(20), Silence(1), Loud(15), Silence(1), Loud(3), Silence(1)));
        try
        {
            var d = new Decoder { Label = (s, n) => s.Length < 6 * Rate ? "" : $"p{n}" };
            int? recovered = null;
            var session = Session(d, recover: pcm => { recovered = pcm.Length; return Task.FromResult("R"); });
            session.Start(path);
            await Task.Delay(500);
            Assert.Equal("p1 R", await session.Finish());
            Assert.InRange(recovered!.Value / (double)Rate, 20.5, 21.2);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task SilentClassifiedChunkDecodingNonEmpty_RecoversInContext()
    {
        // Windows divergence #2 now re-covers locally instead of the whole file: a below-floor 15 s chunk
        // that the model hears words in, after two kept pieces.
        string path = Write(Concat(Loud(24), Silence(1), Loud(15), Silence(1), Level(15, 100), Silence(1), Loud(3)));
        try
        {
            int? recovered = null;
            var session = new StreamingTranscriptionSession(
                (s, ct) => Task.FromResult(s.Max() < 0.01f && s.Length > 10 * Rate ? "quiet words" : "A"),
                recover: pcm => { recovered = pcm.Length; return Task.FromResult("R"); }, Cfg, FastPollMs, speculateAfterSeconds: 0);
            session.Start(path);
            await Task.Delay(400);
            Assert.Equal("A R", await session.Finish());
            Assert.InRange(recovered!.Value / (double)Rate, 35.5, 36.2);
        }
        finally { File.Delete(path); }
    }

    // ---- pure helper

    [Fact]
    public void TrailingSilenceSamples_CountsTheQuietEnd()
    {
        Assert.Equal(16000, ChunkPlanner.TrailingSilenceSamples(Concat(Loud(1), Silence(1)), Cfg));
        Assert.Equal(0, ChunkPlanner.TrailingSilenceSamples(Loud(1), Cfg));
        Assert.Equal(32000, ChunkPlanner.TrailingSilenceSamples(Silence(2), Cfg));
        Assert.Equal(0, ChunkPlanner.TrailingSilenceSamples(Array.Empty<short>(), Cfg));
    }
}
