# Codebase Scan Report

**Scanned:** /Users/davidghermansteinberg/Desktop/Home/Code/JVoice (excluding docs/demo-video, .build)
**Date:** 2026-06-06
**Project profile:** Single macOS menu-bar dictation app (Swift 5.9, SwiftPM, WhisperKit on-device), ~4.3k source LOC across 32 files + ~1.3k test LOC across 16 files. No web frontend; dev-only Remotion project under docs/demo-video.
**Agents run:** CORE-ARCH, CORE-QUALITY, CORE-TESTS, CORE-DEPS, CORE-DOCS, BACKEND-CORRECTNESS×1, BACKEND-SECURITY (light), IMPROVEMENTS

> Items marked **[FIXED 2026-06-06]** were addressed in the same session as this scan.

---

## Executive Summary

JVoice is a healthy, well-layered app with above-average discipline for its size: clean coordinator-over-services architecture, versioned settings with corruption recovery, deliberate DI seams, zero TODO debt, and zero hardcoded secrets. Three findings genuinely matter: **(1)** CI pins Xcode 15.4, whose toolchain cannot run swift-testing — 78 of 96 test cases silently never execute and the "did tests run" guard is fooled by the 4 XCTest-fallback files **[FIXED]**; **(2)** `Package.resolved` is gitignored, so builds aren't reproducible and the open-ended WhisperKit `from: 1.0.0` range becomes a real supply-chain exposure **[FIXED]**; **(3)** raw microphone WAVs can be orphaned in the temp directory on quit-while-recording / recorder-failure paths — at odds with the privacy-first positioning **[FIXED]**. Everything else is medium-or-below: bounded correctness edges in new vocabulary code **[FIXED]**, UX gaps around model loading **[FIXED]**, and a stock of dead convenience API worth pruning before open-sourcing.

## Health Scorecard

| Dimension                     | Score | Top Finding |
|-------------------------------|-------|-------------|
| Architecture                  | 🟢    | Clean coordinator+services; god-object pressure building in VoiceCoordinator (588 LOC) |
| Code Quality                  | 🟢    | ~20 dead alias methods double several types' API surface; zero TODO/FIXME debt |
| Backend Correctness           | 🟡    | Pending-engine swap lost vocabulary updates [FIXED]; short-vocab-word length gate loose |
| Backend Security/Privacy      | 🟡    | Temp WAV orphans on quit/failure paths [FIXED]; clean secrets/network posture |
| Test Coverage                 | 🔴→🟢 | CI never executed the swift-testing suite (78/96 cases skipped, false green) [FIXED] |
| Dependencies                  | 🟡    | Package.resolved untracked → unpinned WhisperKit in CI [FIXED]; licenses all GPL-compatible |
| Documentation                 | 🟡    | CLAUDE.md architecture map missing today's services [FIXED]; README undersells vocabulary v2 [FIXED] |

---

## Critical Issues (Fix Now)

1. 🔴 **CI silently skips the swift-testing suite** — `.github/workflows/test.yml` pins Xcode 15.4 (Swift 5.10); `canImport(Testing)` is false there, so the 12 swift-testing-only files compile to nothing. The grep guard (`Test (Suite|case|Run)`) is satisfied by the 4 XCTest-fallback files → false green. **[FIXED: workflow now uses Xcode 16.4 on macos-15 and asserts a minimum executed swift-testing case count.]**
2. 🔴 **`Package.resolved` gitignored** — every CI run/fresh clone re-resolves; a future WhisperKit 1.x lands unreviewed. **[FIXED: removed from .gitignore so the pin gets committed.]**
3. 🟠 **Temp WAV privacy leak** — `quitApp()` discarded the in-flight recording URL; recorder failure handlers left partial files; no startup sweep. Raw speech audio could persist in `/tmp` for days. **[FIXED: delete on quit, delete in all three failure handlers, best-effort `jvoice-*.wav` sweep at launch.]**
4. 🟠 **Vocabulary lost across pending-engine swap** — `TranscriptionManager`'s defer-promotion installed the queued engine without re-applying the latest custom words. **[FIXED: manager remembers the last pushed vocabulary and re-applies it on promotion.]**
5. 🟠 **Silent 2–3 minute model preparation** — first use of the Large model specializes for minutes with only a generic "Transcribing" pill (or nothing) as feedback; reads as a hang. **[FIXED: HUD now shows a "Preparing model" state whenever dictation has to wait for a model load.]**
6. 🟠 **`WhisperModelLocator` completeness check too narrow** — checked only encoder/decoder weights; a download interrupted after those could pass the check yet lack other required artifacts. **[FIXED: required-file list extended to MelSpectrogram weights + config.json. tokenizer.json deliberately NOT required — WhisperKit stores tokenizers outside the model folder, so requiring it would force eternal re-downloads.]**

## Architecture & Structure (Good)

- Coordinator pattern over single-responsibility services; layering genuinely respected (no service→coordinator references; `SystemActions.errorHandler` is a clean error-inversion shim).
- 🟡 `VoiceCoordinator.swift` (588 LOC, 14 @Published) is accreting both view-model and pipeline-orchestrator roles. Recommended refactor: extract a `DictationSession` for the record→transcribe→paste pipeline. *(Deferred — structural, not urgent.)*
- 🟡 Settings state duplicated across six @Published mirrors + `settingsState` struct, synced by hand (`isInitializing` guard exists only to suppress the resulting write cascade). Recommended: single source of truth with computed bindings. *(Deferred.)*
- 🔵 Bundle assembly is script-owned (`install.sh`); CI doesn't verify the bundle layout. *(Deferred — release-workflow task will cover.)*
- 🔵 One persistence leak: `jvoice.app.didPromptAXOnLaunch` read/written directly in the coordinator.

## Code Quality (Good)

- 🟡 Complexity hotspots: `PhoneticMatcher.correct` (4-level nesting, labeled breaks), `VoiceCoordinator.finishTranscription` (~78 lines). Readable but dense.
- 🟠 **Dead convenience API** (zero callers, confirmed): `RecordingManager.start/stop/toggle/toggleRecording/phase/elapsedTime/hasRecordedAudio/recordingStartedAt`; `PasteManager.stageText/clearStagedText/clear/performPaste`; `TextProcessor.shared/transform`; `TranscriptionManager.transcribe(_:)` overload; `SettingsStore.update`; most of `HUDState`'s computed props (`displayText/subtitle/accentRole/isBusy/isTerminal/payload`) + `AccentRole`. *(Deliberately NOT removed this session — pre-existing surface, flagged for David's call before open-sourcing.)*
- 🔵 Duplication: `ToneMode`↔`AppMode` and `WhisperModelChoice`↔`WhisperModelOption` bridge enums (~90 lines of ceremony); twin `synthesizeCommandVPaste` variants; three hand-rolled debounce-task idioms.
- Zero TODO/FIXME/HACK markers; no commented-out code; error handling consistently typed and surfaced.

## Backend — Correctness & Edge Cases

- 🟠 Pending-engine vocabulary staleness **[FIXED]** (see Critical #4).
- 🟡 `PhoneticMatcher` length gate is loosest exactly for the shortest (most collision-prone) entries: 3-letter words accept 0–6-letter candidates. Contained by the lev≤1 cap; tighten if false positives surface in dogfooding.
- 🟡 Multi-token already-correct vocab entries ("VS Code" spelled right) were re-replaced, dropping interior punctuation in rare cases. **[FIXED: exact-match early-out now covers multi-token windows.]**
- 🟡 `RecordingError.fileTooSmall` is declared and handled but never produced — dead error path (the real check is `isUsableRecording` later). *(Flagged, not removed.)*
- 🟡 `averageWPM` is a lifetime aggregate (lifetime words / lifetime recording seconds) — drifts toward a meaningless constant. *(Product decision; deferred.)*
- 🔵 `toggleRecording`'s stop branch wraps a synchronous call in `Task` (needless hop, correctness unaffected). 🔵 Whisper-hallucination stripping is exact-match only. 🔵 `--bench` trailing flags fall through silently (dev tool).

## Backend — Security & Privacy (light pass)

- 🟠 Temp WAV lifecycle **[FIXED]** (see Critical #3).
- 🟡 `setup-signing.sh` hardcodes `pass:jvoice` for the throwaway self-signed P12 — harmless for the dev cert; would matter only if repurposed for a real identity.
- 🟡 `BenchRunner` prints transcripts to stdout and ships in release builds (not `#if DEBUG`) — acceptable for a deliberate hidden dev mode.
- 🔵 Last transcript persists in UserDefaults with no "clear" affordance (it IS the user-facing fix-last-transcript feature; consider a clear button someday).
- ✅ Zero-network claim verified for first-party code (only Apple settings deep-links + WhisperKit's one-time HF model download). No secrets. No injection surface. Clipboard save/restore handled carefully (lazy/promised pasteboard types may not survive restore — inherent to the approach).

## Test Coverage & Quality

- 🔴 CI execution gap **[FIXED]** (see Critical #1).
- 96 swift-testing cases across 16 files; strong coverage of the text/logic "brain" (TextProcessor, PhoneticMatcher, migration, locator), thin-to-absent on orchestration (`VoiceCoordinator` has one assertion-free smoke test), `HUDState`, `StatsStore`, `BenchRunner`, `HotKeyManager`.
- 🟡 `PasteManagerTests` mutates the real `NSPasteboard.general` (CI clipboard clobber, order-sensitivity).
- 🟡 Debounce test asserts existence, not coalescing; race test asserts nothing.
- `scripts/run-logic-tests.sh` provides genuine local execution for the pure-logic sources (this machine cannot run XCTest/swift-testing).

## Dependencies & Package Health

- WhisperKit 1.0.0 (= latest tag, verified), KeyboardShortcuts exact 1.10.0, transitive swift-argument-parser 1.8.2. All MIT/Apache-2.0 — GPL-3.0 compatible.
- 🔴 Lock not tracked **[FIXED — .gitignore]**; consider also pinning WhisperKit `exact: "1.0.0"` (David's call; lock-commit largely neutralizes the risk).
- 🟡 Remotion packages (docs/demo-video) are proprietary-licensed dev tooling — never linked into the GPL binary; documented boundary recommended at publish time.
- Demo-video npm lock: present, fresh, `npm audit` clean.

## Documentation & DX

- README launch-ready; "Open Anyway" dance accurately documented twice.
- 🟡 CLAUDE.md architecture map predated today's services **[FIXED: PhoneticMatcher, VocabularyPrompt, BenchRunner, J status item, bench/harness scripts documented]**.
- 🟡 README undersold vocabulary v2 **[FIXED: custom-dictionary copy updated]**.
- Missing (deferred to publish prep): CONTRIBUTING/BUILDING.md (the launch research itself calls it a trust lever), troubleshooting section, changelog, `setup-signing.sh` mention in README build path.
- 🔵 Speed plan doc describes the superseded unconditional `withoutTimestamps`; annotated by the implementation's code comment. **[Annotated in plan doc.]**

---

## Recommended Improvements (Non-Blocking)

**Implemented this session:**
- 💡 Model picker caption: surfaces size/speed guidance (incl. Large first-use download/preparation warning) — `SettingsView` + demo-video panel synced.
- 💡 Menu bar "transcribing" state (idle J / red mic recording / tinted waveform transcribing) — `MenuBarController` + demo synced.
- 💡 HUD "Preparing model" state (see Critical #5).
- 💡 Harness↔canonical-tests cross-reference comment in `run-logic-tests.sh`.

**Deferred (S effort):** sound feedback on start/paste; `Task.sleep(for: .seconds(n))` + named constants for HUD timings; shared JVoicePalette for HUD/Settings colors; Makefile; swiftformat/swiftlint configs; `engines` field in demo package.json.
**Deferred (M effort):** push-to-talk (hold) mode; transcript history ring buffer; collapse bridge enums; collapse settings mirrors; `DictationSession` extraction; model download progress in HUD (WhisperKit progress callback).
**Deferred (L effort):** streaming/eager transcription for long dictations (would fix the 53s-clip ~41s wall time — WhisperKit 1.0.0's timestamped multi-window decode is inherently slow; revisit on a future WhisperKit release).

---

## Consolidated Recommendations

### Immediate (done this session)
CI swift-testing execution; Package.resolved tracking; temp-WAV lifecycle; vocabulary re-push on engine promotion; model-locator completeness; preparing-model HUD; multi-token exact early-out; docs sync.

### Short-term (before launch)
Dogfood via `scripts/install.sh`; release-DMG workflow (already planned); CONTRIBUTING/BUILDING.md + troubleshooting README section; prune dead API surface; fix PasteManager general-pasteboard test; give the race test a real invariant; consider `exact:` pin for WhisperKit.

### Long-term (roadmap)
`DictationSession` extraction + settings single-source-of-truth; push-to-talk; transcript history; model download progress; streaming transcription; sub-group `Services/` (Audio/Persistence/Text).
