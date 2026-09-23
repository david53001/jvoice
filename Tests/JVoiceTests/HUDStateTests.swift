#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

/// Clipboard-only mode used to finish on a "Pasted" pill although nothing was
/// pasted. The copied state must say so and behave like `.done` otherwise.
@Test func copiedStateSaysCopiedNotPasted() {
    let state = HUDState.copied("hello")
    #expect(state.headline == "Copied")
    #expect(state.displayText == "Copied")
    #expect(HUDState.done("hello").headline == "Pasted")
    #expect(state.isVisible)
    #expect(state.isTerminal)
    #expect(!state.isBusy)
    #expect(state.payload == "hello")
}

@Test func copiedStateSurvivesACodableRoundTrip() throws {
    let data = try JSONEncoder().encode(HUDState.copied("hello"))
    #expect(try JSONDecoder().decode(HUDState.self, from: data) == .copied("hello"))
}
#endif
