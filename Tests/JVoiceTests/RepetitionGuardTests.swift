#if canImport(Testing)
import Testing
@testable import JVoice

// The vocabulary from the real-world report (tariffs dictation that degenerated
// into a custom-word loop).
private let reportedVocab = ["sub agents", "claude", "li-fraumeni", "vs code"]

// MARK: - The reported bug

@Test func stripsTrailingVocabularyRegurgitationKeepingSpeech() {
    let input = """
    so basically what tariffs are is when governments put taxes on imported goods \
    and who pays them is the people buying the item from a country that is \
    sub agents, claude, li-fraumeni, sub agents, claude, vs code, li-fraumeni, \
    sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, \
    sub agents, li-fraumeni, sub agents, la-fa, li-fraumeni, sub agents, li-fraumeni
    """
    let out = RepetitionGuard.strip(input, vocabulary: reportedVocab)

    // The real speech survives…
    #expect(out.hasPrefix("so basically what tariffs are"))
    #expect(out.contains("country"))
    // …and the regurgitation is gone.
    #expect(!out.lowercased().contains("li-fraumeni"))
    #expect(!out.lowercased().contains("sub agents"))
    #expect(!out.contains(","))
    #expect(out.count < input.count / 2)
}

@Test func stripsLoopDegeneratingIntoTruncatedTokens() {
    // Real-world sample (2026-06-10, theme-settings dictation): the loop
    // interleaves whole vocabulary words, then degenerates into a truncated
    // "li-, li-, li-" run — the cores ("li") must still match the vocabulary.
    let speech = """
    oh these are actually all really good it's very hard to make a choice \
    maybe we could have like a theme settings in the app where you could \
    really just pick your theme that you wanted out of all these different \
    options and i also want you to add one that is it's just a minimalistic \
    one just pretty minimalistic
    """
    let loop = "sub agents, code, li-fraumeni, code, li-fraumeni, code, li-fraumeni, "
        + "code, li-fraumeni, code, li-fraumeni, sub agents, code, li-fraumeni, "
        + "code, li-fraumeni, code, "
        + Array(repeating: "li-,", count: 75).joined(separator: " ") + " li-."
    let r = RepetitionGuard.scrub(speech + " " + loop, vocabulary: reportedVocab)
    #expect(r.removedRegurgitation == true)
    #expect(r.text == speech)
}

@Test func wholeTranscriptIsLoopReducesToEmpty() {
    let input = "claude claude claude claude claude claude claude claude claude claude"
    #expect(RepetitionGuard.strip(input, vocabulary: ["claude"]) == "")
}

// MARK: - Generic (non-vocabulary) Whisper loops

@Test func stripsGenericRepetitionLoopWithoutVocabulary() {
    let input = "the meeting is tomorrow afternoon thanks thanks thanks thanks thanks thanks thanks thanks thanks"
    let out = RepetitionGuard.strip(input, vocabulary: [])
    #expect(out == "the meeting is tomorrow afternoon")
}

// MARK: - False-positive guards (legitimate custom-word use is preserved)

@Test func legitimateSingleVocabularyMentionUntouched() {
    let input = "I love using VS Code and Claude for my projects every single day at work"
    #expect(RepetitionGuard.strip(input, vocabulary: reportedVocab) == input)
}

@Test func denseButNonRepetitiveVocabularyUseUntouched() {
    // Several custom words, each said once — dense, but not a loop.
    let input = "today I paired Claude with VS Code and my sub agents to ship the feature"
    #expect(RepetitionGuard.strip(input, vocabulary: reportedVocab) == input)
}

@Test func ordinaryProseUntouched() {
    let input = "the quick brown fox jumps over the lazy dog and then runs back again to sleep"
    #expect(RepetitionGuard.strip(input, vocabulary: []) == input)
}

@Test func shortTextNeverStripped() {
    // Below the minimum-loop length: too risky to distinguish from real speech.
    #expect(RepetitionGuard.strip("sub agents claude", vocabulary: reportedVocab) == "sub agents claude")
}

@Test func emptyAndWhitespaceInputsAreSafe() {
    #expect(RepetitionGuard.strip("", vocabulary: reportedVocab) == "")
    #expect(RepetitionGuard.strip("hello world", vocabulary: reportedVocab) == "hello world")
}

// MARK: - Helpers

// MARK: - scrub: the re-decode trigger (removedRegurgitation flag)

@Test func scrubFlagsRemovedRegurgitation() {
    let input = "and that is the part sub agents claude li-fraumeni sub agents claude vs code li-fraumeni sub agents li-fraumeni sub agents li-fraumeni"
    let r = RepetitionGuard.scrub(input, vocabulary: reportedVocab)
    #expect(r.removedRegurgitation == true)
    #expect(!r.text.lowercased().contains("li-fraumeni"))
    #expect(r.text.hasPrefix("and that is the part"))
}

@Test func scrubDoesNotFlagCleanText() {
    let input = "today I paired Claude with VS Code and my sub agents to ship the feature on time"
    let r = RepetitionGuard.scrub(input, vocabulary: reportedVocab)
    #expect(r.removedRegurgitation == false)
    #expect(r.text == input)
}

@Test func scrubFlagsAllLoopAsEmpty() {
    let r = RepetitionGuard.scrub("claude claude claude claude claude claude claude claude claude", vocabulary: ["claude"])
    #expect(r.removedRegurgitation == true)
    #expect(r.text == "")
}

// MARK: - decoder-artifact stripping ([BLANK_AUDIO] etc.)

@Test func stripsDecoderArtifacts() {
    #expect(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world") == "hello world")
    #expect(TextProcessor.stripDecoderArtifacts("a [MUSIC] b [APPLAUSE] c") == "a b c")
    #expect(TextProcessor.stripDecoderArtifacts("[BLANK_AUDIO]") == "")
    #expect(TextProcessor.stripDecoderArtifacts("the quick brown fox") == "the quick brown fox")
    // Lowercase brackets are not decoder sentinels — left alone.
    #expect(TextProcessor.stripDecoderArtifacts("see [note] here") == "see [note] here")
}

@Test func vocabularyCoresSplitsSpokenParts() {
    let cores = RepetitionGuard.vocabularyCores(["sub agents", "VS Code", "li-fraumeni"])
    #expect(cores.contains("sub"))
    #expect(cores.contains("agents"))
    #expect(cores.contains("vs"))
    #expect(cores.contains("code"))
    #expect(cores.contains("fraumeni"))
    #expect(cores.contains("lifraumeni"))
}
#endif
