# Changelog

All notable changes to JVoice — a free, open-source macOS menu-bar voice-dictation app (press ⌥Space to record, on-device speech recognition via WhisperKit, styled text pasted into the frontmost app; zero network calls at runtime) — are documented here. WhisperKit is an Apple-Silicon-optimised on-device Whisper inference library. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased] — 2026-06-28

### Added

- **Monochrome dark/light theme.** A new `AppTheme` enum (`dark` / `light`, in `Sources/JVoice/Models/AppTheme.swift`) is persisted in `SettingsState` at schema version 2. A sun/moon toggle in the Settings window flips the appearance at runtime. `VoiceCoordinator.appTheme` exposes the active theme as a `@Published` (SwiftUI reactive) property. A `Theme` struct (`Sources/JVoice/UI/Theme.swift`) provides the design tokens — pure blacks, whites, and neutral greys, no hue — used by the HUD (heads-up display) pill and Settings window. Unknown theme values decode safely to `.dark`.

- **Mic-reactive waveform bars in the HUD.** `AudioLevelMeter` (`Sources/JVoice/Services/Audio/AudioLevelMeter.swift`) polls `AVAudioRecorder` metering at 15 Hz with equal-weight smoothing. A pure `AudioLevel.normalize(dB:)` function (`Sources/JVoice/Services/Audio/AudioLevel.swift`) maps the decibel reading to a 0–1 level. The recording HUD bars resize in real time to microphone input.

- **`DictationError` enum** (`Sources/JVoice/Services/Orchestration/DictationError.swift`). Ten specific, user-facing error messages replace the previous generic fallback. Two new failure paths are detected: `noMicrophone` (via `AudioInputRouter.hasInputDevice()`) and `noSpeechHeard` (via a new `RecordingManager.isSilentRecording` check that reads the recorded WAV file using `WavTailReader` — an internal growing-WAV parser — and tests it with `ChunkPlanner.isSilent` — an internal silence-detection utility).

- New test files (run in CI — continuous integration, via `.github/workflows/test.yml`): `AppThemeTests`, `AudioLevelTests`, `DictationErrorTests`, `SilentRecordingTests`, `SettingsStateMigrationTests`, `MenuBarIconTests`, `StatsStoreTests`, `TextProcessorTests`, `TranscriptHistoryStoreTests`, `VoiceCoordinatorLogicTests`. `DictationError` message copy is also covered by `scripts/run-logic-tests.sh` (executes locally without Xcode).

### Changed

- **Redesigned HUD pill** (`Sources/JVoice/UI/HUDView.swift`, `HUDLayout.swift`, `HUDWindow.swift`). The recording and transcribing states now show a centered horizontal row: the "J" mark · animated waveform bars · a stop button, with a short status label underneath. The transcribing state shows a low-amplitude shimmer. `HUDLayout.glowPadding` prevents the pill glow from clipping square at the window edge. All surfaces are styled with `Theme` tokens.

- **Wider, 2-column Settings window** (`Sources/JVoice/UI/SettingsView.swift`, `SettingsWindow.swift`). Window width increased to 700 pt. Controls (Whisper Model, Processing, Voice Style, Language, Keyboard Shortcut) occupy the left column; user data (Recent Transcripts, Custom Words) the right. Stats appear full-width at the top. The sun/moon theme toggle is in the top-right corner. A Restore-Defaults / Quit row is pinned at the footer.

- `SettingsState` schema bumped to version 2 to store the persisted `appTheme` field.
