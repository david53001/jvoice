import Foundation

/// Detects Whisper's NON-SPEECH ANNOTATION output: on audio with no speech the
/// model often writes a caption instead of words — "[Music]", "[Sigh]",
/// "(birds chirping)", "*coughs*". A transcript made ENTIRELY of such groups is
/// no-speech at any capture level.
///
/// Ported 1:1 from the Windows port (`windows/JVoice.Core/Text/NonSpeechAnnotation.cs`,
/// docs/HANDOFF-WINDOWS.md §7 #21 and #44). The captions come from the model's
/// training data, not the runtime, and WhisperKit 1.0.0 does not suppress the
/// "[", "(" and "*" tokens (`DecodingOptions.suppressTokens` defaults to `[]`), so
/// the same shapes reach the macOS decode.
///
/// `TextProcessor.stripDecoderArtifacts` only removes ALL-CAPS sentinel tokens
/// ("[BLANK_AUDIO]", "[MUSIC]"), so the mixed-case ("[Music]"), parenthesised
/// ("(wind blowing)") and asterisk ("*sighs*") forms survive it — those are
/// what this catches. It deliberately works on the WHOLE transcript only: a real
/// sentence that merely contains a group ("the (optional) flag") keeps its text
/// outside the group, is not an annotation, and is returned untouched.
public enum NonSpeechAnnotation {
    /// One bracketed [...], parenthesised (...) or asterisk-delimited *...* group
    /// (non-greedy, no nesting — Whisper's captions never nest). A lone dictated
    /// asterisk ("press the * key") never forms a group: it needs a closing one.
    private static let annotationGroup = try? NSRegularExpression(pattern: #"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*"#)

    /// True when `text` is non-empty but, once every annotation group is removed,
    /// contains no letter or number — the whole transcript is a caption (and/or
    /// lone punctuation). False for "": emptiness is the caller's existing
    /// empty-transcript path, and "" is not itself an annotation.
    public static func isAnnotationOnly(_ text: String) -> Bool {
        guard !text.isEmpty, let annotationGroup else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = annotationGroup.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        return !stripped.contains { $0.isLetter || $0.isNumber }
    }

    /// "" when `text` is a caption-only decode (see `isAnnotationOnly`), otherwise
    /// `text` unchanged — so a caption-only decode reads as an empty transcript.
    public static func reduce(_ text: String) -> String {
        isAnnotationOnly(text) ? "" : text
    }
}
