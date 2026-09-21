# UI — HUD, Settings window, and menu bar

The app's SwiftUI/AppKit surfaces. All three mirror the state owned by `VoiceCoordinator.swift`
(at `Sources/JVoice/VoiceCoordinator.swift`).

## Files
- `Theme.swift` — monochrome (pure black/white/grey, no hue) design tokens, `dark`/`light` variants,
  plus the `AppTheme.theme` bridge. Single source of truth for every surface JVoice draws itself (the
  HUD pill + Settings cards). Native SwiftUI controls follow `.preferredColorScheme`; these tokens
  cover the rest. The active appearance is `VoiceCoordinator.appTheme` (persisted in `SettingsState`).
- `HUDView.swift` / `HUDWindow.swift` / `HUDLayout.swift` — the HUD (heads-up display): a small
  floating, theme-aware monochrome pill for the recording / preparing-model / transcribing / done /
  error states. **Recording** and **transcribing** show a centered row (the "J" mark · animated
  waveform bars · stop button) with a small bottom label — recording bars are mic-reactive (driven by
  `AudioLevelMeter`), transcribing is a gentle low shimmer. **Preparing-model / done / error** keep a
  status icon + text. `HUDLayout.glowPadding` keeps the soft pill glow from clipping square at the
  window edge. `HUDWindow.update(state:theme:meter:)` is the entry point. **Latency contract
  (2026-09-12):** `VoiceCoordinator.toggleRecording` shows `.recording` synchronously on the hotkey
  press, BEFORE any microphone work — the pill must never wait on the recorder. `HUDWindow.prewarm()`
  (called once from `VoiceCoordinator.start()`) realizes the panel at launch (ordered front fully
  transparent with the recording view, hidden 250 ms later) so the first press pays a re-show rather
  than window-server surface creation + the hosting view's first layout; `update()` cancels a
  pending prewarm hide, so an early press takes the realized panel over.
- `SettingsView.swift` / `SettingsWindow.swift` — the Settings window: a 700-wide, 2-column grouped
  monochrome layout (controls on the left — Whisper Model, Processing, Voice Style, Language, Keyboard
  Shortcut; your data on the right — Recent Transcripts, Custom Words), with Stats full-width on top, a
  sun/moon `ThemeToggle` (top-right, flips `appTheme` dark↔light), and a pinned Restore-Defaults/Quit
  footer. The **Recent Transcripts** card is a read-only list of up to 30 entries (hover a row to Copy
  or delete it; "Clear all" empties it), backed by `TranscriptHistoryStore` in `Services/Orchestration/`.
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
- `SettingsSmokeRunner.swift` — the hidden `JVoice --settings-smoke` dev mode: it builds the real
  Settings window, shows it transparently so SwiftUI performs a genuine display pass, and exits 0.
  Run it **from an assembled `.app` bundle** — that is the environment the crash above only ever
  happened in. It does NOT call `VoiceCoordinator.start()` (no status item, no hotkey
  registration, no login item, no model load), so it is safe to run while the installed app is in
  use. This is the only automated check that can catch an AppKit/SwiftUI crash in Settings on a
  machine that cannot execute the test suite.
- `MenuBarController.swift` — the menu-bar status item: a bold "J" template image when idle, a red
  microphone while recording, a tinted waveform while transcribing, plus the dropdown NSMenu.
  (Deliberately left untouched by the monochrome theming — it already adapts to the OS menu bar.)
- `Components/` — shared UI subviews used by the above.

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
- There is still **no** automated visual test — run the app and check layout/appearance by eye for
  any visual change (`ImageRenderer` and `CALayer.render(in:)` were both tried for a headless PNG
  in 2026-09-21 and both come back blank: SwiftUI's content is drawn by the render server).
