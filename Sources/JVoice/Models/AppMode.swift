import Foundation

public enum AppMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case casual
    case formal
    case veryCasual
    /// Minimal formatting that preserves casing, symbols and punctuation exactly
    /// as spoken (for terminals/editors). Selectable ONLY as a per-app override
    /// (see `AppModeResolver`); deliberately NOT part of the manual `toggled`
    /// cycle, mirroring the Windows port's `ToneStyle.Code`.
    case code

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .casual:
            return "Casual"
        case .formal:
            return "Formal"
        case .veryCasual:
            return "Very Casual"
        case .code:
            return "Code"
        }
    }

    public var toggled: AppMode {
        switch self {
        case .casual:
            return .formal
        case .formal:
            return .veryCasual
        case .veryCasual:
            return .casual
        // Code is never a target of the manual cycle; a stray toggle from it
        // returns to Casual (mirrors the Windows `_ => Casual` default).
        case .code:
            return .casual
        }
    }
}

extension AppMode {
    /// Fallback decoder: an unknown rawValue decodes to `.casual` instead
    /// of throwing, so a renamed/removed tone case in a future build cannot
    /// torpedo the entire SettingsState decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AppMode(rawValue: raw) ?? .casual
    }
}