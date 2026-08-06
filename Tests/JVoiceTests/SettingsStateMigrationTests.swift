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

@Test func newSettingsStateDefaultsToDarkTheme() {
    #expect(SettingsState().theme == .dark)
}

@Test func decodesV1BlobWithoutThemeAsDark() throws {
    // A schema-v1 blob predates the theme field; it must decode (v1 < current)
    // and default theme to .dark.
    let v1JSON = """
    {"schemaVersion":1,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: v1JSON)
    #expect(decoded.theme == .dark)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
}

@Test func themeRoundTripsThroughSettingsState() throws {
    var s = SettingsState()
    s.theme = .light
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(SettingsState.self, from: data)
    #expect(back.theme == .light)
}

// MARK: - Schema v2 → v3 (dictation-parity features)

@Test func decodesV2BlobWithoutV3FieldsAtDefaults() throws {
    // A schema-v2 blob predates the v3 dictation-parity fields; it must decode
    // (v2 < current) and default every new field: developerTerms ON, the rest OFF,
    // and no app-mode rules.
    let v2JSON = """
    {"schemaVersion":2,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true,"theme":"dark"}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: v2JSON)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
    #expect(decoded.developerTerms == true)
    #expect(decoded.translateToEnglish == false)
    #expect(decoded.copyToClipboardOnly == false)
    #expect(decoded.appAwareModes == false)
    #expect(decoded.appModeRules.isEmpty)
}

@Test func newSettingsStateV3Defaults() {
    let s = SettingsState()
    #expect(s.developerTerms == true)
    #expect(s.translateToEnglish == false)
    #expect(s.copyToClipboardOnly == false)
    #expect(s.appAwareModes == false)
    #expect(s.appModeRules.isEmpty)
}

@Test func appModeRulesRoundTripThroughSettingsState() throws {
    var s = SettingsState()
    s.appModeRules = [AppModeRule(appMatch: "com.microsoft.VSCode", mode: .code),
                      AppModeRule(appMatch: "slack", mode: .formal)]
    s.developerTerms = false
    s.copyToClipboardOnly = true
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(SettingsState.self, from: data)
    #expect(back.appModeRules == s.appModeRules)
    #expect(back.developerTerms == false)
    #expect(back.copyToClipboardOnly == true)
}
#endif
