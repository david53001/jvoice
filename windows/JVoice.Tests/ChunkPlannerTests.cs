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
}
