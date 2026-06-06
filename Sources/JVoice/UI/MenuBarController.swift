import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private weak var coordinator: VoiceCoordinator?
    private var statusItem: NSStatusItem?
    private var recordingState = false

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

    func updateRecordingState(_ isRecording: Bool) {
        recordingState = isRecording
        updateStatusButton(statusItem?.button)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let dictationTitle = recordingState ? "Stop Dictation" : "Start Dictation"
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

        let symbolName = recordingState ? "mic.fill" : "waveform"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "JVoice")
        button.image = image
        button.contentTintColor = recordingState ? .systemRed : nil
        button.appearance = NSAppearance(named: .darkAqua)
    }
}
