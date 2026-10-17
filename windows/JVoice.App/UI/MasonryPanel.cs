using System.Windows;
using System.Windows.Controls;
using JVoice.Core;

namespace JVoice.App.UI;

/// <summary>
/// The Settings cards' masonry layout (Mac <c>MasonryColumns</c>): the panel's real width picks the
/// column count (<see cref="MasonryLayout.ColumnCount"/>), every card is measured at the column width,
/// and each card, in order, drops into the currently shortest column — no holes at any width. WPF
/// re-runs Measure/Arrange on every size change, so the cards reflow live while the window edge is
/// dragged. Collapsed cards take no slot.
/// </summary>
public sealed class MasonryPanel : Panel
{
    private (int Column, double Top)[] _placed = [];
    private int _columns = 1;
    private double _columnWidth;

    /// <summary>Columns used by the last layout pass (renders + tests read it).</summary>
    public int Columns => _columns;

    protected override Size MeasureOverride(Size available)
    {
        double width = double.IsFinite(available.Width) ? available.Width : MasonryLayout.MaxContentWidth;
        _columns = MasonryLayout.ColumnCount(width);
        _columnWidth = MasonryLayout.ColumnWidth(width, _columns);

        var heights = new List<double>(InternalChildren.Count);
        foreach (UIElement child in InternalChildren)
        {
            if (child.Visibility == Visibility.Collapsed) { heights.Add(-1); continue; }
            child.Measure(new Size(_columnWidth, double.PositiveInfinity));
            heights.Add(child.DesiredSize.Height);
        }
        var visible = heights.Where(h => h >= 0).ToList();
        var placedVisible = MasonryLayout.Place(visible, _columns, out double total);

        _placed = new (int, double)[heights.Count];
        int v = 0;
        for (int i = 0; i < heights.Count; i++)
            _placed[i] = heights[i] < 0 ? (-1, 0) : placedVisible[v++];
        return new Size(width, total);
    }

    protected override Size ArrangeOverride(Size final)
    {
        // Arrange may hand us a different width than Measure did (a scrollbar appearing): recompute.
        double colWidth = MasonryLayout.ColumnWidth(final.Width, _columns);
        for (int i = 0; i < InternalChildren.Count; i++)
        {
            var child = InternalChildren[i];
            if (i >= _placed.Length || _placed[i].Column < 0) { child.Arrange(new Rect(0, 0, 0, 0)); continue; }
            var (column, top) = _placed[i];
            double x = column * (colWidth + MasonryLayout.Spacing);
            child.Arrange(new Rect(x, top, colWidth, child.DesiredSize.Height));
        }
        return final;
    }
}
