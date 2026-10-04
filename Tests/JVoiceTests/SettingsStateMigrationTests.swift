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

@Test func newSettingsStateDefaultsToSystemTheme() {
    #expect(SettingsState().theme == .system)
}

@Test func decodesV1BlobWithoutThemeAsSystem() throws {
    // A schema-v1 blob predates the theme field; it must decode (v1 < current)
    // and default theme to .system (follow macOS).
    let v1JSON = """
    {"schemaVersion":1,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: v1JSON)
    #expect(decoded.theme == .system)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
}

@Test func legacyThemeMigratesToSystemAppearance() throws {
    // A blob without `appearance` (older build): `.dark` was the old default, not a choice, so it
    // becomes `.system`; an explicit `.light` is kept. `appearance`, when present, wins.
    func decode(_ json: String) throws -> AppTheme {
        try JSONDecoder().decode(SettingsState.self, from: json.data(using: .utf8)!).theme
    }
    #expect(try decode("{\"schemaVersion\":4,\"theme\":\"dark\"}") == .system)
    #expect(try decode("{\"schemaVersion\":4,\"theme\":\"light\"}") == .light)
    #expect(try decode("{\"schemaVersion\":4,\"theme\":\"dark\",\"appearance\":\"dark\"}") == .dark)
    #expect(try decode("{\"schemaVersion\":4,\"theme\":\"dark\",\"appearance\":\"system\"}") == .system)
}

@Test func appearanceKeepsOlderBuildsReadable() throws {
    // The schema stays v4 and the legacy `theme` field is still written (never "system", which an
    // older build doesn't know), so a v1.1.3 build keeps reading the blob.
    for (appearance, legacy) in [(AppTheme.system, "dark"), (.dark, "dark"), (.light, "light")] {
        var s = SettingsState()
        s.theme = appearance
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        #expect(object["schemaVersion"] as? Int == 4)
        #expect(object["theme"] as? String == legacy)
        #expect(object["appearance"] as? String == appearance.rawValue)
    }
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

// MARK: - Schema v3 → v4 (math notation)

@Test func decodesV3BlobWithoutV4FieldsAtDefaults() throws {
    // A schema-v3 blob predates `mathNotation`; it must decode and default it ON, so
    // upgrading gains the feature without a settings edit.
    let v3JSON = """
    {"schemaVersion":3,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true,"theme":"dark","developerTerms":true,
     "translateToEnglish":false,"copyToClipboardOnly":false,"appAwareModes":false,
     "appModeRules":[]}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: v3JSON)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
    #expect(decoded.mathNotation == true)
}

@Test func mathNotationRoundTripsThroughSettingsState() throws {
    var s = SettingsState()
    #expect(s.mathNotation == true)          // opt-out, like developerTerms
    s.mathNotation = false
    let back = try JSONDecoder().decode(SettingsState.self, from: JSONEncoder().encode(s))
    #expect(back.mathNotation == false)
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
