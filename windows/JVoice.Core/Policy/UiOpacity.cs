namespace JVoice.Core;

/// Settings → Appearance → **Opacity** (parity row 30; shared spec with MacStats/BetterScreenshot,
/// `docs/mac-reference/design-language/opacity-setting.md`): one 0…1 value for every translucent
/// surface. 0 = as see-through as each surface may go, 0.5 = the designed default, 1 = solid. Each
/// surface is its backdrop plus a BACKING of the surface's own colour at <see cref="BackingAlpha"/>,
/// piecewise-linear 0 → 0.5 → 1.
///
/// The ratios are the contract, the alphas are calibration (spec §9.4): primary text ≥ 4.5:1 at the
/// default and ≥ 3:1 at 0. The window anchors are the Mac's (Settings/Welcome sit on Mica, which is
/// effectively opaque). The pill anchors are RAISED for Windows: the pill is a layered window with no
/// blur behind it, so over a white page the backing alone carries the contrast — the Mac's 0.45/0.62
/// would give white text 2.9:1 at 0. Raised again to 0.70/0.88 after David's dogfood (2026-10-02: "the pill is too
/// transparent" at the default): the pill reads as a solid dark capsule with only a hint of what's behind it.
public static class UiOpacity
{
    public const double Default = 0.5;

    public enum Surface
    {
        /// Settings, Welcome and the tour tag (a Mica backdrop behind the backing).
        Window,
        /// The floating dictation pill (no backdrop blur on Windows).
        Pill,
    }

    /// The backing alpha at 0 / 0.5 / 1.
    public static (double Transparent, double Standard, double Opaque) Anchors(Surface surface) => surface switch
    {
        Surface.Pill => (0.70, 0.88, 1.0),
        _ => (0.0, 0.35, 1.0),
    };

    /// The backing's alpha for <paramref name="value"/> on <paramref name="surface"/>.
    public static double BackingAlpha(double value, Surface surface)
    {
        var (t, m, o) = Anchors(surface);
        double v = Clamp(value);
        return v <= 0.5 ? t + (m - t) * (v / 0.5) : m + (o - m) * ((v - 0.5) / 0.5);
    }

    /// Any stored value into 0…1; a non-finite one reads as the default.
    public static double Clamp(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : Default;

    /// The pill's backing colour (sRGB, always dark — the pill keeps a dark appearance like the Mac's).
    public static readonly (byte R, byte G, byte B) PillColor = (0x1E, 0x1E, 0x1E);

    /// WCAG relative luminance of an sRGB colour.
    public static double Luminance(double r, double g, double b)
    {
        static double Lin(double c) { c /= 255.0; return c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); }
        return 0.2126 * Lin(r) + 0.7152 * Lin(g) + 0.0722 * Lin(b);
    }

    /// WCAG contrast ratio of two luminances.
    public static double Contrast(double l1, double l2)
    {
        double hi = Math.Max(l1, l2), lo = Math.Min(l1, l2);
        return (hi + 0.05) / (lo + 0.05);
    }

    /// White (primary) text over the pill at <paramref name="value"/>, composited over a page of grey
    /// level <paramref name="page"/> (255 = white, the worst case).
    public static double PillTextContrast(double value, double page = 255, double textAlpha = 1)
    {
        double a = BackingAlpha(value, Surface.Pill);
        double Mix(double c) => a * c + (1 - a) * page;
        double br = Mix(PillColor.R), bg = Mix(PillColor.G), bb = Mix(PillColor.B);
        double tr = textAlpha * 255 + (1 - textAlpha) * br, tg = textAlpha * 255 + (1 - textAlpha) * bg,
            tb = textAlpha * 255 + (1 - textAlpha) * bb;
        return Contrast(Luminance(tr, tg, tb), Luminance(br, bg, bb));
    }
}
