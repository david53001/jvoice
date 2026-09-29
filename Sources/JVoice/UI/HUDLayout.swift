import AppKit

enum HUDLayout {
    /// The capsule's corner radius (half its height).
    static let pillCorner: CGFloat = 28
    static let pillHeight: CGFloat = 56
    static let pillMinWidth: CGFloat = 240

    /// Transparent margin around the capsule INSIDE the panel, so the panel's soft system shadow
    /// (`HUDWindow.hasShadow`) and the stop button's press never clip at the window edge.
    static let shadowPadding: CGFloat = 16

    /// The capsule's distance from the bottom of the screen's visible frame (above the Dock).
    static let bottomGap: CGFloat = 64

    static func minimumSize(for state: HUDState) -> NSSize {
        NSSize(width: pillMinWidth + shadowPadding * 2,
               height: pillHeight + shadowPadding * 2)
    }
}
