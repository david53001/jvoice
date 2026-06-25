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
            // The color is baked into a non-template image instead of being
            // applied via `contentTintColor`: a *template* status-bar image is
            // rendered through the menu bar's vibrancy, which mutes a saturated
            // tint toward the background — on a dark menu bar the "red" came out
            // near-black and invisible. A non-template image draws its actual
            // pixels, so the red stays red on any menu bar.
            button.image = Self.recordingIcon
            button.contentTintColor = nil
            // State is otherwise signalled only by the icon color; the tooltip
            // makes it discoverable for color-blind and hover users too.
            button.toolTip = "JVoice — Recording"
        case .transcribing:
            // Cyan waveform = "working on your words" (matches the HUD's
            // transcribing accent), so the menu bar shows progress even when
            // the HUD is out of view. Baked in (non-template) for the same
            // reason as the recording mic above.
            button.image = Self.transcribingIcon
            button.contentTintColor = nil
            button.toolTip = "JVoice — Transcribing"
        case .idle:
            button.image = Self.statusIcon
            button.contentTintColor = nil
            button.toolTip = "JVoice"
        }
    }

    /// Red microphone shown while recording. See `updateStatusButton` for why
    /// the color is baked into the image rather than applied as a tint.
    private static let recordingIcon: NSImage = makeColoredSymbol(
        "mic.fill", color: .systemRed, accessibility: "JVoice — recording")

    /// Cyan waveform shown while transcribing (matches the HUD's accent).
    private static let transcribingIcon: NSImage = makeColoredSymbol(
        "waveform",
        color: NSColor(srgbRed: 0.0, green: 0.831, blue: 0.878, alpha: 1.0),
        accessibility: "JVoice — transcribing")

    /// Renders an SF Symbol as an opaque, flat-colored, **non-template** image
    /// so the menu bar draws its actual pixels (no vibrancy muting of the tint).
    static func makeColoredSymbol(_ symbolName: String, color: NSColor, accessibility: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(config)
        let size = base.map { $0.size == .zero ? NSSize(width: 18, height: 18) : $0.size }
            ?? NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let base, base.size != .zero else { return false }
            // Draw the symbol (a template alpha mask), then paint the color only
            // where the symbol is opaque — bakes a flat color into the bitmap.
            base.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibility
        return image
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
