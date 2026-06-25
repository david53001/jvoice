import AppKit
import SwiftUI

@MainActor
final class SettingsWindow: NSWindow {
    init(coordinator: VoiceCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        isReleasedWhenClosed = false
        center()
        contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator))
    }

    func show() {
        // Accessory (LSUIElement) apps don't auto-activate when ordering a
        // window front — without this the window opens behind whatever app
        // currently owns the foreground.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
