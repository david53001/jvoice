using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the §7 #43 sparse-transcript guard (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported 2026-07-20, reproduced deterministically on the real clip
/// capture-20260720-231246-541.wav): on a 32 s Bible-study dictation the vocabulary-PROMPTED
/// whole-file decode silently SKIPPED the middle ~25 s — it emitted only the head + tail
/// ("Now next, Jesus appears to his disciples. not forgiven. Amen.", 61 chars ≈ 1.9 chars/s)
/// while ending near the audio end, so every existing guard was blind: no loop
/// (PhraseLoopGuard), no repetition (RepetitionGuard), no uncovered tail (TailCoverageGuard),
/// and the clip was not near-silent (SilenceHallucinationGate). The UNPROMPTED decode of the
/// same audio was complete (566 chars ≈ 17.6 chars/s).
///
/// Measured discriminator (2026-07-20 sweep, 30 real capture clips, large-v3-turbo): every
/// legitimate ≥10 s dictation decoded at 8.9–17.8 chars/s and its witness stayed within
/// ±10% of the prompted length; only the failing decode was sparse (1.9 chars/s) with a
/// witness 9.3× richer. Legitimately terse clips ("*sad music*", 1.2 chars/s) were all
/// SHORT (≤ 8.1 s) with an equally terse witness. So: sparseness on long audio only
/// TRIGGERS a witness decode; the witness is adopted only when it carries ≥2× the text.
public class SparseTranscriptGuardTests
{
    // The real failure, verbatim: 32.11 s of audio → 61 prompted chars.
    private const string RealSparsePrompted =
        "Now next, Jesus appears to his disciples. not forgiven. Amen.";
    private const double RealSparseSeconds = 32.11;
    // The witness that recovered the full paragraph (566 chars) — length-representative stub.
    private static readonly string RealWitness = new string('w', 566);

    // ---- constants (calibrated against the 2026-07-20 sweep; change = recalibrate) ----

    [Fact]
    public void Constants_AreLocked()
    {
        Assert.Equal(10.0, SparseTranscriptGuard.MinAudioSeconds);
        Assert.Equal(4.0, SparseTranscriptGuard.SparseCharsPerSecond);
        Assert.Equal(2, SparseTranscriptGuard.WitnessAdoptFactor);
    }

    // ---- ShouldVerify: the real failure triggers ----

    [Fact]
    public void ShouldVerify_RealSparseDecode_Triggers()
        => Assert.True(SparseTranscriptGuard.ShouldVerify(RealSparseSeconds, RealSparsePrompted));

    // ---- ShouldVerify: every legitimate sweep shape stays quiet ----

    [Theory]
    [InlineData(62.58, 555)]  // the sparsest legit long clip measured (8.87 chars/s)
    [InlineData(12.49, 148)]  // normal dictation density
    [InlineData(97.10, 1255)] // the Caesar clip after healing
    [InlineData(32.62, 438)]  // his re-dictation of the swallowed paragraph
    public void ShouldVerify_NormalDensity_DoesNotTrigger(double seconds, int chars)
        => Assert.False(SparseTranscriptGuard.ShouldVerify(seconds, new string('x', chars)));

    [Theory]
    [InlineData(8.12, 10)] // "*sad music*." — legitimately terse, but SHORT
    [InlineData(3.97, 11)] // short mumble
    [InlineData(9.99, 5)]  // just under the audio floor
    public void ShouldVerify_ShortClips_NeverTrigger(double seconds, int chars)
        => Assert.False(SparseTranscriptGuard.ShouldVerify(seconds, new string('x', chars)));

    [Fact] // Blank transcripts are the engine's no-speech path, not this guard's.
    public void ShouldVerify_BlankTranscript_DoesNotTrigger()
    {
        Assert.False(SparseTranscriptGuard.ShouldVerify(30.0, ""));
        Assert.False(SparseTranscriptGuard.ShouldVerify(30.0, "   "));
    }

    // ---- ShouldVerify: exact boundaries ----

    [Fact]
    public void ShouldVerify_Boundaries()
    {
        // At exactly the audio floor, sparseness triggers; just below it never does.
        Assert.True(SparseTranscriptGuard.ShouldVerify(10.0, new string('x', 39)));
        // chars == SparseCharsPerSecond * seconds is NOT sparse (strict <).
        Assert.False(SparseTranscriptGuard.ShouldVerify(10.0, new string('x', 40)));
    }

    [Fact] // Degenerate durations must never trigger a pointless witness decode.
    public void ShouldVerify_NonFiniteOrZeroSeconds_DoesNotTrigger()
    {
        Assert.False(SparseTranscriptGuard.ShouldVerify(0.0, "hi"));
        Assert.False(SparseTranscriptGuard.ShouldVerify(double.NaN, "hi"));
    }

    // ---- Resolve: the real failure adopts the witness ----

    [Fact]
    public void Resolve_RealFailure_AdoptsWitness()
        => Assert.Same(RealWitness, SparseTranscriptGuard.Resolve(RealSparsePrompted, RealWitness));

    // ---- Resolve: a comparable witness vouches, the prompted text is kept ----

    [Theory]
    [InlineData(61)]  // identical length (every legit sweep clip: ratio ≤ 1.1×)
    [InlineData(66)]  // +10% — normal prompt/no-prompt wording drift
    [InlineData(121)] // just under 2×
    public void Resolve_ComparableWitness_KeepsPrompted(int witnessChars)
        => Assert.Same(RealSparsePrompted,
            SparseTranscriptGuard.Resolve(RealSparsePrompted, new string('w', witnessChars)));

    [Fact] // Exactly 2× is enough: the witness carries double the speech.
    public void Resolve_ExactlyDoubleWitness_AdoptsWitness()
    {
        string witness = new string('w', 122);
        Assert.Same(witness, SparseTranscriptGuard.Resolve(RealSparsePrompted, witness));
    }

    [Theory] // An empty/blank witness can never replace real prompted text.
    [InlineData("")]
    [InlineData("   ")]
    public void Resolve_BlankWitness_KeepsPrompted(string witness)
        => Assert.Same(RealSparsePrompted,
            SparseTranscriptGuard.Resolve(RealSparsePrompted, witness));
}
