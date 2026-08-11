namespace JVoice.Core;

/// Sample-level statistics of one captured recording. `NonZeroSamples` counts samples
/// whose 16-bit PCM value is not exactly 0.
public readonly record struct CaptureSignalStats(long TotalSamples, long NonZeroSamples, double Seconds)
{
    public double NonZeroRatio => TotalSamples > 0 ? (double)NonZeroSamples / TotalSamples : 0d;
}

/// Distinguishes "the selected microphone delivered no signal at all" (a dead/muted/virtual
/// input endpoint) from "the user spoke quietly". Exists so a dead input is reported as a
/// DEVICE problem instead of the misleading "No speech detected.", which blames the user's
/// voice and made the 2026-08-11 Voicemod-virtual-mic outage very hard to diagnose (§7 #46).
///
/// **This is NOT an RMS / amplitude gate** — the retired RMS pre-gate (§7 #21) rejected David's
/// real quiet dictation and must never come back. The discriminator here is *exact zero*
/// samples, which is categorically different:
///
///   * A real microphone always carries a dither/noise floor. Measured on this machine, the
///     Yeti Classic sitting IDLE in a quiet room reports 283,584 non-zero of 285,120 samples
///     (99.46%) at peak 0.045 — nowhere near the threshold below.
///   * A dead endpoint (app-less virtual mic, muted device, level 0) returns *bit-exact* zeros:
///     0 of 1,224,640 samples non-zero across a 76 s recording. There is no overlap.
///
/// It is also **fail-safe by construction**: the caller only consults it once the transcript has
/// already come back empty, so this can only ever change the wording of an error the user was
/// going to see anyway. It can never reject audio or suppress a transcript.
public static class SilentCaptureDetector
{
    /// Recordings shorter than this aren't judged — a very short clip can legitimately be
    /// all-zero (e.g. the mic hardware hasn't ramped up yet on the first few frames).
    public const double MinSecondsToJudge = 0.35;

    /// At or below this fraction of non-zero samples the endpoint is considered dead. Set far
    /// above the observed dead-device value (exactly 0.0) and far below a real idle mic's noise
    /// floor (~0.99), so neither side is anywhere near the boundary.
    public const double MaxNonZeroRatio = 0.0005;

    /// True when the capture endpoint produced digital silence rather than quiet audio.
    public static bool IsDeadInput(CaptureSignalStats stats)
    {
        if (stats.TotalSamples <= 0) return false;          // nothing measured — don't guess
        if (stats.Seconds < MinSecondsToJudge) return false; // too short to judge fairly
        return stats.NonZeroRatio <= MaxNonZeroRatio;
    }

    /// The user-facing error for a dead input. Names the device so the fix is obvious
    /// (the whole point: "No speech detected." pointed the user at their own voice).
    public static string DeadInputMessage(string? deviceName)
    {
        string name = string.IsNullOrWhiteSpace(deviceName) ? "Your microphone" : $"\"{deviceName}\"";
        return $"{name} is not sending any audio. Pick a different microphone in JVoice Settings, " +
               "or check that it isn't muted.";
    }
}
