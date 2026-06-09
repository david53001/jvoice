import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// What the status item should communicate at a glance.
    enum Activity {
        case idle
        case recording
        case transcribing
    }

    private weak var coordinator: VoiceCoordinator?
    /// `private(set)` (not `private`) so `@testable` icon-state tests can read
    /// back the button's image/tint after `updateActivity`.
    private(set) var statusItem: NSStatusItem?
    private var activity: Activity = .idle

    init(coordinator: VoiceCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        guard let button = item.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "JVoice"
        updateStatusButton(button)
    }

    func updateActivity(_ activity: Activity) {
        guard activity != self.activity else { return }
        self.activity = activity
        updateStatusButton(statusItem?.button)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let dictationTitle = activity == .recording ? "Stop Dictation" : "Start Dictation"
        menu.addItem(menuItem(dictationTitle, #selector(toggleDictation)))

        menu.addItem(.separator())

        menu.addItem(menuItem("Settings…", #selector(openSettings)))

        let launchItem = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        launchItem.state = (coordinator?.launchAtLogin ?? false) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        menu.addItem(menuItem("Quit JVoice", #selector(quit)))
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleDictation() {
        coordinator?.toggleRecording()
    }

    @objc private func openSettings() {
        coordinator?.openSettingsWindow()
    }

    @objc private func toggleLaunchAtLogin() {
        guard let coordinator else { return }
        coordinator.setLaunchAtLogin(!coordinator.launchAtLogin)
    }

    @objc private func quit() {
        coordinator?.quitApp()
    }

    private func updateStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }

        switch activity {
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "JVoice — recording")
            button.contentTintColor = .systemRed
            // State is otherwise signalled only by tint color; the tooltip
            // makes it discoverable for color-blind and hover users too.
            button.toolTip = "JVoice — Recording"
        case .transcribing:
            // Cyan waveform = "working on your words" (matches the HUD's
            // transcribing accent), so the menu bar shows progress even when
            // the HUD is out of view.
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "JVoice — transcribing")
            button.contentTintColor = NSColor(srgbRed: 0.0, green: 0.831, blue: 0.878, alpha: 1.0)
            button.toolTip = "JVoice — Transcribing"
        case .idle:
            button.image = Self.statusIcon
            button.contentTintColor = nil
            button.toolTip = "JVoice"
        }
    }

    /// The product mark: a bold "J", rendered as a template image so the
    /// system tints it like a native status item (black on light menu bars,
    /// white on dark ones).
    private static let statusIcon: NSImage = makeStatusIcon()

    static func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 15, weight: .bold)
            let string = NSAttributedString(string: "J", attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ])
            let glyphSize = string.size()
            string.draw(at: NSPoint(
                x: (rect.width - glyphSize.width) / 2,
                y: (rect.height - glyphSize.height) / 2
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
