namespace JVoice.Core;

/// Pure frame-rate gate for the HUD's per-frame animation (HudView.OnRendering).
///
/// WPF's CompositionTarget.Rendering fires at the DISPLAY refresh rate while anything animates
/// — on a 240 Hz gaming monitor that is ~200+ layout+render passes per second for a pill whose
/// motion is indistinguishable above ~60 fps. Every pass re-measures 21 bars and re-composites the
/// layered window, all on the UI thread that also has to service the hotkey hop. Skipping frames
/// that arrive too soon keeps the same visual at a third of the cost (§7 #49).
public static class FramePacer
{
    /// Target minimum spacing between applied frames: 1/60 s, minus a hair so a display that
    /// ticks at exactly 60 Hz never alternates between applying and skipping.
    public const double MinFrameIntervalSeconds = 1.0 / 60.0 - 0.0005;

    /// True when a frame arriving at `nowSeconds` should be applied given the last applied frame
    /// at `lastAppliedSeconds` (negative = never applied yet → always apply).
    public static bool ShouldApply(double nowSeconds, double lastAppliedSeconds)
        => lastAppliedSeconds < 0 || nowSeconds - lastAppliedSeconds >= MinFrameIntervalSeconds;
}
