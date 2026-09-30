import Foundation

/// The decode-and-recover policy that contains the vocabulary prompt's failure
/// modes. Decode WITH the prompt (best custom-word accuracy); if that decode
/// shows a prompt failure, decode the SAME audio again WITHOUT the prompt — the
/// "witness" — and let it decide. At most one witness decode per call, and only
/// when something looks wrong, so the clean common case costs one decode.
///
/// Failure modes, each with its witness rule:
/// - regurgitation (a loop RepetitionGuard stripped) or an empty decode → the
///   witness replaces the decode (the original purpose of this type);
/// - a phrase loop ANYWHERE in the text (`PhraseLoopGuard`) → the witness,
///   collapsed (it carries the speech the loop overwrote);
/// - conspicuously little text for the audio (`SparseTranscriptGuard`, the
///   decoder silently skipping a stretch) → the witness when it carries ≥ 2×
///   the text;
/// - quiet audio that still produced text (`SilenceHallucinationGate`, the
///   decoder inventing words on hum/hiss/breath), or a short comma-separated
///   list of vocabulary words (`RepetitionGuard.isVocabularyList`) → kept
///   only if the witness shares a word with it, else "" (no speech).
///
/// Pulled out of `WhisperKitTranscriptionEngine` so the policy is pure and
/// testable without WhisperKit: it takes a `decode` closure parameterised by
/// whether to use the prompt. Used by the whole-file, streaming-chunk and
/// local-recovery paths. The defaults (`audioSeconds` 0, `peakRMS` +∞) disable
/// the density and quiet triggers.
public enum RegurgitationRecovery {
    /// Returns the checked transcript (possibly ""). `decode(usePrompt)` runs
    /// the real model; it is called once in the common (clean) case and a second
    /// time, with `usePrompt == false`, only when a failure mode shows.
    public static func decode(
        useVocabularyPrompt: Bool,
        vocabulary: [String],
        audioSeconds: Double = 0,
        peakRMS: Float = .infinity,
        log: (String) -> Void = { _ in },
        decode: (_ usePrompt: Bool) async throws -> String
    ) async rethrows -> String {
        let primary = RepetitionGuard.scrub(try await decode(useVocabularyPrompt), vocabulary: vocabulary)
        // No prompt ⇒ no prompt failure to witness; still never paste a loop.
        guard useVocabularyPrompt else { return PhraseLoopGuard.collapse(primary.text).text }
        if primary.removedRegurgitation || primary.text.isEmpty {
            // The prompt regurgitated. A prompt-free decode of the same audio
            // transcribes what was actually spoken (no vocabulary attractor → no
            // loop, no dropped speech).
            return PhraseLoopGuard.collapse(RepetitionGuard.scrub(try await decode(false), vocabulary: vocabulary).text).text
        }

        let text = primary.text
        let looped = PhraseLoopGuard.hasLoop(text)
        let sparse = SparseTranscriptGuard.shouldVerify(audioSeconds: audioSeconds, promptedTranscript: text)
        let quiet = SilenceHallucinationGate.shouldVerify(peakRMS: peakRMS, prompted: text)
        let listy = RepetitionGuard.isVocabularyList(text, vocabulary: vocabulary)
        guard looped || sparse || quiet || listy else { return text }

        let witness = RepetitionGuard.scrub(try await decode(false), vocabulary: vocabulary).text
        var result = text
        if looped {
            result = PhraseLoopGuard.resolve(looped: text, witness: witness)
        } else if sparse {
            result = SparseTranscriptGuard.resolve(promptedTranscript: text, unpromptedWitness: witness)
        }
        if quiet || listy {
            result = SilenceHallucinationGate.resolve(prompted: result, witness: witness, vocabulary: vocabulary)
        }
        let reasons = [looped ? "loop" : nil, sparse ? "sparse" : nil, quiet ? "quiet" : nil, listy ? "vocab" : nil].compactMap { $0 }.joined(separator: "+")
        let verdict = result.isEmpty ? "rejected (no speech)" : result == text ? "kept prompted" : "adopted witness"
        log("witness(\(reasons)) audio=\(String(format: "%.1f", audioSeconds))s peak=\(String(format: "%.3f", peakRMS)) chars prompted=\(text.count) witness=\(witness.count) → \(verdict)")
        return result
    }
}
