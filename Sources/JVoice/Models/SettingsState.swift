import Foundation

public struct SettingsState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: Int = 4
    public var schemaVersion: Int = SettingsState.currentSchemaVersion
    public var mode: AppMode
    public var model: WhisperModelOption
    public var language: TranscriptionLanguage
    public var customWords: [String]
    public var removeFillerWords: Bool
    public var theme: AppTheme
    /// v3 dictation-parity fields (mirror the Windows port's SettingsState v3).
    public var developerTerms: Bool
    public var translateToEnglish: Bool
    public var copyToClipboardOnly: Bool
    public var appAwareModes: Bool
    public var appModeRules: [AppModeRule]
    /// v4: spoken mathematics → real notation ("x squared equals 4" → "x² = 4").
    /// Opt-out, like the Windows port's `MathNotation` (schema v6 there).
    public var mathNotation: Bool

    public var whisperModel: WhisperModelOption {
        get { model }
        set { model = newValue }
    }

    public init(
        mode: AppMode = .casual,
        model: WhisperModelOption = .tiny,
        language: TranscriptionLanguage = .english,
        customWords: [String] = [],
        removeFillerWords: Bool = true,
        theme: AppTheme = .dark,
        developerTerms: Bool = true,
        translateToEnglish: Bool = false,
        copyToClipboardOnly: Bool = false,
        appAwareModes: Bool = false,
        appModeRules: [AppModeRule] = [],
        mathNotation: Bool = true
    ) {
        self.mode = mode
        self.model = model
        self.language = language
        self.customWords = customWords
        self.removeFillerWords = removeFillerWords
        self.theme = theme
        self.developerTerms = developerTerms
        self.translateToEnglish = translateToEnglish
        self.copyToClipboardOnly = copyToClipboardOnly
        self.appAwareModes = appAwareModes
        self.appModeRules = appModeRules
        self.mathNotation = mathNotation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case model
        case language
        case customWords
        case removeFillerWords
        case theme
        case developerTerms
        case translateToEnglish
        case copyToClipboardOnly
        case appAwareModes
        case appModeRules
        case mathNotation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        self.schemaVersion = SettingsState.currentSchemaVersion   // always normalize forward
        if version > SettingsState.currentSchemaVersion {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Settings written by a newer JVoice build (v\(version) > v\(SettingsState.currentSchemaVersion)). Refusing to read."
            )
        }
        mode = (try? container.decode(AppMode.self, forKey: .mode)) ?? .casual
        model = (try? container.decode(WhisperModelOption.self, forKey: .model)) ?? .tiny
        language = try container.decodeIfPresent(TranscriptionLanguage.self, forKey: .language) ?? .english
        customWords = try container.decodeIfPresent([String].self, forKey: .customWords) ?? []
        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? true
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
        // v3 fields: absent in v1/v2 blobs → default (developerTerms ON, rest OFF).
        developerTerms = try container.decodeIfPresent(Bool.self, forKey: .developerTerms) ?? true
        translateToEnglish = try container.decodeIfPresent(Bool.self, forKey: .translateToEnglish) ?? false
        copyToClipboardOnly = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboardOnly) ?? false
        appAwareModes = try container.decodeIfPresent(Bool.self, forKey: .appAwareModes) ?? false
        appModeRules = try container.decodeIfPresent([AppModeRule].self, forKey: .appModeRules) ?? []
        // v4 field: absent in v1–v3 blobs → default ON, so an upgrade gains the feature.
        mathNotation = try container.decodeIfPresent(Bool.self, forKey: .mathNotation) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(SettingsState.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(mode, forKey: .mode)
        try container.encode(model, forKey: .model)
        try container.encode(language, forKey: .language)
        try container.encode(customWords, forKey: .customWords)
        try container.encode(removeFillerWords, forKey: .removeFillerWords)
        try container.encode(theme, forKey: .theme)
        try container.encode(developerTerms, forKey: .developerTerms)
        try container.encode(translateToEnglish, forKey: .translateToEnglish)
        try container.encode(copyToClipboardOnly, forKey: .copyToClipboardOnly)
        try container.encode(appAwareModes, forKey: .appAwareModes)
        try container.encode(appModeRules, forKey: .appModeRules)
        try container.encode(mathNotation, forKey: .mathNotation)
    }
}
