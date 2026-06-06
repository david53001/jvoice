import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService` (macOS 13+). The OS owns the on/off
/// state — `SMAppService.mainApp.status` is the source of truth — so we don't
/// persist the preference ourselves. The only thing we remember is whether
/// we've done the one-time, first-run auto-enable, so we never re-enable after
/// a user deliberately turns it off.
enum LaunchAtLoginManager {
    private static let didInitializeKey = "jvoice.app.launchAtLogin.didInitialize"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// On the very first launch only, best-effort enable launch-at-login.
    /// Silent by design: a failure here (e.g. running an unsigned/dev copy)
    /// shouldn't nag the user — they can flip the Settings toggle manually.
    static func performFirstRunEnableIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didInitializeKey) else { return }
        defaults.set(true, forKey: didInitializeKey)
        try? setEnabled(true)
    }
}
