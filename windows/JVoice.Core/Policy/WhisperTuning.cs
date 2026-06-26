namespace JVoice.Core;

/// Pure, unit-tested tuning policies for the whisper decode path.
/// No Whisper.net / Win32 dependency — just arithmetic the App engine applies.
/// Windows-first (no macOS counterpart yet), like GameDetectionPolicy / DeveloperTerms.
public static class WhisperTuning
{
    public const int SampleRate = 16_000;
    /// whisper.cpp's full encoder window: 50 mel frames/sec * 30 s = 1500.
    public const int FullAudioContext = 1500;
    /// Maintainer floor — below this the encoder loses real context (whisper.cpp Discussion #297).
    /// 768 frames ≈ 15.4 s of audio, so it always covers a sub-13 s clip with headroom.
    public const int MinAudioContext = 768;

    /// Encoder context size for a clip of the given duration, or null to leave whisper's full
    /// default (used once the sized value would meet/exceed 1500 — reducing a long clip would
    /// risk truncating real speech, since whisper windows long audio into 30 s segments).
    /// Formula (whisper.cpp issue #1855): ctx = (seconds/30)*1500 + 128, rounded UP to a
    /// multiple of 64, clamped to [768, 1500]; null when that reaches the full window.
    public static int? AudioContextFor(double seconds)
    {
        if (double.IsNaN(seconds) || seconds <= 0) return MinAudioContext;
        double raw = seconds / 30.0 * FullAudioContext + 128.0;
        if (raw >= FullAudioContext) return null;                  // long clip → full context
        int rounded = (int)(System.Math.Ceiling(raw / 64.0) * 64); // multiples of 64
        rounded = System.Math.Clamp(rounded, MinAudioContext, FullAudioContext);
        return rounded >= FullAudioContext ? null : rounded;       // rounding hit the cap → full
    }

    /// Encoder context size from a raw mono 16 kHz sample count.
    public static int? AudioContextForSamples(int sampleCount)
        => AudioContextFor(sampleCount / (double)SampleRate);

    /// whisper.cpp decode threads: the physical core count is the sweet spot; going past it
    /// (into hyperthreads) adds contention without throughput (whisper.cpp Discussion #403).
    /// Clamped to a sane [1, 16]. Mainly helps the CPU-fallback build (whisper's default is
    /// only min(4, logical)); on the GPU path threads barely matter.
    public static int DecodeThreads(int physicalCores)
        => System.Math.Clamp(physicalCores, 1, 16);
}
