#if canImport(Testing)
import Testing
@testable import JVoice

// Mirrors windows/JVoice.Tests/NonSpeechAnnotationTests.cs. A decode made only of
// Whisper captions is no-speech; a real sentence that merely CONTAINS a bracketed,
// parenthesised or asterisk pair keeps its text outside the group and is kept.

@Test(arguments: [
    "[BLANK_AUDIO]",
    "[Music]",
    "[Sigh]",
    "[Applause]",
    "[MUSIC]",
    "(wind blowing)",
    "(door closes)",
    "(speaking foreign language)",
    "  [BLANK_AUDIO]  ",
    "[Music] (applause)",          // several captions, nothing else
    "[Sigh].",                     // caption + lone punctuation
    "(...)",
    "*coughs*",                    // the asterisk form (Windows §7 #44)
    "*music*",
    "*soft music*.",
    "* sighs *",
    "*music* *applause*",
    "[BLANK_AUDIO] *music*",       // mixed delimiters, nothing else
])
func captionOnlyDecodeIsNoSpeech(_ raw: String) {
    #expect(NonSpeechAnnotation.isAnnotationOnly(raw))
    #expect(NonSpeechAnnotation.reduce(raw) == "")
}

@Test(arguments: [
    "you",                               // a real one-word reply
    "Please check the build again.",
    "Thanks.",                           // the stock-phrase blocklist's job, not this one's
    "music",                             // the word, not a caption
    "the (optional) flag",
    "Set the (optional) flag before you run it.",
    "I said (quietly) no.",
    "The index is [3] here.",
    "(side note) call the bank",
    "*emphasis* here",
    "I *really* like this idea.",
    "multiply 2 * 3 * 4",                // the pair is removed, the digits outside it stay
    "press the * key",                   // a lone asterisk never forms a group
])
func realSpeechWithBracketsOrAsterisksIsKept(_ raw: String) {
    #expect(!NonSpeechAnnotation.isAnnotationOnly(raw))
    #expect(NonSpeechAnnotation.reduce(raw) == raw)
}

@Test func emptyStringIsNotAnAnnotation() {
    // Emptiness is the caller's existing empty-transcript path.
    #expect(!NonSpeechAnnotation.isAnnotationOnly(""))
    #expect(NonSpeechAnnotation.reduce("") == "")
}

@Test func composesWithTheSentinelStripper() {
    // stripDecoderArtifacts removes the ALL-CAPS sentinel; the mixed-case caption
    // it leaves behind is what reduce catches.
    #expect(NonSpeechAnnotation.reduce(TextProcessor.stripDecoderArtifacts("[BLANK_AUDIO] [Sigh]")) == "")
    #expect(NonSpeechAnnotation.reduce(TextProcessor.stripDecoderArtifacts("ship it [BLANK_AUDIO] (maybe)")) == "ship it (maybe)")
}
#endif
