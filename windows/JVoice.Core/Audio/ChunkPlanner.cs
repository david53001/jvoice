namespace JVoice.Core.Audio;

/// Pure chunking policy for streaming transcription. Faithful port of ChunkPlanner.swift.
/// Cuts only at silence (words never split) until maxChunkSeconds forces one.
public static class ChunkPlanner
{
    public sealed class Config
    {
        public int SampleRate { get; init; } = 16_000;
        public double MinChunkSeconds { get; init; } = 15;
        public double MaxChunkSeconds { get; init; } = 25;
        public double SilenceWindowSeconds { get; init; } = 0.3;
        public float SilenceRmsFloor { get; init; } = 0.005f;
        public float RelativeSilenceFraction { get; init; } = 0.1f;
    }

    public enum DecisionKind { Wait, Cut }

    public readonly record struct Decision(DecisionKind Kind, int AtSample, bool IsSilent)
    {
        public static readonly Decision Wait = new(DecisionKind.Wait, 0, false);
        public static Decision Cut(int at, bool silent) => new(DecisionKind.Cut, at, silent);
    }

    public static Decision Plan(ReadOnlySpan<short> unconsumed, Config config)
    {
        int minSamples = (int)(config.MinChunkSeconds * config.SampleRate);
        int maxSamples = (int)(config.MaxChunkSeconds * config.SampleRate);
        int window = Math.Max(1, (int)(config.SilenceWindowSeconds * config.SampleRate));
        if (unconsumed.Length < minSamples) return Decision.Wait;

        int searchEnd = Math.Min(unconsumed.Length, maxSamples);
        var energies = WindowRms(unconsumed[..searchEnd], window);
        float peak = energies.Count == 0 ? 0 : energies.Max(e => e.Rms);
        float threshold = Math.Max(config.SilenceRmsFloor, peak * config.RelativeSilenceFraction);

        WindowEnergy? quietest = null;
        foreach (var e in energies)
        {
            if (e.Start < minSamples || e.Start + window > searchEnd) continue;
            if (quietest is null || e.Rms < quietest.Value.Rms) quietest = e;
        }

        if (quietest is { } q && q.Rms < threshold)
            return MakeCut(unconsumed, q.Start + window / 2, config);

        if (unconsumed.Length < maxSamples) return Decision.Wait;
        int at = quietest is { } q2 ? q2.Start + window / 2 : maxSamples;
        return MakeCut(unconsumed, at, config);
    }

    public static bool IsSilent(ReadOnlySpan<short> samples, Config config)
    {
        int window = Math.Max(1, (int)(config.SilenceWindowSeconds * config.SampleRate));
        var energies = WindowRms(samples, window);
        float peak = energies.Count == 0 ? 0 : energies.Max(e => e.Rms);
        return peak < config.SilenceRmsFloor;
    }

    /// How many samples at the END of `samples` are silence: walk back in `probeSeconds` windows and
    /// stop at the first whose RMS reaches the silence floor (Mac trailingSilenceSamples, parity §5.3).
    public static int TrailingSilenceSamples(ReadOnlySpan<short> samples, Config config, double probeSeconds = 0.1, float? floor = null)
    {
        int step = Math.Max(1, (int)(probeSeconds * config.SampleRate));
        float threshold = floor ?? config.SilenceRmsFloor;
        int end = samples.Length;
        while (end > 0)
        {
            int start = Math.Max(0, end - step);
            if (Rms(samples[start..end]) >= threshold) break;
            end = start;
        }
        return samples.Length - end;
    }

    /// WINDOWS DIVERGENCE (speculation only): the pause floor relative to this audio's own speech
    /// level — 15 % of its 90th-percentile 0.1 s window RMS, kept within [0.0004, SilenceRmsFloor].
    /// Measured on David's recent captures (2026-10-02): his speech's median window RMS is
    /// 0.001–0.003 and only 5–30 % of windows reach the absolute 0.005 floor, while his room reads
    /// ≈ 0.0000–0.0001 — so the absolute floor calls most of his speech a pause, and this doesn't.
    public static float AdaptivePauseFloor(ReadOnlySpan<short> samples, Config config, double probeSeconds = 0.1)
    {
        int step = Math.Max(1, (int)(probeSeconds * config.SampleRate));
        var rms = new List<float>();
        for (int i = 0; i < samples.Length; i += step)
            rms.Add(Rms(samples.Slice(i, Math.Min(step, samples.Length - i))));
        if (rms.Count == 0) return config.SilenceRmsFloor;
        rms.Sort();
        float p90 = rms[(int)(0.9 * (rms.Count - 1))];
        return Math.Clamp(0.15f * p90, 0.0004f, config.SilenceRmsFloor);
    }

    /// RMS of a span (16-bit PCM → −1…1).
    public static float Rms(ReadOnlySpan<short> samples)
    {
        if (samples.Length == 0) return 0;
        double sum = 0;
        foreach (short v in samples)
        {
            double f = v / 32768.0;
            sum += f * f;
        }
        return (float)Math.Sqrt(sum / samples.Length);
    }

    private static Decision MakeCut(ReadOnlySpan<short> unconsumed, int sample, Config config)
        => Decision.Cut(sample, IsSilent(unconsumed[..sample], config));

    internal readonly record struct WindowEnergy(int Start, float Rms);

    /// Non-overlapping RMS windows; the last (partial) window is included.
    /// `internal` (not `private`) to mirror Swift's testable `windowRMS`.
    internal static List<WindowEnergy> WindowRms(ReadOnlySpan<short> samples, int window)
    {
        var result = new List<WindowEnergy>();
        if (samples.Length == 0 || window <= 0) return result;
        int start = 0;
        while (start < samples.Length)
        {
            int end = Math.Min(start + window, samples.Length);
            double sum = 0;
            for (int i = start; i < end; i++)
            {
                double v = samples[i] / 32768.0;
                sum += v * v;
            }
            result.Add(new WindowEnergy(start, (float)Math.Sqrt(sum / (end - start))));
            start += window;
        }
        return result;
    }
}
