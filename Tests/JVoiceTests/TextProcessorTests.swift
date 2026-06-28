#if canImport(Testing)
import Testing
@testable import JVoice

@Test
func appliesCorrections() {
    let processor = TextProcessor()
    let output = processor.process("please use j voice with whisper kit", mode: .casual)

    #expect(output == "please use JVoice with WhisperKit")
}

@Test
func formalModeCapitalizesAndTerminatesSentence() {
    let processor = TextProcessor()
    let output = processor.process("hello world", mode: .formal)

    #expect(output == "Hello world.")
}

@Test
func userDictionaryVariantsAreGenerated() {
    let dict = TextProcessor.buildUserDictionary(from: ["VS Code"])
    #expect(dict["vs code"] == "VS Code")
    #expect(dict["vscode"] == "VS Code")
}

@Test
func userDictionaryAppliedDuringProcess() {
    let userDict = TextProcessor.buildUserDictionary(from: ["Claude"])
    let output = TextProcessor.process("I use claude every day", mode: .casual, extraDictionary: userDict)
    #expect(output == "I use Claude every day")
}

@Test
func builtInDictionaryWinsOverUserEntry() {
    let userDict = TextProcessor.buildUserDictionary(from: ["jvoice override"])
    #expect(userDict["jvoice"] == nil)
}

@Test func removesStandaloneUm() {
    #expect(TextProcessor.removeDisfluencies("Um, I was thinking") == "I was thinking")
}

@Test func removesInlineUh() {
    #expect(TextProcessor.removeDisfluencies("I was uh thinking") == "I was thinking")
}

@Test func removesHmm() {
    #expect(TextProcessor.removeDisfluencies("hmm I need to go") == "I need to go")
}

@Test func removesTrailingFillerAndOrphanedComma() {
    #expect(TextProcessor.removeDisfluencies("I was thinking, um") == "I was thinking")
}

@Test func removesMultipleFillers() {
    #expect(TextProcessor.removeDisfluencies("I was umm uhh really") == "I was really")
}

@Test func removesConsecutiveFillers() {
    #expect(TextProcessor.removeDisfluencies("Umm, ahh, er, I see") == "I see")
}

@Test func doesNotRemoveLike() {
    #expect(TextProcessor.removeDisfluencies("I'd like to go") == "I'd like to go")
}

@Test func doesNotTouchWordContainingEr() {
    #expect(TextProcessor.removeDisfluencies("The error was clear") == "The error was clear")
}

@Test func removesMTrailingHesitationFillers() {
    // "uhm"/"erm" are pure hesitation fillers (never English words) that the
    // formatter's word boundaries keep distinct from real -rm/-hm words.
    #expect(TextProcessor.removeDisfluencies("uhm, I was thinking") == "I was thinking")
    #expect(TextProcessor.removeDisfluencies("I was uhm thinking") == "I was thinking")
    #expect(TextProcessor.removeDisfluencies("erm, I think so") == "I think so")
    #expect(TextProcessor.removeDisfluencies("I was uhmm really erm sure") == "I was really sure")
}

@Test func doesNotTouchRealRmWords() {
    #expect(TextProcessor.removeDisfluencies("the term was firm and warm") == "the term was firm and warm")
}

@Test func emptyStringReturnsEmpty() {
    #expect(TextProcessor.removeDisfluencies("") == "")
}

@Test func processWithFillerRemovalEnabled() {
    let result = TextProcessor.process("Um, hello world", mode: .casual, removeFillerWords: true)
    #expect(result == "hello world")
}

@Test func customWordWithDollarSignDoesNotInjectBackreference() {
    let output = TextProcessor.process("the price is portable", mode: .casual,
                                       extraDictionary: ["portable": "$ortable"])
    #expect(output == "the price is $ortable")
}

@Test func customWordWithBackslashDoesNotInjectBackreference() {
    let output = TextProcessor.process("save to cpath", mode: .casual,
                                       extraDictionary: ["cpath": "C:\\path"])
    #expect(output == "save to C:\\path")
}

@Test func customWordWithGroupReferenceProducesLiteral() {
    let output = TextProcessor.process("send the unit", mode: .casual,
                                       extraDictionary: ["unit": "$1unit"])
    #expect(output.contains("$1unit"))
}

@Test
func veryCasualLowercasesEverything() {
    let output = TextProcessor.process("Hello World From Me", mode: .veryCasual)
    #expect(output == "hello world from me.")
}

@Test
func veryCasualEnsuresTerminalPeriod() {
    #expect(TextProcessor.process("this has no ending", mode: .veryCasual) == "this has no ending.")
}

@Test
func veryCasualPreservesQuestionMark() {
    #expect(TextProcessor.process("Is It Working?", mode: .veryCasual) == "is it working?")
}

@Test
func veryCasualConvertsExclamationToPeriod() {
    #expect(TextProcessor.process("Stop right there!", mode: .veryCasual) == "stop right there.")
}

@Test
func veryCasualCollapsesRepeatedCommas() {
    let output = TextProcessor.process("well,, you know,, it works", mode: .veryCasual)
    #expect(output == "well, you know, it works.")
}

@Test
func veryCasualKeepsSeparatingCommasButDropsDanglingOne() {
    let output = TextProcessor.process("first, second, third,", mode: .veryCasual)
    #expect(output == "first, second, third.")
}

@Test
func veryCasualPreservesDictionaryCorrectionCasing() {
    // Policy change (2026-06-06): corrections win over the lowering — the
    // sentence is lowercased, but dictionary/custom words keep exact casing.
    // (Previously the lowering destroyed corrections, which made custom
    // words look broken in Very Casual mode.)
    let output = TextProcessor.process("use j voice now", mode: .veryCasual)
    #expect(output == "use JVoice now.")
}

@Test
func veryCasualPreservesCustomWordCasing() {
    let result = TextProcessor.process(
        "Open Jay Voice Settings",
        mode: .veryCasual,
        vocabulary: ["JVoice"]
    )
    #expect(result == "open JVoice settings.")
}

@Test
func processAppliesPhoneticVocabularyCorrection() {
    let result = TextProcessor.process(
        "open jay voice now",
        mode: .casual,
        vocabulary: ["JVoice"]
    )
    #expect(result == "open JVoice now")
}

// MARK: - TRX-01: no double/triple custom-word substitution

@Test func punctuatedCustomWordCorrectedOnce() {
    // ".NET" must be inserted exactly once; the old bug re-matched the bare
    // "net" inside the freshly-inserted ".NET", yielding "..NET"/"...NET".
    let dict = TextProcessor.buildUserDictionary(from: [".NET"])
    #expect(TextProcessor.applyCorrections("use dot net daily", extraDictionary: dict) == "use dot .NET daily")
}

@Test func builtInDictionaryStaysIdempotent() {
    #expect(TextProcessor.applyCorrections("use whisperkit now") == "use WhisperKit now")
    #expect(TextProcessor.applyCorrections("please use j voice with whisper kit") == "please use JVoice with WhisperKit")
}

@Test func spokenVariantsDropSelfSubstrings() {
    // ".NET" must NOT register the bare "net" variant (substring of the word),
    // which is what caused the re-match. The dotted/spaced variants remain so
    // "dot net" still corrects.
    let variants = Set(TextProcessor.spokenVariants(for: ".NET"))
    #expect(!variants.contains("net"))
    #expect(!variants.contains(".net"))
}

// MARK: - TRX-06: preserve legitimate bracketed tokens

@Test func stripDecoderArtifactsPreservesSingleLetterTokens() {
    #expect(TextProcessor.stripDecoderArtifacts("see figure [A] here") == "see figure [A] here")
    #expect(TextProcessor.stripDecoderArtifacts("reference [I] and [II]") == "reference [I] and [II]")
    #expect(TextProcessor.stripDecoderArtifacts("the answer is [X]") == "the answer is [X]")
}

@Test func stripDecoderArtifactsStillStripsSentinels() {
    #expect(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world") == "hello world")
    #expect(TextProcessor.stripDecoderArtifacts("a [MUSIC] b") == "a b")
    #expect(TextProcessor.stripDecoderArtifacts("a [APPLAUSE] b") == "a b")
    #expect(TextProcessor.stripDecoderArtifacts("a [NOISE_1] b") == "a b")
}

@Test func stripDecoderArtifactsMixedKeepsLabelStripsSentinel() {
    #expect(TextProcessor.stripDecoderArtifacts("see figure [A] then [MUSIC] plays") == "see figure [A] then plays")
}

// MARK: - BLD-12: extractCorrections stays bounded (no junk flood)

@Test func extractCorrectionsFullRewriteIsBounded() {
    let rewrite = TextProcessor.extractCorrections(
        from: "i think we should go now",
        corrected: "Honestly, I believe that the team ought to proceed immediately at once.")
    #expect(rewrite.count <= 12)
    #expect(!rewrite.contains("I"))          // single-char tokens filtered (count > 1)
    #expect(rewrite.allSatisfy { $0.count > 1 })
    #expect(!rewrite.contains(""))
}

@Test func extractCorrectionsPureDeletionIsEmpty() {
    let result = TextProcessor.extractCorrections(
        from: "please send the report by friday afternoon",
        corrected: "please send the report")
    #expect(result.isEmpty)
}

@Test func extractCorrectionsCapturesGenuineCorrection() {
    let result = TextProcessor.extractCorrections(
        from: "i use whisper kit daily",
        corrected: "i use WhisperKit daily")
    #expect(result == ["WhisperKit"])
}

@Test func removesThanksForWatchingHallucination() {
    #expect(TextProcessor.removeWhisperHallucinations(" Thanks for watching!") == "")
}

@Test func removesSubscribeHallucination() {
    #expect(TextProcessor.removeWhisperHallucinations("Subscribe to my channel.") == "")
}

@Test func removesUnpunctuatedHallucinationFromCasualTone() {
    // The Casual tone formatter strips terminal .!? before this filter runs,
    // so a whole-transcript hallucination must be caught without it too.
    #expect(TextProcessor.removeWhisperHallucinations("Thanks for watching") == "")
    #expect(TextProcessor.removeWhisperHallucinations("Bye") == "")
    // A longer real sentence that merely starts with such a phrase is untouched.
    #expect(TextProcessor.removeWhisperHallucinations("Thanks for watching the fireworks tonight")
        == "Thanks for watching the fireworks tonight")
}

@Test func removesBlankTextSentinel() {
    #expect(TextProcessor.removeWhisperHallucinations("[BLANK_TEXT]") == "")
    #expect(TextProcessor.removeWhisperHallucinations("BLANK_TEXT") == "")
}

@Test func removesLonePunctuation() {
    #expect(TextProcessor.removeWhisperHallucinations(".") == "")
    #expect(TextProcessor.removeWhisperHallucinations(",") == "")
    #expect(TextProcessor.removeWhisperHallucinations(" . ") == "")
}

@Test func preservesShortValidUtterance() {
    #expect(TextProcessor.removeWhisperHallucinations("OK.") == "OK.")
    #expect(TextProcessor.removeWhisperHallucinations("Hi") == "Hi")
}

@Test func preservesLongTranscriptWithThanks() {
    let input = "Thanks for the help, please send the file by Friday."
    #expect(TextProcessor.removeWhisperHallucinations(input) == input)
}

#elseif canImport(XCTest)
import XCTest
@testable import JVoice

final class TextProcessorTests: XCTestCase {
    func testAppliesCorrections() {
        let processor = TextProcessor()
        let output = processor.process("please use j voice with whisper kit", mode: .casual)

        XCTAssertEqual(output, "please use JVoice with WhisperKit")
    }

    func testFormalModeCapitalizesAndTerminatesSentence() {
        let processor = TextProcessor()
        let output = processor.process("hello world", mode: .formal)

        XCTAssertEqual(output, "Hello world.")
    }

    func testUserDictionaryVariantsAreGenerated() {
        let dict = TextProcessor.buildUserDictionary(from: ["VS Code"])
        XCTAssertEqual(dict["vs code"], "VS Code")
        XCTAssertEqual(dict["vscode"], "VS Code")
    }

    func testUserDictionaryAppliedDuringProcess() {
        let userDict = TextProcessor.buildUserDictionary(from: ["Claude"])
        let output = TextProcessor.process("I use claude every day", mode: .casual, extraDictionary: userDict)
        XCTAssertEqual(output, "I use Claude every day")
    }

    func testBuiltInDictionaryWinsOverUserEntry() {
        let userDict = TextProcessor.buildUserDictionary(from: ["jvoice override"])
        XCTAssertNil(userDict["jvoice"])
    }

    func testRemovesStandaloneUm() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("Um, I was thinking"), "I was thinking")
    }

    func testRemovesInlineUh() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("I was uh thinking"), "I was thinking")
    }

    func testRemovesHmm() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("hmm I need to go"), "I need to go")
    }

    func testRemovesTrailingFillerAndOrphanedComma() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("I was thinking, um"), "I was thinking")
    }

    func testRemovesMultipleFillers() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("I was umm uhh really"), "I was really")
    }

    func testRemovesConsecutiveFillers() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("Umm, ahh, er, I see"), "I see")
    }

    func testDoesNotRemoveLike() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("I'd like to go"), "I'd like to go")
    }

    func testDoesNotTouchWordContainingEr() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("The error was clear"), "The error was clear")
    }

    func testRemovesMTrailingHesitationFillers() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("uhm, I was thinking"), "I was thinking")
        XCTAssertEqual(TextProcessor.removeDisfluencies("I was uhm thinking"), "I was thinking")
        XCTAssertEqual(TextProcessor.removeDisfluencies("erm, I think so"), "I think so")
        XCTAssertEqual(TextProcessor.removeDisfluencies("I was uhmm really erm sure"), "I was really sure")
    }

    func testDoesNotTouchRealRmWords() {
        XCTAssertEqual(TextProcessor.removeDisfluencies("the term was firm and warm"), "the term was firm and warm")
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(TextProcessor.removeDisfluencies(""), "")
    }

    func testProcessWithFillerRemovalEnabled() {
        let result = TextProcessor.process("Um, hello world", mode: .casual, removeFillerWords: true)
        XCTAssertEqual(result, "hello world")
    }

    // MARK: - TRX-01: no double/triple custom-word substitution

    func testPunctuatedCustomWordCorrectedOnce() {
        let dict = TextProcessor.buildUserDictionary(from: [".NET"])
        XCTAssertEqual(TextProcessor.applyCorrections("use dot net daily", extraDictionary: dict), "use dot .NET daily")
    }

    func testBuiltInDictionaryStaysIdempotent() {
        XCTAssertEqual(TextProcessor.applyCorrections("use whisperkit now"), "use WhisperKit now")
        XCTAssertEqual(TextProcessor.applyCorrections("please use j voice with whisper kit"), "please use JVoice with WhisperKit")
    }

    func testSpokenVariantsDropSelfSubstrings() {
        let variants = Set(TextProcessor.spokenVariants(for: ".NET"))
        XCTAssertFalse(variants.contains("net"))
        XCTAssertFalse(variants.contains(".net"))
    }

    // MARK: - TRX-06: preserve legitimate bracketed tokens

    func testStripDecoderArtifactsPreservesSingleLetterTokens() {
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("see figure [A] here"), "see figure [A] here")
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("reference [I] and [II]"), "reference [I] and [II]")
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("the answer is [X]"), "the answer is [X]")
    }

    func testStripDecoderArtifactsStillStripsSentinels() {
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world"), "hello world")
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("a [MUSIC] b"), "a b")
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("a [APPLAUSE] b"), "a b")
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("a [NOISE_1] b"), "a b")
    }

    func testStripDecoderArtifactsMixedKeepsLabelStripsSentinel() {
        XCTAssertEqual(TextProcessor.stripDecoderArtifacts("see figure [A] then [MUSIC] plays"), "see figure [A] then plays")
    }

    // MARK: - BLD-12: extractCorrections stays bounded (no junk flood)

    func testExtractCorrectionsFullRewriteIsBounded() {
        let rewrite = TextProcessor.extractCorrections(
            from: "i think we should go now",
            corrected: "Honestly, I believe that the team ought to proceed immediately at once.")
        XCTAssertLessThanOrEqual(rewrite.count, 12)
        XCTAssertFalse(rewrite.contains("I"))
        XCTAssertTrue(rewrite.allSatisfy { $0.count > 1 })
        XCTAssertFalse(rewrite.contains(""))
    }

    func testExtractCorrectionsPureDeletionIsEmpty() {
        let result = TextProcessor.extractCorrections(
            from: "please send the report by friday afternoon",
            corrected: "please send the report")
        XCTAssertTrue(result.isEmpty)
    }

    func testExtractCorrectionsCapturesGenuineCorrection() {
        let result = TextProcessor.extractCorrections(
            from: "i use whisper kit daily",
            corrected: "i use WhisperKit daily")
        XCTAssertEqual(result, ["WhisperKit"])
    }
}

#else
@testable import JVoice

enum TextProcessorTestsFallback {
    static func run() {
        let processor = TextProcessor()
        assert(processor.process("please use j voice with whisper kit", mode: .casual) == "please use JVoice with WhisperKit")
        assert(processor.process("hello world", mode: .formal) == "Hello world.")
    }
}
#endif
