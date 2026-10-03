import Foundation

/// Hook for surfacing transient errors to the user. The app wires this once in
/// `AppDelegate.applicationDidFinishLaunching` to a closure that forwards to
/// `VoiceCoordinator.showError(_:)`, so services that can't reach the
/// coordinator directly (e.g. `SettingsStore`) can still report failures
/// through the HUD. Always invoked on the main actor.
enum SystemActions {
    /// Setting the handler delivers any errors `report` queued before it existed.
    @MainActor static var errorHandler: ((String) -> Void)? {
        didSet {
            guard let errorHandler, !pendingErrors.isEmpty else { return }
            let queued = pendingErrors
            pendingErrors = []
            queued.forEach(errorHandler)
        }
    }

    /// Errors reported before `errorHandler` was installed. `SettingsStore` loads
    /// while `AppDelegate` builds the coordinator — before
    /// `applicationDidFinishLaunching` installs the handler — so its load-time
    /// warnings (unreadable / newer-schema settings) would otherwise be dropped.
    @MainActor private static var pendingErrors: [String] = []

    /// Deliver `message` to the handler, or hold it until one is installed.
    @MainActor static func report(_ message: String) {
        if let errorHandler {
            errorHandler(message)
        } else {
            pendingErrors.append(message)
        }
    }
}
