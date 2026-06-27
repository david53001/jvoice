# JVoice UI Overhaul — Monochrome Themes, Redesigned Pill, Specific Errors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give JVoice a user-toggleable monochrome dark/light theme (persisted, sun/moon switch), a redesigned HUD pill (single centered row of J · animated waveform bars · stop, with a small bottom label, mic-reactive while recording / gentle shimmer while transcribing, and a smooth uncut glow), a wider 2-column Settings window, and specific detectable error messages (no generic "Something Went Wrong").

**Architecture:** A single `AppTheme` enum (`.dark`/`.light`) persisted inside the existing `SettingsState` JSON blob and exposed as `@Published var appTheme` on `VoiceCoordinator`. All custom-drawn chrome reads monochrome design tokens from a `Theme` struct (dark/light variants); native SwiftUI controls follow `.preferredColorScheme`. The HUD pill is rebuilt from scratch in `HUDView`, driven by an `AudioLevelMeter` (polls the existing `AVAudioRecorder` metering at 15 Hz). Errors funnel through a single `DictationError` enum (pure message data) plus two new detections (no-microphone, silent-clip). The menu-bar "J" template image is deliberately left untouched (it already adapts to the OS menu bar).

**Tech Stack:** Swift 5.9, SwiftPM, macOS 14+, SwiftUI + AppKit, AVFoundation. No new dependencies.

---

## Conventions & verification (read once before starting)

- **Build gate (every task):** `swift build` must succeed. Run it from the repo root `/Users/davidghermansteinberg/Desktop/Home/Code/JVoice`.
- **Pure-logic gate:** `./scripts/run-logic-tests.sh` compiles the dependency-free logic sources with a standalone assertion `main` and **executes** them locally. New Foundation-only logic (AppTheme, DictationError, AudioLevel) is added here AND to the authoritative swift-testing suite.
- **swift-testing suite** lives in `Tests/JVoiceTests/` and is the authority; it **compiles but executes 0 tests on this machine** (Command Line Tools only). So for suite-only tests, local verification = "`swift build` compiles + the file is added"; real execution happens in CI. Where a test can ALSO be expressed as a pure assertion, add it to `run-logic-tests.sh` for real local execution.
- **Streaming guarantee gate (only if you touch transcription/streaming):** `./scripts/verify-streaming.sh`.
- **UI has no automated visual test.** For UI tasks the gate is `swift build` plus a by-eye check. To see the app, the user runs `./scripts/install.sh` (release build → /Applications) — **do NOT run install yourself; ask the user to dogfood** when a visual checkpoint is reached.
- **Commits:** commit after each task. End every commit message with:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```
- **Do NOT** `git push`, add remotes, or publish (JVoice house rule).
- All new Swift source files belong to the single `JVoice` target — cross-area `import` is unnecessary (one module).

### Parallelization (for subagent-driven execution)
Phase 1 (theme foundation) is the shared prerequisite — land it first. Then three tracks can run in parallel:
- **Track A — Errors:** Tasks 5–9.
- **Track B — Audio meter + HUD pill:** Tasks 10–13 (Task 7 `AudioLevel` is a prerequisite of Task 10; include it in this track if Track A hasn't done it).
- **Track C — Settings:** Tasks 14–15.

`AudioLevel.normalize` (Task 7) is used by both Track A's silent-clip work and Track B's meter — whichever track runs first creates it; the other depends on it. Tasks 7 and 5 are listed under Track A but are independent leaf tasks.

---

## File structure

**New files**
- `Sources/JVoice/Models/AppTheme.swift` — `AppTheme` enum (`.dark`/`.light`), Foundation-only.
- `Sources/JVoice/UI/Theme.swift` — `Theme` monochrome token struct (SwiftUI), `dark`/`light` statics, `AppTheme.theme` bridge.
- `Sources/JVoice/Services/Audio/AudioLevel.swift` — pure `AudioLevel.normalize(dB)` math, Foundation-only.
- `Sources/JVoice/Services/Audio/AudioLevelMeter.swift` — `@MainActor ObservableObject` polling `AVAudioRecorder` metering.
- `Sources/JVoice/Services/Orchestration/DictationError.swift` — user-facing error enum (pure message data), Foundation-only.
- `Tests/JVoiceTests/AppThemeTests.swift`
- `Tests/JVoiceTests/DictationErrorTests.swift`
- `Tests/JVoiceTests/AudioLevelTests.swift`
- `Tests/JVoiceTests/SilentRecordingTests.swift`

**Modified files**
- `Sources/JVoice/Models/SettingsState.swift` — add `theme`, bump schema 1→2.
- `Sources/JVoice/Services/Audio/AudioInputRouter.swift` — add public `hasInputDevice()`.
- `Sources/JVoice/Services/Audio/RecordingManager.swift` — `levelMeter`, start/stop wiring, `isSilentRecording(at:)`.
- `Sources/JVoice/UI/HUDLayout.swift` — new pill geometry + glow padding.
- `Sources/JVoice/UI/HUDView.swift` — full monochrome redesign (rewrite).
- `Sources/JVoice/UI/HUDWindow.swift` — `update(state:theme:meter:)`.
- `Sources/JVoice/UI/SettingsView.swift` — 2-column grouped layout, tokens, sun/moon toggle (rewrite).
- `Sources/JVoice/UI/SettingsWindow.swift` — width 700, theme appearance.
- `Sources/JVoice/VoiceCoordinator.swift` — `appTheme`, persist/reset, theme propagation, error funnel, new detections.
- `Tests/JVoiceTests/SettingsStateMigrationTests.swift` — theme migration cases.
- `scripts/run-logic-tests.sh` — compile + assert AppTheme, DictationError, AudioLevel.

---

## Phase 0 — Branch & baseline

### Task 0: Feature branch + green baseline

**Files:** none (git only)

- [ ] **Step 1: Create a feature branch off the current branch**

Run:
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Code/JVoice
git checkout -b ui-overhaul-monochrome
```

- [ ] **Step 2: Confirm baseline builds**

Run: `swift build`
Expected: `Build complete!` (warnings OK).

- [ ] **Step 3: Confirm baseline logic tests pass**

Run: `./scripts/run-logic-tests.sh`
Expected: ends with `All logic tests passed.`

No commit (no changes yet).

---

## Phase 1 — Theme foundation (land first)

### Task 1: `AppTheme` enum

**Files:**
- Create: `Sources/JVoice/Models/AppTheme.swift`
- Create: `Tests/JVoiceTests/AppThemeTests.swift`
- Modify: `scripts/run-logic-tests.sh`

- [ ] **Step 1: Write the swift-testing test**

Create `Tests/JVoiceTests/AppThemeTests.swift`:
```swift
#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

@Test func appThemeToggleAlternates() {
    #expect(AppTheme.dark.toggled == .light)
    #expect(AppTheme.light.toggled == .dark)
}

@Test func appThemeUnknownDecodesToDark() throws {
    let json = "\"sepia\"".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AppTheme.self, from: json)
    #expect(decoded == .dark)
}

@Test func appThemeRoundTrips() throws {
    for theme in AppTheme.allCases {
        let data = try JSONEncoder().encode(theme)
        let back = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(back == theme)
    }
}
#endif
```

- [ ] **Step 2: Run the build to verify the test references a missing type**

Run: `swift build`
Expected: FAIL — `cannot find 'AppTheme' in scope`.

- [ ] **Step 3: Implement `AppTheme`**

Create `Sources/JVoice/Models/AppTheme.swift`:
```swift
import Foundation

/// User-selectable app appearance. Persisted in `SettingsState`; the sun/moon
/// toggle in Settings flips it. Drives the monochrome `Theme` tokens used by
/// every custom-drawn JVoice surface (HUD pill + Settings window).
public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dark:  return "Dark"
        case .light: return "Light"
        }
    }

    public var toggled: AppTheme {
        switch self {
        case .dark:  return .light
        case .light: return .dark
        }
    }
}

extension AppTheme {
    /// Fallback decoder: an unknown rawValue decodes to `.dark` instead of
    /// throwing, so a future renamed/removed case can't torpedo the whole
    /// SettingsState decode (mirrors `AppMode`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AppTheme(rawValue: raw) ?? .dark
    }
}
```

- [ ] **Step 4: Add real local assertions to the logic harness**

In `scripts/run-logic-tests.sh`, add `AppTheme.swift` to the `xcrun swiftc` source list (it is Foundation-only). Add this line immediately after the existing `AppMode.swift` line:
```bash
    "$REPO_ROOT/Sources/JVoice/Models/AppTheme.swift" \
```
Then add this assertion block in the heredoc, immediately before the final `if failures > 0 {` block:
```swift
print("AppTheme")
expectEqual(AppTheme.dark.toggled, .light, "dark toggles to light")
expectEqual(AppTheme.light.toggled, .dark, "light toggles to dark")
expectEqual(try! JSONDecoder().decode(AppTheme.self, from: "\"sepia\"".data(using: .utf8)!), .dark, "unknown theme → dark")
```

- [ ] **Step 5: Run the logic harness**

Run: `./scripts/run-logic-tests.sh`
Expected: prints the three `AppTheme` ✓ lines, ends `All logic tests passed.`

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit**
```bash
git add Sources/JVoice/Models/AppTheme.swift Tests/JVoiceTests/AppThemeTests.swift scripts/run-logic-tests.sh
git commit -m "feat(theme): add AppTheme enum with fallback decode + local logic test"
```

---

### Task 2: Persist `theme` in `SettingsState` (schema 1 → 2)

**Files:**
- Modify: `Sources/JVoice/Models/SettingsState.swift`
- Modify: `Tests/JVoiceTests/SettingsStateMigrationTests.swift`

- [ ] **Step 1: Add migration tests**

In `Tests/JVoiceTests/SettingsStateMigrationTests.swift`, add these tests inside the `#if canImport(Testing)` block (before the closing `#endif`):
```swift
@Test func newSettingsStateDefaultsToDarkTheme() {
    #expect(SettingsState().theme == .dark)
}

@Test func decodesV1BlobWithoutThemeAsDark() throws {
    // A schema-v1 blob predates the theme field; it must decode (v1 < current)
    // and default theme to .dark.
    let v1JSON = """
    {"schemaVersion":1,"mode":"casual","model":"tiny","language":"english",
     "customWords":[],"removeFillerWords":true}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SettingsState.self, from: v1JSON)
    #expect(decoded.theme == .dark)
    #expect(decoded.schemaVersion == SettingsState.currentSchemaVersion)
}

@Test func themeRoundTripsThroughSettingsState() throws {
    var s = SettingsState()
    s.theme = .light
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(SettingsState.self, from: data)
    #expect(back.theme == .light)
}
```

- [ ] **Step 2: Build to verify failure**

Run: `swift build`
Expected: FAIL — `value of type 'SettingsState' has no member 'theme'`.

- [ ] **Step 3: Add the `theme` field, bump schema, wire coding**

Edit `Sources/JVoice/Models/SettingsState.swift`:

Change the schema version line (line 4):
```swift
    public static let currentSchemaVersion: Int = 2
```

Add the stored property after `removeFillerWords` (after line 10):
```swift
    public var theme: AppTheme
```

Replace the `init(...)` (lines 17–29) with:
```swift
    public init(
        mode: AppMode = .casual,
        model: WhisperModelOption = .tiny,
        language: TranscriptionLanguage = .english,
        customWords: [String] = [],
        removeFillerWords: Bool = true,
        theme: AppTheme = .dark
    ) {
        self.mode = mode
        self.model = model
        self.language = language
        self.customWords = customWords
        self.removeFillerWords = removeFillerWords
        self.theme = theme
    }
```

Add `case theme` to `CodingKeys` (after `case removeFillerWords`):
```swift
        case theme
```

Add this decode line at the end of `init(from:)` (after the `removeFillerWords` decode, line 55):
```swift
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
```

Add this encode line at the end of `encode(to:)` (after the `removeFillerWords` encode, line 65):
```swift
        try container.encode(theme, forKey: .theme)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Verify existing logic harness still green** (SettingsState isn't in the harness, but confirm nothing regressed)

Run: `./scripts/run-logic-tests.sh`
Expected: `All logic tests passed.`

- [ ] **Step 6: Commit**
```bash
git add Sources/JVoice/Models/SettingsState.swift Tests/JVoiceTests/SettingsStateMigrationTests.swift
git commit -m "feat(theme): persist theme in SettingsState, bump schema to v2"
```

---

### Task 3: `Theme` monochrome design tokens

**Files:**
- Create: `Sources/JVoice/UI/Theme.swift`

- [ ] **Step 1: Implement the token struct**

Create `Sources/JVoice/UI/Theme.swift`:
```swift
import SwiftUI

/// Monochrome (pure black & white) design tokens — the single source of truth
/// for every JVoice surface we draw ourselves (HUD pill + Settings cards).
/// Native SwiftUI controls (segmented pickers, toggles, the shortcut recorder)
/// follow `.preferredColorScheme(colorScheme)`; these tokens cover the rest.
/// No hue anywhere — only neutral greys/black/white.
struct Theme {
    let colorScheme: ColorScheme

    // Surfaces
    let windowBackground: Color
    let surface: Color           // cards + pill body
    let inputBackground: Color
    let hairline: Color          // 1px borders / dividers

    // Content
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color

    // Pill
    let barFill: Color           // waveform bars + the "J" mark
    let pillBackground: Color
    let pillGlow: Color          // soft, even glow around the pill
    let pillDropShadow: Color

    /// Destructive affordance. Kept monochrome to honor the black/white
    /// direction; the confirmation dialog is the real safety net. (Reversible:
    /// swap to a red here if a coloured Quit/Reset is wanted later.)
    var danger: Color { textPrimary }

    static let dark = Theme(
        colorScheme: .dark,
        windowBackground: Color(white: 0.04),
        surface: Color(white: 0.075),
        inputBackground: Color(white: 0.10),
        hairline: Color.white.opacity(0.10),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.62),
        textMuted: Color.white.opacity(0.40),
        barFill: .white,
        pillBackground: Color(white: 0.05),
        pillGlow: Color.white.opacity(0.06),
        pillDropShadow: Color.black.opacity(0.45)
    )

    static let light = Theme(
        colorScheme: .light,
        windowBackground: Color(white: 0.93),
        surface: .white,
        inputBackground: Color(white: 0.96),
        hairline: Color.black.opacity(0.10),
        textPrimary: Color(white: 0.06),
        textSecondary: Color.black.opacity(0.55),
        textMuted: Color.black.opacity(0.40),
        barFill: Color(white: 0.06),
        pillBackground: .white,
        pillGlow: Color.black.opacity(0.10),
        pillDropShadow: Color.black.opacity(0.18)
    )
}

extension AppTheme {
    /// The concrete monochrome tokens for this appearance.
    var theme: Theme {
        switch self {
        case .dark:  return .dark
        case .light: return .light
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/JVoice/UI/Theme.swift
git commit -m "feat(theme): add monochrome Theme tokens (dark/light) + AppTheme bridge"
```

---

### Task 4: `appTheme` on `VoiceCoordinator` (persist + reset)

This task wires persistence and a propagation stub. The stub becomes real once HUDWindow/Settings are updated (Tasks 13–15); for now it compiles and persists.

**Files:**
- Modify: `Sources/JVoice/VoiceCoordinator.swift`

- [ ] **Step 1: Add the published property**

In `Sources/JVoice/VoiceCoordinator.swift`, add after the `removeFillerWords` published property (after line 95):
```swift
    @Published var appTheme: AppTheme {
        didSet {
            persistSettings()
            applyTheme()
        }
    }
```

- [ ] **Step 2: Initialize it in `init()`**

Add to `init()` after `self.removeFillerWords = settingsStore.state.removeFillerWords` (after line 157):
```swift
        self.appTheme = settingsStore.state.theme
```

- [ ] **Step 3: Persist it**

In `persistSettings()` add after `s.removeFillerWords = removeFillerWords` (after line 587):
```swift
        s.theme = appTheme
```

- [ ] **Step 4: Reset it**

In `resetSettings()` add after `removeFillerWords = settingsStore.state.removeFillerWords` (after line 349):
```swift
        appTheme = settingsStore.state.theme
```

- [ ] **Step 5: Add the propagation method (stub for now)**

Add this method near `updateHUD` (e.g., immediately after the `updateHUD(_:)` method, after line 320):
```swift
    /// Re-render theme-dependent surfaces when the user flips the sun/moon
    /// toggle. The Settings SwiftUI view re-renders automatically (it observes
    /// `appTheme` via `@ObservedObject`); the HUD pill and the Settings
    /// NSWindow chrome need an explicit nudge.
    private func applyTheme() {
        settingsWindow?.appearance = NSAppearance(named: appTheme == .dark ? .darkAqua : .aqua)
        // HUD restyle wired in Task 13 (update(state:theme:meter:)).
    }
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit**
```bash
git add Sources/JVoice/VoiceCoordinator.swift
git commit -m "feat(theme): VoiceCoordinator.appTheme published, persisted, reset-aware"
```

---

## Phase 2 — Specific errors (Track A)

### Task 5: `DictationError` enum

**Files:**
- Create: `Sources/JVoice/Services/Orchestration/DictationError.swift`
- Create: `Tests/JVoiceTests/DictationErrorTests.swift`
- Modify: `scripts/run-logic-tests.sh`

- [ ] **Step 1: Write the swift-testing test**

Create `Tests/JVoiceTests/DictationErrorTests.swift`:
```swift
#if canImport(Testing)
import Testing
@testable import JVoice

@Test func everyDictationErrorHasNonEmptySpecificMessage() {
    for e in DictationError.allCases {
        #expect(!e.message.isEmpty)
        // No case may fall back to the old generic copy.
        #expect(e.message.lowercased() != "something went wrong")
    }
}

@Test func dictationErrorMessagesAreDistinct() {
    let messages = DictationError.allCases.map(\.message)
    #expect(Set(messages).count == messages.count)
}

@Test func noMicrophoneMentionsMicrophone() {
    #expect(DictationError.noMicrophone.message.lowercased().contains("microphone"))
}
#endif
```

- [ ] **Step 2: Build to verify failure**

Run: `swift build`
Expected: FAIL — `cannot find 'DictationError' in scope`.

- [ ] **Step 3: Implement `DictationError`**

Create `Sources/JVoice/Services/Orchestration/DictationError.swift`:
```swift
import Foundation

/// Specific, user-facing dictation failures. One source of truth for the HUD
/// error copy — there is deliberately no generic fallback. Permission failures
/// (microphone / Accessibility) are handled separately by `PermissionError`
/// because they also open the relevant System Settings pane.
///
/// Foundation-only on purpose so the copy is verified by both the swift-testing
/// suite and scripts/run-logic-tests.sh.
public enum DictationError: Equatable, CaseIterable, Sendable {
    case noMicrophone
    case recorderFailedToStart
    case recordingInterrupted
    case recordingTooShort
    case noSpeechHeard
    case noTextFieldFocused
    case modelLoadFailed
    case transcriptionFailed
    case pasteFailed
    case clipboardBusy

    public var message: String {
        switch self {
        case .noMicrophone:
            return "No microphone detected. Connect one and try again."
        case .recorderFailedToStart:
            return "Couldn't start recording. Please try again."
        case .recordingInterrupted:
            return "Recording was interrupted (audio device changed)."
        case .recordingTooShort:
            return "That was too quick — hold the hotkey while you speak."
        case .noSpeechHeard:
            return "We didn't hear anything — check your mic volume and try again."
        case .noTextFieldFocused:
            return "No place to paste — click into a text field first."
        case .modelLoadFailed:
            return "The speech model failed to load. Please restart JVoice."
        case .transcriptionFailed:
            return "Couldn't transcribe that audio. Please try again."
        case .pasteFailed:
            return "Couldn't paste into this app."
        case .clipboardBusy:
            return "Clipboard was busy — try again."
        }
    }
}
```

- [ ] **Step 4: Add real local assertions to the logic harness**

In `scripts/run-logic-tests.sh`, add to the `xcrun swiftc` source list (Foundation-only), after the AppTheme line added in Task 1:
```bash
    "$REPO_ROOT/Sources/JVoice/Services/Orchestration/DictationError.swift" \
```
Add this assertion block before the final `if failures > 0 {`:
```swift
print("DictationError")
expect(DictationError.allCases.allSatisfy { !$0.message.isEmpty }, "every error has a message")
expect(DictationError.allCases.allSatisfy { $0.message.lowercased() != "something went wrong" }, "no generic fallback copy")
expect(Set(DictationError.allCases.map { $0.message }).count == DictationError.allCases.count, "messages are distinct")
expect(DictationError.noMicrophone.message.lowercased().contains("microphone"), "no-mic mentions microphone")
```

- [ ] **Step 5: Run the logic harness**

Run: `./scripts/run-logic-tests.sh`
Expected: prints the `DictationError` ✓ lines, ends `All logic tests passed.`

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit**
```bash
git add Sources/JVoice/Services/Orchestration/DictationError.swift Tests/JVoiceTests/DictationErrorTests.swift scripts/run-logic-tests.sh
git commit -m "feat(errors): add DictationError enum with specific, tested messages"
```

---

### Task 6: `AudioInputRouter.hasInputDevice()`

**Files:**
- Modify: `Sources/JVoice/Services/Audio/AudioInputRouter.swift`

- [ ] **Step 1: Expose an input-device presence check**

In `Sources/JVoice/Services/Audio/AudioInputRouter.swift`, change the visibility of `availableInputDevices()` from `private static` to `static` (line 82):
```swift
    static func availableInputDevices() -> [InputDevice] {
```
Then add this public helper immediately after that function (after line 86):
```swift
    /// True when at least one usable microphone (input channel) exists. Used to
    /// surface a clear "no microphone" error before attempting to record.
    static func hasInputDevice() -> Bool {
        !availableInputDevices().isEmpty
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/JVoice/Services/Audio/AudioInputRouter.swift
git commit -m "feat(errors): AudioInputRouter.hasInputDevice() for no-mic detection"
```

---

### Task 7: `AudioLevel.normalize` (pure)

This pure helper is shared by Task 8 (silent-clip uses ChunkPlanner, not this — see note) and Task 10 (the live meter). It maps AVAudioRecorder decibels to a 0…1 bar level.

**Files:**
- Create: `Sources/JVoice/Services/Audio/AudioLevel.swift`
- Create: `Tests/JVoiceTests/AudioLevelTests.swift`
- Modify: `scripts/run-logic-tests.sh`

- [ ] **Step 1: Write the swift-testing test**

Create `Tests/JVoiceTests/AudioLevelTests.swift`:
```swift
#if canImport(Testing)
import Testing
@testable import JVoice

@Test func audioLevelClampsSilenceToZero() {
    #expect(AudioLevel.normalize(-160) == 0)
    #expect(AudioLevel.normalize(-55) == 0)
}

@Test func audioLevelClampsLoudToOne() {
    #expect(AudioLevel.normalize(0) == 1)
    #expect(AudioLevel.normalize(5) == 1)
}

@Test func audioLevelIsMonotonicInBetween() {
    let quiet = AudioLevel.normalize(-40)
    let mid = AudioLevel.normalize(-20)
    let loud = AudioLevel.normalize(-5)
    #expect(quiet < mid)
    #expect(mid < loud)
    #expect(quiet >= 0 && loud <= 1)
}

@Test func audioLevelHandlesNaN() {
    #expect(AudioLevel.normalize(Float.nan) == 0)
}
#endif
```

- [ ] **Step 2: Build to verify failure**

Run: `swift build`
Expected: FAIL — `cannot find 'AudioLevel' in scope`.

- [ ] **Step 3: Implement `AudioLevel`**

Create `Sources/JVoice/Services/Audio/AudioLevel.swift`:
```swift
import Foundation

/// Pure mapping from an `AVAudioRecorder` average-power reading (dBFS, roughly
/// -160…0) to a 0…1 amplitude for the waveform bars. Kept dependency-free so
/// it runs in both the swift-testing suite and scripts/run-logic-tests.sh.
public enum AudioLevel {
    /// `floor` is the quietest dB treated as "silence" (maps to 0). Speech sits
    /// well above -55 dBFS, so anything below it flattens the bars.
    public static func normalize(_ db: Float, floor: Float = -55) -> Float {
        if db.isNaN { return 0 }
        if db <= floor { return 0 }
        if db >= 0 { return 1 }
        return (db - floor) / (0 - floor)
    }
}
```

- [ ] **Step 4: Add real local assertions to the logic harness**

In `scripts/run-logic-tests.sh`, add to the `xcrun swiftc` source list (Foundation-only):
```bash
    "$REPO_ROOT/Sources/JVoice/Services/Audio/AudioLevel.swift" \
```
Add this assertion block before the final `if failures > 0 {`:
```swift
print("AudioLevel.normalize")
expectEqual(AudioLevel.normalize(-160), 0, "very quiet → 0")
expectEqual(AudioLevel.normalize(-55), 0, "floor → 0")
expectEqual(AudioLevel.normalize(0), 1, "0 dB → 1")
expectEqual(AudioLevel.normalize(5), 1, "above 0 dB clamps to 1")
expect(AudioLevel.normalize(-40) < AudioLevel.normalize(-20), "monotonic increasing")
expectEqual(AudioLevel.normalize(Float.nan), 0, "NaN → 0")
```

- [ ] **Step 5: Run the logic harness**

Run: `./scripts/run-logic-tests.sh`
Expected: prints the `AudioLevel.normalize` ✓ lines, ends `All logic tests passed.`

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit**
```bash
git add Sources/JVoice/Services/Audio/AudioLevel.swift Tests/JVoiceTests/AudioLevelTests.swift scripts/run-logic-tests.sh
git commit -m "feat(audio): pure AudioLevel.normalize(dB) with local + suite tests"
```

---

### Task 8: Silent-clip detection (`RecordingManager.isSilentRecording`)

Reuses the existing, already-tested `ChunkPlanner.isSilent` on the finished WAV (via `WavTailReader`). Fail-open: if the file can't be parsed, return `false` so a recording we can't inspect still goes to transcription (the empty-transcript guard remains the backstop).

**Files:**
- Modify: `Sources/JVoice/Services/Audio/RecordingManager.swift`
- Create: `Tests/JVoiceTests/SilentRecordingTests.swift`

- [ ] **Step 1: Write the swift-testing test**

Create `Tests/JVoiceTests/SilentRecordingTests.swift`:
```swift
#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

/// Build a minimal PCM/16-bit/mono/16 kHz WAV on disk from Int16 samples so the
/// real WAV-reading + silence path is exercised (matches RecordingManager's
/// output format, which WavTailReader requires).
private func writeWav(_ samples: [Int16]) throws -> URL {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]
    }
    let dataBytes = samples.flatMap { le16(UInt16(bitPattern: $0)) }
    var bytes: [UInt8] = Array("RIFF".utf8) + le32(UInt32(36 + dataBytes.count)) + Array("WAVE".utf8)
    bytes += Array("fmt ".utf8) + le32(16)
    bytes += le16(1) + le16(1) + le32(16_000)
    bytes += le32(16_000 * 2) + le16(2) + le16(16)
    bytes += Array("data".utf8) + le32(UInt32(dataBytes.count)) + dataBytes
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("jvoice-test-\(UUID().uuidString).wav")
    try Data(bytes).write(to: url)
    return url
}

private func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}

@Test func silentRecordingDetected() throws {
    let url = try writeWav(tone(seconds: 1, amplitude: 0.0))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(RecordingManager.isSilentRecording(at: url))
}

@Test func speechRecordingNotSilent() throws {
    let url = try writeWav(tone(seconds: 1, amplitude: 0.5))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(!RecordingManager.isSilentRecording(at: url))
}

@Test func unreadableRecordingFailsOpen() {
    let bogus = URL(fileURLWithPath: "/nonexistent/jvoice-missing.wav")
    #expect(!RecordingManager.isSilentRecording(at: bogus))
}
#endif
```

- [ ] **Step 2: Build to verify failure**

Run: `swift build`
Expected: FAIL — `type 'RecordingManager' has no member 'isSilentRecording'`.

- [ ] **Step 3: Implement `isSilentRecording`**

In `Sources/JVoice/Services/Audio/RecordingManager.swift`, add this static method right after `isUsableRecording(at:minBytes:)` (after line 270, before the final closing brace):
```swift
    /// True when a finished recording contains no audio above the silence floor
    /// (user held the hotkey but didn't speak, or the mic captured nothing).
    /// Reuses the streaming pipeline's WAV reader + the proven
    /// `ChunkPlanner.isSilent` policy. Fails open (returns `false`) when the
    /// file can't be read, so an uninspectable recording still reaches
    /// transcription rather than being wrongly rejected.
    public static func isSilentRecording(at url: URL) -> Bool {
        guard let reader = WavTailReader.open(url: url),
              let samples = reader.samples(from: 0),
              !samples.isEmpty else {
            return false
        }
        return ChunkPlanner.isSilent(samples)
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Sanity-check the silence policy is intact**

Run: `./scripts/run-logic-tests.sh`
Expected: `All logic tests passed.` (the `ChunkPlanner.isSilent` checks still pass).

- [ ] **Step 6: Commit**
```bash
git add Sources/JVoice/Services/Audio/RecordingManager.swift Tests/JVoiceTests/SilentRecordingTests.swift
git commit -m "feat(errors): detect silent recordings via WavTailReader + ChunkPlanner.isSilent"
```

---

### Task 9: Funnel all dictation errors through `DictationError` + new detections

Replaces inline error strings and the generic transcription fallback with `DictationError`, and adds the no-mic and silent-clip checks. Permission flows (`PermissionError.microphoneDenied`/`accessibilityDenied`) are left exactly as they are.

**Files:**
- Modify: `Sources/JVoice/VoiceCoordinator.swift`

- [ ] **Step 1: Add a single error-presentation helper**

In `Sources/JVoice/VoiceCoordinator.swift`, add this method right after `showError(_:)` (after line 327):
```swift
    /// Single funnel for specific dictation failures — guarantees the HUD never
    /// shows a generic message and the copy stays in one tested place.
    private func show(_ error: DictationError) {
        updateHUD(.error(error.message))
        scheduleHUDReset(after: 3_000_000_000)
    }

    /// Map a thrown transcription error to a specific user-facing failure.
    private func dictationError(for error: Error) -> DictationError {
        if let t = error as? TranscriptionError {
            switch t {
            case .emptyTranscript:
                return .noSpeechHeard
            case .modelLoadFailed:
                return .modelLoadFailed
            case .audioFileMissing, .unsupportedAudioFile:
                return .transcriptionFailed
            }
        }
        return .transcriptionFailed
    }
```

- [ ] **Step 2: Add the no-microphone precheck in `startRecordingFlow()`**

In `startRecordingFlow()`, insert this immediately after the permission `guard granted else { ... }` block (after line 369), before `guard recordingManager.startRecording() else {`:
```swift
        guard AudioInputRouter.hasInputDevice() else {
            show(.noMicrophone)
            return
        }
```

- [ ] **Step 3: Replace the recording-start error switch with `DictationError`**

In `startRecordingFlow()`, replace the entire `if let err = recordingManager.lastError { switch err { ... } } else { ... }` block (lines 372–388) with:
```swift
            if let err = recordingManager.lastError {
                switch err {
                case .permissionDenied:
                    PermissionError.microphoneDenied.surfaceAndOpenSettings()
                    return
                case .engineSetupFailed:
                    show(.recorderFailedToStart)
                case .encodeFailure, .finishedUnsuccessfully:
                    show(.recordingInterrupted)
                case .fileTooSmall:
                    show(.recordingTooShort)
                }
            } else {
                show(.recorderFailedToStart)
            }
            return
```
(Note: `show(...)` already schedules the HUD reset, so the old `scheduleHUDReset()` line in this block is removed.)

- [ ] **Step 4: Replace the "No target app" error in `stopRecordingAndTranscribe()`**

Replace lines 440–441:
```swift
            updateHUD(.error("No target app — focus an app that accepts text before recording."))
            scheduleHUDReset(after: 3_000_000_000)
```
with:
```swift
            show(.noTextFieldFocused)
```

- [ ] **Step 5: Replace error sites in `finishTranscription()`**

Replace lines 460–462 (the `audioURL == nil` branch body):
```swift
            if let session { await session.cancel() }
            updateHUD(.error("No recording was captured."))
            scheduleHUDReset()
            return
```
with:
```swift
            if let session { await session.cancel() }
            show(.recorderFailedToStart)
            return
```

Replace lines 472–474 (the `!isUsableRecording` branch body):
```swift
            if let session { await session.cancel() }
            updateHUD(.error("Recording too short — please hold the hotkey longer."))
            scheduleHUDReset(after: 3_000_000_000)
```
with:
```swift
            if let session { await session.cancel() }
            show(.recordingTooShort)
```

Add the silent-clip precheck immediately AFTER the `!isUsableRecording` guard closes (after line 476, before the `// If the model isn't loaded yet` comment):
```swift
        if RecordingManager.isSilentRecording(at: audioURL) {
            if let session { await session.cancel() }
            show(.noSpeechHeard)
            return
        }
```

Replace the empty-processed branch (lines 509–510):
```swift
                updateHUD(.error("No speech detected."))
                scheduleHUDReset()
```
with:
```swift
                show(.noSpeechHeard)
```

Replace the paste-outcome error branches (lines 536–542):
```swift
            case .pasteboardLocked:
                updateHUD(.error("Pasteboard is busy — try again."))
                scheduleHUDReset()
                return
            case .targetRejected:
                updateHUD(.error("Unable to paste into the active app."))
                scheduleHUDReset()
                return
```
with:
```swift
            case .pasteboardLocked:
                show(.clipboardBusy)
                return
            case .targetRejected:
                show(.pasteFailed)
                return
```

Replace the catch block (lines 556–559):
```swift
        } catch {
            updateHUD(.error(error.localizedDescription))
            scheduleHUDReset()
        }
```
with:
```swift
        } catch {
            show(dictationError(for: error))
        }
```

- [ ] **Step 6: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Verify nothing in the logic/streaming guarantees regressed**

Run: `./scripts/run-logic-tests.sh && ./scripts/verify-streaming.sh`
Expected: both end with their success line.

- [ ] **Step 8: Commit**
```bash
git add Sources/JVoice/VoiceCoordinator.swift
git commit -m "feat(errors): route all dictation failures through DictationError; add no-mic + silent-clip detection"
```

---

## Phase 3 — Audio level meter (Track B)

### Task 10: `AudioLevelMeter` + RecordingManager wiring

**Files:**
- Create: `Sources/JVoice/Services/Audio/AudioLevelMeter.swift`
- Modify: `Sources/JVoice/Services/Audio/RecordingManager.swift`

Depends on Task 7 (`AudioLevel`).

- [ ] **Step 1: Implement the meter**

Create `Sources/JVoice/Services/Audio/AudioLevelMeter.swift`:
```swift
import AVFoundation
import Foundation

/// Publishes a smoothed 0…1 microphone level for the recording HUD bars. Polls
/// the existing `AVAudioRecorder` metering at a modest 15 Hz (the bars redraw
/// is the only continuous work while recording, and it's tiny — a handful of
/// capsules). Never rebuilds the HUD view; the bar subview observes `level`.
@MainActor
public final class AudioLevelMeter: ObservableObject {
    @Published public private(set) var level: Float = 0

    private var timer: Timer?
    private weak var recorder: AVAudioRecorder?
    private let fps: Double = 15

    public init() {}

    public func start(recorder: AVAudioRecorder) {
        self.recorder = recorder
        level = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        level = 0
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let target = AudioLevel.normalize(recorder.averagePower(forChannel: 0))
        // Equal-weight smoothing so bars glide rather than jitter.
        level = level * 0.5 + target * 0.5
    }
}
```

- [ ] **Step 2: Expose the meter on RecordingManager and drive it**

In `Sources/JVoice/Services/Audio/RecordingManager.swift`:

Add the property after `private var recorder: AVAudioRecorder?` (after line 31):
```swift
    /// Live mic level (0…1) for the recording HUD bars. Driven only while a
    /// recording is active.
    public let levelMeter = AudioLevelMeter()
```

In `startRecording()`, start the meter on the success path — add immediately after `self.isRecording = true` (after line 108), before `return true`:
```swift
            levelMeter.start(recorder: recorder)
```

In `stopRecording()`, stop the meter — add after `recorder = nil` (after line 142):
```swift
        levelMeter.stop()
```

In `tearDownFailedRecording()`, stop the meter — add after `recorder = nil` (after line 227):
```swift
        levelMeter.stop()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**
```bash
git add Sources/JVoice/Services/Audio/AudioLevelMeter.swift Sources/JVoice/Services/Audio/RecordingManager.swift
git commit -m "feat(audio): AudioLevelMeter polling recorder metering at 15Hz for HUD bars"
```

---

## Phase 4 — HUD pill redesign (Track B)

### Task 11: HUD geometry + glow padding

**Files:**
- Modify: `Sources/JVoice/UI/HUDLayout.swift`

- [ ] **Step 1: Rewrite HUDLayout**

Replace the entire contents of `Sources/JVoice/UI/HUDLayout.swift` with:
```swift
import AppKit

enum HUDLayout {
    static let pillCorner: CGFloat = 28
    static let pillHeight: CGFloat = 56
    static let pillMinWidth: CGFloat = 240

    /// Transparent margin around the pill INSIDE the window, so the soft glow
    /// fades out fully before the window edge. The old square-glow bug came
    /// from sizing the window to the pill's `fittingSize`, which excludes shadow
    /// blur — the blur then clipped at the window border. This padding must
    /// exceed the largest glow radius used in HUDView (28) plus any offset.
    static let glowPadding: CGFloat = 40

    static func minimumSize(for state: HUDState) -> NSSize {
        NSSize(width: pillMinWidth + glowPadding * 2,
               height: pillHeight + glowPadding * 2)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL — `HUDView.swift` and `HUDWindow.swift` still reference `HUDLayout.hudPillSize`. This is expected; Tasks 12–13 replace those usages. (If executing strictly task-by-task and you need a green build here, proceed directly into Task 12 in the same working session and build once at the end of Task 12.)

> Build/commit checkpoint: Tasks 11, 12, 13 are tightly coupled (they share the HUDView/HUDWindow API). Implement all three, then build once and commit at the end of Task 13. The per-task commits below can be squashed into one if preferred.

---

### Task 12: HUDView — full monochrome redesign

**Files:**
- Modify (rewrite): `Sources/JVoice/UI/HUDView.swift`

- [ ] **Step 1: Replace the entire contents of `Sources/JVoice/UI/HUDView.swift`**

```swift
import SwiftUI

struct HUDView: View {
    let state: HUDState
    var theme: Theme = .dark
    var meter: AudioLevelMeter? = nil
    var onStop: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .recording:
            RecordingPill(theme: theme, meter: meter, onStop: onStop)
        case .preparingModel:
            PreparingModelPill(theme: theme)
        case .transcribing:
            TranscribingPill(theme: theme)
        case .done, .error:
            StatusPill(state: state, theme: theme)
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Shared pill chrome

private extension View {
    /// Monochrome pill body + soft, even glow that fully fades within the
    /// surrounding glow padding (no square clip).
    func pillChrome(theme: Theme, minWidth: CGFloat = HUDLayout.pillMinWidth, maxWidth: CGFloat? = nil) -> some View {
        self
            .frame(minWidth: minWidth,
                   maxWidth: maxWidth,
                   minHeight: HUDLayout.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: HUDLayout.pillCorner, style: .continuous)
                    .fill(theme.pillBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HUDLayout.pillCorner, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: theme.pillGlow, radius: 16)
            .shadow(color: theme.pillGlow.opacity(0.6), radius: 28)
            .shadow(color: theme.pillDropShadow, radius: 12, x: 0, y: 6)
            .padding(HUDLayout.glowPadding)
    }
}

// MARK: - J mark

private struct JMark: View {
    let theme: Theme
    var body: some View {
        Text("J")
            .font(.system(size: 22, weight: .heavy))
            .foregroundStyle(theme.barFill)
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - Waveform bars

/// Recording: mic-reactive bars (driven by the live meter, with a subtle
/// per-bar oscillation so they look alive even at a steady level).
private struct ReactiveBars: View {
    @ObservedObject var meter: AudioLevelMeter
    let theme: Theme
    let barCount = 15
    private let minH: CGFloat = 4
    private let maxH: CGFloat = 26

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(theme.barFill)
                        .frame(width: 3, height: height(i, t))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: maxH)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let level = CGFloat(meter.level)                       // 0…1
        let osc = 0.55 + 0.45 * CGFloat(sin(t * 6 + Double(i) * 0.7)) // 0.1…1
        return minH + (maxH - minH) * level * osc
    }
}

/// Transcribing: a gentle, low-amplitude shimmer (no mic input during decode).
private struct ShimmerBars: View {
    let theme: Theme
    let barCount = 15
    private let minH: CGFloat = 4
    private let maxH: CGFloat = 11

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(theme.barFill.opacity(0.85))
                        .frame(width: 3, height: height(i, t))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .accessibilityHidden(true)
    }

    private func height(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let wave = 0.5 + 0.5 * CGFloat(sin(t * 3 + Double(i) * 0.6))
        return minH + (maxH - minH) * wave
    }
}

// MARK: - Stop button

private struct StopButton: View {
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.barFill.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.barFill.opacity(0.45), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.barFill)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PanelPressableButtonStyle())
        .accessibilityLabel("Stop recording")
    }
}

// MARK: - Bottom label

private struct PillLabel: View {
    let text: String
    let theme: Theme
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 7, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(theme.textMuted)
    }
}

// MARK: - Recording pill

private struct RecordingPill: View {
    let theme: Theme
    let meter: AudioLevelMeter?
    let onStop: (() -> Void)?

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                JMark(theme: theme)
                if let meter {
                    ReactiveBars(meter: meter, theme: theme)
                } else {
                    ShimmerBars(theme: theme) // defensive fallback
                }
                if let onStop {
                    StopButton(theme: theme, action: onStop)
                } else {
                    Color.clear.frame(width: 22)
                }
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                PillLabel(text: "Recording", theme: theme)
                    .padding(.bottom, 6)
            }
        }
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
    }
}

// MARK: - Transcribing pill

private struct TranscribingPill: View {
    let theme: Theme
    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                JMark(theme: theme)
                ShimmerBars(theme: theme)
                Color.clear.frame(width: 22) // keep bars centered (no stop button)
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                PillLabel(text: "Transcribing", theme: theme)
                    .padding(.bottom, 6)
            }
        }
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }
}

// MARK: - Preparing-model pill (keeps a status icon + the live timer)

/// Shown while the Whisper model loads / does its first-ever CoreML compile
/// (~2¼ min for Large on first use). The ticking counter proves the app is
/// alive — a static pill reads as a hang and invites a force-quit that restarts
/// the compile from zero.
private struct PreparingModelPill: View {
    let theme: Theme
    @State private var startDate = Date()

    private static func elapsed(_ start: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    Text("One-time setup — keep JVoice open · \(Self.elapsed(startDate, context.date))")
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .pillChrome(theme: theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing model")
    }
}

// MARK: - Status pill (done / error)

private struct StatusPill: View {
    let state: HUDState
    let theme: Theme

    var body: some View {
        let text: String = {
            if case .error(let message) = state, !message.isEmpty { return message }
            return state.headline
        }()

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.barFill.opacity(0.12))
                    .overlay(Circle().strokeBorder(theme.barFill.opacity(0.30), lineWidth: 1))
                    .frame(width: 28, height: 28)
                Image(systemName: state.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .pillChrome(theme: theme, maxWidth: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
```

(Implementation note: `state.systemImageName` already returns `checkmark.circle.fill` for `.done` and `exclamationmark.triangle.fill` for `.error` — kept, now monochrome.)

- [ ] **Step 2:** proceed to Task 13 (shared API), then build.

---

### Task 13: HUDWindow theme/meter wiring + coordinator propagation

**Files:**
- Modify: `Sources/JVoice/UI/HUDWindow.swift`
- Modify: `Sources/JVoice/VoiceCoordinator.swift`

- [ ] **Step 1: Update HUDWindow init + update signature**

In `Sources/JVoice/UI/HUDWindow.swift`:

Change the stored hosting controller's initial root view (line 17) to pass an explicit theme:
```swift
        self.hostingController = NSHostingController(rootView: HUDView(state: .idle, theme: .dark))
```

Replace the `update(state:)` method (lines 49–61) with:
```swift
    func update(state: HUDState, theme: AppTheme = .dark, meter: AudioLevelMeter? = nil) {
        currentState = state
        hostingController.rootView = HUDView(
            state: state,
            theme: theme.theme,
            meter: meter,
            onStop: onStop
        )
        ignoresMouseEvents = (state != .recording)

        if state.isVisible {
            sizeToFit()
            positionAtBottomCenter()
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }
```

- [ ] **Step 2: Pass theme + meter from the coordinator**

In `Sources/JVoice/VoiceCoordinator.swift`, replace the `updateHUD(_:)` body's single line `hudWindow.update(state: state)` (line 309) with:
```swift
        hudWindow.update(state: state, theme: appTheme, meter: recordingManager.levelMeter)
```

Update `applyTheme()` (from Task 4) to actually restyle a visible HUD — replace its body with:
```swift
    private func applyTheme() {
        settingsWindow?.appearance = NSAppearance(named: appTheme == .dark ? .darkAqua : .aqua)
        hudWindow.update(state: hudState, theme: appTheme, meter: recordingManager.levelMeter)
    }
```

- [ ] **Step 3: Build (covers Tasks 11–13)**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Logic + streaming guarantees still green**

Run: `./scripts/run-logic-tests.sh && ./scripts/verify-streaming.sh`
Expected: both succeed.

- [ ] **Step 5: Commit**
```bash
git add Sources/JVoice/UI/HUDLayout.swift Sources/JVoice/UI/HUDView.swift Sources/JVoice/UI/HUDWindow.swift Sources/JVoice/VoiceCoordinator.swift
git commit -m "feat(hud): monochrome pill — J + mic-reactive bars + bottom label + uncut glow, theme-aware"
```

- [ ] **Step 6: Visual checkpoint (ask the user)**

Ask the user to run `./scripts/install.sh` and dictate, verifying: recording bars react to voice, transcribing shimmers low, the "J" shows, the label sits at the bottom, and the glow is smooth (no square). Do not run install yourself.

---

## Phase 5 — Settings window (Track C)

### Task 14: SettingsWindow width + theme appearance

**Files:**
- Modify: `Sources/JVoice/UI/SettingsWindow.swift`

- [ ] **Step 1: Widen the window and set initial appearance**

Replace the `init(coordinator:)` body in `Sources/JVoice/UI/SettingsWindow.swift` (lines 6–18) with:
```swift
    init(coordinator: VoiceCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: coordinator.appTheme == .dark ? .darkAqua : .aqua)
        center()
        contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator))
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: FAIL — `SettingsView` still hardcodes `.frame(width: 380, height: 520)`. Fixed in Task 15. (Build once at the end of Task 15.)

---

### Task 15: SettingsView — 2-column grouped layout, tokens, sun/moon toggle

**Files:**
- Modify (rewrite): `Sources/JVoice/UI/SettingsView.swift`

- [ ] **Step 1: Replace the entire contents of `Sources/JVoice/UI/SettingsView.swift`**

```swift
import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

// MARK: - Section card (theme-aware)

private struct SettingsSection<Content: View>: View {
    let title: String
    let theme: Theme
    let content: Content

    init(_ title: String, theme: Theme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(theme.textMuted)
                    .frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.7)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(theme.hairline).frame(height: 0.5)

            content.padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Button style (theme-aware)

private struct SettingsButtonStyle: ButtonStyle {
    let theme: Theme
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        let c = destructive ? theme.danger : theme.textPrimary
        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(c.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(c.opacity(0.25), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.70 : 1.0)
    }
}

// MARK: - Sun/moon theme toggle

private struct ThemeToggle: View {
    @Binding var selection: AppTheme
    let theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            icon("sun.max.fill", on: selection == .light) { selection = .light }
            icon("moon.fill", on: selection == .dark) { selection = .dark }
        }
        .padding(3)
        .background(
            Capsule().fill(theme.inputBackground)
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
        )
        .accessibilityLabel("Appearance")
    }

    private func icon(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? theme.textPrimary : theme.textMuted)
                .frame(width: 26, height: 20)
                .background(
                    Capsule().fill(on ? theme.barFill.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var coordinator: VoiceCoordinator
    @State private var newWord = ""
    @State private var showResetConfirm = false

    var body: some View {
        let theme = coordinator.appTheme.theme

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header with sun/moon toggle (top-right)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("JVoice")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Menu bar transcription controls")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer()
                    ThemeToggle(selection: $coordinator.appTheme, theme: theme)
                }
                .padding(.bottom, 2)

                // Stats — full width
                statsSection(theme)

                // Two columns: controls (left) · your data (right)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        modelSection(theme)
                        processingSection(theme)
                        voiceStyleSection(theme)
                        languageSection(theme)
                        shortcutSection(theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 12) {
                        recentTranscriptsSection(theme)
                        customWordsSection(theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                footer(theme)
            }
            .padding(18)
        }
        .background(theme.windowBackground)
        .preferredColorScheme(theme.colorScheme)
        .frame(width: 700, height: 560)
    }

    // MARK: Sections

    private func statsSection(_ theme: Theme) -> some View {
        SettingsSection("Stats", theme: theme) {
            HStack(spacing: 0) {
                stat("\(coordinator.totalWordsSpoken)", "total words", theme)
                Rectangle().fill(theme.hairline).frame(width: 0.5, height: 44)
                stat(coordinator.averageWPM > 0 ? String(format: "%.0f", coordinator.averageWPM) : "—", "avg WPM", theme)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ value: String, _ label: String, _ theme: Theme) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func modelSection(_ theme: Theme) -> some View {
        SettingsSection("Whisper Model", theme: theme) {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Model", selection: $coordinator.whisperModel) {
                    ForEach(WhisperModelChoice.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(coordinator.whisperModel.guidance)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func processingSection(_ theme: Theme) -> some View {
        SettingsSection("Processing", theme: theme) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove Filler Words")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text("Strip um, uh, er, ah, hmm from output")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Toggle("", isOn: $coordinator.removeFillerWords)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func voiceStyleSection(_ theme: Theme) -> some View {
        SettingsSection("Voice Style", theme: theme) {
            Picker("Tone", selection: $coordinator.toneMode) {
                ForEach(ToneMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func languageSection(_ theme: Theme) -> some View {
        SettingsSection("Language", theme: theme) {
            Picker("Language", selection: $coordinator.transcriptionLanguage) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func shortcutSection(_ theme: Theme) -> some View {
        SettingsSection("Keyboard Shortcut", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                #if canImport(KeyboardShortcuts)
                KeyboardShortcuts.Recorder("Toggle Recording:", name: .toggleRecording)
                    .foregroundStyle(theme.textSecondary)
                #else
                Text("Shortcut customization is unavailable in this build.")
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
                #endif
                Text("Default: ⌥ Space")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentTranscriptsSection(_ theme: Theme) -> some View {
        SettingsSection("Recent Transcripts", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.recentTranscripts.isEmpty {
                    Text("No transcripts yet.")
                        .font(.footnote)
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(coordinator.recentTranscripts) { entry in
                                TranscriptRow(
                                    text: entry.text,
                                    theme: theme,
                                    onCopy: { coordinator.copyToClipboard(entry.text) },
                                    onDelete: { coordinator.deleteTranscript(entry.id) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 220)

                    HStack {
                        Spacer()
                        Button("Clear all") { coordinator.clearTranscriptHistory() }
                            .buttonStyle(SettingsButtonStyle(theme: theme))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customWordsSection(_ theme: Theme) -> some View {
        SettingsSection("Custom Words", theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.customWords.isEmpty {
                    Text("No custom words added.")
                        .font(.footnote)
                        .foregroundStyle(theme.textMuted)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(coordinator.customWords, id: \.self) { word in
                                HStack {
                                    Text(word)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    Button {
                                        coordinator.removeCustomWord(word)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(theme.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 150)
                }

                HStack(spacing: 6) {
                    TextField("Add word (e.g. VS Code)", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(theme.hairline, lineWidth: 1)
                                )
                        )
                        .onSubmit { submitWord() }

                    Button("Add") { submitWord() }
                        .buttonStyle(SettingsButtonStyle(theme: theme))
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ theme: Theme) -> some View {
        HStack {
            Button("Restore Default Settings") { showResetConfirm = true }
                .buttonStyle(SettingsButtonStyle(theme: theme, destructive: true))
                .confirmationDialog(
                    "Reset all JVoice settings to defaults?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) { coordinator.resetSettings() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your custom words, model choice, and language will be restored to defaults, and your recent transcripts will be cleared. Recording statistics will not be affected.")
                }

            Spacer()
            Button("Quit JVoice", role: .destructive) { coordinator.quitApp() }
                .buttonStyle(SettingsButtonStyle(theme: theme, destructive: true))
        }
    }

    private func submitWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coordinator.addCustomWord(trimmed)
        newWord = ""
    }
}

// MARK: - TranscriptRow

private struct TranscriptRow: View {
    let text: String
    let theme: Theme
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                Button {
                    onCopy()
                    flashCopied()
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? theme.inputBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func flashCopied() {
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            justCopied = false
        }
    }
}
```

- [ ] **Step 2: Build (covers Tasks 14–15)**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/JVoice/UI/SettingsView.swift Sources/JVoice/UI/SettingsWindow.swift
git commit -m "feat(settings): wider 2-column monochrome layout with sun/moon theme toggle"
```

- [ ] **Step 4: Visual checkpoint (ask the user)**

Ask the user to dogfood (`./scripts/install.sh`): confirm the Settings window is wider with controls left / data right, the sun/moon toggle flips dark↔light and persists across relaunch, and native controls (pickers, toggle, shortcut recorder) read correctly in both themes.

---

## Phase 6 — Final verification & docs

### Task 16: Full verification + brief doc touch-ups

**Files:**
- Modify: `Sources/JVoice/UI/CLAUDE.md` (one-line description updates)

- [ ] **Step 1: Full build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: All local logic + streaming gates**

Run: `./scripts/run-logic-tests.sh && ./scripts/verify-streaming.sh`
Expected: both end with their success line (AppTheme, DictationError, AudioLevel.normalize, ChunkPlanner sections all ✓).

- [ ] **Step 3: Confirm the test suite still compiles** (executes 0 locally; CI runs it)

Run: `swift test 2>&1 | tail -5`
Expected: compiles without errors (0 tests executed locally is expected).

- [ ] **Step 4: Update the UI area brief**

In `Sources/JVoice/UI/CLAUDE.md`, update the `SettingsView.swift / SettingsWindow.swift` bullet to describe the new 700-wide 2-column monochrome layout with the sun/moon theme toggle, and the `HUDView.swift` bullet to describe the monochrome pill (J + mic-reactive waveform bars + bottom label). Add a one-line pointer to `Theme.swift` (monochrome tokens) and note that recording/transcribing show animated bars while preparing/done/error keep status icons. Keep it to the existing terse style.

- [ ] **Step 5: Commit**
```bash
git add Sources/JVoice/UI/CLAUDE.md
git commit -m "docs(ui): refresh area brief for monochrome themes + redesigned pill"
```

- [ ] **Step 6: Final dogfood checkpoint (ask the user)**

Ask the user to run `./scripts/install.sh` and verify end-to-end in both themes:
- Recording pill: J shown, bars react to voice, label bottom-center, smooth glow.
- Transcribing pill: gentle low shimmer.
- Trigger an error (e.g., start with no text field focused) → specific message.
- Sun/moon toggle persists across relaunch (theme saved like other settings).

---

## Self-review (completed by plan author)

**Spec coverage:**
- Wider Settings, same widgets, less scrolling → Tasks 14–15 (Option B grouped 2-column, 700-wide). ✅
- Dark + light monochrome themes, sun/moon top-right, persisted → Tasks 1–4, 15. ✅
- Pill: remove mic/talking icon, animated rounded bars; recording mic-reactive (lightweight), transcribing low shimmer → Tasks 7, 10, 12. ✅
- "J" logo in pill → Task 12 (`JMark`). ✅
- Centered row (J·bars·stop) with small bottom label → Task 12 layout. ✅
- Glow no longer square/cut off → Task 11 (glow padding > blur radius) + Task 12 chrome. ✅
- Recording + Transcribing get bars; Preparing/Done/Error keep restyled icons → Task 12. ✅
- Specific detectable errors, no generic fallback; new no-mic + silent-clip detection → Tasks 5, 6, 8, 9. ✅
- Menu-bar "J" untouched (adapts natively) → not modified anywhere. ✅
- Multi-subagent execution → Parallelization section. ✅

**Placeholder scan:** none — every code step contains full code; every command has expected output.

**Type consistency:** `AppTheme`/`Theme`/`AppTheme.theme`, `HUDView(state:theme:meter:onStop:)`, `HUDWindow.update(state:theme:meter:)`, `AudioLevelMeter` (`start(recorder:)`/`stop()`/`level`), `AudioLevel.normalize(_:floor:)`, `RecordingManager.levelMeter` / `isSilentRecording(at:)`, `AudioInputRouter.hasInputDevice()`, `DictationError` cases + `message`, and the coordinator's `show(_:)` / `dictationError(for:)` are used consistently across tasks. HUDLayout exposes `pillCorner`/`pillHeight`/`pillMinWidth`/`glowPadding`/`minimumSize(for:)`; the old `hudPillSize` is removed and all its usages are replaced in Tasks 12–13.

**Build-order note:** Tasks 11–13 and 14–15 each leave an intentionally-broken intermediate build (shared API rename); each pair builds green at the end of its last task. This is called out inline.
