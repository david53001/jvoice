import AppKit
import SwiftUI

/// Native macOS design tokens (the MacStats design language —
/// `../MacStats/docs/design-language/README.md`). Every surface JVoice draws itself sits on a system
/// material (the window/pill backdrop) and uses *tints* of `Color.primary` on top of it, so the blur
/// shows through and light/dark adapt by themselves. Opacities live in `Design`.
struct Theme {
    /// The explicit appearance override, or nil to follow macOS (`AppTheme.system`).
    let colorScheme: ColorScheme?

    // Surfaces — tints over the material, never solid fills.
    var surface: Color { Color.primary.opacity(Design.cardFill) }
    var inputBackground: Color { Color.primary.opacity(Design.inputFill) }
    /// Borders and dividers, drawn at `Design.hairlineWidth`.
    var hairline: Color { Color.primary.opacity(Design.cardHairline) }

    // Content
    var textPrimary: Color { .primary }
    var textSecondary: Color { .secondary }
    var textMuted: Color { Color(nsColor: .tertiaryLabelColor) }

    /// Waveform bars + the "J" mark.
    var barFill: Color { .primary }

    /// Destructive affordance (Apple convention).
    var danger: Color { .red }

    static let native = Theme(colorScheme: nil)
}

/// Sizes and opacities, copied from MacStats' `Design.swift` (design-language README §2).
enum Design {
    /// Content cards in a regular window (System Settings' grouped sections are ~10).
    static let cardCornerRadius: CGFloat = 10
    /// Card surface — a touch more transparent than MacStats' 0.05, as asked.
    static let cardFill: Double = 0.04
    static let cardHoverFill: Double = 0.085
    static let cardPressedFill: Double = 0.12
    static let cardHairline: Double = 0.08
    static let hairlineWidth: CGFloat = 0.5
    static let inputFill: Double = 0.06
    /// Rows inside a card (transcripts, words) under the pointer.
    static let rowHoverFill: Double = 0.07
    static let rowCornerRadius: CGFloat = 6
    /// Small secondary buttons (`SubtleButtonStyle`).
    static let smallButtonFill: Double = 0.08
    static let smallButtonHoverFill: Double = 0.12
    static let smallButtonPressedFill: Double = 0.16
    static let smallButtonRadius: CGFloat = 6
    static let smallButtonHeight: CGFloat = 24
}

extension AppTheme {
    /// The tokens for this appearance (they only differ in the override).
    var theme: Theme {
        switch self {
        case .system: return .native
        case .dark:   return Theme(colorScheme: .dark)
        case .light:  return Theme(colorScheme: .light)
        }
    }

    /// The AppKit appearance to force on a window, or nil to follow macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark:   return NSAppearance(named: .darkAqua)
        case .light:  return NSAppearance(named: .aqua)
        }
    }
}
