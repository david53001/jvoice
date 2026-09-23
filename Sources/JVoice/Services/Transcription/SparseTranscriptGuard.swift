import Foundation

/// Catches a vocabulary-PROMPTED decode that silently SKIPPED whole stretches of
/// speech. Ported 1:1 from the Windows port's
/// `windows/JVoice.Core/Policy/SparseTranscriptGuard.cs` (HANDOFF-WINDOWS §7 #43).
///
/// The failure (Windows, real clip, 2026-07-20): a 32 s dictation decoded WITH the
/// prompt to only its head + tail — "Now next, Jesus appears to his disciples. not
/// forgiven. Amen." (61 chars ≈ 1.9 chars/s) — while the UNPROMPTED decode of the same
/// audio was complete (566 chars). Nothing else notices: it is not empty and has no
/// loop, so `RegurgitationRecovery` keeps it, and the streaming session pastes it.
/// Same prompt-failure class as `RegurgitationRecovery`, so the same remedy: a
/// suspicious decode triggers a WITNESS re-decode without the prompt, and the witness
/// decides.
///
/// It is a MODEL behavior (the decoder conditioned on `<|startofprev|> word, word, …`),
/// not a whisper.cpp one, so WhisperKit running the same large-v3-turbo weights with
/// the same prompt technique is exposed too. It needs no timestamps — text length over
/// audio length is available on every Mac decode path, including the no-timestamps
/// ≤ 25 s file path and the streaming chunks.
///
/// Measured on Windows (30 real clips, large-v3-turbo): every legitimate ≥ 10 s
/// dictation decoded at 8.9–17.8 chars/s and its unprompted witness stayed within ±10 %
/// of the prompted length; the failure measured 1.9 chars/s with a witness 9.3× richer.
/// Density is only the cheap TRIGGER — the replace decision is the model's own
/// unprompted decode (≥ 2× the text), so a terse decode is never rejected on
/// arithmetic alone. The constants are kept verbatim: chars per second is a property
/// of the speaker and the model, not of the engine. Re-calibrate from a Mac sweep
/// (prompted vs `--bench --no-prompt`) before tightening them.
public enum SparseTranscriptGuard {
    /// Clips shorter than this never trigger: terse-but-genuine transcripts all
    /// measured ≤ 8.1 s on Windows.
    public static let minAudioSeconds = 10.0

    /// Verify-trigger density: > 2× above the observed failure (1.9) and > 2× below
    /// the sparsest legitimate long clip (8.9).
    public static let sparseCharsPerSecond = 4.0

    /// The witness replaces the prompted text only when it carries at least this many
    /// times the characters (legitimate prompt/no-prompt drift measured ≤ 1.1×; the
    /// real skip's witness was 9.3×).
    public static let witnessAdoptFactor = 2

    /// True when a prompted transcript of `audioSeconds` of audio needs a witness
    /// decode: long enough to expect real density, yet conspicuously little text.
    /// Blank transcripts are the empty-decode path's business, not this guard's.
    public static func shouldVerify(audioSeconds: Double, promptedTranscript: String) -> Bool {
        !isBlank(promptedTranscript)
            && audioSeconds >= minAudioSeconds
            && Double(promptedTranscript.count) < sparseCharsPerSecond * audioSeconds
    }

    /// Decide from the WITNESS — the same audio decoded WITHOUT the prompt and cleaned
    /// the same way. A witness carrying ≥ `witnessAdoptFactor`× the text proves the
    /// prompted decode swallowed speech ⇒ the witness, wholesale. Otherwise the witness
    /// only vouches that the audio really was that terse ⇒ keep the vocabulary-accurate
    /// prompted text.
    public static func resolve(promptedTranscript: String, unpromptedWitness: String) -> String {
        guard !isBlank(unpromptedWitness),
              unpromptedWitness.count >= witnessAdoptFactor * promptedTranscript.count else {
            return promptedTranscript
        }
        return unpromptedWitness
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
