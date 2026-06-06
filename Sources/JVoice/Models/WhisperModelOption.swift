import Foundation

public enum WhisperModelOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiny
    case base
    case small
    case largeTurbo = "large-v3_turbo"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tiny, .base, .small:
            return rawValue.capitalized
        case .largeTurbo:
            return "Large v3 Turbo"
        }
    }

    public var whisperKitModelName: String {
        rawValue
    }

    public var whisperKitFolderName: String {
        "openai_whisper-\(rawValue)"
    }

    public var approximateRelativeSize: String {
        switch self {
        case .tiny:
            return "Smallest"
        case .base:
            return "Balanced"
        case .small:
            return "Larger"
        case .largeTurbo:
            return "Most capable"
        }
    }
}

extension WhisperModelOption {
    /// Fallback decoder: an unknown rawValue (e.g. a model removed in a
    /// future build) decodes to `.tiny` instead of throwing, so a single
    /// stale enum case cannot torpedo the entire SettingsState decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = WhisperModelOption(rawValue: raw) ?? .tiny
    }
}