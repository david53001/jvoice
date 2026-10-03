import Foundation

/// User-selectable app appearance. Persisted in `SettingsState`; the System / Light / Dark picker in
/// Settings sets it. `.system` (the default) follows macOS; the other two force an appearance on every
/// JVoice window (HUD pill, Settings, Welcome).
public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Flips between the two explicit appearances (`.system` → `.dark`). Unused since the three-way
    /// picker replaced the sun/moon toggle; kept for its tests.
    public var toggled: AppTheme {
        switch self {
        case .dark:           return .light
        case .light, .system: return .dark
        }
    }
}

extension AppTheme {
    /// Fallback decoder: an unknown rawValue decodes to `.system` instead of
    /// throwing, so a future renamed/removed case can't torpedo the whole
    /// SettingsState decode (mirrors `AppMode`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AppTheme(rawValue: raw) ?? .system
    }
}
