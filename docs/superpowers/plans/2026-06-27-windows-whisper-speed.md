# JVoice (Windows) — Whisper Transcription Speed-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **✅ EXECUTED 2026-06-27** (commits `45a640d`..`28a158c` on `windows-port`; measured numbers in
> [`2026-06-27-windows-whisper-speed-results.md`](2026-06-27-windows-whisper-speed-results.md)).
> The per-lever "adopt" steps below describe the *intended* measure-then-adopt flow; the **actual
> outcome** on the RTX 3060 Ti / i5-12400 was: **flash attention ADOPTED** (GPU ~30–37% faster,
> transcripts identical; forced OFF on CPU) and **decode threads = physical cores ADOPTED** (CPU
> ~21% faster). **Tasks 4 (per-clip `audio_ctx`), 7 (CUDA), 8 (temp-fallback cap) were measured/
> assessed but NOT adopted** — audio_ctx was non-monotonic (regression risk), CUDA needs an
> uninstalled toolkit, temp-cap diverges from macOS parity. `dotnet test` 555/555; the installed app
> + both `~/Downloads` installers were refreshed to this build. See HANDOFF-WINDOWS §7 #31.

**Goal:** Make on-device Whisper transcription in the JVoice Windows port measurably faster — especially the "Large" (large-v3-turbo) model — without losing accuracy, by adding a small, measured, tunable layer on top of the existing Whisper.net engine (no model/brain changes, no Whisper.net upgrade).

**Architecture:** Add one pure, unit-tested tuning-policy helper to `JVoice.Core` and thread a small `EngineTuning` options record through the existing `WhisperNetTranscriptionEngine`. Wire three already-available Whisper.net 1.9.1 levers — **per-clip `audio_ctx` sizing** (the biggest short-clip win), **decode thread count**, and **flash attention** (factory option) — each gated behind an on-device `--bench` A/B measurement before its default is flipped. Backend work (forcing/measuring CUDA vs the current Vulkan runtime) is an optional, opt-in extension. The macOS Swift app and the `JVoice.Core` "brain" constants are untouched.

**Tech Stack:** C# / .NET 9 / WPF, `win-x64`. Whisper.net **1.9.1** (managed whisper.cpp bindings; bundled whisper.cpp 1.8.5) with GGML models; runtimes referenced: `Whisper.net.Runtime` (CPU), `Whisper.net.Runtime.Cuda` (CUDA 13), `Whisper.net.Runtime.Vulkan`. Dev machine: NVIDIA RTX 3060 Ti (8 GB, Ampere CC 8.6) + Intel i5-12400 (6 physical cores / 12 logical).

## Global Constraints

These are copied verbatim from the project's rules (`CLAUDE.md`, `docs/HANDOFF-WINDOWS.md`) and apply to **every** task below:

- **Do NOT modify the macOS sources:** never touch `Sources/`, `Tests/`, `Package.swift`, or `Resources/`. They are the read-only reference.
- **Do NOT change the "brain" constants.** `JVoice.Core/Text/*` (TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard, RegurgitationRecovery) is a 1:1 port of macOS and is parity-test-locked. This plan adds a **new** Windows-first `JVoice.Core/Policy/WhisperTuning.cs` (allowed — same category as the existing Windows-first `GameDetectionPolicy`/`DeveloperTerms`), and touches the **App engine layer**, the **bench**, and **docs** only.
- **Do NOT upgrade Whisper.net.** 1.9.1 (released 2026-06-01) is already the latest stable; every lever this plan uses is confirmed present in the pinned 1.9.1 assembly (see §"API facts" below). Upgrading is out of scope and would force a re-pin + full re-test.
- **Do NOT add digital gain to the transcription audio** to "fix accuracy" (standing guard — `CLAUDE.md` §7 #22; memory `win-mic-low-capture-level`). This plan is about *speed*, not level.
- **$0 / unsigned / privacy:** no new runtime network calls (the one-time model download is the only allowed network); all deps stay MIT-compatible (GPL-3.0 app); **NO publishing / pushing / PRs / remotes** without David's explicit go-ahead.
- **Build:** `dotnet build windows/JVoice.sln -c Release` must stay **0 errors**. `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` is **523/523 green** at the start and must stay green (plus the new tests this plan adds).
- **Build/run gotchas:** (a) a running JVoice tray app **locks `JVoice.Core.dll`** in `bin\`, so a rebuild reports MSB3021/MSB3026 *copy* errors — quit the tray app first, or build to a throwaway dir with `-o <tmp>`. (b) The real app binary is at `windows\JVoice.App\bin\x64\Release\net9.0-windows\JVoice.exe`; a plain build can leave that path **stale** — build with the `.sln` or `-p:Platform=x64` and launch from `bin\x64\Release` (memory `win-build-x64-path`). (c) **Do NOT run JVoice elevated** — elevated launch freezes the first recording (`HANDOFF-WINDOWS.md` §8); run/measure non-elevated.
- **Git:** work on a feature branch (create `feat/whisper-speed` off `windows-port`); commit per task; do **not** push.

---

## Background — read this first (zero-context reader)

**What JVoice is.** A hotkey-driven voice-dictation tray app: press `Ctrl+Shift+Space` → record mic → on-device Whisper transcription → tone-styled, custom-word-corrected text pasted into the focused app. Windows port lives under `windows/` (a .NET solution); the macOS original is Swift/WhisperKit and is reference-only.

**How transcription works today (the code you'll change).**
- The engine is `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs` (implements `JVoice.Core.Transcription.ITranscriptionEngine`).
- It loads a GGML model once via `WhisperFactory.FromPath(modelPath)` in `PerformLoadAsync` (line ~126), deduping concurrent loads.
- Every decode (whole-file **and** each streaming chunk) goes through one method, `DecodeSamplesAsync` (line ~237), which builds a fresh `WhisperProcessor` with: `.WithLanguage(code)`, optional `.WithPrompt(vocabPrompt)`, `.WithTemperature(0)`, `.WithTemperatureInc(0.2)`. **Nothing else is set** — no thread count, no flash attention, no audio-context sizing.
- "Large" maps to `ggml-large-v3-turbo-q5_0.bin` (~574 MB), downloaded to `%LOCALAPPDATA%\JVoice\models\` by `WhisperModelStore`. This is already the *fast* turbo variant (4 decoder layers) and is q5_0-quantized.
- Streaming-while-recording (`JVoice.Core/Audio/StreamingTranscriptionSession.cs` + `ChunkPlanner.cs`) decodes completed chunks (15–25 s each) during recording; on any failure it falls back losslessly to a whole-file decode.
- The hidden bench CLI is `windows/JVoice.App/Whisper/BenchRunner.cs` (`JVoice.exe --bench <wav> [--model …] [--stream] …`), the only end-to-end speed/accuracy check for the native path (there is **no** xUnit coverage of the GPU/native decode — that is verified on-device by `--bench`, by design).
- The engine is constructed in `windows/JVoice.App/VoiceCoordinator.cs` → `MakeEngine` (line ~385): `new WhisperNetTranscriptionEngine(model, lang, vocab, useVocabularyPrompt: true, _modelStore)`.

**Why the GPU path is currently Vulkan, not CUDA (root cause, confirmed).** The app references `Whisper.net.Runtime.Cuda` 1.9.1, which is the **CUDA 13** build: its `ggml-cuda-whisper.dll` hard-imports `cublas64_13.dll` + `nvcudart_hybrid64.dll`, which come from the **CUDA 13 Toolkit (≥ 13.0.1) + an r580+ driver** — neither is installed on the dev box. The NuGet does **not** bundle cudart/cublas (verified by reading the package's PE imports). So the CUDA runtime fails to load and Whisper.net **silently falls back** down its probe order to the self-contained **Vulkan** runtime (which only needs the GPU driver's Vulkan ICD). This is whisper.net issue #509. There is also a `Whisper.net.Runtime.Cuda12` package (CUDA 12 Toolkit ≥ 12.4.1, driver ≥ 551.61) for CUDA-12 systems.

**The lever map (researched, with the magnitude and the catch for each).**

| Lever | Where | Backend | Expected gain | Risk | Plan |
| --- | --- | --- | --- | --- | --- |
| **`audio_ctx` sized per clip** (`WithAudioContextSize`) | decode builder | all (Vulkan/CUDA/CPU) | **~2–3× encoder on short clips** (whisper.cpp #297, #1855) | low–med (size with headroom; never under-cover speech) | **Task 4 — primary win for the current Vulkan box** |
| **Decode threads** (`WithThreads`) | decode builder | mostly CPU | meaningful on the **CPU build** (default download); ~nil on GPU | low | Task 5 |
| **Flash attention** (`WhisperFactoryOptions.UseFlashAttention`) | factory | CUDA: ~1.3–1.7× encoder (whisper.cpp PR #2152). **Vulkan: coin-flip** (needs NVIDIA `coopmat2`; else regresses to CPU). **CPU: degrades** | med (measure; English accuracy near-identical, one report of language-dependent drift) | Task 6 (measure on Vulkan; force OFF on CPU build) |
| **CUDA backend** (add `Cuda12` + redist) | runtime | CUDA only | ~20–30% encode vs Vulkan in 2026; near-parity on decode | high cost (Toolkit/redist + driver; large bundle) | Task 7 (OPTIONAL, opt-in) |
| **Cap temperature fallback** (`WithTemperatureInc(0)`) | decode builder | all | removes worst-case up-to-6× re-decode on hard clips | med (loses retry safety net; diverges from macOS) | Task 8 (OPTIONAL, lowest priority) |

**Rejected — do NOT do these:**
- **q5_0 → q4 for speed.** On GPU, quantization is a **VRAM-only** change, not a speed win (the encoder is compute-bound; GPU quant kernels add dequant work). HF ships no turbo-q4 file anyway (would need a self-quantize build step), and turbo's 4 decoder layers make q4 accuracy-riskier. (whisper.cpp DeepWiki 5.2; discussions #838/#859.) Optional q8_0 (~874 MB) is an *accuracy* option, not a speed one — out of scope.
- **`WithSingleSegment()`.** It truncates anything > 30 s (the handoff explicitly warns against it). Not worth the marginal gain.
- **Beam search.** We're already greedy at temp 0 (the fast path). Switching to beam would be *slower*.
- **Token timestamps / DTW.** Already off; keep off.
- **Silero VAD (`WhisperVadFactory`, new in 1.9.1).** Trimming "silence" before decode risks re-introducing the exact false-negative (`HANDOFF-WINDOWS.md` §7 #21) where David's quiet/low-SNR speech reads as silence. The app's no-speech handling is hard-won; do not bolt VAD under it. Noted, deferred.

**API facts — all confirmed present in the pinned 1.9.1 `Whisper.net.dll` (no upgrade needed):**
- `Whisper.net.WhisperFactoryOptions` with settable `UseFlashAttention` (bool, default false), `UseGpu` (bool, default true), `GpuDevice` (int, default 0). Consumed by `WhisperFactory.FromPath(string path, WhisperFactoryOptions options)`.
- `WhisperProcessorBuilder.WithThreads(int)`, `.WithAudioContextSize(int)`, `.WithTemperatureInc(float)`, `.WithNoContext()` — all present. (Flash attention is **NOT** a builder method — it's the factory option above.)
- `Whisper.net.LibraryLoader.RuntimeOptions.RuntimeLibraryOrder` (a `List<RuntimeLibrary>`, must be set **before** the first `WhisperFactory`), `RuntimeOptions.LoadedLibrary` (`RuntimeLibrary?`, null until first load). `RuntimeLibrary` enum members: `Cpu, Cuda, Cuda12, Vulkan, CoreML, OpenVino, CpuNoAvx`.
- `Whisper.net.Logger.LogProvider.AddConsoleLogging(WhisperLogLevel level)`; `WhisperLogLevel.{Debug,Info,Warning,Error,None}`.
- whisper.cpp default thread count when unset = `min(4, hardware_concurrency())` → only 4 on the i5-12400.

**Key source URLs (for the zero-context reader to verify):** whisper.net runtime API — `https://raw.githubusercontent.com/sandrohanea/whisper.net/1.9.1/Whisper.net/LibraryLoader/RuntimeOptions.cs`; flash-attention option — `https://github.com/sandrohanea/whisper.net/pull/302`; CUDA-fallback root cause — `https://github.com/sandrohanea/whisper.net/issues/509`; flash attention in whisper.cpp — `https://github.com/ggml-org/whisper.cpp/pull/2152`; `audio_ctx` guidance — `https://github.com/ggml-org/whisper.cpp/discussions/297` and `https://github.com/ggml-org/whisper.cpp/issues/1855`; thread scaling — `https://github.com/ggml-org/whisper.cpp/discussions/403`.

---

## File Structure

**New files:**
- `windows/JVoice.Core/Policy/WhisperTuning.cs` — pure tuning policies (audio-context sizing + decode-thread count). No Whisper.net/Win32 deps. Namespace `JVoice.Core` (matches the other `Policy/` files).
- `windows/JVoice.Tests/WhisperTuningTests.cs` — xUnit tests locking the policies.
- `windows/JVoice.App/Whisper/EngineTuning.cs` — App-internal record carrying the decode knobs into the engine; holds the single committed-default (`EngineTuning.Default`).
- `windows/JVoice.App/Platform/System/CpuInfo.cs` — physical-core count via Win32 `GetLogicalProcessorInformation` (added in Task 5).
- `docs/superpowers/plans/2026-06-27-windows-whisper-speed-results.md` — the measured before/after matrix (written in Task 9 from David's machine).

**Modified files:**
- `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs` — accept `EngineTuning`; apply factory + builder options.
- `windows/JVoice.App/Whisper/WhisperRuntime.cs` — add `ForceRuntimeOrder(...)` + `EnableDebugLogging()` helpers (for the bench).
- `windows/JVoice.App/Whisper/BenchRunner.cs` — new measurement flags (`--iters`, `--flash`, `--threads`, `--audio-ctx`, `--runtime`, `--log-runtime`) + warm-up + median/min reporting.
- `windows/JVoice.App/JVoice.App.csproj` — define `JVOICE_CPU` for the `cpu` publish flavor (forces flash attention off there); (Task 7, optional) conditional `Whisper.net.Runtime.Cuda12` reference.
- `windows/tools/whisper-smoke/whisper-smoke.csproj` — link the new `EngineTuning.cs` (and `CpuInfo.cs` in Task 5) since it compiles the engine source.
- `docs/HANDOFF-WINDOWS.md` and `windows/JVoice.App/Whisper/CLAUDE.md` — record the tuned defaults + the FA backend-conditionality (Task 9).

---

## Setup (do once, before Task 1)

- [ ] **Create the feature branch.**

```bash
cd /c/Users/david_v0a3rlc/Sorted/Coding/Apps/JVoice-Windows
git checkout windows-port
git checkout -b feat/whisper-speed
```

- [ ] **Confirm a clean baseline.** Quit any running JVoice tray app first (it locks DLLs).

```bash
dotnet build windows/JVoice.sln -c Release        # expect: Build succeeded, 0 errors
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj   # expect: Passed!  523/523 (number may have grown; all green)
```
Expected: build 0 errors; all tests pass. If not, stop and fix the environment before proceeding.

---

### Task 1: Pure tuning policies in `JVoice.Core` (TDD)

The arithmetic that decides `audio_ctx` per clip and the decode-thread count. Pure and unit-tested; the App layer just applies the results.

**Files:**
- Create: `windows/JVoice.Core/Policy/WhisperTuning.cs`
- Test: `windows/JVoice.Tests/WhisperTuningTests.cs`

**Interfaces:**
- Produces (later tasks rely on these exact signatures):
  - `JVoice.Core.WhisperTuning.AudioContextFor(double seconds) -> int?` (null = leave whisper's full default)
  - `JVoice.Core.WhisperTuning.AudioContextForSamples(int sampleCount) -> int?`
  - `JVoice.Core.WhisperTuning.DecodeThreads(int physicalCores) -> int`
  - Constants `WhisperTuning.SampleRate = 16000`, `FullAudioContext = 1500`, `MinAudioContext = 768`.

- [ ] **Step 1: Write the failing tests.**

Create `windows/JVoice.Tests/WhisperTuningTests.cs`:

```csharp
using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

public class WhisperTuningTests
{
    [Theory]
    // Short clips clamp UP to the 768 floor (which covers ~15 s of audio, so never under-covers).
    [InlineData(0.5, 768)]
    [InlineData(5.0, 768)]
    [InlineData(12.0, 768)]
    // Mid clips: (s/30)*1500 + 128, rounded UP to a multiple of 64.
    [InlineData(13.0, 832)]
    [InlineData(15.0, 896)]
    [InlineData(20.0, 1152)]
    [InlineData(25.0, 1408)]
    public void AudioContextFor_ShortAndMidClips_ReturnsSizedContext(double seconds, int expected)
        => Assert.Equal(expected, WhisperTuning.AudioContextFor(seconds));

    [Theory]
    // Long enough that the sized value meets/exceeds the full window → null (don't set; use default).
    [InlineData(27.0)]
    [InlineData(30.0)]
    [InlineData(125.0)]
    public void AudioContextFor_LongClips_ReturnsNull(double seconds)
        => Assert.Null(WhisperTuning.AudioContextFor(seconds));

    [Theory]
    [InlineData(0.0)]
    [InlineData(-3.0)]
    [InlineData(double.NaN)]
    public void AudioContextFor_NonPositiveOrNaN_ReturnsFloor(double seconds)
        => Assert.Equal(WhisperTuning.MinAudioContext, WhisperTuning.AudioContextFor(seconds));

    [Fact]
    public void AudioContextForSamples_ConvertsSamplesToSeconds()
        // 80 000 samples / 16 000 Hz = 5 s → 768 floor.
        => Assert.Equal(768, WhisperTuning.AudioContextForSamples(80_000));

    [Fact]
    public void AudioContextFor_NeverUnderCoversTheClip()
    {
        // The returned context (in 50-frames/sec units) must always cover the clip duration.
        for (double s = 0.5; s < 27.0; s += 0.5)
        {
            int? ctx = WhisperTuning.AudioContextFor(s);
            int frames = ctx ?? WhisperTuning.FullAudioContext;
            Assert.True(frames / 50.0 >= s, $"ctx {frames} (~{frames / 50.0}s) under-covers {s}s clip");
        }
    }

    [Theory]
    [InlineData(6, 6)]
    [InlineData(1, 1)]
    [InlineData(0, 1)]    // clamp up to 1
    [InlineData(24, 16)]  // clamp down to 16
    public void DecodeThreads_ClampsToSaneRange(int physical, int expected)
        => Assert.Equal(expected, WhisperTuning.DecodeThreads(physical));
}
```

- [ ] **Step 2: Run the tests to confirm they fail (red).**

```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj --filter WhisperTuningTests
```
Expected: FAIL — `WhisperTuning` does not exist (CS0103 / compile error). Good.

- [ ] **Step 3: Implement the policy.**

Create `windows/JVoice.Core/Policy/WhisperTuning.cs`:

```csharp
namespace JVoice.Core;

/// Pure, unit-tested tuning policies for the whisper decode path.
/// No Whisper.net / Win32 dependency — just arithmetic the App engine applies.
/// Windows-first (no macOS counterpart yet), like GameDetectionPolicy / DeveloperTerms.
public static class WhisperTuning
{
    public const int SampleRate = 16_000;
    /// whisper.cpp's full encoder window: 50 mel frames/sec * 30 s = 1500.
    public const int FullAudioContext = 1500;
    /// Maintainer floor — below this the encoder loses real context (whisper.cpp Discussion #297).
    /// 768 frames ≈ 15.4 s of audio, so it always covers a sub-13 s clip with headroom.
    public const int MinAudioContext = 768;

    /// Encoder context size for a clip of the given duration, or null to leave whisper's full
    /// default (used once the sized value would meet/exceed 1500 — reducing a long clip would
    /// risk truncating real speech, since whisper windows long audio into 30 s segments).
    /// Formula (whisper.cpp issue #1855): ctx = (seconds/30)*1500 + 128, rounded UP to a
    /// multiple of 64, clamped to [768, 1500]; null when that reaches the full window.
    public static int? AudioContextFor(double seconds)
    {
        if (double.IsNaN(seconds) || seconds <= 0) return MinAudioContext;
        double raw = seconds / 30.0 * FullAudioContext + 128.0;
        if (raw >= FullAudioContext) return null;                 // long clip → full context
        int rounded = (int)(System.Math.Ceiling(raw / 64.0) * 64); // multiples of 64
        rounded = System.Math.Clamp(rounded, MinAudioContext, FullAudioContext);
        return rounded >= FullAudioContext ? null : rounded;       // rounding hit the cap → full
    }

    /// Encoder context size from a raw mono 16 kHz sample count.
    public static int? AudioContextForSamples(int sampleCount)
        => AudioContextFor(sampleCount / (double)SampleRate);

    /// whisper.cpp decode threads: the physical core count is the sweet spot; going past it
    /// (into hyperthreads) adds contention without throughput (whisper.cpp Discussion #403).
    /// Clamped to a sane [1, 16]. Mainly helps the CPU-fallback build (whisper's default is
    /// only min(4, logical)); on the GPU path threads barely matter.
    public static int DecodeThreads(int physicalCores)
        => System.Math.Clamp(physicalCores, 1, 16);
}
```

- [ ] **Step 4: Run the tests to confirm they pass (green).**

```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj --filter WhisperTuningTests
```
Expected: PASS (all WhisperTuningTests cases). Then run the **full** suite to confirm no regressions:
```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj
```
Expected: all green (523 + the new cases).

- [ ] **Step 5: Commit.**

```bash
git add windows/JVoice.Core/Policy/WhisperTuning.cs windows/JVoice.Tests/WhisperTuningTests.cs
git commit -m "feat(win): add pure WhisperTuning policies (audio_ctx sizing + decode threads)"
```

---

### Task 2: Thread `EngineTuning` through the engine (no-op defaults)

Add an options record and apply the three levers in the engine. **Defaults reproduce today's behavior exactly**, so this task changes no runtime behavior and keeps all tests green — it just creates the seam the bench and the later adoption tasks use.

**Files:**
- Create: `windows/JVoice.App/Whisper/EngineTuning.cs`
- Modify: `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`
- Modify: `windows/tools/whisper-smoke/whisper-smoke.csproj` (link the new file)

**Interfaces:**
- Consumes: `JVoice.Core.WhisperTuning.AudioContextForSamples(int)` (Task 1).
- Produces: `internal sealed record EngineTuning(bool UseFlashAttention, bool AdaptiveAudioContext, int? FixedAudioContext, int? Threads)` with `EngineTuning.Default`; `WhisperNetTranscriptionEngine` ctor gains a trailing optional `EngineTuning? tuning = null`.

- [ ] **Step 1: Create the options record (all defaults = current behavior).**

Create `windows/JVoice.App/Whisper/EngineTuning.cs`:

```csharp
namespace JVoice.App.Whisper;

/// Decode-time tuning knobs for the whisper engine. The Default values reproduce the
/// pre-tuning behavior (no flash, full audio context, whisper's own thread default) so
/// existing call sites are unchanged; the bench overrides them per run to measure, and the
/// later speed-plan tasks flip individual Default fields once a lever is measured to help.
internal sealed record EngineTuning(
    bool UseFlashAttention,   // factory-level flash attention (WhisperFactoryOptions.UseFlashAttention)
    bool AdaptiveAudioContext,// size audio_ctx per clip via WhisperTuning (ignored if FixedAudioContext set)
    int? FixedAudioContext,   // non-null forces this audio_ctx (bench A/B only); null = use the policy/none
    int? Threads)             // null = leave whisper's default (min(4, logical)); else WithThreads(n)
{
    /// The single committed app default. Speed-plan tasks edit THIS to adopt a measured win:
    ///   Task 4 → AdaptiveAudioContext: true
    ///   Task 5 → Threads: WhisperTuning.DecodeThreads(CpuInfo.PhysicalCoreCount)
    ///   Task 6 → UseFlashAttention: <measured winner on the GPU path>
    public static EngineTuning Default { get; } = new(
        UseFlashAttention: false,
        AdaptiveAudioContext: false,
        FixedAudioContext: null,
        Threads: null);
}
```

- [ ] **Step 2: Accept the tuning in the engine ctor.**

In `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`, add a `using` and a field, and extend the constructor. Find the field block near the top (after `private readonly WhisperModelStore _store;`) and add:

```csharp
    private readonly EngineTuning _tuning;
```

Add `using JVoice.Core;` to the using block at the top (for `WhisperTuning`). Then change the constructor signature from:

```csharp
    public WhisperNetTranscriptionEngine(
        WhisperModelOption model,
        TranscriptionLanguage language,
        IReadOnlyList<string> vocabulary,
        bool useVocabularyPrompt,
        WhisperModelStore store)
    {
        _model = model;
        _language = language;
        _vocabulary = vocabulary ?? Array.Empty<string>();
        _useVocabularyPrompt = useVocabularyPrompt;
        _store = store ?? throw new ArgumentNullException(nameof(store));
    }
```

to (add the trailing optional param + one assignment):

```csharp
    public WhisperNetTranscriptionEngine(
        WhisperModelOption model,
        TranscriptionLanguage language,
        IReadOnlyList<string> vocabulary,
        bool useVocabularyPrompt,
        WhisperModelStore store,
        EngineTuning? tuning = null)
    {
        _model = model;
        _language = language;
        _vocabulary = vocabulary ?? Array.Empty<string>();
        _useVocabularyPrompt = useVocabularyPrompt;
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _tuning = tuning ?? EngineTuning.Default;
    }
```

(`VoiceCoordinator.MakeEngine` and the tools call the ctor without the new arg, so they keep compiling and get `EngineTuning.Default`.)

- [ ] **Step 3: Apply flash attention at factory load.**

In the same file, change `PerformLoadAsync`'s factory build from:

```csharp
            return WhisperFactory.FromPath(modelPath);
```

to:

```csharp
            bool useFlash = _tuning.UseFlashAttention;
#if JVOICE_CPU
            useFlash = false; // flash attention degrades CPU decode (whisper.cpp PR #2152)
#endif
            return WhisperFactory.FromPath(
                modelPath, new WhisperFactoryOptions { UseFlashAttention = useFlash });
```

(`WhisperFactoryOptions` is in the already-imported `Whisper.net` namespace.)

- [ ] **Step 4: Apply threads + per-clip audio_ctx on the decode builder.**

In `DecodeSamplesAsync`, find:

```csharp
        var builder = factory.CreateBuilder()
            .WithLanguage(_language.WhisperCode());   // fixed language, no auto-detect

        builder = ApplyTemperatureFallback(builder);

        if (promptText is { Length: > 0 })
            builder = builder.WithPrompt(promptText);
```

and insert the two lever blocks between `ApplyTemperatureFallback` and the prompt:

```csharp
        var builder = factory.CreateBuilder()
            .WithLanguage(_language.WhisperCode());   // fixed language, no auto-detect

        builder = ApplyTemperatureFallback(builder);

        // Decode threads — only set when configured (null = whisper's own min(4, logical) default).
        if (_tuning.Threads is int threads)
            builder = builder.WithThreads(threads);

        // Per-clip encoder context: a short utterance doesn't need the full 30 s window, so a
        // smaller audio_ctx skips wasted encoder work. FixedAudioContext (bench A/B) wins; else
        // the adaptive policy; else leave whisper's full default. Sized from THIS decode's sample
        // count, so both the whole-file and the 15–25 s streaming-chunk paths are covered.
        int? audioCtx = _tuning.FixedAudioContext
            ?? (_tuning.AdaptiveAudioContext
                ? WhisperTuning.AudioContextForSamples(samples.Length)
                : null);
        if (audioCtx is int ctx)
            builder = builder.WithAudioContextSize(ctx);

        if (promptText is { Length: > 0 })
            builder = builder.WithPrompt(promptText);
```

- [ ] **Step 5: Keep whisper-smoke compiling (it links the engine source).**

In `windows/tools/whisper-smoke/whisper-smoke.csproj`, inside the `<ItemGroup>` that links the engine `.cs` files, add:

```xml
    <Compile Include="..\..\JVoice.App\Whisper\EngineTuning.cs" Link="Whisper\EngineTuning.cs" />
```

- [ ] **Step 6: Build + test (no behavior change expected).**

```bash
dotnet build windows/JVoice.sln -c Release
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj
```
Expected: 0 errors; all tests green (the engine path is unchanged because `EngineTuning.Default` is all-no-op).

- [ ] **Step 7: On-device smoke (engine still works through the new seam).** Generate a quick clip (PowerShell), then bench it with the existing flags. Quit any running tray app first; run **non-elevated**.

```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SetOutputToWaveFile("$env:TEMP\jv-short.wav",$fmt); $s.Speak('Testing JVoice transcription speed on Windows today.'); $s.Dispose()
```
```bash
windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe --bench "$TEMP/jv-short.wav" --model large
```
Expected: prints `runtime: whisper.cpp (Vulkan)`, a `transcribe: …s` line, and a non-empty `raw:`/`processed:` transcript. (Exact path may be `%TEMP%`; in Git Bash use `"$(cygpath "$TEMP")/jv-short.wav"` or just pass the Windows path.) This proves the new options seam doesn't break the real decode.

- [ ] **Step 8: Commit.**

```bash
git add windows/JVoice.App/Whisper/EngineTuning.cs windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs windows/tools/whisper-smoke/whisper-smoke.csproj
git commit -m "feat(win): thread EngineTuning (flash/threads/audio_ctx) through the whisper engine (no-op defaults)"
```

---

### Task 3: Instrument `--bench` for measurement

Turn the bench into a real measurement tool: repeatable medians, the three lever toggles, and the ability to force/observe a backend. This is the instrument every adoption task uses.

**Files:**
- Modify: `windows/JVoice.App/Whisper/WhisperRuntime.cs`
- Modify: `windows/JVoice.App/Whisper/BenchRunner.cs`

**Interfaces:**
- Consumes: `EngineTuning` (Task 2), `Whisper.net.LibraryLoader.RuntimeOptions`/`RuntimeLibrary`, `Whisper.net.Logger.LogProvider`.
- Produces: new `WhisperRuntime.ForceRuntimeOrder(params RuntimeLibrary[])` and `WhisperRuntime.EnableDebugLogging()`; bench flags `--iters N`, `--flash on|off`, `--threads N`, `--audio-ctx N|auto|off`, `--runtime auto|cuda|cuda12|vulkan|cpu`, `--log-runtime`.

- [ ] **Step 1: Add runtime helpers.**

In `windows/JVoice.App/Whisper/WhisperRuntime.cs`, add `using System.Linq;` and `using Whisper.net.Logger;` (it already has `using Whisper.net.LibraryLoader;`), then add two methods to the class:

```csharp
    /// Force the native-runtime probe order BEFORE the first WhisperFactory is created.
    /// Pass a single library (e.g. RuntimeLibrary.Cuda) to make a missing backend a HARD
    /// failure (FileNotFoundException) instead of a silent fallback — used by `--bench --runtime`.
    public static void ForceRuntimeOrder(params RuntimeLibrary[] order)
        => RuntimeOptions.RuntimeLibraryOrder = order.ToList();

    /// Stream whisper.cpp's own debug log to the console (e.g. "cudaGetDeviceCount returned 35 …"),
    /// so a forced-CUDA run prints exactly why a backend was rejected.
    public static void EnableDebugLogging()
        => LogProvider.AddConsoleLogging(WhisperLogLevel.Debug);
```

- [ ] **Step 2: Parse the new bench flags.** In `windows/JVoice.App/Whisper/BenchRunner.cs`, in `RunAsync`, after the existing `useDecoderPrompt` line and before the header `Console.WriteLine`, add flag parsing:

```csharp
        // ---- speed-measurement flags (speed plan 2026-06-27) ----
        int iters = ReadIntFlag(arguments, "--iters", 3);

        bool? flash = null;
        int fi = Array.IndexOf(arguments, "--flash");
        if (fi >= 0 && arguments.Length > fi + 1)
            flash = arguments[fi + 1] is "on" or "true" or "1";

        int? threads = null;
        int ti = Array.IndexOf(arguments, "--threads");
        if (ti >= 0 && arguments.Length > ti + 1 && int.TryParse(arguments[ti + 1], out int tparsed))
            threads = tparsed;

        // --audio-ctx: "off" (default, full window) | "auto" (per-clip policy) | <int> (fixed)
        bool adaptiveCtx = false;
        int? fixedCtx = null;
        int ai = Array.IndexOf(arguments, "--audio-ctx");
        if (ai >= 0 && arguments.Length > ai + 1)
        {
            string v = arguments[ai + 1];
            if (v == "auto") adaptiveCtx = true;
            else if (v != "off" && int.TryParse(v, out int cparsed)) fixedCtx = cparsed;
        }

        if (arguments.Contains("--log-runtime")) WhisperRuntime.EnableDebugLogging();

        int ri = Array.IndexOf(arguments, "--runtime");
        if (ri >= 0 && arguments.Length > ri + 1)
        {
            switch (arguments[ri + 1])
            {
                case "auto": break; // default probe order
                case "cuda": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda); break;
                case "cuda12": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda12); break;
                case "cuda-any": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda, RuntimeLibrary.Cuda12); break;
                case "vulkan": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Vulkan); break;
                case "cpu": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cpu); break;
                default:
                    Console.Error.WriteLine($"unknown runtime {arguments[ri + 1]}");
                    return 64;
            }
        }

        var tuning = new EngineTuning(
            UseFlashAttention: flash ?? false,
            AdaptiveAudioContext: adaptiveCtx,
            FixedAudioContext: fixedCtx,
            Threads: threads);
```

Add `using Whisper.net.LibraryLoader;` at the top of `BenchRunner.cs`. Add this small helper method to the class:

```csharp
    private static int ReadIntFlag(string[] args, string name, int fallback)
    {
        int i = Array.IndexOf(args, name);
        return (i >= 0 && args.Length > i + 1 && int.TryParse(args[i + 1], out int v)) ? v : fallback;
    }
```

- [ ] **Step 3: Pass the tuning to the engine + echo it.** Change the engine construction line:

```csharp
        var engine = new WhisperNetTranscriptionEngine(
            model, language, vocabulary, useDecoderPrompt, store);
```

to:

```csharp
        var engine = new WhisperNetTranscriptionEngine(
            model, language, vocabulary, useDecoderPrompt, store, tuning);
```

And extend the existing header `Console.WriteLine` (the `model: … decoderPrompt: …` line) by appending a second line right after it:

```csharp
        Console.WriteLine(
            $"tuning: flash={(tuning.UseFlashAttention ? "on" : "off")}  " +
            $"threads={(tuning.Threads?.ToString() ?? "default")}  " +
            $"audio_ctx={(tuning.FixedAudioContext?.ToString() ?? (tuning.AdaptiveAudioContext ? "auto" : "full"))}  " +
            $"iters={iters}");
```

- [ ] **Step 4: Warm-up + median/min timing.** Replace the single-shot timed block in the non-`--stream` branch:

```csharp
        try
        {
            var sw = Stopwatch.StartNew();
            string raw = await engine.TranscribeAsync(audioPath, CancellationToken.None);
            sw.Stop();
            Console.WriteLine($"transcribe:   {sw.Elapsed.TotalSeconds:0.00}s");
            Console.WriteLine($"raw:       \"{raw}\"");
            var userDict = TextProcessor.BuildUserDictionary(vocabulary);
            string processed = TextProcessor.Process(
                raw, ToneStyle.Casual, userDict, removeFillerWords: false, vocabulary: vocabulary);
            Console.WriteLine($"processed: \"{processed}\"");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"transcription failed: {ex.Message}");
            return 1;
        }
```

with:

```csharp
        try
        {
            // One warm-up decode (excluded) so steady-state timing isn't polluted by lazy init.
            string raw = await engine.TranscribeAsync(audioPath, CancellationToken.None);

            var times = new List<double>();
            for (int i = 0; i < Math.Max(1, iters); i++)
            {
                var sw = Stopwatch.StartNew();
                raw = await engine.TranscribeAsync(audioPath, CancellationToken.None);
                sw.Stop();
                times.Add(sw.Elapsed.TotalSeconds);
            }
            times.Sort();
            double median = times[times.Count / 2];
            Console.WriteLine(
                $"transcribe: median={median:0.000}s  min={times[0]:0.000}s  " +
                $"max={times[^1]:0.000}s  (n={times.Count}, warm-up excluded)");
            Console.WriteLine($"raw:       \"{raw}\"");
            var userDict = TextProcessor.BuildUserDictionary(vocabulary);
            string processed = TextProcessor.Process(
                raw, ToneStyle.Casual, userDict, removeFillerWords: false, vocabulary: vocabulary);
            Console.WriteLine($"processed: \"{processed}\"");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"transcription failed: {ex.Message}");
            return 1;
        }
```

Ensure `using System.Collections.Generic;` is available (it is via implicit usings in the App project for most types, but `List<double>` needs it — add `using System.Collections.Generic;` to `BenchRunner.cs` if the compiler flags it).

- [ ] **Step 5: Update the usage string.** Change the `usage:` line in `RunAsync` to include the new flags:

```csharp
            Console.Error.WriteLine(
                "usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--lang en|ro] " +
                "[--vocab \"Word1,Word2\"] [--stream] [--no-prompt] " +
                "[--iters N] [--flash on|off] [--threads N] [--audio-ctx off|auto|N] " +
                "[--runtime auto|cuda|cuda12|cuda-any|vulkan|cpu] [--log-runtime]");
```

- [ ] **Step 6: Build + verify the instrument.** Quit the tray app; build; then run two bench invocations and confirm the new output + that forcing a backend works.

```bash
dotnet build windows/JVoice.sln -c Release
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
# (a) default auto runtime, 5 iters:
"$WIN_EXE" --bench "$TEMP/jv-short.wav" --model large --iters 5
# (b) force CUDA to OBSERVE the failure reason (proves the silent fallback is the CUDA-toolkit gap):
"$WIN_EXE" --bench "$TEMP/jv-short.wav" --model large --runtime cuda --log-runtime
```
Expected (a): a `tuning:` line, a `transcribe: median=… min=… max=…` line, runtime `whisper.cpp (Vulkan)`. Expected (b): with CUDA forced and no CUDA Toolkit installed, the run **fails loudly** (engine-unavailable, exit 70) and `--log-runtime` prints whisper.cpp's reason (e.g. a `cudaGetDeviceCount`/insufficient-driver message). This confirms the diagnosis and that `--runtime` works.

- [ ] **Step 7: Commit.**

```bash
git add windows/JVoice.App/Whisper/WhisperRuntime.cs windows/JVoice.App/Whisper/BenchRunner.cs
git commit -m "feat(win): instrument --bench with iters/median, flash/threads/audio_ctx toggles, and runtime forcing"
```

---

### Task 4: Baseline + adopt per-clip `audio_ctx` (the primary current-backend win)

Measure the baseline, then prove the adaptive `audio_ctx` policy is faster on short/medium clips with **no accuracy change**, then flip its default on.

**Files:**
- Modify: `windows/JVoice.App/Whisper/EngineTuning.cs` (flip one default)

- [ ] **Step 1: Generate a representative clip set.** (PowerShell; produces short/medium/long WAVs.) These approximate real dictation lengths.

```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
function Say($file,$text){ $s.SetOutputToWaveFile($file,$fmt); $s.Speak($text); }
Say("$env:TEMP\jv-3s.wav",  'Open the settings panel now.')
Say("$env:TEMP\jv-12s.wav", 'This is a medium length dictation that lasts around twelve seconds so the encoder has a realistic amount of speech to process for a typical sentence or two.')
Say("$env:TEMP\jv-35s.wav", ('JVoice transcribes speech on device using Whisper. ' * 8))
$s.Dispose()
```
Also, **if available**, copy any of David's real captured clips from `%APPDATA%\JVoice\capture\` (created when the app runs with `JVOICE_KEEP_WAV=1`, see `HANDOFF-WINDOWS.md` §7 #24) into the test set — real low-SNR mic audio is the truest accuracy check.

- [ ] **Step 2: Record the baseline (audio_ctx = full).** Run each clip; capture median time + the `raw:` transcript.

```bash
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
for c in jv-3s jv-12s jv-35s; do
  echo "=== $c (full) ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --audio-ctx off --iters 5
done
```
Record, per clip: `median` seconds and the exact `raw:` string. This is the baseline.

- [ ] **Step 3: Measure adaptive audio_ctx.** Same clips, `--audio-ctx auto`:

```bash
for c in jv-3s jv-12s jv-35s; do
  echo "=== $c (auto) ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --audio-ctx auto --iters 5
done
```
**Pass criteria:** the 3 s and 12 s clips show a **lower median** than baseline (expect a meaningful drop — short clips benefit most), the 35 s clip is unchanged (policy returns null → full context), and **every `raw:` transcript is identical** (or only trivially different in punctuation/casing) to the baseline. The `--bench` already prints `raw:`; diff them by eye / paste both.
- If a transcript materially changes or drops words on any clip, the policy is too aggressive — do **not** adopt; instead raise `WhisperTuning.MinAudioContext` (e.g. to 1024) in Task 1, re-test, and re-run its unit tests. (768 is the maintainer-recommended floor and is not expected to drop words.)

- [ ] **Step 4: Adopt — flip the default.** Once the pass criteria hold, edit `windows/JVoice.App/Whisper/EngineTuning.cs`, changing `AdaptiveAudioContext: false` to `true` and appending the measured numbers in the comment:

```csharp
    public static EngineTuning Default { get; } = new(
        UseFlashAttention: false,
        AdaptiveAudioContext: true,   // adopted 2026-06-27: <clip>:<full>s → <auto>s, transcripts identical
        FixedAudioContext: null,
        Threads: null);
```

- [ ] **Step 5: Confirm the adopted default (no flag needed now).**

```bash
dotnet build windows/JVoice.sln -c Release
"$WIN_EXE" --bench "$TEMP/jv-3s.wav" --model large --iters 5   # audio_ctx should report "auto"
```
Expected: the `tuning:` line shows `audio_ctx=auto` with **no** `--audio-ctx` flag, and the median matches the Step 3 "auto" number. Run the full test suite — still green (pure logic only; no test asserts the App default):
```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj
```

- [ ] **Step 6: Commit.**

```bash
git add windows/JVoice.App/Whisper/EngineTuning.cs
git commit -m "perf(win): default to per-clip audio_ctx sizing (faster short-clip decode, transcripts unchanged)"
```

---

### Task 5: Adopt the decode thread count (CPU-build win)

Add physical-core detection and set `WithThreads` so the CPU-fallback build (the default download for everyone) uses all physical cores instead of whisper's `min(4, logical)`. Measure on the CPU runtime (where it matters); GPU is unaffected.

**Files:**
- Create: `windows/JVoice.App/Platform/System/CpuInfo.cs`
- Modify: `windows/JVoice.App/Whisper/EngineTuning.cs`
- Modify: `windows/tools/whisper-smoke/whisper-smoke.csproj` (link the new file)

**Interfaces:**
- Consumes: `JVoice.Core.WhisperTuning.DecodeThreads(int)` (Task 1).
- Produces: `JVoice.App.Platform.CpuInfo.PhysicalCoreCount` (int).

- [ ] **Step 1: Add the physical-core helper.**

Create `windows/JVoice.App/Platform/System/CpuInfo.cs`:

```csharp
using System.Runtime.InteropServices;

namespace JVoice.App.Platform;

/// Physical CPU core count (not logical/hyperthreaded). whisper.cpp throughput peaks at the
/// physical core count and regresses past it (Discussion #403), and .NET only exposes the
/// LOGICAL count, so we read the topology from Win32. Falls back to the logical count on any
/// failure. Computed once.
internal static class CpuInfo
{
    public static int PhysicalCoreCount { get; } = Compute();

    private const int RelationProcessorCore = 0;

    private static int Compute()
    {
        try
        {
            uint len = 0;
            GetLogicalProcessorInformation(IntPtr.Zero, ref len);
            if (len == 0) return Environment.ProcessorCount;

            int size = Marshal.SizeOf<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>();
            int count = (int)(len / size);
            var buffer = new SYSTEM_LOGICAL_PROCESSOR_INFORMATION[count];
            if (!GetLogicalProcessorInformation(buffer, ref len))
                return Environment.ProcessorCount;

            int cores = 0;
            for (int i = 0; i < count; i++)
                if (buffer[i].Relationship == RelationProcessorCore) cores++;
            return cores > 0 ? cores : Environment.ProcessorCount;
        }
        catch
        {
            return Environment.ProcessorCount;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEM_LOGICAL_PROCESSOR_INFORMATION
    {
        public UIntPtr ProcessorMask;
        public int Relationship;       // LOGICAL_PROCESSOR_RELATIONSHIP
        public ulong Reserved0;        // union payload (largest member is 16 bytes total with the
        public ulong Reserved1;        // fields above accounting for padding; only Relationship is read)
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformation(
        IntPtr buffer, ref uint returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformation(
        [Out] SYSTEM_LOGICAL_PROCESSOR_INFORMATION[] buffer, ref uint returnLength);
}
```

- [ ] **Step 2: Use it in the engine default.** In `windows/JVoice.App/Whisper/EngineTuning.cs`, add `using JVoice.App.Platform;` and `using JVoice.Core;` at the top, and change `Threads: null` to:

```csharp
        Threads: WhisperTuning.DecodeThreads(CpuInfo.PhysicalCoreCount), // adopted 2026-06-27
```

- [ ] **Step 3: Keep whisper-smoke compiling.** In `windows/tools/whisper-smoke/whisper-smoke.csproj`, add another link line next to the `EngineTuning.cs` one:

```xml
    <Compile Include="..\..\JVoice.App\Platform\System\CpuInfo.cs" Link="Platform\CpuInfo.cs" />
```

- [ ] **Step 4: Build, then measure threads on the CPU runtime.** (Threads matter on CPU, not GPU. Force the CPU backend to isolate the effect.)

```bash
dotnet build windows/JVoice.sln -c Release
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
# whisper default (min(4,logical)=4) vs physical cores (6 on the i5-12400), CPU backend:
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --runtime cpu --threads 4 --iters 5
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --runtime cpu --threads 6 --iters 5
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --runtime cpu --threads 8 --iters 5
```
**Pass criteria:** `--threads 6` (physical cores) is faster than `--threads 4`, and `--threads 8` is not better than 6 (confirming the physical-core sweet spot). The committed default now reports `threads=6` automatically:
```bash
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --runtime cpu --iters 5   # tuning: threads=6
```
Also confirm the GPU path is unharmed:
```bash
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --iters 5   # Vulkan; median ≈ unchanged vs Task 4
```

- [ ] **Step 5: Test + commit.**

```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj   # still green
git add windows/JVoice.App/Platform/System/CpuInfo.cs windows/JVoice.App/Whisper/EngineTuning.cs windows/tools/whisper-smoke/whisper-smoke.csproj
git commit -m "perf(win): set whisper decode threads to physical core count (CPU-build speedup)"
```

---

### Task 6: Flash attention — measure on the GPU path, adopt the winner, force OFF on CPU

Flash attention is a clean ~1.3–1.7× encoder win on **CUDA**, a **coin-flip on Vulkan** (fast only with NVIDIA `coopmat2`; otherwise it offloads attention to CPU and regresses), and a **regression on CPU**. So: measure on David's actual Vulkan backend, adopt only if it helps, and hard-guard it off in the CPU publish flavor.

**Files:**
- Modify: `windows/JVoice.App/JVoice.App.csproj` (define `JVOICE_CPU` for the cpu flavor)
- Modify: `windows/JVoice.App/Whisper/EngineTuning.cs` (adopt iff measured to help)

- [ ] **Step 1: Define the CPU-flavor compile constant.** In `windows/JVoice.App/JVoice.App.csproj`, find the cpu-flavor PropertyGroup:

```xml
  <PropertyGroup Condition="'$(JVoiceFlavor)' == 'cpu'">
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
  </PropertyGroup>
```
and add the constant so the engine's `#if JVOICE_CPU` (Task 2 Step 3) forces flash off in the CPU build:

```xml
  <PropertyGroup Condition="'$(JVoiceFlavor)' == 'cpu'">
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
    <DefineConstants>$(DefineConstants);JVOICE_CPU</DefineConstants>
  </PropertyGroup>
```

- [ ] **Step 2: Measure flash on/off on the live Vulkan backend.** (Build a fresh exe; the dev build loads Vulkan.)

```bash
dotnet build windows/JVoice.sln -c Release
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
for c in jv-3s jv-12s jv-35s; do
  echo "=== $c flash OFF ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --flash off --iters 5
  echo "=== $c flash ON  ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --flash on  --iters 5
done
```
Note: this stacks on the already-adopted adaptive audio_ctx (that's fine — measure the real, combined config). Record median flash-off vs flash-on per clip, and compare `raw:` transcripts.

**Decision:**
- **If flash-on is faster on Vulkan (David's 3060 Ti has a coopmat2-capable driver) AND transcripts are unchanged** → adopt: set `UseFlashAttention: true` in `EngineTuning.Default` (the `JVOICE_CPU` guard keeps the CPU build safe).
- **If flash-on is the same or slower on Vulkan** (no coopmat2 fast path) → **do not adopt**; keep `UseFlashAttention: false`. Record the measurement in the results doc and note FA should be enabled only when the CUDA backend is used (Task 7).
- **If transcripts degrade** (watch for the documented English-minor / other-language drift) → do not adopt.

- [ ] **Step 3: Apply the decision.** If adopting, edit `windows/JVoice.App/Whisper/EngineTuning.cs`:

```csharp
        UseFlashAttention: true,   // adopted 2026-06-27: Vulkan flash <off>s → <on>s, transcripts identical
```
Then rebuild and confirm the default reports `flash=on`:
```bash
dotnet build windows/JVoice.sln -c Release
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --iters 5   # tuning: flash=on
```
If **not** adopting, leave the field `false` and add a one-line comment recording the null result.

- [ ] **Step 4: Verify the CPU build forces flash off (regardless of the default).** Publish the cpu flavor to a throwaway dir and bench it — flash must read `off` even if the Default is `on`.

```bash
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=cpu \
  -p:PublishSingleFile=true -p:SelfContained=true -p:PublishTrimmed=false -o out/cpu-test
out/cpu-test/JVoice.exe --bench "$TEMP/jv-12s.wav" --model large --iters 3
```
Expected: `runtime: whisper.cpp (Cpu)` and the `tuning:` line shows `flash=off` (the `#if JVOICE_CPU` guard fired). Delete `out/cpu-test` afterward.

- [ ] **Step 5: Test + commit.**

```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj   # still green
git add windows/JVoice.App/JVoice.App.csproj windows/JVoice.App/Whisper/EngineTuning.cs
git commit -m "perf(win): measure flash attention on Vulkan + force it off in the CPU build (JVOICE_CPU guard)"
```

---

### Task 7 (OPTIONAL): Enable & measure the real CUDA backend on the 3060 Ti

CUDA is the strongest single GPU lever (~20–30% encode over Vulkan + a clean flash-attention win), but it requires CUDA Toolkit/redist DLLs the app doesn't ship — so it's **opt-in**, and whether to ship a CUDA distribution is **David's call** (it would bloat the GPU download). This task makes CUDA *measurable* on the dev box and records the delta so the distribution decision is data-driven. **Do not adopt CUDA as the default runtime; keep Vulkan as the zero-install default.**

**Files:**
- Modify: `windows/JVoice.App/JVoice.App.csproj` (add conditional `Whisper.net.Runtime.Cuda12`)

- [ ] **Step 1: Add the CUDA 12 runtime package** (CUDA 12 is the more common driver/toolkit line than CUDA 13). In `windows/JVoice.App/JVoice.App.csproj`, in the conditional GPU-runtime `<ItemGroup Condition="'$(JVoiceFlavor)' != 'cpu'">`, add:

```xml
    <PackageReference Include="Whisper.net.Runtime.Cuda12" Version="1.9.1" />
```
(Also add it to `windows/tools/whisper-smoke/whisper-smoke.csproj` if you want to bench CUDA via whisper-smoke.)

- [ ] **Step 2: Provide the CUDA 12 runtime DLLs.** The package does **not** bundle them. Either install the **CUDA Toolkit 12.4+** (which puts `cudart64_12.dll`, `cublas64_12.dll`, `cublasLt64_12.dll` on PATH), or copy those three redistributable DLLs next to `JVoice.exe`. Ensure the NVIDIA driver is **≥ 551.61**. (`cublasLt64_12.dll` is large, ~300–500 MB — this is the distribution-cost crux.)

- [ ] **Step 3: Force + confirm CUDA loads.**

```bash
dotnet build windows/JVoice.sln -c Release
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
"$WIN_EXE" --bench "$TEMP/jv-12s.wav" --model large --runtime cuda12 --log-runtime --iters 5
```
Expected: `runtime: whisper.cpp (Cuda12)` (not Vulkan). If it still fails, `--log-runtime` prints the exact missing-DLL/driver reason; resolve and retry.

- [ ] **Step 4: Measure CUDA (+flash) vs Vulkan (+ adopted config).**

```bash
for c in jv-3s jv-12s jv-35s; do
  echo "=== $c Vulkan ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --runtime vulkan --iters 5
  echo "=== $c CUDA+FA ==="; "$WIN_EXE" --bench "$TEMP/$c.wav" --model large --runtime cuda12 --flash on --iters 5
done
```
Record the CUDA-vs-Vulkan median deltas per clip and confirm transcripts match.

- [ ] **Step 5: Decision (David-gated, log it, do not auto-ship).** Write the measured delta into the results doc (Task 9). Recommendation framing: if CUDA is materially faster *and* David wants a CUDA distribution, a future task adds a third publish flavor (`gpu-cuda`) that bundles the three CUDA 12 redist DLLs; otherwise document "advanced users can install the CUDA 12 Toolkit to unlock the CUDA backend automatically" and keep Vulkan the default. **Either way, do not change the default runtime order in committed code** (leave Whisper.net's auto-probe; it already prefers CUDA when loadable). If David does not want CUDA shipped, you may revert the `Cuda12` package reference (it adds native payload to the GPU build) — note the choice in the commit.

- [ ] **Step 6: Commit (only the package-ref + any kept config).**

```bash
git add windows/JVoice.App/JVoice.App.csproj
git commit -m "feat(win): add optional Whisper.net.Runtime.Cuda12 so the CUDA backend can load when the toolkit is present"
```

---

### Task 8 (OPTIONAL, lowest priority): Cap the temperature fallback

`WithTemperatureInc(0.2)` lets whisper re-decode a clip that fails its quality gates at temp 0→0.2→…→1.0 — up to ~6 full passes — a worst-case latency spike on hard clips (clean dictation never triggers it). The app already has its own recovery layer (`RepetitionGuard`/`RegurgitationRecovery`), so capping the fallback is a defensible *worst-case* latency trade. It **diverges from the macOS parity** (`temperatureFallbackCount = 2`), so it's optional and must be logged.

**Files:**
- Modify: `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs` (only if adopted)

- [ ] **Step 1: Measure the worst case.** Find/synthesize a clip that triggers fallback (very noisy or near-silent), then compare:

```bash
WIN_EXE="windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe"
# Baseline (temp_inc 0.2 today) vs a one-off build with WithTemperatureInc(0f).
```
Since `temperature_inc` isn't a bench flag, to A/B it temporarily change `ApplyTemperatureFallback` to `.WithTemperatureInc(0.0f)`, rebuild, and bench the hard clip vs the baseline build. Measure the median on the hard clip and confirm clean clips are unaffected (they never fell back, so their time is identical).

- [ ] **Step 2: Decide.** Only adopt if the worst-case improvement is real **and** the cap doesn't worsen accuracy on the hard clip beyond what the app's own recovery handles. If adopting, change `ApplyTemperatureFallback` to:

```csharp
    private static WhisperProcessorBuilder ApplyTemperatureFallback(WhisperProcessorBuilder builder)
        => builder
            .WithTemperature(0.0f)
            .WithTemperatureInc(0.0f); // speed plan 2026-06-27: cap whisper's internal multi-pass
                                       // fallback; the app's RegurgitationRecovery is our recovery
                                       // layer. DIVERGES from macOS temperatureFallbackCount=2.
```
If not adopting, revert and record the null result. (Default expectation: likely **not worth it** for a dictation app where most clips are clean — but the lever is documented.)

- [ ] **Step 3: Test + commit (only if adopted).**

```bash
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj
git add windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs
git commit -m "perf(win): cap whisper temperature fallback to bound worst-case decode latency"
```

---

### Task 9: Record results + update the docs (zero-context handoff)

Capture the measured numbers and update the two living docs so the next session knows what's tuned and why.

**Files:**
- Create: `docs/superpowers/plans/2026-06-27-windows-whisper-speed-results.md`
- Modify: `docs/HANDOFF-WINDOWS.md` (add a §7 entry)
- Modify: `windows/JVoice.App/Whisper/CLAUDE.md` (record the tuned defaults + FA conditionality)

- [ ] **Step 1: Write the results doc.** Create `docs/superpowers/plans/2026-06-27-windows-whisper-speed-results.md` with: the dev-machine spec, the loaded runtime, the model, and a table per clip of **median seconds before → after** for each adopted lever (audio_ctx, threads, flash if adopted, CUDA if measured), plus the adopted `EngineTuning.Default` values and any null results (levers measured but not adopted, with the reason). Include the exact bench commands used so the numbers are reproducible.

- [ ] **Step 2: Add a HANDOFF entry.** In `docs/HANDOFF-WINDOWS.md` §7, add a new numbered deviation entry (next free number, e.g. **#31**) summarizing: the adopted tuning (per-clip audio_ctx; physical-core threads; flash on/off per measurement), that the work is in the **App engine layer + a new pure `JVoice.Core/Policy/WhisperTuning.cs`** (brain untouched, parity intact), that the CPU build forces flash off via `JVOICE_CPU`, the CUDA-fallback root cause + that CUDA stays opt-in, and the new `--bench` flags. Reference this plan + the results doc. Update the test count if it grew.

- [ ] **Step 3: Update the Whisper area brief.** In `windows/JVoice.App/Whisper/CLAUDE.md`, add a short "Tuning" note: the engine applies `EngineTuning.Default` (per-clip `audio_ctx` via `WhisperTuning`, `WithThreads` = physical cores, flash attention = `<adopted value>`), flash is forced off in the `cpu` flavor (`JVOICE_CPU`), and the runtime is auto-selected (Vulkan on the dev box; CUDA only when the toolkit is present). Note the `--bench` measurement flags.

- [ ] **Step 4: Final full verification.**

```bash
dotnet build windows/JVoice.sln -c Release          # 0 errors
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj # all green
```

- [ ] **Step 5: Commit.**

```bash
git add docs/superpowers/plans/2026-06-27-windows-whisper-speed-results.md docs/HANDOFF-WINDOWS.md windows/JVoice.App/Whisper/CLAUDE.md
git commit -m "docs(win): record whisper speed-tuning results + handoff/area updates"
```

---

## Self-Review (author's checklist — already applied)

- **Spec coverage:** every lever from the research (audio_ctx, threads, flash, CUDA, temperature-fallback) maps to a task; the rejected levers (q4, single-segment, beam, VAD) are documented with reasons in Background. The measurement instrument (Task 3) precedes every adoption task (4–8), so each "make it faster" claim is backed by a before/after median on David's actual machine.
- **Type/name consistency:** `WhisperTuning.AudioContextFor/AudioContextForSamples/DecodeThreads` and the constants are defined in Task 1 and used verbatim in Tasks 2/5. `EngineTuning(UseFlashAttention, AdaptiveAudioContext, FixedAudioContext, Threads)` is defined in Task 2 and constructed identically in Task 3's bench. `CpuInfo.PhysicalCoreCount`, `WhisperRuntime.ForceRuntimeOrder/EnableDebugLogging`, the `RuntimeLibrary` members, and `WhisperFactoryOptions.UseFlashAttention` are all confirmed against the pinned 1.9.1 assembly (see "API facts").
- **No placeholders:** every code step shows the actual code; every measurement step shows the exact command and the pass criterion. The only intentionally deferred values are the *measured numbers* (they come from David's hardware at execution time) — these are filled into `EngineTuning.Default` comments and the results doc as each task runs, which is the correct place for runtime-measured data.
- **Safety:** brain constants untouched; macOS sources untouched; CPU build flash-guarded; CUDA opt-in; no new network; defaults stay no-op until each lever is measured, so the suite is green throughout.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-27-windows-whisper-speed.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks. Note: Tasks 4–8 require on-device GPU runs on David's machine (they can't be done in a headless/CI sandbox), so those tasks are "measure on the dev box, then adopt"; Tasks 1–3 and 9 are fully automatable.
2. **Inline Execution** — execute in this session with checkpoints.

Which approach?
