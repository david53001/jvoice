namespace JVoice.Core.Tours;

/// <summary>A screen rectangle in DIPs, y-down (WPF).</summary>
public readonly record struct TagRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double CenterX => X + Width / 2;
    public double CenterY => Y + Height / 2;
    public bool IsEmpty => Width <= 0 || Height <= 0;
    public TagRect Inflate(double d) => new(X - d, Y - d, Width + 2 * d, Height + 2 * d);
    public bool Contains(TagRect r) => r.X >= X - 1e-6 && r.Y >= Y - 1e-6 && r.Right <= Right + 1e-6 && r.Bottom <= Bottom + 1e-6;

    public TagRect Intersect(TagRect o)
    {
        double x = Math.Max(X, o.X), y = Math.Max(Y, o.Y), r = Math.Min(Right, o.Right), b = Math.Min(Bottom, o.Bottom);
        return r > x && b > y ? new TagRect(x, y, r - x, b - y) : new TagRect(x, y, 0, 0);
    }

    public TagRect Union(TagRect o)
    {
        double x = Math.Min(X, o.X), y = Math.Min(Y, o.Y);
        return new TagRect(x, y, Math.Max(Right, o.Right) - x, Math.Max(Bottom, o.Bottom) - y);
    }

    public bool Intersects(TagRect o) => !Intersect(o).IsEmpty;
}

public readonly record struct TagPoint(double X, double Y);

public enum TagSide { Left, Right, Below, Above, InsideCorner, Over }

/// <summary>The tag's frame, which side it took, the outline box, and the leader line (none inside / over).</summary>
public sealed record TagPlacementResult(TagRect Tag, TagSide Side, TagRect Box, (TagPoint From, TagPoint To)? Leader);

/// <summary>Inputs for <see cref="TagLayout.Place"/>.</summary>
public sealed record TagLayoutInput(
    TagRect Control,
    double TagWidth,
    double TagHeight,
    TagRect WorkArea,
    TagRect? Host = null,
    TagRect? KeepOut = null,
    bool VerticalFirst = false,
    TagPlacement Placement = TagPlacement.Automatic);

/// <summary>
/// Where the tour tag goes (Mac <c>TagLayout.place</c>, y-down; shared with BetterScreenshot's port): the step's placement if it fits; a big
/// control (≥ 60 % of its window both ways) gets the tag beside the window or inside its top-right corner; else
/// the sides in order (left, right, below, above — vertical first for bars and title-bar controls), outside the
/// keep-out then just outside the box; nothing fits → over the box's top-left corner.
/// </summary>
public static class TagLayout
{
    public const double BoxGrow = 4;
    public const double Gap = 24;
    public const double ScreenInset = 8;
    public const double CornerInset = 16;
    public const double BigFraction = 0.6;

    public static TagPlacementResult Place(TagLayoutInput input)
    {
        var box = input.Control.Inflate(BoxGrow);
        var area = input.WorkArea.Inflate(-ScreenInset);
        var sides = input.VerticalFirst
            ? new[] { TagSide.Below, TagSide.Above, TagSide.Left, TagSide.Right }
            : new[] { TagSide.Left, TagSide.Right, TagSide.Below, TagSide.Above };
        var keepOut = input.KeepOut ?? box;

        TagPlacementResult? Try(TagSide side, TagRect avoid)
        {
            if (Fit(side, avoid, box, input, area) is not { } tag) return null;
            return new TagPlacementResult(tag, side, box, Leader(tag, side, box));
        }

        TagPlacementResult? Corner()
        {
            var region = input.Control.Intersect(area);
            if (input.Host is { } h) region = region.Intersect(h);
            if (region.Width < input.TagWidth + 2 * CornerInset || region.Height < input.TagHeight + 2 * CornerInset) return null;
            var tag = new TagRect(Math.Round(region.Right - CornerInset - input.TagWidth), Math.Round(region.Y + CornerInset), input.TagWidth, input.TagHeight);
            return new TagPlacementResult(tag, TagSide.InsideCorner, box, null);
        }

        // A. The step's own placement.
        if (input.Placement != TagPlacement.Automatic)
        {
            var forced = input.Placement switch
            {
                TagPlacement.InsideCorner => Corner(),
                _ => Try(ToSide(input.Placement), keepOut) ?? Try(ToSide(input.Placement), box),
            };
            if (forced is not null) return forced;
        }

        // B. Big control: beside the whole window, else inside its corner — never "beside the control".
        if (input.Host is { } host && IsBig(input.Control, host))
        {
            var whole = host.Union(keepOut);
            foreach (var s in sides) if (Try(s, whole) is { } r) return r;
            if (Corner() is { } c) return c;
        }

        // D. Sides outside the keep-out, then just outside the box.
        foreach (var s in sides) if (Try(s, keepOut) is { } r) return r;
        foreach (var s in sides) if (Try(s, box) is { } r) return r;

        // E. Over the box's top-left corner.
        double ox = Math.Clamp(box.X + 12, area.X, Math.Max(area.X, area.Right - input.TagWidth));
        double oy = Math.Clamp(box.Y + 12, area.Y, Math.Max(area.Y, area.Bottom - input.TagHeight));
        return new TagPlacementResult(new TagRect(Math.Round(ox), Math.Round(oy), input.TagWidth, input.TagHeight), TagSide.Over, box, null);
    }

    /// <summary>What's visible of the control spans ≥ 60 % of the host's width and height.</summary>
    public static bool IsBig(TagRect control, TagRect host)
    {
        var v = control.Intersect(host);
        return !v.IsEmpty && v.Width >= BigFraction * host.Width && v.Height >= BigFraction * host.Height;
    }

    private static TagSide ToSide(TagPlacement p) => p switch
    {
        TagPlacement.Left => TagSide.Left,
        TagPlacement.Right => TagSide.Right,
        TagPlacement.Above => TagSide.Above,
        _ => TagSide.Below,
    };

    /// <summary>24 beyond <paramref name="avoid"/> on that side, centred on the box, slid into the area (and the host's
    /// extent when it fits there); fits when inside the area and still overlapping the box's span.</summary>
    private static TagRect? Fit(TagSide side, TagRect avoid, TagRect box, TagLayoutInput input, TagRect area)
    {
        double w = input.TagWidth, h = input.TagHeight;
        double x, y;
        bool horizontal = side is TagSide.Left or TagSide.Right;
        if (horizontal)
        {
            x = side == TagSide.Left ? avoid.X - Gap - w : avoid.Right + Gap;
            y = box.CenterY - h / 2;
            y = Slide(y, h, area.Y, area.Bottom, input.Host is { } host && host.Height >= h ? (host.Y, host.Bottom) : null);
        }
        else
        {
            y = side == TagSide.Above ? avoid.Y - Gap - h : avoid.Bottom + Gap;
            x = box.CenterX - w / 2;
            x = Slide(x, w, area.X, area.Right, input.Host is { } host && host.Width >= w ? (host.X, host.Right) : null);
        }
        var tag = new TagRect(Math.Round(x), Math.Round(y), w, h);
        if (!area.Contains(tag)) return null;
        bool overlaps = horizontal ? tag.Y < box.Bottom && tag.Bottom > box.Y : tag.X < box.Right && tag.Right > box.X;
        return overlaps ? tag : null;
    }

    private static double Slide(double v, double size, double lo, double hi, (double Lo, double Hi)? within)
    {
        if (within is { } w)
        {
            lo = Math.Max(lo, w.Lo);
            hi = Math.Min(hi, w.Hi);
        }
        if (hi - lo < size) return v;
        return Math.Clamp(v, lo, hi - size);
    }

    /// <summary>Straight across where the tag's side overlaps the box's (ends ≥ 12 from the tag's corners, ≥ 6 from the
    /// box's), nearest the box's middle; a diagonal when the tag had to slide off the box's span.</summary>
    public static (TagPoint From, TagPoint To) Leader(TagRect tag, TagSide side, TagRect box)
    {
        var outer = box.Inflate(2);
        if (side is TagSide.Left or TagSide.Right)
        {
            double lo = Math.Max(tag.Y + 12, outer.Y + 6), hi = Math.Min(tag.Bottom - 12, outer.Bottom - 6);
            double tx = side == TagSide.Left ? tag.Right : tag.X, bx = side == TagSide.Left ? outer.X : outer.Right;
            if (hi >= lo)
            {
                double y = Math.Clamp(outer.CenterY, lo, hi);
                return (new TagPoint(tx, y), new TagPoint(bx, y));
            }
            return (new TagPoint(tx, Math.Clamp(outer.CenterY, tag.Y + 12, tag.Bottom - 12)), new TagPoint(bx, Math.Clamp(tag.CenterY, outer.Y + 6, outer.Bottom - 6)));
        }
        else
        {
            double lo = Math.Max(tag.X + 12, outer.X + 6), hi = Math.Min(tag.Right - 12, outer.Right - 6);
            double ty = side == TagSide.Above ? tag.Bottom : tag.Y, by = side == TagSide.Above ? outer.Y : outer.Bottom;
            if (hi >= lo)
            {
                double x = Math.Clamp(outer.CenterX, lo, hi);
                return (new TagPoint(x, ty), new TagPoint(x, by));
            }
            return (new TagPoint(Math.Clamp(outer.CenterX, tag.X + 12, tag.Right - 12), ty), new TagPoint(Math.Clamp(tag.CenterX, outer.X + 6, outer.Right - 6), by));
        }
    }
}

public enum TagKey { Enter, Escape, Other }
public enum TagKeyAction { None, Next, SkipTour }

/// <summary>Return/Enter = Next on Explain steps, Esc = Skip Tour; everything passes through with modifiers, auto-repeat,
/// an editable focused control, the done state, or while the host claims the key (Mac <c>TagKeys</c>).</summary>
public static class TagKeys
{
    public static TagKeyAction Action(TagKey key, bool modifiers, bool isRepeat, bool focusedEditable, bool isExplainStep,
        bool doneState, bool hostClaimsEscape = false, bool hostClaimsKeys = false)
    {
        if (modifiers || isRepeat || focusedEditable || doneState || hostClaimsKeys) return TagKeyAction.None;
        return key switch
        {
            TagKey.Enter when isExplainStep => TagKeyAction.Next,
            TagKey.Escape when !hostClaimsEscape => TagKeyAction.SkipTour,
            _ => TagKeyAction.None,
        };
    }
}

/// <summary>The tag's look numbers (Mac <c>TagStyle</c>): one place, so overlay + lint agree.</summary>
public static class TagStyle
{
    /// <summary>Gap between the control and the outline's inner edge.</summary>
    public const double BoxPadding = TagLayout.BoxGrow;
    /// <summary>Corner radius of the outline's inner edge for a control that declares no shape.</summary>
    public const double BoxRadius = 6;
    public const double OutlineWidth = 1.5;
    public const double LeaderWidth = 1.5;
    public const double TagRadius = 12;
    public const double TagMinWidth = 200;
    public const double TagMaxWidth = 260;
    public const double TagPaddingX = 12;
    public const double TitleSize = 13;
    public const double BodySize = 12;
    public const int BodyMaxLines = 2;
    /// <summary>Black at this alpha over the rest of a light host, and over a dark one (20 % barely shows there).</summary>
    public const double DimAlpha = 0.2;
    public const double DarkHostDimAlpha = 0.35;

    public static double DimAlphaFor(bool hostIsDark) => hostIsDark ? DarkHostDimAlpha : DimAlpha;

    /// <summary>
    /// The outline's inner-edge corner radius (Mac <c>TagLayout.boxRadius</c>): <see cref="BoxRadius"/>, or for a control
    /// that declares its own radius (the capsule pill) that radius + the padding — a concentric outline — never more
    /// than half the box's short side.
    /// </summary>
    public static double OutlineRadius(TagRect box, double? anchorRadius) =>
        anchorRadius is not { } r ? BoxRadius : Math.Max(0, Math.Min(r + BoxPadding, Math.Min(box.Width / 2, box.Height / 2)));

    /// <summary>"Skip Tour" is left out next to the last Explain step's "Done" (same result, one click), and on a
    /// one-step tour, where "Skip Step" already ends it (review round 1 JV #9).</summary>
    public static bool ShowsSkipTour(bool isLast, bool isExplain, int total = 2) => total > 1 && !(isExplain && isLast);

    /// <summary>Joins each "+" of a shortcut chord of up to three keys to its keys with WORD JOINERs (U+2060), so a
    /// tag body never breaks "Ctrl+Shift+Space" across lines (review round 1 JV #8). A longer chord
    /// ("Ctrl+Alt+Shift+Win+F12") may still wrap — kept whole it would push the body to a third line.</summary>
    public static string KeepChordsTogether(string body) =>
        System.Text.RegularExpressions.Regex.Replace(body, @"(?<![\w+])\w+(?:\+\w+)+(?![\w+])",
            m => m.Value.Count(c => c == '+') <= 2 ? m.Value.Replace("+", $"{WordJoiner}+{WordJoiner}") : m.Value);

    private const char WordJoiner = (char)0x2060;

    public static string PrimaryTitle(bool isTry, bool isLast) => isTry ? "Skip Step" : isLast ? "Done" : "Next";

    public static string Counter(int number, int total) => $"{number} of {total}";

    public static string Announcement(string title, string body, int number, int total) => $"{title}. {body} Step {number} of {total}.";
}
