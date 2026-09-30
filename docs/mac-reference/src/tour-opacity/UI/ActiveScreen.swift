import AppKit

extension NSScreen {
    /// The display the user is working on: the one under the mouse pointer (where they just clicked the
    /// menu-bar J, or where they're dictating). `NSScreen.main` is the screen of JVoice's own key window —
    /// for a menu-bar app with no window open that's the primary display, so windows used to open there
    /// even when the user was on another monitor (David, 2026-09-30).
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }
}

extension NSWindow {
    /// Centres the window on the display the user is on (`NSScreen.underMouse`) when it's about to
    /// appear, like `center()` (a bit above the middle) but on that display, not the primary one.
    /// An already-visible window stays where it is.
    func centerOnActiveScreen() {
        guard !isVisible, let area = NSScreen.underMouse?.visibleFrame else { return }
        let size = frame.size
        let x = area.midX - size.width / 2
        // `center()`'s placement: a third of the leftover height above, two thirds below.
        let y = area.minY + max(0, area.height - size.height) * 2 / 3
        setFrameOrigin(NSPoint(x: x.rounded(), y: min(y, area.maxY - size.height).rounded()))
    }
}
