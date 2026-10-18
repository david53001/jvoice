import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService` (macOS 13+). The OS owns the on/off
/// state — `SMAppService.mainApp.status` is the source of truth — so we don't
/// persist the preference ourselves.
///
/// JVoice never turns it on by itself (since 1.2.0): the user does, with the menu's
/// "Launch at Login" item or by answering the one-time "Open JVoice at login?" card
/// (`UI/LaunchAtLoginPromptController.swift`, rules in `LaunchAtLoginPrompt`). Up to 1.1.4
/// the first launch registered silently (flag `jvoice.app.launchAtLogin.didInitialize`);
/// that is gone, and the flag is now only read, to keep from asking those users.
enum LaunchAtLoginManager {
    /// Posted after every `setEnabled`, so the menu item's mirror (`VoiceCoordinator.launchAtLogin`)
    /// and the card show the real status.
    static let didChangeNotification = Notification.Name("com.jvoice.app.launchAtLoginDidChange")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// System Settings → General → Login Items, where the user approves (or re-enables) it.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Turns launch at login on or off. Any explicit choice also counts as the answer to the
    /// one-time question, so the card never asks someone who already chose. Throws the
    /// `SMAppService` error; the status afterwards is the real outcome either way.
    static func setEnabled(_ enabled: Bool) throws {
        LaunchAtLoginPrompt().markAsked()
        defer { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
