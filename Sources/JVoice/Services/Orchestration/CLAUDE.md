# Services/Orchestration — system glue & persisted state

The running app's integration with macOS, plus its small persisted stores.

The conductor that drives the whole flow — `VoiceCoordinator.swift` — deliberately lives one level
up at `Sources/JVoice/VoiceCoordinator.swift`, beside the app entry points (`JVoiceApp.swift`,
`AppDelegate.swift`), because it is the app's spine/composition root rather than peer glue. When
working on the end-to-end flow, read it too.

## The flow
Global hotkey (⌥Space) → record → transcribe → post-process → paste into the frontmost app.
`VoiceCoordinator` orchestrates this, owns the HUD state (the heads-up recording pill; the menu bar
mirrors it), and updates stats.

## Files
- `PasteManager.swift` — pastes text into the frontmost app via the macOS Accessibility API.
- `HotKeyManager.swift` — registers the global ⌥Space hotkey (via the KeyboardShortcuts package).
- `SettingsStore.swift` / `SettingsURLs.swift` — settings persistence and the URLs the Settings UI
  links out to.
- `StatsStore.swift` — usage statistics.
- `LastTranscriptStore.swift` — remembers the single most recent transcript (cleared by the privacy
  controls). Kept for the coordinator's Fix/Revert custom-word teaching path, which is no longer
  surfaced in the UI.
- `TranscriptHistoryStore.swift` — the recent-transcripts history shown in the Settings window:
  up to 30 entries (`TranscriptEntry`, newest first), JSON-persisted in `UserDefaults`. Same
  plaintext-in-prefs privacy posture as `LastTranscriptStore`; only ever erased by explicit user
  action (per-row delete, "Clear all", or "Restore Default Settings").
- `LaunchAtLoginManager.swift` — the launch-at-login toggle.
- `SystemActions.swift` — small system-action helpers.
- `PermissionError.swift` — permission-failure types surfaced to the UI.
- `AppTimings.swift` — named timing constants.

## How to verify changes here
- `swift build` must pass. Relevant tests run in CI (e.g. `PasteManagerTests`,
  `SettingsStoreCorruptionTests`, `StatsStoreTests`, `TranscriptHistoryStoreTests`,
  `VoiceCoordinatorHotkeyRaceTests`).
