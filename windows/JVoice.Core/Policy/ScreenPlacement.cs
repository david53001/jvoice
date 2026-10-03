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

    /// <summary>The Mac reference screen the pill was designed on: a MacBook Air 13" at its default 1470 × 956 pt,
    /// where the 240 × 56 capsule takes ~16 % of the width (Mac HUDLayout.swift).</summary>
    public const double MacScreenWidth = 1470, MacScreenHeight = 956;
    public const double MinPillScale = 0.85, MaxPillScale = 1.8;

    /// <summary>The pill's uniform scale so it takes the SAME share of the screen's area as on the Mac:
    /// √(screen area / Mac screen area), from the screen in DIPs. Area, not width, so a 16:9 or a stretched non-native
    /// desktop (1500 × 1080 on a 1920 × 1080 panel) gets the Mac's proportion too — DIP area fractions are physical
    /// area fractions whatever the monitor's scaler does. Clamped so tiny/huge screens stay sane; no screen → 1.</summary>
    public static double PillScale(double screenWidthDip, double screenHeightDip)
    {
        if (screenWidthDip <= 0 || screenHeightDip <= 0) return 1.0;
        double scale = Math.Sqrt(screenWidthDip * screenHeightDip / (MacScreenWidth * MacScreenHeight));
        return Math.Clamp(scale, MinPillScale, MaxPillScale);
    }

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
