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

    private static Decision MakeCut(ReadOnlySpan<short> unconsumed, int sample, Config config)
        => Decision.Cut(sample, IsSilent(unconsumed[..sample], config));

    private readonly record struct WindowEnergy(int Start, float Rms);

    /// Non-overlapping RMS windows; the last (partial) window is included.
    private static List<WindowEnergy> WindowRms(ReadOnlySpan<short> samples, int window)
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
