import SwiftUI

/// Monochrome (pure black & white) design tokens — the single source of truth
/// for every JVoice surface we draw ourselves (HUD pill + Settings cards).
/// Native SwiftUI controls (segmented pickers, toggles, the shortcut recorder)
/// follow `.preferredColorScheme(colorScheme)`; these tokens cover the rest.
/// No hue anywhere — only neutral greys/black/white.
struct Theme {
    let colorScheme: ColorScheme

    // Surfaces
    let windowBackground: Color
    let surface: Color           // cards + pill body
    let inputBackground: Color
    let hairline: Color          // 1px borders / dividers

    // Content
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color

    // Pill
    let barFill: Color           // waveform bars + the "J" mark
    let pillBackground: Color
    let pillGlow: Color          // soft, even glow around the pill
    let pillDropShadow: Color

    /// Destructive affordance. Kept monochrome to honor the black/white
    /// direction; the confirmation dialog is the real safety net. (Reversible:
    /// swap to a red here if a coloured Quit/Reset is wanted later.)
    var danger: Color { textPrimary }

    static let dark = Theme(
        colorScheme: .dark,
        windowBackground: Color(white: 0.04),
        surface: Color(white: 0.075),
        inputBackground: Color(white: 0.10),
        hairline: Color.white.opacity(0.10),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.62),
        textMuted: Color.white.opacity(0.40),
        barFill: .white,
        pillBackground: Color(white: 0.05),
        pillGlow: Color.white.opacity(0.06),
        pillDropShadow: Color.black.opacity(0.45)
    )

    static let light = Theme(
        colorScheme: .light,
        windowBackground: Color(white: 0.93),
        surface: .white,
        inputBackground: Color(white: 0.96),
        hairline: Color.black.opacity(0.10),
        textPrimary: Color(white: 0.06),
        textSecondary: Color.black.opacity(0.55),
        textMuted: Color.black.opacity(0.40),
        barFill: Color(white: 0.06),
        pillBackground: .white,
        pillGlow: Color.black.opacity(0.10),
        pillDropShadow: Color.black.opacity(0.18)
    )
}

extension AppTheme {
    /// The concrete monochrome tokens for this appearance.
    var theme: Theme {
        switch self {
        case .dark:  return .dark
        case .light: return .light
        }
    }
}
