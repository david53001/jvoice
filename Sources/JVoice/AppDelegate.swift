import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = VoiceCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        coordinator.bootstrapLaunchAtLogin()

        // Route service-level failures (e.g. settings encode errors) through
        // the HUD instead of silently swallowing them.
        SystemActions.errorHandler = { [weak coordinator] message in
            coordinator?.showError(message)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.flushSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
