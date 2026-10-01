namespace JVoice.Core.Tours;

/// <summary>
/// The Opacity tour step's demo motion (Mac <c>OpacityDemoTimeline.swift</c>, ported exactly), as a pure function of
/// time: from the user's value down to 0, a pause, up to 1, a pause, back to the user's value, a longer pause, then
/// again (~9.5 s loop). Every move eases in and out (smoothstep), so the thumb visibly slows into each end.
/// </summary>
public static class OpacityDemoTimeline
{
    /// <summary>The Settings tour step that plays the demo (the Appearance card).</summary>
    public const string Anchor = "settings.appearance";

    public readonly record struct Frame(double Value, string Readout);

    /// <summary>(target, seconds to get there, seconds to hold it); a null target = back to the start value.</summary>
    private static readonly (double? Target, double Move, double Hold)[] Legs =
    {
        (0, 2.0, 0.9),     // fade to Transparent
        (1, 2.6, 0.9),     // rise to Opaque
        (null, 1.3, 1.8),  // back to the user's value
    };

    public static double LoopDuration => Legs.Sum(l => l.Move + l.Hold);

    public static Frame FrameAt(double time, double start)
    {
        start = UiOpacity.Clamp(start);
        double t = Math.Max(0, time) % LoopDuration;
        double from = start;
        foreach (var leg in Legs)
        {
            double to = leg.Target ?? start;
            if (t < leg.Move)
            {
                double p = t / leg.Move;
                double eased = p * p * (3 - 2 * p);
                double value = from + (to - from) * eased;
                string arrow = to < from ? " ↓" : to > from ? " ↑" : "";
                return new Frame(value, $"Watch: {Percent(value)} %{arrow}");
            }
            t -= leg.Move;
            if (t < leg.Hold) return new Frame(to, HoldReadout(to, isYours: leg.Target is null));
            t -= leg.Hold;
            from = to;
        }
        return new Frame(start, HoldReadout(start, isYours: true));
    }

    /// <summary>Swift's <c>(x * 100).rounded()</c> — half away from zero.</summary>
    public static int Percent(double value) => (int)Math.Round(UiOpacity.Clamp(value) * 100, MidpointRounding.AwayFromZero);

    private static string HoldReadout(double value, bool isYours) =>
        isYours ? $"Yours: {Percent(value)} %" : value <= 0 ? "Watch: 0 % Transparent" : "Watch: 100 % Opaque";
}
