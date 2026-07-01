using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the "marketing" download-progress curve. Requirements (David, 2026-07-01):
///  - the bar never shows the exact byte percentage — it is EASED so it feels good;
///  - it moves FAST early and DECELERATES toward the end;
///  - it never stalls (a time-based crawl fills gaps when the server sends no length);
///  - it never reaches 100% until the download is actually done (then it snaps to full).
public class UpdateProgressCurveTests
{
    private const double Eps = 1e-9;

    [Fact]
    public void FromFraction_StartsAtZero_AndCapsBelowFull()
    {
        Assert.Equal(0.0, UpdateProgressCurve.FromFraction(0.0), 6);
        // At 100% real bytes the bar is held at the ceiling, NOT full — full is reserved for done.
        Assert.Equal(UpdateProgressCurve.Ceiling, UpdateProgressCurve.FromFraction(1.0), 6);
        Assert.True(UpdateProgressCurve.Ceiling < 1.0);
    }

    [Fact]
    public void FromFraction_ClampsOutOfRangeInput()
    {
        Assert.Equal(0.0, UpdateProgressCurve.FromFraction(-0.5), 6);
        Assert.Equal(UpdateProgressCurve.Ceiling, UpdateProgressCurve.FromFraction(1.5), 6);
    }

    [Fact]
    public void FromFraction_IsMonotonicNonDecreasing()
    {
        double prev = -1;
        for (int i = 0; i <= 100; i++)
        {
            double d = UpdateProgressCurve.FromFraction(i / 100.0);
            Assert.True(d >= prev - Eps, $"decreased at {i}%: {d} < {prev}");
            prev = d;
        }
    }

    [Fact]
    public void FromFraction_IsFrontLoaded_AboveLinearEarly()
    {
        // Ease-out: displayed runs AHEAD of the true fraction in the first half (feels fast early).
        Assert.True(UpdateProgressCurve.FromFraction(0.25) > 0.25);
        Assert.True(UpdateProgressCurve.FromFraction(0.5) > 0.5);
    }

    [Fact]
    public void FromFraction_Decelerates_TowardTheEnd()
    {
        double early = UpdateProgressCurve.FromFraction(0.20) - UpdateProgressCurve.FromFraction(0.10);
        double late = UpdateProgressCurve.FromFraction(0.90) - UpdateProgressCurve.FromFraction(0.80);
        Assert.True(late < early, $"expected the tail to move slower: late={late} !< early={early}");
    }

    [Fact]
    public void FromElapsed_Crawls_Forward_And_Decelerates_Bounded()
    {
        Assert.Equal(0.0, UpdateProgressCurve.FromElapsed(0.0), 6);

        double prev = -1;
        for (double t = 0; t <= 120; t += 1)
        {
            double d = UpdateProgressCurve.FromElapsed(t);
            Assert.True(d >= prev - Eps, $"crawl decreased at t={t}");
            Assert.True(d < UpdateProgressCurve.Ceiling + Eps, $"crawl exceeded ceiling at t={t}");
            prev = d;
        }
        // It keeps approaching the ceiling with enough time, but never a full bar.
        Assert.True(UpdateProgressCurve.FromElapsed(600) > 0.9 * UpdateProgressCurve.Ceiling);
        Assert.True(UpdateProgressCurve.FromElapsed(600) < 1.0);
    }

    [Fact]
    public void Display_Done_IsFull_RegardlessOfBytes()
    {
        Assert.Equal(1.0, UpdateProgressCurve.Display(0, null, 0, done: true), 9);
        Assert.Equal(1.0, UpdateProgressCurve.Display(10, 1000, 3, done: true), 9);
    }

    [Fact]
    public void Display_KnownTotal_UsesEasedRealFraction()
    {
        Assert.Equal(UpdateProgressCurve.FromFraction(0.5),
                     UpdateProgressCurve.Display(500, 1000, 42, done: false), 9);
    }

    [Fact]
    public void Display_UnknownTotal_UsesTimeCrawl()
    {
        Assert.Equal(UpdateProgressCurve.FromElapsed(7.0),
                     UpdateProgressCurve.Display(12345, null, 7.0, done: false), 9);
    }

    [Fact]
    public void Display_NeverLeavesUnitInterval()
    {
        foreach (var (recv, total, t, done) in new (long, long?, double, bool)[]
        {
            (0, 0, 0, false), (5, 0, 1, false), (100, 100, 5, false),
            (0, null, 0, false), (0, null, 1000, false), (10, 1000, -3, false),
        })
        {
            double d = UpdateProgressCurve.Display(recv, total, t, done);
            Assert.InRange(d, 0.0, 1.0);
        }
    }
}
