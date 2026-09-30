import AppKit
import SwiftUI

enum HUDLayout {
    /// The capsule's corner radius (half its height).
    static let pillCorner: CGFloat = 28
    static let pillHeight: CGFloat = 56
    /// The recording / transcribing capsule (J · waveform · stop). Status pills hug their content.
    static let pillMinWidth: CGFloat = 240
    /// A status pill's text wraps (≤ 2 lines) beyond this capsule width.
    static let pillMaxWidth: CGFloat = 360

    /// Transparent margin around the capsule INSIDE the panel, so its soft shadow (radius 10, 4 pt
    /// down — `PillShadow` in HUDView) fades out before the window edge instead of clipping square.
    static let shadowPadding: CGFloat = 22

    /// The capsule's distance from the bottom of the screen's visible frame (above the Dock).
    static let bottomGap: CGFloat = 64

    /// How one pill turns into the next (recording → transcribing → Pasted): the capsule resizes with
    /// this while the contents cross-fade. Subtle, no bounce.
    static let morph: Animation = .snappy(duration: 0.3)
    /// When the panel shrinks to the new capsule — after the morph has finished.
    static let morphSettleDelay: TimeInterval = 0.35

    /// The smallest panel: an empty capsule's height plus the shadow margin.
    static let minimumSize = NSSize(width: pillHeight + shadowPadding * 2,
                                    height: pillHeight + shadowPadding * 2)
}
