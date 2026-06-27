import Foundation

/// User-selectable app appearance. Persisted in `SettingsState`; the sun/moon
/// toggle in Settings flips it. Drives the monochrome `Theme` tokens used by
/// every custom-drawn JVoice surface (HUD pill + Settings window).
public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dark:  return "Dark"
        case .light: return "Light"
        }
    }

    public var toggled: AppTheme {
        switch self {
        case .dark:  return .light
        case .light: return .dark
        }
    }
}

extension AppTheme {
    /// Fallback decoder: an unknown rawValue decodes to `.dark` instead of
    /// throwing, so a future renamed/removed case can't torpedo the whole
    /// SettingsState decode (mirrors `AppMode`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AppTheme(rawValue: raw) ?? .dark
    }
}
