using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class ChunkPlannerTests
{
    private static readonly ChunkPlanner.Config Cfg = new();

    private static short[] Loud(int seconds)
    {
        var n = seconds * 16000;
        var s = new short[n];
        for (int i = 0; i < n; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000); // ~0.24 RMS
        return s;
    }

    private static short[] Silence(int seconds) => new short[seconds * 16000];

    private static short[] Concat(params short[][] parts)
        => parts.SelectMany(p => p).ToArray();

    [Fact]
    public void Plan_WaitsBelowMinChunk()
        => Assert.Equal(ChunkPlanner.DecisionKind.Wait, ChunkPlanner.Plan(Loud(10), Cfg).Kind);

    [Fact]
    public void Plan_CutsAtSilenceAfterMinChunk()
    {
        var audio = Concat(Loud(16), Silence(2), Loud(5));
        var d = ChunkPlanner.Plan(audio, Cfg);
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
        // Cut lands inside the silent gap (between 16s and 18s).
        Assert.InRange(d.AtSample, 16 * 16000, 18 * 16000);
    }

    [Fact]
    public void Plan_ForcesCutAtMaxWhenNoSilence()
    {
        var d = ChunkPlanner.Plan(Loud(30), Cfg); // > 25 s cap, no pause
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
    }

    [Fact]
    public void IsSilent_TrueForSilence_FalseForSpeech()
    {
        Assert.True(ChunkPlanner.IsSilent(Silence(2), Cfg));
        Assert.False(ChunkPlanner.IsSilent(Loud(2), Cfg));
    }

    [Fact]
    public void Plan_SilentChunkFlaggedSilent()
    {
        var audio = Concat(Silence(16), Loud(2), Silence(1));
        var d = ChunkPlanner.Plan(audio, Cfg);
        if (d.Kind == ChunkPlanner.DecisionKind.Cut)
            Assert.True(d.IsSilent); // the leading silence before the cut is silent
    }

    // ===== Swift-parity vectors + edges =====

    private static short[] Wave(int seconds, short amp)
    {
        var n = seconds * 16000;
        var s = new short[n];
        for (int i = 0; i < n; i++) s[i] = (short)(i % 2 == 0 ? amp : -amp);
        return s;
    }

    [Fact]
    public void Plan_WaitsOnEmpty()
        => Assert.Equal(ChunkPlanner.DecisionKind.Wait, ChunkPlanner.Plan(Array.Empty<short>(), Cfg).Kind);

    // 16 s of continuous loud audio: no pause to cut at, < 25 s cap => wait (Swift: waitsThroughContinuousSpeechUntilCap).
    [Fact]
    public void Plan_WaitsThroughContinuousSpeechBelowCap()
        => Assert.Equal(ChunkPlanner.DecisionKind.Wait, ChunkPlanner.Plan(Loud(16), Cfg).Kind);

    // Cut inside a pause after the minimum, and the leading chunk is NOT silent (Swift: cutsInsideAPauseAfterMinimum).
    [Fact]
    public void Plan_CutInPause_IsNotSilent()
    {
        var audio = Concat(Loud(17), Silence(1), Loud(2));
        var d = ChunkPlanner.Plan(audio, Cfg);
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
        Assert.InRange(d.AtSample, 17 * 16000, 18 * 16000);
        Assert.False(d.IsSilent);
    }

    // 26 s continuous: forced cut bounded to the single-window range, not silent (Swift: forcesCutAtSingleWindowCap).
    [Fact]
    public void Plan_ForcedCut_InSingleWindowRange_NotSilent()
    {
        var d = ChunkPlanner.Plan(Loud(26), Cfg);
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
        Assert.InRange(d.AtSample, 15 * 16000, 25 * 16000);
        Assert.False(d.IsSilent);
    }

    // All-silence past the minimum still produces a cut, flagged silent (so the caller drops it).
    [Fact]
    public void Plan_AllSilence_CutFlaggedSilent()
    {
        var d = ChunkPlanner.Plan(Silence(16), Cfg);
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
        Assert.True(d.IsSilent);
    }

    [Fact]
    public void IsSilent_Empty_IsTrue()
        => Assert.True(ChunkPlanner.IsSilent(Array.Empty<short>(), Cfg));

    // Quiet speech (RMS above the absolute floor) is NOT silence (Swift: silenceDetectionUsesAbsoluteFloor).
    [Fact]
    public void IsSilent_QuietSpeechAboveFloor_IsFalse()
        => Assert.False(ChunkPlanner.IsSilent(Wave(3, 1600), Cfg)); // RMS ~0.049 >> 0.005 floor

    // Non-overlapping RMS windows include the final partial window (Swift: windowRMSCoversPartialFinalWindow).
    [Fact]
    public void WindowRms_CoversPartialFinalWindow()
    {
        var energies = ChunkPlanner.WindowRms(Wave(1, 8000).AsSpan(0, 8000), 4800); // 0.5 s of samples
        Assert.Equal(2, energies.Count);          // full [0,4800) + partial [4800,8000)
        Assert.Equal(4800, energies[1].Start);
    }

    // Plan never throws on arbitrary input, and any Cut lands in (0, length].
    [Fact]
    public void Fuzz_Plan_NeverThrows_CutInBounds()
    {
        var rng = new Random(20260623);
        for (int iter = 0; iter < 300; iter++)
        {
            int n = rng.Next(0, 30 * 16000);
            var s = new short[n];
            for (int i = 0; i < n; i++) s[i] = (short)rng.Next(short.MinValue, short.MaxValue + 1);
            var d = ChunkPlanner.Plan(s, Cfg);
            if (d.Kind == ChunkPlanner.DecisionKind.Cut)
                Assert.InRange(d.AtSample, 1, n);
        }
    }
}
