# Sources/JVoice — app shell & orientation

JVoice is a macOS menu-bar voice-dictation app (press ⌥Space → record → on-device WhisperKit
transcription → styled text pasted into the frontmost app). This file is the top-level orientation;
each subfolder has its own `CLAUDE.md` with the real detail — **read the relevant area brief before
working there.** Kept short on purpose: it auto-loads for any work under `Sources/JVoice/`.

## Boot path (the three top-level files)
- `JVoiceApp.swift` — the `@main` entry (`JVoiceMain` enum). First checks for the hidden
  `--bench` CLI mode (`BenchRunner` — measures transcription speed/accuracy on this machine, where
  the XCTest runner cannot execute); otherwise launches the SwiftUI `JVoiceApp`. The app is a
  **menu-bar accessory** (`.accessory` activation policy, no Dock icon). It declares no real SwiftUI
  scenes — windows are managed imperatively by `AppDelegate` / `SettingsWindow`; the empty `Settings`
  scene is only the placeholder SwiftUI requires.
- `AppDelegate.swift` (`@MainActor`) — owns the single `VoiceCoordinator`. On launch:
  `coordinator.start()` + `bootstrapLaunchAtLogin()`, and routes service-level failures to the HUD
  (the heads-up status pill) via `SystemActions.errorHandler`. On terminate:
  `cleanUpForTermination()` + `flushSettings()`. The app stays alive with no windows open.
- `VoiceCoordinator.swift` — the spine. Drives the hotkey → record → transcribe → post-process →
  paste flow, owns the HUD state (the menu bar mirrors it), and tracks stats. Its collaborators are
  briefed under `Services/Orchestration/`.

## Where things live (each has its own CLAUDE.md brief)
- `Services/Transcription/` — WhisperKit engine, streaming-while-recording, custom-word accuracy.
- `Services/Audio/` — recording + microphone routing.
- `Services/Orchestration/` — system glue: paste, hotkey, settings/stats/transcript stores.
- `UI/` — the HUD, the Settings window, the menu-bar status item.
- `Models/` — small shared enums/structs (tone styles, HUD state, model options, language, settings).

## Verifying changes (important, non-obvious)
`swift build` must pass. `swift test` **compiles but runs 0 tests on this machine** (Command Line
Tools only — no test runner); the real test execution happens in CI (`.github/workflows/test.yml`).
For real local checks use `./scripts/run-logic-tests.sh` and `./scripts/verify-streaming.sh`, which
compile and EXECUTE the pure-logic and streaming guarantees without WhisperKit or a microphone.
