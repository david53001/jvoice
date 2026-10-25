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
    /// Closing only orders this window out (`isReleasedWhenClosed = false`), so the SwiftUI tree lives
    /// on; this tells it (`\.windowOnScreen`) when nobody can see it, and the glow stops ticking.
    private let visibility = WindowVisibility()
    private var occlusionObserver: NSObjectProtocol?

    init(coordinator: VoiceCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            // Resizable (David, 2026-10-17): drag any edge/corner, double-click the title bar to fill
            // the screen (macOS "zoom", or whatever the user set in Desktop & Dock), the green button too.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        isReleasedWhenClosed = false
        appearance = coordinator.appTheme.nsAppearance   // nil = follow macOS
        // A behind-window material under a transparent title bar: the desktop shows softly through.
        let hosting = WindowMaterial.install(
            OnScreenGate(visibility: visibility, content: SettingsView(coordinator: coordinator)),
            in: self, belowTitleBar: true)
        // Only the SwiftUI MINIMUM becomes a constraint: its intrinsic (ideal) size would pin the window
        // and stop the user resizing it. Then open at the designed 700 × 560 (+ the title bar).
        hosting.sizingOptions = [.minSize]
        let titleBar = frame.height - contentLayoutRect.height
        setContentSize(NSSize(width: 700, height: 560 + titleBar))
        contentMinSize = NSSize(width: SettingsView.minWindowWidth, height: SettingsView.minWindowHeight + titleBar)
        center()
        // The green button fills the screen like the double-click, instead of opening a full-screen Space.
        collectionBehavior.insert(.fullScreenNone)
        if let zoomButton = standardWindowButton(.zoomButton) {
            zoomButton.target = self
            zoomButton.action = #selector(toggleFill(_:))
        }

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
        // The notification only reports changes, so start from the real state (not yet shown = off
        // screen); otherwise a window that is never visible would keep the default and tick forever.
        syncVisibility()
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncVisibility() }
        }
    }

    private func syncVisibility() {
        let onScreen = occlusionState.contains(.visible)
        if visibility.isOnScreen != onScreen { visibility.isOnScreen = onScreen }
    }

    // MARK: Fill the screen / back (title-bar double-click, green button)

    /// The size to go back to after "fill the screen".
    private var frameBeforeFill: NSRect?

    /// Fills the screen's visible area, or — when already filling it — goes back to the size before.
    /// Ours rather than AppKit's `zoom`: under this window's transparent, full-size-content title bar
    /// the system double-click never reached the zoom (David, 2026-10-17), and the green button
    /// would open a separate full-screen Space instead.
    @objc func toggleFill(_ sender: Any? = nil) {
        guard let area = screen?.visibleFrame else { return }
        let filling = abs(frame.width - area.width) < 2 && abs(frame.height - area.height) < 2
        if filling, let previous = frameBeforeFill {
            setFrame(previous, display: true, animate: true)
            frameBeforeFill = nil
        } else {
            frameBeforeFill = frame
            setFrame(area, display: true, animate: true)
        }
    }

    override func zoom(_ sender: Any?) { toggleFill(sender) }

    /// A double-click on the title bar (not on its buttons) does what the user chose in System Settings
    /// → Desktop & Dock → "Double-click a window's title bar to": fill/zoom (the default) or nothing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2,
           event.locationInWindow.y >= contentLayoutRect.maxY,
           !isOverTitleBarControl(event.locationInWindow) {
            let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
            if action != "None" && action != "Minimize" {
                toggleFill()
                return
            }
        }
        super.sendEvent(event)
    }

    private func isOverTitleBarControl(_ point: NSPoint) -> Bool {
        // The frame view holds every title-bar view: the traffic lights and the ⓘ accessory.
        guard let root = contentView?.superview,
              let hit = root.hitTest(root.convert(point, from: nil)) else { return false }
        return hit is NSControl || hit.superview is NSControl
    }

    func show() {
        // Opened from the Dock menu, Help & Tours or a tour, JVoice isn't
        // active — without this the window opens behind whatever app
        // currently owns the foreground. (A Dock click activates it anyway.)
        NSApp.activate(ignoringOtherApps: true)
        centerOnActiveScreen()   // on the display the user is on, not always the primary one
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

/// Whether the Settings window is on screen (its occlusion state), for `\.windowOnScreen`.
@MainActor
private final class WindowVisibility: ObservableObject {
    @Published var isOnScreen = true
}

/// Hands `WindowVisibility` to the Settings tree as `\.windowOnScreen`.
private struct OnScreenGate<Content: View>: View {
    @ObservedObject var visibility: WindowVisibility
    let content: Content

    var body: some View {
        content.environment(\.windowOnScreen, visibility.isOnScreen)
    }
}
