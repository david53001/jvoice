#if canImport(Testing)
import Testing
@testable import JVoice

@Test func emptyVocabularyProducesNoPrompt() {
    #expect(VocabularyPrompt.text(for: []) == nil)
    #expect(VocabularyPrompt.text(for: ["", "   "]) == nil)
}

@Test func wordsAreCommaJoinedWithLeadingSpace() {
    // The leading space matters: Whisper's BPE merges a leading space into
    // word tokens, so conditioning text must look like natural transcript.
    #expect(VocabularyPrompt.text(for: ["JVoice", "WhisperKit"]) == " JVoice, WhisperKit")
}

@Test func vocabularyIsCappedToBoundDecodeCost() {
    let words = (0..<100).map { "word\($0)" }
    let text = VocabularyPrompt.text(for: words)!
    #expect(text.contains("word\(VocabularyPrompt.maxWords - 1)"))
    #expect(!text.contains("word\(VocabularyPrompt.maxWords),") && !text.hasSuffix("word99"))
}
#endif
