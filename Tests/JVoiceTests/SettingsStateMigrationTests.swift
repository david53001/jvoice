#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test func newSettingsStateHasSchemaVersion() {
    let s = SettingsState()
    #expect(s.schemaVersion == SettingsState.currentSchemaVersion)
}

@Test func decodesLegacyBlobWithoutSchemaVersion() throws {
    let legacyJSON = """
    {"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: legacyJSON)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
}

@Test func encodesNewBlobWithSchemaVersion() throws {
    let s = SettingsState()
    let data = try JSONEncoder().encode(s)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"schemaVersion\""))
}

@Test func decodingNewerSchemaVersionFails() {
    let futureJSON = """
    {"schemaVersion":99,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true}
    """.data(using: .utf8)!
    let result = Swift.Result { try JSONDecoder().decode(SettingsState.self, from: futureJSON) }
    #expect((try? result.get()) == nil)
}

@Test func unknownWhisperModelDecodesToDefault() throws {
    let json = "\"ghost-model\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(WhisperModelOption.self, from: json)
    #expect(decoded == .tiny)
}

@Test func unknownLanguageDecodesToDefault() throws {
    let json = "\"klingon\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(TranscriptionLanguage.self, from: json)
    #expect(decoded == .english)
}

@Test func unknownToneModeDecodesToDefault() throws {
    // AppMode is the Codable persisted form of tone (ToneMode in
    // VoiceCoordinator.swift is a non-Codable UI mirror).
    let json = "\"interplanetary\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppMode.self, from: json)
    #expect(decoded == .casual)
}
#endif
