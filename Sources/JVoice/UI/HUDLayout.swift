import AppKit

enum HUDLayout {
    static let pillCorner: CGFloat = 28
    static let pillHeight: CGFloat = 56
    static let pillMinWidth: CGFloat = 240

    /// Transparent margin around the pill INSIDE the window, so the soft glow
    /// fades out fully before the window edge. The old square-glow bug came
    /// from sizing the window to the pill's `fittingSize`, which excludes shadow
    /// blur — the blur then clipped at the window border. This padding must
    /// exceed the largest glow radius used in HUDView (28) plus any offset.
    static let glowPadding: CGFloat = 40

    static func minimumSize(for state: HUDState) -> NSSize {
        NSSize(width: pillMinWidth + glowPadding * 2,
               height: pillHeight + glowPadding * 2)
    }
}
