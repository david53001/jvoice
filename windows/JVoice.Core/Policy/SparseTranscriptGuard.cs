namespace JVoice.Core.Policy;

/// §7 #43 — the sparse-transcript guard (Windows-only; no macOS equivalent).
///
/// Failure mode (David-reported 2026-07-20, reproduced deterministically on the real clip
/// capture-20260720-231246-541.wav): on a 32 s dictation the vocabulary-PROMPTED whole-file
/// decode silently SKIPPED the middle ~25 s of speech — it emitted only the head + tail
/// ("Now next, Jesus appears to his disciples. not forgiven. Amen.", 61 chars ≈ 1.9 chars/s)
/// while its last segment ended near the audio end. Every existing guard is structurally
/// blind to this: no repetition loop (PhraseLoopGuard/RepetitionGuard), no uncovered tail
/// (TailCoverageGuard), and the clip is not near-silent (SilenceHallucinationGate). Same
/// prompt-failure class as RegurgitationRecovery/#38/#42, so the remedy follows the family
/// shape: a suspicious decode triggers a WITNESS re-decode without the prompt, and the
/// witness decides.
///
/// Measured discriminator (2026-07-20 sweep, 30 real capture clips, large-v3-turbo): every
/// legitimate ≥10 s dictation decoded at 8.9–17.8 chars/s, and its unprompted witness stayed
/// within ±10% of the prompted length; the failing decode measured 1.9 chars/s with a
/// witness 9.3× richer (566 vs 61 chars). Legitimately terse clips ("*sad music*",
/// 1.2 chars/s) were all SHORT (≤ 8.1 s) — and even when one triggers, its witness is
/// equally terse, so the prompted text is kept. Density is only the cheap TRIGGER; the
/// replace decision is always the model's own unprompted decode (≥2× the text), so a sparse
/// prompted decode is never rejected on arithmetic alone.
public static class SparseTranscriptGuard
{
    /// Clips shorter than this never trigger: terse-but-genuine transcripts ("*sad
    /// music*.", a short mumble) all measured ≤ 8.1 s, and near-silent short presses are
    /// SilenceHallucinationGate's territory.
    public const double MinAudioSeconds = 10.0;

    /// Verify-trigger density. Real dictation on every ≥10 s sweep clip measured
    /// 8.9–17.8 chars/s; the failing skip decode 1.9. 4.0 sits >2× above the observed
    /// failure and >2× below the sparsest legitimate clip.
    public const double SparseCharsPerSecond = 4.0;

    /// The witness replaces the prompted text only when it carries at least this many
    /// times the characters. Legitimate prompt/no-prompt wording drift measured ≤ 1.1×;
    /// the real skip's witness was 9.3×.
    public const int WitnessAdoptFactor = 2;

    /// True when the prompted whole-file transcript needs a witness decode: the audio is
    /// long enough to expect real density, yet the decode produced conspicuously little
    /// text. Blank transcripts need no verification — the engine's empty path already
    /// reports "No speech detected."
    public static bool ShouldVerify(double audioSeconds, string promptedTranscript)
        => !string.IsNullOrWhiteSpace(promptedTranscript)
           && audioSeconds >= MinAudioSeconds
           && promptedTranscript.Length < SparseCharsPerSecond * audioSeconds;

    /// Decide from the WITNESS — the same audio decoded WITHOUT the prompt, then fully
    /// reduced (NonSpeechAnnotation.Reduce + StripDecoderArtifacts +
    /// RemoveWhisperHallucinations). A witness carrying ≥ WitnessAdoptFactor× the text
    /// proves the prompted decode swallowed speech ⇒ adopt the witness wholesale (the
    /// PhraseLoopGuard position: the primary is known-lossy). Otherwise the witness merely
    /// vouches that the audio really was that terse ⇒ keep the vocab-accurate prompted text.
    public static string Resolve(string promptedTranscript, string unpromptedWitness)
        => !string.IsNullOrWhiteSpace(unpromptedWitness)
           && unpromptedWitness.Length >= (long)WitnessAdoptFactor * promptedTranscript.Length
            ? unpromptedWitness
            : promptedTranscript;
}
