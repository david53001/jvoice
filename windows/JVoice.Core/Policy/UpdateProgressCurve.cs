namespace JVoice.Core.Policy;

/// The "marketing" progress curve for the in-app update download bar (David, 2026-07-01):
/// the bar must NOT show the raw byte percentage — it is eased so it *feels* fast and smooth.
/// Windows-only feature; pure math so it is unit-locked (UpdateProgressCurveTests).
///
/// Two shaping rules, both deliberate perceived-performance tricks:
///  1. <see cref="FromFraction"/> — an ease-OUT over the real download fraction: it runs ahead of
///     the true byte count early (feels quick to start) and decelerates toward the end. It is
///     capped at <see cref="Ceiling"/> so the bar sits just shy of full while bytes finish; the
///     UI snaps to a full bar only once the download is actually <c>done</c>.
///  2. <see cref="FromElapsed"/> — a time-based asymptotic crawl for when the server sends no
///     Content-Length (total unknown): the bar still creeps forward and decelerates, so it never
///     looks stuck at 0.
/// <see cref="Display"/> chooses between them and forces a full bar when done.
public static class UpdateProgressCurve
{
    /// The bar never fills past this until the download is genuinely finished (then it snaps to 1).
    public const double Ceiling = 0.95;

    /// Ease-out exponent (&gt; 1 ⇒ fast start, slow finish). 1.8 feels lively without lying wildly.
    public const double EaseExponent = 1.8;

    /// Time constant (seconds) of the unknown-total crawl — ~63% of the ceiling by this many seconds.
    public const double TimeTauSeconds = 8.0;

    /// Ease-out of a real download fraction (0..1) → displayed fraction (0..<see cref="Ceiling"/>).
    public static double FromFraction(double realFraction)
    {
        double r = Clamp01(realFraction);
        double eased = 1.0 - Math.Pow(1.0 - r, EaseExponent);
        return Math.Min(Ceiling, eased);
    }

    /// Unknown-total crawl: an asymptotic approach to <see cref="Ceiling"/> that always advances
    /// with elapsed time and decelerates, so the bar is never frozen at zero on a length-less stream.
    public static double FromElapsed(double elapsedSeconds)
    {
        if (elapsedSeconds <= 0) return 0.0;
        return Ceiling * (1.0 - Math.Exp(-elapsedSeconds / TimeTauSeconds));
    }

    /// The displayed fraction the bar should target:
    ///  - <paramref name="done"/> ⇒ 1.0 (the only time the bar is full);
    ///  - known <paramref name="totalBytes"/> ⇒ eased real fraction;
    ///  - unknown total ⇒ time-based crawl.
    public static double Display(long receivedBytes, long? totalBytes, double elapsedSeconds, bool done)
    {
        if (done) return 1.0;
        if (totalBytes is > 0) return FromFraction((double)receivedBytes / totalBytes.Value);
        return FromElapsed(elapsedSeconds);
    }

    private static double Clamp01(double x) => x < 0 ? 0 : x > 1 ? 1 : x;
}
