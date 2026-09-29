# UI — HUD, Settings window, and menu bar

The app's SwiftUI/AppKit surfaces. All three mirror the state owned by `VoiceCoordinator.swift`
(at `Sources/JVoice/VoiceCoordinator.swift`).

## Files
- **Design direction (2026-09-29): the native macOS look of David's MacStats app** — spec
  `../MacStats/docs/design-language/jvoice-native-redesign.md`, design language
  `../MacStats/docs/design-language/README.md`. It REPLACED the 2026-06-27 monochrome direction
  (David: "it's all black", "little dots on all the different things", "doesn't look like a Mac native
  app"). Rules: system materials behind content (never opaque black/white/grey fills), `Color.primary`
  tints for surfaces, continuous (squircle) corners, 0.5 pt hairlines, text *styles* (no fixed tiny
  fonts, no kerning), semantic colours + one meaningful hue (red = destructive/stop, green = done,
  orange = warning, blue = model work), no decorative dots, no glows, at most one system shadow.
- `Theme.swift` — the semantic tokens (`Theme.native`: `Color.primary` tints + `.primary/.secondary/
  .tertiary` text; `danger` = red) and `Design` (radii/opacities copied from MacStats). `AppTheme`
  (`Models/`) is **System** (default — follows macOS) / Light / Dark; `AppTheme.nsAppearance` is the
  override set on each NSWindow (`nil` = follow macOS) — windows never use `.preferredColorScheme`
  (SwiftUI can't reliably hand a window back to the system appearance). Persisted under a NEW
  `SettingsState` key `appearance` (schema stays v4, so older builds still read the blob); the legacy
  `theme` field is still written (dark/light only). A blob without `appearance` maps the old `.dark`
  default to `.system` and keeps an explicit `.light`.
- `Components/` — `CardBackground` (the inset card: 0.04 tint, 0.5 pt hairline, radius 10 continuous) +
  `inputFieldStyle()`; `SubtleButtonStyle` (MacStats' small button; `destructive:` = red label);
  `VisualEffectBackground` (an `NSVisualEffectView`, behind-window) and `WindowMaterial.install` (makes a
  window's content a `.sidebar` material under a transparent title bar — Settings + Welcome; Settings
  passes `belowTitleBar: true` so its scrolling content never slides under the title bar);
  `InlineNotice`; `PanelPressableButtonStyle`.
- `HUDView.swift` / `HUDWindow.swift` / `HUDLayout.swift` — the HUD (heads-up display): a floating
  **glass capsule** — Liquid Glass (`.glassEffect(.regular, in: Capsule())`) on macOS 26, the
  `.hudWindow` behind-window material (masked with a stretchable capsule `maskImage` — a behind-window
  effect view ignores clip shapes) + 0.5 pt hairline before; `JVOICE_HUD_MATERIAL=1` forces that
  fallback on macOS 26 for previews. The glass call MUST stay inside `#if compiler(>=6.2)` +
  `if #available(macOS 26, *)` (CI builds with Xcode 16 / Swift 6.1). One soft shadow, `PillShadow`: a
  capsule shadow with the capsule itself cut away, so no text shadows through the translucent body.
  **Pills hug their content and morph (David, 2026-09-29):** ONE capsule wraps whichever pill is
  showing; each pill reports its own size (`fixedSize` — recording/transcribing 240 wide, "Pasted" as
  small as its text, errors wrap at `HUDLayout.pillMaxWidth`), so recording → transcribing → Pasted
  resizes that capsule with `HUDLayout.morph` (`.snappy(0.3)`) while the contents cross-fade. The
  panel grows to fit both capsules for the morph and shrinks to the new one `morphSettleDelay` later
  (content is bottom-anchored + centred, so nothing jumps). The FIRST show and the hide never animate
  (`HUDView.animated` is set only when a visible pill replaces another) — latency contract. **Recording** / **transcribing**: the J mark ·
  waveform bars (3 pt capsules resting at 2 pt = a calm flat line, secondary→primary opacity with
  level) · a red stop square (no label — the red control says "recording"). **Downloading / preparing /
  done / copied / error / notice**: the SF Symbol in `HUDState.accentRole`'s colour + `.callout` text
  (no badge circle). `HUDLayout.shadowPadding` (22) is the transparent margin for that shadow;
  `bottomGap` keeps the capsule where it always was. `HUDWindow.update(state:theme:meter:)` is the entry point. **Latency contract
  (2026-09-12):** `VoiceCoordinator.toggleRecording` shows `.recording` synchronously on the hotkey
  press, BEFORE any microphone work — the pill must never wait on the recorder. `HUDWindow.prewarm()`
  (called once from `VoiceCoordinator.start()`) realizes the panel at launch (ordered front fully
  transparent with the recording view, hidden 250 ms later) so the first press pays a re-show rather
  than window-server surface creation + the hosting view's first layout; `update()` cancels a
  pending prewarm hide, so an early press takes the realized panel over.
- `SettingsView.swift` / `SettingsWindow.swift` — the Settings window: a 700-wide, 2-column layout of
  MacStats-style cards (`.caption2` semibold section labels, no dots) on a translucent `.sidebar`
  window material (controls on the left — Whisper Model, Processing, Voice Style, Language, App Modes,
  Keyboard Shortcut; your data on the right — Recent Transcripts, Custom Words, Tours & Tips), Stats
  full-width on top (MacStats stat pattern), a native segmented **System / Light / Dark** picker
  (top-right) and a Restore-Defaults…/Quit footer (small red buttons). Restore Defaults confirms with a
  native `NSAlert` sheet (a SwiftUI dialog can lose focus in an accessory app). Rows in the lists
  (transcripts, words, app rules) reveal their actions (copy / remove) on hover over a 0.07 highlight.
  The **Recent Transcripts** card is a read-only list of up to 30 entries (hover a row to Copy
  or delete it; "Clear All" empties it), backed by `TranscriptHistoryStore` in `Services/Orchestration/`.
- `ShortcutRecorder.swift` / `ShortcutCapturePolicy.swift` — the two Settings rows that record a
  global chord ("Toggle Recording", "Undo Last Paste"). **JVoice draws these itself instead of
  using `KeyboardShortcuts.Recorder`**, and must keep doing so: that view is the package's only
  user of SwiftPM's generated `Bundle.module`, which hard-traps (`Swift.fatalError`) inside a
  packaged `.app` — it looks for its resource bundle at `<App>.app/KeyboardShortcuts_KeyboardShortcuts.bundle`
  (the bundle ROOT, where `codesign` refuses to seal anything: "unsealed contents present in the
  bundle root") and then at an absolute build-directory path baked in on the build machine. Both
  are gone in a shipped app, so **opening Settings killed the process in every build between
  2026-06-06 and 2026-09-21**. Everything else in the package (Name, defaults, storage, global
  registration via `HotKeyManager`) is untouched and still used. `ShortcutCapturePolicy` is the
  pure decision table for a key press while recording (Esc/Tab cancel, Delete clears, ⇧ alone is
  refused, F-keys need no modifier) and is covered by `scripts/run-logic-tests.sh`. The control
  disables both global hotkeys while it listens — otherwise the registered chord is swallowed
  system-wide before the local event monitor sees it — and re-enables them when the Settings
  window stops being key, so a close mid-capture can never leave the hotkeys off.
- `ShortcutCapturePolicy+AppKit.swift`, `SettingsEntryPolicy.swift`, `Components/InlineNotice.swift`
  (2026-09-24) — the recorder refuses bare keys (only ⌘⌥⌃⇧ count as modifiers; F-keys may be bare;
  bare ⌦ clears), system-reserved chords (`CopySymbolicHotKeys`), app-menu chords and a chord taken
  by the other action, each with a reason; Custom Words / App Modes explain a rejected entry instead
  of silently clearing it. `HUDWindow.prewarm()` swaps the hidden pill to the idle view so nothing
  animates while hidden (was 2.3–5.5 % of a core from launch to the first dictation).
- `SettingsSmokeRunner.swift` — the hidden `JVoice --settings-smoke` dev mode: it builds the real
  Settings window, shows it transparently so SwiftUI performs a genuine display pass, and exits 0.
  Run it **from an assembled `.app` bundle** — that is the environment the crash above only ever
  happened in. It does NOT call `VoiceCoordinator.start()` (no status item, no hotkey
  registration, no login item, no model load), so it is safe to run while the installed app is in
  use. This is the only automated check that can catch an AppKit/SwiftUI crash in Settings on a
  machine that cannot execute the test suite.
- `UIPreviewRunner.swift` (2026-09-29) — the hidden `JVoice --ui-preview <dir>` dev mode: opens the
  real Settings (Light + Dark, plus a tour tag on the model card), Welcome (both pages) and every HUD
  state (plus a frame half-way through the transcribing → Pasted morph), and saves a `screencapture -R` PNG of the screen under each (desktop included, so the
  translucency shows — a `-l` single-window capture has no backdrop and renders glass black). Never
  calls `VoiceCoordinator.start()`, never writes a setting (appearances are forced on the windows).
  Windows really appear on screen ~1 s each; needs Screen Recording permission for the terminal.
- `WelcomeWindow.swift` (2026-09-28) — the first-run window (same translucent material as Settings,
  the real app icon, native `.borderedProminent`/`.bordered` large buttons), shown at launch ONLY to users classified
  "new" who haven't answered the tour question: a permissions page (Microphone + Accessibility with
  live status) → "You're all set!" (shortcut cheat sheet + **"Want a quick tour?"** Show Me Around /
  No Thanks; closing it on either page = No Thanks). Also opened on the all-set page (no question) by
  Help & Tours → Take the Welcome Tour. Tour anchors `welcome.shortcut`, `welcome.tryIt`. Everything
  about who sees it: `Sources/JVoice/Tours/CLAUDE.md`.
- Tour hooks in the other surfaces: Settings cards carry `.tourAnchor("settings.*")`, a **Tours & Tips**
  card (bottom of the right column: "Show Me Around" toggle = `firstUseToursEnabled`, Replay Welcome
  Tour, Reset All Tours) and a title-bar **ⓘ** (`InfoButton`, anchor `settings.help`); `SettingsWindow`
  claims Return/Esc while a shortcut row is recording (`TourKeysClaiming`) so Esc cancels the capture,
  not the tour. The HUD's recording pill is anchored `pill.controls` and `HUDWindow` adopts
  `TourHostShaping` (the tag dims only the capsule — computed from the pill's fitting size — not its
  shadow margin or a morph's spare room). `HUDState.notice` is a neutral
  message pill (info icon) used for tour confirmations.
- `MenuBarController.swift` — the menu-bar status item: a bold "J" template image when idle, a red
  microphone while recording, a tinted waveform while transcribing, plus the dropdown NSMenu.
  (Deliberately left untouched by the redesigns — it is already native.)
  The button is tour anchor `menuBar.icon`; the menu has a **Help & Tours** submenu (Welcome /
  Recording / Settings tours, Reset All Tours).

## How to verify changes here
- `swift build` must pass; `MenuBarIconTests` runs in CI.
- **Any change to the Settings window must be smoke-tested in a real bundle**, because a crash
  there is invisible to `swift build` and to the test suite:
  ```
  swift build -c release
  APP=$(mktemp -d)/JVoice.app
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp .build/release/JVoice "$APP/Contents/MacOS/JVoice"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  "$APP/Contents/MacOS/JVoice" --settings-smoke     # expect: settings-smoke: OK …
  ```
- There is still **no** automated visual test (`ImageRenderer` and `CALayer.render(in:)` both come back
  blank: SwiftUI's content is drawn by the render server). To LOOK at a visual change, run
  `"$APP/Contents/MacOS/JVoice" --ui-preview <dir>` from the assembled bundle above (copy
  `Resources/AppIcon.icns` into `$APP/Contents/Resources/` for the Welcome icon) and open the PNGs.
  Materials follow the window's active state, so the previews (never key) show the inactive look.
