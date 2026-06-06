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
func veryCasualLowercasesEvenDictionaryCorrections() {
    // "everything is lowercased" wins even over the correction dictionary.
    let output = TextProcessor.process("use j voice now", mode: .veryCasual)
    #expect(output == "use jvoice now.")
}

@Test func removesThanksForWatchingHallucination() {
    #expect(TextProcessor.removeWhisperHallucinations(" Thanks for watching!") == "")
}

@Test func removesSubscribeHallucination() {
    #expect(TextProcessor.removeWhisperHallucinations("Subscribe to my channel.") == "")
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

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(TextProcessor.removeDisfluencies(""), "")
    }

    func testProcessWithFillerRemovalEnabled() {
        let result = TextProcessor.process("Um, hello world", mode: .casual, removeFillerWords: true)
        XCTAssertEqual(result, "hello world")
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
