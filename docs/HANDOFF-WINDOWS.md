# HANDOFF-WINDOWS — Windows port status

**Last updated:** 2026-06-26. **Branch:** `windows-port` (published to `origin/windows-port`).
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
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` → **713 / 713 passing** (grew from 122 during
  the bug-hunt and the subsequent feature work tracked in §7; a shared, moving total).
- `windows/tools/whisper-smoke` and `JVoice.exe --bench` → **real on-device transcription works**
  (Vulkan GPU on the RTX 3060 Ti; CPU fallback verified too). Accuracy invariants proven.
- **The GUI launches** to the system tray with the "J" icon + first-run Settings window
  (confirmed running; two startup crashes were found & fixed — see §7).
- **The full dictation loop works:** hotkey → record (real mic) → transcribe (LargeTurbo on Vulkan) →
  paste into the focused app. Two paste bugs that made *every* transcription end in "Something Went
  Wrong" were found & fixed — see §7 #13. Verified by driving the real GUI with a synthetic hotkey.
- **Paste now lands where you clicked, including in a terminal** (David-reported, fixed 2026-06-23 — see
  §7 #16): the paste target was matched against a stale window handle snapshotted at launch (the terminal
  JVoice was started from), so dictating into that terminal mis-fired. Target is now resolved by **process
  ownership** of the live foreground (matching macOS `ownPID`), not a frozen HWND. Unit-verified;
  live terminal path is on the dogfood checklist.
- **User-editable "Corrections" list** (David-requested, 2026-06-23 — see §7 #17): a Windows-only Settings
  section of opt-in `heard phrase → replacement` rules for systematic recognizer mishearings (David's case:
  "web app" → "web api"). Applied in post-processing via `TextProcessor`'s existing `extraDictionary`
  (the brain is untouched / still 1:1 with Swift). Recommended as a *phrase* (`web api → web app`) so
  legitimate standalone "API" stays intact. Unit-verified; UI visuals on the dogfood checklist.
- **Black-&-white UI redesign + HUD voice bars** (David-requested, 2026-06-23 — see §7 #18): the HUD is now
  a **text-free, pure-black pill showing white voice-activity bars** — a **continuous, mic-independent wave**
  while recording (David preferred a constant flow over mic-reactive bars; see §7 #23), an indeterminate
  shimmer while transcribing/preparing/downloading; **errors are the only text**; a
  **successful paste is silent** (HUD just disappears — no "Pasted" pill). The whole app went **monochrome**
  (Settings, all "pills", tray glyphs — every blue/cyan/purple/teal/orange/pink/green accent → white/gray).
  The bars also **fix the HUD blur** David saw at his non-native 1600×1080 gaming resolution: solid shapes
  don't suffer the layered-window grayscale-AA softness the old small glowy text did, and the existing
  `DisplayMetrics.HudScale` still enlarges the pill by the resolution stretch ratio. **The pill went through
  seven same-day shape iterations** (David tuning by eye — see §7 #18 for the full numeric arc); the **final
  as-built look** (commit `f59bc0d`) is a **152 × 38 px black pill (CornerRadius 19)** holding **21 white round-capped lines**
  (3 px wide, 3 px gap, 3 px resting "dot" → 32 px tall). The pivotal fix mid-arc was switching the
  bars from a `ScaleTransform` (which squashed the rounded caps into cubic corners at low levels) to a
  **direct `Height` animation** with a fixed `BarWidth/2` corner radius, so every bar is a true vertical
  capsule at any height. Verified by screenshot via `--hud-preview` / `--hud-render` / `--settings-render`.
  Build 0 errors; `dotnet test` **434/434**.
- **Quiet/short dictation transcribes, and sentence tails are no longer cut off** (David-reported
  2026-06-23 — see §7 #21, which RETIRES the #15/#19/#20 gates). His real speech and room hum overlap in
  BOTH level and spectral ratio, so no signal-level gate could separate them — every prior gate (tuned on
  synthetic clips) rejected his real quiet/short sentences. **The no-speech decision now belongs to the
  MODEL:** the whole-file engine decodes first, then `NonSpeechAnnotation.Reduce` maps whisper's no-speech
  output (`[BLANK_AUDIO]`/`[Music]`/`(birds chirping)`) to empty ⇒ "No speech detected.", while real quiet
  speech (verified on-device down to rawRMS ≈ 0.001) transcribes. **Bug #2 ("cuts off the last part"):**
  the streaming session dropped his quiet *trailing clause* (it read as "silent" at his low level); it now
  falls back to the lossless whole-file path instead of dropping the tail. Verified end-to-end (real engine):
  silence/hum/noise → "No speech detected."; quiet speech at his levels → exact transcript. `dotnet test` 434/434.
- **The "first recording freeze" is root-caused and FIXED** (2026-07-02 — see §7 #37). It was never
  elevation: `NAudioRecorder.Stop()` disposed the WASAPI capture (whose `Dispose` joins the capture
  thread) while holding the gate that the capture callback needs — a lock-order inversion that froze
  the UI thread on an unlucky stop press. Teardown now detaches under the gate and disposes outside it;
  deterministic regression via `JVOICE_TEST_SLOW_CAPTURE_MS` + the headless
  `windows/tools/capture-stop-probe`. Elevated dictation verified working (the old §8 warning is retired).
- **Silence no longer pastes a hallucinated sentence** (David-reported 2026-06-24; CLOSED 2026-07-02 —
  see §7 #38). Calibrated on 17 of David's real capture clips: whisper's confidence is INVERTED
  (hallucinations score highest), and the working discriminator is **prompt-vs-no-prompt agreement**.
  `Core/Policy/SilenceHallucinationGate` + a witness decode in the engine: a near-silent clip
  (rawRMS < 0.004, trigger only) that still produced prompted text is re-decoded without the prompt —
  an empty reduced witness ⇒ "No speech detected.", else the prompted transcript is kept. 10/10 silent
  presses gated, 7/7 quiet real sentences kept (the #21 balance held).

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
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj  # expect: Passed! 434/434

# Run the actual app (tray + first-run Settings window):
dotnet run --project windows/JVoice.App
#   - First run only: the dark 640x846 two-column Settings window opens + a one-time info dialog.
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
│   │                              HudState, HotkeyChord, SettingsStateJson, CorrectionRule,
│   │                              TranscriptHistory(+Entry) (Win-only Recent Transcripts, §7 #26)
│   ├── Text/                      TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard,
│   │                              RegurgitationRecovery, NonSpeechAnnotation (Win-only no-speech detector)
│   ├── Audio/                     WavTail(+WavTailReader), ChunkPlanner, StreamingTranscriptionSession,
│   │                              BluetoothDevicePolicy, HighPassSilence (Win-only; now metrics-only, §7 #21)
│   ├── Transcription/             ITranscriptionEngine, TranscriptionException, FileBackedTranscriptionEngine
│   │   └── Policy/                    CoordinatorDecisions, HotkeyGate, GameDetectionPolicy, StatsMath, AppTimings
│                                  (moved from Core root → Policy/ in the 2026-06-26 reorg; namespace JVoice.Core unchanged)
├── JVoice.App/                    net9.0-windows, WinExe, UseWPF — the app
│   ├── App.xaml(.cs)              [STAThread] Main (bench short-circuit → single-instance →
│   │                              WhisperRuntime.EnsureLoaded → Run); OnStartup wires it all
│   ├── app.manifest               asInvoker, PerMonitorV2 DPI, longPathAware, UTF-8, Win10/11 supportedOS
│   ├── VoiceCoordinator.cs        the orchestrator (port of VoiceCoordinator.swift)
│   ├── Whisper/                   WhisperRuntime, WhisperModelStore, WhisperNetTranscriptionEngine, BenchRunner
│   ├── Platform/                  OS integration, split 2026-06-26 into @-mentionable sub-areas
│   │   │                          (namespace JVoice.App.Platform unchanged — folder ≠ namespace is intentional):
│   │   ├── Capture/               IAudioRecorder, NAudioRecorder, AudioInputRouter
│   │   ├── Persistence/           PlatformPaths, SettingsStore, StatsStore, LastTranscriptStore,
│   │   │                          TranscriptHistoryStore (§7 #26)
│   │   └── System/                GlobalHotkey, Paster, Elevation, ElevatedAutostart, LaunchAtLogin,
│   │                              GameDetector, GameProbeRunner, ForegroundWindowTracker, DisplayMetrics,
│   │                              SingleInstance, SystemActions, SettingsUris, PermissionError, DiagnosticLog
│   ├── UI/                        App-level: HudWindow + HudView, SettingsWindow + SettingsView, DarkSection,
│   │   │                          HotkeyRecorder, TrayIcon, TranscriptRow (§7 #26), Converters,
│   │   │                          Styles/JVoicePalette.xaml
│   └── Assets/                    JVoice.ico + tray-idle/recording/transcribing.png (generated, committed)
├── JVoice.Tests/                  net9.0 xUnit — 523 tests locking JVoice.Core
└── tools/
    ├── whisper-smoke/             net9.0 console — WPF-free end-to-end transcription harness
    ├── generate-icon/             net9.0 console (SkiaSharp) — writes Assets/JVoice.ico + tray PNGs
    ├── nospeech-probe/            net9.0-windows console — runs silence/hum/noise/quiet-speech clips
    │                              through the real engine to lock the no-speech behaviour (§7 #21);
    │                              self-generates a SAPI clip, `--muffle` matches David's low-ratio mic
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
- **Default hotkey Ctrl+Shift+Space** (Alt+Space is the Windows window menu). Rebindable in Settings
  and **persisted** across relaunch via the `hotkey` field in `settings.json` (a Windows-only, structural
  `{modifiers,virtualKey,keyName}` object — macOS persists its shortcut separately via the
  KeyboardShortcuts library). Absent/malformed → Ctrl+Shift+Space; Restore Defaults re-registers it.
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
- Full Release build 0 errors; **434 xUnit tests** (Phase 4/5 was 122 = 73 brain + 36 platform helpers +
  13 coordinator helpers; the rest came from the bug-hunt, Corrections, and the no-speech/tail work in §7).
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
- **No-speech (§7 #21):** `SegmentData` exposes `Text`, `Probability` / `MinProbability` / `MaxProbability`
  (avg token logprobs), `Tokens`, `Start`/`End` — but **NOT** a per-segment `no_speech_prob` (Whisper.net
  1.9.1 doesn't surface it; not in the DLL). `WithNoSpeechThreshold(float)` exists but is `[EXPERIMENTAL]`
  and had **no observable effect** on-device — so the no-speech decision is made from whisper's TEXT output
  (it emits a strippable annotation like `[BLANK_AUDIO]`/`(birds chirping)` on silence), not a probability.
- **`Probability`/`MinProbability`/`MaxProbability` read `0` unless `.WithProbabilities()` is set on the
  builder** (verified 2026-06-24, §7 #24 — cost a debug cycle: they silently return 0, not null). The method
  is `WhisperProcessorBuilder.WithProbabilities()` (also `WithSuppressRegex`, `WithMaxSegmentLength`,
  `WithSingleSegment` exist). **Even when populated, segment confidence does NOT cleanly separate a
  silence-hallucination from quiet speech** — a confident prompt-induced hallucination out-scores real quiet
  speech (§7 #24), so a naive confidence gate is backwards.

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
15. **[SUPERSEDED by #21 — the RMS no-speech gate this added was later RETIRED; kept for history.]
    Silence pasted a whisper hallucination instead of saying "nothing heard" (`Whisper/
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
    macOS app and `DESIGN-TOKENS.md` are unchanged.** **[Partly SUPERSEDED by #23 — the recording bars are
    now a continuous, mic-independent wave (not mic-reactive) and the final pill geometry changed; #23 is the
    as-built record, #18 below is the redesign rationale + the shape-iteration history.]** David asked for a minimal, text-free HUD ("just the
    swervy lines / bars that show voice activity"), no paste confirmation, a fully **black & white** theme,
    and the HUD to **not be blurry** at his non-native 1600×1080 gaming resolution.
    - **HUD = voice bars (`UI/HudView.xaml` + `.xaml.cs`, full rewrite).** A pure-black rounded pill holds a
      centred row of white bars (built in code), driven from the `CompositionTarget.Rendering` loop. *(As
      first shipped this was 11 bars animated by a per-bar `ScaleTransform`; the count/sizing and the
      animation method were refined the same day — see the "Shape refinement → final as-built" bullet below.
      Final: 19 round-capped bars driven by a direct `Height` animation.)* **Recording** → bars track the smoothed live mic
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
    - **Shape refinement → final as-built (six same-day iterations, David tuning by eye).** The pill aspect
      ratio, bar count and cap shape were tuned across `1af6627` → `8ebf441` → `2ef1587` → `bb6721e` →
      `77c93ff` → `510e108`. The arc (PillBody `MinWidth × MinHeight` / CornerRadius · `BarCount` / `BarWidth`
      / `MaxBarHeight`):
      `1af6627` 120×50 r18 · 11/4/26 (initial; ScaleTransform) → `8ebf441` slimmer 118×28 r13 · 11/4/16
      (baseScale 1.1→1.0) → `2ef1587` "slim & tall" 92×58 r20 · 9/4/34 → `bb6721e` "wide + many slim lines"
      180×70 r30 · 21/3/44 → **`77c93ff` the pivotal fix: dropped `ScaleTransform` for a direct `Height`
      animation** with a fixed `BarWidth/2` corner radius (ScaleTransform had squashed the rounded caps into
      cubic corners at low levels) → 114×46 r22 · 15/3/26, `MinBarHeight == BarWidth` so a resting bar is a
      perfect round dot → `510e108` final settle **140×46 r22 · 19/3/40**. Live-level shaping (recording):
      `LevelGate` 0.004, `LevelGain` 20× (a **visual** meter boost for David's quiet mic — see #22), attack
      0.55, decay 0.18, per-bar smoothing 0.5, centre-weighted bell + per-bar wobble; idle breathing so bars
      are never fully still. Constants live at the top of `HudView.xaml.cs`.
    - **Gotcha — which binary actually runs (this bit David 2026-06-23).** Two output paths coexist:
      `bin\Release\net9.0-windows\` and `bin\x64\Release\net9.0-windows\` (depending on whether the build
      resolved `Platform=x64` or AnyCPU). It is easy to *run a stale exe from one path while you rebuilt the
      other.* After any code change: **fully quit the app and relaunch**, and confirm which exe is live with
      `(Get-Process JVoice).Path`. A running `JVoice.exe` also **locks its loaded DLL**, so a rebuild of that
      same path fails with a file-in-use error — quit first (`Stop-Process -Name JVoice`) or build the other
      path. To verify a built DLL contains a given change without launching it, search its bytes: type names
      are UTF-8, string literals are UTF-16LE in the `#US` heap (e.g. `model empty/annotation` for §7 #21).
    - **Verified:** `--hud-preview` screenshots of recording (lively centre-weighted bars), transcribing
      (sweep), error (white text); `--settings-render` PNG (all-monochrome panel). `dotnet build` 0 errors;
      `dotnet test` **395/395**. Live-mic bar reactivity + the on-desktop look are on David's dogfood checklist.
19. **[SUPERSEDED by #21 — this gate was RETIRED; kept for history.]
    High-pass no-speech gate — quiet/short dictation stopped being rejected as "No speech detected"
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
21. **No-speech gate RETIRED → model decides; + sentence tails no longer cut off (David-reported
    2026-06-23, the FOURTH and final no-speech iteration; supersedes #15/#19/#20).** David still hit BOTH
    "No speech detected." on short sentences AND "cuts off the last part of my sentences." His fresh
    `diagnostic.log` settled it: a **real 3.32 s sentence** logged `silence-gated hpRms=0.0004 rawRms=0.0041
    ratio=0.10` and a **1.78 s sentence** `ratio=0.08` — both gated by #20 (ratio < 0.20). #20's "speech
    ratio ≈ 0.4–0.5" anchor was from **synthesized SAPI clips**; his real low-pitched voice + room hum sit
    at ratio 0.08–0.12, *overlapping* hum. **No absolute level/ratio threshold can separate his speech from
    his room tone** — every gate iteration (#15 raw, #19 hp, #20 ratio) was tuned on synthetic clips that
    don't reproduce his real low-level, low-SNR mic. Meanwhile his 19 s/31 s clips transcribed *verbatim*,
    proving the decoder was never the problem — only the gate.
    - **On-device experiment (`windows/tools/nospeech-probe`, kept in the solution as a re-runnable harness):**
      ran silence / 60 Hz hum / low-freq rumble / white noise / SAPI speech scaled peak 0.10→0.008 through
      Whisper.net 1.9.1 (tiny), ±vocab prompt. **(a)** whisper decodes quiet speech correctly at EVERY level —
      even peak 0.008 (rawRMS ≈ 0.001, *below* David's). **(b)** On genuine no-speech whisper emits a NON-SPEECH
      ANNOTATION (`[BLANK_AUDIO]`, `[Music]`, `[Sigh]`, `(birds chirping)`) — never a plausible sentence. So
      "did the user speak?" is answered by whisper's OUTPUT, not the signal level. `WithNoSpeechThreshold`
      (`[EXPERIMENTAL]`) had no effect; not used. (This also revealed #15 was a **misdiagnosis** — whisper's
      silence output was always a strippable annotation; the RMS gate was never needed.)
    - **Fix — bug #1 (`WhisperNetTranscriptionEngine.TranscribeAsync`):** **removed the `HighPassSilence.IsSilent`
      rejection.** Decode first; then **new `JVoice.Core/Text/NonSpeechAnnotation.Reduce`** maps a
      whole-transcript annotation (`[...]`/`(...)`, any case, no real words outside the groups) to `""` ⇒ the
      existing `EmptyTranscript` ⇒ "No speech detected." Level-independent. `HighPassSilence` is now
      metrics-only (its `PeakHighPassRms`/`PeakWindowRms` still feed the diagnostic log; `IsSilent` is no
      longer wired — class doc updated, tests kept).
    - **Fix — bug #2 (`JVoice.Core/Audio/StreamingTranscriptionSession.Finish()`):** the streaming
      `ChunkPlanner.IsSilent` (absolute 0.005 floor) dropped David's quiet **trailing clause** (his last words
      read as "silent" at his level), so earlier chunks pasted but the tail was lost. The final tail judged
      silent now **returns null → lossless whole-file fallback** (which re-decodes everything with the gate
      gone) instead of being dropped. Normal-level users (loud tail) are unaffected; the never-silently-drop
      invariant is preserved. `NonSpeechAnnotation.Reduce` is also applied to chunk decodes. **WINDOWS
      DIVERGENCE from Swift** (mac mic is normal-level, so its silent-tail drop never misfires).
    - **Verified:** `dotnet test` **434/434** (new `NonSpeechAnnotationTests`; `StreamingSessionTests` updated:
      `SilentTail_ForcesWholeFileFallback_NotDropped` + `SubFloorQuietTail_ForcesWholeFileFallback` — both
      RED before the fix). End-to-end via `whisper-smoke` (REAL engine, tiny): silence/hum/rumble/white-noise →
      "No speech detected."; **quiet speech at peak 0.05/0.02/0.008 and 0.05+hum → exact transcript** ("Please
      figure out this issue and fix the last part of my sentence."). Build 0 errors. Full design +
      evidence: `docs/superpowers/plans/2026-06-23-windows-nospeech-and-tail-fix.md`.
    - **Note:** the old TEMP `hpRms/rawRms` diagnostic on the no-speech exception is **kept** (now reads
      `no-speech (model empty/annotation) hpRms=… rawRms=… ratio=…`) so David's mic spectrum is still logged.
      Residual (minor, unchanged): a stray mixed-case `[Music]` *mid*-sentence isn't stripped (whole-transcript
      only); and the WASAPI/​resampler stop drops ≤ ~one buffer period (~10–30 ms, sub-syllable) — neither is
      David's reported bug.
22. **HUD meter gain for David's low mic (VISUAL only) + the standing "don't gain the transcription audio"
    guard (2026-06-23).** **[The meter-gain half is SUPERSEDED by #23 — the recording bars no longer use the
    mic level at all (the live wave is generated, not metered); the GUARD below still stands, unchanged.]**
    David's mic peaks ≈0.05 on normal speech (≈0.02 very quiet) where a typical mic
    peaks ≈0.2–0.5, so the HUD voice-bars barely moved (~16%) on his voice. `HudView.xaml.cs` `LevelGain`
    `3.6→20` and `LevelGate` `0.006→0.004` — a **purely visual** boost so the bars actually react to his quiet
    mic. **This touches ONLY the HUD meter (`IAudioRecorder.CurrentLevel` → bars); it does NOT change the
    audio sent to whisper.**
    - **GUARD — do NOT add digital makeup gain to the *transcription* audio to "fix accuracy."** It is
      tempting (his levels are low), but it's theater: whisper.cpp normalizes log-mel energy and decodes his
      quiet audio correctly (engine verified down to rawRMS ≈ 0.001, #21), and no gate drops quiet speech
      anymore. Linear gain scales his room noise **equally** (no SNR gain) and risks clipping. He's already on
      the most accurate model (**LargeTurbo**); the only real accuracy levers left are **mic SNR** (quieter
      room / consistent close mic / raising the Windows capture level / mic-boost at the OS-analog stage) and
      **diction** — nothing in-app. See memory `win-mic-low-capture-level`.

23. **HUD recording bars → a continuous synthetic wave (NOT mic-reactive); final pill geometry
    (2026-06-23, commits `c8f4a8d` → `526e395` → `f59bc0d`; supersedes the mic-reactive / meter-gain parts of
    #18 and #22).** The mic-reactive bars (#18/#22) **stuttered on David's words** — he wanted a steady
    up-and-down flow — so the live-mic drive in `HudView.xaml.cs` was retired.
    - **`526e395` removed the live-level path entirely** (`LevelGate`/`LevelGain`/attack-decay/`_smoothLevel`
      and the per-frame `InputLevelProvider.Invoke()`), replacing it with a purely generative `LiveBar` wave:
      each bar = two summed sines at different rates with a per-bar phase gradient (so the motion *travels*
      across the row) + an independent per-bar speed + a centre-weighted bell — "tall, always moving, never
      flat" — driven from `CompositionTarget.Rendering`. **The mic-level wiring is kept but DEAD**
      (`InputLevelProvider`, `HudWindow.InputLevelProvider`, `VoiceCoordinator.CurrentInputLevel`,
      `IAudioRecorder.CurrentLevel` all still compile so a mic-reactive mode can be re-enabled without
      re-threading the callback — `InputLevelProvider`'s XML doc now literally says "Currently UNUSED").
      `c8f4a8d` was an interim step (slammed the meter to `LevelGain=38`, `LevelGate=0.003`) before `526e395`
      dropped mic-reactivity altogether.
    - **⇒ The "bars react to the live mic" / "meter gain (`LevelGain` 20×)" language in #18 and #22 is now
      FALSE.** #22's **guard still stands** (do NOT add digital makeup gain to the *transcription* audio —
      that is unchanged and still correct); only its *visual meter-gain* half is moot.
    - **Final pill geometry (`f59bc0d`, "squeeze shorter & a touch longer"; verbatim from `HudView.xaml`/`.cs`):**
      PillBody `MinWidth 152 × MinHeight 38`, `CornerRadius 19`, black `#FF000000`, 1 px hairline border
      `#FFFFFFFF @0.10`, black drop shadow. Bars: `BarCount 21`, `BarWidth 3`, `BarGap 3`, `MaxBarHeight 32`
      (== `Bars.Height`), `MinBarHeight 3` (== `BarWidth` → a resting bar is a round dot), fully round caps
      (`RadiusX/Y = BarWidth/2 = 1.5`; **Height** is animated directly, never a `ScaleTransform`).
      `DisplayMetrics.HudBaseScale` was trimmed **1.1 → 1.0** (the pill read "too big" at 1.1×); `HudScale`
      still multiplies by the native/current stretch ratio (clamp 1.8) so the pill stays crisp below native
      resolution. **Transcribing / preparing / downloading** = an `IndeterminateBar` Gaussian "bump"
      ping-ponging across the row (a text-free shimmer). **Error** = the only text state. **Idle/Done** =
      window hidden (silent success).
    - **Visual-only — no brain/engine/test change.** `dotnet test` stays **434/434**, build 0 errors. The
      stale in-source comments in `HudView.xaml`/`.cs` (the "rise and fall with the live microphone level"
      header + two "1.1 at native" notes) were corrected to match this as-built state in the 2026-06-24 doc pass.

24. **Silence sometimes pastes a PLAUSIBLE hallucinated sentence — David-reported 2026-06-24 (IN PROGRESS;
    the *inverse* of #21).** #21 fixed the false-NEGATIVE (real quiet speech wrongly rejected as "no speech").
    This is the false-POSITIVE: on a near-silent short press, whisper.cpp emits a confident, real-looking
    sentence that gets pasted. **Evidence (`%APPDATA%\JVoice\diagnostic.log`, his own session):** `recSecs=0.65
    → "you can't see it, but you can't see it."`, `recSecs=1.30 → "you're welcome."`, `recSecs=0.99 → "you
    can't see it, but you can't see it."` (his bug-report dictation literally quotes one).
    - **Root cause — #21(b) was only HALF true.** #21 claimed "on no-speech whisper never emits a plausible
      sentence, only an annotation." That held for the **synthetic** probe clips (digital silence / 60 Hz hum /
      white noise → `[BLANK_AUDIO]`). But on David's **real** short near-silence (faint mic self-noise / a
      breath / a click) whisper hallucinates a real sentence — **worst with the vocab prompt ON** (which he
      runs). A plausible sentence has letters, so `NonSpeechAnnotation.IsAnnotationOnly` returns false and it
      sails through. `TextProcessor.RemoveWhisperHallucinations` is an EXACT-MATCH blocklist that (a) lacks
      these phrases and (b) is a **1:1 frozen port of the macOS brain** (`Sources/.../TextProcessor.swift:157`,
      parity-test-locked) — so it **must not** be extended with Windows-only phrases. The fix has to live in
      the **Windows-only** layer.
    - **Why not a blocklist / a confidence gate (both rejected):** a blocklist would also eat "you're welcome."
      / "thank you" when David *actually says them*. And a confidence gate is **backwards** — smoke test (large-
      turbo, `.WithProbabilities()`, synthetic): the prompt-induced silence hallucination read `avgConf 0.92 /
      minConf 0.38`, **higher** than real (SAPI) speech `0.88 / 0.025`. Whisper is *confidently* wrong on
      silence. Candidate discriminators that DID separate on the smoke test: **prompt-vs-no-prompt agreement**
      (real speech decoded identically ±prompt; silence decoded to totally different text each way) and **gzip
      compression ratio** (1.16 vs 0.70; a looped hallucination compresses far better). Must be re-confirmed on
      David's REAL clips — synthetic silence has no mic self-noise and SAPI ≠ his voice.
    - **Harness built this session (fix NOT yet shipped — awaiting calibration clips):**
      • `JVoice.App/Platform/PlatformPaths.cs` — `CaptureDirectory` (`%APPDATA%\JVoice\capture`) + `KeepRecordings`
        (env var **`JVOICE_KEEP_WAV`**).
      • `JVoice.App/VoiceCoordinator.cs` — `TryDelete` routes to new `TryKeepForCalibration` when `KeepRecordings`:
        copies each real recording into the capture dir **before** deleting the temp WAV (privacy preserved;
        best-effort — never disrupts the dictation flow). Off by default; zero cost when the env var is unset.
      • `windows/tools/nospeech-probe/Program.cs` — new **`--analyze [wav…]`** mode: reads `settings.json` so it
        mirrors the LIVE app's model+vocab (**LargeTurbo** + his customWords), decodes each clip **±prompt** with
        `.WithProbabilities()`, and prints `secs rawRMS hpRMS segs avgConf minConf compR` + the current engine
        result + text. With no paths it scans the capture dir. (`WithProbabilities()` is REQUIRED or the conf
        columns are 0 — see §6.)
    - **Next steps (zero-context):** (1) David records ~5 silent presses + ~5 quiet sentences with the capture
      build running (launched with `JVOICE_KEEP_WAV=1`). (2) `dotnet run --project
      windows/tools/nospeech-probe/nospeech-probe.csproj -c Release -- --analyze` (no args → reads
      `%APPDATA%\JVoice\capture`). (3) Pick the discriminator that cleanly splits the silent rows from the
      speech rows. (4) Implement a **Windows-only** gate in `WhisperNetTranscriptionEngine` (reduce a
      hallucination to `""` ⇒ the existing `EmptyTranscript` ⇒ "No speech detected."), with xUnit tests,
      **balanced against #21** (must NOT reject his real quiet speech). (5) Delete the capture clips; relaunch
      WITHOUT the env var. Build = 0 errors; capture harness verified working (probabilities populate,
      large-turbo loads). `dotnet test` still **434/434** (no brain change yet).

25. **Hotkey is DEAD while an elevated (admin) window has focus — David-reported 2026-06-24; FIXED by an
    opt-in "run JVoice elevated" path.** When David focused an **admin terminal** and pressed Ctrl+Shift+Space,
    **nothing happened** — no HUD, no recording. Confirmed by his own test: same press worked in a non-elevated
    Notepad.
    - **Root cause — UIPI (the SAME rule as the paste-side `PasteOutcome.AccessDenied`, but one step UPSTREAM).**
      `GlobalHotkey` uses a low-level keyboard hook (`WH_KEYBOARD_LL`). By Windows UIPI design, a hook installed
      by a **non-elevated** (medium-integrity) process is **not called** for keystrokes destined for a window
      owned by a **higher-integrity (elevated) foreground** process. JVoice ships `asInvoker` (overview §6.4), so
      while an admin window has focus the chord is never even seen → the whole trigger is inert. (overview §6.4 had
      documented only the *paste* half — "can't paste into an elevated app"; the trigger half is more fundamental.)
    - **Why the fix is "run JVoice itself elevated".** For an UNSIGNED app that's the only option: the
      `uiAccess="true"` UIPI bypass (what AutoHotkey/screen readers use) requires an Authenticode signing cert
      **and** install into `Program Files` — both ruled out by the $0/unsigned posture. A high-integrity process's
      hook DOES receive input to elevated windows, and it can SendInput/paste into them too — so running elevated
      fixes both the trigger and the paste in one move. **The manifest stays `asInvoker`** (default non-elevated);
      elevation is **opt-in** via the tray.
    - **Implementation (App layer only — no brain/Core/test change):**
      • `Platform/Elevation.cs` — `IsElevated`; `RelaunchElevated(flag)` = ShellExecute `runas` (the UAC prompt),
        returns Started / UserCancelled (`Win32Exception` 1223) / Failed; relaunch-flag constants.
      • `Platform/ElevatedAutostart.cs` — registers/removes a **Task Scheduler logon task** "JVoice Elevated
        Autostart" with **RunLevel=HighestAvailable** + a per-user `LogonTrigger` (built as XML, applied via
        `schtasks /create … /xml`). This is the **only seamless** elevated-autostart mechanism: the elevation is
        authorized once (task creation) so logon launches elevated **without a per-boot UAC prompt** — the HKCU
        Run key **cannot** elevate.
      • Tray (`UI/TrayIcon.cs`): **Restart as Administrator** (one-off, when non-elevated) / **Running as
        Administrator ✓** (disabled, when elevated) + **Run as Administrator at Login** (✓ = the task exists).
      • `VoiceCoordinator`: `RestartAsAdministrator()`, `SetRunAsAdminAtLogin()/Toggle…`,
        `ApplyElevationStartupIntent(args)` (the elevated relaunch carries `--enable/-disable-admin-autostart` and
        applies it on startup, since creating/removing a HIGHEST task is itself privileged).
      • `App.Main`: an elevated **relaunch** waits up to 5 s for the outgoing instance to release the
        single-instance mutex (`SingleInstance.TryAcquire(timeoutMs)`), and a **logon** launch (the Run-key value
        now ends in `--autostart`) **steps aside** (`exit 0`) when the elevated task is enabled — so a non-elevated
        Run-key copy can't win the slot at logon and silently re-break the hotkey. A **manual** launch (no
        `--autostart`) never steps aside.
      • `SingleInstance` hardened: a `Mutex` ctor `UnauthorizedAccessException` (the name is owned by a
        higher-integrity instance we can't open) is treated as "another instance is running", not a crash.
    - **Follow-up (2026-06-25): the hotkey now SWALLOWS its main key.** David re-tested and reported the chord
      "just types a space in the terminal and does nothing". Two facts: (1) he was still on the **old pre-fix
      build** (the running PID was the original non-elevated exe — my code wasn't deployed yet), which is why it
      still didn't trigger in the admin terminal; and (2) the stray **space** exposed a real wart — `GlobalHotkey`
      historically did **NOT** swallow the chord (the old comment: "keep behavior transparent"), so on **every**
      trigger the Space leaked through into the focused app. Fix: `HookCallback` now `return (IntPtr)1` on an exact
      chord match (consuming the **main key only**, never the held modifiers, and on every match even when debounce
      skips the trigger — so a held auto-repeat can't dribble spaces). This is **global** (helps non-elevated apps
      too) and is actually **more** faithful to the macOS reference, where the global shortcut is consumed. Ordinary
      Space typing is untouched (no modifier match → not swallowed). `JVOICE_HOTKEY_LOG` now also logs the swallow.
    - **GOTCHAS / invariants:** (a) creating OR removing the HIGHEST task needs elevation — the non-elevated
      enable/disable paths relaunch elevated to do it. (b) `RelaunchElevated` blocks the UI thread on the UAC
      prompt (fine — the user is deciding); on **cancel** the app keeps running unchanged. (c) enabling the task
      also re-writes the Run-key value (if launch-at-login is on) so it gains the `--autostart` marker — otherwise
      a pre-existing Run entry wouldn't step aside. (d) the relaunch carries the exe from
      `LaunchAtLogin.CurrentExecutablePath` (the host `.exe`), so it's a **release** feature like launch-at-login.
    - **VERIFICATION — build 0 errors, `dotnet test` 434/434, and DEPLOYED + verified elevated (2026-06-25).**
      The plumbing has no testable pure logic (consistent with the App layer's other P/Invoke services). Because
      David was still running the stale build, this session **rebuilt Release, stopped the old non-elevated
      instance, and relaunched the new build elevated** (`Start-Process -Verb RunAs`): confirmed the new process is
      running **elevated** (a non-elevated WMI/Path query across the integrity boundary came back blank — the
      classic signature) and the **hook installed** (`%TEMP%\jvoice-hotkey.log`: `SetWindowsHookEx -> hook=… err=0`).
      The in-admin-terminal record→paste loop is the one part only a human at the desk can finish-verify (David's
      go-ahead to finalize docs indicates it now triggers there). **Still pending an explicit dogfood tick:** the
      **persisted** path — "Run as Administrator at Login" registering the `schtasks` task and a real
      logout/login coming up elevated with the tray (the logon-task XML, InteractiveToken + HighestAvailable, is
      the standard recipe — **assumption logged**). Steps: `docs/launch/windows-dogfood-checklist.md` →
      "Permissions & edge cases → Elevated-window dictation".

26. **Settings reordered to mirror macOS + new "Recent Transcripts" history — 2026-06-25.** Two changes
    ported from the macOS Settings UI (layout/behaviour only — the Windows **monochrome palette is unchanged**;
    no colors were touched). **(a) Section order** is now, top-to-bottom: Header, **Stats**, **Recent
    Transcripts**, Whisper Model, Processing, Voice Style, Language, Custom Words, **Corrections**, Keyboard
    Shortcut, footer (Restore/Quit). The old editable **Last Transcript** card (the inline Fix/Revert box) was
    **removed from the UI** — its VM members (`EditedTranscript`/`CanFix`/`CanRevert`/`FixLastTranscript`/
    `RevertLastFix`/`SyncEditedTranscriptFromLast`/`ClearRevertBuffer`) and the `last-transcript.txt` write are
    **kept but unsurfaced** (the macOS handoff sanctions leaving them unused). **Corrections is Windows-only**
    (no macOS counterpart, §6/CorrectionRule) and the macOS order doesn't list it — **assumption logged:** it's
    kept immediately after Custom Words (its sibling), between Custom Words and Keyboard Shortcut.
    **(b) Recent Transcripts** is a read-only history of the last **30** finalized transcripts, newest first.
    Architecture mirrors the SettingsStateJson/StatsStore split — **pure brain in Core, file-I/O in App:**
    - `JVoice.Core/Models/TranscriptHistoryEntry.cs` — `record TranscriptHistoryEntry(Guid Id, string Text)`
      (the Id gives each row a stable identity so a per-row delete targets the right entry).
    - `JVoice.Core/Models/TranscriptHistory.cs` — pure `Add` (trim → blank-ignored → prepend → cap 30),
      `Remove(id)`, `Serialize`/`Deserialize` (camelCase JSON; **corrupt/missing/blank → empty list, never
      throws**; drops blank-text entries, fills a missing id, caps to 30). **Unit-tested** by
      `JVoice.Tests/TranscriptHistoryTests.cs` (19 cases).
    - `JVoice.App/Platform/TranscriptHistoryStore.cs` — thin lock-guarded wrapper: loads on construct, mutates
      via the Core helpers, persists synchronously to `%APPDATA%\JVoice\transcript-history.json` with the same
      atomic temp+move + `SystemActions.ReportError` pattern as StatsStore. `Add` returns the new entry so the UI
      inserts just that row.
    - `JVoice.App/UI/TranscriptRow.cs` — bound row VM: immutable `Id`+`Text` plus one transient
      `JustCopied` flag (never persisted) the Copy button flips for `AppTimings.CopyFeedbackDuration` (1.2 s).
    - **Wiring (`VoiceCoordinator`):** `_historyStore` + `ObservableCollection<TranscriptRow> RecentTranscripts`
      + `HasRecentTranscripts`; `AddRecentTranscript(processed)` is called in `FinishTranscriptionAsync` at the
      **same UI-thread point that records stats / the last transcript** (after a successful paste, using the
      final pasted text). `ResetSettings` (Restore Defaults) **also clears the history** (`_historyStore.Clear()`
      + collection clear) — **statistics are deliberately NOT reset** (StatsStore untouched, unchanged from
      before). The Restore-Defaults confirmation text now says recent transcripts will be cleared and stats won't
      be affected.
    - **UI (`SettingsView.xaml`):** empty state shows muted "No transcripts yet."; non-empty is a
      `ScrollViewer MaxHeight=150` of single-line, `TextTrimming=CharacterEllipsis`, `TextWrapping=NoWrap` rows.
      Each row Border has a base `Background=Transparent` (so the whole row is hit-testable) and an
      `IsMouseOver` trigger that highlights it (`#1AFFFFFF`, monochrome) and reveals a Copy + Delete button pair
      (revealed via `Visibility` bound to the row Border's `IsMouseOver` through `BoolToVis`). Copy =
      `Clipboard.SetText` (try/catch for clipboard-busy) + glyph swaps to a checkmark for 1.2 s; Delete =
      `RemoveRecentTranscript(row.Id)`. A monochrome **"Clear all"** button below the list calls
      `ClearRecentTranscripts`. **Privacy:** plaintext on disk, erased **only** by explicit user action (per-row
      delete, Clear all, Restore Defaults) — nothing clears it automatically.
    - **VERIFICATION:** `dotnet build windows/JVoice.sln -c Debug` = 0 errors; Release App build = 0 errors
      (the locked-DLL copy error if a JVoice instance is running is a file lock, not a code error — build to a
      separate `-o` dir, or stop the instance); `dotnet test` green incl. the **19 new `TranscriptHistoryTests`**
      (the full-suite total moves with concurrent work — 523 at this writing). Layout confirmed
      headlessly via `JVoice.exe --settings-render` in both empty and seeded states (order correct, rows
      ellipsis-truncate, Clear all present, palette unchanged). **Hover-reveal, Copy→checkmark, Delete, Clear
      all, persistence-across-restart, and Restore-Defaults-clears-history are the interactive bits** a static
      render can't capture → on the dogfood checklist ("Settings panel → Recent Transcripts").
27. **Game-detection hotkey suppression — David-requested 2026-06-25 (Windows-only; no macOS equivalent).**
    When a **video game owns the foreground**, the hotkey goes **silent AND fully transparent** — JVoice does
    not record, and crucially it **stops swallowing the chord** so `Ctrl+Shift+Space` passes straight through
    to the game (it may be an in-game bind). Stops an accidental keypress in Minecraft/GTA/Fortnite/Valorant
    from popping the HUD or pasting into game chat. Plan: `docs/superpowers/plans/2026-06-25-windows-game-detection.md`.
    - **ANTI-CHEAT SAFE BY CONSTRUCTION (David's hard requirement — no false bans).** Detection uses ONLY
      read-only OS queries and **never touches a game process**: the only process handle opened is
      `PROCESS_QUERY_LIMITED_INFORMATION (0x1000)` to read the image path via `QueryFullProcessImageName`.
      **NO** memory reads, **NO** `PROCESS_VM_READ`, **NO** module enumeration (`EnumProcessModules`/Toolhelp),
      **NO** injection, **NO** overlay, **NO** synthesized input — i.e. none of the behaviours Vanguard/EAC/
      BattlEye ban for. On any `OpenProcess` denial (hardened process) the path-based signals just go false and
      we move on — **never retried with broader access**. The graphics-DLL module-scan signal from the plan was
      **deliberately dropped from v1** to keep process interaction at exactly zero (it also avoided a fullscreen-
      browser false positive). Same API category as OBS / Windows Focus Assist.
    - **Pure brain (`JVoice.Core/Policy/GameDetectionPolicy.cs`, unit-tested like `HotkeyGate`):** `GameSignals` →
      `ShouldSuppress(signals, GameDetectionMode)`. Modes `Off | Balanced | Aggressive` (`JVoice.Core/Models/
      GameDetectionMode.cs`). [reorg 2026-06-26: policy now at `JVoice.Core/Policy/GameDetectionPolicy.cs`] **Balanced (default)** suppresses on `D3DFullscreen ∨ RegisteredGame ∨ KnownGamePath`
      — deliberately **NOT** bare fullscreen, so fullscreen video/browsers never false-positive. **Aggressive**
      also suppresses on any borderless/exclusive fullscreen app (catches obscure windowed games; will also trip
      on fullscreen YouTube — opt-in). User force-allow/deny (`UserForceNotGame`/`UserForceGame`) are wired in the
      policy but hard-false in v1 (the per-exe lists are v2).
    - **Signals (`JVoice.App/Platform/System/GameDetector.cs`, all read-only):** #1 `SHQueryUserNotificationState ==
      QUNS_RUNNING_D3D_FULL_SCREEN` (Microsoft's own Focus-Assist "a game is fullscreen" signal, process-
      untouching); #2 **GameConfigStore** (`HKCU\System\GameConfigStore\Children\*` → `MatchedExeFullPath`, 30 s
      cache) — Windows' own per-user recognized-game list, catches **windowed Minecraft**; #3 known install roots
      (`\steamapps\common\`, `\Epic Games\`, `\Riot Games\`, …) + a curated exe-name set (`VALORANT-Win64-Shipping.exe`,
      `GTA5.exe`, … — **not** `javaw.exe`, too ambiguous); #4 foreground window rect == monitor rect (excl. shell
      `Progman`/`WorkerW` + our own windows). Decision cached in a `volatile bool`, recomputed on
      `ForegroundWindowTracker.ForegroundChanged` (new event) + a 1.5 s `DispatcherTimer` backstop (alt-enter).
      **Foreground-keyed:** a backgrounded/alt-tabbed game does NOT suppress (so dictating into an app on monitor 2
      while a game sits on monitor 1 still works).
    - **Wiring:** `GlobalHotkey.SuppressPredicate` (O(1) volatile read on the hook thread) → on suppress,
      `return CallNextHookEx(...)` (passthrough), NOT `(IntPtr)1` (swallow). The predicate is
      **`() => !IsRecording && _gameDetector?.ShouldSuppress == true`**: it suppresses (passes the chord to the
      game) only when a game is foreground **and we're not already recording**, so a recording started *before*
      alt-tabbing into a game can still be **stopped** with the hotkey (and that stop-press is swallowed, not
      leaked into game chat). `VoiceCoordinator` constructs the detector in `Start()` (with `_foreground`), sets
      the predicate before `_hotkey.Register`, pushes `GameMode` from settings, and start-guards `ToggleRecording`
      (covers the tray Start path). Settings adds a monochrome **"Gaming"** segmented picker (Off/Balanced/Aggressive).
      **`SettingsState` schema v1→v2** adds persisted `GameMode` (default Balanced); a v1 file with no `gameMode`
      loads as Balanced (backward-compat). **When `GameMode == Off`, `GameDetector.Recompute` short-circuits — it
      does NOT inspect the foreground at all** (no `OpenProcess`, no registry read): zero process interaction when
      the feature is disabled.
    - **`--game-probe` dev CLI (`JVoice.exe --game-probe [seconds]`, default 60):** loops `GameDetector.Inspect()`
      once/sec, writing each foreground-window signal snapshot to **`%TEMP%\jvoice-gameprobe.log`** (and console
      under redirection — WinExe) so you can alt-tab into a real game and read the live signals + decision. Runs
      before WPF, like `--bench`.
    - **VERIFICATION:** `GameDetectionPolicyTests` truth table (precedence + the Balanced-excludes-bare-fullscreen
      guarantee) + settings v1→v2 migration tests; `dotnet build windows/JVoice.sln -c Debug` = 0 errors;
      `dotnet test` = **523/523**. The Win32 signal-gathering itself has no unit tests (Win32 glue, like the other
      `Platform/*` interop) — verified live via `--game-probe` during dogfood (gaming section of the checklist).
    - **Commits:** `0b73904` (policy + settings v2 + hook passthrough), `e8153ee` (GameDetector), `40af40b`
      (`--game-probe`). **NOTE:** the `VoiceCoordinator` + `SettingsView.xaml` wiring landed *inside* commit
      `8002db9` (the concurrent "Recent Transcripts" commit) — that session's wholesale `git add` swept the
      uncommitted wiring in; the code is intact and correct, just filed under that commit rather than a clean one.
    - **Remaining:** David's interactive dogfood (gaming section). **v2 (optional):** per-exe allow/deny lists in
      Settings, a manual **"Pause JVoice"** tray toggle and/or **push-to-talk** so a stray tap can't latch a
      recording regardless of detection.
28. **Developer-terms correction pack — opt-out, recognizes coding vocabulary (2026-06-25).** David dictates
    programming terms ("Node.js", "GitHub", "TypeScript", "JSON", "C#", ".NET", "OpenAI"…) and Whisper mis-rendered
    them — usually spacing/casing drift ("node js", "git hub", "type script") or a dev homophone ("jason"→JSON). The
    custom-words box helped but is the wrong tool at scale: only its first 40 words ever reach the decoder prompt
    (`VocabularyPrompt.MaxWords`), and that scarce budget should stay reserved for the user's genuinely-unusual words.
    - **Design — route to the UNBOUNDED post-processing channel, NOT the decoder prompt.** Most coding terms are
      already transcribed phonetically close; they only need spelling/casing NORMALIZATION, which the `extraDictionary`
      path (`TextProcessor.ApplyCorrections`) does for hundreds of terms at **zero decoder cost and zero
      prompt-regurgitation risk**. So the pack is a post-hoc correction dictionary, not a `VocabularyPrompt` addition.
    - **`JVoice.Core/Text/DeveloperTerms.cs`** — a curated `Map` (heard-form→canonical, ~165 entries after the
      2026-07-01 AI/vibe-coding expansion — see §7 #34) + `Augment(baseDict)`.
      NEW Windows-first Core file (NOT a 1:1 Swift port; intended to be ported to macOS later like the rest of the
      brain). It is deliberately NOT folded into `TextProcessor` (which stays a verbatim macOS port).
    - **Wiring (`VoiceCoordinator` ProcessAndPaste):** `userDict = BuildUserDictionary(vocab)` →
      `withPack = DeveloperTermsEnabled ? DeveloperTerms.Augment(userDict) : userDict` → `UserCorrections.Merge(withPack, rules)`.
      **Precedence (low→high): dev pack < user custom-word variants < user correction rules < builtin
      CorrectionDictionary.** `Augment` lays the pack UNDER the base dict so a user's own custom word always wins over
      the generic pack. (Very Casual lowercases before `ApplyCorrections`, so the pack also RE-CASES correctly there.)
    - **Curation is deliberately CONSERVATIVE** — only unambiguous spacing/casing fixes + clearly-dev homophones.
      Ambiguous single English words are EXCLUDED so ordinary dictation is never corrupted: `go`/`rust`/`swift`/`react`
      casing, bare `java`/`pandas`, bare `dotnet` (would wreck the lowercase `dotnet` CLI), `sequel`→`SQL` (would wreck
      "the movie sequel"). The test `Map_ExcludesAmbiguousEnglishWords` LOCKS that policy. The acronym-casing entries
      (`api`→API, `sql`→SQL, `url`→URL…) are safe because `\bword\b` boundaries prevent intra-word hits — `FastAPI`,
      `REST API`, `PostgreSQL`, `HTTPS` are all left intact. **One KEPT risk:** `jason`→`JSON` collides with the name
      "Jason" — overwhelmingly right in coding dictation and trivially removable via a user correction rule.
    - **Settings:** `SettingsState.DeveloperTerms` (bool, **default ON**) — a second Windows-only on-disk key
      `developerTerms` alongside `corrections`; **no schema bump** (per-field fallback to `true` on absence, so
      older/macOS files and existing installs come up ON after upgrade). `VoiceCoordinator.DeveloperTermsEnabled`
      (named differently from the `DeveloperTerms` class to avoid shadowing it inside the coordinator) + a monochrome
      **"Developer Terms"** toggle in the Processing settings section.
    - **VERIFICATION — `dotnet test` 523/523** (full merged suite after integrating the game-detection/v2 line;
      added `DeveloperTermsTests` (30) + settings round-trip/default coverage); `JVoice.App` builds 0 errors. The `node js`→`Node.js` transforms are locked by end-to-end
      `TextProcessor.Process` tests (more reliable than a live `--bench` of spoken audio).
    - **Built on branch `feat/developer-terms` in an isolated git worktree** (two other sessions were live on
      `windows-port`). ⚠️ **The branch's base — `windows-port` HEAD `f5277ea` — does NOT currently build `JVoice.App`:**
      committed `VoiceCoordinator.cs` references `PlatformPaths.KeepRecordings`/`CaptureDirectory`, which exist only in
      an **uncommitted** `PlatformPaths.cs` in the main checkout (a different session's WIP). The dev-terms App code was
      verified to compile by temporarily borrowing that file (then reverting it). **Merge `feat/developer-terms` →
      `windows-port` once `PlatformPaths.cs` is committed there.**
    - **Follow-ups (not started):** (a) "learn from my fixes" — reuse `TextProcessor.ExtractCorrections` + the
      fix-last-transcript flow to SUGGEST adding a term the user just corrected; (b) categorized packs
      (Web/Python/DevOps…) toggled independently; (c) port `DeveloperTerms` 1:1 to the macOS app.

28. **@-mentionable area reorg + per-area `CLAUDE.md` briefs (2026-06-26).** The `windows/` tree was
    reorganized into `@`-mentionable area folders via **pure `git mv`** — 0 source edits, every move
    `R100`, build + **523/523** tests byte-identical to baseline. `JVoice.App/Platform/` split into
    `Capture/` (recorder + input router), `Persistence/` (settings/stats/transcript stores + paths),
    and `System/` (hotkey, paste, elevation, game detection, display, single-instance, …). The five
    `JVoice.Core` root helpers (CoordinatorDecisions, HotkeyGate, GameDetectionPolicy, StatsMath,
    AppTimings) moved to `JVoice.Core/Policy/`. **Namespaces were NOT changed** (C# declares them
    in-file) — so folder ≠ namespace is intentional, no `using` moved; don't "fix" it as a drive-by
    (that's a separate cross-cutting rename). Each area folder got a `CLAUDE.md` brief; `windows/CLAUDE.md`
    is the area index. App-shell files (`App.xaml`, `app.manifest`, `Assets/`) stayed put (path-coupled
    in `JVoice.App.csproj`). The macOS `Sources/` was untouched.

29. **Settings widened to a two-column layout + two layout bugs fixed (David-requested, 2026-06-26).**
    `SettingsView.xaml` went from a single tall scrolling column (`320×520`) to a **wider `640×846`
    two-column "masonry"**: a full-width header (row 0), a two-column body (row 1), and a full-width
    footer (row 2), all still inside the outer `ScrollViewer`. The body is a 3-column Grid (`*` / `14`
    gutter / `*`); each side is an independent vertical `StackPanel` so variable-height cards pack
    tip-to-tail with **no cross-column height coupling** (rejected `UniformGrid` = forced equal cells,
    and `WrapPanel` = ragged gaps). The 10 cards split **order-preserving** to keep the macOS reading
    order, growth-balanced so no column balloons: **Left** = Stats · Recent Transcripts · Whisper Model
    · Processing · Voice Style; **Right** = Language · Custom Words · Corrections · Keyboard Shortcut ·
    Gaming. `HorizontalScrollBarVisibility="Disabled"` on the `ScrollViewer` is **required** — it gives
    the body a finite width so the `*` columns resolve (at infinite measure width the masonry + the
    flex add-rows collapse). The result is **wider and shows everything at once with no scrolling** for
    a typical populated state (David's data: ~5 custom words + several transcripts) — vs. the old
    320-wide window that scrolled ~1400px; the `ScrollViewer` remains an overflow safety net.
    Two bugs fixed structurally (robust at any width, not just papered over by the new size):
    (a) **Developer Terms subtitle overlapped its toggle** — each Processing row was a single-cell Grid
    where the unconstrained left text slid under the right-aligned switch; now a 2-column Grid (`*` text
    col with a 12px right margin + `TextWrapping="Wrap"`, `Auto` switch col) so text can never reach the
    switch. (b) **Corrections "Add" button was clipped to "Ac"** — the add-row was a fixed-width
    horizontal `StackPanel` (100+arrow+100+button > content width) that overflowed; now a Grid with
    flexible `*` input column(s) + `Auto` button (and `Auto` arrow), applied to **both** Custom Words and
    Corrections, so the button always reserves its full width. The four `x:Name`d elements (`Recorder`,
    `NewWordBox`, `CorrectionFromBox`, `CorrectionToBox`) were preserved → **zero `SettingsView.xaml.cs`
    changes**. The off-screen screenshot harness `App.xaml.cs:RenderSettingsToFile` now follows the
    view's own declared size (`new Size(view.Width, view.Height)`) instead of a hardcoded `320×520`, so
    `SettingsView.xaml:5` is the single source of truth. Verified via `--settings-render` (empty +
    David's populated state) + **536/536** tests green. Height (846) was tuned empirically to fit David's
    current data with no scrollbar; one number to change if a shorter (slightly-scrolling) window is
    preferred. The macOS `Sources/` Settings (its own `320×520` view in a `640×480` window) is unchanged.

30. **Installed app + both installers refreshed to the §29 two-column build; autostart repointed; CPU-default
    distribution decided (2026-06-26).** After §29 the user-facing install
    (`%LOCALAPPDATA%\Programs\JVoice`) and both `~/Downloads` installers were still the pre-Settings build
    (`cd63b3b`); all were refreshed to `6f8ffc2`.
    - **Install refreshed in place** with `robocopy /MIR <gpu-folder> <install> /XF uninstall.ps1` from a
      fresh `dotnet publish windows\JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=gpu -p:SelfContained=true
      -p:PublishTrimmed=false -p:PublishReadyToRun=true -o windows\artifacts\gpu-folder`. **Use robocopy /MIR,
      NOT `Remove-Item -Recurse -Force`** — the harness sandbox blocks recursive force-deletes of the
      `Programs\JVoice` path. The GGML model store (`%LOCALAPPDATA%\JVoice\models\`, ~574 MB) and the
      Start-Menu `.lnk` live OUTSIDE the install dir, so they survive a mirror.
    - **Autostart repointed.** `HKCU:\…\Run\JVoice` had drifted to the volatile dev
      `bin\x64\Release\…\JVoice.exe`; repointed to `"<install>\JVoice.exe" --autostart` (the exact format
      `LaunchAtLogin.SetEnabled` writes) so logon launches the *installed* app, matching the single
      Start-Menu shortcut + Uninstall entry. App *search* was already correct (one `.lnk`).
    - **Both one-click installers rebuilt** from `6f8ffc2`: `JVoice-Setup.exe` (CPU, ~65 MB) and
      `JVoice-Setup-GPU.exe` (GPU, ~360 MB). Recipe: publish each flavor to a folder (CPU adds
      `-p:JVoiceFlavor=cpu -p:PublishSingleFile=false`), zip the folder as `app.zip` with a **top-level
      `JVoice\`** (what `install.ps1` expects), then `iexpress /N /Q windows\artifacts\JVoice-<flavor>.sed`
      packs `app.zip` + `install.ps1` + `uninstall.ps1` into the setup `.exe` (TargetName → `~/Downloads`).
      Verified end-to-end (inner `JVoice.exe` ProductVersion = `6f8ffc2`).
    - **Distribution decision (David):** **CPU `JVoice-Setup.exe` is the default download for everyone; the
      GPU build is optional, only worth its ~5× size for NVIDIA owners** (it falls back to CPU otherwise).
      Documented in `docs/launch/windows-distribution.md` + the ready-to-paste
      `docs/launch/windows-release-notes-draft.md`.
    - **Gotchas:** a JVoice instance running **elevated** can't be killed from a non-elevated shell (Access
      denied) and locks the install dir's `JVoice.exe`/`JVoice.Core.dll` → quit it via the tray before any
      swap. The IExpress build inputs (`pkg-gpu/`, `pkg-cpu/`, `*-folder/`, `JVoice-<flavor>.sed`) live under
      the gitignored `windows/artifacts/`. **`LICENSE.txt` is not yet inside the installer folder** (GPL-3.0
      wants it shipped with the binary) — add before any public release.
    - **NOT published** — the repo (`david53001/jvoice`) stays **private**; pushing here is a private sync,
      not the on-hold public release.
31. **Whisper transcription speed-up — flash attention + decode threads, measured & adopted (2026-06-27).**
    A tuning layer on top of the existing Whisper.net 1.9.1 engine (NO model change, NO Whisper.net upgrade —
    1.9.1 is already latest; the "brain" `JVoice.Core/Text` is untouched). Plan +
    measured numbers: `docs/superpowers/plans/2026-06-27-windows-whisper-speed.md` (+ `…-results.md`).
    - **New pure helper `JVoice.Core/Policy/WhisperTuning.cs`** (Windows-first, like GameDetectionPolicy —
      unit-tested by `WhisperTuningTests`, +19) holds `AudioContextFor`/`DecodeThreads`. **New App record
      `JVoice.App/Whisper/EngineTuning.cs`** carries the knobs into `WhisperNetTranscriptionEngine`
      (factory `WhisperFactoryOptions.UseFlashAttention`; builder `.WithThreads` / `.WithAudioContextSize`).
      The engine ctor gained a trailing optional `EngineTuning? tuning = null` (defaults to `EngineTuning.Default`,
      so `VoiceCoordinator.MakeEngine` and the tools are unchanged). `whisper-smoke` links the two new files.
    - **ADOPTED #1 — flash attention ON for GPU builds.** On the RTX 3060 Ti (Vulkan) large-v3-turbo decoded
      **~30–37% faster** (18.8 s clip 0.538 s → 0.360 s; default-vs-old-default 0.565 s → 0.348 s ≈ **−38%**)
      with **byte-identical transcripts**. Forced **OFF** in the `cpu` flavor via a new `JVOICE_CPU`
      `DefineConstants` (`#if JVOICE_CPU` in `EngineTuning.Default` + a belt-and-suspenders guard in
      `PerformLoadAsync`) — flash degrades CPU decode (whisper.cpp PR #2152). Verified: dev/GPU `--bench`
      reports `flash=on`, the cpu-folder build reports `flash=off`.
    - **ADOPTED #2 — `WithThreads` = physical core count** (new `JVoice.App/Platform/System/CpuInfo.cs`,
      Win32 `GetLogicalProcessorInformation`). CPU decode (`tiny`) was **~21% faster at 6 vs whisper's
      default 4** (no gain past physical cores); ~no effect on GPU. This mainly helps the **CPU build (the
      default download)**.
    - **NOT adopted — per-clip `audio_ctx`.** Measured **non-monotonic**: a 768-frame ctx REGRESSED ~9 s
      clips 2–3× (while 896–1280 helped), and tuning a floor on SAPI clips risks misbehaving on David's real
      low-SNR mic. Left OFF; lever stays behind `--bench --audio-ctx`. **CUDA** confirmed unavailable without
      the toolkit (forced-cuda bench) → stays a documented opt-in, not shipped (no `Cuda12` package added).
      **Temp-fallback cap** not adopted (diverges from macOS parity, marginal EV).
    - **`--bench` instrumented** (`--iters` median/min, `--flash`, `--threads`, `--audio-ctx`, `--runtime`,
      `--log-runtime`; warm-up excluded; bases tuning on `EngineTuning.Default` so a no-flag run reflects
      shipped behavior). New `WhisperRuntime.ForceRuntimeOrder/EnableDebugLogging`. ⚠ **WinExe stdout is only
      captured via `& JVoice.exe … 2>&1 | …`, never `$out = & …`.**
    - **VERIFICATION:** `dotnet build windows/JVoice.sln -c Release` = 0 errors; `dotnet test` = **555/555**
      (was 536; +19 WhisperTuningTests). On-device benches above. Live-mic accuracy with flash on is a
      dogfood item (the realistic clips were transcript-identical; only a degenerate 8×-repeat synthetic clip
      diverged → "No speech").

32. **Dictation-features batch — quick-wins bundle + app-aware modes (2026-07-01).** David asked "what
    should we add"; picked a **quick-wins bundle first, then app-aware modes**. All on branch
    `feat/dictation-modes`. Plan: `docs/superpowers/plans/2026-07-01-windows-dictation-modes.md`. The
    "brain" `JVoice.Core/Text` is untouched; the new Core pieces are pure + TDD-locked; the
    game-detection / anti-cheat invariants are preserved.
    - **Schema bump v2 → v3 (ONE bump for the whole batch).** `SettingsState` gains five Windows-only
      fields, each with a safe default + per-field JSON fallback so a v2 file upgrades transparently:
      `copyToClipboardOnly` (false), `undoHotkey` (nullable — **null = disabled**, serialized as JSON
      null; the only field whose malformed/absent value falls back to null not a default chord),
      `translateToEnglish` (false), `appAwareModes` (**true**), `appModeRules` (empty). Version-coupled
      tests moved to v3 in the same commit (schema asserts, forward-version boundary 3→4, exact-keys
      10→15). `AppModeRules` uses a nullable-param + normalized-property so positional/defaulted
      construction never yields null.
    - **Quick win — clipboard-only.** `FinishTranscriptionAsync` stages the text (`Paster.Stage`, which
      already existed) instead of pasting when the "Copy to Clipboard" toggle (Processing card) is on.
      No `_lastPastedText` capture in this mode (nothing in an app to undo).
    - **Quick win — time saved.** New pure `StatsMath.EstimatedMinutesSaved` (words ÷ **40 wpm** typing
      baseline − minutes spoken, floored at 0, NaN/neg-safe; `TypingWpmBaseline = 40.0`). Surfaced as a
      third stat in the now **three-up** green Stats card (`TimeSavedDisplay`: "—" / "N min" / "N.N h").
      6 new StatsMathTests.
    - **Quick win — dictate-to-translate.** Whisper.net 1.9.1 **does** expose `WithTranslate()` (verified
      by reflecting the DLL — an earlier explore agent wrongly inferred it was absent). Engine ctor gained
      a **trailing** optional `bool translate = false` (placed after `tuning` so BenchRunner's positional
      `tuning` arg still binds); `_translate` → `builder.WithTranslate()`. The "Translate to English"
      toggle (Language card) rebuilds the engine like a language change. Source stays the `Language`
      setting; output is English.
    - **Quick win — undo last paste (opt-in).** A **second** `GlobalHotkey` instance (`_undoHotkeyReg`),
      registered only when a chord is assigned (**no default** — a registered global chord is swallowed
      system-wide, so a default would clobber a common key). `UndoLastPaste()` sends the foreground app's
      own Undo via new `Paster.SendUndo()` (Ctrl+Z; `SendCtrlV` refactored to a shared `SendCtrlKey`).
      Guarded (only if JVoice pasted this session + foreground isn't ours), **one-shot** (clears
      `_lastPastedText`), and **game-suppressed** (passes the chord through to a foregrounded game).
      Recorder + Clear button in the Keyboard Shortcut card; shows "None" when unset.
    - **App-aware modes.** New Windows-only `ToneStyle.Code` (4th value; minimal formatting — preserve
      casing/symbols/terminal punctuation as spoken, no forced cap/period/lowercase; corrections + filler
      removal still apply; kept OUT of the manual `Toggled` cycle). New pure `AppModeResolver.Resolve(exe,
      userRules, enabled)` + `AppModeRule` record: user rules win (case-insensitive substring, list order =
      precedence) over a built-in `CodeApps` list (terminals/editors/IDEs → Code); null when off/unknown/
      unmatched → caller keeps the global tone. The foreground exe is read by new
      `JVoice.App/Platform/System/ForegroundApp.ExeName` — **same read-only access class as GameDetector**
      (`PROCESS_QUERY_LIMITED_INFORMATION` + `QueryFullProcessImageName` only; no memory reads/module
      scans/injection — anti-cheat-safe). Applied in `FinishTranscriptionAsync` on the paste `target`
      before `TextProcessor.Process`. New "App Modes" card: master toggle (default ON) + per-app rule
      editor with a **click-to-cycle mode chip** (ComboBox avoided — its dropdown fights the monochrome
      theme). **NOTE on the request:** David said "switch models" — in context that means **modes** (tone),
      not Whisper models; per-app rules switch tone only (a runtime model reload costs seconds). Per-app
      *model* override is left as a documented future field.
    - **UI:** `SettingsView.xaml` grew to **640×1080** two-column (rendered-verified via `--settings-render`;
      two initial-display values — the mode chip "Code" and the undo recorder "None" — are set in XAML, not
      `Loaded`, because the render harness doesn't fire `Loaded`).
    - **VERIFICATION:** `dotnet build windows/JVoice.sln -c Release` = 0 errors; `dotnet test` = **608/608**
      (was 555; +53 across StatsMath / TextProcessor / AppModeResolver / SettingsState / SettingsStoreJson).
      Settings render inspected. **Live dogfood pending** (translate accuracy on RO speech; the undo chord;
      per-app Code mode in a real terminal/VS Code; clipboard-only). **NOT pushed / not merged** — sits on
      `feat/dictation-modes` off `windows-port`.
    - **REVIEW (2026-07-01, commit `39b7864`):** a multi-angle review (correctness / concurrency / cleanup /
      conventions) ran on the branch. Fixed: (a) `ForegroundApp`'s `QueryFullProcessImageName` was binding
      the **ANSI** entry (missing `CharSet.Unicode`) unlike `GameDetector` → a non-ASCII install path would
      mangle the exe name; now matches `GameDetector` exactly; (b) the undo chord could be set equal to the
      record chord (esp. via the recorder's Backspace-→-default) → both hooks swallow the same press;
      `SetUndoHotkey`/`SetHotkey` now reject/clear on a shared trigger (modifiers+VK); (c) `UndoLastPaste` now
      gates on the paste-target HWND so alt-tabbing away can't Ctrl+Z the wrong app; (d) `HotkeyRecorder`
      gained an opt-in unset/`Placeholder` state (`AllowClear`) so the undo recorder shows "None" and
      Backspace clears; (e) the app-aware foreground-exe syscall now runs only when the toggle is ON; (f) App
      Modes list got an empty-state + `MaxHeight`; (g) fuzz round-trip now covers the v3 fields. The
      `AppModeRules.ToList()`-on-a-background-thread flag was **refuted** — `FinishTranscriptionAsync` has no
      `ConfigureAwait(false)`, so with the `DispatcherSynchronizationContext` every continuation (incl. the
      `.ToList()`s) resumes on the UI thread, same as the pre-existing `CustomWords`/`Corrections` calls — no
      race. **Deferred (considered, not bandaids):** generalizing `GlobalHotkey` to a multi-chord binding list
      (the undo feature adds a 2nd low-level hook/thread/watchdog — cost only paid when undo is enabled), and
      extracting a shared `ProcessImagePath.FromWindow(hwnd)` so the exe-path read isn't duplicated between
      `ForegroundApp` and `GameDetector` (touches the invariant-locked `GameDetector`; the two are now at
      least byte-identical). Also latent, unchanged: the `Loaded`-time event subscriptions assume the Settings
      window is hidden-not-destroyed (true today; matches the pre-existing main-recorder pattern).
    - **SEARCHABLE APP PICKER (2026-07-01, commit `7bc94fa`, David-requested):** the App Modes add-row is no
      longer a raw exe text box — focusing it opens a dark filtered dropdown of the user's **currently-open
      apps** (friendly `FileVersionInfo.FileDescription` + exe name), typing filters, picking fills the exact
      exe name the resolver matches. Free-text still works (partial name = substring match at runtime). New
      `JVoice.App/Platform/System/RunningApps.cs` enumerates visible/titled/non-owned top-level windows, skips
      shell hosts (`ApplicationFrameHost`…), de-dupes by exe — **read-only, reuses the now-public
      `ForegroundApp.ExePath`** (no new privileged P/Invoke; anti-cheat-safe). Verified via a throwaway
      `--list-apps` probe (found Chrome/VS Code(exe "Code")/Discord/Spotify/Explorer with correct friendly
      names), then the probe was removed. `--settings-render` shows the watermark; the popup itself opens only
      on focus (not in the static render).
    - **INSTALLED BUILD REFRESHED (2026-07-01):** David dogfooding — the install at
      `%LOCALAPPDATA%\Programs\JVoice` was updated to this branch via a fresh `JVoiceFlavor=gpu` publish +
      `robocopy /MIR /XF uninstall.ps1` (preserve the uninstaller; user data lives elsewhere), relaunched
      **non-elevated**. So the installed app is now the `feat/dictation-modes` build, NOT `windows-port`/`main`
      — reinstall from `JVoice-Setup-GPU.exe` (or re-mirror a `windows-port` publish) to revert.

33. **Settings went two-column → three-column so the window fits the screen (David-requested, 2026-07-01).**
    David reported the Settings window was "very very long and not as wide" — so tall he **couldn't click the
    title-bar X to close it**. Root cause: `SettingsView` was a fixed `640×1080` and `SettingsWindow` uses
    `SizeToContent.WidthAndHeight` + `CenterScreen`, so on his **non-native 1600×1080** desktop a ~1090-tall
    window (centered in a ~1032 work area) pushed the title bar off the top of the screen. The §32 additions
    (App Modes card + Translate row) had made the two-column layout hit the full 1080. **Fix — three-column
    masonry** (`SettingsView.xaml`): Width **640→960**, body Grid `* 14 * 14 *`, the 11 cards redistributed
    across three independent vertical-StackPanel columns —
    col1: Stats / Recent Transcripts / Whisper Model / Voice Style;
    col2: Language / Processing / Custom Words / Gaming;
    col3: App Modes / Corrections / Keyboard Shortcut
    (the four list cards kept in separate columns so none balloons). Each column stays ~300px wide (identical
    to the old per-card width, so **no card is more cramped** — the panel got wider, not the cards narrower).
    The view's **fixed `Height` was removed** (it now sizes to content, exactly what the live `SizeToContent`
    window does); result is **960×757**, rendered-verified via `--settings-render` — comfortably inside the
    work area, X always reachable. Two structural guards so this can't recur: `SettingsWindow` clamps
    `MaxHeight = SystemParameters.WorkArea.Height − 16`, and the view's outer `ScrollViewer` scrolls if a
    future card ever overflows. **Harness gotcha fixed too:** `RenderSettingsToFile` now does **two**
    Measure→Arrange→UpdateLayout passes before reading `DesiredSize.Height` — the outer ScrollViewer settles
    its content extent only after the first pass, so a single pass under-measured (683 vs the true 757) and
    clipped the tallest column + footer. Brain untouched; `dotnet test` **608/608**; NOT pushed. Code-behind
    unchanged (all `x:Name`d elements — `Recorder`, `UndoRecorder`, `NewWordBox`, `CorrectionFromBox/ToBox`,
    `AppRuleBox`, `AppRuleWatermark`, `AppPickerPopup`, `AppPickerList`, `AppRuleModeButton` — were moved with
    their cards, names preserved). ⚠ **Not yet dogfooded live** — the two-pass need in the harness means the
    live `SizeToContent` window *should* settle on its own (WPF runs the layout loop to completion), and worst
    case the `MaxHeight` guard + outer ScrollViewer keep the X reachable, but David should confirm the live
    window opens at ~757 tall (not showing an outer scrollbar).

34. **Developer-terms pack — AI / "vibe coding" expansion (David-requested, 2026-07-01, branch `feat/dictation-modes`).**
    David noted the pack (§7 #28) was strong on the "traditional stack" (JS/Python/infra) but had almost none of the
    modern AI-assisted / "vibe coding" vocabulary. Added a new **`// ---- AI / vibe coding ----`** block to
    `JVoice.Core/Text/DeveloperTerms.cs` — **+58 heard-form keys** (Map `107 → 165`), no code/API change, no schema
    change, no wiring change (it flows through the existing `DeveloperTerms.Augment(userDict)` call at
    `VoiceCoordinator.cs:921`, still gated by the **Developer Terms** toggle, still default ON). Brain otherwise untouched.
    - **What was added** (all unambiguous product tokens; two variants each where Whisper spaces them):
      **tools/agents** Copilot, GitHub Copilot, Claude Code, Codeium, Windsurf, Ollama, Replit;
      **frameworks/protocols** MCP, LangGraph, LlamaIndex, CrewAI, AutoGen, Semantic Kernel, DSPy, vLLM;
      **models/labs** GPT, DeepSeek, Mixtral, Qwen, Gemini, Mistral, Groq;
      **vector DBs** Weaviate, ChromaDB, Qdrant, pgvector, Milvus, FAISS;
      **deploy/stack** Vercel, Netlify, Supabase, Firebase, Cloudflare, PlanetScale, Turborepo, tRPC, SvelteKit,
      Deno, pnpm, Zod, Zustand, Prisma.
    - **The hard part was what to LEAVE OUT.** The pack rewrites ordinary dictation too, so every candidate was audited
      against the actual `\bword\b` matcher (`TextProcessor.PhrasePattern`). Product names that are also everyday English
      are **EXCLUDED** and now **test-locked** in `Map_ExcludesAmbiguousEnglishWords`: **`cursor`** (the text/mouse
      cursor — the single most dangerous possible add), `bolt`, `continue`, `render`, `railway`, `remix`, `warp`,
      `astro`, bare `svelte` (SvelteKit kept instead), `bun`, **`pinecone`/`pine cone`** (the botanical object), bare
      `chroma` (ChromaDB kept instead), `cohere` (the verb), **`perplexity`** (also a real ML metric), `grok` (the
      everyday verb), `drizzle`, `lovable`, and bare `llama` (the animal; versioned model names skipped because Whisper
      renders digits unpredictably). Those products stay reachable via the user's own custom-words / correction rules,
      which outrank the pack.
    - **Three KEPT homophones/judgment calls**, each the same call as the pre-existing `jason`→JSON: `groq`→Groq (NOT
      `grok`), `gemini`→Gemini (SAFE either way — capitalized in both the zodiac and the Google-model sense, so it can
      never corrupt), and distinctive tokens `mistral`/`firebase`/`windsurf` whose non-tech senses (the wind / a military
      firebase / the sport) are vanishingly rare in coding dictation — same judgment already made for `django`/`redis`.
    - **VERIFICATION:** `dotnet test` **650/650** (DeveloperTermsTests 30 → **72**: +11 positive `Process_AppliesPack`
      cases, +12 negative `Process_LeavesAmbiguousWordsUntouched` collision guards, +19 `Map_ExcludesAmbiguousEnglishWords`
      exclusions); `dotnet build JVoice.sln -c Release` **0 errors**. NOT pushed. The full curation rationale (why each
      exclusion, why each kept homophone) is in the `DeveloperTerms` class doc-comment.

35. **Default Whisper model → Large, with a "keep on Large" advisory (David-requested, 2026-07-01, branch `feat/dictation-modes`).**
    David wanted the model to **default to Large and stay there** unless the user really knows what they're doing —
    on his RTX 3060 Ti (Vulkan) large-v3-turbo is both the most accurate model **and** fast (§7 #31 measured it ≈30–37%
    faster with flash attention), so it is the right out-of-the-box choice. **This is a deliberate Windows-only divergence
    from macOS**, which defaults to `.tiny` (`Sources/JVoice/Models/SettingsState.swift:19`) — the `Default_MatchesSwiftDefaults`
    test now carries a comment noting the model field intentionally diverges (other Windows-only default fields already do).
    - **Core (2 constants, kept in sync):** `SettingsState.Default.Model` `Tiny → LargeTurbo`
      (`JVoice.Core/Models/SettingsState.cs`), **and** the per-field fallback in `SettingsStateJson.ParseModel`
      (both the `raw is null` and the final unparseable-value branches) `Tiny → LargeTurbo`. The two are deliberately
      aligned so **any** unspecified-model path (fresh install with no file, a foreign/partial file, a garbage `model`
      string) resolves to the *same* default — which is exactly what `Deserialize_MissingFields_UseDefaults` asserts
      (it compares against `SettingsState.Default.Model`, so it auto-follows). **No schema change** (the `model` field
      already exists; still schema v3) and **no engine/download-flow change** — a fresh user simply downloads the
      ~574 MB `ggml-large-v3-turbo-q5_0.bin` on first use via the existing `WhisperModelStore.EnsureAsync` path
      (HUD `preparingModel`/`downloadingModel`), same as any other model choice.
    - **UI (`SettingsView.xaml`, "Whisper Model" card):** added a monochrome warning callout **below** the segmented
      Tiny/Base/Small/Large control and the per-model guidance line — a bordered box (`#14FFFFFF` fill, `Settings.Border`,
      r6) with the **Segoe MDL2 Assets `E7BA` Warning triangle** (same icon font used elsewhere in Settings) and text
      **"Keep this on Large."** + why (most accurate; fast with GPU; only switch if you know you need to, e.g. an older
      CPU-only PC). An **extra caution line** ("You've picked a smaller model — accuracy may drop…") is bound to
      `Visibility="{Binding IsLarge, Converter={StaticResource InverseBoolToVis}}"` so it appears **only when a smaller
      model is selected** — reusing the existing `IsLarge` VM flag and the `InverseBoolToVis` converter, so **no
      code-behind and no VoiceCoordinator change**. The callout added ~one card-row of height to column 1; the panel
      still fits (the §33 `SizeToContent` + `MaxHeight` clamp + outer `ScrollViewer` guards hold).
    - **Tests updated for the new default** (3 assertions, same commit): `SettingsStateTests.Default_MatchesSwiftDefaults`
      and `.Record_With_OverridesOnlyNamedFields` (`Tiny → LargeTurbo`), and
      `SettingsStoreJsonTests.Deserialize_UnknownEnumValues_FallBackPerField` (unparseable `"Quantum"` now falls back to
      `LargeTurbo`, not `Tiny`). `Deserialize_MissingFields_UseDefaults` needed no edit (it references
      `SettingsState.Default.Model`).
    - **VERIFICATION:** `dotnet test` **650/650**; `dotnet build JVoice.App -c Release` **0 errors**; **both UI states
      rendered** via `--settings-render` (Large selected → advisory only; a temporary reversible swap to Small →
      advisory **+** caution line, then the real `settings.json` restored byte-for-byte to `LargeTurbo`). Committed
      `fcbbe50`; **NOT pushed**. ⚠ **Note for CPU builds:** the default distribution is the **CPU** `JVoice-Setup.exe`
      (§7 #30/§30) where Large runs *slowly* — the callout's "just as fast" wording is GPU-true; a CPU-flavor user is
      the exact "you know you need a smaller model" case the caution line points at. Left as-is (David is the primary
      user, on GPU); revisit if a flavor-aware default is ever wanted.

36. **In-app updates — "there's an update available" prompt + one-click update with an eased bar
    (David-requested, 2026-07-01, branch `feat/in-app-updates`).** Windows-only. A silent startup
    check (opt-out) + a **Settings → Updates** card that shows the current version, "Check Now",
    "Update available — vX.Y.Z", and an **"Update Now"** button; a bold tray item surfaces it too.
    "Update Now" downloads the matching installer behind a **"marketing" progress bar** (eased fill,
    **no percentage text**, fast-start/slow-finish, full only when done), then launches the installer
    and quits so it can overwrite + relaunch. **Updates from a published GitHub Release, not raw
    `main` commits** (intended pipeline: commit/tag → CI builds installers → Release → app sees it).
    - **Full detail: `docs/launch/windows-in-app-updates.md`** (architecture, privacy, publish steps).
    - **Pure Core (`JVoice.Core/Policy/`, unit-locked):** `ReleaseVersion` (tolerant version compare),
      `UpdateProgressCurve` (the eased curve, `Ceiling=0.95` until done), `UpdateCheck`
      (`GitHubReleaseParser` + `UpdateAssetSelector` CPU/GPU + `UpdateDecision`, fail-safe).
    - **App (`JVoice.App/Update/`):** `UpdateConfig` (repo slug + `#if JVOICE_CPU` flavor — the one
      publish-time edit), `UpdateService` (the only I/O: HTTP check never throws, 404→"no update";
      streamed download; ShellExecute the installer), `UpdateCoordinator` (state machine + a 30 ms
      timer easing a shown value toward the pure curve), `UpdateProbeRunner` (hidden `--update-check`).
      `VoiceCoordinator.Updates` + a persisted `CheckForUpdatesAutomatically`; `SettingsView`
      "Updates" card (Col 3, green) with a `FractionToWidthConverter` fill bar; `TrayIcon` item;
      `App.xaml.cs` `--update-preview <state>` + `--settings-render <path> <state>`.
    - **Schema v3 → v4:** new `checkForUpdates` (bool, default true; per-field fallback). Settings
      tests updated (asserts → 4, forward test → 5, key count 15→16, new default/round-trip cases).
    - **Privacy:** the update check is the SECOND and only other network call besides the model
      download — an anonymous GitHub API GET that sends **no user data**; disclosed in the card
      ("No data is sent"); **default ON** (assumption logged) so the prompt appears; **dormant while
      the repo is private** (404 → no update). ⚠ Also: the shipped IExpress `install.ps1` should wait
      for the old JVoice to exit before robocopy (belt-and-braces; see the feature doc).
    - **VERIFICATION:** `dotnet test` **693/693** consolidated with #34/#35 (651 standalone on the
      feature branch = 650 dictation-modes + 43 new); `dotnet build JVoice.sln -c Release`
      **0 errors**; `--update-check` graceful 404; `--settings-render … available|downloading|error`
      render-verified. **NOT dogfooded live** (needs a public release) — David. **NOT pushed.**
    - **Consolidation:** #34/#35 are the concurrent `feat/dictation-modes` session's entries (dev-terms
      AI / default-model→Large); all three (#34/#35/#36) are now merged onto `feat/dictation-modes`.

37. **"Elevated first-recording freeze" root-caused and FIXED — it was never about elevation
    (2026-07-02, branch `feat/dictation-modes`).** The §8 known bug ("launching JVoice elevated freezes
    the first recording; the stop press never registers") is closed. The old ⚠ do-NOT-run-elevated
    warning is obsolete: **elevated dictation works** (verified live this session).
    - **Root cause — a capture-teardown deadlock in `Platform/Capture/NAudioRecorder.cs`, reachable on
      ANY stop, elevated or not.** `Stop()` held the recorder's `_gate` for its whole body and, still
      under that gate, called `_capture.Dispose()`. NAudio's `WasapiCapture.Dispose` **joins its capture
      thread** — but that thread delivers `DataAvailable` every ~10 ms and `OnDataAvailable` takes the
      SAME `_gate` to append samples. If a packet arrived while `Stop()` held the gate, the capture
      thread blocked on `_gate`, `Dispose` waited forever on the join → the **UI thread** (Stop runs on
      the dispatcher) froze permanently: HUD wave stalls, every later hotkey press dispatches into a
      dead dispatcher ("the stop press never registers"), and the diagnostic log ends at `HUD Recording`
      — exactly the 2026-06-26 00:44:48 signature — because the deadlock sat BEFORE the `StopRecording`
      log line. Same join-under-gate hazard existed in `TearDownLocked`'s callers (TryStart failure,
      pump-write failure, `OnRecordingStopped`, `Dispose`).
    - **Why it looked elevation-specific:** coincidence + cold start. The per-stop hit probability is
      tiny (the callback holds the gate ~µs out of every ~10 ms), but on the FIRST stop of a fresh
      process, JIT + cold file caches stretch `Stop()`'s gate hold, widening the window — and the first
      confirmed hit happened to be the first elevated test (n=1). The same signature exists in the log
      **non-elevated on 2026-06-24 00:26** (before the elevated feature was even deployed), and this
      session's UNFIXED build ran a full elevated dictation cycle fine while the seeded repro froze it
      non-elevated.
    - **Deterministic repro (the "failing test"):** new env-gated seam `JVOICE_TEST_SLOW_CAPTURE_MS=<n>`
      (kept in-tree, `GlobalHotkey` test-seam precedent; zero cost unset) widens the callback's gate
      hold. At 200 ms the unfixed build froze on the first stop **every time** (log ends at the dispose
      step); the fixed build completes the full record→stop→transcribe→paste cycle under the same seam.
    - **The fix — never join the capture thread while holding `_gate`:** teardown now **detaches** the
      capture+device from the fields under the gate (`DetachLocked`) and **disposes them outside** it
      (`DisposeDetached`), for all five paths (Stop, TryStart-failure, pump-failure, OnRecordingStopped,
      Dispose). `DisposeDetached` defers to the thread pool iff the current thread still holds the gate
      reentrantly (Stop → pump-failure). Two guards make the detached window airtight: `OnDataAvailable`
      and `OnRecordingStopped` ignore a **stale sender** (`!ReferenceEquals(sender, _capture)`), so a
      final in-flight packet can neither leak samples into a NEW recording's buffer nor tear down a new
      session. Behavior otherwise unchanged (same ≤10 ms tail-drop semantics as before).
    - **Also:** `DiagnosticLog` lines now carry a `[pid/tid]` prefix — the original hunt could not tell
      which instance/thread wrote which line when an elevated relaunch overlapped the outgoing copy.
    - **VERIFICATION:** seeded repro fail→fixed as above (on-device); `dotnet build JVoice.sln -c
      Release` 0 errors; `dotnet test` **693/693**; live loops on the deployed install — non-elevated
      cycle, seeded non-elevated cycle, and **two elevated cycles** (launched UAC-free via
      `Start-ScheduledTask 'JVoice Elevated Autostart'`; chord injected with Notepad foreground) all
      complete: `HUD Recording → StopRecording → Transcribed → HUD Idle`. **Scripted regression check
      (headless — no HUD, no paste, no focus steal):** `dotnet run --project
      windows/tools/capture-stop-probe -c Release -- --cycles 3 --slow-ms 200` drives the REAL recorder
      sources through seeded start/record/stop cycles; exit 0 = pass, 2 = the deadlock is back (not in
      the .sln, like hotkey-probe). David's at-the-desk elevated dogfood tick (§8 item 2) remains the
      final confirmation.

38. **Silence-hallucination gate — the §7 #24 open bug is CLOSED (2026-07-02, branch
    `feat/dictation-modes`).** Near-silent short presses sometimes pasted a confident invented
    sentence ("you're welcome.", "you", "you can't believe it, but you can't believe it.", even the
    bare vocab word "app") — silent data corruption that the frozen `RemoveWhisperHallucinations`
    blocklist can't chase (novel sentences; parity-locked).
    - **Calibration (the #24 plan, executed):** David recorded 13 fresh clips through the LIVE
      pipeline (`JVOICE_KEEP_WAV=1` → `%APPDATA%\JVoice\capture\`; 8 silent presses 0.4–4.4 s +
      5 quiet real sentences), analyzed with `nospeech-probe --analyze` (17 clips total incl. the
      06-24 four; mirrors the live model `large-v3-turbo-q5_0` + his real vocab prompt).
      **Measured:** (a) whisper's confidence is INVERTED as predicted — silence hallucinations
      score avgConf up to **0.96**, real speech 0.58–0.81 → unusable; (b) gzip compR mostly tracks
      text length → unusable alone; (c) **prompt-vs-no-prompt agreement separates 17/17**: on every
      silent press the UNPROMPTED decode collapses to stock "Thank you." (→ blocklist → empty),
      while it keeps the real sentence on all quiet-speech clips; (d) all silent presses measured
      **rawRMS ≤ 0.0003** (digital-level), his quietest real speech 0.0005–0.0028, louder 0.004+.
    - **The gate:** pure `JVoice.Core/Policy/SilenceHallucinationGate.cs` (namespace
      `JVoice.Core.Policy`) + wiring in `WhisperNetTranscriptionEngine.TranscribeAsync`. When the
      guarded transcript is non-empty AND the clip is near-silent (`rawRms < QuietRmsTrigger` =
      **0.004**, 13× above observed silence) AND a vocab prompt is active → decode the same samples
      once more WITHOUT the prompt and reduce that WITNESS (`NonSpeechAnnotation.Reduce` +
      `StripDecoderArtifacts` + `RemoveWhisperHallucinations`): **empty witness ⇒ no-speech; else
      keep the PROMPTED transcript** (the vocab-accurate one). RMS is only the verify TRIGGER —
      the reject decision is always the model's, so the §7 #21 "no level floor may reject speech"
      rule stands: quiet real speech triggers verification and passes because its witness keeps
      words. Cost: one extra decode only on near-silent clips (his louder dictation adds zero).
      Whole-file path only (silent short presses never produce a completed streaming chunk; a
      silent chunk already falls back losslessly).
    - **Balanced against #21 by construction and by data:** 7/7 real quiet clips KEPT through the
      real engine after the gate; 10/10 silent clips → "No speech detected."
      (`--bench` sweep over all 17 capture clips with the live vocab: silent → exit 1 `no-speech
      (model empty/annotation)`, real → exit 0 with the correct transcript.)
    - **VERIFICATION:** `dotnet build JVoice.sln -c Release` 0 errors; `dotnet test` **713/713**
      (20 new `SilenceHallucinationGateTests` locking thresholds + resolve semantics with the
      measured values); the 17-clip `--bench` sweep above. Calibration clips deleted after the
      sweep (privacy); `JVOICE_KEEP_WAV` removed from the user env (HKCU\Environment).
    - **Residual risk (accepted, documented):** if BOTH decodes hallucinate on the same silent clip
      (never observed — unprompted always gave blocklisted stock phrases), the text still pastes;
      and "noisy silence" above 0.004 rawRMS relies on whisper's own annotation (#21 behavior).
      Re-calibrate any time with the same capture → `nospeech-probe --analyze` loop.
39. **Tail-cutoff hunt — mid-stream silent-chunk drop FIXED, tail-coverage recovery added, decode
    instrumentation added (2026-07-03, branch `fix/tail-cutoff`, David-reported).** "Sometimes it
    just cuts the last part of what I'm trying to say."
    - **Evidence (`%APPDATA%\JVoice\diagnostic.log`, 104 paired dictations analyzed):** the loss is
      DECODE-side, not capture. Smoking gun 2026-07-02 23:58: rec=3.52 s with 3.48 s of audio on
      disk decoded to just "please get this" — he re-dictated "please get this into an actual app
      that I can run." 5 s later. Capture layer clean overall (avg recSecs−audioSecs = **0.086 s**)
      EXCEPT two unexplained half-audio outliers (07-02 00:33/00:42, gaps 4.3 s/2.7 s — suspected
      pump-timer starvation under game load + the 5 s `BufferedWaveProvider` overflow-discard;
      OPEN). Long streamed dictations ran 0.78–1.05 words/sec vs his normal ≈2.5–3 → mid-stream
      chunk loss. The post-decode guards (`RepetitionGuard.Scrub`, `RegurgitationRecovery`,
      `SilenceHallucinationGate.Resolve`) are ruled out by construction — none can emit a partial
      transcript. Synthetic repro at his exact levels (TTS ×0.01–0.04, 120 Hz hum floor, trailing
      fade) did NOT reproduce the whole-file tail drop — whisper decoded everything — so the
      short-clip truncation mechanism still needs a REAL failing clip (see Residual).
    - **Fix 1 — streaming silent-chunk drop (code-certain hole; Windows divergence #2):**
      `StreamingTranscriptionSession.PollOnce` and `Finish()`'s drain loop dropped silent-classified
      chunks UNHEARD (`ChunkPlanner.IsSilent` = peak 0.3 s-window RMS < 0.005 — but David's real
      speech peaks 0.0005–0.005, so entire 15–25 s clauses could vanish from long dictations; the
      2026-06-23 bug-#2 fix protected only the FINAL tail). Now EVERY cut chunk is decoded and the
      MODEL decides: empty decode ⇒ confirmed silence, skipped losslessly (NOT a failure — that
      policy stays reserved for non-silent chunks); non-empty ⇒ rescued speech, appended; decode
      error ⇒ fail → whole-file fallback (invariant intact). On-device proof: a 43 s clip
      (loud 20 s + sub-floor quiet 20 s + loud coda) streams to the full text with
      `Stream chunk cut@242400: silent-classified but decoded 257 chars -> RESCUED` — the old code
      deleted that entire middle sentence.
    - **Fix 2 — tail-coverage guard (whole-file path):** new pure
      `JVoice.Core/Policy/TailCoverageGuard.cs` + wiring in
      `WhisperNetTranscriptionEngine.TranscribeAsync`. When the decode's LAST segment ends
      ≥ **1.5 s** (`MinUncoveredSeconds`) before the end of the audio — the early-EOT truncation
      fingerprint; the trigger is whisper's own timestamp coverage, never an RMS level (#21
      stands) — the uncovered tail alone is re-decoded (unprompted witness-style, fully reduced)
      and merged with a normalized-containment dedupe so a boundary word can never paste twice.
      A trailing thinking-pause decodes to empty and merges to nothing. On-device: fires with
      `uncovered=3.57s` on a digital-silence tail and merges nothing (no-harm), does NOT fire when
      whisper stretches the last segment across a hum tail (`lastEnd≈audio`), and stays quiet on
      covered decodes (whisper rounds lastEnd PAST the clip end: 6.32 s on 5.40 s audio).
    - **Instrumentation (one real occurrence now pinpoints the failing stage):** the engine logs
      every decode (`Engine decode prompt=… chars=… segs=… lastEnd=… audio=… rawRms=…`), the
      witness verdict (`Engine witness … -> kept|no-speech`), and the tail-guard decision
      (`Engine tailGuard … -> RECOVERED|unchanged`); `StreamingTranscriptionSession` gained an
      optional `log` callback (wired to `DiagnosticLog.Write`) reporting cuts, rescues, failures,
      and the finish path. Pure Core stays platform-free (callback injection).
    - **VERIFICATION:** `dotnet test` **733/733** (+3 StreamingSessionTests, +17
      TailCoverageGuardTests); x64 build 0 errors; on-device `--bench` sweep with his exact
      model/vocab: short-clip regression clean, tail-guard trigger + no-harm confirmed, streaming
      rescue confirmed.
    - **Residual (OPEN):** (a) whisper can still skip very quiet words INSIDE one decode when much
      louder speech follows (observed only in a −10 dB synthetic worst case); (b) the short-clip
      whole-file truncation ("please get this") is not yet reproducible synthetically. Both need a
      real failing clip: run David with **`JVOICE_KEEP_WAV=1`** until a cutoff strikes — the new
      logs + the kept WAV in `%APPDATA%\JVoice\capture\` then show exactly which stage lost the
      words (same calibration loop as #38). (c) The two half-audio capture outliers are unexplained.

40. **Biblical / God / Jesus capitalization — ALWAYS-ON pack (David-requested, 2026-07-08, branch
    `feat/biblical-terms`).** David asked that "every single term related to God and Jesus and popular
    Biblical terms that are supposed to be capitalized" be capitalized **automatically, with no toggle,
    in every mode**. Implemented as a new pure pack `JVoice.Core/Text/BiblicalTerms.cs` — same shape as
    `DeveloperTerms` (`Map` of lower-cased heard form → canonical capitalized value + `Augment`) — but
    wired in **UNCONDITIONALLY** at `VoiceCoordinator.cs` (one line right after the dev-pack toggle:
    `withPack = BiblicalTerms.Augment(withPack);`, NOT gated by any setting) and in `BenchRunner`.
    Because it flows through the existing post-processing correction channel it fires in **all four
    tones** — Casual/Formal/Code, and **Very Casual** (which lower-cases first, then corrections run
    after, so the capitals survive — test-locked).
    - **Curation:** intentionally more assertive than the conservative dev pack because David wants it
      aggressive — it DOES capitalize bare `god`→God and `lord`→Lord despite their lower-case common-noun
      senses ("a Greek god", "House of Lords"); the `\b…\b` matcher already shields compounds
      (godzilla/goddess/landlord/warlord never match). Kept terms: God, Lord, Jesus, Christ, Jesus Christ,
      Messiah, Yahweh, Jehovah, Emmanuel/Immanuel, Savior/Saviour, Redeemer, Holy Spirit/Ghost/Trinity,
      Trinity, Son/Lamb/Word/Kingdom of God, King of Kings, Prince of Peace, Almighty God, Bible/Holy
      Bible, Scripture(s), Gospel(s), Old/New Testament, Ten Commandments, Garden of Eden, Satan, Lucifer,
      Christian(s)/Christianity.
    - **Deliberate EXCLUSIONS (test-locked `Map_ExcludesDangerousWords`):** reverential pronouns
      (he/him/his/thee/thou/…) — would wreck every sentence; book names that collide with English/first
      names (numbers, acts, kings, judges, **job**, mark, john, luke, matthew, james, revelation, genesis,
      exodus) — "a job" alone makes the whole book category unsafe; bare abstractions/roles that are
      ordinary English or names (father, son, spirit, grace, faith, hope, cross, word, king, **creator**
      ["content creator"!], devil); and stylistically-optional words (heaven, hell, amen, hallelujah, holy,
      divine, blessed, sacred, bare almighty). Those stay reachable via the user's own custom-words /
      correction rules, which outrank this pack (`Augment` lays it in as the floor; `UserCorrections.Merge`
      and the builtin `CorrectionDictionary` still win). No schema/settings/UI change.
    - **VERIFICATION:** `dotnet build JVoice.sln -c Release` 0 errors; `dotnet test` **787/787** (~75 new
      `BiblicalTermsTests` covering map hygiene, value idempotence, all-four-tones capitalization, the
      exclusion list, compound-word safety, and layering with the dev/user/builtin stacks). NOT dogfooded
      live yet (the unit tests exercise the exact `TextProcessor.Process` path the coordinator uses); NOT
      pushed.

### Persistence paths (overview §4.9)
`%APPDATA%\JVoice\settings.json` (+ `settings.corrupt.bak`; **schemaVersion 4** — v2 added `gameMode`
(§7 #27); v3 added `copyToClipboardOnly`/`undoHotkey`/`translateToEnglish`/`appAwareModes`/`appModeRules`
(§7 #32); v4 added `checkForUpdates` (§7 #36)),
`stats.json`, `last-transcript.txt`, `transcript-history.json` (Recent Transcripts, §7 #26);
registry `HKCU\Software\JVoice` (`LaunchAtLoginInitialized`, `UiFirstRunShown`) + `HKCU\…\Run\JVoice`
(value now ends in `--autostart`, §7 #25); a Task Scheduler task **"JVoice Elevated Autostart"** when
"Run as Administrator at Login" is on (§7 #25); temp recordings `%TEMP%\jvoice-<guid>.wav` (swept on
launch); models `%LOCALAPPDATA%\JVoice\models\`.

---

## 8. What remains

> ✅ **The 2026-06-26 "elevated first-recording freeze" is FIXED (2026-07-02, §7 #37).** It was a
> capture-teardown deadlock in `NAudioRecorder` reachable on any stop — elevation was a coincidental
> first observation. The §7 #25 elevated path works again (verified live via the logon task); David's
> at-the-desk elevated dogfood tick (item 2 below) is the remaining confirmation. Forward-looking work
> beyond this list: `docs/windows-roadmap.md`.

1. **✅ Silence-hallucination gate — DONE 2026-07-02 (§7 #38).** The #24 plan was executed end-to-end:
   David recorded 13 real clips, `nospeech-probe --analyze` confirmed prompt-vs-no-prompt agreement as
   the discriminator (confidence measured INVERTED, as predicted), and the gate shipped as
   `Core/Policy/SilenceHallucinationGate` + a witness decode in `WhisperNetTranscriptionEngine`.
   17/17 clips verdict-correct through the real engine; 713/713 tests. See §7 #38.
1b. **Tail-cutoff hunt — catch the real clip (§7 #39, PRIORITY).** The streaming silent-chunk drop is
   fixed and the tail-coverage guard + full decode instrumentation shipped (branch `fix/tail-cutoff`),
   but the short-clip whole-file truncation ("please get this") is not reproducible synthetically.
   Refresh David's install with the `fix/tail-cutoff` build, set **`JVOICE_KEEP_WAV=1`** in his user
   env, and dictate normally until a cutoff strikes — then the `Engine decode …` log lines plus the
   kept WAV in `%APPDATA%\JVoice\capture\` identify the failing stage exactly (then delete the kept
   clips + unset the env var, privacy, as after #38). Also open: the two half-audio capture outliers
   (§7 #39 Evidence).
2. **Dogfood the GUI (David, interactive):** run `docs/launch/windows-dogfood-checklist.md` — the live
   Ctrl+Shift+Space → record → transcribe → paste loop, the new black-&-white HUD bars reacting to your
   voice (and the silent-success / error-only-text behaviour), the 640×846 two-column monochrome Settings round-trip,
   BT device routing, mic-permission flow, and the new **elevated-window** path (§7 #25: "Restart as
   Administrator" / "Run as Administrator at Login" → hotkey works in an admin terminal). The app is confirmed to *launch* and the
   HUD/Settings look is screenshot-verified via `--hud-preview`/`--settings-render`; live-mic reactivity is
   what a person at the desk must confirm. The elevated path is unblocked again by §7 #37 (the freeze is
   fixed; scripted elevated loops pass) — the at-the-desk admin-terminal round-trip is the remaining tick.
   **New:** the **game-detection** gaming section (§7 #27) — with
   `JVoice.exe --game-probe` running, alt-tab into real games (Valorant/Fortnite/GTA/Minecraft) and confirm the
   hotkey suppresses + passes through, then confirm fullscreen **video** does NOT suppress (Balanced).
3. **(Optional) Phase 5 Task 6** — port `scripts/verify-transcription.py` to
   `windows/tools/verify-transcription` (corpus-level word-retention / spurious-vocab scoring across
   many generated clips). `whisper-smoke` + `--bench` already prove end-to-end transcription; this is the
   larger scripted accuracy harness.
4. **(Optional) Phase 5 Task 3** — an Inno Setup installer (`windows/installer/JVoice.iss`). The zipped
   self-contained folder is already a complete distributable, so this is convenience only (and needs
   Inno Setup installed to compile).
5. **Polish from dogfooding:** the HUD shape has been tuned over several same-day iterations, and the recording bars are
   now a continuous, mic-independent wave (#18, #22, #23; no mic meter) — further tweaks are by-eye taste (constants at the top of
   `HudView.xaml.cs`). The Settings scrollbar is now monochrome (done, commit `990ba76`). (The old
   "waveform glyph" / "per-section accent" / "default-grey scrollbar" polish items are obsolete — #18/#22.)
6. **(Follow-ups) Developer-terms pack (§7 #28)** — **merge `feat/developer-terms` → `windows-port`** once that
   branch's base builds `JVoice.App` (blocked on a different session committing `PlatformPaths.cs`, §7 #28). Then the
   optional next slices: a "learn from my fixes" suggester (reuse `TextProcessor.ExtractCorrections`), categorized
   packs (Web/Python/DevOps…), and porting `JVoice.Core/Text/DeveloperTerms.cs` 1:1 to the macOS app. Curating the
   word list further (add/remove terms; the one name-collision risk is `jason`→`JSON`) is by-eye taste.
7. **Do NOT publish/push** without David's explicit go-ahead.

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
