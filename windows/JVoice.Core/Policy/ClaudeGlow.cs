namespace JVoice.Core;

/// <summary>
/// The "Claude is working" glow (Mac <c>UI/Components/ClaudeGlowText.swift</c>): a Claude-orange
/// (#D97757) highlight sweeps through the letters while a soft orange glow breathes behind them. Two
/// strengths share one control (<c>JVoice.App/UI/ClaudeGlowText</c>): <see cref="Full"/> on the
/// "AI refining" pill, <see cref="Subtle"/> on the AI Polish card's title. Pure so the numbers and the
/// pose are tested; values are the Mac's (WINDOWS-HANDOFF §9.4).
/// </summary>
public sealed record ClaudeGlow(double PeriodSeconds, double GlowMin, double GlowMax, double BlurRadius)
{
    /// <summary>Claude orange, #D97757.</summary>
    public const byte R = 0xD9, G = 0x77, B = 0x57;

    /// <summary>The pill: 1.6 s per sweep, glow opacity 0.2–0.7, blur radius 6.</summary>
    public static readonly ClaudeGlow Full = new(1.6, 0.20, 0.70, 6);

    /// <summary>The card title: slower and fainter — 3.2 s, 0.12–0.35, blur radius 4.</summary>
    public static readonly ClaudeGlow Subtle = new(3.2, 0.12, 0.35, 4);

    /// <summary>The band's horizontal offset in the text's own width (−0.7 = just off the left edge,
    /// +0.7 = just off the right) and the glow's opacity at <paramref name="seconds"/>. The glow peaks
    /// as the band crosses the middle of the word.</summary>
    public (double SweepX, double GlowOpacity) Pose(double seconds)
    {
        double phase = (seconds % PeriodSeconds + PeriodSeconds) % PeriodSeconds / PeriodSeconds;
        double sweep = -0.7 + 1.4 * phase;
        double breath = 0.5 - 0.5 * Math.Cos(2 * Math.PI * phase);   // 0 at the edges, 1 mid-sweep
        return (sweep, GlowMin + (GlowMax - GlowMin) * breath);
    }

    /// <summary>The still pose (screenshots, Windows animations turned off): band mid-word, glow full.</summary>
    public (double SweepX, double GlowOpacity) StaticPose => (0, GlowMax);
}
