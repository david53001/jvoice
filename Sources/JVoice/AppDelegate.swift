import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = VoiceCoordinator()
    /// Guided tours (`Tours/`). The audience (new vs existing user) was already classified in
    /// `JVoiceMain.main()`, before anything wrote a preference.
    private(set) lazy var tourCoordinator = TourCoordinator(
        makePresenter: { TagOverlayController() },
        shortcutText: { name in
            let shortcutName: KeyboardShortcuts.Name
            switch name {
            case KeyboardShortcuts.Name.toggleRecording.rawValue: shortcutName = .toggleRecording
            case KeyboardShortcuts.Name.undoLastPaste.rawValue: shortcutName = .undoLastPaste
            default: return nil
            }
            return KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? TourText.unboundShortcut
        })
    /// The first-run window; made on first use (new users at launch, or the Welcome tour from the menu).
    private var welcomeWindow: WelcomeWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTours()
        // A new user who hasn't answered "Want a quick tour?" gets the Welcome window, which asks for
        // Accessibility itself — so the launch-time system prompt would only stack a second dialog.
        // Existing users (and new users who already answered) see nothing new at launch, ever.
        let showWelcome = tourCoordinator.shouldAskQuestion
        if showWelcome { coordinator.suppressLaunchAccessibilityPrompt = true }

        coordinator.start()
        coordinator.bootstrapLaunchAtLogin()

        // Route service-level failures (e.g. settings encode errors) through
        // the HUD instead of silently swallowing them. Installing the handler
        // also delivers warnings queued while `coordinator` was being built
        // (SettingsStore's load-time "settings reset" warning) — deliberately
        // AFTER start(), whose updateHUD(.idle) would otherwise hide them.
        SystemActions.errorHandler = { [weak coordinator] message in
            coordinator?.showError(message)
        }

        if showWelcome {
            // Once launch has finished, so the status item (the tour's first anchor) is in place.
            DispatchQueue.main.async { [weak self] in
                self?.welcome().show(page: .permissions, askTourQuestion: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.cleanUpForTermination()
        coordinator.flushSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Tours

    private func installTours() {
        let tours = tourCoordinator
        tours.install()   // wires the TourEvents bus, incl. Reset All Tours (+ its HUD confirmation)
        tours.notify = { [weak self] message in self?.coordinator.showTourNotice(message) }
        // The Opacity step plays the slider down and up (never saved; `OpacityTourDemo`).
        tours.makeDemo = { step in step.anchor == OpacityTourDemo.anchor ? OpacityTourDemo() : nil }
        tours.openSurface = { [weak self] surface in
            guard let self else { return false }
            switch surface {
            case .welcome:
                self.welcome().show(page: .allSet, askTourQuestion: false)
                return true
            case .settings:
                self.coordinator.openSettingsWindow()
                return true
            case .recordingPill:
                return false
            }
        }
        // The Welcome window's job is done once its tour ends: don't leave it behind.
        tours.onFinished = { [weak self] id in
            if id == .welcome { self?.welcomeWindow?.close() }
        }
        // The Welcome tour's first step points at the menu-bar "J", which lives in the status bar's own
        // window — any visible window of ours may hold a step's anchor.
        tours.extraAnchorWindows = { NSApp.windows.filter(\.isVisible) }
    }

    private func welcome() -> WelcomeWindow {
        if let welcomeWindow { return welcomeWindow }
        let window = WelcomeWindow(coordinator: coordinator)
        window.onTourAnswer = { [weak self] showMeAround, host in
            self?.tourCoordinator.answerQuestion(showMeAround: showMeAround, in: host)
        }
        welcomeWindow = window
        return window
    }
}
