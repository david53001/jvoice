# HANDOFF-WINDOWS — Windows port status

**Last updated:** 2026-06-23. **Branch:** `windows-port` (local only — never pushed).
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
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` → **402 / 402 passing** (grew from 122 during
  the bug-hunt, the no-speech fix, the Corrections feature, and the high-pass silence gate below).
- `windows/tools/whisper-smoke` and `JVoice.exe --bench` → **real on-device transcription works**
  (Vulkan GPU on the RTX 3060 Ti; CPU fallback verified too). Accuracy invariants proven.
- **The GUI launches** to the system tray with the "J" icon + first-run Settings window
  (confirmed running; two startup crashes were found & fixed — see §7).
- **The full dictation loop works:** hotkey → record (real mic) → transcribe (LargeTurbo on Vulkan) →
  paste into the focused app. Two paste bugs that made *every* transcription end in "Something Went
  Wrong" were found & fixed — see §7 #13. Verified by driving the real GUI with a synthetic hotkey.
- **Silence no longer pastes a hallucination** (David-reported, fixed 2026-06-23 — see §7 #15): saying
  nothing → faint room tone → whisper.cpp hallucinated a short phrase (`"you"`, `"(birds chirping)"`)
  that got pasted. The whole-file decode now gates on `ChunkPlanner.IsSilent` → silence shows
  **"No speech detected."** instead. Reproduced + fix verified on-device with Tiny.
- **Paste now lands where you clicked, including in a terminal** (David-reported, fixed 2026-06-23 — see
  §7 #16): the paste target was matched against a stale window handle snapshotted at launch (the terminal
  JVoice was started from), so dictating into that terminal mis-fired. Target is now resolved by **process
  ownership** of the live foreground (matching macOS `ownPID`), not a frozen HWND. Unit-verified
  (383/383); live terminal path is on the dogfood checklist.
- **User-editable "Corrections" list** (David-requested, 2026-06-23 — see §7 #17): a Windows-only Settings
  section of opt-in `heard phrase → replacement` rules for systematic recognizer mishearings (David's case:
  "web app" → "web api"). Applied in post-processing via `TextProcessor`'s existing `extraDictionary`
  (the brain is untouched / still 1:1 with Swift). Recommended as a *phrase* (`web api → web app`) so
  legitimate standalone "API" stays intact. Unit-verified (395/395); UI visuals on the dogfood checklist.
- **Black-&-white UI redesign + HUD voice bars** (David-requested, 2026-06-23 — see §7 #18): the HUD is now
  a **text-free, pure-black pill showing white voice-activity bars** that react to the live mic level
  (an indeterminate shimmer while transcribing/preparing/downloading); **errors are the only text**; a
  **successful paste is silent** (HUD just disappears — no "Pasted" pill). The whole app went **monochrome**
  (Settings, all "pills", tray glyphs — every blue/cyan/purple/teal/orange/pink/green accent → white/gray).
  The bars also **fix the HUD blur** David saw at his non-native 1600×1080 gaming resolution: solid shapes
  don't suffer the layered-window grayscale-AA softness the old small glowy text did, and the existing
  `DisplayMetrics.HudScale` still enlarges the pill by the resolution stretch ratio. Verified by screenshot
  via `--hud-preview` / `--settings-render`. A **follow-up the same day** slimmed the pill (height ~halved,
  baseline scale 1.1→1.0) per David's "too big/fat" feedback. **A later 2026-06-23 reshape** ("too thick and
  short → slim and tall", David chose "narrower + taller, keep horizontal bars"): the pill went from a wide
  thin strip (~132×28, 4.7:1) to a compact taller pill (~94×58, 1.6:1) — `HudView.xaml` PillBody MinWidth
  118→92 / MinHeight 28→58 / CornerRadius 13→20, inner padding `22,6`→`11,12`, `Bars.Height` 16→34; code-behind
  `BarCount` 11→9 and `MaxBarHeight` 16→34 (kept in sync with `Bars.Height`). New hidden flag **`--hud-render
  [path]`** renders the pill off-screen to a PNG (headless/CI, immune to a fullscreen game covering the
  overlay — the analog of `--settings-render`; `HudView.PrepareStaticCapture()` poses the bars). Build 0
  errors; `dotnet test` 412/412.
- **Quiet/short dictation no longer wrongly "No speech detected"** (David-reported 2026-06-23 — see §7 #19):
  real-mic room tone (mains hum) and quiet speech sit at the SAME raw RMS (~0.0044), so the raw-0.005 gate
  rejected quiet speech. New `HighPassSilence` gates on high-passed (broadband) energy instead — hum is
  crushed, speech survives. Validated end-to-end: a 0.0044-RMS quiet-speech clip the old gate rejected now
  transcribes, while same-level mains hum stays gated. The engine was always fine (short synthesized clips
  bench correctly); only the gate was over-aggressive.

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
    ├── generate-icon/             net9.0 console (SkiaSharp) — writes Assets/JVoice.ico + tray PNGs
    └── hotkey-probe/              net9.0 console — compiles the REAL GlobalHotkey source and drives
                                   it via SendInput/keybd_event (chord-match / watchdog re-arm / recovery
                                   modes); the diagnostic harness behind §7 #14
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
10. **HUD `ShowRing`/orbital-ring glyphs — SUPERSEDED by the 2026-06-23 redesign (#18).** The old HUD was
    a colored pill with a spinning ring + MDL2 center glyph + "Recording"/"Transcribing"/… text. That whole
    layout is gone; the HUD is now text-free white voice bars on a black pill (only the error state keeps a
    glyph + text, MDL2 warning E7BA). Kept here for history.
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
15. **Silence pasted a whisper hallucination instead of saying "nothing heard" (`Whisper/
    WhisperNetTranscriptionEngine.cs` + `VoiceCoordinator.cs`) — David reported "when I don't say
    anything it defaults to pasting."** Root cause: real-mic "silence" is faint room tone (mains hum +
    mic self-noise), NOT digital zero. The whole-file decode path ran whisper.cpp on it unconditionally,
    and whisper hallucinates a short phrase on near-silence (`"you"`, `"Thank you."`, paren/lowercase
    sound-tags like `"(birds chirping)"`). Those aren't in the brain's `RemoveWhisperHallucinations`
    blocklist (and `"you"` *can't* be — it's a real word) nor caught by `StripDecoderArtifacts`
    (uppercase-bracket only), so the hallucination survived post-processing as non-empty `processed`
    and got pasted. The streaming path was already silence-safe (it only decodes non-silent chunks and
    returns null on all-silence → whole-file fallback), so the gap was *only* the whole-file fallback.
    - **Reproduced on-device (Tiny via `whisper-smoke`):** 60/120 Hz mains-hum room tone at peak-window
      RMS **0.0035–0.0045 (below the 0.005 floor)** → `transcript: "(birds chirping)"` (exit 0, i.e. it
      would paste). Synthetic Gaussian white noise was a poor proxy (only hallucinated *above* the floor)
      — structured low-frequency hum is what reproduces the real-world case.
    - **Fix:** `TranscribeAsync` now reads the PCM once and, before decoding, gates on
      `ChunkPlanner.IsSilent(pcm, ChunkPlanner.Config())` — the **same** tuned `SilenceRmsFloor = 0.005`
      the streaming chunker already trusts to drop silent chunks (so no new threshold to tune, and it
      can't cut real speech: the verify-transcription harness proved that floor never drops speech).
      Silence → `throw EmptyTranscript()` (skips a wasted decode too). `VoiceCoordinator`'s
      `TranscriptionException` catch now maps `EmptyTranscript` → the existing **"No speech detected."**
      HUD (same copy + `HudResetDelay` as the post-processing empty-result path), not the generic error.
    - **Verified:** post-fix those hum clips → exit 1 (gated, "No speech detected." in-app); a real SAPI
      speech clip still transcribes verbatim; above-floor audio (RMS ~0.008) is unchanged. Premise locked
      by `ChunkPlannerTests.IsSilent_SubFloorRoomTone_IsTrue`. The Core "brain" was deliberately NOT
      touched (it's 1:1 with Swift) — the gate lives in the Windows engine layer and reuses a Core
      primitive. `dotnet test` → **381/381**; solution builds 0 errors.
    - **Known follow-up (out of scope, not a regression):** non-speech audio *above* the 0.005 floor
      (a loud fan, the 0.008 white-noise case) can still hallucinate a paren/lowercase sound-tag that
      slips past the brain. Catching that would need case-insensitive bracket/paren stripping in
      `StripDecoderArtifacts` — a Core/Swift-parity change, left for a deliberate brain edit.
16. **Dictation pasted into the wrong place / nowhere, "especially in a terminal" (`CoordinatorDecisions.cs`
    + `ForegroundWindowTracker.cs` + `VoiceCoordinator.cs`) — David reported "I click a box and speak and it
    sometimes isn't pasted there, like it doesn't recognise that I clicked there."** Root cause: the paste
    target was resolved by comparing the live foreground HWND against `_selfHwnd`, a **single window handle
    snapshotted once in `Start()`** via `GetForegroundWindowNow()`. JVoice is a tray app with **no window of
    its own at startup**, so that snapshot is just whatever app happened to be foreground when JVoice
    launched — during dev/dogfooding, **the terminal it was launched from**. So whenever the user later
    dictated *into that same terminal*, `current == _selfHwnd` made `ResolveTargetWindow` conclude "the
    foreground is myself," throw away the correct live target, and fall back to `lastNonSelf` (often stale,
    sometimes `Zero` → "No target app"). Intermittent because it only misfired for that one window; "terminal"
    because that's what launches the app. The macOS source decides this by **process identity**
    (`frontmost.processIdentifier != ownPID`, `VoiceCoordinator.swift:412-419`); the port had frozen it to one
    HWND, which also fails to guard our *own* HUD/Settings windows (a real JVoice window wouldn't equal the
    stale snapshot either).
    - **Fix:** `ResolveTargetWindow(current, bool currentForegroundIsSelf, lastNonSelf)` now takes a
      **boolean** the caller computes from process ownership — `ForegroundWindowTracker.IsOwnedByCurrentProcess`
      (`GetWindowThreadProcessId(hwnd).pid == Environment.ProcessId`), the same primitive the tracker's
      own self-filter already used. `_selfHwnd` and its `Start()` snapshot are deleted. Now the live foreground
      is the paste target whenever it's a *foreign* window (exactly when the user clicked into it), and we fall
      back to `lastNonSelf` only when the foreground is genuinely one of ours — robust regardless of how/where
      JVoice was launched, and it also closes the HUD/Settings-as-target hole.
    - **Verified:** new regression test `Resolve_SelfDecisionIsByOwnership_NotHandleIdentity` (same handle
      resolves differently by ownership, not identity); all `ResolveTargetWindow` tests migrated to the bool
      contract; `dotnet test` → **383/383**, solution builds 0 errors. Live "dictate into the launching
      terminal" path is in the dogfood checklist (still needs David's interactive mic confirmation).
17. **User-editable "Corrections" list (David-requested feature, 2026-06-23) — a Windows-only addition; no
    macOS counterpart.** David hit a systematic recognizer mishearing: dictating "web **app**" sometimes
    transcribes "web **api**". This is an inherent acoustic ambiguity ("app"/"API" reduce to the same
    `PhoneticMatcher` key `"ap"`), and the existing accuracy layers can't fix it: the custom-words path maps
    *spelling variants of the same word* to a canonical form, not one real word → a *different* real word; a
    blanket `api→app` rule would corrupt every legitimate "API" (which David does use). The fix is a
    user-controlled, opt-in list of `heard phrase → replacement` rules, applied in post-processing.
    - **The brain (`TextProcessor`) was NOT modified** (it stays 1:1 with Swift). The rules feed the
      *existing* `extraDictionary` parameter `TextProcessor.Process` already accepts. New glue:
      `Models/CorrectionRule.cs` (`record CorrectionRule(From, To)`) and `Text/UserCorrections.cs`
      (`Merge(spokenVariants, rules)` → folds rules into the spoken-variant dict, lower-cased/trimmed key,
      skips blank From/To, later rule wins; built-in `CorrectionDictionary` still overrides). `VoiceCoordinator`
      merges at transcribe time: `UserCorrections.Merge(BuildUserDictionary(vocab), Corrections)`.
    - **Phrase-capable on purpose:** `TextProcessor` matches multi-word keys (`\s+` between tokens), so the
      recommended rule for this case is the *phrase* `web api → web app` — it fixes "web app" while leaving
      standalone "API"/"REST API" untouched. The Settings UI hint says exactly this.
    - **Persistence:** new `SettingsState.Corrections` field + a 7th on-disk JSON key `corrections`
      (array of `{from,to}`). **Schema stays v1** (a bump would trip the forward-version guard and wipe all
      settings on downgrade); absent/malformed `corrections` falls back to empty per the existing
      per-field-fallback design. The `Serialize_EmitsExactlyThe…Keys` test was updated 6→7 keys.
    - **UI:** a new pink "Corrections" `DarkSection` in `SettingsView.xaml` (two input boxes `From → To`, a
      live list with per-row remove), mirroring the Custom Words section. Adding/removing a rule only
      persists — no engine/vocabulary reload (it's post-processing only). New brush `Settings.Pink`.
    - **Verified:** new `UserCorrectionsTests.cs` (merge semantics + end-to-end: `web api`→`web app` corrected,
      standalone "REST API" preserved) + `SettingsStoreJson` round-trip/fuzz/malformed-skip cover the new
      field; `dotnet test` → **395/395**, `dotnet build … -c Release` → 0 errors. The live mic path + the
      Settings UI visuals are on David's dogfood checklist.
18. **Black-&-white UI redesign + HUD voice bars (David-requested, 2026-06-23) — a Windows-only look; the
    macOS app and `DESIGN-TOKENS.md` are unchanged.** David asked for a minimal, text-free HUD ("just the
    swervy lines / bars that show voice activity"), no paste confirmation, a fully **black & white** theme,
    and the HUD to **not be blurry** at his non-native 1600×1080 gaming resolution.
    - **HUD = voice bars (`UI/HudView.xaml` + `.xaml.cs`, full rewrite).** A pure-black rounded pill holds a
      centred row of 11 white bars (built in code). They grow/shrink **symmetrically about centre via a
      per-bar `ScaleTransform`** (RenderTransform, not Height — no per-frame layout, pill never resizes),
      driven from the `CompositionTarget.Rendering` loop. **Recording** → bars track the smoothed live mic
      level (centre-weighted bell + an independent per-bar wobble so they "swerve"; a gentle breathing at
      silence). **Transcribing / preparing / downloading** → an indeterminate left-right shimmer (no live
      mic). **Error** → the only text state: white ⚠ (MDL2 E7BA) + the specific message. **Done/Idle** →
      hidden. The old orbital ring / center glyph / "Recording"/"Listening…" copy / stop button are all gone.
    - **Live mic level plumbing.** `IAudioRecorder.CurrentLevel` (0..1 peak) — new; `NAudioRecorder` computes
      it in `OnDataAvailable` (peak of the raw capture buffer; handles 32-bit float and 16-bit PCM; reset to 0
      on stop). `VoiceCoordinator.CurrentInputLevel` surfaces it; `App` wires `HudWindow.InputLevelProvider`
      → the HUD render loop polls it each frame (a `volatile float`, no lock — single-float read/write is atomic).
    - **Silent success + always click-through.** `VoiceCoordinator` success path now calls `UpdateHud(Idle)`
      instead of `HudState.Done(...)` (stats/last-transcript still recorded). `HudWindow` is **always**
      click-through now (the old non-click-through-while-recording exception only existed for the stop button).
      `HudState.Done` is untouched in Core (tests still pass); the coordinator just no longer sends it.
    - **Monochrome everywhere (`UI/Styles/JVoicePalette.xaml`, `SettingsView.xaml`, tray icons).** Every
      former accent (blue/indigo/purple/teal/cyan/orange/green/pink/red) → white; backgrounds → pure black,
      cards `#0E0E0E`, borders `#262626`, headers gray `#9A9A9A`. The teal switch → `MonoSwitch` (white-on,
      black knob). Segmented "checked" highlight → white@0.16. Destructive buttons → white (the confirm
      dialog, not colour, guards them). Tray recording/transcribing glyphs regenerated **white** (was red/cyan)
      via `tools/generate-icon` — all three tray states now match the white "J".
    - **Blur fix (honours the memory: David runs 1600×1080 on purpose for gaming — fix IN-APP, never tell him
      to change resolution).** The redesign *is* the fix: the old softness was WPF's grayscale-AA (no ClearType)
      on small glowy **text** inside the layered HUD window; solid white **bars** don't have that problem.
      `DisplayMetrics.HudScale` (pre-existing) still enlarges the whole pill by `native/current` so it keeps
      its device-pixel budget under the monitor's hardware downscale. DPI awareness was already `PerMonitorV2`
      (`app.manifest`), so WPF itself isn't bitmap-stretching anything.
    - **New dev aids (hidden flags, like `--hud-preview`):** `--hud-preview recording|transcribing|preparing|
      downloading|error` (recording gets a synthetic 0.32 level so the bars aren't idle); `--settings-preview`
      (live Settings window, topmost); `--settings-render <path>` (renders Settings to a PNG **off-screen** —
      immune to a fullscreen game covering the desktop, CI-friendly); `--hud-render <path>` (the HUD analog of
      `--settings-render` — renders the pill off-screen to a PNG with the bars posed in a static frame). All
      bypass the single-instance lock.
    - **Gotcha for the next session:** building `JVoice.App.csproj` **alone** outputs to
      `bin\Release\net9.0-windows\`, but the **solution** build outputs to `bin\x64\Release\net9.0-windows\`
      (the sln sets `Platform=x64`). Run/screenshot the exe from the path matching how you built, or you'll
      launch a stale binary. Also: a running `JVoice.exe` locks the output DLL — `Stop-Process -Name JVoice`
      before rebuilding.
    - **Verified:** `--hud-preview` screenshots of recording (lively centre-weighted bars), transcribing
      (sweep), error (white text); `--settings-render` PNG (all-monochrome panel). `dotnet build` 0 errors;
      `dotnet test` **395/395**. Live-mic bar reactivity + the on-desktop look are on David's dogfood checklist.
19. **High-pass no-speech gate — quiet/short dictation stopped being rejected as "No speech detected"
    (David-reported 2026-06-23, follow-up to #15).** After the redesign surfaced the *real* error text,
    David saw "No speech detected." on short test utterances. Investigation (his `%APPDATA%\JVoice\
    diagnostic.log` + local `--bench` repro) proved it was **not** the UI change and **not** the engine:
    short synthesized speech clips (down to 1.27 s "Open") all transcribe correctly, and his own long
    paragraphs worked. The failures were all recordings whose **peak RMS was below the 0.005 silence floor**
    — i.e. the raw-RMS no-speech gate (#15) rejecting them. The catch: on real hardware, **mains-hum room
    tone and quiet speech sit at the SAME raw RMS (~0.0044 measured)**, so no raw-RMS floor can separate
    them (lowering it re-enables the #15 hallucination; keeping it rejects quiet speech).
    - **Fix: `JVoice.Core/Audio/HighPassSilence.cs`** — gate on the **high-passed** (first-difference, ~0 at
      DC, +6 dB/oct) peak 0.3 s-window RMS instead of raw RMS. Low-frequency hum is crushed to a few percent;
      broadband speech survives. Validated on synthesized clips at equal raw level: room-tone hpRMS ≈ 0.0007,
      quiet-speech hpRMS ≈ 0.0023, digital silence ≈ 0.0002, normal speech ≈ 0.02–0.08 → a floor of **0.0012**
      gates hum/silence and passes quiet speech, far below normal speech (no regression).
    - **Wiring:** `WhisperNetTranscriptionEngine.TranscribeAsync` now gates on `HighPassSilence.IsSilent(pcm)`
      (replacing `ChunkPlanner.IsSilent` + the now-removed `SilenceConfig`). The streaming chunker still uses
      `ChunkPlanner.IsSilent` (raw 0.005) for *which sub-chunk to drop* in long recordings — a uniformly-quiet
      long recording just falls back to the whole-file high-pass gate, so it's covered; only a *mixed* loud/
      quiet long recording could still drop a quiet passage (pre-existing, rare — noted, not fixed).
    - **Verified end-to-end (`--bench --model large`):** the 0.0044-RMS quiet-speech clip the old gate rejected
      now transcribes ("Hello world, this is a quick test."); same-level mains hum → `silence-gated hpRms=0.0007
      floor=0.0012 rawRms=0.0045`; digital silence → gated; normal speech → transcribes. `HighPassSilenceTests`
      (+7) lock the hum-vs-speech separation; `dotnet test` **402/402**, build 0 errors. A TEMP diagnostic
      attaches `hpRms/rawRms` to the gated exception (logged by the coordinator) so the floor can be re-tuned
      to David's mic from a real session if needed.
20. **High-pass gate, second pass — spectral-ratio gate so David's *real* quiet/short dictation passes
    (David-reported 2026-06-23, follow-up to #19; this is the THIRD no-speech-gate iteration).** After #19
    shipped, David still hit "No speech detected." on short dictations. This time the TEMP diagnostic paid
    off — his `%APPDATA%\JVoice\diagnostic.log` showed the *actual* gated values from his mic, and they were
    far lower than #19's **synthesized-clip** tuning assumed:

    | recSecs | rawRMS | hpRMS | hp/raw ratio | #19 gate (hp<0.0012) | outcome |
    |--------:|-------:|------:|-------------:|:--------------------:|---------|
    | 2.38 | 0.0014 | 0.0006 | **0.43** | gated | real speech, wrongly rejected |
    | 1.51 | 0.0017 | 0.0009 | **0.53** | gated | real speech, wrongly rejected |
    | 0.89 | 0.0027 | 0.0003 | 0.11 | gated | low-freq tap, correctly rejected |
    | 0.45 | 0.0017 | 0.0002 | 0.12 | gated | low-freq tap, correctly rejected |

    His longer dictations (5–63 s) all transcribed perfectly. The single absolute hpRMS floor from #19
    couldn't be lowered enough to pass his quiet speech without also passing pure hum/silence: the
    synthesized "quiet speech hpRMS ≈ 0.0023" anchor simply does **not** hold on his hardware/voice — a
    first-difference high-pass crushes a low-pitched male voice's low-frequency fundamental, so even his real
    speech reads at digital-silence absolute level. **The separator that *does* survive is spectral, not
    absolute: speech stays broadband (high hp/raw ratio ≈ 0.4–0.5) even when quiet; hum/rumble does not
    (ratio ≈ 0.02–0.12).** Confirmed why the gate can't just be removed: a `--bench` repro showed whisper.cpp
    (large-v3-turbo) hallucinating **`"you're welcome."`** on a low-energy tone — it sailed through the fixed
    text blocklist and would have been pasted, so the gate is genuinely protective.
    - **Fix: `JVoice.Core/Audio/HighPassSilence.cs`** — dual-criterion gate. `hpRMS ≥ SpeechFloor (0.0012)`
      ⇒ pass unconditionally (**exactly the old pass set — zero regression to working dictation**);
      `hpRMS < HardFloor (0.0002)` ⇒ silent (digital silence / pure hum); in the ambiguous zone between,
      decide by the high-passed/raw **ratio** vs `SpeechRatioFloor (0.20)`. New `IsSilent(float hp, float raw)`
      overload encodes the policy so it's unit-tested against David's exact logged numbers. **Monotonic by
      construction:** the gate now reports silent for a strict *subset* of what #19 did, so it can only
      *reduce* false rejections, never add one.
    - **Wiring:** `WhisperNetTranscriptionEngine.TranscribeAsync` computes `hp`/`raw` once, calls the new
      overload, and the TEMP diagnostic now also logs `ratio` + all three thresholds. Removed the engine's
      duplicate `PeakWindowRms` (now on `HighPassSilence`).
    - **Verified:** `dotnet test` **412/412** (the +10 new `HighPassSilenceTests` lock the policy to David's
      real-mic anchors). `--bench --model large` end-to-end: digital silence / 60 Hz hum / a *loud* 150 Hz
      rumble (raw 0.012, ratio 0.06) → all still gated; a **quiet broadband clip (hpRMS 0.0011, ratio 0.54)
      that the #19 gate rejected now passes** to whisper. Build 0 errors.
    - **⚠ RESIDUAL — needs David's dogfood:** his failing recordings sit at rawRMS 0.0014–0.0027 (≈ −55 dBFS,
      *below* his own room tone), i.e. **20–30 dB below even quiet speech**. The two with broadband character
      (2.38 s / 1.51 s) now pass and should transcribe; but the two very-short taps (0.45 s / 0.89 s,
      ratio 0.11–0.12) are still gated — correctly *if* they were accidental, but if he genuinely spoke a
      quick word whose consonants were attenuated below the noise floor, the gate can't recover it. That
      points to a deeper **capture-level** cause (most likely Windows shared-mode WASAPI **audio enhancements
      / AGC ramp** attenuating short/early audio — long recordings survive because the loud middle clears the
      gate). That can't be verified without his live mic, so it's **not** attempted here. The enriched
      diagnostic (`ratio=…`) will reveal it: if his next short-dictation failures log a *high* ratio they're
      real speech captured too quietly (chase the capture path / raw-capture mode); a *low* ratio means no
      speech was captured. The TEMP diagnostic + `DiagnosticLog` call sites **stay** until this is confirmed
      on his mic.
    - **Note:** I stopped his running `JVoice.exe` (PID-locked the output DLL) to rebuild — **he must relaunch
      the rebuilt app to get the fix** (`dotnet run --project windows/JVoice.App`, or the refreshed
      `bin\Release\net9.0-windows\JVoice.exe` / `bin\x64\Release\…`; both were rebuilt). Also observed in the
      bench: the runtime selected **Vulkan**, not CUDA, on his RTX 3060 Ti — unrelated to this bug, flagged
      for later.

### Persistence paths (overview §4.9)
`%APPDATA%\JVoice\settings.json` (+ `settings.corrupt.bak`), `stats.json`, `last-transcript.txt`;
registry `HKCU\Software\JVoice` (`LaunchAtLoginInitialized`, `UiFirstRunShown`) + `HKCU\…\Run\JVoice`;
temp recordings `%TEMP%\jvoice-<guid>.wav` (swept on launch); models `%LOCALAPPDATA%\JVoice\models\`.

---

## 8. What remains

1. **Dogfood the GUI (David, interactive):** run `docs/launch/windows-dogfood-checklist.md` — the live
   Ctrl+Shift+Space → record → transcribe → paste loop, the new black-&-white HUD bars reacting to your
   voice (and the silent-success / error-only-text behaviour), the 320×520 monochrome Settings round-trip,
   BT device routing, mic-permission flow, elevated-window UIPI. The app is confirmed to *launch* and the
   HUD/Settings look is screenshot-verified via `--hud-preview`/`--settings-render`; live-mic reactivity is
   what a person at the desk must confirm.
2. **(Optional) Phase 5 Task 6** — port `scripts/verify-transcription.py` to
   `windows/tools/verify-transcription` (corpus-level word-retention / spurious-vocab scoring across
   many generated clips). `whisper-smoke` + `--bench` already prove end-to-end transcription; this is the
   larger scripted accuracy harness.
3. **(Optional) Phase 5 Task 3** — an Inno Setup installer (`windows/installer/JVoice.iss`). The zipped
   self-contained folder is already a complete distributable, so this is convenience only (and needs
   Inno Setup installed to compile).
4. **Polish from dogfooding:** tune the bar count/heights/level gain to taste once seen with a real mic
   (constants live at the top of `HudView.xaml.cs`); optionally style the Settings scrollbar (still the
   default WPF grey). (The old "waveform glyph" / "per-section accent" polish items are obsolete — #18.)
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
