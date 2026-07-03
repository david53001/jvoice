import Foundation

/// A per-app tone override rule: when the frontmost app's bundle identifier
/// matches `appMatch` (case-insensitive substring), dictation uses `mode`
/// instead of the user's global tone. Persisted in `SettingsState` (schema v3).
/// Mirrors the Windows port's `AppModeRule` (which matched exe names instead).
public struct AppModeRule: Codable, Equatable, Hashable, Sendable {
    public var appMatch: String
    public var mode: AppMode

    public init(appMatch: String, mode: AppMode) {
        self.appMatch = appMatch
        self.mode = mode
    }
}
