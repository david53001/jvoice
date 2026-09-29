import AppKit
import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

@MainActor
final class SettingsWindow: NSWindow, TourKeysClaiming {
    /// While a shortcut row is recording, Return/Esc go to it, not to the tour tag (Esc cancels).
    var claimsTourKeys: Bool { ShortcutRecorder.activeCaptures > 0 }

    /// The title bar's ⓘ (Replay Tour · Keyboard Shortcuts). Installed in `init` so `--settings-smoke`
    /// builds and draws it too.
    private var infoButton: InfoButton?
    private var shortcutsObserver: NSObjectProtocol?

    init(coordinator: VoiceCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        isReleasedWhenClosed = false
        appearance = coordinator.appTheme.nsAppearance   // nil = follow macOS
        // A behind-window material under a transparent title bar: the desktop shows softly through.
        WindowMaterial.install(SettingsView(coordinator: coordinator), in: self, belowTitleBar: true)
        center()

        // Title-bar row, top-right. The SwiftUI header's appearance picker sits below the title bar — the
        // hosting view keeps content inside the safe area (measured 2026-09-28 on macOS 26: title bar
        // 32 pt, window grows to 592 tall; the ⓘ sits 5–27 pt from the top, the picker starts at ~50 pt).
        let info = InfoButton.install(in: self, tour: .settings, shortcuts: Self.infoShortcuts())
        info.tourAnchor = "settings.help"
        infoButton = info
        // KeyboardShortcuts stores chords in UserDefaults: follow a change made in the recorder rows.
        shortcutsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak info] _ in
            MainActor.assumeIsolated { info?.shortcuts = Self.infoShortcuts() }
        }
    }

    func show() {
        // Accessory (LSUIElement) apps don't auto-activate when ordering a
        // window front — without this the window opens behind whatever app
        // currently owns the foreground.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        // The Settings tour's first time; a no-op unless tours are on and it hasn't been seen.
        TourEvents.surfaceShown(.settings, in: self)
    }

    /// The ⓘ's Keyboard Shortcuts list: the two global chords, as currently set (unset ones left out).
    static func infoShortcuts() -> [(keys: String, action: String)] {
        #if canImport(KeyboardShortcuts)
        let actions: [(name: KeyboardShortcuts.Name, title: String)] = [
            (.toggleRecording, "Toggle Recording"),
            (.undoLastPaste, "Undo Last Paste"),
        ]
        return actions.compactMap { action in
            KeyboardShortcuts.getShortcut(for: action.name).map { (keys: $0.description, action: action.title) }
        }
        #else
        return []
        #endif
    }
}
