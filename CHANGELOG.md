# Changelog

All notable changes to JVoice — a free, open-source macOS menu-bar voice-dictation app (press ⌥Space to record, on-device speech recognition via WhisperKit, styled text pasted into the frontmost app; zero network calls at runtime) — are documented here. WhisperKit is an Apple-Silicon-optimised on-device Whisper inference library. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased] — 2026-07-02

### Added

- **Dictation feature parity with the Windows port (six features).** JVoice has an in-progress Windows port (on the `origin/windows-port` git branch); these six dictation features were ported back to macOS so the two apps behave the same. Each is TDD-tested — pure logic is executed locally by `scripts/run-logic-tests.sh` and mirrored in the CI (continuous integration) swift-testing suite under `Tests/JVoiceTests/`.
  1. **Developer-terms correction pack** (`Sources/JVoice/Services/Transcription/DeveloperTerms.swift`). An opt-out (on by default) pack of ~165 canonical spellings of common programming terms (e.g. "node js" → "Node.js", "type script" → "TypeScript", "c sharp" → "C#", "jason" → "JSON"), keyed by how Whisper tends to mis-render them. It is folded into the post-processing correction dictionary *underneath* the user's own custom words (their words win). Ambiguous everyday English words (cursor, bolt, render, warp, grok, llama, …) are deliberately excluded so ordinary dictation is never corrupted. Toggle: Settings → Processing → "Developer Terms".
  2. **Dictate-to-translate** (`translateToEnglish`). Speak any supported language and paste English: sets WhisperKit's decode task to `.translate` (WhisperKit is the on-device Whisper inference library; `DecodingOptions.task = .translate` makes Whisper translate to English). The spoken language is kept as the source hint. Toggle: Settings → Language → "Translate to English".
  3. **App-aware modes + a new "Code" tone.** A new `AppMode.code` tone applies minimal formatting (keeps casing, symbols and punctuation exactly as spoken — for terminals/editors). A pure resolver (`Sources/JVoice/Services/Transcription/AppModeResolver.swift`) picks a tone from the paste target's macOS bundle identifier: user rules first (case-insensitive substring), then a built-in list of code apps (VS Code, Terminal, iTerm2, Xcode, JetBrains IDEs, Cursor, Warp, …) → Code. Settings → "App Modes": a master "Auto-switch by App" toggle plus a per-app rule list with a click-to-cycle tone chip. `Code` is selectable only as a per-app override, not in the manual tone picker.
  4. **Clipboard-only paste** (`copyToClipboardOnly`). Puts the transcript on the clipboard (visible to clipboard-history managers) instead of auto-pasting it with a synthesized ⌘V. Needs no Accessibility permission. Toggle: Settings → Processing → "Copy to Clipboard".
  5. **Time-saved stat** (`StatsStore.estimatedMinutesSaved`). Estimates minutes saved by dictating vs. typing at a 40-words-per-minute baseline, floored at 0. Shown as a third cell in the Settings Stats card.
  6. **Undo-last-paste hotkey** (opt-in second global shortcut, no default). Sends the target app's own Undo (⌘Z) to reverse the last paste. One-shot and gated on that app still being frontmost; unset for clipboard-only dictations. Recorder: Settings → Keyboard Shortcut → "Undo Last Paste".
- New test files (CI): `Tests/JVoiceTests/DeveloperTermsTests.swift`, `Tests/JVoiceTests/AppModeResolverTests.swift`. New `AppModeRule` model (`Sources/JVoice/Models/AppModeRule.swift`).

- **Monochrome dark/light theme.** A new `AppTheme` enum (`dark` / `light`, in `Sources/JVoice/Models/AppTheme.swift`) is persisted in `SettingsState` at schema version 2. A sun/moon toggle in the Settings window flips the appearance at runtime. `VoiceCoordinator.appTheme` exposes the active theme as a `@Published` (SwiftUI reactive) property. A `Theme` struct (`Sources/JVoice/UI/Theme.swift`) provides the design tokens — pure blacks, whites, and neutral greys, no hue — used by the HUD (heads-up display) pill and Settings window. Unknown theme values decode safely to `.dark`.

- **Mic-reactive waveform bars in the HUD.** `AudioLevelMeter` (`Sources/JVoice/Services/Audio/AudioLevelMeter.swift`) polls `AVAudioRecorder` metering at 15 Hz with equal-weight smoothing. A pure `AudioLevel.normalize(dB:)` function (`Sources/JVoice/Services/Audio/AudioLevel.swift`) maps the decibel reading to a 0–1 level. The recording HUD bars resize in real time to microphone input.

- **`DictationError` enum** (`Sources/JVoice/Services/Orchestration/DictationError.swift`). Ten specific, user-facing error messages replace the previous generic fallback. Two new failure paths are detected: `noMicrophone` (via `AudioInputRouter.hasInputDevice()`) and `noSpeechHeard` (via a new `RecordingManager.isSilentRecording` check that reads the recorded WAV file using `WavTailReader` — an internal growing-WAV parser — and tests it with `ChunkPlanner.isSilent` — an internal silence-detection utility).

- New test files (run in CI — continuous integration, via `.github/workflows/test.yml`): `AppThemeTests`, `AudioLevelTests`, `DictationErrorTests`, `SilentRecordingTests`, `SettingsStateMigrationTests`, `MenuBarIconTests`, `StatsStoreTests`, `TextProcessorTests`, `TranscriptHistoryStoreTests`, `VoiceCoordinatorLogicTests`. `DictationError` message copy is also covered by `scripts/run-logic-tests.sh` (executes locally without Xcode).

### Changed

- **Redesigned HUD pill** (`Sources/JVoice/UI/HUDView.swift`, `HUDLayout.swift`, `HUDWindow.swift`). The recording and transcribing states now show a centered horizontal row: the "J" mark · animated waveform bars · a stop button, with a short status label underneath. The transcribing state shows a low-amplitude shimmer. `HUDLayout.glowPadding` prevents the pill glow from clipping square at the window edge. All surfaces are styled with `Theme` tokens.

- **Wider, 2-column Settings window** (`Sources/JVoice/UI/SettingsView.swift`, `SettingsWindow.swift`). Window width increased to 700 pt. Controls (Whisper Model, Processing, Voice Style, Language, Keyboard Shortcut) occupy the left column; user data (Recent Transcripts, Custom Words) the right. Stats appear full-width at the top. The sun/moon theme toggle is in the top-right corner. A Restore-Defaults / Quit row is pinned at the footer.

- `SettingsState` schema bumped to version 2 to store the persisted `appTheme` field.

- `SettingsState` (`Sources/JVoice/Models/SettingsState.swift`) schema bumped to version 3 for the five new dictation-parity settings (`developerTerms` — defaults ON; `translateToEnglish`, `copyToClipboardOnly`, `appAwareModes` — default OFF; `appModeRules` — defaults empty). Old version-1/version-2 settings blobs decode cleanly with the new fields at their defaults.

### Fixed

- **Whisper hallucination filter catches more silence artifacts.** `TextProcessor.removeWhisperHallucinations` (`Sources/JVoice/Services/Transcription/TextProcessor.swift`) drops whole-transcript "hallucinations" — text Whisper invents over near-silent or noisy audio — before it is pasted. Three gaps were closed: (1) YouTube-style sign-offs ("Thanks for watching", "Subscribe to my channel", "Bye") are now caught in **every** tone style, including Casual, which strips the trailing "." that the filter previously needed; (2) a transcript made **entirely of punctuation or symbols** — a stray "-", an ellipsis "…", or Whisper's music-note "♪ ♪" runs over background music — is dropped, not just the old ASCII `.,;:!?` set; (3) a hallucinated phrase **wrapped in leading/surrounding marks** ("- Thanks for watching", "… Bye", "♪ Thanks for watching ♪") is matched by comparing with surrounding marks trimmed from both ends. Real content carrying such marks (e.g. "- send the report by Friday") is left untouched.

- **Filler-word removal strips the hesitations "uhm" and "erm."** `TextProcessor.removeDisfluencies` (same file) already removed um/uh/er/ah/hmm, but missed the common m-trailing forms "uhm"/"erm" (neither is an English word). They are now removed when filler removal is enabled, while real words ending in those letters — "term", "firm", "warm", "error" — are preserved.

### Performance

- **Lower latency for streaming-while-recording transcription.** `ChunkPlanner.plan` (`Sources/JVoice/Services/Transcription/ChunkPlanner.swift`) decides where to cut the still-growing recording into chunks that are transcribed during recording. It now cuts at the **earliest** silence-level pause in range instead of the globally quietest one — so each chunk is emitted as soon as a valid pause appears (and chunks stay smaller, so they decode faster), with no loss of cut safety since every candidate is already below the silence threshold. Validated end-to-end with the `scripts/verify-transcription.py` harness (`base` Whisper model): streaming word-retention and spurious-word counts were byte-identical before and after the change — zero accuracy regression.

These accuracy and latency changes were developed on the `perf-loop/auto-improvements` branch via an autonomous, test-first improvement loop; the per-change rationale, baselines, and verification results are recorded in `docs/perf-loop-journal.md`.
