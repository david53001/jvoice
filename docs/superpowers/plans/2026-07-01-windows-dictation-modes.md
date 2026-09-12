# Plan — JVoice Windows: quick-wins bundle + app-aware modes

**Date:** 2026-07-01 · **Branch:** `feat/dictation-modes` (off `windows-port`) · **Scope:** `windows/` only (macOS `Sources/` is read-only).

## Context & goal

JVoice is a push-to-talk voice-dictation app (hotkey → record → Whisper transcribe →
post-process → paste). This plan adds two batches of user-facing features that David
picked, in order:

1. **Quick-wins bundle** (4 small features).
2. **App-aware modes** (auto-switch the dictation tone/mode based on the foreground app).

"Done" = `dotnet build windows/JVoice.sln -c Release` is 0 errors, `dotnet test
windows/JVoice.Tests` is all-green (555 existing + new tests), each feature works in a
`--bench`/render check where verifiable offline, and each is a clean commit on
`feat/dictation-modes`. **Do not push / open PRs** (David publishes manually).

### Ground rules that constrain this work
- `JVoice.Core` is the portable "brain," ported 1:1 from macOS and locked by `JVoice.Tests`.
  Windows-only Core additions ARE allowed when clearly marked (precedent: `DeveloperTerms`,
  `HighPassSilence`, `NonSpeechAnnotation`). New enum value `ToneStyle.Code` is such an addition.
- `Core/Policy` must stay **pure** (no Win32/IO). Rule-resolution + stats math live there;
  the privileged OS reads (foreground exe path) live in `JVoice.App/Platform/System`.
- Game-detection invariant: read-only OS signals only. The new foreground-exe helper uses
  `PROCESS_QUERY_LIMITED_INFORMATION` + `QueryFullProcessImageName` ONLY (no memory reads).
- `$0`/privacy/GPL unchanged. No new network. No telemetry.

### Schema versioning decision
All new persisted fields land under a **single** `SettingsState` schema bump **v2 → v3**
(one version for this whole branch). New fields all have safe defaults and per-field JSON
fallbacks, so a v2 `settings.json` upgrades transparently and a partially-written v3 file
also loads. `SettingsStateJson` uses `TryGet… ?? default` per field — keep that pattern.

## Key files (verified insertion points)

| Concern | File | Anchor |
|---|---|---|
| Settings model | `JVoice.Core/Models/SettingsState.cs` | record params + `CurrentSchemaVersion` (currently `2`) |
| Settings JSON | `JVoice.Core/Models/SettingsStateJson.cs` | `Serialize` (~L33-64), `Deserialize` (~L70-92) |
| Tone enum | `JVoice.Core/Models/ToneStyle.cs` | `enum ToneStyle` |
| Tone apply | `JVoice.Core/Text/TextProcessor.cs` | `Format(text, mode)` (~L115-127); `Process` (~L24-41) |
| Stats math | `JVoice.Core/Policy/StatsMath.cs` | add `EstimatedMinutesSaved` |
| Orchestrator | `JVoice.App/VoiceCoordinator.cs` | paste at ~L785; stats at ~L802-815; props ~L40-180; `PersistSettings` ~L425; hotkey register ~L246; `SetHotkey` ~L364 |
| Paste | `JVoice.App/Platform/System/Paster.cs` | `Paste`, `Stage` (clipboard-only exists), `SendCtrlV` (~L196) |
| Hotkey | `JVoice.App/Platform/System/GlobalHotkey.cs` + `JVoice.Core/Models/HotkeyChord.cs` | second instance for undo |
| Foreground | `JVoice.App/Platform/System/ForegroundWindowTracker.cs` | `GetForegroundWindowNow`; paste `target` HWND |
| Engine | `JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs` | builder ~L253-274; ctor `_language` |
| Settings UI | `JVoice.App/UI/SettingsView.xaml` (+ `.xaml.cs`) | two-column masonry; stats card (green) ~L41-68 |

## Phase 1 — Quick-wins bundle

### 1a. Copy-to-clipboard-only mode
- **Setting:** `bool CopyToClipboardOnly = false` (v3).
- **Behavior:** in `VoiceCoordinator` finish path (~L785), when on, call `_paster.Stage(processed)`
  (already exists — sets clipboard, no Ctrl+V) instead of `_paster.Paste(...)`. Skip the
  `PasteOutcome` switch. Still record stats / recent transcript. HUD: since paste is silent
  today, keep it silent (text is on the clipboard); no error path needed for Stage (returns bool —
  if false, surface "Clipboard is busy — try again." like `ClipboardLocked`).
- **UI:** toggle in the behavior/advanced card. Label "Copy to clipboard (don't auto-paste)".
- **Assumption:** global toggle (not per-invocation). Documented for review.

### 1b. Undo-last-paste hotkey
- **Setting:** `HotkeyChord? UndoHotkey = null` (v3). **null = disabled (opt-in).**
- **Why opt-in / no default:** `GlobalHotkey` swallows its chord globally, so registering any
  common chord (e.g. Ctrl+Z) would break that key everywhere. Ship it unassigned; user picks a
  rare chord in Settings.
- **Capture:** after a successful paste (~L789 `PasteOutcome.Ok`) store `_lastPastedText = processed`.
- **Second hotkey:** add a second `GlobalHotkey _undoHotkey = new()`; register in `Start()` /
  re-register on change **only when `UndoHotkey` is non-null**; wire its trigger to `UndoLastPaste()`.
- **`UndoLastPaste()`:** send Ctrl+Z to the current foreground app via a new `Paster.SendUndo(hwnd)`
  (mirror `SendCtrlV`, VK 0x5A 'Z'). Pragmatic cross-app undo. **Caveat (document in UI tooltip):**
  it sends the app's Undo — if the user typed after the paste, it undoes that instead.
- **UI:** a second hotkey recorder + a "Clear" to disable, near the main hotkey. Label
  "Undo-last-paste hotkey (optional)".

### 1c. Time-saved stat
- **Core (TDD):** `StatsMath.EstimatedMinutesSaved(int totalWords, double totalSeconds)`:
  `typingMinutes = totalWords / TypingWpmBaseline` (const `40.0`), `spokenMinutes = totalSeconds/60`,
  return `max(0, typingMinutes - spokenMinutes)`. Guard: `totalWords <= 0` → 0; NaN-safe like the
  existing guards. Add `StatsMathTests` cases (zero words, typical, spoken-slower-than-typed → 0).
- **Wiring:** `StatsStore` already exposes `TotalWords`/`TotalSeconds`. Add a
  `VoiceCoordinator.TimeSavedDisplay` computed string (e.g. `"12 min"`, or `"1.2 h"` when ≥ 60 min,
  `"—"` when 0). Recompute alongside `TotalWordsSpoken`/`AverageWpm` at ~L810.
- **UI:** add a third stat to the green stats card ("time saved").

### 1d. Dictate-to-translate (→ English)
- **Setting:** `bool TranslateToEnglish = false` (v3).
- **Engine:** add `bool translate` to `WhisperNetTranscriptionEngine` ctor (mirror `_language`);
  in `DecodeSamplesAsync` builder chain add `if (_translate) builder = builder.WithTranslate();`
  (confirmed present in Whisper.net 1.9.1). Source language stays the `Language` setting; output
  is English.
- **Swap:** changing `TranslateToEnglish` must rebuild the engine (same path `Language` change uses —
  find `MakeEngine`/`SwapEngine`, thread the flag through). Expose `VoiceCoordinator.TranslateToEnglish`
  bindable property that persists + swaps engine.
- **UI:** toggle in the Language card: "Translate speech to English". Tooltip: most useful with a
  non-English source language.

## Phase 2 — App-aware modes

### 2a. `ToneStyle.Code` (Core, TDD)
- Add `Code` to `enum ToneStyle` (Windows-only value; document with a comment).
- `TextProcessor.Format`: `ToneStyle.Code => trimmed` (minimal — preserve case & punctuation as
  spoken, only whitespace already normalized upstream; NO forced capitalization, NO terminal
  period, NO lowercasing). Ensure `Process` does not lowercase for Code (only VeryCasual lowercases).
- Tests: Code preserves "MyClass.doThing()" casing/symbols; does not add a period; filler removal
  still honored when the setting is on.

### 2b. Per-app rule model + resolver (Core, TDD)
- **Model:** `JVoice.Core/Models/AppModeRule.cs` — `record AppModeRule(string AppMatch, ToneStyle Mode)`.
  `AppMatch` = case-insensitive exe name or substring (e.g. `"code.exe"`, `"code"`, `"WindowsTerminal"`).
- **Resolver (pure):** `JVoice.Core/Policy/AppModeResolver.cs`:
  - Built-in code-app matches (const list): terminals (`WindowsTerminal`, `wt`, `cmd`, `powershell`,
    `pwsh`, `conhost`, `alacritty`, `wezterm`, `wezterm-gui`), editors/IDEs (`Code` = VS Code,
    `Cursor`, `devenv` = Visual Studio, `rider64`, `idea64`, `pycharm64`, `clion64`, `webstorm64`,
    `goland64`, `phpstorm64`, `sublime_text`, `notepad++`, `windsurf`). Match on exe name w/o `.exe`,
    case-insensitive.
  - `static ToneStyle? Resolve(string? exeName, IReadOnlyList<AppModeRule> userRules, bool enabled, ...)`:
    if `!enabled` or `exeName` null → `null` (caller falls back to global tone). Else: first matching
    **user rule** wins (substring, case-insensitive); else if exe ∈ built-in code apps → `Code`; else `null`.
  - Tests: user rule beats built-in; built-in code app → Code; unknown app → null; disabled → null;
    case-insensitivity; substring match.

### 2c. Foreground-exe helper (App, Platform/System)
- New `JVoice.App/Platform/System/ForegroundApp.cs`: `static string? ExeName(IntPtr hwnd)` →
  `GetWindowThreadProcessId` → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` →
  `QueryFullProcessImageName` → `Path.GetFileNameWithoutExtension`. Read-only; close handle;
  null on failure (anti-cheat-safe, same access class as `GameDetector`). Do NOT refactor
  `GameDetector` (preserve its locked invariants).

### 2d. Settings + wiring
- **Settings (v3):** `bool AppAwareModes = true`, `IReadOnlyList<AppModeRule> AppModeRules = []`
  (user rules; built-ins are implicit in the resolver, not persisted).
- **Apply:** in the finish path, before `TextProcessor.Process(..., _toneMode, ...)`, compute the
  effective tone: `var exe = ForegroundApp.ExeName(target); var eff = AppModeResolver.Resolve(exe,
  AppModeRules, _appAwareModes) ?? _toneMode;` and pass `eff` into `Process`. (`target` is the paste
  target HWND already resolved in the flow.)
- **Props:** `AppAwareModes` bindable toggle; `ObservableCollection<AppModeRule>` for the rules +
  `AddAppRule(app, mode)` / `RemoveAppRule(rule)` (mirror Corrections). Persist via `PersistSettings`.
- **Default ON assumption:** app-aware modes default ON so David's terminals/IDEs get Code mode with
  zero config. It's a behavior change (dictation formats differently in code apps) but that IS the
  feature and it's discoverable + toggleable in Settings. Documented for review.

### 2e. UI
- New "App modes" card (right column): master toggle + a rules editor (ItemsControl of
  app-name + mode dropdown + delete, and an add-row: TextBox + ComboBox(Casual/Formal/VeryCasual/Code)
  + Add). Note line: "Terminals, VS Code & IDEs use Code mode automatically."

## Verification
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` — all green (new StatsMath / TextProcessor /
  AppModeResolver tests included).
- `dotnet build windows/JVoice.sln -c Release` — 0 errors (build to a throwaway `-o` dir if the tray
  app is running and locks `JVoice.Core.dll`).
- `JVoice.exe --settings-render <png>` — the new toggles/cards render without clipping in the
  two-column layout.
- `JVoice.exe --bench <clip> --lang ro` sanity for translate once wired (offline where possible).

## Commit plan (one logical commit each)
1. Core: `StatsMath.EstimatedMinutesSaved` + tests.
2. Core: `ToneStyle.Code` + `TextProcessor` + tests.
3. Core: `AppModeRule` + `AppModeResolver` + tests.
4. Settings v3: model + JSON (all new fields) + tests.
5. App: clipboard-only + time-saved wiring + UI.
6. App: undo-last-paste (2nd hotkey + `Paster.SendUndo`) + UI.
7. App: translate (engine flag + swap) + UI.
8. App: app-aware modes (`ForegroundApp` + apply + rules editor UI).
9. Docs: HANDOFF-WINDOWS §7 #32/#33 + CLAUDE.md Windows-port bullet.

## Assumptions log (for David's review)
- "switch models" in the request = switch **modes** (tone), not Whisper models — per-app rules
  change tone only (avoids costly runtime model reloads). Model-override left as a future field.
- Clipboard-only is a **global** toggle.
- Undo-last-paste is **opt-in / no default hotkey** (global-swallow safety) and sends the app's Undo.
- App-aware modes default **ON** with implicit built-in Code-mode apps.
- Typing-speed baseline for "time saved" = **40 WPM**.
