# BetterScreenshot → native macOS look (MacStats design language) — redesign spec

**Status:** spec only, not started (written 2026-09-29). Nothing in the BetterScreenshot repo has been changed.
**App:** BetterScreenshot, a CleanShot-X-style macOS screenshot/recording app, repo
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot` (SwiftPM + Command Line Tools only,
deployment target macOS 14; app code in `App/`, local packages in `Packages/` — CaptureKit, OverlayKit, EditorKit,
RecordingKit, HistoryKit, TourKit, TestKit).
**Design language to apply:** `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/README.md`
— read it first (tokens, components, motion, materials, toolchain rules). Reference screenshot:
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/assets/macstats-overview.png`.

## 0. Why, and what this changes

The user (the app's owner) wants BetterScreenshot to look like a native Mac app — "slightly transparent", squircle
(continuous-corner) cards, simple lines and text — like their MacStats menu-bar app, and consistent with the same
restyle planned for their JVoice app (`.../MacStats/docs/design-language/jvoice-native-redesign.md`).

### Standing decisions this touches — read before starting
The repo has deliberate, documented choices. This spec **changes some of them at the owner's request (2026-09-29)**
and **keeps others**. Record each change in the named doc when implementing.

| Standing decision | Where recorded | This spec |
|---|---|---|
| Settings = pure-black 960 pt "JVoice" masonry, white as the only accent, glowing-dot card headers, forced dark | `docs/WINDOWS-TO-MAC-PARITY.md` Part 1 §1.1–1.10 (it was copied from JVoice, which is itself being restyled) | **Changes**: translucent material, system accent, no dots, follows system appearance (§1.3 of that doc explicitly left this open as "a deliberate later change"). |
| Floating HUD surfaces forced dark (`.vibrantDark`) + 40 % black tint for contrast | `docs/reviews/2026-09-25-ui-review.md` C1, `RecordingHUDStyle.swift:3-9` | **Keeps dark + contrast guarantee**; only shape/material recipe changes (continuous corners, 0.5 pt hairline, glass on macOS 26). Apple's own HUDs are dark too. |
| Editor + trim window forced dark (light mode broke contrast, review E2) | review E2 | **Keeps dark**; replaces flat grey with a dark translucent material. |
| Quick Access card scrim/sample contrast argument | `CLAUDE.md` ("do not narrow the scrim or widen the sample…"), `QuickAccessContrast.swift` | **Keeps untouched** — corners and hover only. |
| Tour tags bright red `#C62D22` for 5.5:1 contrast | `Packages/TourKit/.../TagStyle.swift:11` | **Keeps the red**; corners become continuous. |
| New-user-only tours rule; Background/wallpaper styling dropped (2026-06-05) | `CLAUDE.md` | Untouched; don't re-propose. |
| Every UI change updates the Windows parity doc | `docs/MAC-TO-WINDOWS-PARITY-v3.md` (spec §12) | **Required** for every phase below. |

### Before you start — coordinate
- At the time of writing the repo was on branch `ocr-structure-math` with uncommitted Capture-Text work and several
  agent worktrees under `.claude/worktrees/` — other sessions were active. Do this on its own branch
  (e.g. `feat/native-look`) from `main`, touch no other session's worktree, and expect to rebase.
- Read `CLAUDE.md`, `docs/BUILD-NOTES.md`, `docs/reviews/2026-09-25-ui-review.md` and
  `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md` §2 first.
- CI (`.github/workflows/ci.yml`) runs `swift build` on `macos-15`, which may lack the macOS 26 SDK → wrap every
  Liquid Glass call in `#if compiler(>=6.2)` **and** `if #available(macOS 26, *)` with the `NSVisualEffectView`
  fallback (precedent for SDK-guarding: `TrimExporter.swift:77`).

## 1. Current state (summary; file:line as of 2026-09-29)

Three visual languages coexist:
1. **Pure-black custom Settings** — `App/Settings/SettingsWindowController.swift:38-61` (`backgroundColor = .black`,
   forced `.darkAqua`), `SettingsView.swift`, `SettingsTheme.swift:31-103` (hex solids `#000000`, `#0E0E0E` cards,
   white accent, fixed 10–18 pt fonts), custom components in `App/Settings/Components/` (`DarkSection` with a
   **glowing dot** card header `DarkSection.swift:20`, `MonoSwitchStyle`, `SegmentedControl` via
   `UnevenRoundedRectangle` without `style:`, `PillButtonStyle`/`AccentButtonStyle`, `MonoSlider`,
   `MonoComboField`, `MonoPathField`, `InfoTip` with a *serif* ⓘ).
2. **Dark blurred "HUD" floating surfaces** — two duplicated recipes, `Packages/OverlayKit/Sources/OverlayKit/HUDStyle.swift:8-40`
   and `Packages/RecordingKit/Sources/RecordingKit/RecordingHUDStyle.swift:10-47` (`.hudWindow`, `.vibrantDark`,
   40 % black tint, 1 pt white-10 % border, **circular** `layer.cornerRadius`); repeated inline without the tint in
   the editor tool pill (`EditorWindowController.swift:173-182`), inspector (`EditorInspectorView.swift:87-95`) and
   trim card (`TrimWindowController.swift:186-196`).
3. **Stock system UI** — History (SwiftUI, `App/History/HistoryWindowController.swift`), onboarding
   (`App/MenuBar/OnboardingController.swift`), the menu (`App/MenuBar/MenuBarController.swift`), ⓘ popovers.

**Nothing uses continuous corners** (`.continuous` / `cornerCurve`) and nothing uses Liquid Glass yet.
Radii in use: 24 countdown · 20 pill · 15 tool pill · 14 Quick Access · 12 inspector/strip/trim/tag · 11 switch ·
10 Settings card/keystroke · 9 tool highlight · 8 History cell/timeline · 7 buttons/segments · 6 chips/thumbs ·
5 · 3.5 checkbox · 1.5 meter bars. Hard-coded window greys: Settings `.black`, editor `NSColor(white: 0.12)`
(`EditorWindowController.swift:52,90`), trim `NSColor(white: 0.09)` (`TrimWindowController.swift:127`).
Keystroke overlay is a flat black 75 % box (`KeystrokeOverlayController.swift:26-50`).

## 2. Target look

- **Settings** looks like the MacStats popover grown into a window: a **slightly translucent** behind-window
  material, inset cards with a faint `Color.primary` tint, 0.5 pt hairline, continuous 10 pt corners, **no dots**,
  `.caption2` semibold secondary section labels, native controls with the system accent, system light/dark.
- **Floating controls** (tool pill, inspector, record strip, recording pill, toast, countdown, size chip, keystroke
  overlay) share **one** dark HUD recipe with continuous corners and hairlines — on macOS 26 as Liquid Glass (these
  are exactly the "floating control layer" glass is for), with the current tinted blur as the fallback.
- **Editor/trim windows** stay dark (Photos/Final-Cut style) but their backdrop becomes a dark translucent material,
  not flat grey.
- Everything rounded is a squircle, concentric where nested.

## 3. Work plan (phased; each phase shippable alone; each updates `docs/MAC-TO-WINDOWS-PARITY-v3.md`)

### Phase 1 — Shared design primitives (new, small)
There's no shared UI module (RecordingKit doesn't depend on OverlayKit, hence the duplicate HUD style). Add a tiny
local package **`Packages/DesignKit`** (AppKit + SwiftUI, no dependencies) and depend on it from OverlayKit,
RecordingKit, EditorKit, TourKit and the App target. Contents:
- `Design` tokens (the MacStats table, design-language README §2): card fill 0.05 (0.04 if the owner wants more
  transparency), hover 0.085, pressed 0.12, hairline 0.08 @ 0.5 pt, radii.
- `HUDSurface` — the single floating-surface recipe, replacing both `HUDStyle` and `RecordingHUDStyle`:
  ```swift
  /// Dark floating-control surface. macOS 26: Liquid Glass (NSGlassEffectView, dark appearance);
  /// earlier: .hudWindow behind-window blur + the 40 % black tint that review C1 measured as
  /// necessary for white-text contrast. Continuous corners, 0.5 pt white-10 % hairline.
  public enum HUDSurface {
      public static func make(cornerRadius: CGFloat) -> NSView { … }
  }
  ```
  On 26: `NSGlassEffectView` with `cornerRadius`, `appearance = .darkAqua`; **re-measure white-text contrast over
  a white page** (review C1 method) — if glass alone is below 4.5:1, add the same 40 % tint (`tintColor`) and keep it.
  Fallback: today's recipe + `layer.cornerCurve = .continuous` + 0.5 pt border.
- `ContinuousPath` — `NSBezierPath`/`CGPath` for a continuous rounded rect, for the hand-drawn shapes that
  currently use `NSBezierPath(roundedRect:xRadius:yRadius:)`:
  ```swift
  public func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
      RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
  }
  ```
  (SwiftUI `Path.cgPath` works on macOS 14; wrap with `NSBezierPath(cgPath:)` where an `NSBezierPath` is needed.)
- SwiftUI `CardBackground`, `CardButtonStyle`, `SubtleButtonStyle` copied from MacStats
  (`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/Sources/MacStatsApp/StatCard.swift`).
- `WindowMaterial` — `NSViewRepresentable`/`NSView` for a behind-window `NSVisualEffectView` backdrop.

### Phase 2 — Settings (biggest win; `App/Settings/`)
1. **Window** (`SettingsWindowController.swift:38-61`): drop `backgroundColor = .black` and the forced `.darkAqua`
   (follow system; keep `titlebarAppearsTransparent`). Content view = `NSVisualEffectView`
   (`material = .sidebar` — or `.underWindowBackground` if too see-through — `blendingMode = .behindWindow`,
   `state = .followsWindowActiveState`) with the `NSHostingView` pinned inside.
2. **Cards** (`DarkSection.swift`): delete the glowing dot and its white shadow (`:20`); header =
   `.caption2` semibold `.secondary` uppercase (no custom kerning/size); background = `CardBackground`, radius
   **10** `.continuous`, 0.5 pt hairline instead of 1 pt `#2A2A2A`.
3. **Tokens** (`SettingsTheme.swift`): replace hex solids with semantic values — text `.primary/.secondary/.tertiary`,
   surfaces `Color.primary.opacity(…)`, accent = `Color.accentColor`. Replace `SettingsTheme.Font` fixed sizes with
   text styles (`.headline` page title, `.body`/`.callout` rows, `.caption` sub-labels). Remove inline literals such
   as `Color(rgb: 0x0A0A0A)` (`PillButtons.swift:36`, `MonoControls.swift:124`).
4. **Controls → native** (the custom ones existed only to invert colours for pure black; with the system accent
   they're unnecessary):
   - `MonoSwitchStyle` → `Toggle` `.toggleStyle(.switch)` `.controlSize(.small)`.
   - `SegmentedControl` → `Picker` `.pickerStyle(.segmented)` (or, if kept, `UnevenRoundedRectangle(…, style: .continuous)`).
   - `PillButtonStyle` / `AccentButtonStyle` → `.bordered` / `.borderedProminent`, destructive with `role: .destructive`.
   - `MonoSlider` → `Slider` (keep the stop-index behaviour of `OverlayDismissScale`/`TempFileRetentionScale` and the `∞` label).
   - `MonoComboField` / `MonoPathField` → `Picker(.menu)` / a `TextField(.roundedBorder)` + "Choose…" `.bordered` button.
   - `InfoTip` ⓘ: SF `info.circle` (not serif), `.secondary`, native `.popover`.
   - Replace the `.confirmationDialog` at `SettingsView.swift:214` with `NSAlert` (reliable in an accessory app).
5. **Layout**: keep the 3-column masonry if the owner likes it, but with MacStats spacing (outer 20, gutter 12,
   card gap 12, card padding 12). The window stays 960 wide.

### Phase 3 — One HUD recipe everywhere (squircles + glass)
Swap every floating surface to `HUDSurface` (Phase 1):
- OverlayKit: toast `HUDController.swift:21-62` (capsule), size chip in `SelectionOverlayController.swift:139-167`
  (radius 6), window-picker title chip `WindowPickerController.swift:105-137` (now black 60 % → `HUDSurface` r6),
  Quick Access recording badge, Pin close button (circle).
- RecordingKit / App recording: record strip `RecordStripController.swift:78-117` (r12), live pill
  `RecordingControlsController.swift:55-66` (r20 capsule) + hover-hint bubble (r7), countdown
  `CountdownOverlayController.swift:29-45` (r24), keystroke overlay `KeystrokeOverlayController.swift:26-50`
  (flat black 75 % → `HUDSurface` r10).
- Inner controls: every `layer.cornerRadius` gets `cornerCurve = .continuous`; `ChoiceControl` segments r7/r5,
  icon buttons r7, meter bars; hover fill white 12–13 % stays (it's on a dark surface).
- Delete `HUDStyle.swift` and `RecordingHUDStyle.swift` once nothing references them (resolves the leftover in
  `docs/PROGRESS-v3.md:65-69`).

### Phase 4 — Editor & trim windows
- Editor (`Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`): keep `.darkAqua` (review E2), but
  replace `backgroundColor = NSColor(white: 0.12)` with a dark behind-window `NSVisualEffectView`
  (`.underWindowBackground` or `.hudWindow`) behind the canvas scroll view, so it's slightly translucent like the
  rest. The image canvas itself stays opaque.
- Tool pill (`:172-208`, `EditorChrome.swift:10-65`) and inspector (`EditorInspectorView.swift:85-130`): these float
  over content → `HUDSurface` (glass on 26); radii 15 / 12 continuous; 0.5 pt hairline; tool-selection highlight
  (r9, accent) via `ContinuousPath` if hand-drawn.
- Inspector typography (`EditorChrome.swift:105-194`, `InspectorStyle`): 10 pt uppercase 45 %-white captions →
  `.caption2` semibold `secondaryLabelColor`; 12 pt row labels → `.callout`; keep mono-digit slider values.
- Bottom bar (`.headerView` + `separatorColor`) is already native — keep; on 26 consider a glass toolbar.
- Trim window (`Packages/RecordingKit/Sources/RecordingKit/TrimWindowController.swift`): same as the editor
  (dark material instead of `NSColor(white: 0.09)`, control card = `HUDSurface` r12). `CutTimelineView.swift`
  hand-drawn radii 4/6/8 → `ContinuousPath`; keep `systemYellow` selection (native trim colour).

### Phase 5 — Quick Access card (careful)
`Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`: container `cornerRadius 14` (`:105`)
and icon buttons r7 (`:455`) → add `cornerCurve = .continuous`. **Do not change the scrim geometry, the sampled
band, or the button colours from `QuickAccessContrast`** (contrast guarantee in `CLAUDE.md`). Optional on 26: glass
buttons only if the contrast argument is redone and still holds.

### Phase 6 — Tours, History, onboarding, menu
- Tour tags (`Packages/TourKit/Sources/TourKit/Overlay/TagViews.swift`, `TagStyle.swift`): keep the red; bubble
  r12 → `cornerCurve = .continuous`; outline box r6 → `ContinuousPath`; keep 5.5:1 contrast. Re-measure
  `TagOverlayController.titledWindowCornerRadius` (`:47-50`) if Phase 2/4 change window chrome (toolbars change the
  macOS 26 window radius 16 → 26).
- History (`App/History/HistoryWindowController.swift`): already native — just make the thumbnail (r6) and cell
  (r8) `RoundedRectangle(…, style: .continuous)`; selected cell: accent 15 % fill, 2 pt accent stroke is fine.
- Onboarding and the menu-bar menu are native — leave them.

## 4. Don'ts
- Don't make floating HUDs follow light mode (contrast regressions C1/E2/S1 are measured and documented).
- Don't touch the Quick Access scrim/sample logic or the tour red.
- No glass inside glass (inspector controls on a glass inspector use plain tints, not more glass).
- No decorative dots/glows; no 1 pt borders; no `NSBezierPath(roundedRect:xRadius:yRadius:)` for UI chrome.
- Don't skip the Windows parity doc update.

## 5. Acceptance criteria
- Design-language README §7 checklist passes for Settings, History, onboarding (system appearance) and for the
  dark surfaces (in dark).
- `grep -rn "cornerRadius" App Packages --include=*.swift | grep -v cornerCurve` shows only places that also set
  `cornerCurve = .continuous` or use SwiftUI `.continuous` shapes.
- One HUD recipe (`HUDSurface`); `HUDStyle`/`RecordingHUDStyle` gone.
- White-text contrast on HUD surfaces ≥ 4.5:1 over a white page (review C1 method), on macOS 26 glass and fallback.
- Settings follows light/dark, has no black background, no dots, native controls, same instant-apply behaviour.
- `swift build` passes locally **and** would pass on the macOS 15 SDK (`#if compiler(>=6.2)` guards).
- `docs/MAC-TO-WINDOWS-PARITY-v3.md` (and Part 1 of `docs/WINDOWS-TO-MAC-PARITY.md` for Settings) updated.

## 6. How to verify
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot
swift build                 # must pass
scripts/test.sh             # TestKit suites (pure logic)
scripts/build-app.sh        # assembles dist/BetterScreenshot.app for a by-eye check
```
UI is verified by eye (repo convention: manual checklists). Compare against the current-state screenshots in
`docs/reviews/2026-09-25-ui/` and `docs/parity-v3/*.png`; check light + dark (Settings/History), bright + dark
wallpapers (HUDs), and re-run the contrast measurements from `docs/reviews/2026-09-25-ui-review.md` for C1.
Follow `CLAUDE.md` for installing (bundle id `com.betterscreenshot.mac`, never lose users' permissions/settings).
