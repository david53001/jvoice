#if canImport(Testing)
import Testing
@testable import JVoice

// MARK: - phoneticKey

@Test func phoneticKeyWorkedExamples() {
    #expect(PhoneticMatcher.phoneticKey(for: "jvoice") == "jfs")
    #expect(PhoneticMatcher.phoneticKey(for: "jayvoice") == "jfs")
    #expect(PhoneticMatcher.phoneticKey(for: "gvoice") == "jfs")
    #expect(PhoneticMatcher.phoneticKey(for: "whisperkit") == "wsprkt")
    #expect(PhoneticMatcher.phoneticKey(for: "whispercat") == "wsprkt")
    #expect(PhoneticMatcher.phoneticKey(for: "voice") == "fs")
}

@Test func phoneticKeyKeepsLeadingVowel() {
    #expect(PhoneticMatcher.phoneticKey(for: "appkit").first == "a")
}

// MARK: - levenshtein

@Test func levenshteinBasics() {
    #expect(PhoneticMatcher.levenshtein("jvoice", "jayvoice", limit: 3) == 2)
    #expect(PhoneticMatcher.levenshtein("same", "same", limit: 3) == 0)
    #expect(PhoneticMatcher.levenshtein("abc", "xyz", limit: 2) == 3) // early-exit cap = limit+1
}

// MARK: - correct: the cases the user actually hits

@Test func hearsSpelledOutName() {
    #expect(
        PhoneticMatcher.correct("open jay voice settings", vocabulary: ["JVoice"])
            == "open JVoice settings"
    )
}

@Test func hearsLetterGVariant() {
    #expect(
        PhoneticMatcher.correct("g voice is running", vocabulary: ["JVoice"])
            == "JVoice is running"
    )
}

@Test func hearsSoundalikeCompound() {
    #expect(
        PhoneticMatcher.correct("built with whisper cat", vocabulary: ["WhisperKit"])
            == "built with WhisperKit"
    )
}

@Test func preservesPunctuation() {
    #expect(
        PhoneticMatcher.correct("is jay voice, ready", vocabulary: ["JVoice"])
            == "is JVoice, ready"
    )
}

// MARK: - correct: false-positive guards

@Test func plainWordIsNotHijacked() {
    // "voice" alone must NOT become JVoice — initial sound differs (f vs j).
    #expect(
        PhoneticMatcher.correct("use your voice now", vocabulary: ["JVoice"])
            == "use your voice now"
    )
}

@Test func alreadyCorrectTextIsUntouched() {
    #expect(
        PhoneticMatcher.correct("JVoice is great", vocabulary: ["JVoice"])
            == "JVoice is great"
    )
}

@Test func multiTokenExactSpellingIsUntouched() {
    // A correctly-spelled multi-word entry must not be rewritten (a rewrite
    // would drop interior punctuation and churn the token list).
    #expect(
        PhoneticMatcher.correct("I use VS Code daily", vocabulary: ["VS Code"])
            == "I use VS Code daily"
    )
}

@Test func exactWordDoesNotSwallowFollowingWords() {
    // Regression: the 2-token window "JVoice is" → "jvoiceis" keys to "jfs"
    // (the trailing s collapses into the dedupe) and used to eat "is".
    // Smallest-window-first probing guards this.
    #expect(
        PhoneticMatcher.correct("JVoice is so fast", vocabulary: ["JVoice"])
            == "JVoice is so fast"
    )
}

@Test func emptyVocabularyIsNoop() {
    #expect(PhoneticMatcher.correct("hello there", vocabulary: []) == "hello there")
}

@Test func shortVocabularyWordsAreIgnored() {
    // <3 letters is too false-positive-prone to fuzzy-match.
    #expect(PhoneticMatcher.correct("ay bee sea", vocabulary: ["AB"]) == "ay bee sea")
}
#endif
