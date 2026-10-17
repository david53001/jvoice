namespace JVoice.Core;

/// <summary>
/// The Settings window's card layout (Mac <c>MasonryColumns</c> in SettingsView.swift): the window's
/// real width picks the column count, and each card, IN ORDER, drops into whichever column is
/// currently shortest — so no column keeps a hole at any width. Pure so it is unit-tested;
/// <c>JVoice.App/UI/MasonryPanel</c> is the WPF panel that applies it on every layout pass (live
/// while the user drags the window edge).
/// </summary>
public static class MasonryLayout
{
    /// <summary>Gap between columns and between cards in a column (DIP).</summary>
    public const double Spacing = 12;

    /// <summary>Content wider than this stops growing and is centred (Mac: 1400 pt) — a maximized
    /// window on a wide monitor keeps readable card widths instead of four 600-px stripes.</summary>
    public const double MaxContentWidth = 1440;

    /// <summary>Column-count thresholds on the CONTENT width (inside the window's 20-DIP margins):
    /// 3 columns from 900 (≈ 292 DIP each — the width every card has had since HANDOFF §7 #33) and 4
    /// from 1360 (≈ 331 each). Below 900, 2 columns; below 560 (only reachable inside a tiny host), 1.</summary>
    public const double TwoColumnsFrom = 560;
    public const double ThreeColumnsFrom = 900;
    public const double FourColumnsFrom = 1360;

    public static int ColumnCount(double contentWidth) =>
        !double.IsFinite(contentWidth) ? 3
        : contentWidth >= FourColumnsFrom ? 4
        : contentWidth >= ThreeColumnsFrom ? 3
        : contentWidth >= TwoColumnsFrom ? 2
        : 1;

    public static double ColumnWidth(double contentWidth, int columns) =>
        Math.Max(0, (contentWidth - Spacing * (columns - 1)) / columns);

    /// <summary>Where each card goes: its column and its top, in order. A tie picks the leftmost
    /// column, so a fresh layout fills left to right like reading order.</summary>
    public static IReadOnlyList<(int Column, double Top)> Place(IReadOnlyList<double> heights, int columns,
        out double totalHeight)
    {
        columns = Math.Max(1, columns);
        var bottoms = new double[columns];
        var placed = new List<(int, double)>(heights.Count);
        foreach (double h in heights)
        {
            int shortest = 0;
            for (int c = 1; c < columns; c++)
                if (bottoms[c] < bottoms[shortest] - 0.5) shortest = c;   // 0.5 DIP: ignore rounding noise
            double top = bottoms[shortest] == 0 ? 0 : bottoms[shortest] + Spacing;
            placed.Add((shortest, top));
            bottoms[shortest] = top + Math.Max(0, h);
        }
        totalHeight = bottoms.Max();
        return placed;
    }
}
