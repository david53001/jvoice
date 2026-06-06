#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test func largeTurboMapsToWhisperKitTurboModel() {
    #expect(WhisperModelOption.largeTurbo.whisperKitModelName == "large-v3_turbo")
    #expect(WhisperModelOption.largeTurbo.whisperKitFolderName == "openai_whisper-large-v3_turbo")
}

@Test func largeTurboHasReadableDisplayName() {
    // The raw "large-v3_turbo" string must never leak into the UI.
    #expect(WhisperModelOption.largeTurbo.displayName == "Large v3 Turbo")
}

@Test func largeTurboRoundTripsThroughCodable() throws {
    let data = try JSONEncoder().encode(WhisperModelOption.largeTurbo)
    #expect(String(data: data, encoding: .utf8) == "\"large-v3_turbo\"")
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: data)
    #expect(decoded == .largeTurbo)
}

@Test func largeTurboIsOfferedAsAModelOption() {
    #expect(WhisperModelOption.allCases.contains(.largeTurbo))
}

@Test func unknownModelStillFallsBackToTiny() throws {
    // Adding the new case must not disturb the existing unknown-value fallback.
    let json = "\"ghost-model\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: json)
    #expect(decoded == .tiny)
}
#endif
