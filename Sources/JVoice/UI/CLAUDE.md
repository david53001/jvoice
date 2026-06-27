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
  window edge. `HUDWindow.update(state:theme:meter:)` is the entry point.
- `SettingsView.swift` / `SettingsWindow.swift` — the Settings window: a 700-wide, 2-column grouped
  monochrome layout (controls on the left — Whisper Model, Processing, Voice Style, Language, Keyboard
  Shortcut; your data on the right — Recent Transcripts, Custom Words), with Stats full-width on top, a
  sun/moon `ThemeToggle` (top-right, flips `appTheme` dark↔light), and a pinned Restore-Defaults/Quit
  footer. The **Recent Transcripts** card is a read-only list of up to 30 entries (hover a row to Copy
  or delete it; "Clear all" empties it), backed by `TranscriptHistoryStore` in `Services/Orchestration/`.
- `MenuBarController.swift` — the menu-bar status item: a bold "J" template image when idle, a red
  microphone while recording, a tinted waveform while transcribing, plus the dropdown NSMenu.
  (Deliberately left untouched by the monochrome theming — it already adapts to the OS menu bar.)
- `Components/` — shared UI subviews used by the above.

## How to verify changes here
- `swift build` must pass; `MenuBarIconTests` runs in CI. There is **no** automated visual test —
  run the app and check layout/appearance by eye for any visual change.
