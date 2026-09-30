import Foundation

/// Settings → Appearance → **Opacity**: one 0…1 value for every translucent surface JVoice draws
/// (shared spec for MacStats, JVoice and BetterScreenshot:
/// `../MacStats/docs/design-language/opacity-setting.md` §2). 0 = as see-through as each surface may
/// go, 0.5 = the designed default look, 1 = solid. Pure (Foundation only) so
/// `scripts/run-logic-tests.sh` can check the mapping.
///
/// Every surface is a system material (the blur) with a *backing* laid over it: the surface's own solid
/// colour (`windowBackgroundColor`, which follows Light/Dark) at `backingAlpha`. 1 = fully solid; the
/// material only shows through as the alpha drops. Piecewise-linear 0 → 0.5 → 1 per surface.
enum UIOpacity {
    /// UserDefaults key (standard domain, JVoice's `jvoice.app.*` namespace).
    static let defaultsKey = "jvoice.app.uiOpacity"
    static let defaultValue = 0.5

    enum Surface {
        /// Settings, Welcome and the tour tag: a `.popover` material (the MacStats panel's family).
        case window
        /// The HUD pill: Liquid Glass (`.clear`) on macOS 26, the `.hudWindow` material before.
        case pill
    }

    /// The backing's alpha at 0 / 0.5 / 1. Measured 2026-09-30 on macOS 26.6 with `--ui-preview` over
    /// white/black backdrops (see-through = how much of the backdrop's contrast survives;
    /// `docs/opacity-progress.md`):
    /// - window: Settings' old `.sidebar` was 17 % (Dark) / 9 % (Light) see-through; `.popover` + 0.35 is
    ///   23 % / 22 % — a touch more, like the MacStats panel. 0 = the bare `.popover` (36 % / 34 %), which
    ///   still keeps primary text ≥ 3:1 over a white page (the spec's clamp), so nothing thinner is used.
    /// - pill: floats over any app, and glass re-adapts to a white page, so the backing carries the
    ///   contrast itself: 0.62 = 27 % see-through with primary text 5.1:1 / secondary 3.2:1 over white
    ///   (Dark); the 0.45 floor keeps primary at 3.5:1 even at 0 (the spec's ≥ 3:1 clamp).
    static func anchors(for surface: Surface) -> (transparent: Double, standard: Double, opaque: Double) {
        switch surface {
        case .window: return (0, 0.35, 1)
        case .pill:   return (0.45, 0.62, 1)
        }
    }

    /// The backing's alpha for `value` on `surface`.
    static func backingAlpha(_ value: Double, on surface: Surface) -> Double {
        let a = anchors(for: surface)
        let v = clamped(value)
        return v <= 0.5
            ? a.transparent + (a.standard - a.transparent) * (v / 0.5)
            : a.standard + (a.opaque - a.standard) * ((v - 0.5) / 0.5)
    }

    /// Any stored value into 0…1 (a missing or non-finite one reads as the default).
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : defaultValue
    }

    /// The stored value, or the default when the key was never written.
    static func stored(in defaults: UserDefaults) -> Double {
        (defaults.object(forKey: defaultsKey) as? NSNumber).map { clamped($0.doubleValue) } ?? defaultValue
    }
}
