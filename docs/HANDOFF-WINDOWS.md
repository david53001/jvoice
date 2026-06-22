# HANDOFF-WINDOWS — Windows port status

**Last updated:** 2026-06-22. **Branch:** `windows-port` (local only — never pushed).
**Audience:** David + the next zero-context Claude session.

This is the single source of truth for the **state** of the JVoice Windows port. Read
`CLAUDE.md` (the "Windows port" section) for the hard rules. The macOS Swift app under
`Sources/` is the **read-only reference** for the accuracy "brain" and its invariants — never
modify `Sources/`, `Tests/`, `Package.swift`, or `Resources/`.

---

## 1. TL;DR — where the port stands

JVoice is a hotkey-driven voice-dictation app: press a hotkey → record mic → on-device Whisper
transcription → tone-styled, custom-word-accurate text pasted into the focused app. This is a
**native Windows port** (the macOS app is Swift/WhisperKit/AppKit; this is C#/.NET 9/WPF/Whisper.net).

**All five phases are implemented.** Current verified state:

- `dotnet build windows/JVoice.sln -c Release` → **0 errors** (5 projects).
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` → **122 / 122 passing**.
- `windows/tools/whisper-smoke` and `JVoice.exe --bench` → **real on-device transcription works**
  (Vulkan GPU on the RTX 3060 Ti; CPU fallback verified too). Accuracy invariants proven.
- **The GUI launches** to the system tray with the "J" icon + first-run Settings window
  (confirmed running; two startup crashes were found & fixed — see §7).
- **The full dictation loop works:** hotkey → record (real mic) → transcribe (LargeTurbo on Vulkan) →
  paste into the focused app. Two paste bugs that made *every* transcription end in "Something Went
  Wrong" were found & fixed — see §7 #13. Verified by driving the real GUI with a synthetic hotkey.

**What still needs a human (David's interactive dogfood):** real-mic-with-actual-speech accuracy and
the *visual* fidelity of the HUD/Settings can only be judged by a person at the desktop. Walk
`docs/launch/windows-dogfood-checklist.md`. Everything an autonomous/headless session can verify, is verified.

**Optional remaining work** (does NOT block a working app): an Inno Setup installer and a
corpus-level accuracy harness — see §8.

---

## 2. How to build / run / test / dogfood / publish (zero-context)

Prereqs: .NET 9 SDK (dev box has 9.0.304), Windows 10/11 x64. From the repo root:

```bash
# Build everything (Release):
dotnet build windows/JVoice.sln -c Release            # expect: Build succeeded, 0 errors

# Run the unit suite (the brain + pure helpers):
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj  # expect: Passed! 122/122

# Run the actual app (tray + first-run Settings window):
dotnet run --project windows/JVoice.App
#   - First run only: the dark 320x520 Settings window opens + a one-time info dialog.
#   - Tray "J" icon → right-click for: Start/Stop Dictation, Settings…, Launch at Login, Quit.
#   - Press Ctrl+Shift+Space to dictate (first dictation downloads the Tiny model ~74 MB once).
#   - Quit via the tray menu (the app has no main window; it lives in the tray).
#   - To replay the first-run experience: delete HKCU\Software\JVoice\UiFirstRunShown.

# Transcribe a WAV with NO GUI (fastest engine check):
dotnet run --project windows/tools/whisper-smoke -- <file.wav> --model tiny

# Hidden bench CLI (also on the app exe; bypasses the UI entirely):
#   JVoice.exe --bench <file.wav> [--model tiny|base|small|large] [--lang en|ro]
#              [--vocab "A,B"] [--stream] [--no-prompt]
#   exit codes: 64 usage, 66 no-file, 65 not-a-wav, 70 engine-unavailable, 1 failed, 0 ok.

# Regenerate the app icon + tray PNGs (only if the squircle-J art changes):
dotnet run --project windows/tools/generate-icon
```

A bench/smoke WAV must be **16 kHz / mono / 16-bit PCM**. Generate one with Windows TTS:
```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SetOutputToWaveFile("$env:TEMP\jv.wav",$fmt); $s.Speak('Testing JVoice on Windows.'); $s.Dispose()
```

**Publish a distributable** (ship a zipped self-contained folder, NOT a single-file exe — see §7):
```bash
# CPU-only "lite" folder (small; runs on CPU):
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=cpu \
  -p:PublishSingleFile=false -p:SelfContained=true -p:PublishTrimmed=false \
  -p:PublishReadyToRun=true -o out/cpu
# GPU folder (bundles CUDA+Vulkan+CPU native runtimes):
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=gpu \
  -p:SelfContained=true -p:PublishTrimmed=false -p:PublishReadyToRun=true -o out/gpu
# then: Copy-Item LICENSE out/<flavor>/LICENSE.txt ; Compress-Archive out/<flavor>/* JVoice-<flavor>-win-x64.zip
```

---

## 3. Repository layout

The macOS app stays in place (reference). The Windows app is the `windows/` .NET solution.

```
windows/
├── JVoice.sln
├── Directory.Build.props          LangVersion latest, Nullable+ImplicitUsings enable, Version 1.0.0
├── JVoice.Core/                   net9.0 — PURE brain + pure decision helpers (no UI/native deps)
│   ├── Models/                    ToneStyle, TranscriptionLanguage, WhisperModelOption, SettingsState,
│   │                              HudState, HotkeyChord, SettingsStateJson
│   ├── Text/                      TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard,
│   │                              RegurgitationRecovery
│   ├── Audio/                     WavTail(+WavTailReader), ChunkPlanner, StreamingTranscriptionSession,
│   │                              BluetoothDevicePolicy
│   ├── Transcription/             ITranscriptionEngine, TranscriptionException, FileBackedTranscriptionEngine
│   ├── AppTimings.cs  StatsMath.cs  CoordinatorDecisions.cs
├── JVoice.App/                    net9.0-windows, WinExe, UseWPF — the app
│   ├── App.xaml(.cs)              [STAThread] Main (bench short-circuit → single-instance →
│   │                              WhisperRuntime.EnsureLoaded → Run); OnStartup wires it all
│   ├── app.manifest               asInvoker, PerMonitorV2 DPI, longPathAware, UTF-8, Win10/11 supportedOS
│   ├── VoiceCoordinator.cs        the orchestrator (port of VoiceCoordinator.swift)
│   ├── Whisper/                   WhisperRuntime, WhisperModelStore, WhisperNetTranscriptionEngine, BenchRunner
│   ├── Platform/                  PlatformPaths, SettingsStore, StatsStore, LastTranscriptStore, SystemActions,
│   │                              LaunchAtLogin, SingleInstance, SettingsUris, PermissionError,
│   │                              AudioInputRouter, IAudioRecorder, NAudioRecorder, ForegroundWindowTracker,
│   │                              GlobalHotkey, Paster
│   ├── UI/                        App-level: HudWindow + HudView, SettingsWindow + SettingsView, DarkSection,
│   │   │                          HotkeyRecorder, TrayIcon, Converters, Styles/JVoicePalette.xaml
│   └── Assets/                    JVoice.ico + tray-idle/recording/transcribing.png (generated, committed)
├── JVoice.Tests/                  net9.0 xUnit — 122 tests locking JVoice.Core
└── tools/
    ├── whisper-smoke/             net9.0 console — WPF-free end-to-end transcription harness
    └── generate-icon/             net9.0 console (SkiaSharp) — writes Assets/JVoice.ico + tray PNGs
```

**Why the split:** `JVoice.Core` is pure `net9.0` (no UI/native deps) so `JVoice.Tests` (also
`net9.0`) can lock every accuracy/decision invariant on CI without Windows audio/GPU/clipboard.
Anything OS-bound lives in `JVoice.App` and is verified by build + the dogfood checklist. Pure
testable value types that conceptually belong to the platform/UI (HotkeyChord, SettingsStateJson,
BluetoothDevicePolicy, StatsMath, CoordinatorDecisions) live in Core so the tests can reach them
(overview §10).

---

## 4. Locked decisions

- **Stack: C# / .NET 9 / WPF** (`win-x64`, WinExe). Speech via **Whisper.net** (managed whisper.cpp
  bindings, **GGML** models) with GPU accel (CUDA→Vulkan→CPU auto-select) + CPU fallback. NAudio
  (capture), H.NotifyIcon.Wpf (tray), SkiaSharp (icon tool). Rejected alternatives (Swift-on-Windows
  / WinUI3 / Tauri / Electron) in overview §2.4. **This was an autonomous choice and is now fully
  executed** — revisiting it means re-doing the UI/platform shells (the Core brain + engine choice
  are ~80% reusable regardless).
- **The brain ports 1:1**, every constant verbatim, locked by xUnit. The two WhisperKit-1.0.0
  workarounds (SuppressBlankFilter prompt trap; single-window timestamp truncation) are **dropped** —
  whisper.cpp doesn't have those bugs (empirically reconfirmed, §6).
- **GGML model map:** Tiny→`ggml-tiny.bin`, Base→`ggml-base.bin`, Small→`ggml-small.bin`,
  Large→`ggml-large-v3-turbo-q5_0.bin` (~547 MB). Downloaded on first use to `%LOCALAPPDATA%\JVoice\models\`.
- **Default hotkey Ctrl+Shift+Space** (Alt+Space is the Windows window menu). Rebindable in Settings;
  the rebind is **session-only** (SettingsState has no hotkey field yet — resets to default on relaunch).
- **Tray-first UI** + a real focusable Settings window + first-run shows Settings once + the floating
  HUD pill overlay. `AudioInputRouter` does NOT change the system default device — it picks a non-BT
  capture endpoint only when the default is Bluetooth (keeps the user's headset music in A2DP).
- **$0 / unsigned:** no code-signing → unsigned download; document SmartScreen "More info → Run anyway"
  (`docs/launch/windows-distribution.md`). Privacy: zero runtime network except the one-time model
  download. GPL-3.0; all NuGet deps MIT.
- **NO publishing / pushing / PRs / remotes** without David's explicit go-ahead (same as macOS side).

## 5. Pinned NuGet versions

| Package | Version | Where | Notes |
| --- | --- | --- | --- |
| `Whisper.net` | 1.9.1 | JVoice.App, whisper-smoke | engine |
| `Whisper.net.Runtime` (CPU) | 1.9.1 | JVoice.App, whisper-smoke | always |
| `Whisper.net.Runtime.Cuda` | 1.9.1 | JVoice.App (cond.), whisper-smoke | **conditional** in App (omitted for `cpu` publish flavor) |
| `Whisper.net.Runtime.Vulkan` | 1.9.1 | JVoice.App (cond.), whisper-smoke | conditional in App |
| `NAudio` | 2.3.0 | JVoice.App | capture |
| `H.NotifyIcon.Wpf` | **2.3.0** | JVoice.App | tray. **NOT 2.4.1** (2.4.1 ships only net10.0/net462 → broke on net9) |
| `SkiaSharp` | 3.119.4 | tools/generate-icon | icon rendering only |

xUnit + runner + Microsoft.NET.Test.Sdk in JVoice.Tests. `JVoice.Core` has **zero** package refs.

---

## 6. What was verified (evidence)

### Engine / transcription (Phase 2) — real on-device runs on the dev machine
- **Runtime selected = Vulkan** (the bundled CUDA runtime needs the CUDA toolkit DLLs, which aren't
  installed; Vulkan is the GPU path on the 3060 Ti; CPU is the fallback). The CPU-only publish flavor
  correctly reports `whisper.cpp (Cpu)`.
- **Model download/locate:** `ggml-tiny.bin` (77,691,713 bytes, SHA `be07e048…c6e1b21`, matches the
  published whisper.cpp hash) downloads to `%LOCALAPPDATA%\JVoice\models\`, verified by size+SHA, and
  is reused with no re-download; no `.part` leftovers.
- **Prompted decode is non-empty** (proves SuppressBlankFilter is unneeded): `--vocab "VS Code,JVoice"`
  → raw `"I am editing Code in VS Code with J Voice Today."` → processed `"…with JVoice Today"`.
  `--no-prompt` is also non-empty; the prompt biased "VS Code" (capital C) vs "VS code" — biasing works.
- **>30s clip not truncated** (proves the single-window timestamp trap is unneeded): a ~125s clip
  returned all 12 numbered sentences in 3.73s.
- **Streaming** (`--stream`): a short clip falls back to whole-file losslessly (correct — under the 15s
  min chunk); a long clip streams with all content present (no data loss); whole-file corroborates.
- **`--bench` exit codes** 64/66/0 verified.

### GGML model manifest (in `WhisperModelStore`)
| Model | File | ExpectedBytes | SHA-256 |
| --- | --- | --- | --- |
| Tiny | ggml-tiny.bin | 77,691,713 | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| Base | ggml-base.bin | 147,951,465 | null (size-only) |
| Small | ggml-small.bin | 487,601,967 | null (size-only) |
| Large | ggml-large-v3-turbo-q5_0.bin | 574,041,195 | null (size-only) |
`CompleteModelPath` checks existence+size (cheap); full SHA verified once after download before the
atomic `.part`→final rename.

### Platform services (Phase 3) — verified via throwaway consoles on the dev machine
- **SettingsStore**: fresh-write, reload, corruption→backup+reset, forward-version refusal.
- **StatsStore / LastTranscriptStore**: record/guard/reload, UTF-8 round-trip.
- **SingleInstance**: real cross-process — a child process got "blocked" while the parent held the mutex.
- **LaunchAtLogin**: enable/disable/first-run-idempotent registry round-trip, then **reverted** (clean).
- **NAudioRecorder**: orphan sweep, usable-check, mic-permission probe true, and a **growing WAV
  readable by `WavTailReader` at ~16000 samples/sec, final header 16000/1/2** — the critical Phase 1↔3
  streaming contract.
- **AudioInputRouter / Paster / ForegroundWindowTracker / PermissionError**: non-BT pick = null on a
  normal default mic; Paste no-target → TargetRejected; Stage clipboard round-trip; foreground HWND non-zero.

### Engine/UI build + tests (Phase 4/5)
- Full Release build 0 errors; **122 xUnit tests** (73 brain + 36 platform helpers + 13 coordinator helpers).
- `JVoice.exe --bench` exits 64 (bench branch still short-circuits before WPF through the new App.Main).
- generate-icon produced a valid 6-frame `.ico` + 3 tray PNGs.
- **The app launches to the tray and stays alive** (confirmed running; see §7 for the two fixes that got it there).

### Whisper.net 1.9.1 API facts (so a future session doesn't re-derive them)
- `WhisperFactory.FromPath(string)` ✓, `.CreateBuilder()` ✓; builder has `WithLanguage`, `WithPrompt`
  (NOT `WithPromptText`), `WithTemperature`, `WithTemperatureInc`, `WithEntropyThreshold`,
  `WithLogProbThreshold` (NOT `WithProbabilityThreshold`).
- **No `WithoutTimestamps()`** in 1.9.1 — the engine just concatenates `SegmentData.Text`; whisper.cpp
  windows internally so long audio isn't truncated. **`WithoutSuppressBlank()` exists** → suppress_blank
  is ON by default (we never call it).
- `WhisperProcessor.ProcessAsync(float[], CancellationToken)` — CT is required (not defaulted).
- Runtime selection read via `Whisper.net.LibraryLoader.RuntimeOptions.LoadedLibrary` (typed
  `RuntimeLibrary?`, null until first factory load).

---

## 7. Deviations & gotchas a new session MUST know

These are real corrections discovered during execution — preserve them.

1. **WindowsDesktop SDK trims implicit usings.** `net9.0-windows` + `UseWPF` omits `System.IO` and
   `System.Net.Http` from implicit usings (to avoid `Path` ambiguity with `System.Windows.Shapes.Path`).
   Every `JVoice.App` file using files/HTTP needs an explicit `using System.IO;` / `using System.Net.Http;`.
   `JVoice.Core` (plain net9.0) keeps the full implicit set.
2. **Two GUI startup crashes (found by actually launching; now fixed in `UI/TrayIcon.cs`):**
   - `TaskbarIcon.ForceCreate()` defaults `enablesEfficiencyMode=true`, which calls
     `SetProcessInformation` (process QoS) and throws `COMException 0x80070001` on this Windows build →
     **fixed with `ForceCreate(enablesEfficiencyMode: false)`**.
   - The tray used a **PNG `IconSource`**, but H.NotifyIcon feeds it to `new System.Drawing.Icon(stream)`,
     which only accepts `.ico` bytes → `ArgumentException` → **fixed by converting the PNGs to
     `System.Drawing.Icon` via `Bitmap.GetHicon()` and setting the `Icon` property** instead.
3. **`NAudioRecorder` `BufferedWaveProvider.ReadFully = false`** (root-cause fix, not in the plan): the
   default `true` makes `Read()` zero-pad forever, turning the flush pump into an infinite busy loop
   (caught when two processes pinned the CPU at >130s). `false` makes it return only buffered bytes.
4. **Single-file publish doesn't work for the engine.** A CPU single-file builds (~75 MB) but **fails
   native load (exit 70)** — Whisper.net 1.9.1 resolves natives via `Assembly.Location`, which is empty
   for bundled single-file assemblies. **Ship a self-contained FOLDER zip** (the CPU folder build is
   verified working). WPF also can't be trimmed (`PublishTrimmed=false` is pinned).
5. **CUDA/Vulkan runtime packages are CONDITIONAL** in `JVoice.App.csproj` (`Condition="$(JVoiceFlavor) != 'cpu'"`)
   — `ExcludeAssets` was insufficient (the runtime `.targets` copy natives regardless, ballooning the
   build to 418 MB). The `cpu` flavor omits them entirely.
6. **`H.NotifyIcon.Wpf` pinned at 2.3.0** (2.4.1 ships only net10.0/net462 → falls back to net462 on
   net9, which breaks WPF). 2.3.0 has a `net9.0-windows7.0` asset.
7. **`App.xaml` is build-action `Page`, not `ApplicationDefinition`** — otherwise the SDK auto-generates
   a `Main` that collides with our explicit bench-aware `[STAThread] Main` (CS0017).
8. **`DarkSection` is a templated `ContentControl`, not a `UserControl`** — a UserControl creates its own
   namescope, making `x:Name`d children inside a section illegal (MC3093). The ContentControl keeps
   section content in the declaring file's namescope. Its visual is the implicit `DarkSection` style in
   JVoicePalette.xaml; HeaderText is coerced to upper-case so the `TemplateBinding` shows it uppercased.
9. **Icon tool uses SkiaSharp 3.x `SKFont`+`DrawText`+`MeasureText`** (the plan assumed the 2.x
   `SKPaint.GetTextPath`; SKPaint lost its text members in 3.x).
10. **HUD `ShowRing` simplified** to `ShowRing(string glyph)`; Transcribing uses the MDL2 Volume glyph
    (E767) — there's no clean waveform glyph (a drawn-Path waveform is a noted polish item). HUD center
    glyphs are MDL2 code points E720/E713/E896/E767/E73E/E7BA (byte-verified).
11. **Temperature fallback** (`temperatureFallbackCount=2`) maps to `WithTemperature(0)+WithTemperatureInc(0.2)`
    (≈ the macOS behavior; Whisper.net has no exact fallback-count knob).
12. Benign **CS4014** warnings on intentional fire-and-forget `_ = …PrewarmAsync()/…Cancel()`
    (`TreatWarningsAsErrors` is false).
13. **Paste was broken end-to-end (two bugs, both fixed in `Platform/Paster.cs`) — found during the
    first real dictation dogfood, where every transcription ended in the HUD's "Something Went Wrong"
    (the title shown for *any* `HudState.Error`; the detail was `Unable to paste into the active app`).
    Transcription itself was always fine — the failure was purely the paste step returning
    `PasteOutcome.TargetRejected`:**
    - **`SendInput` always failed with `ERROR_INVALID_PARAMETER` (87), sent 0/4 events.** The `INPUT`
      P/Invoke struct's union declared only `KEYBDINPUT`, making `sizeof(INPUT)` = 32; on x64 SendInput's
      `cbSize` check requires **40**. Fixed by giving `InputUnion` its largest member (`MOUSEINPUT`, plus
      `HARDWAREINPUT`) so the struct is 40 bytes. This path had **never** been exercised successfully —
      Phase 3 only verified no-target rejection + clipboard staging, never a real paste.
    - **`FocusTarget` was fragile:** it attached input to the *target* thread (should be the *current
      foreground* thread), trusted `SetForegroundWindow`'s unreliable return value, and treated any
      non-`true` as a fatal abort — even when the target was already foreground (the common case!). Fixed
      to early-return success when the target is already foreground, attach to the current-foreground
      thread, zero the foreground-lock timeout (`SPI_SETFOREGROUNDLOCKTIMEOUT`), and verify success by
      reading `GetForegroundWindow()` instead of the API return code.
    - Verified by driving the real GUI (synthetic Ctrl+Shift+Space) end-to-end: pre-fix → `TargetRejected`;
      post-fix → `PasteOutcome.Ok` with `SendInput` injecting 4/4 events (and correct `AccessDenied` when
      the foreground target is an elevated window like Task Manager). `dotnet test` still 122/122.
14. **Global hotkey hardened against silent loss (`Platform/GlobalHotkey.cs`) — David reported "the
    keybind isn't working even though I'm pressing the right keys."** Systematic investigation (a new
    `windows/tools/hotkey-probe` that compiles the *real* `GlobalHotkey` source and drives it via
    `SendInput`/`keybd_event`, plus env-gated tracing to `%TEMP%\jvoice-hotkey.log`) established:
    - The chord-matching logic is **correct** — it fires for both generic (`0x11/0x10`) and the
      left-specific (`0xA2/0xA0`) modifier vk codes a *physical* keyboard actually emits (the hook reads
      modifiers via `GetAsyncKeyState(VK_CONTROL/VK_SHIFT)`, which report down for either L/R). A fresh
      launch records on the first injected chord, and the hook keeps firing through a full LargeTurbo GPU
      transcription. So neither the matching nor the down-stream `ToggleRecording` path is broken.
    - **Root failure mode: a `WH_KEYBOARD_LL` hook can stop delivering events.** `HKCU\Control Panel\
      Desktop\LowLevelHooksTimeout` is **1000 ms** on this machine; if the hook callback (or its thread)
      ever exceeds that — e.g. the hook thread is starved while the GPU/CPU is pegged by transcription —
      Windows drops the event (and on some configs silently *removes* the hook entirely, leaving the
      hotkey dead for the rest of the session with no notification or re-arm).
    - **Fix (defense-in-depth, all verified with the probe):** (a) the hook thread runs at
      `ThreadPriority.Highest` so the trivial callback is scheduled promptly and returns within the
      timeout even under load (prevention); (b) a **self-healing watchdog** — a thread `WM_TIMER` every
      1 s compares `GetLastInputInfo()` (system-wide last-input tick) against the hook's last-callback
      tick; if the system saw input >3 s newer than our hook did, the hook is presumed lost and is
      **re-installed** (new hook installed *before* the old is removed, so there's no gap; the 150 ms
      debounce absorbs any overlap). Probe confirmed: re-arm fires and the chord still triggers afterward.
    - **Diagnostics kept in-tree (zero cost when off):** `JVOICE_HOTKEY_LOG=1` traces hook install +
      every main-key match decision + watchdog re-arms to `%TEMP%\jvoice-hotkey.log`. If the hotkey ever
      misbehaves again, relaunch with that env set and the trace pins it (hook received the key? matched?
      modifier mismatch? re-armed?). Test seams `JVOICE_HOTKEY_TEST_STALL_MS` / `JVOICE_HOTKEY_NO_WATCHDOG`
      drive the probe's `recovery`/`watchdog` modes. NOTE: the *exact* trigger David hit was not
      deterministically reproducible (this machine *skips*, not removes, on a >1 s stall), so this is
      hardening of the proven failure modes + a recovery path + a trace for next time, not a one-line bug.
      `dotnet test` still **122/122**; full solution builds 0 errors.

### Persistence paths (overview §4.9)
`%APPDATA%\JVoice\settings.json` (+ `settings.corrupt.bak`), `stats.json`, `last-transcript.txt`;
registry `HKCU\Software\JVoice` (`LaunchAtLoginInitialized`, `UiFirstRunShown`) + `HKCU\…\Run\JVoice`;
temp recordings `%TEMP%\jvoice-<guid>.wav` (swept on launch); models `%LOCALAPPDATA%\JVoice\models\`.

---

## 8. What remains

1. **Dogfood the GUI (David, interactive):** run `docs/launch/windows-dogfood-checklist.md` — the live
   Ctrl+Shift+Space → record → transcribe → paste loop, HUD pill states/animation vs DESIGN-TOKENS, the
   320×520 Settings round-trip, BT device routing, mic-permission flow, elevated-window UIPI. The app is
   confirmed to *launch*; the live input/visual paths are what a person must confirm.
2. **(Optional) Phase 5 Task 6** — port `scripts/verify-transcription.py` to
   `windows/tools/verify-transcription` (corpus-level word-retention / spurious-vocab scoring across
   many generated clips). `whisper-smoke` + `--bench` already prove end-to-end transcription; this is the
   larger scripted accuracy harness.
3. **(Optional) Phase 5 Task 3** — an Inno Setup installer (`windows/installer/JVoice.iss`). The zipped
   self-contained folder is already a complete distributable, so this is convenience only (and needs
   Inno Setup installed to compile).
4. **Polish from dogfooding:** HUD pixel fidelity, the waveform glyph, per-section selected-segment accent.
5. **Do NOT publish/push** without David's explicit go-ahead.

---

## 9. The phase plans (reference)

`docs/superpowers/plans/2026-06-22-windows-port-0{0..5}-*.md` — the original zero-context, task-by-task
plans that were executed. Read **00 (overview)** first (architecture, canonical names §4, constraints
§5, gotchas §6, cross-phase reconciliation §10 — §10 wins over §4 on conflicts). These are historical
plan docs; **this HANDOFF reflects the as-built state** (which deviates from the plans where §7 above says so).

## 10. Other docs

- `windows/README.md` — developer guide (layout, build/test/run, engine/models, publish).
- `docs/launch/windows-distribution.md` — unsigned distribution + the SmartScreen "Run anyway" flow.
- `docs/launch/windows-dogfood-checklist.md` — the interactive verification checklist (David runs this).
- `CLAUDE.md` "Windows port" section — the hard rules + a one-line status.
