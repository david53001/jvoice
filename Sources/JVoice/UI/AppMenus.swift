import AppKit
import Combine

/// JVoice's menus since 1.4.0, when it became a Dock app (until 1.3.1 everything lived in a menu-bar
/// status item's menu): the main menu (JVoice · Edit · Window · Help) and the Dock icon's right-click
/// menu. Each offers every action the old status menu had, built by the same helpers and acting through
/// the same calls. The dynamic parts — Start/Stop Dictation, Launch at Login's checkmark, Check for
/// Updates… / Update Available (X)… — are set in `validateMenuItem` (main menu: AppKit asks before a menu
/// shows and before a key equivalent fires) or when the Dock asks for its menu (`makeDockMenu`).
///
/// Key equivalents fire for real while JVoice is frontmost, so only the standard ones are set
/// (⌘, ⌘H ⌥⌘H ⌘Q, the Edit chords, ⌘M ⌘W). Start Dictation has none: its keyboard path is the global
/// shortcut (KeyboardShortcuts — a Carbon hotkey that takes the key before any menu sees it), so nothing
/// fires twice. The Settings shortcut recorder already refuses any chord a menu here uses
/// (`ShortcutCapturePolicy.menuShortcuts(in: NSApp.mainMenu)`).
///
/// Where the text goes: a dictation started or stopped from either menu pastes into the app the user
/// was in — the frontmost app at the stop, or, when that is JVoice itself (its menu bar, Settings, a
/// Dock click), the last other app that was frontmost since JVoice started
/// (`VoiceCoordinator.resolveTargetPID`), which is brought back for the paste; none yet → "No text field
/// focused". JVoice itself is never the target.
@MainActor
final class AppMenus: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private weak var coordinator: VoiceCoordinator?
    /// The main menu's update item, kept current while its menu is open (`observeUpdates`).
    private weak var updatesItem: NSMenuItem?
    private var updatesObservation: AnyCancellable?

    init(coordinator: VoiceCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    // MARK: - Main menu

    func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "Main Menu")

        let app = NSMenu(title: "JVoice")
        app.delegate = self   // re-reads Launch at Login before it opens (`menuNeedsUpdate`)
        app.addItem(withTitle: "About JVoice",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(dictationItem())
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(openSettings), key: ","))
        let updates = updatesMenuItem()
        app.addItem(updates)
        updatesItem = updates
        app.addItem(launchAtLoginItem())
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(submenuItem("Services", services))
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide JVoice", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
                    keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
                    keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Quit JVoice", #selector(quit), key: "q"))
        main.addItem(submenuItem("JVoice", app))

        // Standard first-responder actions (target nil): the Settings text fields — the API key, custom
        // words, app rules — need ⌘V and friends.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenuItem("Edit", edit))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
                       keyEquivalent: "")
        main.addItem(submenuItem("Window", window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(helpToursItem())
        main.addItem(submenuItem("Help", help))
        NSApp.helpMenu = help

        observeUpdates()
        return main
    }

    /// While a menu is open AppKit doesn't re-validate it: follow a check starting or ending, or a found
    /// update, live. The main queue, not `RunLoop.main`: it is serviced during menu tracking too.
    private func observeUpdates() {
        let updates = Updates.shared
        updatesObservation = updates.$pendingVersion.combineLatest(updates.$canCheck)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending, canCheck in
                guard let item = self?.updatesItem else { return }
                item.title = Updates.actionTitle(pendingVersion: pending)
                item.isEnabled = canCheck || pending != nil   // = Updates.canCheckOrShow
            }
    }

    /// The JVoice menu is about to open (or AppKit searches it for a key equivalent — on every ⌘-key while
    /// JVoice is in front): Launch at Login may have changed in System Settings → Login Items. Publishes
    /// only a change, so a ⌘V in Settings doesn't redraw it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        coordinator?.refreshLaunchAtLogin(onlyChanges: true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleDictation):
            menuItem.title = dictationTitle
            return coordinator != nil
        case #selector(toggleLaunchAtLogin):
            menuItem.state = launchAtLoginState
            return coordinator != nil
        case #selector(checkForUpdates):
            menuItem.title = Updates.shared.actionTitle
            return Updates.shared.canCheckOrShow
        default:
            return true
        }
    }

    // MARK: - Dock menu

    /// The Dock icon's right-click menu, built fresh each time the Dock asks
    /// (`NSApplicationDelegate.applicationDockMenu`). The Dock adds its own Options / Show in Finder /
    /// Hide / Quit below these items, so there's no Quit here.
    func makeDockMenu() -> NSMenu {
        coordinator?.refreshLaunchAtLogin()   // it may have changed in System Settings → Login Items
        let menu = NSMenu(title: "JVoice")
        menu.autoenablesItems = false   // each item carries its own isEnabled
        let dictation = dictationItem()
        dictation.title = dictationTitle
        menu.addItem(dictation)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings)))
        let launch = launchAtLoginItem()
        launch.state = launchAtLoginState
        menu.addItem(launch)
        menu.addItem(helpToursItem())
        let updates = updatesMenuItem()
        updates.isEnabled = Updates.shared.canCheckOrShow
        menu.addItem(updates)
        return menu
    }

    // MARK: - Items shared by both menus

    private var dictationTitle: String {
        coordinator?.hudState == .recording ? "Stop Dictation" : "Start Dictation"
    }

    private var launchAtLoginState: NSControl.StateValue {
        (coordinator?.launchAtLogin ?? false) ? .on : .off
    }

    private func dictationItem() -> NSMenuItem { item("Start Dictation", #selector(toggleDictation)) }

    private func launchAtLoginItem() -> NSMenuItem { item("Launch at Login", #selector(toggleLaunchAtLogin)) }

    /// Sparkle: the result of a check, or the update a background check found — named right in the menu
    /// ("Update Available (X)…") until the user has looked at it.
    private func updatesMenuItem() -> NSMenuItem { item(Updates.shared.actionTitle, #selector(checkForUpdates)) }

    /// "Help & Tours ▸": Take the Welcome Tour · one "<Name> Tour" per other tour · Reset All Tours.
    /// Each tour item carries its `TourID` raw value as `representedObject`.
    private func helpToursItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Help & Tours")
        submenu.autoenablesItems = false
        func addTour(_ title: String, _ tour: TourID) {
            let tourItem = item(title, #selector(replayTour(_:)))
            tourItem.representedObject = tour.rawValue
            submenu.addItem(tourItem)
        }
        addTour("Take the \(TourID.welcome.menuTitle)", .welcome)
        submenu.addItem(.separator())
        for tour in TourID.allCases where tour != .welcome {
            addTour(tour.menuTitle, tour)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Reset All Tours", #selector(resetTours)))
        return submenuItem("Help & Tours", submenu)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        coordinator?.toggleRecording()
    }

    @objc private func openSettings() {
        coordinator?.openSettingsWindow()
    }

    @objc private func checkForUpdates() {
        Updates.shared.checkForUpdates()
    }

    @objc private func toggleLaunchAtLogin() {
        guard let coordinator else { return }
        coordinator.setLaunchAtLogin(!coordinator.launchAtLogin)
    }

    /// Help & Tours: run a tour from its first step (now if its surface is on screen, otherwise the
    /// next time it appears) / forget which tours were seen. No-ops while no tour coordinator is installed.
    @objc private func replayTour(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tour = TourID(rawValue: raw) else { return }
        TourEvents.replay(tour, in: nil)
    }

    @objc private func resetTours() {
        TourEvents.resetAll()
    }

    @objc private func quit() {
        coordinator?.quitApp()
    }
}
