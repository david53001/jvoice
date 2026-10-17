using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

// WINDOWS-HANDOFF §9 (the Mac's resizable Settings, masonry cards, the shared Claude glow, the second
// launch): the pure halves, locked like the rest of the brain.
public class SettingsLayoutTests
{
    [Theory]
    [InlineData(500, 1)]
    [InlineData(560, 2)]
    [InlineData(644, 2)]    // the minimum window (700) minus margins: two ~316-DIP columns
    [InlineData(899, 2)]
    [InlineData(900, 3)]
    [InlineData(1040, 3)]   // the designed 1080 window: three columns, as since §7 #33
    [InlineData(1359, 3)]
    [InlineData(1360, 4)]
    [InlineData(1440, 4)]   // the cap (a maximized window)
    public void ColumnCount_FollowsTheContentWidth(double width, int columns) =>
        Assert.Equal(columns, MasonryLayout.ColumnCount(width));

    [Fact]
    public void EveryColumnStaysAboutAsWideAsTheCardsWereDesignedFor()
    {
        // The narrowest column at each threshold is never below ~290 DIP (today's card width ≈ 300).
        foreach (double w in new[] { MasonryLayout.TwoColumnsFrom + 40, MasonryLayout.ThreeColumnsFrom, MasonryLayout.FourColumnsFrom })
        {
            int c = MasonryLayout.ColumnCount(w);
            Assert.True(MasonryLayout.ColumnWidth(w, c) >= 290, $"{w} → {c} × {MasonryLayout.ColumnWidth(w, c)}");
        }
        Assert.Equal((1040 - 24) / 3.0, MasonryLayout.ColumnWidth(1040, 3), 9);
    }

    [Fact]
    public void EachCard_GoesIntoTheCurrentlyShortestColumn_InOrder()
    {
        // heights: a tall first card, then short ones: they fill the other columns before stacking under it.
        var placed = MasonryLayout.Place([300, 100, 100, 100, 100], columns: 3, out double total);
        Assert.Equal((0, 0.0), placed[0]);
        Assert.Equal((1, 0.0), placed[1]);
        Assert.Equal((2, 0.0), placed[2]);
        Assert.Equal((1, 112.0), placed[3]);   // column 1 and 2 tie at 100: leftmost wins
        Assert.Equal((2, 112.0), placed[4]);
        Assert.Equal(300, total);
    }

    [Fact]
    public void NoColumnKeepsAHole_TheGapBetweenColumnsIsBoundedByOneCard()
    {
        var rng = new Random(7);
        for (int run = 0; run < 200; run++)
        {
            var heights = Enumerable.Range(0, 15).Select(_ => 60 + rng.NextDouble() * 400).ToList();
            foreach (int columns in new[] { 1, 2, 3, 4 })
            {
                var placed = MasonryLayout.Place(heights, columns, out double total);
                var bottoms = new double[columns];
                for (int i = 0; i < heights.Count; i++)
                {
                    var (c, top) = placed[i];
                    // Cards in a column stack with exactly one spacing between them: no overlap, no hole.
                    Assert.Equal(bottoms[c] == 0 ? 0 : bottoms[c] + MasonryLayout.Spacing, top, 9);
                    bottoms[c] = top + heights[i];
                }
                // Shortest-column placement: the columns end within one card (+ spacing) of each other.
                Assert.True(bottoms.Max() - bottoms.Min() <= heights.Max() + MasonryLayout.Spacing + 1e-9);
                Assert.Equal(bottoms.Max(), total, 9);
            }
        }
    }

    [Fact]
    public void TheGlow_IsTheMacsFullOnThePillAndSubtleOnTheTitle()
    {
        Assert.Equal(new ClaudeGlow(1.6, 0.20, 0.70, 6), ClaudeGlow.Full);
        Assert.Equal(new ClaudeGlow(3.2, 0.12, 0.35, 4), ClaudeGlow.Subtle);
        Assert.Equal((0xD9, 0x77, 0x57), (ClaudeGlow.R, ClaudeGlow.G, ClaudeGlow.B));
        foreach (var glow in new[] { ClaudeGlow.Full, ClaudeGlow.Subtle })
        {
            var (x0, o0) = glow.Pose(0);
            Assert.Equal(-0.7, x0, 9);                       // starts just off the left edge
            Assert.Equal(glow.GlowMin, o0, 9);               // faint at the edges
            var (xm, om) = glow.Pose(glow.PeriodSeconds / 2);
            Assert.Equal(0, xm, 9);                          // mid-word at half the period
            Assert.Equal(glow.GlowMax, om, 9);               // brightest as it crosses the middle
            Assert.Equal(glow.Pose(0.3), glow.Pose(0.3 + glow.PeriodSeconds));   // periodic
            for (double t = 0; t < 10; t += 0.07)
            {
                var (x, o) = glow.Pose(t);
                Assert.InRange(x, -0.7, 0.7);
                Assert.InRange(o, glow.GlowMin - 1e-9, glow.GlowMax + 1e-9);
            }
            Assert.Equal((0, glow.GlowMax), glow.StaticPose);
        }
    }

    [Theory]
    [InlineData(false, false, true)]    // the user double-clicks JVoice.exe while it runs → Settings
    [InlineData(true, false, false)]    // the logon entry stepping aside: never pop Settings at login
    [InlineData(false, true, false)]    // our own elevated relaunch waiting for the handoff
    public void ASecondLaunch_OpensSettingsOnlyWhenTheUserLaunchedIt(bool autostart, bool relaunch, bool opens) =>
        Assert.Equal(opens, CoordinatorDecisions.SecondLaunchOpensSettings(autostart, relaunch));
}
