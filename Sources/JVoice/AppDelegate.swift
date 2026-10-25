import AppKit
import KeyboardShortcuts
import os

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
    /// The main menu and the Dock icon's menu (a Dock app since 1.4.0; it was a menu-bar item before).
    private lazy var menus = AppMenus(coordinator: coordinator)
    private static let launchLog = Logger(subsystem: "com.jvoice.app", category: "launch")

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if SPARKLE_E2E_TEST
        // The throwaway updater-only copy stays out of the Dock, beside the user's real JVoice.
        NSApp.setActivationPolicy(.accessory)
        #else
        NSApp.setActivationPolicy(.regular)
        #endif
        // The system's own "Start Dictation…" (Apple dictation) would sit in JVoice's Edit menu right
        // next to JVoice's Start Dictation. Registration domain only: nothing is written to disk.
        UserDefaults.standard.register(defaults: ["NSDisabledDictationMenuItem": true])
        NSApp.mainMenu = menus.makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SPARKLE_E2E_TEST
        // The throwaway build of scripts/sparkle-e2e-test.sh runs next to the user's real copy: it
        // only starts the updater — no hotkeys, microphone, model load, orphan-WAV sweep or
        // Welcome window, which would touch the real app's shared state or ask for permissions.
        Updates.shared.start()
        return
        #endif
        installTours()
        // A new user who hasn't answered "Want a quick tour?" gets the Welcome window, which asks for
        // Accessibility itself — so the launch-time system prompt would only stack a second dialog.
        // Existing users (and new users who already answered) never get it.
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

        // At login JVoice opens no window — it waits in the Dock with the shortcut ready; opened by the
        // user, it shows Settings (`LaunchWindowPolicy`). The launch Apple Event says which it was.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = LaunchWindowPolicy.isLoginItemLaunch(
            eventID: launchEvent?.eventID,
            launchProperty: launchEvent?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue)
        // A session restore at login ("Reopen windows when logging back in") may not carry the login-item
        // property, but it isn't a default launch.
        let isDefault = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        let window = LaunchWindowPolicy.atLaunch(showWelcome: showWelcome, launchedAsLoginItem: atLogin,
                                                 isDefaultLaunch: isDefault)
        Self.launchLog.info("Launch atLogin=\(atLogin, privacy: .public) isDefault=\(isDefault, privacy: .public) window=\(String(describing: window), privacy: .public)")
        // Once launch has finished, so everything above is in place.
        DispatchQueue.main.async { [weak self] in self?.open(window, atLaunch: true) }
    }

    /// Opens what `LaunchWindowPolicy` decided. The Welcome window opens on its first page with the tour
    /// question at launch, and is just brought forward on a Dock click.
    private func open(_ window: LaunchWindowPolicy.Window, atLaunch: Bool) {
        switch window {
        case .welcome:
            if atLaunch {
                welcome().show(page: .permissions, askTourQuestion: true)
            } else {
                welcomeWindow?.makeKeyAndOrderFront(nil)
            }
        case .settings:
            coordinator.openSettingsWindow()
        case .noWindow:
            break
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

    /// A click on the Dock icon, or launching JVoice again while it runs (Finder, Spotlight, Launchpad,
    /// `open`), shows Settings — or brings the first-run Welcome window forward while that is open. Not
    /// gated on `hasVisibleWindows`: the HUD pill or the login card counts as a visible window, and a
    /// Dock click must still open Settings then.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if SPARKLE_E2E_TEST
        return false   // the throwaway updater-only build never opens a window
        #endif
        open(LaunchWindowPolicy.onReopen(welcomeVisible: welcomeWindow?.isVisible ?? false), atLaunch: false)
        return false
    }

    /// The Dock icon's right-click menu: every action of the old menu-bar menu (`AppMenus`).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        #if SPARKLE_E2E_TEST
        return nil
        #endif
        return menus.makeDockMenu()
    }

    // MARK: - Launch at login

    private func installLoginPrompt() {
        let prompt = LaunchAtLoginPromptController()
        prompt.isDictationActive = { [weak coordinator] in coordinator?.isDictationActive ?? false }
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
