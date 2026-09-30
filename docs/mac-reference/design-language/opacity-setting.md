# Opacity setting + "a touch more transparent" — shared spec for MacStats, JVoice, BetterScreenshot

**Status:** spec, 2026-09-30. Being built on branch `feat/opacity-setting` in each repo (git worktrees at
`<repo>/.claude/worktrees/opacity`). Companion to `README.md` in this folder (the MacStats design language) —
read that first; this file only adds transparency rules and the setting.

Repos:
- MacStats — `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats` (reference look)
- JVoice — `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice`
- BetterScreenshot — `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot`

## The owner's request (2026-09-30, paraphrased)

"The UI looks great, but a tiny bit more transparent would look better — more like MacStats. Get what's needed
from MacStats and apply it to BetterScreenshot and JVoice so the whole ecosystem looks the same. Add a small
setting in each app (MacStats, JVoice, BetterScreenshot) to change the opacity of the UI, with a default you can
go back to."

## 1. Default look = MacStats

- **MacStats is the reference.** Its popover is the SwiftUI `MenuBarExtra(.window)` panel; its blurred background
  is drawn by the window server for the private `MenuBarExtraWindow` (no `NSVisualEffectView` in its tree — see
  `MacStats/docs/superpowers/plans/2026-09-29-polish-perf-progress.md` §5). Cards on top are `Color.primary`
  tints at 0.05 fill / 0.08 hairline (`MacStats/Sources/MacStatsApp/Design.swift`).
- **JVoice and BetterScreenshot:** at the default setting, every translucent surface should be *a touch more
  transparent* than it is on 2026-09-29, and read as the same family as the MacStats popover: thin system
  material, faint `Color.primary` card tints (≤ 0.05), 0.5 pt hairlines, no opaque slabs.
  The closest public materials to the MacStats panel are `NSVisualEffectView.Material.popover` / `.menu`
  (SwiftUI `.thinMaterial` / `.ultraThinMaterial`); compare side by side against a real MacStats screenshot
  (`MacStats/docs/design-language/assets/macstats-overview.png`, or open MacStats yourself) rather than guessing.
- **Readability floor (hard):** at the default, primary text must stay ≥ 4.5:1 contrast and secondary text
  ≥ 3:1 over the worst realistic background (a white web page for HUDs that float over other apps; a busy bright
  wallpaper for windows). BetterScreenshot measured its HUDs at 6.0–6.8:1 with a 50 % black tint and found that
  Liquid Glass adapts to what's behind it and dropped a pill to 2.4:1 — reuse its measurement method
  (`BetterScreenshot/docs/reviews/2026-09-29-native-look-review.md`), don't drop below the floor at the default.

## 2. The setting (identical in all three apps)

**What the user sees**
- A section/card titled **Appearance** (reuse an existing one if the app already has it) containing a row
  **Opacity** with a native `Slider` (0…1, continuous) whose ends are labelled with small `.caption`
  `.secondary` text **"Transparent"** (left) and **"Opaque"** (right), and a small bordered **"Default"** button
  that resets it (disabled while already at the default). One-line help text under it, e.g.
  "How much of what's behind the app shows through its windows and panels."
- Changes apply **live** to every open surface (no restart, no Apply button) and persist in `UserDefaults`.
- If the user has System Settings → Accessibility → Display → **Reduce transparency** on, surfaces are solid
  anyway (system behaviour); the slider may stay enabled but must not break that.

**What the value means (so the same slider position looks alike in all three apps)**
- Stored as a `Double` in 0…1. **Default = 0.5** in every app. Key: `uiOpacity` in the app's existing
  UserDefaults namespace (JVoice: `jvoice.app.uiOpacity`; BetterScreenshot: through its `SettingsStore`
  / `CaptureSettings` pattern like every other setting; MacStats: `uiOpacity` in the standard domain).
- 0.5 = the default look from §1.
- 1.0 = solid: the background is fully opaque (window-background colour for windows/popovers; the HUD's dark
  colour for HUDs), no see-through.
- 0.0 = as see-through as that surface can go: a thinner material and/or a lower-alpha background, **but never
  so clear that primary text over a white page drops below 3:1** — clamp per surface if needed (document the
  clamp in the code).
- Between those points interpolate smoothly (piecewise-linear 0→0.5→1 per surface is fine). Each surface keeps
  its own designed default at 0.5 — e.g. a dark HUD's tint and a Settings window's tint differ at 0.5, but
  both get more see-through to the left and more solid to the right.
- One slider per app drives **all** of that app's translucent surfaces (windows, popovers, HUD pills, toasts).
  Card tints (`cardFill` etc.) may scale gently with it but stay faint.

## 3. Implementation rules

- Touch only what the setting needs; match each repo's style; keep the change self-contained (a small
  `Appearance`/`Opacity` model + the control + the surface hooks).
- Each repo's own `CLAUDE.md` rules win (JVoice: never run the swift-testing suite locally; BetterScreenshot:
  never change the bundle id or signing).
- Verify: build, the repo's local tests, and screenshots of each surface at 0, 0.5 and 1 in light and dark,
  plus a contrast check at 0.5 and 0.
