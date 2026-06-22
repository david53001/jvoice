# CLAUDE.md — JVoice

Standalone macOS menu-bar voice-dictation app. Press ⌥Space anywhere → record → on-device WhisperKit transcription → tone-styled text pasted into the frontmost app. Free, open-source, privacy-first: zero network calls at runtime (only the one-time Whisper model download), no telemetry, no accounts.

## Provenance

Extracted 2026-06-06 from `../MacOSUtils` (David's multi-utility app, formerly named JVoice). **Never modify `../MacOSUtils`** — it is a separate, active project. This repo is the public-facing standalone product.

## Hard rules

- **NO publishing without David's explicit go-ahead.** Do not `gh repo create`, `git push`, or add remotes. He has two gh accounts (`david53001` active, `da97d`); publishing is deliberately on hold. Same applies to posting anywhere (HN/Reddit drafts exist in `docs/launch/` — David posts those himself).
- **$0 budget.** No Apple Developer account → unsigned distribution (ad-hoc signed DMG via GitHub Releases). Homebrew is NOT an option (bans unsigned casks as of Sept 2026 — see `docs/launch/unsigned-distribution-findings.md`). Everything must stay free: GitHub Pages for the site, free CI, no paid services.
- The app stays **free forever**; potential future model is VoiceInk-style (free buildable source + paid prebuilt binary) — but that's a David decision, not yours.

## Build & test

- `swift build` — must pass. SwiftPM, Swift 5.9, macOS 14+. Deps: WhisperKit (≥1.0.0), KeyboardShortcuts (exact 1.10.0). `Package.resolved` is tracked deliberately (reproducible builds).
- `swift test` — **compiles but executes 0 tests locally**: this machine has Command Line Tools only (no swift-testing runner). Real test runs happen in CI (`.github/workflows/test.yml`, macos-15 + Xcode 16, which asserts ≥90 swift-testing cases actually executed — older Xcode silently compiles the suite out via `#if canImport(Testing)`).
- `./scripts/run-logic-tests.sh` — REAL local verification for the pure-logic sources (TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard incl. a 120-case loop fuzz, WavTail, ChunkPlanner): compiles them with a standalone assertion main and runs it.
- `./scripts/verify-streaming.sh` — REAL local verification (compiles + EXECUTES, no WhisperKit/mic) of the streaming session's data-loss guarantee (empty non-silent chunk → fallback, never a silent drop) and the regurgitation-recovery policy, using mock decoders.
- `python3 scripts/verify-transcription.py --model tiny|base|small|large [--quick]` — end-to-end harness: generates many `say` clips (varied length/pauses/voices, custom words spoken or not) and scores word-retention (no dropped speech) + spurious-vocab (no hallucinated custom words) across whole-file AND streaming. Needs the model downloaded.
- `.build/release/JVoice --bench <wav> [--model tiny|base|small|large] [--vocab "A,B"] [--stream] [--lang en|ro] [--no-prompt]` — hidden CLI mode for measuring transcription speed and verifying vocabulary biasing / streaming end-to-end on this machine (generate clips with `say` + `afconvert`). `--stream` simulates a live recording at 10×; `--no-prompt` A/B-tests the decoder prompt.
- `swift scripts/generate-icon.swift` — regenerates `Resources/AppIcon.icns` (black-squircle "J") and `docs/demo-video/public/app-icon.png`.
- `./scripts/install.sh` — release build, signs with the local "JVoice Self-Signed" keychain cert, installs to /Applications. Only run when David asks to install/dogfood.
- Bundle ID is `com.jvoice.app` — deliberately NOT `com.jvoice.JVoice` (that's MacOSUtils'; both apps coexist on this machine). UserDefaults namespace: `jvoice.app.*`.

## Architecture (Sources/JVoice/)

- `VoiceCoordinator.swift` — central orchestrator: hotkey → record → transcribe → process → paste flow, HUD state (menu bar mirrors it), stats.
- `Services/` — RecordingManager (AVAudioRecorder, orphan-WAV sweep), TranscriptionManager (WhisperKit engine; WhisperModelLocator). **Custom-word accuracy + robustness is layered**: VocabularyPrompt builds the decoder-conditioning `promptTokens` (the main accuracy lever — gets "Li-Fraumeni"/"VS Code" right; kept ON by default); RepetitionGuard detects/strips "prompt regurgitation" (the decoder reciting the vocab list on pauses/silence) and flags it via `scrub`; RegurgitationRecovery re-decodes the same audio *without* the prompt **only when** a decode regurgitated or came back empty — keeping prompt accuracy in the common case while making the failure mode (loops, scattered insertions, dropped speech) unreachable. The engine also duration-gates `withoutTimestamps` (long clips MUST keep timestamps — WhisperKit 1.0.0 truncates otherwise) and runs `TextProcessor.stripDecoderArtifacts` (drops `[BLANK_AUDIO]`-style sentinels). **Streaming-while-recording**: WavTail (growing-WAV parser), ChunkPlanner (pure silence-cut chunk policy), StreamingTranscriptionSession (decodes completed chunks during recording; any failure or an empty non-silent chunk → whole-file fallback, *never* a silent drop). **Post-processing**: TextProcessor (tone styles, filler removal, exact custom-word corrections, hallucination-sentinel stripping), PhoneticMatcher (fuzzy sound-alike correction, "jay voice"→"JVoice"). Plus PasteManager (Accessibility paste), HotKeyManager, AudioInputRouter (keeps Bluetooth on A2DP by recording from built-in mic), SettingsStore, StatsStore, LastTranscriptStore, BenchRunner (hidden `--bench` CLI).
- `Models/` — AppMode (tone styles), HUDState (incl. `.preparingModel` for first-load waits), WhisperModelOption, TranscriptionLanguage, SettingsState.
- `UI/` — HUDView/HUDWindow (recording/preparing/transcribing/done pills), SettingsView/SettingsWindow, MenuBarController (status item: bold "J" template image idle, red mic recording, cyan waveform transcribing + NSMenu).

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

## Windows port (in progress — `windows/`)

A native **Windows** port of JVoice lives under `windows/` (a separate .NET solution). The macOS Swift app above is **unchanged and read-only** — it is the reference and the source-of-truth for the accuracy "brain" and its invariants. **Do not modify `Sources/`, `Tests/`, `Package.swift`, or `Resources/` when working on the Windows port.**

- **Stack:** C# on **.NET 9**, **WPF** (`win-x64`, WinExe), speech via **Whisper.net** (managed whisper.cpp bindings, GGML models) with **CUDA** GPU acceleration + a CPU fallback. This replaces macOS-only WhisperKit/CoreML. NAudio for capture, H.NotifyIcon.Wpf for the tray, SkiaSharp for the icon. The dev machine has an RTX 3060 Ti (CUDA) + i5-12400 (AVX2).
- **The brain ports faithfully.** `JVoice.Core` reproduces TextProcessor / PhoneticMatcher / VocabularyPrompt / RepetitionGuard / RegurgitationRecovery / ChunkPlanner / WavTail / StreamingTranscriptionSession 1:1 (every constant verbatim), locked by `JVoice.Tests` (xUnit) translated from the Swift tests. The WhisperKit-specific workarounds (SuppressBlankFilter, single-window timestamp trap) are dropped — whisper.cpp doesn't need them.
- **Plan:** the complete, zero-context, phase-by-phase implementation plan is in `docs/superpowers/plans/2026-06-22-windows-port-0{0..5}-*.md`. Read `…-00-overview.md` first (architecture, canonical names, constraints, rejected alternatives, cross-phase reconciliation §10). Phases: 1 Core brain → 2 Whisper engine → 3 platform (audio/hotkey/paste/persistence) → 4 WPF UI + VoiceCoordinator → 5 packaging/CI/docs.
- **Build/test/run:** `dotnet build windows/JVoice.sln -c Release` · `dotnet test windows/JVoice.Tests` · `dotnet run --project windows/JVoice.App` · publish single-file per Phase 5.
- **Same constraints as the macOS side:** $0 budget (no paid code-signing → unsigned `.exe`; document the SmartScreen "More info → Run anyway" step, the Windows analog of Gatekeeper "Open Anyway"); GPL-3.0 (all NuGet deps MIT-compatible); privacy (zero runtime network except the one-time GGML model download); **NO publishing/pushing without David's go-ahead.** Default hotkey is **Ctrl+Shift+Space** (⌥Space has no clean Windows equivalent — Alt+Space is the system window menu).
- **Status:** all 5 phases implemented. `dotnet build windows/JVoice.sln -c Release` = 0 errors; `dotnet test` = 122/122; on-device transcription verified (whisper-smoke / `--bench`, Vulkan GPU + CPU); **the GUI launches to the tray** (two startup crashes found & fixed: `TaskbarIcon.ForceCreate` efficiency-mode COMException, and the PNG→`System.Drawing.Icon` conversion). Remaining: David's interactive **dogfood** of the live dictation loop + HUD/Settings visuals (`docs/launch/windows-dogfood-checklist.md`); optional Inno installer + verify-transcription harness. Full as-built state, pinned versions, and all deviations/gotchas are in `docs/HANDOFF-WINDOWS.md` (the zero-context anchor).
