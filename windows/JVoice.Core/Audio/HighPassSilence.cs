namespace JVoice.Core.Audio;

/// Silence detection that ignores low-frequency room hum (50/60 Hz mains + rumble).
///
/// Raw peak-RMS can't tell quiet speech apart from mains-hum room tone — on real hardware
/// they sit at the SAME level (~0.0044 RMS measured), so a raw-RMS gate must either reject
/// quiet speech ("No speech detected." on real words) or let whisper.cpp hallucinate a phrase
/// on silence ("you", "Thank you.", "(birds chirping)"). Speech, unlike hum, carries broadband
/// energy: a first-difference high-pass (y[i] = x[i] − x[i−1]; +6 dB/oct, ≈0 at DC) crushes the
/// 60/120 Hz hum to a few percent of its amplitude while keeping most speech energy. The peak
/// 0.3 s-window RMS of that high-passed signal separates the two cleanly (validated on
/// synthesized clips at equal raw level):
///   • mains-hum room tone   hpRMS ≈ 0.0007
///   • quiet speech          hpRMS ≈ 0.0023
///   • digital silence       hpRMS ≈ 0.0002
///   • normal speech         hpRMS ≈ 0.02–0.08
/// so a floor of <see cref="DefaultFloor"/> gates hum/silence and passes quiet speech, and is
/// far below normal speech (never regresses working dictation).
///
/// Windows-only: the macOS brain has no equivalent — this specifically guards whisper.cpp's
/// hallucinate-on-room-tone behavior. Used for the whole-file no-speech gate.
public static class HighPassSilence
{
    /// High-passed peak-window RMS below this ⇒ treat the recording as silence (no decode).
    /// Tuned so 50/60 Hz mains-hum room tone reads as silent while quiet speech does not.
    public const float DefaultFloor = 0.0012f;

    private const int WindowSamples = 4800; // 0.3 s @ 16 kHz, matching ChunkPlanner's window

    /// True when the recording carries no broadband (speech) energy above the floor.
    public static bool IsSilent(ReadOnlySpan<short> samples, float floor = DefaultFloor)
        => PeakHighPassRms(samples) < floor;

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
}
