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
    /// "Open JVoice at login?", once, after the 5th completed dictation.
    private var loginPrompt: LaunchAtLoginPromptController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SPARKLE_E2E_TEST
        // The throwaway build of scripts/sparkle-e2e-test.sh runs next to the user's real copy: it
        // only starts the updater — no status item, hotkeys, microphone, model load, orphan-WAV sweep or
        // Welcome window, which would touch the real app's shared state or ask for permissions.
        Updates.shared.start()
        return
        #endif
        installTours()
        // A new user who hasn't answered "Want a quick tour?" gets the Welcome window, which asks for
        // Accessibility itself — so the launch-time system prompt would only stack a second dialog.
        // Existing users (and new users who already answered) see nothing new at launch, ever.
        let showWelcome = tourCoordinator.shouldAskQuestion
        if showWelcome { coordinator.suppressLaunchAccessibilityPrompt = true }

        coordinator.start()
        coordinator.bootstrapLaunchAtLogin()
        // "Check for Updates…" in the menu, Settings → Updates, and the daily background check.
        Updates.shared.start()
        installLoginPrompt()

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
        #if SPARKLE_E2E_TEST
        return   // nothing was started
        #endif
        coordinator.cleanUpForTermination()
        coordinator.flushSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launching JVoice again while it runs (Finder, Spotlight, Launchpad, `open`) shows the real
    /// Settings window — never SwiftUI's own default window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if SPARKLE_E2E_TEST
        return false   // the throwaway updater-only build never opens a window
        #endif
        if !flag { coordinator.openSettingsWindow() }
        return false
    }

    // MARK: - Launch at login

    private func installLoginPrompt() {
        let prompt = LaunchAtLoginPromptController()
        prompt.isDictationActive = { [weak coordinator] in coordinator?.isDictationActive ?? false }
        prompt.isMenuOpen = { [weak coordinator] in coordinator?.isMenuBarMenuOpen ?? false }
        prompt.appearance = { [weak coordinator] in coordinator?.appTheme.nsAppearance }
        coordinator.onDictationCompleted = { [weak prompt] in prompt?.dictationCompleted() }
        loginPrompt = prompt
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
