using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

/// <summary>Parity row 34 (doc §11): windows centre on the pointer's monitor; the pill sits bottom-centre on it.</summary>
public class ScreenPlacementTests
{
    private static readonly PxRect Primary = new(0, 0, 1920, 1032);          // 1080p, taskbar 48 px
    private static readonly PxRect Right4K = new(1920, 0, 1920 + 3840, 2088); // a 4K monitor to the right, 150 %

    [Fact]
    public void CentresOnTheGivenMonitorAtItsScale()
    {
        Assert.Equal((420, 44), ScreenPlacement.Center(Primary, 1080, 945, 1.0)); // 43.5 rounds to even
        // 1080 × 945 DIPs at 150 % = 1620 × 1418 px, centred in the right-hand monitor's work area.
        Assert.Equal((1920 + 1110, 335), ScreenPlacement.Center(Right4K, 1080, 945, 1.5));
    }

    [Fact]
    public void ATooBigWindowKeepsItsTitleBarOnScreen()
    {
        var small = new PxRect(-1600, 0, 0, 1040); // a monitor LEFT of the primary (negative x)
        var (x, y) = ScreenPlacement.Center(small, 1800, 1200, 1.0);
        Assert.Equal(-1600, x);
        Assert.Equal(0, y);
    }

    [Fact]
    public void PillSitsBottomCentreWithTheCapsule64AboveTheWorkArea()
    {
        // The 404 × 100 pill panel: 22 of shadow margin below the capsule, so its bottom edge sits at
        // workBottom − 64 + 22 and the capsule's bottom 64 above the taskbar edge.
        var (x, y) = ScreenPlacement.Pill(Primary, 404, 100, 22, 1.0);
        Assert.Equal((1920 - 404) / 2, x);
        Assert.Equal(1032 - 100 + 22 - 64, y);
        // On the 150 % monitor everything scales, and x is relative to that monitor.
        var (x2, y2) = ScreenPlacement.Pill(Right4K, 404, 100, 22, 1.5);
        Assert.Equal(1920 + (3840 - 606) / 2, x2);
        Assert.Equal(2088 - (int)Math.Round((100 - 22 + 64) * 1.5), y2);
    }

    [Fact]
    public void PxRectBasics()
    {
        Assert.Equal(3840, Right4K.Width);
        Assert.True(Right4K.Contains(1920, 0));
        Assert.False(Right4K.Contains(1919, 0));
    }

    [Fact]
    public void PillTakesTheSameShareOfTheScreenAsOnTheMac()
    {
        // The Mac reference itself (MacBook Air 13", 1470 × 956 pt) → the Mac's own 240 × 56 capsule.
        Assert.Equal(1.0, ScreenPlacement.PillScale(1470, 956), 6);
        // David's desktop: 1500 × 1080 stretched on a 1920 × 1080 panel. Was 1.28 (the stretch ratio), which made
        // the recording capsule 307 × 72 — 20.5 % of the screen's width vs the Mac's 16.3 %.
        double s = ScreenPlacement.PillScale(1500, 1080);
        Assert.Equal(1.074, s, 3);
        Assert.Equal(240.0 * 56 / (1470 * 956), 240 * s * 56 * s / (1500 * 1080), 9); // same area share
        // A 4K panel at 150 % (2560 × 1440 DIPs) grows with its screen…
        Assert.Equal(Math.Sqrt(2560.0 * 1440 / (1470 * 956)), ScreenPlacement.PillScale(2560, 1440), 6);
        // …but tiny or absurd screens stay within sane bounds.
        Assert.Equal(ScreenPlacement.MinPillScale, ScreenPlacement.PillScale(1024, 600));
        Assert.Equal(ScreenPlacement.MaxPillScale, ScreenPlacement.PillScale(7680, 4320));
        Assert.Equal(1.0, ScreenPlacement.PillScale(0, 0)); // no screen info → the Mac's size
    }
}
