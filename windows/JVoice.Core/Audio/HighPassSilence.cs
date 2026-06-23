namespace JVoice.Core.Audio;

/// No-speech gate that tells a person speaking apart from room tone / mains hum / silence.
///
/// whisper.cpp hallucinates a short phrase on near-silent audio ("you", "Thank you.",
/// "you're welcome.", "(birds chirping)") that the fixed text blocklist can't reliably
/// strip, so a recording with no speech must be stopped before it reaches the decoder.
/// But LEVEL alone can't make that call: on real hardware faint room tone and a person's
/// quiet/short speech sit at the SAME low RMS, so a raw-RMS floor either rejects quiet
/// speech ("No speech detected." on real words) or passes hum (hallucination). The
/// discriminator is SPECTRAL, not level: speech carries broadband energy; hum/rumble is
/// low-frequency. A first-difference high-pass (y[i] = x[i] − x[i−1]; +6 dB/oct, ≈0 at DC)
/// crushes 60/120 Hz hum to a few percent of its amplitude while keeping speech, so the
/// peak 0.3 s-window RMS of the high-passed signal is the primary measure.
///
/// Decision (two regimes):
///   • hpRMS ≥ <see cref="SpeechFloor"/>  → unambiguous broadband energy: speech. Passes
///     UNCONDITIONALLY. This is exactly the old single-threshold gate's pass set, so
///     working dictation (which always reads here) is never touched.
///   • hpRMS &lt; SpeechFloor            → ambiguous low-energy zone. Below
///     <see cref="HardFloor"/> there is essentially no signal at all (digital silence /
///     pure hum) → silent. Otherwise decide by SPECTRAL CHARACTER — the ratio of
///     high-passed to raw energy: speech stays broadband even when quiet, hum/rumble does
///     not. ratio ≥ <see cref="SpeechRatioFloor"/> ⇒ speech, below ⇒ silent.
///
/// Why this exists / why the constants: the original gate used one absolute hpRMS floor
/// (0.0012) tuned on synthesized `say` clips. On David's real mic (RTX 3060 Ti / i5-12400,
/// measured 2026-06-23) his genuine short/quiet dictation reads FAR lower than the
/// synthesized clips predicted, so that floor rejected real speech as "No speech detected."
/// Measured anchors (hpRMS / rawRMS / ratio) that lock this policy — see HighPassSilenceTests:
///   • 60 Hz hum @ room tone      0.0001 / 0.0044 / 0.02  → silent (hard floor)
///   • short accidental taps      0.0002 / 0.0017 / 0.12  → silent (low ratio)
///                                0.0003 / 0.0027 / 0.11  → silent (low ratio)
///   • real quiet dictation       0.0006 / 0.0014 / 0.43  → speech (ratio ≥ floor)
///                                0.0009 / 0.0017 / 0.53  → speech (ratio ≥ floor)
///   • normal speech              0.02–0.08 / …           → speech (≥ SpeechFloor)
///
/// Monotonic by construction: the gate now reports silent for a strict SUBSET of what the
/// old hpRMS &lt; 0.0012 gate did (it only ever lets MORE through in the ambiguous zone),
/// so it can only REDUCE false "No speech detected" rejections, never add one.
///
/// Windows-only: the macOS brain has no equivalent — this specifically guards whisper.cpp's
/// hallucinate-on-room-tone behavior. Used for the whole-file no-speech gate.
public static class HighPassSilence
{
    /// High-passed peak-window RMS at/above this is unambiguous broadband (speech) energy:
    /// never gated. This is the original single-threshold floor, kept verbatim so working
    /// dictation behavior is unchanged.
    public const float SpeechFloor = 0.0012f;

    /// High-passed peak-window RMS below this is essentially no signal at all (digital
    /// silence / pure low-frequency hum): silent regardless of spectral ratio (and it keeps
    /// the ratio test away from a divide-by-near-zero raw level).
    public const float HardFloor = 0.0002f;

    /// In the ambiguous zone [<see cref="HardFloor"/>, <see cref="SpeechFloor"/>), the
    /// high-passed energy must be at least this fraction of the raw energy to count as
    /// speech. Separates broadband speech (ratio ≈ 0.3–0.6 measured) from low-frequency
    /// hum/rumble (ratio ≈ 0.02–0.12 measured); the gap between them is wide.
    public const float SpeechRatioFloor = 0.20f;

    /// Back-compat alias for the primary floor (older diagnostics/tests referenced this name).
    public const float DefaultFloor = SpeechFloor;

    private const int WindowSamples = 4800; // 0.3 s @ 16 kHz, matching ChunkPlanner's window

    /// True when the recording carries no broadband (speech) energy — i.e. it is digital
    /// silence, mains hum, or low-frequency room rumble rather than a person speaking.
    public static bool IsSilent(ReadOnlySpan<short> samples)
        => IsSilent(PeakHighPassRms(samples), PeakWindowRms(samples));

    /// The gate decision from the two peak-window metrics (high-passed and raw). Exposed so
    /// the real-mic anchor points can lock the policy directly (and so the engine can log the
    /// metrics it already computed without recomputing them). See the class remarks.
    public static bool IsSilent(float peakHighPassRms, float peakRawRms)
    {
        if (peakHighPassRms < HardFloor) return true;     // no signal / pure hum
        if (peakHighPassRms >= SpeechFloor) return false; // clearly broadband → speech
        if (peakRawRms <= 0f) return true;                // guard the ratio
        return peakHighPassRms / peakRawRms < SpeechRatioFloor; // low ratio = hum/rumble
    }

    /// Peak 0.3 s-window RMS (0..1) of the first-difference (high-passed) signal.
    public static float PeakHighPassRms(ReadOnlySpan<short> samples)
    {
        if (samples.Length < 2) return 0f;
        float peak = 0f;
        double sum = 0;
        int count = 0;
        double prev = samples[0] / 32768.0;
        for (int i = 1; i < samples.Length; i++)
        {
            double cur = samples[i] / 32768.0;
            double d = cur - prev;
            prev = cur;
            sum += d * d;
            if (++count == WindowSamples || i == samples.Length - 1)
            {
                float rms = (float)Math.Sqrt(sum / count);
                if (rms > peak) peak = rms;
                sum = 0;
                count = 0;
            }
        }
        return peak;
    }

    /// Peak 0.3 s-window RMS (0..1) of the raw signal — the same metric ChunkPlanner's
    /// silence gate uses, paired with <see cref="PeakHighPassRms"/> for the spectral ratio.
    public static float PeakWindowRms(ReadOnlySpan<short> samples)
    {
        float peak = 0f;
        for (int start = 0; start < samples.Length; start += WindowSamples)
        {
            int end = Math.Min(start + WindowSamples, samples.Length);
            double sum = 0;
            for (int i = start; i < end; i++) { double v = samples[i] / 32768.0; sum += v * v; }
            float rms = (float)Math.Sqrt(sum / Math.Max(1, end - start));
            if (rms > peak) peak = rms;
        }
        return peak;
    }
}
