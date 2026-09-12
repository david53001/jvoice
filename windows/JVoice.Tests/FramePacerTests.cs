using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

/// §7 #49 — the HUD's per-frame animation is paced to ~60 fps regardless of the display's
/// refresh rate (CompositionTarget.Rendering ticks at 240 Hz on David's monitor).
public class FramePacerTests
{
    [Fact]
    public void FirstFrame_AlwaysApplies()
        => Assert.True(FramePacer.ShouldApply(nowSeconds: 12.345, lastAppliedSeconds: -1));

    [Fact]
    public void FrameTooSoon_IsSkipped()
    {
        // 240 Hz tick spacing (4.17 ms) after an applied frame → skip.
        Assert.False(FramePacer.ShouldApply(nowSeconds: 1.0 + 1.0 / 240, lastAppliedSeconds: 1.0));
        Assert.False(FramePacer.ShouldApply(nowSeconds: 1.0 + 2.0 / 240, lastAppliedSeconds: 1.0));
        Assert.False(FramePacer.ShouldApply(nowSeconds: 1.0 + 3.0 / 240, lastAppliedSeconds: 1.0));
    }

    [Fact]
    public void FourthTickAt240Hz_Applies()
        => Assert.True(FramePacer.ShouldApply(nowSeconds: 1.0 + 4.0 / 240, lastAppliedSeconds: 1.0));

    [Fact]
    public void Exact60HzTick_Applies_NeverAlternates()
    {
        // A 60 Hz display must apply EVERY tick (the interval has a hair of slack for jitter).
        double last = 0;
        for (int i = 1; i <= 120; i++)
        {
            double now = i / 60.0;
            Assert.True(FramePacer.ShouldApply(now, last));
            last = now;
        }
    }

    [Fact]
    public void At240Hz_AppliesAboutSixtyPerSecond()
    {
        double last = -1; int applied = 0;
        for (int i = 0; i < 240; i++)
        {
            double now = i / 240.0;
            if (FramePacer.ShouldApply(now, last)) { applied++; last = now; }
        }
        Assert.InRange(applied, 58, 62);
    }
}
