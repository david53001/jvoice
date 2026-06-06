import Foundation

public enum TranscriptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case romanian

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .romanian: return "Romanian"
        }
    }

    public var whisperCode: String {
        switch self {
        case .english: return "en"
        case .romanian: return "ro"
        }
    }
}

extension TranscriptionLanguage {
    /// Fallback decoder: an unknown rawValue decodes to `.english` instead
    /// of throwing, so a renamed/removed language case in a future build
    /// cannot torpedo the entire SettingsState decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = TranscriptionLanguage(rawValue: raw) ?? .english
    }
}
