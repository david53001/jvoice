# UI — HUD, Settings window, and menu bar

The app's SwiftUI/AppKit surfaces. All three mirror the state owned by `VoiceCoordinator.swift`
(at `Sources/JVoice/VoiceCoordinator.swift`).

## Files
- `HUDView.swift` / `HUDWindow.swift` / `HUDLayout.swift` — the HUD (heads-up display): a small
  floating pill showing the recording / preparing-model / transcribing / done states.
- `SettingsView.swift` / `SettingsWindow.swift` — the Settings window (a fixed 380 × 520 pt column
  of `DarkSection` cards: Stats, Recent Transcripts, Whisper Model, Processing, Voice Style, Language,
  Custom Words, Keyboard Shortcut, then a pinned Restore-Defaults/Quit row). The **Recent Transcripts**
  card is a read-only list of up to 30 entries (hover a row to Copy or delete it; "Clear all" empties
  it), backed by `TranscriptHistoryStore` in `Services/Orchestration/`.
- `MenuBarController.swift` — the menu-bar status item: a bold "J" template image when idle, a red
  microphone while recording, a tinted waveform while transcribing, plus the dropdown NSMenu.
- `Components/` — shared UI subviews used by the above.

## How to verify changes here
- `swift build` must pass; `MenuBarIconTests` runs in CI. There is **no** automated visual test —
  run the app and check layout/appearance by eye for any visual change.
