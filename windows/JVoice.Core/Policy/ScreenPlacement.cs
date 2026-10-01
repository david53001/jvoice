namespace JVoice.Core;

/// <summary>A rectangle in physical pixels (a monitor's work area as Win32 reports it).</summary>
public readonly record struct PxRect(int Left, int Top, int Right, int Bottom)
{
    public int Width => Right - Left;
    public int Height => Bottom - Top;
    public bool Contains(int x, int y) => x >= Left && x < Right && y >= Top && y < Bottom;
}

/// <summary>
/// Where JVoice's windows appear (parity row 34, doc §11; Mac a45598e <c>ActiveScreen</c>): Settings and the Welcome
/// window centre on the monitor with the mouse pointer each time they open from hidden; the pill appears bottom-centre
/// on that monitor, 64 above its taskbar edge, and keeps it while up (a morph never jumps monitors). Pure maths in
/// physical pixels, with the target monitor's DPI scale, so the caller can place a window before showing it.
/// </summary>
public static class ScreenPlacement
{
    /// <summary>The capsule's gap above the bottom of the work area (Mac HUDLayout.bottomGap), in DIPs.</summary>
    public const double PillBottomGap = 64;

    /// <summary>The top-left (px) that centres a <paramref name="widthDip"/> × <paramref name="heightDip"/> window in
    /// <paramref name="work"/> at <paramref name="scale"/>; a window taller/wider than the work area keeps its top-left
    /// corner (title bar, close button) inside it.</summary>
    public static (int X, int Y) Center(PxRect work, double widthDip, double heightDip, double scale)
    {
        double w = widthDip * scale, h = heightDip * scale;
        double x = work.Left + (work.Width - w) / 2;
        double y = work.Top + (work.Height - h) / 2;
        x = Math.Max(work.Left, Math.Min(x, work.Right - w));
        y = Math.Max(work.Top, Math.Min(y, work.Bottom - h));
        return ((int)Math.Round(Math.Max(x, work.Left)), (int)Math.Round(Math.Max(y, work.Top)));
    }

    /// <summary>The pill window's top-left (px): centred horizontally, its capsule <see cref="PillBottomGap"/> above the
    /// work area's bottom. <paramref name="heightDip"/> includes the <paramref name="shadowMarginDip"/> below the capsule.</summary>
    public static (int X, int Y) Pill(PxRect work, double widthDip, double heightDip, double shadowMarginDip, double scale)
    {
        double x = work.Left + (work.Width - widthDip * scale) / 2;
        double y = work.Bottom - (heightDip - shadowMarginDip + PillBottomGap) * scale;
        return ((int)Math.Round(x), (int)Math.Round(y));
    }
}
