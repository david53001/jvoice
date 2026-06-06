import Foundation

/// Hook for surfacing transient errors to the user. The app wires this once in
/// `AppDelegate.applicationDidFinishLaunching` to a closure that forwards to
/// `VoiceCoordinator.showError(_:)`, so services that can't reach the
/// coordinator directly (e.g. `SettingsStore`) can still report failures
/// through the HUD. Always invoked on the main actor.
enum SystemActions {
    @MainActor static var errorHandler: ((String) -> Void)?
}
