#if canImport(Testing)
import Testing
@testable import JVoice

@Test func everyDictationErrorHasNonEmptySpecificMessage() {
    for e in DictationError.allCases {
        #expect(!e.message.isEmpty)
        // No case may fall back to the old generic copy.
        #expect(e.message.lowercased() != "something went wrong")
    }
}

@Test func dictationErrorMessagesAreDistinct() {
    let messages = DictationError.allCases.map(\.message)
    #expect(Set(messages).count == messages.count)
}

@Test func noMicrophoneMentionsMicrophone() {
    #expect(DictationError.noMicrophone.message.lowercased().contains("microphone"))
}
#endif
