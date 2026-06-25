import Foundation

/// The decode-and-recover policy that contains the vocabulary prompt's failure
/// mode. Decode WITH the prompt (best custom-word accuracy); if that decode
/// regurgitated the prompt — a loop was removed, or it came back empty — decode
/// the SAME audio again WITHOUT the prompt and use that instead, recovering the
/// real speech the loop replaced.
///
/// Pulled out of `WhisperKitTranscriptionEngine` so the policy is pure and
/// testable without WhisperKit: it takes a `decode` closure parameterised by
/// whether to use the prompt. Used by both the whole-file and streaming-chunk
/// paths.
public enum RegurgitationRecovery {
    /// Returns the scrubbed transcript (possibly ""). `decode(usePrompt)` runs
    /// the real model; it is called once in the common (clean) case and a second
    /// time, with `usePrompt == false`, only when the prompted decode shows
    /// regurgitation.
    public static func decode(
        useVocabularyPrompt: Bool,
        vocabulary: [String],
        decode: (_ usePrompt: Bool) async throws -> String
    ) async rethrows -> String {
        let primary = RepetitionGuard.scrub(try await decode(useVocabularyPrompt), vocabulary: vocabulary)
        guard useVocabularyPrompt, primary.removedRegurgitation || primary.text.isEmpty else {
            return primary.text
        }
        // The prompt regurgitated. A prompt-free decode of the same audio
        // transcribes what was actually spoken (no vocabulary attractor → no
        // loop, no dropped speech).
        return RepetitionGuard.scrub(try await decode(false), vocabulary: vocabulary).text
    }
}
