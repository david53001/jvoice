#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test func largeTurboMapsToOpenAITurboModel() {
    // OpenAI's actual large-v3-turbo (4-layer decoder), NOT WhisperKit's
    // "_turbo" compression of original large-v3 (32-layer decoder). The
    // physical build is the turbo-optimized 632 MB variant — same architecture,
    // ~21–36% faster, ~624 MB download — decoupled from the stable Codable
    // rawValue (which stays "large-v3-v20240930").
    #expect(WhisperModelOption.largeTurbo.whisperKitModelName == "large-v3-v20240930_turbo_632MB")
    #expect(WhisperModelOption.largeTurbo.whisperKitFolderName == "openai_whisper-large-v3-v20240930_turbo_632MB")
}

@Test func largeTurboHasReadableDisplayName() {
    // The raw "large-v3-v20240930" identifier must never leak into the UI.
    #expect(WhisperModelOption.largeTurbo.displayName == "Large v3 Turbo")
}

@Test func largeTurboRoundTripsThroughCodable() throws {
    let data = try JSONEncoder().encode(WhisperModelOption.largeTurbo)
    #expect(String(data: data, encoding: .utf8) == "\"large-v3-v20240930\"")
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: data)
    #expect(decoded == .largeTurbo)
}

@Test func legacyLargeTurboRawValueStillDecodesToLargeTurbo() throws {
    // Settings written before the 2026-06 model swap stored "large-v3_turbo";
    // they must keep resolving to the large option, not the .tiny fallback.
    let json = "\"large-v3_turbo\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: json)
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
