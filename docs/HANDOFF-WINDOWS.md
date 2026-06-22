# HANDOFF-WINDOWS — Windows port state (as of 2026-06-22)

Audience: David + the next Claude session. Read `CLAUDE.md` (incl. the new "Windows port" section) for the rules; this file is the mutable status for the **Windows** port. The macOS Swift app is unchanged and remains the reference.

## What this is

A native **Windows** port of JVoice. JVoice is a hotkey-driven voice-dictation app: press a hotkey → record mic → on-device Whisper transcription → tone-styled, custom-word-accurate text pasted into the focused app. The macOS app (Swift, WhisperKit/CoreML, AppKit) lives under `Sources/`. The Windows app is being built under `windows/` as a separate .NET solution.

## Decisions (locked this session, autonomous)

- **Stack: C# / .NET 9 / WPF** (`win-x64`, WinExe). Speech via **Whisper.net** (managed whisper.cpp bindings, **GGML** models) with **CUDA** GPU acceleration (dev machine: RTX 3060 Ti) + a CPU fallback. NAudio for capture, H.NotifyIcon.Wpf for the tray, SkiaSharp for the icon. This replaces macOS-only WhisperKit/CoreML — see the rejected alternatives (Swift-on-Windows / WinUI3 / Tauri / Electron) in the overview §2.4.
- **The accuracy "brain" ports faithfully** (model-agnostic): TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard, RegurgitationRecovery, ChunkPlanner, WavTail, StreamingTranscriptionSession — every constant verbatim, locked by xUnit tests translated from the Swift suite. The two WhisperKit-1.0.0-specific workarounds (SuppressBlankFilter prompt trap; single-window timestamp truncation) are **dropped** — whisper.cpp doesn't have those bugs.
- **GGML model map:** Tiny→`ggml-tiny.bin`, Base→`ggml-base.bin`, Small→`ggml-small.bin`, Large→`ggml-large-v3-turbo-q5_0.bin` (~547 MB, closest to the macOS ~630 MB turbo build). Downloaded on first use to `%LOCALAPPDATA%\JVoice\models\`.
- **Default hotkey: Ctrl+Shift+Space** (⌥Space has no clean Windows equivalent; Alt+Space is the system window menu). Rebindable.
- **"Actual app UI":** tray-first (faithful to the macOS menu-bar model) + a real focusable Settings window + first-run shows Settings once. The floating HUD pill remains the overlay.
- **$0 / unsigned:** no paid code-signing → unsigned `.exe`; document the SmartScreen "More info → Run anyway" step (the Gatekeeper analog). Privacy unchanged: zero runtime network except the one-time model download. GPL-3.0; all NuGet deps MIT-compatible.
- **Repo layout:** macOS app stays in place (read-only reference); Windows app under `windows/` (`JVoice.Core` pure-logic library + `JVoice.App` WPF + `JVoice.Tests` xUnit + `windows/tools/`).

## The plan (zero-context, phase-by-phase)

`docs/superpowers/plans/2026-06-22-windows-port-0{0..5}-*.md`. Read **00 (overview)** first — architecture, canonical names (§4), global constraints (§5), gotchas (§6), and the cross-phase reconciliation (§10).
- **00 overview** — anchor doc.
- **01 core-brain** — `JVoice.Core` + `JVoice.Tests`. **EXECUTED & GREEN this session** (see below).
- **02 whisper-engine** — Whisper.net engine + GGML model store + `--bench` CLI. **EXECUTED & VERIFIED this session** (see "Phase 2 progress" below — real on-device transcription on Windows, all invariants proven).
- **03 platform** — audio capture, BT-safe device pick, global hotkey, paste, persistence, launch-at-login. **EXECUTED & VERIFIED this session** (see "Phase 3 progress" below).
- **04 ui** — WPF tray + HUD pill + 320×520 settings + the "J" `.ico` + `VoiceCoordinator`. (Plan only.)
- **05 packaging** — single-file publish, Inno Setup, SmartScreen docs, Windows CI, verify-transcription harness, docs, dogfood checklist. (Plan only.)

## What was DONE this session (autonomous)

1. **Explored** the whole macOS app (architecture, brain, UI design tokens, platform services, icon geometry, build/test harnesses, transcription gotchas).
2. **Wrote the complete plan** (6 docs above) — zero-context, task-by-task, with real code. Phases 2–5 drafted by parallel subagents against the overview's canonical names + Phase 1 interfaces, then reconciled (overview §10).
3. **Executed Phase 1**: scaffolded `windows/JVoice.sln` (+ `Directory.Build.props`, `.editorconfig`), created `JVoice.Core` (Models, Text, Audio, Transcription) and `JVoice.Tests`, and **verified**:
   - `dotnet build windows/JVoice.sln -c Debug` → **Build succeeded, 0 warnings, 0 errors**.
   - `dotnet test windows/JVoice.Tests` → **Passed! 73 / 73** (PhoneticKey vectors jvoice/gvoice→jfs & whisperkit→wsprkt; tone/filler/correction/sentinel text processing; RepetitionGuard 36-case loop-dominated fuzz + single-mention controls; RegurgitationRecovery 4 cases; WavTail header (incl. FLLR padding); ChunkPlanner silence cuts; StreamingTranscriptionSession data-loss guarantees incl. finish-once/cancel-join; FileBackedTranscriptionEngine).
4. **Updated docs:** `CLAUDE.md` (new "Windows port" section), `.gitignore` (.NET ignores), this handoff.

## Assumptions made (logged)

- Stack chosen autonomously (no stack was specified) — see overview §2/§9. If David prefers Tauri/WinUI, Phase 1 (Core brain) + Phase 2 (engine choice) are ~80% reusable; only the UI/platform shells change.
- Hotkey default Ctrl+Shift+Space; "Large" = quantized turbo GGML; tray-first UI; CUDA runtime bundled (NVIDIA dev box) + CPU fallback always.
- `SettingsState` has no persisted hotkey field yet (rebind is session-only until a v2 schema adds it) — noted in Phase 4.

## Needs David's eyes

- **The stack decision** is the big one. Everything downstream assumes .NET 9 + WPF + Whisper.net. Confirm before Phases 2–5 are executed.
- Whether the public Windows build should bundle Vulkan (broad non-NVIDIA GPU support) in addition to CPU + CUDA (Phase 2 decision).
- Whether "Large" should be the quantized turbo (`q5_0`, ~547 MB) or the full `ggml-large-v3-turbo.bin` (~1.5 GB) — Phase 2 verifies accuracy on real audio before locking.

## Next steps

1. **David reviews the stack + plan**; confirm or redirect.
2. Execute **Phase 2** (whisper engine) — first real transcription on Windows; verify a prompted vocab decode is non-empty and a >30 s clip isn't truncated (the two whisper.cpp-vs-WhisperKit checks).
3. Execute **Phase 3** (platform), **Phase 4** (UI + coordinator), **Phase 5** (packaging).
4. Dogfood (Phase 5 checklist). **Do NOT publish/push** without David's explicit go-ahead (same rule as the macOS side).

## Phase 2 progress (Whisper engine — this session)

### Pinned NuGet versions (Task 1)

All resolved + pinned at the current stable **1.9.1** (in `windows/JVoice.App/JVoice.App.csproj`, and copied to `windows/tools/whisper-smoke/whisper-smoke.csproj`):

- `Whisper.net` `1.9.1` (MIT)
- `Whisper.net.Runtime` `1.9.1` — CPU (MIT)
- `Whisper.net.Runtime.Cuda` `1.9.1` — NVIDIA GPU (MIT)
- `Whisper.net.Runtime.Vulkan` `1.9.1` — cross-GPU (MIT). Restored fine; bundled.

### Whisper.net 1.9.1 API probe results (Task 1 Step 7) — what the engine code uses

Reflected the installed assembly. **The plan's assumed names mostly hold, with key deviations recorded here so future sessions don't re-derive them:**

- `WhisperFactory.FromPath(string)` ✓ (also `FromPath(string, WhisperFactoryOptions)`); `WhisperFactory.CreateBuilder()` ✓; `WhisperFactory.GetRuntimeInfo()` (instance, returns string).
- `WhisperProcessorBuilder`: `WithLanguage(string)` ✓, `WithPrompt(string)` ✓ (NOT `WithPromptText`), `WithTemperature(float)` ✓, `WithTemperatureInc(float)` ✓, `WithEntropyThreshold(float)` ✓, `WithLogProbThreshold(float)` ✓ (NOT `WithProbabilityThreshold`), `WithGreedySamplingStrategy(Action)` / `WithBeamSearchSamplingStrategy(Action)` exist.
- **`WithoutTimestamps()` does NOT exist in 1.9.1.** There is no decoder no-timestamps flag on the builder (only `WithPrintTimestamps(bool)`, `WithTokenTimestamps()`, `WithSingleSegment()` — none is the right thing). **Resolution:** the engine does NOT disable timestamps; it just concatenates `SegmentData.Text` across segments. whisper.cpp does its own 30s windowing with context carry, so the full transcript is produced and is NOT truncated (verified in Task 6 Step 5). This is effectively the "timestamps on" position, which was already the documented Task 3 Step 9 fallback — so we're at the safe end and the `isSingleWindowClip` WhisperKit gate stays dropped. (Do NOT add `WithSingleSegment()` — it would force one segment and could truncate long audio.)
- **`WithoutSuppressBlank()` exists** → confirms `suppress_blank` is ON by default in whisper.cpp/Whisper.net. We do NOT call it, so the SuppressBlankFilter workaround stays dropped (§6.3 confirmed; empirically re-checked in Task 6 Step 4).
- `WhisperProcessor.ProcessAsync(float[], CancellationToken)` ✓ — also `(ReadOnlyMemory<float>, CT)` and `(Stream, CT)`. The CancellationToken is a REQUIRED positional arg (not defaulted) — always pass `ct`.
- `SegmentData.Text` (string) ✓ — segments also carry `Start`/`End` (TimeSpan), `Probability`, `NoSpeechProbability`, `Tokens`.
- Runtime selection: `Whisper.net.LibraryLoader.RuntimeOptions.LoadedLibrary` is a typed static `RuntimeLibrary?` (null until first factory load). `RuntimeLibrary` enum = `Cpu, Cuda, Cuda12, Vulkan, CoreML, OpenVino, CpuNoAvx`. `WhisperRuntime.Describe()` reads this typed property (after prewarm).
- Bonus: a built-in `Whisper.net.Ggml.WhisperGgmlDownloader` exists, but we keep the custom `WhisperModelStore` (atomic `.part` + size/SHA verification + the `%LOCALAPPDATA%\JVoice\models\` layout the plan specifies).

### GGML model manifest (Task 2) — recorded from Hugging Face `ggerganov/whisper.cpp`

| Model | File | ExpectedBytes | SHA-256 |
| --- | --- | --- | --- |
| Tiny | `ggml-tiny.bin` | 77,691,713 | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| Base | `ggml-base.bin` | 147,951,465 | null (size-only) |
| Small | `ggml-small.bin` | 487,601,967 | null (size-only) |
| Large | `ggml-large-v3-turbo-q5_0.bin` | 574,041,195 | null (size-only) |

Tiny's SHA matches the published whisper.cpp hash; it was pre-placed in `%LOCALAPPDATA%\JVoice\models\ggml-tiny.bin` (verified) so Task 6 reuses it without re-downloading. `CompleteModelPath` checks existence + exact size (cheap); the full SHA is verified once, right after download, before the atomic `.part`→final rename.

### Build gotcha (logged): WindowsDesktop SDK trims implicit usings

`net9.0-windows` + `<UseWPF>true</UseWPF>` uses the WindowsDesktop SDK, whose implicit-usings set is REDUCED vs the base `Microsoft.NET.Sdk`: it includes `System`, `System.Collections.Generic`, `System.Linq`, `System.Threading`, `System.Threading.Tasks` but NOT `System.IO` or `System.Net.Http` (stripped to avoid `Path` ambiguity with `System.Windows.Shapes.Path`). The plan's `JVoice.App` code snippets assumed the base set, so engine/store/bench files need explicit `using System.IO;` (and `using System.Net.Http;` where used). `JVoice.Core` (plain `net9.0`) keeps the full implicit set, so its code is unaffected. (Did NOT add a project-level global `System.IO` using — that would re-introduce the `Path` ambiguity in Phase 4 UI files.)

### Deviations from the plan (logged)

- **Temperature fallback (`temperatureFallbackCount = 2`)**: mapped to `WithTemperature(0.0f)` + `WithTemperatureInc(0.2f)` (these equal whisper.cpp defaults; Whisper.net exposes no exact "fallback count" knob, so the macOS `=2` is approximated — the plan calls this `≈`). Entropy/logprob thresholds left at whisper.cpp defaults.
- **`Program.cs` ordering**: created as a runnable no-op in Task 1 (no `BenchRunner` reference) so Tasks 1–4 each build green; the `BenchRunner.ShouldRun/RunAndExit` branch is wired in during Task 5 (matches the plan's end-state Program.cs). Phase 4 replaces this with the WPF `App.xaml` `[STAThread]` entry but must keep the bench branch before any UI.

### Phase 2 E2E verification (Task 6) — REAL on-device transcription on Windows

Run on the dev machine (RTX 3060 Ti, i5-12400). Test WAVs generated via Windows TTS
(System.Speech, 16 kHz mono 16-bit PCM): `jv-known.wav` (~6.5s), `jv-long.wav` (~125s),
`jv-vocab.wav` (~3.6s). `dotnet build windows/JVoice.sln -c Release` = **succeeded, 0/0**;
`dotnet test` = **73/73 green** (Phase 1 unaffected).

- **Selected runtime: `whisper.cpp (Vulkan)`.** Whisper.net's loader fell CUDA → **Vulkan**
  (the CUDA *runtime* package is bundled, but the CUDA toolkit DLLs (`cudart`) aren't installed
  on this box, so it used the Vulkan GPU path — still GPU-accelerated on the 3060 Ti; CPU is the
  universal fallback). All four runtime packages' natives land under `bin/.../runtimes/` (cuda,
  vulkan, win-x64). To force CUDA later, install the CUDA toolkit or set
  `RuntimeOptions.RuntimeLibraryOrder`.
- **(a) Download/locate** — `ggml-tiny.bin` (size 77,691,713, SHA verified) reused from
  `%LOCALAPPDATA%\JVoice\models\` with NO re-download on repeat runs; no `.part` leftovers.
- **(b) Prompted decode is NON-EMPTY** (the SuppressBlankFilter-not-needed proof). `--bench
  jv-vocab.wav --vocab "VS Code,JVoice"`:
  - prompted (`decoderPrompt: on`): raw `"I am editing Code in VS Code with J Voice Today."` → processed `"I am editing Code in VS Code with JVoice Today"` (exit 0)
  - `--no-prompt` (`decoderPrompt: off`): raw `"I am editing code in VS code with J Voice Today."` → processed `"I am editing code in VS Code with JVoice Today"` (exit 0)
  - Both non-empty ⇒ the prompt neither breaks decoding nor is load-bearing; and the prompt
    biased "VS Code" (capital C) vs no-prompt "VS code" — vocabulary biasing works at the source.
- **(c) >30s clip NOT truncated** (the dropped single-window-timestamp-trap proof). `--bench
  jv-long.wav` (~125s) returned all 12 numbered sentences (1→12), tail intact, in 3.73s on Vulkan.
  Confirms whisper.cpp's internal 30s windowing handles long audio with no `WithoutTimestamps()`.
- **(d) `--bench` exit codes**: 64 (missing file arg), 66 (no such file), 0 (success) — verified.
- **(e) Streaming corroborated**: `--bench jv-known.wav --stream` → `streamed: nil (session fell
  back)` (CORRECT — 6.5s < ChunkPlanner.MinChunkSeconds 15s, so it never cuts and falls back to
  whole-file losslessly), wholefile corroborates, exit 0. On `jv-long.wav --stream` (forces 25s
  MaxChunkSeconds cuts): `streamed` non-null with all 12 sentences (1→12) — **no data loss** in the
  streaming path; whole-file corroborates.

**Net: all Phase 2 invariants proven on real audio. The two WhisperKit workarounds stay dropped,
empirically confirmed.** (Speed note: first GPU decode pays a one-time Vulkan shader-compile cost
— ~14s on the first prompted decode, then 2-4s on subsequent decodes; not a correctness issue.)

## Phase 3 progress (Platform services — this session)

All under `JVoice.App/Platform/` (Win32/WASAPI/registry/WPF-clipboard), with the pure
testable bits in `JVoice.Core`. **`dotnet build windows/JVoice.sln -c Release` = 0/0;
`dotnet test` = 109/109 green; `JVoice.Core` has NO package references (stayed pure).**
NuGet pinned: **NAudio 2.3.0** (on `JVoice.App`).

Built: PlatformPaths; SettingsStateJson + StatsMath + BluetoothDevicePolicy + HotkeyChord
(pure, in Core, 36 new xUnit tests); SystemActions; SettingsStore (debounced + corruption/
forward-version recovery); StatsStore; LastTranscriptStore; LaunchAtLogin; SingleInstance;
SettingsUris; PermissionError; AudioInputRouter; IAudioRecorder + NAudioRecorder;
ForegroundWindowTracker; GlobalHotkey; Paster.

### Verified on the dev machine (throwaway consoles, since net9.0-windows can't be unit-tested from net9.0 JVoice.Tests):
- **SettingsStore**: fresh-write, reload, corruption→backup+reset, forward-version refusal. PASS.
- **StatsStore / LastTranscriptStore**: record/guard/reload, UTF-8 round-trip. PASS.
- **SingleInstance**: real cross-process — child got `child-blocked` while parent held the mutex; re-acquire after release. PASS.
- **LaunchAtLogin**: enable→true, disable→false, first-run idempotent enable→true; **registry reverted** (Run\JVoice + init flag confirmed absent). PASS.
- **PermissionError/SettingsUris**: deep link == `ms-settings:privacy-microphone`, message non-empty. PASS.
- **AudioInputRouter**: default device "Microphone (Yeti Classic)" (non-BT) → `PreferredCaptureDeviceId()` returns null (record from default). PASS.
- **NAudioRecorder**: orphan sweep (jvoice-*.wav deleted, non-ours kept), usable check (2000B=true/10B=false), mic permission True, **growing WAV readable by WavTailReader at ~16000 samples/sec** (15680→31520→47520 over 3s), final header **16000/1/2**. PASS — the critical Phase 1↔Phase 3 streaming contract holds.
- **Paster**: Paste("")→TargetRejected, Paste(_, IntPtr.Zero)→TargetRejected, Stage() clipboard round-trip. PASS.
- **ForegroundWindowTracker**: GetForegroundWindowNow() non-zero. PASS.

### Deferred to interactive dogfood (Phase 4/5 — cannot run in this non-interactive session):
- **GlobalHotkey live global-fire**: SendInput-injected keystrokes are NOT delivered to a `WH_KEYBOARD_LL` hook in a non-interactive/headless run (LL hooks + synthetic input are bound to an interactive desktop). The code builds and installs/tears-down the hook cleanly; chord matching is covered by HotkeyChord unit tests. David should confirm Ctrl+Shift+Space fires globally + the 150ms debounce when running the Phase 4 app.
- **Paster live paste into another app** (Ctrl+V landing in Notepad + 300ms clipboard restore) and **ForegroundWindowTracker live tracking** (needs a message pump) — verified end-to-end once the Phase 4 UI exists.

### Phase 3 deviations from the plan (logged)
- **NAudioRecorder: `BufferedWaveProvider.ReadFully = false`** — the plan omitted this; its default (`true`) makes `Read()` zero-pad to the requested count forever, so the `PumpToWriter` `while (read > 0)` loop became an **infinite zero-writing busy loop** (caught in verification — two runaway processes at >130s CPU). Setting `ReadFully = false` makes `Read` return only buffered bytes (0 when drained). Root-cause fix, not a workaround.
- **AudioInputRouter form factor via property store** — NAudio 2.3.0 has no `MMDevice.AudioEndpointFormFactor`; read `PKEY_AudioEndpoint_FormFactor` from `MMDevice.Properties` instead (Headset=5/Headphones=3 → BT signal, Microphone=4 → built-in). BTHENUM enumerator name remains the load-bearing BT signal.
- **`ISampleProvider.WaveFormat.SampleRate`** used instead of the plan's `sampleSource.SampleRate` (ISampleProvider exposes rate via WaveFormat).
- **SettingsStoreJson invalid-JSON test** relaxed to `Assert.ThrowsAny<JsonException>` (JsonDocument.Parse throws the JsonReaderException subclass).
- All `JVoice.App` Platform files need explicit `using System.IO;` (WindowsDesktop SDK trims it from implicit usings — see Phase 2 note).

## Verification commands (reference)

- Build: `dotnet build windows/JVoice.sln -c Release`
- Test:  `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj`
- Transcribe (no GUI): `dotnet run --project windows/tools/whisper-smoke -- <wav> --model tiny`
- Bench: `windows/JVoice.App/bin/<cfg>/net9.0-windows/JVoice.exe --bench <wav> [--model …] [--vocab …] [--stream] [--no-prompt]`
- (Later) Run: `dotnet run --project windows/JVoice.App`
