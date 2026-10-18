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
- `LaunchAtLoginManager.swift` — the launch-at-login toggle (`SMAppService`; `setEnabled` also marks the
  one-time question answered and posts `didChangeNotification`). No silent first-launch enable since
  1.2.0; the old flag `jvoice.app.launchAtLogin.didInitialize` is only read. Three controls share it
  (1.3.0): the menu item, Settings → Startup → **Launch at Login**, and the one-time card — all through
  `setEnabled` (the first two via `VoiceCoordinator.setLaunchAtLogin`); `VoiceCoordinator.refreshLaunchAtLogin()`
  re-reads `SMAppService.mainApp.status` (the source of truth) into `launchAtLogin` +
  `launchAtLoginNeedsApproval` on launch, on `didChangeNotification`, when the menu opens and when
  Settings → Startup appears / a window becomes key.
- `LaunchAtLoginPrompt.swift` (2026-10-18) — pure rules of the one-time "Open JVoice at login?" card:
  5 completed dictations, never if already enabled / already asked / a ≤ 1.1.4 user, calm moment,
  unanswered-card spacing (≤ 3 seen showings), plus the card's contrast math. Keys `jvoice.app.launchAtLoginPrompt.*`.
  Tested by `run-logic-tests.sh` (section 5) and `Tests/JVoiceTests/LaunchAtLoginPromptTests.swift`.
- `Updates.swift` (2026-10-18) — Sparkle 2 (`SPUStandardUpdaterController`, gentle reminders): the daily
  check, "Check for Updates…", Settings → Updates. Docs: `docs/sparkle-updates/README.md`.
- `SparkleE2EUI.swift` (2026-10-18) — compiled only with `-DSPARKLE_E2E_TEST`, active only with
  `SPARKLE_E2E_UI=1` (`E2E_UI=1 scripts/sparkle-e2e-test.sh`): clicks through Sparkle's real update
  windows (Install Update → Install and Relaunch) on the throwaway test copy, logging `pendingVersion`
  and the menu title on the way. Ported from BetterScreenshot. Never in a normal build.
- `SystemActions.swift` — small system-action helpers.
- `PermissionError.swift` — permission-failure types surfaced to the UI.
- `AppTimings.swift` — named timing constants: `pasteRestoreDelay`, `pasteActivationDelay` (only
  paid when the paste target is NOT already frontmost — the coordinator checks first), and
  `streamingPoll` (100 ms cadence of the streaming session's WAV check) and `speculativeTailPause`
  (0.4 s of trailing silence before the pending tail is decoded speculatively).

- `CoordinatorDecisions.swift` (2026-09-24) — the pure hotkey-press decision: a press between the
  stop press and the paste is IGNORED (it used to cancel the in-flight transcription); a stop while
  the mic is still opening ends the recording once it opens. `PasteManager` since then restores the
  clipboard per item and skips the restore if the user copied during the window; a refused paste
  (no Accessibility / target rejected) falls back to the clipboard and still records the history.

## Latency contract (2026-09-12, ported from the Windows port)
The recording pill is shown on the hotkey press BEFORE any microphone work; the mic opens off the
main actor; the paste skips the activate + 80 ms settle when the target is already frontmost; the
HUD switches state before the recorder stop and before the post-paste bookkeeping. The coordinator
logs `MicStarted +Nms after press`, `RecorderStopped +Nms …` and `Timing stop->transcript=…
stop->pasted=… stop->done=…` to the unified log (subsystem `com.jvoice.app`, category `latency`):
`/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jvoice.app"'` (`--info` required; full path — zsh
shadows `log`). Don't reintroduce work between the press and `updateHUD(.recording)`.

## How to verify changes here
- `swift build` must pass. Relevant tests run in CI (e.g. `PasteManagerTests`,
  `SettingsStoreCorruptionTests`, `StatsStoreTests`, `TranscriptHistoryStoreTests`,
  `VoiceCoordinatorHotkeyRaceTests`).
