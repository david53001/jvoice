using JVoice.Core;

namespace JVoice.App.Platform;

/// How big the HUD pill is drawn on THIS display: the same share of the screen as on the Mac.
///
/// The pill's geometry is the Mac's (240 × 56 capsule, HUDLayout.swift), designed on a MacBook Air
/// 13" (1470 × 956 pt). This scales it uniformly so it covers the same fraction of the primary screen's
/// area here (<see cref="ScreenPlacement.PillScale"/>), measured in DIPs so Windows display scaling is
/// already accounted for.
///
/// It replaces the old "stretch ratio" (nativeWidth / currentWidth): at David's 1500 × 1080 desktop on a
/// 1920 × 1080 panel that gave 1.28×, a 307 × 72 capsule taking 20.5 % of the screen's width against the
/// Mac's 16.3 % — "too big". Area fractions in DIPs are physical area fractions whatever the monitor's
/// scaler does, so no separate stretch correction is needed; legibility under the scaler comes from the
/// Ideal text formatting in HudView.xaml.
public static class DisplayMetrics
{
    // Display metrics are effectively constant for a tray app's session, and the pill is
    // shown on the hot path (the instant the hotkey fires), so compute once and cache —
    // a mid-session resolution change won't re-scale the pill until the next launch.
    private static readonly Lazy<double> _hudScale = new(Compute);

    /// Uniform LayoutTransform scale for the HUD pill on the primary display.
    public static double HudScale => _hudScale.Value;

    private static double Compute()
    {
        try
        {
            // DIPs of the primary screen (full bounds, like the Mac's NSScreen frame).
            return ScreenPlacement.PillScale(System.Windows.SystemParameters.PrimaryScreenWidth,
                                             System.Windows.SystemParameters.PrimaryScreenHeight);
        }
        catch
        {
            return 1.0; // the Mac's own size
        }
    }
}
