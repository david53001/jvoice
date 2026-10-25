# Sources/JVoice — app shell & orientation

JVoice is a macOS voice-dictation app — a Dock app since 1.4.0, a menu-bar app before (press ⌥Space → record → on-device WhisperKit
transcription → styled text pasted into the frontmost app). This file is the top-level orientation;
each subfolder has its own `CLAUDE.md` with the real detail — **read the relevant area brief before
working there.** Kept short on purpose: it auto-loads for any work under `Sources/JVoice/`.

## Boot path (the three top-level files)
- `JVoiceApp.swift` — the `@main` entry (`JVoiceMain` enum). First checks for the hidden
  `--bench` CLI mode (`BenchRunner` — measures transcription speed/accuracy on this machine, where
  the XCTest runner cannot execute) and the other hidden dev modes; otherwise runs a **plain AppKit**
  app (`NSApplication.shared` + `AppDelegate` + `run()`, since 1.4.0). There is no SwiftUI `App` any more:
  its required scene (an empty `Settings` scene until 2026-10-17, then a never-inserted `MenuBarExtra`)
  could open a blank "JVoice Settings" window by itself and built its own main menu. SwiftUI is still
  used inside the windows (`NSHostingView`). The app is a **regular Dock app** since 1.4.0 (`.regular`,
  no `LSUIElement`; it was a menu-bar accessory with a status item until 1.3.1). Right before launching the app it classifies the
  user as new/existing for the first-run tour (`TourCoordinator.classifyAudienceIfNeeded`) — it MUST
  stay before anything writes UserDefaults (see `Tours/CLAUDE.md`).
- `AppDelegate.swift` (`@MainActor`) — owns the single `VoiceCoordinator` and `AppMenus` (the main menu,
  installed in `applicationWillFinishLaunching`, and the Dock menu, `applicationDockMenu`). Which window
  opens is `LaunchWindowPolicy` (`Services/Orchestration/`): a user launch → Settings, a launch at login →
  none (the launch Apple Event's `keyAELaunchedAsLogInItem`, logged as `Launch atLogin=…` in category
  `launch`), first run → Welcome; a Dock click / launching it again → Settings (or Welcome forward). On launch:
  `coordinator.start()` + `bootstrapLaunchAtLogin()` + `Updates.shared.start()` (Sparkle) + the
  one-time launch-at-login card (`LaunchAtLoginPromptController`), and routes service-level failures to the HUD
  (the heads-up status pill) via `SystemActions.errorHandler`. Also owns the `TourCoordinator` and
  the first-run `WelcomeWindow` (shown at launch to new users only). On terminate:
  `cleanUpForTermination()` + `flushSettings()`. The app stays alive with no windows open (closing a
  window never quits; ⌘Q / the Dock's Quit does).
- `VoiceCoordinator.swift` — the spine. Drives the hotkey → record → transcribe → post-process →
  paste flow, owns the HUD state, and tracks stats. It never pastes into JVoice itself: when JVoice is
  frontmost at the stop, the target is the last other app that was (`resolveTargetPID`). Its collaborators are
  briefed under `Services/Orchestration/`.

## Where things live (each has its own CLAUDE.md brief)
- `Services/Transcription/` — WhisperKit engine, streaming-while-recording, custom-word accuracy.
- `Services/Audio/` — recording + microphone routing.
- `Services/Orchestration/` — system glue: paste, hotkey, settings/stats/transcript stores.
- `Services/AIPolish/` — the opt-in Claude polish step (off by default; BYOK key in one owner-only file, hard 3 s
  deadline, any failure pastes the local text) + the `--polish-eval` harness.
- `UI/` — the HUD, the Settings window, the Welcome window, the main menu + Dock menu (`AppMenus`).
- `Tours/` — the first-run guided tour (ported from BetterScreenshot): who gets it, the tour
  catalog, the on-screen tag.
- `Models/` — small shared enums/structs (tone styles, HUD state, model options, language, settings).

## Verifying changes (important, non-obvious)
`swift build` must pass. `swift test` **compiles but runs 0 tests on this machine** (Command Line
Tools only — no test runner); the real test execution happens in CI (`.github/workflows/test.yml`).
For real local checks use `./scripts/run-logic-tests.sh` and `./scripts/verify-streaming.sh`, which
compile and EXECUTE the pure-logic and streaming guarantees without WhisperKit or a microphone.
