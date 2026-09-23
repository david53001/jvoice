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

@Test func leadingPunctuationVocabIsNotDoubled() {
    // TRX-01: ".NET" splits into leading "." + core "NET"; the bare core
    // fuzzy-matches the entry, and the replacement used to re-prepend the
    // entry's own "." → "..NET". A token that already reads exactly as the
    // vocab word (punctuation included) must be left alone.
    #expect(
        PhoneticMatcher.correct("use dot .NET daily", vocabulary: [".NET"])
            == "use dot .NET daily"
    )
}

// MARK: - 2026-09-23: never swallow a neighbour, tighter fuzz, possessives

@Test func multiTokenWindowNeverSwallowsTheWordBefore() {
    // The word matched on its own, so the token in front is not part of it.
    #expect(PhoneticMatcher.correct("I deployed 2 Vercel apps today.", vocabulary: ["Vercel"])
        == "I deployed 2 Vercel apps today.")
    #expect(PhoneticMatcher.correct("Spawn six sub agents", vocabulary: ["sub agents"]) == "Spawn six sub agents")
    #expect(PhoneticMatcher.correct("$20 Vercel", vocabulary: ["Vercel"]) == "$20 Vercel")
    #expect(PhoneticMatcher.correct("The power of Ollama", vocabulary: ["Ollama"]) == "The power of Ollama")
    #expect(PhoneticMatcher.correct("We scheduled a AISB meeting", vocabulary: ["AISB"]) == "We scheduled a AISB meeting")
    // A misspelling after a short word is still corrected — without eating the word.
    #expect(PhoneticMatcher.correct("run it on olama", vocabulary: ["Ollama"]) == "run it on Ollama")
}

@Test func windowNeverJoinsAcrossClausePunctuation() {
    #expect(PhoneticMatcher.correct("Hey Jay, voice memos are great", vocabulary: ["JVoice"])
        == "Hey Jay, voice memos are great")
    #expect(PhoneticMatcher.correct("Jay's voice was hoarse", vocabulary: ["JVoice"]) == "Jay's voice was hoarse")
    // An initial's period is not a clause break.
    #expect(PhoneticMatcher.correct("I use J. Voice daily", vocabulary: ["JVoice"]) == "I use JVoice daily")
}

@Test func twoEditsWithADifferentSoundIsADifferentWord() {
    for word in ["verse", "verbal", "versed", "vessel"] {
        #expect(PhoneticMatcher.correct("the \(word) here", vocabulary: ["Vercel"]) == "the \(word) here")
    }
    #expect(PhoneticMatcher.correct("Obama gave a speech", vocabulary: ["Ollama"]) == "Obama gave a speech")
    #expect(PhoneticMatcher.correct("Such agents are rare", vocabulary: ["sub agents"]) == "Such agents are rare")
    // One-edit mishearings still correct.
    #expect(PhoneticMatcher.correct("deploy to versel", vocabulary: ["Vercel"]) == "deploy to Vercel")
}

@Test func singularAndShortWordRunsAreNotCustomWords() {
    #expect(PhoneticMatcher.correct("spawn a sub agent", vocabulary: ["sub agents"]) == "spawn a sub agent")
    #expect(PhoneticMatcher.correct("if a is b then swap", vocabulary: ["AISB"]) == "if a is b then swap")
}

@Test func possessiveSurvivesCorrection() {
    #expect(PhoneticMatcher.correct("I like Vercel's dashboard", vocabulary: ["Vercel"]) == "I like Vercel's dashboard")
    #expect(PhoneticMatcher.correct("Ollama's API is local", vocabulary: ["Ollama"]) == "Ollama's API is local")
    #expect(PhoneticMatcher.correct("Vercel’s pricing", vocabulary: ["Vercel"]) == "Vercel’s pricing")
    #expect(PhoneticMatcher.correct("versel's dashboard", vocabulary: ["Vercel"]) == "Vercel's dashboard")
}

@Test func replacementDoesNotDoubleTheWordsOwnPunctuation() {
    #expect(PhoneticMatcher.correct("use .nett daily", vocabulary: [".NET"]) == "use .NET daily")
}
#endif
