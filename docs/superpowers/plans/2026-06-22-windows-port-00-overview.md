# JVoice for Windows — Port Master Plan (Overview & Decisions)

> **For agentic workers:** This is the **anchor document** for the JVoice Windows port. It defines the goal, the architecture, every canonical name (projects, namespaces, types, file paths), the global constraints, and the phase index. Each phase has its own self-contained plan file (`2026-06-22-windows-port-0N-*.md`). **Read this overview in full before executing any phase.** Phases are designed to be executed in order; each produces working, testable software on its own.
>
> REQUIRED SUB-SKILL for execution: `superpowers:subagent-driven-development` (recommended — fresh subagent per task, review between) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax.

---

## 0. TL;DR

We are porting **JVoice** — a macOS menu-bar voice-dictation app (press a hotkey → record → on-device Whisper transcription → tone-styled text pasted into the frontmost app) — to a **native Windows desktop app** that looks and behaves like the macOS original.

- **Language/runtime:** C# on **.NET 9**, **WPF** for the UI (`WinExe`, win-x64).
- **Speech engine:** **Whisper.net** (managed bindings to **whisper.cpp**), GGML models, with **CUDA** GPU acceleration (this dev machine has an RTX 3060 Ti) and a **CPU** fallback. This replaces macOS-only WhisperKit/CoreML.
- **The accuracy "brain" is ported faithfully** — the text processing, phonetic correction, vocabulary biasing, regurgitation recovery, repetition guard, and streaming chunk logic are all model-agnostic pure logic and carry over 1:1 (with their tests).
- **The UI is recreated faithfully** in WPF from the exact design tokens in `docs/demo-video/DESIGN-TOKENS.md`: a system-tray app with the same black-squircle "J" logo, the floating HUD pill (recording / preparing / transcribing / done / error), and the dark 320×520 settings panel.
- **Audio, global hotkey, paste, launch-at-login** are reimplemented on Win32/WASAPI.

The existing **Swift macOS app stays in this repo untouched** as the reference implementation and the source of truth for the brain's algorithms and invariants.

---

## 1. Context: what JVoice is and how it works today (macOS)

**Read this if you have never seen the macOS app.** JVoice is a Swift Package Manager executable (`Package.swift`, Swift 5.9, macOS 14+) living under `Sources/JVoice/`. It is an accessory app (`LSUIElement = true`): no Dock icon, just a menu-bar status item plus transient floating windows.

End-to-end flow (the "dictation pipeline"), implemented by `Sources/JVoice/VoiceCoordinator.swift`:

1. User presses the global hotkey (default ⌥Space on macOS).
2. `RecordingManager` records microphone audio to a temp WAV (**16 kHz, mono, 16-bit PCM, little-endian**).
3. While recording, a **streaming** overlay (`StreamingTranscriptionSession` + `WavTail` + `ChunkPlanner`) transcribes completed silence-delimited chunks of the still-growing WAV, so on stop only the tail remains.
4. User presses the hotkey again to stop. The audio is transcribed by the Whisper engine (`TranscriptionManager` → `WhisperKitTranscriptionEngine` on macOS).
5. The raw transcript is post-processed (`TextProcessor`: tone styles, filler-word removal, custom-word corrections; `PhoneticMatcher`: fuzzy sound-alike correction) and pasted into the previously-frontmost app via a synthesized Cmd+V (`PasteManager`).
6. A HUD "pill" shows state throughout (recording / preparing model / transcribing / pasted / error); the menu-bar icon mirrors it.

**The accuracy work is layered and is the product's real IP:**
- `VocabularyPrompt` builds an `initial_prompt`-style decoder conditioning string from the user's custom words (the main accuracy lever — gets "Li-Fraumeni", "VS Code" right at the source).
- `RepetitionGuard` detects and strips "prompt regurgitation" (the decoder reciting the vocab list in low-confidence regions / on silence).
- `RegurgitationRecovery` re-decodes the same audio **without** the prompt only when a decode regurgitated or came back empty — keeping prompt accuracy in the common case while making the failure mode unreachable.
- `PhoneticMatcher` (simplified-Metaphone key + bounded Levenshtein) catches mishearings post-hoc ("jay voice" → "JVoice").
- `TextProcessor` applies tone styles, filler removal, exact custom-word corrections, and strips decoder artifacts/hallucination sentinels.

**Settings (in the 320×520 dark panel):** keyboard shortcut, language (English / Romanian), voice style (Casual / Formal / Very Casual), remove-filler-words toggle, Whisper model (Tiny / Base / Small / Large), custom words, last-transcript editor, lifetime stats (total words + avg WPM).

The exhaustive behavioral specs of every component are embedded in the phase docs. The Swift source is the final authority — phase docs cite exact file:line.

---

## 2. Why a port (not a recompile) and why this stack

### 2.1 The core constraint: WhisperKit is Apple-only

JVoice's speech engine is **WhisperKit**, which runs Whisper models as **CoreML** on the Apple Neural Engine / GPU. CoreML, WhisperKit, AVFoundation, AppKit, SwiftUI, and `SMAppService` are all macOS-only frameworks. The "very well optimized (fast and accurate)" Whisper is *WhisperKit's CoreML optimization* — that specific optimization does not exist on Windows. So the engine must be **replaced**, not recompiled.

Crucially, **the optimization that matters for accuracy is not the CoreML kernel** — it is the surrounding brain (vocabulary prompt biasing, regurgitation recovery, phonetic matching, chunk planning). Those are model-agnostic and port to *any* Whisper backend that exposes an `initial_prompt` and runs the same model weights. So we keep the accuracy and swap the inference engine.

### 2.2 Chosen Whisper backend: whisper.cpp via Whisper.net

**whisper.cpp** is the de-facto on-device Whisper runtime: same OpenAI Whisper models (as GGML/GGUF files), highly optimized, with CPU (AVX/AVX2), **CUDA** (NVIDIA), **Vulkan** (any GPU), and OpenVINO backends. It exposes exactly what the brain needs:
- `initial_prompt` / `prompt_tokens` → our `VocabularyPrompt`.
- `language` selection → our `TranscriptionLanguage`.
- `suppress_blank` (default **on** in whisper.cpp) and `suppress_nst` (non-speech tokens) → makes the WhisperKit-specific `SuppressBlankFilter` workaround **unnecessary** (see §6.3).
- Processing of raw `float[]` PCM arrays → our streaming `ChunkPlanner` chunks.

**Whisper.net** is the mature, actively-maintained managed (.NET) binding to whisper.cpp. It exposes `WhisperFactory` / `WhisperProcessorBuilder` with `.WithLanguage(...)`, `.WithPrompt(...)`, `.WithoutTimestamps()`, temperature/entropy controls, and segment streaming. Runtime native binaries ship as separate NuGet packages (`Whisper.net.Runtime` for CPU, `Whisper.net.Runtime.Cuda` for NVIDIA, `Whisper.net.Runtime.Vulkan` for cross-GPU). This dev machine (**RTX 3060 Ti**, CUDA-capable; **i5-12400**, AVX2) gets GPU acceleration; the CPU runtime is the universal fallback.

### 2.3 Chosen UI stack: WPF

Requirements from the user: a "native windows app", an "actual app UI", the "same typa logo", and a UI that "matches the macbook type of UI" (the dark, rounded, glowing, translucent aesthetic).

**WPF on .NET 9** is the pick because:
- Genuinely native (no Chromium/Electron), small footprint, single process.
- Total control over custom window chrome: borderless always-on-top non-activating overlay windows (the HUD pill), per-monitor DPI, transparency, drop shadows and glows, custom-shaped controls — everything the macOS pills and dark panel need.
- First-class system tray (`H.NotifyIcon.Wpf`) and Win32 interop (global hotkey, SendInput paste, foreground-window tracking, acrylic backdrop).
- Mature for tray-plus-overlay utility apps; the macOS app's menu-bar-plus-floating-HUD model maps directly.

### 2.4 Rejected alternatives (decisions, with rationale)

| Option | Why rejected |
| --- | --- |
| **Swift on Windows** (recompile) | The Swift *language* runs on Windows, but the entire UI (SwiftUI/AppKit), audio (AVFoundation), ML (WhisperKit/CoreML), and login-item (`SMAppService`) layers are Apple-only with no Windows equivalents. It would be a rewrite of everything except pure-Foundation logic, in an ecosystem with essentially no Windows GUI story. Worst of both worlds. |
| **WinUI 3 / Windows App SDK** | Modern Fluent stack with built-in Mica/Acrylic, but rough edges exactly where this app lives: borderless click-through always-on-top overlays, tray icons, and unpackaged single-file deployment all fight the framework (it strongly prefers MSIX/packaged identity, which complicates the global-hotkey overlay and the simple "download and run" story). WPF is more battle-tested for tray+overlay utilities. Revisit only if a future main-window redesign wants Fluent controls. |
| **Tauri (Rust + web UI)** | Smallest binary and the existing Remotion/React UI (`docs/demo-video/src/`) could seed a pixel-faithful web frontend. But the audio/hotkey/paste/Bluetooth-routing glue is more niche in Rust, GPU-accelerated whisper-rs setup is fiddlier than Whisper.net's runtime packages, and it adds a JS+Rust toolchain. Strong runner-up; chosen against for engine ergonomics and "native" feel. |
| **Electron** | Easiest UI reuse but the least "native", heaviest (~150 MB Chromium), and the user explicitly asked for a *native* app. Rejected. |
| **Python (faster-whisper) + a GUI** | Great engine (CTranslate2) but Python desktop packaging and a native-feeling custom UI are both painful; not "native". Rejected. |
| **DirectML / ONNX Runtime Whisper** | Viable GPU path, but more plumbing than Whisper.net and no ready `initial_prompt`/streaming ergonomics. Whisper.net wraps the better-trodden whisper.cpp. Rejected for now. |

### 2.5 GGML model mapping

whisper.cpp uses GGML model files downloaded from Hugging Face (`ggerganov/whisper.cpp`). Map JVoice's four options to GGML files (quantized where it preserves the ~size/accuracy tradeoff):

| JVoice model (`WhisperModelOption`) | UI label | GGML file | Approx size | Notes |
| --- | --- | --- | --- | --- |
| `Tiny` | "Tiny" | `ggml-tiny.bin` | ~75 MB | fastest, least accurate |
| `Base` | "Base" | `ggml-base.bin` | ~142 MB | balanced |
| `Small` | "Small" | `ggml-small.bin` | ~466 MB | more accurate |
| `LargeTurbo` | "Large" | `ggml-large-v3-turbo-q5_0.bin` | ~547 MB | quantized large-v3-turbo; closest match to macOS JVoice's ~630 MB turbo build; 4-layer decoder, fast |

Models are downloaded on first use (mirroring macOS JVoice's first-run Hugging Face download) to `%LOCALAPPDATA%\JVoice\models\`, with a download-progress HUD state. URLs and SHA-256 checksums are pinned in Phase 2. English-only `.en` variants are deliberately **not** offered (JVoice supports Romanian; multilingual models are required).

---

## 3. Repository structure (what gets created)

The macOS Swift app is **kept as-is** (reference). The Windows app is added under a new top-level `windows/` directory containing a single .NET solution.

```
JVoice-Windows/                      (repo root — git remote: david53001/jvoice, branch main)
├── Sources/JVoice/ ...              UNCHANGED — macOS Swift app (reference / brain source-of-truth)
├── Tests/JVoiceTests/ ...           UNCHANGED — Swift tests (encode the brain invariants we re-translate)
├── Package.swift, Resources/, ...   UNCHANGED
├── docs/
│   ├── demo-video/DESIGN-TOKENS.md  UNCHANGED — exact UI tokens (authoritative for the WPF UI)
│   ├── HANDOFF.md                   UNCHANGED (macOS handoff)
│   ├── HANDOFF-WINDOWS.md           NEW — Windows port session state / decisions log
│   └── superpowers/plans/
│       ├── 2026-06-22-windows-port-00-overview.md     (this file)
│       ├── 2026-06-22-windows-port-01-core-brain.md
│       ├── 2026-06-22-windows-port-02-whisper-engine.md
│       ├── 2026-06-22-windows-port-03-platform.md
│       ├── 2026-06-22-windows-port-04-ui.md
│       └── 2026-06-22-windows-port-05-packaging.md
└── windows/                         NEW — the entire Windows app
    ├── JVoice.sln
    ├── Directory.Build.props         shared MSBuild props (LangVersion, Nullable, version)
    ├── .editorconfig
    ├── JVoice.Core/                  net9.0 class library — PURE logic, no UI, no native deps
    │   ├── JVoice.Core.csproj
    │   ├── Models/                   AppMode, ToneStyle, WhisperModelOption, TranscriptionLanguage,
    │   │                             SettingsState, HudState
    │   ├── Text/                     TextProcessor, PhoneticMatcher, VocabularyPrompt,
    │   │                             RepetitionGuard, RegurgitationRecovery
    │   ├── Audio/                    WavTail (WavInfo + WavTailReader), ChunkPlanner,
    │   │                             StreamingTranscriptionSession
    │   └── Transcription/            ITranscriptionEngine, TranscriptionException,
    │                                 FileBackedTranscriptionEngine
    ├── JVoice.App/                   net9.0-windows WPF WinExe — engine wiring, platform, UI
    │   ├── JVoice.App.csproj
    │   ├── Whisper/                  WhisperNetTranscriptionEngine, WhisperModelStore (download/locate)
    │   ├── Platform/                 AudioRecorder, AudioInputRouter, GlobalHotkey, Paster,
    │   │                             ForegroundWindowTracker, LaunchAtLogin, SettingsStore,
    │   │                             StatsStore, LastTranscriptStore, SingleInstance, SettingsUris
    │   ├── UI/                       HudWindow + HudView (pills), SettingsWindow + SettingsView,
    │   │                             TrayIcon, controls, styles (JVoicePalette.xaml)
    │   ├── VoiceCoordinator.cs       the orchestrator (port of VoiceCoordinator.swift)
    │   ├── App.xaml / App.xaml.cs    WPF entry, single-instance, DI wiring
    │   ├── app.manifest              DPI awareness, no UAC elevation
    │   ├── Assets/                   JVoice.ico (the squircle "J"), tray PNGs
    │   └── AppUserModelId            "com.jvoice.app" (toast/taskbar grouping)
    ├── JVoice.Tests/                 net9.0 xUnit — references JVoice.Core
    │   ├── JVoice.Tests.csproj
    │   └── *Tests.cs                 translated from Tests/JVoiceTests/*.swift
    └── tools/
        ├── generate-icon/            C# console app: draws JVoice.ico (port of generate-icon.swift)
        └── verify-transcription/     end-to-end accuracy harness (port of verify-transcription.py)
```

**Why `JVoice.Core` is a separate pure library:** it has zero UI, zero Win32, zero Whisper.net dependencies, so (a) it compiles and unit-tests on any platform / on CI without native whisper binaries, and (b) the accuracy invariants are locked by `JVoice.Tests` independent of the engine. This mirrors the Swift design where the brain depends only on Foundation.

---

## 4. Canonical names (single source of truth — phases MUST match these exactly)

Type/method/file names are fixed here so the independently-executed phase plans interlock. If a phase doc and this table disagree, **this table wins** — fix the phase doc.

### 4.1 Namespaces
- `JVoice.Core.Models`, `JVoice.Core.Text`, `JVoice.Core.Audio`, `JVoice.Core.Transcription`
- `JVoice.App`, `JVoice.App.Whisper`, `JVoice.App.Platform`, `JVoice.App.UI`

### 4.2 Core models (Phase 1)
- `enum ToneStyle { Casual, Formal, VeryCasual }` (ports Swift `AppMode`/`ToneMode`; `DisplayName` → "Casual"/"Formal"/"Very Casual").
- `enum TranscriptionLanguage { English, Romanian }` with `string WhisperCode` ("en"/"ro") and `string DisplayName`.
- `enum WhisperModelOption { Tiny, Base, Small, LargeTurbo }` with `string DisplayName` (LargeTurbo → "Large"), `string GgmlFileName`, `string Guidance`.
- `record SettingsState` with `int SchemaVersion`, `ToneStyle Mode`, `WhisperModelOption Model`, `TranscriptionLanguage Language`, `IReadOnlyList<string> CustomWords`, `bool RemoveFillerWords`. Defaults: `Mode=Casual, Model=Tiny, Language=English, CustomWords=[], RemoveFillerWords=true, SchemaVersion=1`.
- `enum HudStateKind { Idle, Recording, PreparingModel, DownloadingModel, Transcribing, Done, Error }` plus a `readonly record struct HudState` carrying kind + optional payload string + optional progress double. (`DownloadingModel` is **new** for Windows — macOS bundled the download into "preparing"; we surface download progress explicitly.)

### 4.3 Core text brain (Phase 1) — static classes mirroring the Swift enums/structs
- `static class TextProcessor` — `Process(string, ToneStyle, IReadOnlyDictionary<string,string> extraDictionary, bool removeFillerWords, IReadOnlyList<string> vocabulary)`, `ApplyCorrections`, `BuildUserDictionary`, `ExtractCorrections`, `SpokenVariants`, `Format`, `RemoveDisfluencies`, `StripDecoderArtifacts`, `RemoveWhisperHallucinations`, plus `CorrectionDictionary`.
- `static class PhoneticMatcher` — `Correct(string text, IReadOnlyList<string> vocabulary)`, `PhoneticKey(string)`, `Levenshtein(string a, string b, int limit)`.
- `static class VocabularyPrompt` — `const int MaxWords = 40`, `const int MaxPromptTokens = 96`, `string? Text(IReadOnlyList<string> words)`.
- `static class RepetitionGuard` — `Scrub(string, IReadOnlyList<string>) -> ScrubResult { string Text; bool RemovedRegurgitation }`, `Strip(...)`, plus the tuning constants.
- `static class RegurgitationRecovery` — `Task<string> Decode(bool useVocabularyPrompt, IReadOnlyList<string> vocabulary, Func<bool, Task<string>> decode)`.

### 4.4 Core audio (Phase 1)
- `readonly record struct WavInfo(int DataOffset, int SampleRate, int Channels, int BytesPerSample)`.
- `static class WavTail` — `const int HeaderProbeBytes = 16384`, `WavInfo? ParseHeader(ReadOnlySpan<byte>)`, `float[] FloatSamples(ReadOnlySpan<short>)`.
- `sealed class WavTailReader` — `static WavTailReader? Open(string path)`, `short[]? Samples(int sampleOffset)`, props `Path`, `Info`.
- `static class ChunkPlanner` — nested `Config` (with the exact constants), `abstract`/struct `Decision` (`Wait` | `Cut(int AtSample, bool IsSilent)`), `Decision Plan(IReadOnlyList<short> unconsumed, Config config)`, `bool IsSilent(IReadOnlyList<short>, Config)`.
- `sealed class StreamingTranscriptionSession` — ctor `(Func<float[], Task<string>> transcribe, ChunkPlanner.Config config, int pollMilliseconds)`, methods `Start(string path)`, `Task<string?> Finish()`, `Task Cancel()`.

### 4.5 Core transcription abstraction (Phase 1)
- `interface ITranscriptionEngine` — `Task<string> TranscribeAsync(string audioPath, CancellationToken ct)`, `Task PrewarmAsync()`, `Task UpdateVocabularyAsync(IReadOnlyList<string> words)`, `Task<bool> IsReadyAsync()`, `Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()`. (Default no-op behaviors via a base or default-interface methods.)
- `class TranscriptionException : Exception` with factory cases (AudioFileMissing, UnsupportedAudioFile, EmptyTranscript, ModelLoadFailed).
- `sealed class FileBackedTranscriptionEngine : ITranscriptionEngine` (test/no-whisper fallback — reads a UTF-8 text "audio" file; used by Core tests).

### 4.6 App engine (Phase 2)
- `sealed class WhisperNetTranscriptionEngine : ITranscriptionEngine` (in `JVoice.App.Whisper`).
- `sealed class WhisperModelStore` — locate/download GGML models; `string? CompleteModelPath(WhisperModelOption)`, `Task DownloadAsync(WhisperModelOption, IProgress<double>, CancellationToken)`, `string ModelsDirectory`.

### 4.7 App platform (Phase 3) — interfaces + Win32 impls
- `interface IAudioRecorder` / `sealed class NAudioRecorder` — `bool TryStart(out string? error)`, `string? Stop()`, `string? CurrentPath`, `Task<bool> RequestPermissionAsync()`, plus `static void SweepOrphanedRecordings()`, `static bool IsUsableRecording(string path, int minBytes = 1024)`.
- `static class AudioInputRouter` — choose a non-Bluetooth capture endpoint (the Windows analog of the macOS A2DP-preservation routing).
- `sealed class GlobalHotkey` — low-level keyboard hook; `event Action Triggered`; `Register(HotkeyChord)`, `Unregister()`; 150 ms debounce; default chord **Ctrl+Shift+Space**.
- `sealed class Paster` — `PasteOutcome Paste(string text, IntPtr targetHwnd)`; enum `PasteOutcome { Ok, AccessDenied, ClipboardLocked, TargetRejected }`; clipboard save/restore with the 300 ms restore delay.
- `sealed class ForegroundWindowTracker` — tracks the last non-self foreground HWND (analog of `lastNonSelfFrontmostPID`).
- `static class LaunchAtLogin` — `bool IsEnabled { get; }`, `void SetEnabled(bool)`, `void PerformFirstRunEnableIfNeeded()` (registry Run key).
- `sealed class SettingsStore`, `sealed class StatsStore`, `sealed class LastTranscriptStore` — JSON persistence under `%APPDATA%\JVoice\`.
- `static class SettingsUris` — `ms-settings:` deep links.
- `static class SingleInstance` — named `Mutex`.

### 4.8 App UI + coordinator (Phase 4)
- `sealed class VoiceCoordinator` — the orchestrator (port of `VoiceCoordinator.swift`); exposes observable state for the views (INotifyPropertyChanged or a small reactive store).
- `sealed class HudWindow : Window` + `HudView` user control (pills).
- `sealed class SettingsWindow : Window` + `SettingsView` user control.
- `sealed class TrayIcon` (wraps `H.NotifyIcon.Wpf` `TaskbarIcon`).
- `static class JVoicePalette` (or a merged `ResourceDictionary`) — all colors as `Color`/`SolidColorBrush` resources.

### 4.9 Persistence keys / paths (mirror macOS where it aids portability)
- Settings file: `%APPDATA%\JVoice\settings.json`
- Stats file: `%APPDATA%\JVoice\stats.json` (`{ "totalWords": int, "totalSeconds": double }`)
- Last transcript: `%APPDATA%\JVoice\last-transcript.txt`
- Launch-at-login init flag: registry `HKCU\Software\JVoice` value `LaunchAtLoginInitialized` (REG_DWORD)
- Launch-at-login Run entry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value `JVoice` = `"<exe path>"`
- AX-prompt-once analog: not needed (Windows has no per-app accessibility gate for SendInput; see §6.4)
- Models cache: `%LOCALAPPDATA%\JVoice\models\<ggml file>`
- Temp recordings: `%TEMP%\jvoice-<guid>.wav` (sweep pattern `jvoice-*.wav`)

---

## 5. Global Constraints (every task implicitly includes these)

- **.NET 9** (`net9.0` for Core/Tests, `net9.0-windows` for App). C# latest (`<LangVersion>latest</LangVersion>`), `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`. Primary RID **win-x64**; the build must also be parameterizable for `win-arm64` (CUDA is x64-only — arm64 = CPU runtime).
- **Dependencies (NuGet), pinned to exact versions in each csproj** (resolve the current stable version at execution time and pin it):
  - `Whisper.net`, `Whisper.net.Runtime` (CPU), `Whisper.net.Runtime.Cuda` (NVIDIA GPU). Optionally `Whisper.net.Runtime.Vulkan` for non-NVIDIA GPUs (Phase 2 decides whether to bundle).
  - `NAudio` (audio capture + WAV writing).
  - `H.NotifyIcon.Wpf` (system tray for WPF).
  - `System.Text.Json` (in-box) for persistence.
  - xUnit + `xunit.runner.visualstudio` + `Microsoft.NET.Test.Sdk` for `JVoice.Tests`.
- **License compatibility:** repo is **GPL-3.0**. Every dependency must be GPL-compatible. Verified compatible: whisper.cpp (MIT), Whisper.net (MIT), NAudio (MIT), H.NotifyIcon (MIT), GGML models (MIT/Whisper license). Re-verify at execution time; reject any GPL-incompatible dep.
- **Privacy (a product promise — do not break it):** zero network calls at runtime **except** the one-time GGML model download from Hugging Face. No telemetry, no analytics, no accounts. Raw audio WAVs are deleted after transcription and swept on launch (never orphaned). No transcript or audio leaves the machine.
- **Naming / copy:** product name is **"JVoice"** everywhere. App icon is the **black-squircle "J"** (geometry in Phase 4 §icon). The settings panel header is "JVoice" + subtitle "Menu bar transcription controls" → reword to **"Voice dictation controls"** on Windows (no menu bar; see Phase 4). Keep all other user-facing strings identical to macOS unless a string names a macOS-only concept (⌥Space, "menu bar", "System Settings") — those are re-expressed for Windows and listed in Phase 4 §copy-deltas.
- **Hotkey default:** **Ctrl+Shift+Space** (macOS ⌥Space is unavailable: Alt+Space opens the Windows window menu). User-rebindable via a hotkey recorder in Settings. 150 ms debounce preserved.
- **$0 budget:** no paid code-signing certificate. Distribute an unsigned self-contained single-file `.exe` (+ optional Inno Setup installer). Document the **SmartScreen "More info → Run anyway"** flow (the Windows analog of macOS Gatekeeper "Open Anyway"). No paid services.
- **Do NOT publish / push / open PRs / create remotes.** The repo's `CLAUDE.md` rule stands: publishing is on hold pending David's explicit go-ahead. Commit locally on a branch only.
- **Do NOT modify the macOS Swift app** (`Sources/JVoice/`, `Tests/JVoiceTests/`, `Package.swift`, `Resources/`). It is the reference. Treat it like the `../MacOSUtils` rule: read-only.
- **The brain ports faithfully.** Where a Swift algorithm exists (TextProcessor, PhoneticMatcher, RepetitionGuard, ChunkPlanner, WavTail, RegurgitationRecovery, StreamingTranscriptionSession, VocabularyPrompt), the C# must reproduce it line-for-line in behavior, preserving every constant verbatim, and the translated tests must pass. No "improvements" to the algorithm during the port.

---

## 6. Cross-cutting design notes & gotchas (read before any phase)

### 6.1 Concurrency model
Swift uses actors (`WhisperKitTranscriptionEngine`, `StreamingTranscriptionSession`) and `@MainActor`. In C#:
- The streaming session and engine guard their state with an `async` lock (`SemaphoreSlim(1,1)`) or a single-threaded `Channel`/`ConcurrentQueue` consumer — the goal is the same *serial-access* guarantee the Swift actor gives. The streaming session's finish-once / cancel-join contracts (Phase 1 §StreamingTranscriptionSession) must be preserved exactly.
- WPF UI updates marshal to the dispatcher (`Dispatcher.Invoke`/`InvokeAsync`) — this is the `@MainActor` analog. `VoiceCoordinator` raises events on the UI thread.
- The "recordingGeneration" guard (a stale streaming session from recording N must never attach to recording N+1) ports verbatim as an `int _recordingGeneration` checked after each `await`.

### 6.2 macOS units → .NET units
- Swift `TimeInterval` (seconds, double) and nanosecond `Task.sleep` → .NET `TimeSpan` / millisecond `Task.Delay`. Convert: `pasteRestoreDelay = 0.30 s = 300 ms`, `pasteActivationDelay = 0.08 s = 80 ms`, hotkey debounce `0.15 s = 150 ms`, settings debounce `0.5 s = 500 ms`, streaming poll `1_000_000_000 ns = 1000 ms`, HUD reset default `1_000_000_000 ns = 1000 ms`, error HUD `3_000_000_000 ns = 3000 ms`.
- Audio samples: Swift `Int16`/`Float` ↔ C# `short`/`float`; the `/ 32768.0` PCM normalization is identical.

### 6.3 whisper.cpp ≠ WhisperKit — what changes in the engine port
Two WhisperKit-1.0.0-specific workarounds in the Swift engine are **NOT needed** on whisper.cpp and must **not** be ported into the engine (the surrounding brain stays):
- **`SuppressBlankFilter` / `installPromptCompatibilityFilter`** — this fixed a WhisperKit bug where a `<|startofprev|>` prompt made the model emit `<|endoftext|>` as the first content token (empty transcript). whisper.cpp ships `suppress_blank = true` by default (suppresses blank at `sample_begin` like reference Whisper), so the empty-decode trap does not occur. Do not reimplement the filter. **Verify** empirically in Phase 2 (the `--no-prompt` A/B and a vocab clip) that a prompted decode is non-empty.
- **Duration-gated `withoutTimestamps` / single-window 25 s trap** — WhisperKit 1.0.0 truncated multi-window transcripts when timestamps were off. whisper.cpp handles long audio with its own 30 s windowing and context carry; it does not truncate with `WithoutTimestamps()`. Phase 2 decides per-path timestamp usage on its own merits (default: keep timestamps off for speed on the whole-file path too, but **verify** no truncation on a >30 s clip before locking it).

What **does** port (model-agnostic, keep all of it): `VocabularyPrompt` (→ `WithPrompt`), `RepetitionGuard`, `RegurgitationRecovery` (prompt regurgitation happens on any Whisper given an `initial_prompt` of a comma list), `ChunkPlanner`, `StreamingTranscriptionSession`, `PhoneticMatcher`, `TextProcessor`.

### 6.4 Windows permissions vs macOS TCC
- **Microphone:** Windows has a privacy gate (`Settings → Privacy & security → Microphone → Let desktop apps access your microphone`). A denied mic surfaces as a capture failure; map it to a "microphone access denied" HUD error that deep-links to `ms-settings:privacy-microphone` (analog of macOS `PermissionError.microphoneDenied`).
- **Accessibility / paste:** Windows needs **no special permission** to `SendInput` Ctrl+V into another app — *except* the target-process integrity rule: a non-elevated process cannot send input to an elevated (admin) window (UIPI). JVoice ships non-elevated (`app.manifest` `asInvoker`). Document this limitation (can't paste into an elevated app like an admin terminal) instead of requesting elevation. There is no per-app accessibility prompt to replicate — the macOS `AXIsProcessTrusted` checks and the `didPromptAXOnLaunch` flag simply have no Windows equivalent and are dropped.
- **Launch at login:** registry Run key — no permission needed.

### 6.5 "Actual app UI" interpretation
The macOS app is menu-bar-only. The user asked for "an actual app UI". Decision: keep the **tray-first** model (faithful to the original; a dictation tool should not hog the taskbar), but:
- The **Settings window is a real, focusable app window** with proper chrome and a taskbar button while open (`ShowInTaskbar = true` only while shown), reachable from the tray menu and from first-run.
- On **first launch**, show the Settings window once (so the app isn't invisible) with a short "JVoice is running in your system tray — press Ctrl+Shift+Space to dictate" affordance. Subsequent launches start silently to the tray.
- The HUD pill remains the floating overlay. This satisfies "actual app UI" while staying faithful to the macOS product. (If David later wants a larger always-visible main window, that is a post-port enhancement, noted in Phase 4 §future.)

### 6.6 Testing strategy (TDD, per global rules)
- `JVoice.Core` is fully unit-tested by `JVoice.Tests` (xUnit). Every Swift test in `Tests/JVoiceTests/` that targets a ported brain component is **translated** to xUnit with the same assertions and the same vectors (Phase 1 enumerates them). The 120-case RepetitionGuard fuzz and the streaming data-loss scenarios port too.
- The Whisper engine and platform interop are harder to unit-test; they get (a) a thin DI seam so the coordinator is testable with `FileBackedTranscriptionEngine`, and (b) a manual/scripted verification harness (`tools/verify-transcription`, port of `verify-transcription.py`) plus a dogfood checklist.
- **Verification gates** are spelled out per task (exact `dotnet test` / `dotnet run` commands + expected output). Never claim done without running them.

### 6.7 Build/run commands (reference)
- Build all: `dotnet build windows/JVoice.sln -c Release`
- Test: `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj`
- Run the app (dev): `dotnet run --project windows/JVoice.App` (or F5 in VS / `dotnet run -c Release`)
- Publish single-file: `dotnet publish windows/JVoice.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true` (Phase 5 finalizes the flags).

---

## 7. Phase index (execution order)

Each phase is a self-contained plan file. Execute in order; each ends green and testable.

| Phase | File | Deliverable | Depends on |
| --- | --- | --- | --- |
| **1 — Core brain** | `…-01-core-brain.md` | `JVoice.Core` library + `JVoice.Tests` all green: models, full text/phonetic/vocab/regurgitation brain, WAV reader, chunk planner, streaming session, transcription interface + file-backed engine. The accuracy IP, ported and locked by tests. | solution skeleton (Phase 1 task 1) |
| **2 — Whisper engine** | `…-02-whisper-engine.md` | `WhisperNetTranscriptionEngine` + `WhisperModelStore` (GGML download/locate, CUDA+CPU runtime, prompt biasing, streaming integration). End-to-end transcription of a WAV from the command line/test harness. | Phase 1 |
| **3 — Platform services** | `…-03-platform.md` | Audio capture (16 kHz mono PCM, growing WAV, orphan sweep, BT-safe device pick), global hotkey, paste, foreground tracking, launch-at-login, JSON persistence (settings/stats/last-transcript), single instance, settings deep-links. | Phase 1 |
| **4 — WPF UI + coordinator** | `…-04-ui.md` | The full app: tray icon (the "J" logo) + menu, HUD pill window (all states + orbital-ring animation), 320×520 settings panel (exact tokens), `VoiceCoordinator` wiring the whole pipeline, `App.xaml`, the generated `.ico`. The app runs and dictates. | Phases 1–3 |
| **5 — Packaging, distribution, docs, CI** | `…-05-packaging.md` | Single-file publish, optional Inno Setup installer, SmartScreen docs, GitHub Actions Windows CI (build + `dotnet test`), README/CLAUDE.md updates, verify-transcription harness, dogfood checklist. | Phase 4 |

**Definition of done for the whole port:** the app launches to the tray with the "J" icon; Ctrl+Shift+Space records; speech is transcribed on-device via whisper.cpp (GPU when available) with custom-word accuracy; styled text is pasted into the focused app; the HUD and settings panel match the macOS look; `dotnet test` is green; a self-contained `.exe` is produced; docs describe install + the SmartScreen step. No network calls except first-run model download.

---

## 8. Self-review (spec coverage map)

Every macOS component maps to a Windows task. Gaps would be plan failures.

| macOS component | Windows home | Phase |
| --- | --- | --- |
| `Models/AppMode`, `ToneMode` | `ToneStyle` | 1 |
| `Models/TranscriptionLanguage` | `TranscriptionLanguage` | 1 |
| `Models/WhisperModelOption` | `WhisperModelOption` (+ GGML map) | 1/2 |
| `Models/SettingsState` (+ migration) | `SettingsState` (+ JSON migration) | 1 |
| `Models/HUDState` | `HudState` (+ `DownloadingModel`) | 1 |
| `Services/TextProcessor` | `Text/TextProcessor` | 1 |
| `Services/PhoneticMatcher` | `Text/PhoneticMatcher` | 1 |
| `Services/VocabularyPrompt` | `Text/VocabularyPrompt` | 1 |
| `Services/RepetitionGuard` | `Text/RepetitionGuard` | 1 |
| `Services/RegurgitationRecovery` | `Text/RegurgitationRecovery` | 1 |
| `Services/WavTail` | `Audio/WavTail` + `WavTailReader` | 1 |
| `Services/ChunkPlanner` | `Audio/ChunkPlanner` | 1 |
| `Services/StreamingTranscriptionSession` | `Audio/StreamingTranscriptionSession` | 1 |
| `Services/TranscriptionManager` (+ `TranscriptionEngine` protocol, `FileBackedTranscriptionEngine`, `WhisperModelLocator`) | `Transcription/ITranscriptionEngine` + `FileBackedTranscriptionEngine` (Phase 1); `TranscriptionManager` orchestration folds into `VoiceCoordinator` + engine (Phase 4); `WhisperModelStore` (Phase 2) | 1/2/4 |
| `Services/WhisperKitTranscriptionEngine` | `Whisper/WhisperNetTranscriptionEngine` | 2 |
| `Services/RecordingManager` | `Platform/NAudioRecorder` | 3 |
| `Services/AudioInputRouter` | `Platform/AudioInputRouter` | 3 |
| `Services/PasteManager` | `Platform/Paster` | 3 |
| `Services/HotKeyManager` | `Platform/GlobalHotkey` | 3 |
| `Services/LaunchAtLoginManager` | `Platform/LaunchAtLogin` | 3 |
| `Services/SettingsStore` | `Platform/SettingsStore` | 3 |
| `Services/StatsStore` | `Platform/StatsStore` | 3 |
| `Services/LastTranscriptStore` | `Platform/LastTranscriptStore` | 3 |
| `Services/SystemActions` | event/callback on `VoiceCoordinator` | 3/4 |
| `Services/PermissionError` | `Platform/PermissionError` + `SettingsUris` | 3 |
| `Services/AppTimings` | `AppTimings` constants (Core or App) | 1/3 |
| `Services/SettingsURLs` | `Platform/SettingsUris` | 3 |
| `Services/BenchRunner` | `tools/verify-transcription` + a `--bench` CLI switch on the App | 2/5 |
| `VoiceCoordinator` | `VoiceCoordinator` | 4 |
| `UI/HUDView`, `HUDWindow`, `HUDLayout` | `UI/HudView`, `HudWindow` | 4 |
| `UI/SettingsView`, `SettingsWindow` | `UI/SettingsView`, `SettingsWindow` | 4 |
| `UI/MenuBarController` | `UI/TrayIcon` | 4 |
| `UI/Components/PanelPressableButtonStyle` | WPF `Style` for pressable buttons | 4 |
| `JVoiceApp`, `AppDelegate` | `App.xaml(.cs)` + `SingleInstance` | 4 |
| `Resources/Info.plist` | `app.manifest` + assembly metadata + `AppUserModelId` | 4/5 |
| `Resources/AppIcon.icns`, `scripts/generate-icon.swift` | `Assets/JVoice.ico` + `tools/generate-icon` | 4 |
| `scripts/install.sh`, `setup-signing.sh` | Phase 5 publish + (no signing) | 5 |
| `scripts/run-logic-tests.sh`, `verify-streaming.sh` | `dotnet test` (xUnit) | 1 |
| `scripts/verify-transcription.py` | `tools/verify-transcription` | 5 |
| `.github/workflows/test.yml` | `.github/workflows/windows.yml` | 5 |

No macOS component is unmapped.

---

## 9. Assumptions made (logged per global rules)

1. **Stack = .NET 9 + WPF + Whisper.net.** Chosen autonomously (no stack was specified). Rationale + rejected alternatives in §2. This is the single highest-leverage decision; if David prefers Tauri/WinUI, the Core brain (Phase 1) and the engine choice (Phase 2) are still ~80% reusable, only the UI/platform shells change.
2. **Hotkey default Ctrl+Shift+Space** (⌥Space has no clean Windows equivalent). Rebindable.
3. **"Large" = quantized `ggml-large-v3-turbo-q5_0`** to match the macOS ~630 MB turbo build size/speed. Phase 2 can switch to full `ggml-large-v3-turbo.bin` if accuracy on real audio warrants.
4. **Tray-first with a first-run Settings window** as the "actual app UI" (faithful to macOS menu-bar model; §6.5).
5. **Keep the macOS app in-repo as reference**; Windows app under `windows/`. (Alternative: a separate repo. Kept together so the brain source-of-truth and tests travel with the port.)
6. **CUDA runtime bundled** (dev machine is NVIDIA); CPU runtime always bundled as fallback. Vulkan is a Phase 2 decision for broad non-NVIDIA GPU support in public builds.

---

---

## 10. Cross-phase reconciliation (authored after Phases 1–5 were written)

The phase docs were authored together and agree with each other; these notes record where the *as-built* placement refines the tentative §4 table above. **Where this section and §4 disagree, this section wins** (it reflects the final, internally-consistent plan).

- **Pure, testable helpers live in `JVoice.Core`, not `JVoice.App.Platform`.** To satisfy the test-reference constraint (§6.6 — `JVoice.Tests` is `net9.0` and cannot reference the `net9.0-windows` `JVoice.App`), the following pure value types / decision helpers were placed in `JVoice.Core` and unit-tested directly, while their OS-bound runtime counterparts stay in `JVoice.App.Platform`/`JVoice.App`:
  - `JVoice.Core/Models/HotkeyChord.cs` (parse/format/`Default`) ← used by `JVoice.App.Platform.GlobalHotkey` (the hook) and the UI `HotkeyRecorder`.
  - `JVoice.Core/Models/SettingsStateJson.cs` (JSON (de)serialization, forward-version refusal, per-field fallback) ← used by `JVoice.App.Platform.SettingsStore` (debounced file I/O).
  - `JVoice.Core/Audio/BluetoothDevicePolicy.cs` (pure non-BT pick policy) ← used by `JVoice.App.Platform.AudioInputRouter` (NAudio enumeration glue).
  - `JVoice.Core/StatsMath.cs` (WPM math) ← used by `JVoice.App.Platform.StatsStore`.
  - `JVoice.Core/CoordinatorDecisions.cs` (target-window resolution, HUD→tray map, reset-delay map) ← used by `JVoice.App.VoiceCoordinator`.
- **`AppTimings` gains `PasteRestoreDelayFailureMs = 50`** (Phase 1, Task 2) — the macOS PasteManager used a 0.05 s restore delay on the paste-failure path (vs 0.30 s on success). Now defined in Core so Phase 3's `Paster` compiles against it.
- **The engine lives in `JVoice.App` (namespace `JVoice.App.Whisper`)**, and Phase 2 creates `windows/JVoice.App/JVoice.App.csproj` (net9.0-windows WinExe) with a headless `Program.cs` + a `--bench` CLI branch; Phase 4 converts the entry point to WPF `App.xaml` while **preserving the `--bench` branch**. A WPF-free `windows/tools/whisper-smoke/` console project verifies transcription without the GUI.
- **Hotkey persistence:** Phase 1 `SettingsState` deliberately has **no** hotkey field, so a rebound hotkey lives for the session and resets to `HotkeyChord.Default` (Ctrl+Shift+Space) on relaunch. If persistence is wanted later, add a field to `SettingsState` + a schema bump (v2) and persist in `VoiceCoordinator.SetHotkey`. Logged assumption.
- **One Phase 2 ctor-default deviation** is noted in the Phase 2 doc (a constructor default differs slightly from the Swift signature to fit C# defaulting rules) — behaviorally identical.

---

*Next: execute Phase 1 (`2026-06-22-windows-port-01-core-brain.md`).*
