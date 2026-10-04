# Opacity setting — progress note (2026-09-30) — DONE, committed on `feat/opacity-setting`

**What:** Settings → Appearance → **Opacity** slider (0 = Transparent … 1 = Opaque, **Default** = 0.5,
live, stored as the `Double` UserDefaults key `jvoice.app.uiOpacity` in the app's standard domain
`com.jvoice.app`), plus JVoice's translucent surfaces made "a touch more transparent", like David's
MacStats menu-bar app. Shared spec for all three apps (MacStats, JVoice, BetterScreenshot):
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/.claude/worktrees/opacity/docs/design-language/opacity-setting.md`
(§1 default look + readability floor, §2 the setting).

**Where:** git worktree `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/opacity`,
branch `feat/opacity-setting`, based on `feat/native-look` (= shipped v1.1.4). Not merged, not pushed,
not installed (`./scripts/dev-install.sh` is for David / the lead).

Rules that applied: NEVER `swift test` on this Mac (it crashed the machine — `CLAUDE.md`); builds ran
under `lockf /private/tmp/claude-501/-Users-davidghermansteinberg/75e0c0dc-9b20-4d54-8e2a-8e24a75c43e0/scratchpad/swift-build.lock <cmd>`
(a lock shared with parallel agents). System appearance was Dark at start and was never changed
(previews force Light/Dark per window).

## Terms
- **Material** — a system blur of what's behind a window (`NSVisualEffectView`); **Liquid Glass** — macOS 26's
  glass material (SwiftUI `.glassEffect`).
- **Backing** — this feature's solid layer on top of the material: `windowBackgroundColor` (follows
  Light/Dark) at an alpha set by the slider. 1 = solid; lower = more of the material shows.
- **See-through %** — (surface brightness over a white backdrop − over a black backdrop) / 255.
- **Contrast N:1** — WCAG 2.x contrast ratio (AA minimum 4.5:1 for normal text).

## Surfaces (before → after, at the default 0.5)
| Surface | Before (v1.1.4) | After |
|---|---|---|
| Settings + Welcome windows (`UI/Components/VisualEffectBackground.swift` `WindowMaterial.install`) | `.sidebar` material: 17 % see-through Dark / 9 % Light | `.popover` + backing 0.35: 23 % / 22 % |
| Tour tag bubble (`Tours/Kit/TagViews.swift`) | bare `.popover` | `.popover` + the same window backing (matches Settings) |
| HUD pill, macOS 26 (`UI/HUDView.swift` `PillMaterial`) | `.regular` Liquid Glass as the content's own effect: ~30 % see-through Dark, but over a white page it re-tinted itself AND its text light within ~1 s | `.clear` glass as a layer BEHIND the content + backing 0.62: 27 % / 26 %, steady (no flip), red stop stays red |
| HUD pill, macOS 14/15 fallback (`JVOICE_HUD_MATERIAL=1`) | `.hudWindow` material (≈ 59 % see-through Dark — white text ≈ 2:1 over white) | same material + backing 0.62 |
| Cards / inputs / hairlines (`UI/Theme.swift` `Design`) | `Color.primary` 0.04 / 0.06, 0.5 pt 0.08 hairline | unchanged (already ≤ 0.05, MacStats family) |
| ⓘ popover, menu-bar menu | system | unchanged |

Mapping (`Sources/JVoice/UI/UIOpacity.swift`, piecewise-linear 0 → 0.5 → 1):
- windows/tag backing alpha: **0 → 0.35 → 1**
- pill backing alpha: **0.45 → 0.62 → 1** (0.45 = readability clamp: the pill floats over white pages)

## Measurements (macOS 26.6.2, `--ui-preview` captures; scripts in the scratchpad, see below)
See-through % (Dark / Light): windows 36/34 at 0, 23.5/22 at 0.5, 0/0 at 1; pill 39/37, 27/26, 0/0.

Contrast over a **white** page (worst case), Dark appearance:
- Pill primary ("Pasted", error text): **3.5:1 at 0**, **5.1:1 at 0.5**, 12.5:1 at 1 (steady at 0.5/2/5 s);
  secondary (preparing-model caption): 2.4 at 0, **3.2 at 0.5**, 6.1 at 1. Light: primary ≥ 14:1, secondary ≈ 3.8.
  Pre-26 fallback pill: 4.8:1 at 0, 6.3:1 at 0.5.
  (Old pill over white: flipped to a light capsule with black text — readable, 19.8:1, but not dark any more.)
- Settings: primary 3.7:1 at 0, 5.8:1 at 0.5; secondary 4.0 / 4.8. Light ≥ 7:1 / ≥ 4.4:1.
- Over a bright wallpaper (`Mac Yellow.heic`) at 0.5: primary 7.3 (Dark) / 7.2 (Light), secondary 5.7 / 4.9.
Method: body colour = most common colour in a box; text = the pixel in the box that differs most (glyph core).

Screenshots: `/private/tmp/claude-501/-Users-davidghermansteinberg/75e0c0dc-9b20-4d54-8e2a-8e24a75c43e0/scratchpad/jvoice/final/<backdrop>-<opacity>/`
(`wallpaper|white|black` × `0|0.5|1`, plus `white-0.5-pre26pill`, `white-0-pre26pill`); baseline (v1.1.4 look,
emulated) in `…/jvoice/base-white`, `base-black`, `base-wall`; contact sheets `…/jvoice/sheet-*.png`;
scripts `…/jvoice/analyze.py`, `seethrough.py`, `wincontrast.py`, `assemble.sh`. (Scratchpad = temporary.)

Reproduce: assemble the `.app` (recipe in `Sources/JVoice/UI/CLAUDE.md`), then
`"$APP/Contents/MacOS/JVoice" --ui-preview <dir> --opacity 0.5 --backdrop white --active --hud-timeline`.

## Findings worth keeping
- `screencapture` fails in agent shells (no Screen Recording permission). In-process
  `CGWindowListCreateImage` (looked up with `dlsym`; unavailable to Swift in the macOS 15 SDK) captures the
  app's own windows with their behind-window blur — `--ui-preview` now uses it.
- `.regular` Liquid Glass adapts to a white page by turning light and flipping its *content's* colours;
  a SwiftUI backing drawn as glass content gets flipped too. `.clear` glass does not flip, and putting
  the glass on a separate background layer keeps content colours exact (the red stop was washed pink as
  glass content).
- The value lives in `UIOpacityStore` (an `ObservableObject`) rather than `@AppStorage`: AppKit views need a publisher, and KVO-based observation reads the dots in `jvoice.app.uiOpacity` as a key path (not tested).

## Not verified
- The live app (hotkey pill over real apps, Settings while key over a real wallpaper, slider dragging).
- The windows' material is captured with `--active` (forced active state); the real inactive state
  (window not key) is more opaque by system design and was not changed.
- Reduce Transparency on: not toggled (it's a system setting) — materials go solid by themselves; the
  backing only adds the same colour, so nothing should break.

## Possible follow-ups (not done)
- "Restore Default Settings…" does not reset Opacity (it's its own key; the card's Default button does).
- At 0 in Dark over a bright wallpaper the small red footer buttons get low contrast (allowed: the spec
  only clamps primary text at 0).
