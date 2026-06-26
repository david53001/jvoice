namespace JVoice.App.Whisper;

/// Decode-time tuning knobs for the whisper engine. The Default values reproduce the
/// pre-tuning behavior (no flash, full audio context, whisper's own thread default) so
/// existing call sites are unchanged; the bench overrides them per run to measure, and the
/// speed-plan tasks flip individual Default fields once a lever is measured to help.
internal sealed record EngineTuning(
    bool UseFlashAttention,    // factory-level flash attention (WhisperFactoryOptions.UseFlashAttention)
    bool AdaptiveAudioContext, // size audio_ctx per clip via WhisperTuning (ignored if FixedAudioContext set)
    int? FixedAudioContext,    // non-null forces this audio_ctx (bench A/B only); null = use the policy/none
    int? Threads)              // null = leave whisper's default (min(4, logical)); else WithThreads(n)
{
    /// The single committed app default. Speed-plan tasks edit THIS to adopt a measured win:
    ///   Task 4 → AdaptiveAudioContext: true
    ///   Task 5 → Threads: WhisperTuning.DecodeThreads(CpuInfo.PhysicalCoreCount)
    ///   Task 6 → UseFlashAttention: <measured winner on the GPU path>
    public static EngineTuning Default { get; } = new(
        UseFlashAttention: false,
        AdaptiveAudioContext: false,
        FixedAudioContext: null,
        Threads: null);
}
