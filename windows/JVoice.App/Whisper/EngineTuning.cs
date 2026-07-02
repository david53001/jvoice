using JVoice.App.Platform;
using JVoice.Core;

namespace JVoice.App.Whisper;

/// Decode-time tuning knobs for the whisper engine. The bench overrides these per run to
/// measure; Default holds the committed app values adopted from the 2026-06-27 speed plan
/// (docs/superpowers/plans/2026-06-27-windows-whisper-speed.md + ...-results.md).
internal sealed record EngineTuning(
    bool UseFlashAttention,    // factory-level flash attention (WhisperFactoryOptions.UseFlashAttention)
    bool AdaptiveAudioContext, // size audio_ctx per clip via WhisperTuning (ignored if FixedAudioContext set)
    int? FixedAudioContext,    // non-null forces this audio_ctx (bench A/B only); null = use the policy/none
    int? Threads)              // null = leave whisper's default (min(4, logical)); else WithThreads(n)
{
    /// Committed app default. Measured + adopted on the RTX 3060 Ti / i5-12400 dev box:
    ///   • UseFlashAttention — ON for GPU builds: large-v3-turbo on Vulkan decoded ~30-37%
    ///     faster (e.g. 18.8 s clip 0.538 s → 0.360 s) with byte-identical transcripts. The
    ///     CPU flavor (JVOICE_CPU) keeps it OFF — flash degrades CPU decode (whisper.cpp PR #2152).
    ///   • Threads = physical core count — CPU decode of `base`/`tiny` got ~21% faster at 6 vs
    ///     the whisper default 4 (no further gain past physical cores); ~no effect on the GPU path.
    ///   • AdaptiveAudioContext — NOT adopted: measured non-monotonic (a 768-frame ctx REGRESSED
    ///     ~9 s clips 2-3× while 896-1280 helped), too fragile to default on. Lever kept for the
    ///     bench (--audio-ctx) but left off.
    public static EngineTuning Default { get; } = new(
#if JVOICE_CPU
        UseFlashAttention: false,
#else
        UseFlashAttention: true,
#endif
        AdaptiveAudioContext: false,
        FixedAudioContext: null,
        Threads: WhisperTuning.DecodeThreads(CpuInfo.PhysicalCoreCount));
}
