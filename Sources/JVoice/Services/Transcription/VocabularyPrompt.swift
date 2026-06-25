import Foundation

/// Builds the decoder-conditioning prompt from the user's custom words.
///
/// Whisper conditions its decoder on "previous transcript" text. Feeding the
/// custom vocabulary as that text (OpenAI's `initial_prompt` technique) makes
/// the model strongly prefer those spellings when the audio sounds like them —
/// fixing recognition at the source instead of patching it afterwards.
public enum VocabularyPrompt {
    /// Cap on words included — keeps the decoder prefill cheap; prompt tokens
    /// linearly increase per-window decode cost.
    public static let maxWords = 40
    /// Hard cap on encoded tokens, well under WhisperKit's own
    /// `maxTokenContext/2 - 1` (~111) trim.
    public static let maxPromptTokens = 96

    /// The conditioning text, or nil when there is nothing to bias toward.
    public static func text(for words: [String]) -> String? {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        // The leading space matters: Whisper's BPE merges a leading space into
        // word tokens, so conditioning text must look like natural transcript.
        return " " + cleaned.prefix(maxWords).joined(separator: ", ")
    }
}
