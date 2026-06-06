# CLAUDE.md — JVoice

Standalone macOS menu-bar voice-dictation app. Press ⌥Space anywhere → record → on-device WhisperKit transcription → tone-styled text pasted into the frontmost app. Free, open-source, privacy-first: zero network calls at runtime (only the one-time Whisper model download), no telemetry, no accounts.

## Provenance

Extracted 2026-06-06 from `../MacOSUtils` (David's multi-utility app, formerly named JVoice). **Never modify `../MacOSUtils`** — it is a separate, active project. This repo is the public-facing standalone product.

## Hard rules

- **NO publishing without David's explicit go-ahead.** Do not `gh repo create`, `git push`, or add remotes. He has two gh accounts (`david53001` active, `da97d`); publishing is deliberately on hold. Same applies to posting anywhere (HN/Reddit drafts exist in `docs/launch/` — David posts those himself).
- **$0 budget.** No Apple Developer account → unsigned distribution (ad-hoc signed DMG via GitHub Releases). Homebrew is NOT an option (bans unsigned casks as of Sept 2026 — see `docs/launch/unsigned-distribution-findings.md`). Everything must stay free: GitHub Pages for the site, free CI, no paid services.
- The app stays **free forever**; potential future model is VoiceInk-style (free buildable source + paid prebuilt binary) — but that's a David decision, not yours.

## Build & test

- `swift build` — must pass. SwiftPM, Swift 5.9, macOS 14+. Deps: WhisperKit (≥1.0.0), KeyboardShortcuts (exact 1.10.0).
- `swift test` — **compiles but executes 0 tests locally**: this machine has Command Line Tools only (no xctest runner). Same limitation as MacOSUtils. Real test runs happen in CI (`.github/workflows/test.yml`, macos-14 + Xcode 15.4, guards against silently-skipped tests).
- `./scripts/install.sh` — release build, signs with the local "JVoice Self-Signed" keychain cert, installs to /Applications. Only run when David asks to install/dogfood.
- Bundle ID is `com.jvoice.app` — deliberately NOT `com.jvoice.JVoice` (that's MacOSUtils'; both apps coexist on this machine). UserDefaults namespace: `jvoice.app.*`.

## Architecture (Sources/JVoice/)

- `VoiceCoordinator.swift` — central orchestrator: hotkey → record → transcribe → process → paste flow, HUD state, stats.
- `Services/` — RecordingManager (AVAudioRecorder), TranscriptionManager (+WhisperKit engine, WhisperModelLocator), TextProcessor (tone styles, filler removal, custom words), PasteManager (Accessibility paste), HotKeyManager, AudioInputRouter (keeps Bluetooth on A2DP by recording from built-in mic), SettingsStore, StatsStore, LastTranscriptStore.
- `Models/` — AppMode (tone styles), HUDState, WhisperModelOption, TranscriptionLanguage, SettingsState.
- `UI/` — HUDView/HUDWindow (recording/transcribing/done pills), SettingsView/SettingsWindow, MenuBarController (status item + NSMenu).

## Demo video (Remotion)

`docs/demo-video/` is a Remotion project that renders the README demo as a faithful recreation of the real UI. **All visuals must trace to `docs/demo-video/DESIGN-TOKENS.md`**, which was extracted from the SwiftUI source — if app UI changes, regenerate tokens first. Storyboard and fidelity were approved by David (rejected an earlier generic mockup; product-exact UI is the acceptance bar).
- Render: `cd docs/demo-video && npm install && npx remotion render` (see package.json scripts).
- Outputs: `docs/assets/demo.mp4` (1600×1000@30fps) and `docs/assets/demo.gif` (800px@20fps, keep ≤8MB).
- After re-rendering, copy the gif to `../Portfolio/assets/jvoice-demo.gif` (the download site, its own git repo).
- Review stills live in `docs/demo-video/stills/`.

## Launch material

- `docs/launch/distribution-plan.md` — researched channel playbook (r/macapps → Show HN → awesome-lists → directories; TikTok for non-tech users).
- `docs/launch/unsigned-distribution-findings.md` — Gatekeeper "Open Anyway" reality, DMG-not-zip rule, Homebrew ban, VoiceInk model.
- `docs/launch/launch-post-drafts.md` — HN/Reddit/press drafts. David posts these personally (HN bans AI-written replies).
- `README.md` — conversion-focused; `USER` is a literal placeholder for the GitHub username, replace at publish time (also in `../Portfolio` and the launch drafts).

## Current status & next steps

See `docs/HANDOFF.md` for session-by-session state, open questions, and the agreed next actions.
