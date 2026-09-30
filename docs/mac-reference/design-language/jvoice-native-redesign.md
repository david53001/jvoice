# JVoice → native macOS look (MacStats design language) — redesign spec

**Status:** spec only, not started (written 2026-09-29). Nothing in the JVoice repo has been changed.
**App:** JVoice, a macOS menu-bar voice-dictation app, repo `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice`
(SwiftPM, Command Line Tools only, deployment target macOS 14, `LSUIElement` menu-bar app).
**Design language to apply:** `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/README.md`
— read it first (tokens, components, motion, materials, toolchain rules). Reference screenshots:
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/assets/macstats-overview.png`.

## 0. Why, and what this supersedes

The user (the app's owner) wants JVoice to look like a native Mac app — translucent materials, squircle
(continuous-corner) cards, simple lines and text — like their MacStats app. Their complaints about JVoice today:
**"it's all black", "little dots on all the different things", "the way it's laid out does not look like a Mac
native app"**.

This **deliberately replaces** the monochrome direction from
`docs/superpowers/plans/2026-06-27-ui-overhaul-monochrome-themes.md` ("pure black/white/grey, no hue") and the
description in `Sources/JVoice/UI/CLAUDE.md`. Update both docs when the work lands. Keep everything *functional*
from that work (theme persistence plumbing, the redesigned pill layout, specific error messages).

### Before you start — coordinate
- At the time of writing JVoice was on branch `feat/guided-tour` with many agent worktrees under
  `.claude/worktrees/`, i.e. other sessions were actively changing `SettingsView.swift`, `VoiceCoordinator.swift`
  and the tour kit. Start this on its own branch (e.g. `feat/native-look`) from the latest merged state, and
  expect to rebase over tour work. Don't touch other sessions' worktrees.
- Read `CLAUDE.md`, `Sources/JVoice/UI/CLAUDE.md` and `Sources/JVoice/Tours/CLAUDE.md` in the JVoice repo.

### Hard constraints (from JVoice's own docs — do not break)
1. **Never run `swift test` on this Mac** (it froze the machine on 2026-09-24). Gates: `swift build`,
   `./scripts/run-logic-tests.sh` for pure logic, and the Settings smoke run (§7).
2. **Keep JVoice's own `ShortcutRecorder`**; never switch to `KeyboardShortcuts.Recorder` (it crashes in a packaged
   app — see `UI/CLAUDE.md`).
3. **HUD latency contract:** the recording pill must appear synchronously on the hotkey press;
   `HUDWindow.prewarm()` keeps the panel realized. Don't add async work or first-show-only setup to the show path.
4. **Tour anchors must survive:** every `.tourAnchor("settings.*")`, `pill.controls`, `welcome.*`, `menuBar.icon`,
   and `HUDWindow`'s `TourHostShaping`. Restyling a view must keep its anchor modifier on the equivalent element.
5. **CI builds with Xcode 16 (macOS 15 SDK)**, see `.github/workflows/test.yml`. Any Liquid Glass call must be
   inside `#if compiler(>=6.2)` **and** `if #available(macOS 26, *)`, with a material fallback — or CI breaks.
6. Don't `git push` (JVoice house rule). Don't run `./scripts/install.sh` yourself — ask the user to dogfood.

## 1. What's there now (inventory, file:line as of 2026-09-29)

| Surface | Files | Now |
|---|---|---|
| Design tokens | `Sources/JVoice/UI/Theme.swift`, `Sources/JVoice/Models/AppTheme.swift` | Monochrome. Dark default: window `Color(white: 0.04)` (near-black), cards `Color(white: 0.075)`, pill `Color(white: 0.05)`, hairline white 0.10, `danger = textPrimary` (not red). No materials anywhere. |
| Settings window | `UI/SettingsWindow.swift` (NSWindow 700×560, `[.titled, .closable, .fullSizeContentView]`, forced `darkAqua`/`aqua`), `UI/SettingsView.swift` | Opaque near-black page, 2 columns of cards, sun/moon toggle, hard-coded 9.5–26 pt fonts. |
| HUD pill | `UI/HUDWindow.swift` (borderless nonactivating `NSPanel`, clear bg, `hasShadow = false`), `UI/HUDView.swift`, `UI/HUDLayout.swift` | Solid near-black capsule, 1 pt border, **three stacked shadows/glows** (`HUDView.swift:45-47`), 15 bars that rest as 3×4 pt dots, 7 pt "RECORDING" label. |
| Welcome window | `UI/WelcomeWindow.swift` (460×470, transparent titlebar) | Opaque page, 12 pt (continuous) card, custom `MonoButton`s. |
| Tour overlay | `Tours/Kit/TagViews.swift`, `TagStyle.swift`, `TagOverlayController.swift` | Bubble = `CALayer.cornerRadius 12` (**circular**, not continuous), ink/paper hard-coded colours, `NSBezierPath` outline box. |
| Menu bar | `UI/MenuBarController.swift` | Native `NSStatusItem` + `NSMenu` — already fine; leave it. |
| Info popover | `Tours/Kit/InfoButton.swift` | Native `NSPopover`/`NSMenu` — fine. |

**The "little dots" the user means**, found in code:
1. **A 5 pt dot before every Settings card title** — `SettingsView.swift:22-29` (`Circle().fill(theme.textMuted).frame(width: 5, height: 5)`), on all ~10 cards. *Main culprit.*
2. **HUD bars at rest** — 15 capsules 3 pt wide with min height 4 (`HUDView.swift:72-84`, shimmer `:102-113`) read as a row of dots when quiet.
3. **Circle badge behind status icons** — 28 pt circle in the status pill (`HUDView.swift:340-344`).
4. Minor: `minus.circle.fill` delete buttons (`SettingsView.swift:349, 474, 639`), `xmark.circle.fill` (`ShortcutRecorder.swift:85`), "·" separators in model-guidance strings (`VoiceCoordinator.swift:52-58`). The "·" in running text is normal Apple typography — keep it.

## 2. Target look (one paragraph)

Settings looks like a small System-Settings-style window on a **slightly translucent** backdrop (the desktop
softly shows through), with MacStats-style inset cards: faint `Color.primary` tint, 0.5 pt hairline, continuous
10 pt corners, **no dots**, `.caption2` semibold secondary section labels, system text styles, native controls.
The HUD is a **floating glass capsule** (Liquid Glass on macOS 26, HUD material before) with a single soft system
shadow, the J mark and waveform in `.primary`, a red stop control — no glow halo. The Welcome window and the
tour bubbles use the same materials and squircles. Light/dark follows the system by default.

## 3. Work plan (phased; each phase is shippable on its own)

### Phase 1 — Tokens: from monochrome to semantic (`Theme.swift`, `AppTheme.swift`)
- Rewrite `Theme` so tokens are **semantic tints**, not solid colours. Suggested shape (keep the struct so call
  sites compile, change values):
  - `windowBackground` → remove as a fill; the window gets a material instead (Phase 2). If a fallback fill is
    needed use `Color.clear`.
  - `surface` → `Color.primary.opacity(0.05)` (user wants "slightly transparent, maybe a little more" → 0.04 is
    fine); `hairline` → `Color.primary.opacity(0.08)` **drawn at 0.5 pt**; `inputBackground` →
    `Color.primary.opacity(0.06)`.
  - `textPrimary/Secondary/Muted` → `.primary` / `.secondary` / `.tertiary` (as `Color.primary`,
    `Color.secondary`, `Color(nsColor: .tertiaryLabelColor)`).
  - `danger` → `.red` (Apple convention; delete the "kept monochrome" comment).
  - Pill tokens → see Phase 3 (material + one shadow).
  - Because the tokens now adapt by themselves, `Theme.dark`/`Theme.light` can collapse into one `Theme.native`;
    keep the `colorScheme` field only for the override below.
- `AppTheme`: add **`.system`** (follow macOS) and make it the default. The persisted value lives in the
  `SettingsState` JSON blob (`SettingsState.swift:33,87` default `.dark`). Decide with the user whether existing
  installs migrate `.dark` → `.system` (recommended: yes, once, since `.dark` was the *default*, not a choice).
  For `.system`: `window.appearance = nil` and `.preferredColorScheme(nil)`.
- Add a small `UI/Components/` set mirroring MacStats (see the design-language README §3): `CardBackground`,
  `CardButtonStyle` (if any card is tappable), `SubtleButtonStyle`. Today there are three unrelated button systems
  (`SettingsButtonStyle`, `MonoButton`, `TagButton`) — consolidate onto native styles + `SubtleButtonStyle`.

### Phase 2 — Settings window (`SettingsWindow.swift`, `SettingsView.swift`)
1. **Translucent backdrop.** Make the window's content a behind-window material so the desktop shows through
   slightly:
   - AppKit (works on macOS 14): an `NSVisualEffectView` as `contentView` with `material = .sidebar` (or
     `.underWindowBackground` if `.sidebar` is too see-through), `blendingMode = .behindWindow`,
     `state = .followsWindowActiveState`; add the `NSHostingView` as a pinned subview. Set
     `titlebarAppearsTransparent = true` so the material runs under the title bar.
   - Remove `.background(theme.windowBackground)` from the SwiftUI root (`SettingsView.swift:~171`).
   - Check contrast by eye over a bright wallpaper; if text gets muddy, go one step less translucent.
2. **Cards (`SettingsSection`, `SettingsView.swift:9-49`).**
   - Delete the `Circle()` dot. Header = `Text(title.uppercased()).font(.caption2).fontWeight(.semibold)
     .foregroundStyle(.secondary)` — no `.kerning`, no fixed 9.5 pt.
   - Drop the 0.5 pt divider under the header (MacStats cards have none); use spacing (8 pt) instead.
   - Background = `CardBackground` with radius **10** `.continuous`, fill 0.05 (or 0.04), **0.5 pt** hairline
     (today 1 pt).
3. **Typography.** Replace `.system(size:)` with text styles: body copy `.callout`/`.body` (today 10–11 pt is
   below macOS's 13 pt body), subtitles `.caption`/`.footnote` secondary, the page title `.title2.bold()`,
   stats values `.title2.weight(.semibold).monospacedDigit()` with `.caption2` secondary labels (the MacStats
   stat-card pattern). Keep `.monospacedDigit()` on every changing number and
   `.contentTransition(.interpolate)` + `.easeInOut(duration: 0.25)` if they update live.
4. **Controls.**
   - `SettingsButtonStyle` → native `.bordered` + `.controlSize(.small)` for secondary actions, or
     `SubtleButtonStyle`. Destructive (Clear all, Restore Defaults, Quit) → `role: .destructive` and red tint.
   - `ThemeToggle` (sun/moon capsule) → native segmented `Picker` with three options System / Light / Dark
     (SF Symbols `circle.lefthalf.filled`, `sun.max`, `moon`), `.labelsHidden()`, `.pickerStyle(.segmented)`,
     `.fixedSize()`.
   - Segmented pickers / switches are already native — keep; add `.labelsHidden()` to the Voice Style picker
     (its "Tone" label may render, `SettingsView.swift:289-295`).
   - Text fields: either native `.textFieldStyle(.roundedBorder)` or keep the custom look but with a
     `Color.primary.opacity(0.06)` fill, radius 6 `.continuous`, 0.5 pt hairline; de-duplicate the two copies
     (`:359-372`, `:487-500`) into one modifier.
   - Row delete buttons: keep an SF Symbol but make them quiet — `minus.circle` in `.secondary`, shown on row hover
     (the transcript rows already reveal actions on hover — apply the same pattern everywhere).
   - The Restore-Defaults `.confirmationDialog` → `NSAlert` (a SwiftUI dialog in an accessory app can lose focus;
     MacStats hit exactly this — see its `AppModel.confirmAndEmptyTrash` doc comment).
5. **Layout.** Keep the 2-column structure (it's a good fit) but align with Apple spacing: page padding 20,
   column gap 12, card gap 12, card padding 12. Header row: app title left, appearance picker right. Footer:
   buttons in the MacStats footer pattern (secondary left, destructive right). Transcript rows: MacStats list-row
   hover highlight (`Color.primary.opacity(0.07)`, radius 6 continuous).

### Phase 3 — HUD pill (`HUDView.swift`, `HUDWindow.swift`, `HUDLayout.swift`)
1. **Material instead of black.** Replace `pillChrome`'s solid fill + 1 pt border + triple shadow
   (`HUDView.swift:32-49`) with:
   ```swift
   #if compiler(>=6.2)
   if #available(macOS 26, *) {
       content.glassEffect(.regular, in: Capsule())            // Liquid Glass
   } else { content.background(HUDMaterial().clipShape(Capsule())) }
   #else
   content.background(HUDMaterial().clipShape(Capsule()))
   #endif
   ```
   where `HUDMaterial` is an `NSViewRepresentable` wrapping `NSVisualEffectView(material: .hudWindow,
   blendingMode: .behindWindow, state: .active)`. (SwiftUI `.regularMaterial` inside a *clear, borderless*
   window blends within the window and can come out as a flat tint — the AppKit view with `.behindWindow`
   is the reliable fallback. Verify by eye.) Add a 0.5 pt `Color.primary.opacity(0.1)` capsule hairline on the
   fallback only (glass draws its own edge).
2. **One shadow.** Delete the two white "glow" shadows; keep one soft drop shadow
   (`.shadow(color: .black.opacity(0.2), radius: 10, y: 4)`). Shrink `HUDLayout.glowPadding` to what that shadow
   needs (~16) — **and check `TourHostShaping` / `TourTagLayoutTests` still agree** (they reference the glow
   margin). Delete `pillGlow`/`pillDropShadow` tokens.
3. **Waveform without dots.** At silence the bars should read as a calm flat line, not dots: min bar height 2 pt
   (not 4), bar width 2.5–3 pt with 2 pt gaps, and quiet bars at `.secondary` opacity rising to `.primary` with
   level. Keep the 15 Hz meter and the `AudioLevelMeter` logic. Transcribing shimmer: same geometry, no
   `repeatForever` running while hidden (the prewarm already swaps to the idle view — keep that).
4. **Text & icons.** Remove the 7 pt tracked "RECORDING" label (illegible, and the red stop control already
   says "recording"), or make it `.caption2` `.secondary`. J mark → `.primary`, `.title3.weight(.heavy)`.
   Stop button: red (`Color.red`) continuous rounded square (radius 6, inner 2) — keep the size.
   Status pill (done/copied/error/notice): drop the 28 pt circle badge; show the SF Symbol in its meaning colour
   (`checkmark` green, `exclamationmark.triangle` orange/red, `info.circle` secondary) + `.callout` text.
   `HUDState.accentRole` (`HUDState.swift:138-156`) already defines these roles but nothing reads it — use it here.
5. **Motion.** Show/hide stays instant (latency contract); state changes cross-fade `.easeInOut(0.2)`; width
   changes `.snappy(0.3)`.

### Phase 4 — Welcome window (`WelcomeWindow.swift`)
- Same translucent backdrop as Settings (NSVisualEffectView `.sidebar`/`.underWindowBackground`, behind-window);
  remove `theme.windowBackground`.
- Permissions card → `CardBackground` radius 12; rows like MacStats list rows.
- `MonoButton` → native `.borderedProminent` (primary: "Continue", "Show Me Around") and `.bordered`
  (secondary: "No Thanks"), `.controlSize(.large)`.
- JMark 64 pt squircle: use the real app icon (`NSApp.applicationIconImage`) at 64 pt, or keep the drawn mark with
  radius 14 `.continuous` (22 %).
- Text styles: title `.title2.bold()`, body `.body` secondary.

### Phase 5 — Tour overlay (`Tours/Kit/`)
- `TagBubbleView`: set `layer.cornerCurve = .continuous` next to `cornerRadius` (`TagViews.swift:155`);
  background → an `NSVisualEffectView` (`.popover`, behind-window) or glass on 26, instead of ink/paper
  (`TagStyle.swift:16-17`); text in `labelColor`/`secondaryLabelColor`.
- Outline box / cut-out (`TagStyle.swift:39`, `TagViews.swift:42-71`): build the rounded path as continuous
  (SwiftUI `RoundedRectangle(cornerRadius:style: .continuous).path(in:).cgPath`) and use a 1.5 pt
  `controlAccentColor` stroke instead of 2 pt ink.
- `TagButton` capsules → native `NSButton` with `bezelStyle = .push`/`.glass` (26) or keep capsules with
  `SubtleButtonStyle` colours.
- The version-aware host-window radius (`TagOverlayController.swift:46-51`) is already right.

### Phase 6 (optional) — app icon
`scripts/generate-icon.swift:86-112` draws a near-black squircle. A native-feeling icon would use a subtle
gradient in a hue plus a white J; only if the user asks.

## 4. Don'ts
- No opaque black/white/grey fills behind content; no decorative dots; no stacked glows; no 1 pt borders;
  no fixed tiny fonts; no circular (non-continuous) corners; no glass inside glass; don't restyle the menu-bar menu.

## 5. File-by-file change list

| File | Change |
|---|---|
| `Sources/JVoice/UI/Theme.swift` | Semantic tokens (Phase 1) |
| `Sources/JVoice/Models/AppTheme.swift`, `SettingsState.swift` | Add `.system` default (+ optional migration) |
| `Sources/JVoice/UI/Components/` (new files) | `CardBackground`, `SubtleButtonStyle`, `HUDMaterial`/`WindowMaterial` representables |
| `Sources/JVoice/UI/SettingsWindow.swift` | Material content view, transparent titlebar, appearance nil for System |
| `Sources/JVoice/UI/SettingsView.swift` | Cards without dots, text styles, native controls, NSAlert for Restore Defaults |
| `Sources/JVoice/UI/HUDView.swift`, `HUDLayout.swift` | Glass/material capsule, one shadow, flat-line bars, status icons |
| `Sources/JVoice/UI/WelcomeWindow.swift` | Material backdrop, native buttons, card |
| `Sources/JVoice/Tours/Kit/TagViews.swift`, `TagStyle.swift` | Continuous corners, material bubble, semantic colours |
| `Sources/JVoice/UI/CLAUDE.md`, the 2026-06-27 plan | Document the new direction |

## 6. Acceptance criteria
- Every item of the checklist in the design-language README §7 passes.
- No `Circle()` used as decoration anywhere in `Sources/JVoice/UI` (only status meaning).
- `grep -rn "Color(white:" Sources/JVoice` returns nothing in UI code.
- Settings, Welcome and HUD look right in **light and dark**, over a bright and a dark wallpaper, on macOS 26;
  and still render (material fallback) when built against the macOS 15 SDK (`#if compiler` guards).
- HUD still appears instantly on the hotkey; tours still point at the right elements.

## 7. How to verify (JVoice rules)
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice
swift build                       # must pass
./scripts/run-logic-tests.sh      # pure logic (never `swift test` on this Mac)
# Settings smoke test in a real bundle (catches AppKit/SwiftUI crashes swift build can't):
swift build -c release
APP=$(mktemp -d)/JVoice.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/JVoice "$APP/Contents/MacOS/JVoice"
cp Resources/Info.plist "$APP/Contents/Info.plist"
"$APP/Contents/MacOS/JVoice" --settings-smoke     # expect: settings-smoke: OK …
```
There is no headless visual test (ImageRenderer/CALayer.render come back blank). Visual check = the user runs
`./scripts/install.sh` and looks; screenshots can be taken with `screencapture -x out.png` once a window is open.
