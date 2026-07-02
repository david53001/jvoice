# Phase 2 — The Whisper speech engine (Whisper.net / whisper.cpp + GGML) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended — fresh subagent per task, review between tasks) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Read `2026-06-22-windows-port-00-overview.md` (the master plan) and `2026-06-22-windows-port-01-core-brain.md` (Phase 1) in full before executing this phase.** This phase consumes Phase 1's types verbatim — it cannot be built until Phase 1 is green.

**Goal:** Replace JVoice's Apple-only WhisperKit/CoreML speech engine with a Windows-native engine built on **Whisper.net** (managed bindings to **whisper.cpp**) running **GGML** models with **CUDA** GPU acceleration and a **CPU** fallback. Deliver:

- `WhisperNetTranscriptionEngine : ITranscriptionEngine` — loads a GGML model once (dedupe), prewarms, decodes whole files and `float[]` chunks, biases decoding with the user vocabulary prompt, recovers from prompt regurgitation, strips decoder artifacts, and exposes a streaming session.
- `WhisperModelStore` — locates/downloads/verifies GGML models under `%LOCALAPPDATA%\JVoice\models\` from Hugging Face on first use.
- `WhisperRuntime` — selects/loads the correct native runtime (CUDA on this RTX 3060 Ti dev machine, CPU fallback everywhere).
- A hidden `--bench` CLI switch (port of `BenchRunner.swift`) wired into the WPF App's startup so transcription speed and vocabulary biasing can be verified end-to-end without the UI.
- A standalone console smoke-test harness (`tools/whisper-smoke`) that transcribes a WAV without any WPF coupling — used by this phase's end-to-end verification.

**"Done" looks like:** from a clean checkout with Phase 1 green, an implementer can run `dotnet run --project windows/tools/whisper-smoke -- <wav>` (or `dotnet run --project windows/JVoice.App -- --bench <wav>` once the App project exists) and watch JVoice download `ggml-tiny.bin`, transcribe a known WAV on-device, print a non-empty transcript, demonstrate the vocabulary prompt produces non-empty output, and prove a >30 s clip is not truncated with timestamps off.

**Architecture:** The accuracy "brain" (`JVoice.Core`) is finished and frozen by Phase 1. This phase adds the *inference* layer that the brain drives:

```
ITranscriptionEngine (Core)  ◄── implemented by ──  WhisperNetTranscriptionEngine (App.Whisper)
   │                                                       │
   │ TranscribeAsync / MakeStreamingSessionAsync           │ uses
   ▼                                                       ▼
RegurgitationRecovery.Decode ──┐                    WhisperModelStore (download/locate/verify GGML)
RepetitionGuard.Scrub          │ (all Core)         WhisperRuntime (CUDA vs CPU native selection)
TextProcessor.StripDecoder…    │                    Whisper.net WhisperFactory/WhisperProcessor
VocabularyPrompt.Text          ┘
StreamingTranscriptionSession (Core)  ◄── chunk decode closure supplied by the engine
```

The engine is a faithful behavioral port of `Sources/JVoice/Services/TranscriptionManager.swift` (`WhisperKitTranscriptionEngine` + `WhisperModelLocator`) and `Sources/JVoice/Services/BenchRunner.swift`, **but** the inference backend is whisper.cpp/GGML, not WhisperKit/CoreML, and the two WhisperKit-1.0.0-specific workarounds are deliberately **not** ported (see Global Constraints below and overview §6.3).

**Tech Stack:** C# (latest) on **.NET 9** (`net9.0-windows` for `JVoice.App`; `net9.0` for the smoke-test console tool), **Whisper.net** + **Whisper.net.Runtime** (CPU) + **Whisper.net.Runtime.Cuda** (NVIDIA) + optionally **Whisper.net.Runtime.Vulkan** (cross-GPU, public builds), GGML models from Hugging Face `ggerganov/whisper.cpp`. Primary RID **win-x64**.

---

## Global Constraints

(From the overview — every task implicitly includes these. The engine-specific ones are copied here; do **not** re-derive them.)

- **.NET 9.** `JVoice.App` targets `net9.0-windows`; the smoke-test tool `windows/tools/whisper-smoke` targets `net9.0`. `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<LangVersion>latest</LangVersion>` (inherited from `windows/Directory.Build.props`, created in Phase 1). Primary RID **win-x64**; CUDA is x64-only (arm64 = CPU runtime only — handled by which runtime package is referenced, not by code).
- **Engine = Whisper.net (managed whisper.cpp bindings).** At execution time, resolve and **pin the exact current stable versions** of `Whisper.net`, `Whisper.net.Runtime` (CPU), `Whisper.net.Runtime.Cuda` (NVIDIA). Add `Whisper.net.Runtime.Vulkan` too (recommended for public builds covering non-NVIDIA GPUs; harmless on this dev machine — see Task 1 Step 6). Whisper.net auto-selects the best available native runtime at load; document the load order. **Pin every version** — never leave a floating version range.
- **Models = GGML files** named by `WhisperModelOption.GgmlFileName()` (from Phase 1): `ggml-tiny.bin`, `ggml-base.bin`, `ggml-small.bin`, `ggml-large-v3-turbo-q5_0.bin`. Downloaded on first use from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<file>`. Stored under `%LOCALAPPDATA%\JVoice\models\`. Completeness = file exists **AND** byte-size matches the pinned expected size **AND** (when a SHA-256 is recorded) the SHA-256 matches. Partial downloads go to a `<file>.part` temp and are atomically renamed on success only.
- **Whisper.net API names are version-sensitive.** This plan uses the conceptual API: `WhisperFactory.FromPath(modelPath)` → `factory.CreateBuilder().WithLanguage(code).WithPrompt(promptText).WithoutTimestamps()…Build()` → `await foreach (var seg in processor.ProcessAsync(floatSamples, ct))`. **At execution time, verify the actual member names of the installed package** (e.g. `WithPrompt` vs `WithPromptText`; whether `ProcessAsync` accepts `float[]`, `Stream`, or both; the exact temperature/entropy builder methods) and adapt the code to compile. A small "API probe" step is included in Task 1. The conceptual mapping below tells you what each call must achieve.
- **DO NOT port the WhisperKit `SuppressBlankFilter` / `installPromptCompatibilityFilter`.** whisper.cpp ships `suppress_blank = true` by default, so the "prompt makes the first content token be `<|endoftext|>` → empty transcript" trap does not occur. There is no `logitsFilters` install/clear in this engine.
- **DO NOT port the duration-gated `withoutTimestamps` / single-window-25 s trap** (`isSingleWindowClip`). That guarded a WhisperKit 1.0.0 multi-window truncation bug; whisper.cpp does its own 30 s windowing with context carry and does not truncate with timestamps off. This engine uses `WithoutTimestamps()` unconditionally on both the whole-file and chunk paths — **but only after Task 6's verification proves a >30 s clip is not truncated** (if that verification ever fails, the fallback is documented in Task 3 Step 9).
- **DO port (model-agnostic):**
  - Vocabulary prompt: `VocabularyPrompt.Text(vocabulary)` → `WithPrompt(promptText)` on both decode paths, gated by `useVocabularyPrompt`.
  - `RegurgitationRecovery.Decode(...)` wrapping **both** the whole-file decode and the chunk decode (the same `decodeRecoveringFromRegurgitation` wrapper in Swift).
  - `RepetitionGuard` (already in Core; reached via `RegurgitationRecovery`).
  - `TextProcessor.StripDecoderArtifacts` on every raw decode result.
  - Temperature fallback equivalent to WhisperKit's `temperatureFallbackCount = 2` — mapped to whisper.cpp's temperature + temperature-increment + entropy/logprob fallback knobs exposed by Whisper.net (Task 3 Step 5).
  - Language fixed (no auto-detect): `WithLanguage(language.WhisperCode())` and explicitly **no** detect-language pass.
- **Streaming:** `MakeStreamingSessionAsync()` returns a `StreamingTranscriptionSession` (Core type) whose `transcribe` closure decodes a `float[]` chunk through whisper.cpp with the **same** RegurgitationRecovery + StripDecoderArtifacts. **Return `null` when no model is loaded** — never trigger a model load from the polling path (mirrors the Swift `guard whisperKit != nil else { return nil }`).
- **Concurrency:** the Swift engine is an `actor`. Use a `SemaphoreSlim(1, 1)` to serialize (a) model load/dedupe and (b) the `_cachedPromptTokens`/prompt-text recompute. Reproduce load-dedupe (a concurrent prewarm + first transcribe load the model exactly once) and vocabulary-change → prompt-cache invalidation.
- **License (repo is GPL-3.0):** Whisper.net (MIT), whisper.cpp (MIT), GGML models (MIT/Whisper license) are GPL-compatible. Re-verify the license of every pinned package at execution time; reject any GPL-incompatible dependency.
- **Privacy:** the **only** runtime network call is the one-time GGML download from Hugging Face. No telemetry. Delete temp recordings after use (the recorder owns that in Phase 3; this phase creates no orphan WAVs except the bench's own temp file, which it deletes).
- **Do NOT modify the macOS Swift app** (`Sources/`, `Tests/`, `Package.swift`, `Resources/`) — read-only reference.
- **Do NOT push / open PRs / add remotes.** Commit locally on the `windows-port` branch only (created in Phase 1).

---

## File Structure (what this phase creates / modifies)

```
windows/
├── JVoice.App/                                  NEW project (minimal here; Phase 4 adds the UI)
│   ├── JVoice.App.csproj                         create (net9.0-windows WinExe; NuGet packages)
│   ├── app.manifest                              create (DPI awareness, asInvoker)
│   ├── Program.cs                                create (entry point: handle --bench, else fall through)
│   └── Whisper/
│       ├── WhisperRuntime.cs                     create (native runtime selection: CUDA vs CPU)
│       ├── WhisperModelStore.cs                  create (locate/download/verify GGML models)
│       ├── WhisperNetTranscriptionEngine.cs      create (the ITranscriptionEngine implementation)
│       └── BenchRunner.cs                         create (port of BenchRunner.swift; the --bench CLI)
├── tools/
│   └── whisper-smoke/                            NEW console project (no WPF; E2E verification harness)
│       ├── whisper-smoke.csproj                  create (net9.0; references JVoice.Core + Whisper.net)
│       └── Program.cs                            create
└── JVoice.sln                                    modify (add JVoice.App + whisper-smoke projects)
```

**Decision (project layout) — why a minimal `JVoice.App` now + a separate `whisper-smoke` console tool:**

- The overview (§4.6) fixes the engine's namespace as `JVoice.App.Whisper`, so the engine **must** live in the `JVoice.App` project. Phase 4 "fleshes out the UI" in this same project. Therefore this phase **creates `windows/JVoice.App/JVoice.App.csproj` as a real `net9.0-windows` WPF `WinExe`** (so Phase 4 doesn't have to re-create or re-target it), but adds **only** the files needed to compile and run the engine + bench: `Program.cs`, `app.manifest`, and the `Whisper/` folder. No XAML, no windows, no tray — those are Phase 4. To make a `WinExe` runnable headlessly for `--bench`, `Program.cs` is a plain `static Main` (the project sets `<UseWPF>true</UseWPF>` but does **not** yet declare an `Application`/`StartupObject` XAML entry — Phase 4 will switch the entry point to `App.xaml`). This is clean: one engine home, no throwaway project, no WPF coupling in the engine.
- **Why the engine must also be testable without WPF:** a `net9.0-windows` `WinExe` is awkward to drive from a pure unit test and cannot run on non-Windows CI. So this phase also creates a tiny **`windows/tools/whisper-smoke`** `net9.0` **console** project that references `JVoice.Core` **and the Whisper.net packages** and contains a copy-free path to the same decode (it constructs a `WhisperNetTranscriptionEngine`). Because `WhisperNetTranscriptionEngine` lives in `JVoice.App` (a `-windows` exe), the smoke tool references `JVoice.App` via `<ProjectReference>` — this is allowed (a `net9.0` console app can reference a `net9.0-windows` exe's compiled assembly as a library on Windows; if the SDK rejects referencing a `WinExe`, set `<OutputType>Library</OutputType>` is **not** acceptable for the app, so instead the smoke tool simply links the engine `.cs` files via `<Compile Include="..\..\JVoice.App\Whisper\*.cs" />` — see Task 5b). The end-to-end verification (Task 6) runs through `whisper-smoke`, which works on the dev machine (Windows + RTX 3060 Ti).

> **Note for Phase 4:** when you build `App.xaml`/`App.xaml.cs`, replace `Program.cs`'s plain `Main` with the WPF `STAThread` entry that calls `BenchRunner.ShouldRun(args)` **before** `new App().Run()`, exactly as the macOS app calls `BenchRunner.shouldRun` before showing UI. The bench path must keep working after Phase 4.

---

## Task 1: Create `JVoice.App` project + pin Whisper.net NuGet packages + runtime selector

**Files:**
- Create: `windows/JVoice.App/JVoice.App.csproj`
- Create: `windows/JVoice.App/app.manifest`
- Create: `windows/JVoice.App/Program.cs` (temporary headless entry; superseded by Phase 4)
- Create: `windows/JVoice.App/Whisper/WhisperRuntime.cs`
- Modify: `windows/JVoice.sln` (add the project)

**Interfaces:**
- Produces: a buildable `JVoice.App` (`net9.0-windows`, WinExe) referencing `JVoice.Core` and the pinned Whisper.net packages; `static class WhisperRuntime` with `void EnsureLoaded()` and `string Describe()`.
- Consumes: `JVoice.Core` (Phase 1).

- [ ] **Step 1: Create `windows/JVoice.App/JVoice.App.csproj`**

> The package versions below are **placeholders** — at execution time, run the `dotnet add package` commands in Step 6 which write the *current stable* versions into this file. Then pin them (no `*`, no floating range). Do not invent versions; let `dotnet add package` resolve them, then verify they were pinned.

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <RootNamespace>JVoice.App</RootNamespace>
    <AssemblyName>JVoice</AssemblyName>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <!-- Phase 4 sets the WPF StartupObject / App.xaml entry. For now Program.Main is the entry. -->
    <StartupObject>JVoice.App.Program</StartupObject>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\JVoice.Core\JVoice.Core.csproj" />
  </ItemGroup>

  <!-- Whisper.net packages — versions written + pinned by `dotnet add package` (Step 6). -->
  <ItemGroup>
    <PackageReference Include="Whisper.net" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime.Cuda" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime.Vulkan" Version="PINNED_AT_EXECUTION" />
  </ItemGroup>

</Project>
```

- [ ] **Step 2: Create `windows/JVoice.App/app.manifest`** (DPI awareness, no UAC elevation — overview §6.4: non-elevated so UIPI is documented, not worked around)

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifest Version="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="JVoice.app" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
    </windowsSettings>
  </application>
</assembly>
```

> If the build complains about `manifest Version` (a copy-paste artifact above), the correct opening tag is `<assembly manifestVersion="1.0" ...>`. Fix it to `manifestVersion="1.0"` — there is no space.

- [ ] **Step 3: Create `windows/JVoice.App/Program.cs`** (temporary headless entry; Phase 4 replaces this with the WPF `App.xaml` entry but keeps the `--bench` branch)

```csharp
using JVoice.App.Whisper;

namespace JVoice.App;

/// Temporary entry point for Phase 2 so the engine + --bench are runnable before
/// the WPF UI exists. Phase 4 replaces this with the WPF App.xaml [STAThread] Main,
/// which MUST keep the `BenchRunner.ShouldRun(args)` branch (run bench, then exit)
/// BEFORE constructing/showing any UI — mirroring the macOS app's startup order.
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        // No UI yet (Phase 4). For now, a runnable no-op so the WinExe launches and exits cleanly.
        Console.Error.WriteLine("JVoice (Windows) — UI not built yet (Phase 4). Use --bench <audio.wav>.");
        return 0;
    }
}
```

- [ ] **Step 4: Create `windows/JVoice.App/Whisper/WhisperRuntime.cs`**

> Whisper.net auto-discovers and loads the best available native runtime the first time a `WhisperFactory` is created, in this preference order (documented by Whisper.net): **CUDA → Vulkan → CoreML/OpenVINO (n/a on Windows) → CPU**. We don't have to choose manually; we just make sure the runtime packages are present (they are, via the csproj) and surface which one got picked for logging/bench output. `RuntimeOptions` (the static Whisper.net type that reports the loaded library) member names vary by version — verify in the API probe (Step 7) and adapt `Describe()`.

```csharp
namespace JVoice.App.Whisper;

/// Ensures a whisper.cpp native runtime is available and reports which one
/// Whisper.net selected. Whisper.net auto-loads the best runtime (CUDA → Vulkan
/// → CPU) on first WhisperFactory creation; this type exists for logging/bench
/// output and as the single place the runtime story is documented.
///
/// On this dev machine (RTX 3060 Ti) the CUDA runtime is selected; on a machine
/// with no CUDA it falls back to Vulkan (any GPU) or CPU (AVX/AVX2). The CPU
/// runtime is the universal fallback and is always bundled.
internal static class WhisperRuntime
{
    private static bool _ensured;
    private static readonly object Gate = new();

    /// Force the native runtime to be probed/loaded eagerly (so prewarm timing
    /// includes it and bench output can name it). Safe to call repeatedly.
    public static void EnsureLoaded()
    {
        if (_ensured) return;
        lock (Gate)
        {
            if (_ensured) return;
            // Touch Whisper.net's runtime so the native library is resolved now.
            // The actual load happens when the first WhisperFactory is created;
            // there is no public "preload" call in all versions, so this is a
            // best-effort no-op marker. The real load is lazy at FromPath().
            _ensured = true;
        }
    }

    /// A human-readable description of the selected runtime, for bench/log output.
    /// VERIFY the RuntimeOptions API in the installed Whisper.net version (Step 7)
    /// and adjust. If no such API exists, return a static string and rely on the
    /// bench's measured timing to confirm GPU acceleration.
    public static string Describe()
    {
        try
        {
            // Example shape (verify member names): Whisper.net exposes the loaded
            // library via Whisper.net.LibraryLoader.RuntimeOptions.LoadedLibrary
            // or similar. Reflect defensively so a version mismatch can't crash.
            var t = Type.GetType("Whisper.net.LibraryLoader.RuntimeOptions, Whisper.net");
            var prop = t?.GetProperty("LoadedLibrary")
                       ?? t?.GetProperty("RuntimeLibrary");
            var val = prop?.GetValue(null);
            return val is null ? "whisper.cpp (runtime auto-selected)" : $"whisper.cpp ({val})";
        }
        catch
        {
            return "whisper.cpp (runtime auto-selected)";
        }
    }
}
```

- [ ] **Step 5: Add `JVoice.App` to the solution**

```bash
cd windows
dotnet sln add JVoice.App/JVoice.App.csproj
```

- [ ] **Step 6: Add and PIN the Whisper.net packages (resolves current stable versions)**

```bash
cd windows/JVoice.App
dotnet add package Whisper.net
dotnet add package Whisper.net.Runtime
dotnet add package Whisper.net.Runtime.Cuda
dotnet add package Whisper.net.Runtime.Vulkan
```

Then open `JVoice.App.csproj` and confirm each `PackageReference` now has a concrete `Version="x.y.z"` (replace the `PINNED_AT_EXECUTION` placeholders if `dotnet add` didn't overwrite them). **Record the four resolved versions in `docs/HANDOFF-WINDOWS.md`** (create/append that file) under a "Phase 2 pinned versions" heading. Verify the licenses are MIT/GPL-compatible (`dotnet list package --include-transitive` + spot-check on nuget.org). If `Whisper.net.Runtime.Vulkan` is unavailable or fails to restore, drop it (CUDA + CPU still cover the dev machine) and note that in HANDOFF-WINDOWS.md.

- [ ] **Step 7: API probe — confirm the installed Whisper.net surface**

Create a throwaway probe to print the real builder/processor API so Tasks 3–5 use the correct member names. Run from `windows/JVoice.App`:

```bash
dotnet build JVoice.App.csproj -c Debug
```

Then inspect the package's public API. The fastest reliable way is to read the package's XML/metadata or open the assembly:

```bash
# Find the restored Whisper.net assembly and list its WhisperProcessorBuilder members.
# (PowerShell is fine here; this is a read-only inspection.)
```

Use the PowerShell tool:
```powershell
$dll = Get-ChildItem "$env:USERPROFILE\.nuget\packages\whisper.net" -Recurse -Filter Whisper.net.dll | Select-Object -First 1
[void][System.Reflection.Assembly]::LoadFrom($dll.FullName)
$asm = [System.Reflection.Assembly]::LoadFrom($dll.FullName)
$builder = $asm.GetType('Whisper.net.WhisperProcessorBuilder')
$builder.GetMethods() | Where-Object { $_.IsPublic } | Select-Object -ExpandProperty Name | Sort-Object -Unique
```

Record (in HANDOFF-WINDOWS.md) the exact names of: the prompt method (`WithPrompt` vs `WithPromptText`), the timestamp method (`WithoutTimestamps`), the language method (`WithLanguage`), the temperature methods (`WithTemperature`, `WithTemperatureInc`/`WithTemperatureIncrement`, `WithEntropyThreshold`/`WithEntropyThold`, `WithProbabilityThreshold`/`WithLogProbThreshold`), whether `WithGreedySamplingStrategy()`/`WithBeamSearchSamplingStrategy()` exist, and the `WhisperProcessor.ProcessAsync` overloads (accepts `float[]`? `Stream`? `ReadOnlyMemory<float>`?). **Tasks 3 and 5 below assume the common names; if the probe shows different names, adapt the code accordingly — the conceptual goal of each call is documented inline.**

- [ ] **Step 8: Verify the project builds**

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Debug`
Expected: `Build succeeded`, 0 errors. (Native runtime DLLs are restored into `bin/`.)

- [ ] **Step 9: Verify the headless exe runs**

Run: `dotnet run --project windows/JVoice.App -- --help-nonexistent`
Expected: prints `JVoice (Windows) — UI not built yet (Phase 4). Use --bench <audio.wav>.` to stderr and exits 0. (No `--bench`, so it falls through.)

- [ ] **Step 10: Commit**

```bash
git add windows/JVoice.App windows/JVoice.sln docs/HANDOFF-WINDOWS.md
git commit -m "build(windows): scaffold JVoice.App (WinExe) + pin Whisper.net runtimes + WhisperRuntime selector

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `WhisperModelStore` — locate, download, and verify GGML models

> Ports the *intent* of `WhisperModelLocator.completeModelFolder` (only return a path when the download is **complete**, so an interrupted download never hands a half-finished model to the loader) to the GGML world: a single `.bin` file with a known expected size and (optionally) a pinned SHA-256, downloaded atomically via a `.part` temp + rename.

**Files:**
- Create: `windows/JVoice.App/Whisper/WhisperModelStore.cs`
- (No unit test project for App in this phase; the store is exercised end-to-end in Task 6. A pure size/hash helper is unit-testable but kept inline for simplicity — Task 6 covers it.)

**Interfaces:**
- Produces: `sealed class WhisperModelStore` with:
  - `string ModelsDirectory { get; }`
  - `string? CompleteModelPath(WhisperModelOption model)` — full path iff present, size-correct, and (if SHA known) hash-correct; else `null`.
  - `Task DownloadAsync(WhisperModelOption model, IProgress<double> progress, CancellationToken ct)` — download to `<file>.part`, verify, atomic-rename to `<file>`.
  - `Task<string> EnsureAsync(WhisperModelOption model, IProgress<double>? progress, CancellationToken ct)` — return `CompleteModelPath` if present, else download then return the path.
  - a private `record ModelInfo(string FileName, string Url, long ExpectedBytes, string? Sha256)` table keyed by `WhisperModelOption`.
- Consumes: `WhisperModelOption`, `WhisperModelOption.GgmlFileName()` (Phase 1).

- [ ] **Step 1: Record the real expected sizes and SHA-256 checksums (DO THIS FIRST — values get baked into the code)**

The four GGML files live at `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<file>`. Fetch each file's exact byte size and SHA-256 at execution time and record them. Use:

```bash
# For each model file, get the Content-Length (size) without downloading the body:
for f in ggml-tiny.bin ggml-base.bin ggml-small.bin ggml-large-v3-turbo-q5_0.bin; do
  echo "== $f =="
  curl -sIL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$f" | grep -i -E '^content-length|^location'
done
```

To get the SHA-256, you must download the file once (do it for at least `ggml-tiny.bin`, which Task 6 uses; the others can be recorded when first downloaded by a real run):

```bash
curl -fL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin" -o /tmp/ggml-tiny.bin
sha256sum /tmp/ggml-tiny.bin   # record this hex string
stat -c %s /tmp/ggml-tiny.bin  # record this byte count (the EXACT ExpectedBytes)
```

> **Assumption / fallback policy (logged):** Hugging Face may serve `ggml-*.bin` via an LFS redirect, so `Content-Length` from the first response can be the pointer size, not the blob — follow redirects (`-L`) and read the final `Content-Length`. If you cannot obtain a SHA-256 for the larger models without a full download, set their `Sha256` to `null` in the table — the store then verifies **size only** for those (still catches truncated downloads), and the code path is identical. **Always** record the SHA-256 for `ggml-tiny.bin` (used by the automated Task 6 verification). Put the recorded sizes + hashes into the `ModelInfo` table in Step 3 and into `docs/HANDOFF-WINDOWS.md`.

- [ ] **Step 2: Decide the verification contract (no code yet — read)**

`CompleteModelPath` returns the path **only when**:
1. the file exists, AND
2. its byte length equals `ExpectedBytes` (always checked — cheap, catches truncation), AND
3. if `Sha256 != null`, the file's SHA-256 equals it (full read — only on an explicit `VerifyHash` call or first-download verification, NOT on every `CompleteModelPath` to avoid hashing 500 MB on every transcription).

Pragmatic split: `CompleteModelPath` checks **existence + size** (fast, called often). The full SHA-256 is verified **once, right after download**, inside `DownloadAsync` before the atomic rename. This matches the Swift locator's role (cheap completeness gate at load time; integrity enforced at download time).

- [ ] **Step 3: Create `windows/JVoice.App/Whisper/WhisperModelStore.cs`**

```csharp
using System.Security.Cryptography;
using JVoice.Core.Models;

namespace JVoice.App.Whisper;

/// Locates, downloads, and verifies the GGML model files whisper.cpp loads.
///
/// Windows analog of WhisperModelLocator (TranscriptionManager.swift): the point
/// is to only ever hand the engine a *complete* model. WhisperKit's failure mode
/// was a half-finished .mlmodelc folder missing weight.bin; ours is a truncated
/// .bin. We download to "<file>.part", verify size (+ SHA-256 when known), then
/// atomically rename — so a crashed/cancelled download never leaves a usable-
/// looking-but-broken model on disk.
internal sealed class WhisperModelStore
{
    /// %LOCALAPPDATA%\JVoice\models\
    public string ModelsDirectory { get; }

    private readonly HttpClient _http;

    public WhisperModelStore(string? modelsDirectory = null, HttpClient? httpClient = null)
    {
        ModelsDirectory = modelsDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JVoice", "models");
        Directory.CreateDirectory(ModelsDirectory);
        _http = httpClient ?? new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
    }

    /// Base URL for the ggerganov/whisper.cpp GGML files on Hugging Face.
    private const string BaseUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

    private sealed record ModelInfo(string FileName, string Url, long ExpectedBytes, string? Sha256);

    /// The download manifest. ExpectedBytes and Sha256 are recorded at execution
    /// time (Task 2 Step 1). Sha256 may be null for the larger models — size is
    /// still verified. Tiny MUST have a real SHA-256 (the automated verification
    /// in Task 6 depends on it).
    private static readonly IReadOnlyDictionary<WhisperModelOption, ModelInfo> Manifest =
        new Dictionary<WhisperModelOption, ModelInfo>
        {
            [WhisperModelOption.Tiny] = new(
                "ggml-tiny.bin",
                BaseUrl + "ggml-tiny.bin",
                ExpectedBytes: 77_691_713,            // PLACEHOLDER — replace with the size you recorded
                Sha256: "RECORD_TINY_SHA256_AT_EXECUTION"),
            [WhisperModelOption.Base] = new(
                "ggml-base.bin",
                BaseUrl + "ggml-base.bin",
                ExpectedBytes: 147_951_465,           // PLACEHOLDER — replace with recorded size
                Sha256: null),                        // optional; record on first real download
            [WhisperModelOption.Small] = new(
                "ggml-small.bin",
                BaseUrl + "ggml-small.bin",
                ExpectedBytes: 487_601_967,           // PLACEHOLDER — replace with recorded size
                Sha256: null),
            [WhisperModelOption.LargeTurbo] = new(
                "ggml-large-v3-turbo-q5_0.bin",
                BaseUrl + "ggml-large-v3-turbo-q5_0.bin",
                ExpectedBytes: 574_041_195,           // PLACEHOLDER — replace with recorded size
                Sha256: null),
        };

    /// The expected on-disk path (whether or not it exists / is complete).
    public string PathFor(WhisperModelOption model)
        => Path.Combine(ModelsDirectory, model.GgmlFileName());

    /// The path of a *complete* model (exists + correct size), or null.
    /// Cheap: does NOT hash. Full integrity is enforced at download time.
    public string? CompleteModelPath(WhisperModelOption model)
    {
        var info = Manifest[model];
        string path = Path.Combine(ModelsDirectory, info.FileName);
        if (!File.Exists(path)) return null;
        try
        {
            long len = new FileInfo(path).Length;
            return len == info.ExpectedBytes ? path : null;
        }
        catch (IOException) { return null; }
    }

    /// Ensure the model is present and complete, downloading it if needed.
    /// Returns the verified local path.
    public async Task<string> EnsureAsync(
        WhisperModelOption model, IProgress<double>? progress, CancellationToken ct)
    {
        var existing = CompleteModelPath(model);
        if (existing is not null) return existing;
        await DownloadAsync(model, progress ?? new Progress<double>(), ct).ConfigureAwait(false);
        return CompleteModelPath(model)
            ?? throw new InvalidOperationException(
                $"Model {model.GgmlFileName()} still incomplete after download.");
    }

    /// Download to "<file>.part", verify size (+ SHA-256 when known), atomic-rename.
    /// progress reports 0.0–1.0 (NaN when the server doesn't send Content-Length).
    public async Task DownloadAsync(
        WhisperModelOption model, IProgress<double> progress, CancellationToken ct)
    {
        var info = Manifest[model];
        string finalPath = Path.Combine(ModelsDirectory, info.FileName);
        string partPath = finalPath + ".part";

        // Start clean — a stale .part from a prior crash is never resumed (simpler,
        // and HF blobs are immutable so a fresh download is always correct).
        try { if (File.Exists(partPath)) File.Delete(partPath); } catch (IOException) { }

        using (var resp = await _http
                   .GetAsync(info.Url, HttpCompletionOption.ResponseHeadersRead, ct)
                   .ConfigureAwait(false))
        {
            resp.EnsureSuccessStatusCode();
            long? total = resp.Content.Headers.ContentLength;
            await using var src = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            await using var dst = new FileStream(
                partPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20, useAsync: true);

            var buffer = new byte[1 << 20];
            long readTotal = 0;
            int n;
            while ((n = await src.ReadAsync(buffer.AsMemory(0, buffer.Length), ct).ConfigureAwait(false)) > 0)
            {
                await dst.WriteAsync(buffer.AsMemory(0, n), ct).ConfigureAwait(false);
                readTotal += n;
                progress.Report(total is > 0 ? (double)readTotal / total.Value : double.NaN);
            }
        }

        // Verify before exposing the file under its real name.
        long actualBytes;
        try { actualBytes = new FileInfo(partPath).Length; }
        catch (IOException ex) { SafeDelete(partPath); throw new InvalidOperationException("Download verification failed (size unreadable).", ex); }

        if (actualBytes != info.ExpectedBytes)
        {
            SafeDelete(partPath);
            throw new InvalidOperationException(
                $"Downloaded {info.FileName} is {actualBytes} bytes; expected {info.ExpectedBytes}.");
        }

        if (info.Sha256 is { } expectedHash &&
            !expectedHash.Equals("RECORD_TINY_SHA256_AT_EXECUTION", StringComparison.Ordinal))
        {
            string actualHash = await ComputeSha256Async(partPath, ct).ConfigureAwait(false);
            if (!string.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
            {
                SafeDelete(partPath);
                throw new InvalidOperationException(
                    $"SHA-256 mismatch for {info.FileName}: got {actualHash}, expected {expectedHash}.");
            }
        }

        // Atomic publish. File.Move overwrites=false; if a complete file appeared
        // meanwhile (race), keep it and drop our .part.
        try
        {
            if (File.Exists(finalPath)) { SafeDelete(partPath); return; }
            File.Move(partPath, finalPath);
        }
        catch (IOException)
        {
            if (File.Exists(finalPath)) { SafeDelete(partPath); return; }
            throw;
        }
        progress.Report(1.0);
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken ct)
    {
        await using var fs = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20, useAsync: true);
        using var sha = SHA256.Create();
        byte[] hash = await sha.ComputeHashAsync(fs, ct).ConfigureAwait(false);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static void SafeDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { }
    }
}
```

- [ ] **Step 4: Replace the PLACEHOLDER sizes and the tiny SHA-256** with the real values you recorded in Step 1. Re-confirm `ggml-tiny.bin`'s `Sha256` is a real 64-char lowercase hex string (not the sentinel) — otherwise the hash check is skipped.

- [ ] **Step 5: Build**

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Debug`
Expected: `Build succeeded`, 0 errors. (Full functional verification of download is in Task 6.)

- [ ] **Step 6: Commit**

```bash
git add windows/JVoice.App/Whisper/WhisperModelStore.cs docs/HANDOFF-WINDOWS.md
git commit -m "feat(whisper): WhisperModelStore — GGML download/locate/verify with atomic .part rename

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `WhisperNetTranscriptionEngine` — load / prewarm / decode / prompt / recovery

> The heart of the phase. Faithful behavioral port of `WhisperKitTranscriptionEngine` (TranscriptionManager.swift lines 114–367) to Whisper.net/GGML. Reproduce: load-dedupe via a shared load task guarded by a semaphore; prewarm; whole-file + chunk decode both wrapped by `RegurgitationRecovery.Decode`; vocabulary biasing via `WithPrompt`; prompt-text caching invalidated on vocabulary change; `StripDecoderArtifacts` on each raw decode; temperature fallback ≈ 2; language fixed. **Omit** the SuppressBlankFilter and the single-window timestamp trap (overview §6.3).

**Files:**
- Create: `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`

**Interfaces:**
- Produces: `sealed class WhisperNetTranscriptionEngine : ITranscriptionEngine` with constructor
  `WhisperNetTranscriptionEngine(WhisperModelOption model, TranscriptionLanguage language, IReadOnlyList<string> vocabulary, bool useVocabularyPrompt = true, WhisperModelStore store)`.
- Consumes (all from Phase 1 Core): `ITranscriptionEngine`, `TranscriptionException` (+ `.ModelLoadFailed`, `.EmptyTranscript`, `.AudioFileMissing`), `StreamingTranscriptionSession`, `ChunkPlanner.Config`, `VocabularyPrompt.Text`, `RegurgitationRecovery.Decode`, `TextProcessor.StripDecoderArtifacts`, `WhisperModelOption`, `TranscriptionLanguage.WhisperCode()`. Plus `WhisperModelStore` (Task 2), `WhisperRuntime` (Task 1), Whisper.net's `WhisperFactory`/`WhisperProcessorBuilder`/`WhisperProcessor`.

**Swift → C# behavior map (each row MUST be reproduced):**

| Swift (`WhisperKitTranscriptionEngine`) | C# (`WhisperNetTranscriptionEngine`) |
| --- | --- |
| `actor` isolation | `SemaphoreSlim(1,1)` `_gate` around load + prompt-cache recompute |
| `loadTask` dedupe of concurrent loads | shared `Task<WhisperFactory>? _loadTask` created once under `_gate` |
| `updateVocabulary` sets `cachedPromptTokens = nil` only on change | `UpdateVocabularyAsync` resets `_cachedPromptText = null` only when `words != _vocabulary` |
| `isReady()` = `whisperKit != nil` | `IsReadyAsync()` = `_factory != null` |
| `transcribe(audioURL:)` whole-file path | `TranscribeAsync(path, ct)` |
| `transcribeChunkSamples(_:)` chunk path | private `TranscribeChunkSamplesAsync(float[])` |
| `decodeRecoveringFromRegurgitation` wraps both | both paths call `RegurgitationRecovery.Decode(useVocabularyPrompt, vocabulary, decode)` |
| `decodeFile` / `decodeSamples` build `DecodingOptions` | build a `WhisperProcessor` per decode via the builder |
| `applyVocabularyBiasing` (prompt on/off) | `WithPrompt(promptText)` when `usePrompt && promptText != null`, else no prompt |
| `promptTokens(using:)` caches encoded prompt | `PromptText()` caches the **prompt string** (Whisper.net tokenizes internally — no manual token IDs) |
| `withoutTimestamps = isSingleWindowClip(...)` | **DROPPED** — `WithoutTimestamps()` unconditionally (verified non-truncating in Task 6) |
| `installPromptCompatibilityFilter` / `SuppressBlankFilter` | **DROPPED** — whisper.cpp `suppress_blank=true` by default |
| `temperatureFallbackCount = 2` | `WithTemperature(0)` + `WithTemperatureInc(0.2)` + entropy/logprob thresholds (Step 5) ≈ 2 fallbacks |
| `detectLanguage = false`; `language` fixed | `WithLanguage(code)`, no detect pass |
| `chunkingStrategy = .vad` (file path only) | not needed — whisper.cpp windows internally; do not add a VAD knob unless the probe shows a trivial one |
| `prewarm()` ignores errors | `PrewarmAsync()` swallows load errors |
| `makeStreamingSession()` returns nil if no model | `MakeStreamingSessionAsync()` returns null if `_factory == null` (Task 4) |
| `stripDecoderArtifacts(text)` on each decode | `TextProcessor.StripDecoderArtifacts(text)` on each decode |

- [ ] **Step 1: Create the skeleton with fields, constructor, and the simple members**

Create `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`:

```csharp
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using JVoice.Core.Transcription;
using Whisper.net;

namespace JVoice.App.Whisper;

/// On-device speech engine backed by whisper.cpp (via Whisper.net) and GGML models.
/// Faithful behavioral port of WhisperKitTranscriptionEngine (TranscriptionManager.swift):
/// load-dedupe, prewarm, whole-file + chunk decode both guarded by RegurgitationRecovery,
/// vocabulary-prompt biasing with a cache invalidated on vocabulary change, decoder-
/// artifact stripping, fixed language, ~2 temperature fallbacks. The two WhisperKit-1.0.0
/// workarounds (SuppressBlankFilter, single-window timestamp gate) are intentionally NOT
/// ported — whisper.cpp doesn't need them (overview §6.3).
internal sealed class WhisperNetTranscriptionEngine : ITranscriptionEngine
{
    private readonly WhisperModelOption _model;
    private readonly TranscriptionLanguage _language;
    private readonly bool _useVocabularyPrompt;
    private readonly WhisperModelStore _store;

    // Guards model load/dedupe AND the prompt-text cache recompute (the actor analog).
    private readonly SemaphoreSlim _gate = new(1, 1);

    private IReadOnlyList<string> _vocabulary;

    /// The vocabulary prompt string, computed once per vocabulary change.
    /// null = needs (re)computation. "" wrapped as a sentinel is avoided by using
    /// a separate _promptComputed flag, mirroring Swift's `cachedPromptTokens: [Int]?`.
    private string? _cachedPromptText;
    private bool _promptComputed;

    private WhisperFactory? _factory;
    private Task<WhisperFactory>? _loadTask;

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

    public async Task UpdateVocabularyAsync(IReadOnlyList<string> words)
    {
        words ??= Array.Empty<string>();
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (words.SequenceEqual(_vocabulary)) return; // no change → keep cache
            _vocabulary = words.ToArray();
            _cachedPromptText = null;
            _promptComputed = false;
        }
        finally { _gate.Release(); }
    }

    public Task<bool> IsReadyAsync() => Task.FromResult(_factory is not null);

    public async Task PrewarmAsync()
    {
        // Errors ignored — a failed prewarm just means the next TranscribeAsync
        // retries the load and surfaces the error (Swift `prewarm()` semantics).
        try { _ = await LoadFactoryAsync(CancellationToken.None).ConfigureAwait(false); }
        catch { /* swallow */ }
    }

    // ... (decode paths, load, streaming added in the following steps)
}
```

> **Note on the prompt cache:** Swift cached encoded **token IDs** because WhisperKit's API takes `promptTokens: [Int]`. Whisper.net's `WithPrompt(string)` takes the **text** and tokenizes internally, so we cache the prompt **string** instead. `_promptComputed` distinguishes "computed, nothing to bias (null)" from "not yet computed", exactly like Swift's `[Int]?` distinguishes `[]` from `nil`. The `VocabularyPrompt.MaxPromptTokens` cap was enforced post-tokenization in Swift; Whisper.net has no public token-trim hook, so we rely on `VocabularyPrompt.Text`'s `MaxWords=40` cap (the prompt string is short by construction). Document this in a code comment.

- [ ] **Step 2: Add the model load + dedupe (`LoadFactoryAsync` / `EnsureModelFileAsync`)**

Append inside the class, before the closing brace:

```csharp
    /// Load the WhisperFactory once, deduping concurrent callers (a background
    /// prewarm racing the first transcribe). Mirrors Swift loadWhisperKit/performLoad:
    /// the shared task is created under the gate; on failure the task is dropped so
    /// a later call retries; errors surface as TranscriptionException.ModelLoadFailed.
    private async Task<WhisperFactory> LoadFactoryAsync(CancellationToken ct)
    {
        if (_factory is { } ready) return ready;

        Task<WhisperFactory> task;
        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (_factory is { } already) return already;
            task = _loadTask ??= PerformLoadAsync(ct);
        }
        finally { _gate.Release(); }

        try
        {
            var factory = await task.ConfigureAwait(false);
            // Publish under the gate so concurrent callers see it atomically.
            await _gate.WaitAsync(ct).ConfigureAwait(false);
            try { _factory ??= factory; }
            finally { _gate.Release(); }
            return _factory!;
        }
        catch (Exception ex)
        {
            await _gate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
            try { _loadTask = null; }   // drop the failed task so a later call retries
            finally { _gate.Release(); }
            if (ex is TranscriptionException) throw;
            throw TranscriptionException.ModelLoadFailed(ex.Message);
        }
    }

    /// Download (if needed) the GGML file, then build the WhisperFactory from it.
    /// The download is the one allowed runtime network call (overview §5).
    private async Task<WhisperFactory> PerformLoadAsync(CancellationToken ct)
    {
        WhisperRuntime.EnsureLoaded();
        string modelPath = await _store.EnsureAsync(_model, progress: null, ct).ConfigureAwait(false);
        try
        {
            // WhisperFactory.FromPath loads the GGML weights and selects the native
            // runtime (CUDA on this dev machine, else Vulkan/CPU). VERIFY the exact
            // factory-creation API in the installed Whisper.net (Task 1 Step 7) —
            // it may be FromPath(string) or Create...; adapt if needed.
            return WhisperFactory.FromPath(modelPath);
        }
        catch (Exception ex)
        {
            throw TranscriptionException.ModelLoadFailed(
                $"Failed to load GGML model {_model.GgmlFileName()}: {ex.Message}");
        }
    }
```

- [ ] **Step 3: Add the prompt-text cache (`PromptTextLocked`)**

Append:

```csharp
    /// The vocabulary prompt string, cached once per vocabulary change.
    /// Returns null when there's nothing to bias toward. MUST be called with the
    /// gate held (load/decode paths hold it transitively, or call CurrentPrompt()).
    private string? PromptTextLocked()
    {
        if (_promptComputed) return _cachedPromptText;
        _cachedPromptText = VocabularyPrompt.Text(_vocabulary); // null when empty/blank
        _promptComputed = true;
        return _cachedPromptText;
    }

    /// Gate-acquiring accessor for the decode paths.
    private async Task<string?> CurrentPromptAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { return PromptTextLocked(); }
        finally { _gate.Release(); }
    }

    /// Snapshot the vocabulary under the gate (RegurgitationRecovery needs it,
    /// and it can change between decodes).
    private async Task<IReadOnlyList<string>> CurrentVocabularyAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { return _vocabulary; }
        finally { _gate.Release(); }
    }
```

- [ ] **Step 4: Add the whole-file decode path (`TranscribeAsync` + `DecodeFileAsync`)**

Append:

```csharp
    public async Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)
    {
        if (!File.Exists(audioPath))
            throw TranscriptionException.AudioFileMissing(audioPath);

        var factory = await LoadFactoryAsync(ct).ConfigureAwait(false);
        var vocabulary = await CurrentVocabularyAsync().ConfigureAwait(false);

        // Same decode-and-recover policy as Swift decodeRecoveringFromRegurgitation:
        // prompted decode; on regurgitation/empty, a prompt-free re-decode.
        string guarded = await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            usePrompt => DecodeFileAsync(audioPath, factory, usePrompt, ct)).ConfigureAwait(false);

        if (guarded.Length == 0)
            throw TranscriptionException.EmptyTranscript();
        return guarded;
    }

    private async Task<string> DecodeFileAsync(
        string audioPath, WhisperFactory factory, bool usePrompt, CancellationToken ct)
    {
        // Decode the whole file by feeding its float samples to the processor.
        // (Reading the WAV → float[] mirrors what the chunk path already does and
        // keeps a single ProcessAsync(float[]) code path. If the installed
        // Whisper.net only accepts a Stream, use ProcessAsync(fileStream) instead —
        // see Task 1 Step 7 probe results.)
        float[] samples = ReadWavAsFloatSamples(audioPath);
        return await DecodeSamplesAsync(samples, factory, usePrompt, ct).ConfigureAwait(false);
    }
```

> **Why decode the file as `float[]` rather than a `Stream`:** keeps one decode implementation (`DecodeSamplesAsync`) for both paths, and the WAV is always 16 kHz mono 16-bit PCM (the recorder guarantees it — overview §1), which is exactly what whisper.cpp wants. If the probe (Task 1 Step 7) shows `ProcessAsync` takes a `Stream`, the alternative is `await using var fs = File.OpenRead(audioPath); await foreach (var s in processor.ProcessAsync(fs, ct)) ...` — functionally equivalent; pick whichever the installed API supports and note it.

- [ ] **Step 5: Add the shared sample decode (`DecodeSamplesAsync`) — the builder lives here**

Append. **This is the method most sensitive to the installed Whisper.net API — adapt member names per the Task 1 Step 7 probe.** The conceptual requirements are commented.

```csharp
    /// The single decode implementation for both the whole-file and chunk paths.
    /// Builds a fresh WhisperProcessor (cheap relative to the factory load),
    /// streams segments, joins them, and strips decoder artifacts.
    ///
    /// Builder configuration reproduces the Swift DecodingOptions:
    ///   - WithLanguage(code)         ← language fixed; NO detect-language pass
    ///   - WithPrompt(promptText)     ← vocabulary biasing (only when usePrompt && prompt != null)
    ///   - WithoutTimestamps()        ← timestamps off on BOTH paths (verified non-truncating, Task 6)
    ///   - temperature fallback ≈ 2   ← WithTemperature(0) + WithTemperatureInc(0.2)
    ///                                   + entropy/logprob thresholds (whisper.cpp's fallback trigger)
    private async Task<string> DecodeSamplesAsync(
        float[] samples, WhisperFactory factory, bool usePrompt, CancellationToken ct)
    {
        string? promptText = usePrompt ? await CurrentPromptAsync().ConfigureAwait(false) : null;

        var builder = factory.CreateBuilder()
            .WithLanguage(_language.WhisperCode())   // VERIFY name; fixed language, no auto-detect
            .WithoutTimestamps();                    // VERIFY name; off on both paths (§6.3)

        // Temperature fallback ≈ WhisperKit temperatureFallbackCount = 2.
        // whisper.cpp escalates temperature by temperature_inc when a window fails
        // the entropy/logprob gates, up to a small number of retries. Setting a
        // start temp of 0 and an increment of 0.2 yields the same "a couple of
        // fallback attempts" behavior. VERIFY the exact builder method names; if
        // any of these don't exist in the installed version, omit them — the
        // defaults already do temperature fallback — and note it in HANDOFF-WINDOWS.md.
        builder = ApplyTemperatureFallback(builder);

        if (promptText is { Length: > 0 })
            builder = builder.WithPrompt(promptText);  // VERIFY: WithPrompt vs WithPromptText

        await using var processor = builder.Build();

        var sb = new System.Text.StringBuilder();
        // VERIFY: ProcessAsync overload. Common: ProcessAsync(float[] samples, CancellationToken).
        await foreach (var segment in processor.ProcessAsync(samples, ct).ConfigureAwait(false))
            sb.Append(segment.Text);

        string text = sb.ToString().Trim();
        // Remove "[BLANK_AUDIO]"-style decoder sentinels that leak in on silence.
        return TextProcessor.StripDecoderArtifacts(text);
    }

    /// Isolated so the (version-sensitive) temperature/threshold knobs are easy to
    /// adapt. Returns the builder unchanged if the knobs aren't available.
    private static WhisperProcessorBuilder ApplyTemperatureFallback(WhisperProcessorBuilder builder)
    {
        // Reflectively-safe? No — these are compile-time calls. If the installed
        // Whisper.net lacks a method, DELETE that line (compile error tells you).
        // Target behavior: start greedy at temp 0, allow ~2 escalated retries.
        return builder
            .WithTemperature(0.0f)        // VERIFY name
            .WithTemperatureInc(0.2f);    // VERIFY name (WithTemperatureInc / WithTemperatureIncrement)
        // Optionally also: .WithEntropyThreshold(2.4f).WithProbabilityThreshold(0.0f)
        // — add per probe results if present (they tune WHEN fallback fires).
    }

    /// Read a 16 kHz mono 16-bit PCM WAV into normalized float samples.
    /// The recorder (Phase 3) always writes this exact format. We reuse Core's
    /// WavTail header parser + normalization so there is one WAV truth in the repo.
    private static float[] ReadWavAsFloatSamples(string audioPath)
    {
        var reader = WavTailReader.Open(audioPath)
            ?? throw TranscriptionException.UnsupportedAudioFile(audioPath);
        short[] pcm = reader.Samples(0)
            ?? throw TranscriptionException.UnsupportedAudioFile(audioPath);
        return WavTail.FloatSamples(pcm);
    }
```

> **`WavTailReader` accepts only 16 kHz mono 16-bit PCM** (Phase 1, Task 8). That is exactly the bench/recorder format. If a future caller hands a non-conforming WAV, `Open` returns null → `UnsupportedAudioFile`. This is acceptable and matches the privacy/format invariants. The `whisper-smoke` tool and the bench generate conforming WAVs (Task 5/6).

- [ ] **Step 6: Add the chunk decode path (`TranscribeChunkSamplesAsync`)** — used by the streaming session (Task 4)

Append:

```csharp
    /// Decode a chunk of raw 16 kHz mono float samples cut by ChunkPlanner.
    /// Chunks are ≤ maxChunkSeconds by construction, but whisper.cpp windows
    /// internally regardless, so no special-casing is needed. Same regurgitation
    /// recovery as the whole-file path: an all-loop chunk reduces to "" and the
    /// streaming session treats that as a failure → lossless whole-file fallback.
    private async Task<string> TranscribeChunkSamplesAsync(float[] samples, CancellationToken ct)
    {
        var factory = await LoadFactoryAsync(ct).ConfigureAwait(false);
        var vocabulary = await CurrentVocabularyAsync().ConfigureAwait(false);
        return await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            usePrompt => DecodeSamplesAsync(samples, factory, usePrompt, ct)).ConfigureAwait(false);
    }
```

- [ ] **Step 7: Build (the streaming method comes in Task 4 — temporarily this won't implement `MakeStreamingSessionAsync`, which is fine: it's a default-interface method returning null)**

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Debug`
Expected: `Build succeeded`. **If it fails on a Whisper.net member name** (`WithPrompt`, `WithoutTimestamps`, `WithTemperatureInc`, `ProcessAsync`, `WhisperFactory.FromPath`, `CreateBuilder`), consult the Task 1 Step 7 probe output and fix the call to the actual name. Iterate until it builds. Record every name correction in HANDOFF-WINDOWS.md.

- [ ] **Step 8: Commit**

```bash
git add windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs docs/HANDOFF-WINDOWS.md
git commit -m "feat(whisper): WhisperNetTranscriptionEngine — load dedupe, prompt biasing, regurgitation recovery, artifact stripping

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 9: Document the timestamp fallback (no code unless Task 6 fails)**

In a code comment at `WithoutTimestamps()` and in HANDOFF-WINDOWS.md, record: *"If Task 6's >30 s non-truncation check ever fails on a future Whisper.net version, the fix is to call `.WithoutTimestamps()` only on the chunk path and enable timestamps on the whole-file path (drop `WithoutTimestamps()` there). Do NOT reintroduce the WhisperKit `isSingleWindowClip` duration gate — that was a WhisperKit-specific bug guard."* This keeps the decision reversible without re-deriving it.

---

## Task 4: Streaming session integration (`MakeStreamingSessionAsync`)

> Port `makeStreamingSession()` / `makeStreamingSession(pollNanoseconds:)`. Returns a Core `StreamingTranscriptionSession` whose `transcribe` closure is `TranscribeChunkSamplesAsync`. **Returns null when `_factory == null`** (no model loaded) — never triggers a load from the polling path (Swift `guard whisperKit != nil`). Expose the poll-millisecond parameter so the bench can poll faster than the app's 1000 ms.

**Files:**
- Modify: `windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`

**Interfaces:**
- Produces: `Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()` (overrides the `ITranscriptionEngine` default) + an internal `StreamingTranscriptionSession? MakeStreamingSession(int pollMilliseconds)` for the bench.
- Consumes: `StreamingTranscriptionSession` (ctor `(Func<float[], Task<string>> transcribe, ChunkPlanner.Config? config = null, int pollMilliseconds = 1000)` — Phase 1, Task 10), `ChunkPlanner.Config`.

- [ ] **Step 1: Add the two methods** to `WhisperNetTranscriptionEngine` (before the closing brace)

```csharp
    /// A streaming session bound to this engine, or null when no model is loaded.
    /// Default cadence = AppTimings.StreamingPollMs (1000 ms), matching the app.
    public Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()
        => Task.FromResult(MakeStreamingSession(JVoice.Core.AppTimings.StreamingPollMs));

    /// Parameterized variant so the bench can poll faster (e.g. 100 ms) when it
    /// grows the WAV at ~10× real time. NEVER triggers a model load: no loaded
    /// factory → null → the caller uses the whole-file fallback (Swift guard).
    internal StreamingTranscriptionSession? MakeStreamingSession(int pollMilliseconds)
    {
        if (_factory is null) return null;
        return new StreamingTranscriptionSession(
            transcribe: samples => TranscribeChunkSamplesAsync(samples, CancellationToken.None),
            config: new ChunkPlanner.Config(),
            pollMilliseconds: pollMilliseconds);
    }
```

> **Note:** the Swift closure is `[weak self]` and throws `CancellationError()` if self is gone. In C# the engine is a long-lived object owned by the coordinator; a strong capture is correct here (the session never outlives the engine — the coordinator owns both and tears the session down on stop). The `StreamingTranscriptionSession` itself catches decode exceptions and fails the session (Phase 1, Task 10 `AppendPiece`/`PollOnce`), so a decode error during teardown is already handled.

- [ ] **Step 2: Build**

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Debug`
Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```bash
git add windows/JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs
git commit -m "feat(whisper): streaming session integration (chunk decode via StreamingTranscriptionSession; null when no model)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: The `--bench` CLI (port of `BenchRunner.swift`)

> Faithful port of `BenchRunner.swift`: flags `--model`, `--lang`, `--vocab`, `--stream`, `--no-prompt`; the exact stdout format (lines: `model: … audio: … lang: … vocab: … decoderPrompt: …`, `load+prewarm: %.2fs`, `transcribe: %.2fs`, `raw: "…"`, `processed: "…"`; and the stream variant's `stream wall`, `streamed:`, `wholefile:` lines); and the exit codes (64 usage, 66 no-file, 65 not-a-wav, 70 no-engine/runtime, 1 transcription failed, 0 ok). On Windows the engine is always present (no `#if canImport(WhisperKit)`), so the `70` "unavailable" branch becomes "model couldn't load/runtime missing".

**Files:**
- Create: `windows/JVoice.App/Whisper/BenchRunner.cs`

**Interfaces:**
- Produces: `static class BenchRunner` — `bool ShouldRun(string[] args)`, `int RunAndExit(string[] args)` (synchronous wrapper that blocks on the async run and returns the exit code; `Program.Main` returns it).
- Consumes: `WhisperNetTranscriptionEngine`, `WhisperModelStore`, `WhisperRuntime`, `WhisperModelOption`, `TranscriptionLanguage`, `TextProcessor.Process`/`BuildUserDictionary`, `WavTail.ParseHeader`, `ToneStyle.Casual`.

**Exit-code map (verbatim from Swift):**

| Condition | Swift | C# |
| --- | --- | --- |
| missing `--bench <file>` arg | 64 | 64 |
| file not found | 66 | 66 |
| unknown `--model` / `--lang` | 64 | 64 |
| stream: not a 16 kHz mono PCM wav | 65 | 65 |
| engine has no loaded model / runtime unavailable | 70 | 70 |
| transcription throws | 1 | 1 |
| success | 0 | 0 |

- [ ] **Step 1: Create `windows/JVoice.App/Whisper/BenchRunner.cs`**

```csharp
using System.Diagnostics;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using JVoice.Core.Transcription;

namespace JVoice.App.Whisper;

/// Hidden CLI bench mode (port of BenchRunner.swift):
///
///     JVoice --bench <audio.wav> [--model tiny|base|small|large] [--lang en|ro]
///            [--vocab "Word1,Word2"] [--stream] [--no-prompt]
///
/// Transcribes one file with timing and prints the raw transcript and the
/// TextProcessor-processed output. The primary end-to-end verification of
/// transcription speed and vocabulary biasing on Windows (no XUnit coverage of
/// the native path). Runs BEFORE any UI (Program.Main / Phase 4 App startup).
internal static class BenchRunner
{
    public static bool ShouldRun(string[] arguments) => arguments.Contains("--bench");

    /// Blocks on the async run and returns the process exit code.
    public static int RunAndExit(string[] arguments)
        => RunAsync(arguments).GetAwaiter().GetResult();

    private static async Task<int> RunAsync(string[] arguments)
    {
        int benchIndex = Array.IndexOf(arguments, "--bench");
        if (benchIndex < 0 || arguments.Length <= benchIndex + 1)
        {
            Console.Error.WriteLine(
                "usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab \"Word1,Word2\"] [--stream] [--no-prompt]");
            return 64;
        }

        string audioPath = arguments[benchIndex + 1];
        if (!File.Exists(audioPath))
        {
            Console.Error.WriteLine($"no such file: {audioPath}");
            return 66;
        }

        var model = WhisperModelOption.Base;
        int modelIndex = Array.IndexOf(arguments, "--model");
        if (modelIndex >= 0 && arguments.Length > modelIndex + 1)
        {
            switch (arguments[modelIndex + 1])
            {
                case "tiny": model = WhisperModelOption.Tiny; break;
                case "base": model = WhisperModelOption.Base; break;
                case "small": model = WhisperModelOption.Small; break;
                case "large":
                case "large-v3_turbo":
                case "largeTurbo":
                case "large-v3-v20240930":
                    model = WhisperModelOption.LargeTurbo; break;
                default:
                    Console.Error.WriteLine($"unknown model {arguments[modelIndex + 1]}");
                    return 64;
            }
        }

        var language = TranscriptionLanguage.English;
        int langIndex = Array.IndexOf(arguments, "--lang");
        if (langIndex >= 0 && arguments.Length > langIndex + 1)
        {
            switch (arguments[langIndex + 1])
            {
                case "en":
                case "english": language = TranscriptionLanguage.English; break;
                case "ro":
                case "romanian": language = TranscriptionLanguage.Romanian; break;
                default:
                    Console.Error.WriteLine($"unknown lang {arguments[langIndex + 1]}");
                    return 64;
            }
        }

        var vocabulary = new List<string>();
        int vocabIndex = Array.IndexOf(arguments, "--vocab");
        if (vocabIndex >= 0 && arguments.Length > vocabIndex + 1)
        {
            vocabulary = arguments[vocabIndex + 1]
                .Split(',')
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .ToList();
        }

        bool useDecoderPrompt = !arguments.Contains("--no-prompt");

        // Matches the Swift header line. Swift printed `model.rawValue`; we print the
        // GGML file stem (the closest stable Windows analog of the model identity).
        string vocabDisplay = vocabulary.Count == 0 ? "—" : string.Join(", ", vocabulary);
        Console.WriteLine(
            $"model: {model.GgmlFileName()}   audio: {Path.GetFileName(audioPath)}   " +
            $"lang: {language.WhisperCode()}   vocab: {vocabDisplay}   " +
            $"decoderPrompt: {(useDecoderPrompt ? "on" : "off")}");

        var store = new WhisperModelStore();
        var engine = new WhisperNetTranscriptionEngine(
            model, language, vocabulary, useDecoderPrompt, store);

        var loadSw = Stopwatch.StartNew();
        await engine.PrewarmAsync();
        loadSw.Stop();
        WhisperRuntime.EnsureLoaded();
        Console.WriteLine($"runtime: {WhisperRuntime.Describe()}");
        Console.WriteLine($"load+prewarm: {loadSw.Elapsed.TotalSeconds:0.00}s");

        if (!await engine.IsReadyAsync())
        {
            Console.Error.WriteLine("engine has no loaded model (download or runtime failure)");
            return 70;
        }

        if (arguments.Contains("--stream"))
            return await RunStreamAsync(audioPath, engine, vocabulary);

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
    }

    /// Streaming E2E without a microphone: replays `audioPath` into a growing temp
    /// WAV at ~10× real time while a real StreamingTranscriptionSession consumes it,
    /// then compares against the whole-file transcript. Port of BenchRunner.runStream.
    private static async Task<int> RunStreamAsync(
        string audioPath, WhisperNetTranscriptionEngine engine, IReadOnlyList<string> vocabulary)
    {
        byte[] sourceBytes;
        try { sourceBytes = await File.ReadAllBytesAsync(audioPath); }
        catch (Exception)
        {
            Console.Error.WriteLine($"cannot read file: {audioPath}");
            return 65;
        }

        int probe = Math.Min(sourceBytes.Length, WavTail.HeaderProbeBytes);
        var info = WavTail.ParseHeader(sourceBytes.AsSpan(0, probe));
        if (info is not { } header)
        {
            Console.Error.WriteLine($"not a 16 kHz mono 16-bit PCM wav: {audioPath}");
            return 65;
        }

        var session = engine.MakeStreamingSession(pollMilliseconds: 100);
        if (session is null)
        {
            Console.Error.WriteLine("engine has no loaded model");
            return 70;
        }

        string growingPath = Path.Combine(
            Path.GetTempPath(), $"jv-stream-{Guid.NewGuid():N}.wav");
        try
        {
            // Seed the growing file with just the header (everything up to dataOffset).
            await File.WriteAllBytesAsync(growingPath, sourceBytes[..header.DataOffset]);

            int sliceBytes = header.SampleRate * header.BytesPerSample / 2; // 0.5 s of audio
            var writer = Task.Run(async () =>
            {
                await using var handle = new FileStream(
                    growingPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
                handle.Seek(0, SeekOrigin.End);
                int offset = header.DataOffset;
                while (offset < sourceBytes.Length)
                {
                    int end = Math.Min(offset + sliceBytes, sourceBytes.Length);
                    await handle.WriteAsync(sourceBytes.AsMemory(offset, end - offset));
                    await handle.FlushAsync();
                    offset = end;
                    await Task.Delay(50); // …every 50 ms ⇒ ~10× real time
                }
            });

            var wallSw = Stopwatch.StartNew();
            session.Start(growingPath);
            await writer;                       // "recording" ends here
            var stopSw = Stopwatch.StartNew();
            string? streamed = await session.Finish();
            stopSw.Stop();
            wallSw.Stop();

            Console.WriteLine(
                $"stream wall: {wallSw.Elapsed.TotalSeconds:0.00}s   " +
                $"post-stop (finish): {stopSw.Elapsed.TotalSeconds:0.00}s");
            Console.WriteLine($"streamed:  {(streamed is null ? "nil (session fell back)" : $"\"{streamed}\"")}");

            try
            {
                var wholeSw = Stopwatch.StartNew();
                string whole = await engine.TranscribeAsync(audioPath, CancellationToken.None);
                wholeSw.Stop();
                Console.WriteLine($"wholefile: {wholeSw.Elapsed.TotalSeconds:0.00}s");
                Console.WriteLine($"wholefile: \"{whole}\"");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"whole-file comparison failed: {ex.Message}");
                return 1;
            }
            return 0;
        }
        finally
        {
            try { if (File.Exists(growingPath)) File.Delete(growingPath); } catch (IOException) { }
        }
    }
}
```

> **`TextProcessor.Process` signature check:** Phase 1 (Task 5) declares `Process(string text, ToneStyle mode, IReadOnlyDictionary<string,string>? extraDictionary = null, bool removeFillerWords = false, IReadOnlyList<string>? vocabulary = null)`. The call above passes positional `extraDictionary`, then named `removeFillerWords:` and `vocabulary:`. `BuildUserDictionary` returns `IReadOnlyDictionary<string,string>`. Both match Phase 1 exactly — no drift. The Swift bench passed `mode: .casual` and the user dictionary + vocabulary, no filler removal — reproduced.

- [ ] **Step 2: Build**

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Debug`
Expected: `Build succeeded`. Fix any Whisper.net member-name issues surfaced (already resolved in Task 3 ideally).

- [ ] **Step 3: Usage/exit-code smoke (no model needed)**

```bash
dotnet run --project windows/JVoice.App -- --bench
```
Expected: prints the `usage:` line to stderr, process exit code **64**. Verify the code:
```bash
dotnet run --project windows/JVoice.App -- --bench; echo "exit=$?"
```
Expected: `exit=64`.

```bash
dotnet run --project windows/JVoice.App -- --bench C:/no/such/file.wav; echo "exit=$?"
```
Expected: `no such file: …` on stderr, `exit=66`.

- [ ] **Step 4: Commit**

```bash
git add windows/JVoice.App/Whisper/BenchRunner.cs
git commit -m "feat(whisper): --bench CLI (port of BenchRunner.swift) — model/lang/vocab/stream/no-prompt, exact format + exit codes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5b: `whisper-smoke` console tool (WPF-free E2E harness)

> A `net9.0` **console** project that exercises the engine without any WPF coupling, so the end-to-end verification (Task 6) is a plain `dotnet run`. Because `WhisperNetTranscriptionEngine` and friends live in the `net9.0-windows` `WinExe` `JVoice.App`, the tool **link-includes** those `.cs` files (rather than ProjectReferencing a `WinExe`, which the SDK may reject) plus references `JVoice.Core` and the same Whisper.net packages.

**Files:**
- Create: `windows/tools/whisper-smoke/whisper-smoke.csproj`
- Create: `windows/tools/whisper-smoke/Program.cs`
- Modify: `windows/JVoice.sln` (add the project)

**Interfaces:**
- Produces: a runnable console app: `whisper-smoke <wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab "a,b"] [--no-prompt]` that prints the raw transcript and exits 0 on a non-empty result, 1 otherwise.
- Consumes: the engine source files from `JVoice.App/Whisper/`, `JVoice.Core`, Whisper.net packages.

- [ ] **Step 1: Create `windows/tools/whisper-smoke/whisper-smoke.csproj`**

> Versions: use the **same pinned versions** recorded in Task 1 Step 6 (copy them here). `net9.0` (not `-windows`) — but it includes `WhisperRuntime.cs` which has no Windows-only API, and the engine itself uses only BCL + Whisper.net, so it compiles as plain `net9.0`. (If a linked file unexpectedly pulls a Windows-only API, target `net9.0-windows` here too — note it.)

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>JVoice.Tools.WhisperSmoke</RootNamespace>
    <AssemblyName>whisper-smoke</AssemblyName>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\JVoice.Core\JVoice.Core.csproj" />
  </ItemGroup>

  <!-- Link the engine sources (the engine lives in the WinExe app project). -->
  <ItemGroup>
    <Compile Include="..\..\JVoice.App\Whisper\WhisperRuntime.cs" Link="Whisper\WhisperRuntime.cs" />
    <Compile Include="..\..\JVoice.App\Whisper\WhisperModelStore.cs" Link="Whisper\WhisperModelStore.cs" />
    <Compile Include="..\..\JVoice.App\Whisper\WhisperNetTranscriptionEngine.cs" Link="Whisper\WhisperNetTranscriptionEngine.cs" />
  </ItemGroup>

  <!-- Same pinned Whisper.net versions as JVoice.App (copy the resolved versions). -->
  <ItemGroup>
    <PackageReference Include="Whisper.net" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime.Cuda" Version="PINNED_AT_EXECUTION" />
    <PackageReference Include="Whisper.net.Runtime.Vulkan" Version="PINNED_AT_EXECUTION" />
  </ItemGroup>

</Project>
```

> The linked types are `internal` to `JVoice.App`. Because they are **compiled into** `whisper-smoke` (not referenced across an assembly boundary), `internal` is fine — they become internal to this assembly too. No `InternalsVisibleTo` needed.

- [ ] **Step 2: Create `windows/tools/whisper-smoke/Program.cs`**

```csharp
using JVoice.App.Whisper;
using JVoice.Core.Models;

namespace JVoice.Tools.WhisperSmoke;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine(
                "usage: whisper-smoke <audio.wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab \"a,b\"] [--no-prompt]");
            return 64;
        }

        string audioPath = args[0];
        if (!File.Exists(audioPath))
        {
            Console.Error.WriteLine($"no such file: {audioPath}");
            return 66;
        }

        var model = WhisperModelOption.Tiny;
        int mi = Array.IndexOf(args, "--model");
        if (mi >= 0 && args.Length > mi + 1)
            model = args[mi + 1] switch
            {
                "tiny" => WhisperModelOption.Tiny,
                "base" => WhisperModelOption.Base,
                "small" => WhisperModelOption.Small,
                "large" => WhisperModelOption.LargeTurbo,
                _ => WhisperModelOption.Tiny,
            };

        var language = TranscriptionLanguage.English;
        int li = Array.IndexOf(args, "--lang");
        if (li >= 0 && args.Length > li + 1 && args[li + 1] is "ro" or "romanian")
            language = TranscriptionLanguage.Romanian;

        var vocab = new List<string>();
        int vi = Array.IndexOf(args, "--vocab");
        if (vi >= 0 && args.Length > vi + 1)
            vocab = args[vi + 1].Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();

        bool usePrompt = !args.Contains("--no-prompt");

        var store = new WhisperModelStore();
        Console.WriteLine($"models dir: {store.ModelsDirectory}");
        var progress = new Progress<double>(p =>
        {
            if (!double.IsNaN(p)) Console.Error.Write($"\rdownload: {p * 100,5:0.0}%   ");
        });
        // Ensure the model up front so download progress is visible.
        await store.EnsureAsync(model, progress, CancellationToken.None);
        Console.Error.WriteLine();

        var engine = new WhisperNetTranscriptionEngine(model, language, vocab, usePrompt, store);
        await engine.PrewarmAsync();
        Console.WriteLine($"runtime: {WhisperRuntime.Describe()}");

        try
        {
            string text = await engine.TranscribeAsync(audioPath, CancellationToken.None);
            Console.WriteLine($"transcript: \"{text}\"");
            return text.Trim().Length == 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"transcription failed: {ex.Message}");
            return 1;
        }
    }
}
```

- [ ] **Step 3: Add to the solution + build**

```bash
cd windows
dotnet sln add tools/whisper-smoke/whisper-smoke.csproj
dotnet build tools/whisper-smoke/whisper-smoke.csproj -c Debug
```
Expected: `Build succeeded`. Copy the pinned Whisper.net versions into the csproj if the `PINNED_AT_EXECUTION` placeholders remain (or run `dotnet add package` for each, then pin).

- [ ] **Step 4: Commit**

```bash
git add windows/tools/whisper-smoke windows/JVoice.sln
git commit -m "tools(whisper): whisper-smoke — WPF-free end-to-end transcription harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: End-to-end verification (download tiny, transcribe a known WAV, prove invariants)

> The proof gate. Generate a known 16 kHz mono 16-bit PCM WAV with real speech (Windows TTS), then verify: (a) the tiny GGML model downloads and verifies; (b) a prompted decode is **non-empty**; (c) a >30 s clip is **not truncated** with timestamps off; (d) `--bench` produces the expected output lines and exit codes; (e) the `--stream` path produces a non-null streamed result that the whole-file path corroborates. Real commands, real expected output.

**Files:**
- Create (temporary test assets, not committed): `%TEMP%\jv-known.wav`, `%TEMP%\jv-long.wav`, `%TEMP%\jv-vocab.wav` (generated; deleted after, or left in TEMP).
- (No source files; this task only runs and observes.)

**Interfaces:** none (verification only).

- [ ] **Step 1: Generate a known short speech WAV via Windows TTS (16 kHz mono 16-bit PCM)**

Use the PowerShell tool (System.Speech is built into Windows). This writes a WAV at 16 kHz mono 16-bit — exactly what the recorder/engine require:

```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$out = Join-Path $env:TEMP 'jv-known.wav'
$s.SetOutputToWaveFile($out, $fmt)
$s.Speak('The quick brown fox jumps over the lazy dog. JVoice transcribes speech on device.')
$s.Dispose()
Write-Output "wrote $out ($((Get-Item $out).Length) bytes)"
```
Expected: `wrote …\jv-known.wav (NNNN bytes)` with a multi-second WAV. **Verify the format** (must parse as 16 kHz mono): the smoke tool / bench will reject it via `WavTail` if not — if rejected, the `SpeechAudioFormatInfo` line above guarantees the right format, so a rejection means the synthesizer ignored the format; in that case resample with `ffmpeg -i jv-known.wav -ar 16000 -ac 1 -c:a pcm_s16le jv-known16.wav` (if ffmpeg present) and use that.

- [ ] **Step 2: Generate a >30 s WAV (truncation test) and a vocab-targeted WAV**

```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)

# >30s: a long passage. Repeat sentences until well past 30 seconds of speech.
$long = (1..12 | ForEach-Object { "This is sentence number $_ in a deliberately long passage that must exceed thirty seconds of audio so we can confirm whisper does not truncate it." }) -join ' '
$s1 = New-Object System.Speech.Synthesis.SpeechSynthesizer
$longPath = Join-Path $env:TEMP 'jv-long.wav'
$s1.SetOutputToWaveFile($longPath, $fmt); $s1.Rate = -2; $s1.Speak($long); $s1.Dispose()
Write-Output "wrote $longPath ($((Get-Item $longPath).Length) bytes)"

# vocab clip: says a phrase containing a custom term the prompt should help with.
$s2 = New-Object System.Speech.Synthesis.SpeechSynthesizer
$vocabPath = Join-Path $env:TEMP 'jv-vocab.wav'
$s2.SetOutputToWaveFile($vocabPath, $fmt); $s2.Speak('I am editing code in V S Code with JVoice today.'); $s2.Dispose()
Write-Output "wrote $vocabPath ($((Get-Item $vocabPath).Length) bytes)"
```
Expected: two WAVs written. `jv-long.wav` should be > ~30 s (size > ~960 KB at 16 kHz/16-bit mono ≈ 32 KB/s × 30 s). If it's under 30 s, raise the repeat count `1..12` until it exceeds it; confirm with:
```powershell
$len = (Get-Item (Join-Path $env:TEMP 'jv-long.wav')).Length
"approx seconds: {0:N1}" -f (($len - 44) / 32000)
```
Expected: `approx seconds: 30.0` or higher.

- [ ] **Step 3: Download + transcribe the known clip (proves download/verify + non-empty decode)**

```bash
dotnet run --project windows/tools/whisper-smoke -- "$TEMP/jv-known.wav" --model tiny
```
(On PowerShell: `dotnet run --project windows/tools/whisper-smoke -- "$env:TEMP\jv-known.wav" --model tiny`.)

Expected:
- prints `models dir: …\JVoice\models`
- shows `download: 100.0%` (first run only; subsequent runs skip the download because `CompleteModelPath` finds the size-correct file)
- prints `runtime: whisper.cpp (Cuda)` (or `(Cpu)` if no GPU; the dev machine should show CUDA)
- prints `transcript: "…the quick brown fox…"` — **non-empty**, recognizably the spoken text (tiny is imperfect; exact match not required — **non-empty and roughly the words** is the gate)
- exit code **0**

Confirm the model file exists and is size-correct:
```bash
ls -l "$LOCALAPPDATA/JVoice/models/ggml-tiny.bin"   # bash: $LOCALAPPDATA may be unset; use PowerShell:
```
```powershell
Get-Item (Join-Path $env:LOCALAPPDATA 'JVoice\models\ggml-tiny.bin') | Select-Object Length
```
Expected: `Length` equals the `ExpectedBytes` you recorded for tiny.

- [ ] **Step 4: VERIFY (b) — prompted decode of a vocab clip is non-empty**

```powershell
dotnet run --project windows/JVoice.App -- --bench "$env:TEMP\jv-vocab.wav" --model tiny --vocab "VS Code,JVoice"; "exit=$LASTEXITCODE"
```
Expected:
- header line ends with `decoderPrompt: on`
- `raw: "…"` is **non-empty** (this is the SuppressBlankFilter-not-needed proof — a prompted decode does not collapse to empty)
- `processed: "…"` is non-empty
- `exit=0`

A/B against `--no-prompt` to confirm the prompt path itself works and isn't the only thing producing output:
```powershell
dotnet run --project windows/JVoice.App -- --bench "$env:TEMP\jv-vocab.wav" --model tiny --vocab "VS Code,JVoice" --no-prompt; "exit=$LASTEXITCODE"
```
Expected: header ends `decoderPrompt: off`, `raw:` non-empty, `exit=0`. **Both** non-empty ⇒ the prompt neither breaks decoding nor is load-bearing for non-emptiness. Record both `raw:`/`processed:` strings in HANDOFF-WINDOWS.md for future regression comparison.

- [ ] **Step 5: VERIFY (c) — a >30 s clip is NOT truncated with timestamps off**

```powershell
dotnet run --project windows/JVoice.App -- --bench "$env:TEMP\jv-long.wav" --model tiny; "exit=$LASTEXITCODE"
```
Expected: `exit=0`, and the `raw:` transcript contains content from **near the end** of the passage, not just the first ~30 s. Concretely, the passage's later sentences mention high numbers (`sentence number 10/11/12`); confirm the transcript reaches them (TTS may render digits as words, so look for "ten/eleven/twelve" or "10/11/12"):
```powershell
$out = dotnet run --project windows/JVoice.App -- --bench "$env:TEMP\jv-long.wav" --model tiny
$raw = ($out | Select-String '^raw:').Line
if ($raw -match 'eleven|twelve|10|11|12') { "PASS: long clip not truncated" } else { "CHECK: tail content missing — inspect transcript: $raw" }
```
Expected: `PASS: long clip not truncated`. **If this fails** (tail content absent), the `WithoutTimestamps()` choice truncated — apply the documented fallback in Task 3 Step 9 (timestamps on the whole-file path only), rebuild, and re-run this step until it passes. Only then is the unconditional-no-timestamps decision locked.

- [ ] **Step 6: VERIFY (e) — the streaming path produces a corroborated result**

```powershell
dotnet run --project windows/JVoice.App -- --bench "$env:TEMP\jv-known.wav" --model tiny --stream; "exit=$LASTEXITCODE"
```
Expected:
- `stream wall: …s   post-stop (finish): …s`
- `streamed:  "…"` — **not** `nil (session fell back)` for a clean clip (a fallback is acceptable but note it; the gate is that the line prints and the process succeeds)
- `wholefile: "…"` — corroborates the streamed text (same words, allowing chunk-boundary spacing differences)
- `exit=0`

- [ ] **Step 7: Confirm idempotent download (no re-download on second run)**

Re-run Step 3. Expected: **no** `download:` progress line (or it jumps straight to a ready state) because `CompleteModelPath` finds the size-correct `ggml-tiny.bin`. This proves the locate path.

- [ ] **Step 8: Record results + clean up temp assets**

Append to `docs/HANDOFF-WINDOWS.md` a "Phase 2 E2E verification" section with: the pinned Whisper.net versions, the selected runtime (`WhisperRuntime.Describe()` output), the tiny SHA-256/size, the four `raw:`/`processed:` transcripts captured, the long-clip non-truncation PASS, and the streaming corroboration. Then optionally delete the temp WAVs:
```powershell
Remove-Item (Join-Path $env:TEMP 'jv-known.wav'),(Join-Path $env:TEMP 'jv-long.wav'),(Join-Path $env:TEMP 'jv-vocab.wav') -ErrorAction SilentlyContinue
```

- [ ] **Step 9: Final build of the whole solution + commit the handoff notes**

```bash
dotnet build windows/JVoice.sln -c Release
```
Expected: `Build succeeded` for `JVoice.Core`, `JVoice.Tests`, `JVoice.App`, `whisper-smoke`. (`JVoice.Tests` is Phase 1's and must still be green: `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` → all pass.)

```bash
git add docs/HANDOFF-WINDOWS.md
git commit -m "docs(windows): record Phase 2 E2E verification (download, non-empty prompted decode, >30s non-truncation, streaming)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (Swift behavior → task mapping)

Every behavior of `WhisperKitTranscriptionEngine`, `WhisperModelLocator`, and `BenchRunner.swift` maps to a task here (or is deliberately dropped per overview §6.3).

| Swift behavior (file:concept) | Where it lands | Notes |
| --- | --- | --- |
| `WhisperModelLocator.completeModelFolder` (only return a *complete* model) | T2 `WhisperModelStore.CompleteModelPath` | GGML `.bin` size(+SHA) check instead of `.mlmodelc`/`weight.bin` presence |
| first-run HuggingFace download | T2 `WhisperModelStore.DownloadAsync`/`EnsureAsync` | atomic `.part` + rename; the one allowed network call |
| `actor` isolation | T3 `SemaphoreSlim(1,1) _gate` | serializes load + prompt-cache |
| `loadTask` dedupe / `performLoad` | T3 `LoadFactoryAsync`/`PerformLoadAsync` | shared `Task<WhisperFactory>`; dropped on failure for retry |
| `isReady()` | T3 `IsReadyAsync` = `_factory != null` | |
| `prewarm()` (errors ignored) | T3 `PrewarmAsync` (swallows) | |
| `transcribe(audioURL:)` | T3 `TranscribeAsync` | wrapped by RegurgitationRecovery; `EmptyTranscript` on "" |
| `transcribeChunkSamples` | T3 `TranscribeChunkSamplesAsync` | same recovery wrapper |
| `decodeRecoveringFromRegurgitation` | T3 both paths → `RegurgitationRecovery.Decode` | Core type, unchanged |
| `decodeFile`/`decodeSamples` (DecodingOptions) | T3 `DecodeFileAsync`/`DecodeSamplesAsync` | one `WhisperProcessorBuilder` per decode |
| `applyVocabularyBiasing` (prompt on/off) | T3 `DecodeSamplesAsync` `WithPrompt` gate | |
| `promptTokens` caching | T3 `PromptTextLocked`/`_cachedPromptText`/`_promptComputed` | caches prompt **string** (Whisper.net tokenizes internally) |
| `updateVocabulary` invalidates cache only on change | T3 `UpdateVocabularyAsync` (SequenceEqual guard) | |
| `detectLanguage = false` + fixed `language` | T3 `WithLanguage(code)`, no detect | |
| `temperatureFallbackCount = 2` | T3 `ApplyTemperatureFallback` | mapped to temp+inc(+thresholds) |
| `stripDecoderArtifacts(text)` | T3 `DecodeSamplesAsync` final line | Core `TextProcessor.StripDecoderArtifacts` |
| `withoutTimestamps = isSingleWindowClip(...)` | **DROPPED** (T3 Step 9 documents fallback) | whisper.cpp handles long audio; verified T6 Step 5 |
| `installPromptCompatibilityFilter`/`SuppressBlankFilter`/`promptedPrefillCount` | **DROPPED** | whisper.cpp `suppress_blank=true`; verified T6 Step 4 |
| `makeStreamingSession()` / `(pollNanoseconds:)` | T4 `MakeStreamingSessionAsync` / `MakeStreamingSession(int ms)` | null when `_factory==null`; never loads from poll path |
| `chunkingStrategy = .vad` (file path) | not ported | whisper.cpp windows internally; no Whisper.net VAD knob needed |
| native runtime (CoreML) | T1 `WhisperRuntime` + runtime NuGet packages | CUDA→Vulkan→CPU auto-select |
| `BenchRunner.shouldRun` / `runAndExit` | T5 `BenchRunner.ShouldRun`/`RunAndExit` + T1 `Program.Main` branch | runs before UI |
| bench flags `--model/--lang/--vocab/--stream/--no-prompt` | T5 `RunAsync` parsing | verbatim |
| bench stdout format + exit codes (64/66/65/70/1/0) | T5 (whole-file + `RunStreamAsync`) | exact strings + codes |
| bench `--stream` replay at 10× real time | T5 `RunStreamAsync` (0.5 s slice / 50 ms) | matches Swift |
| `verify-transcription.py` (deferred) | Phase 5 `tools/verify-transcription` | overview §8 — not this phase |

## Type-consistency check (vs overview §4 + Phase 1)

All consumed names exist and match exactly:
- `ITranscriptionEngine` (+ default `PrewarmAsync`/`UpdateVocabularyAsync`/`IsReadyAsync`/`MakeStreamingSessionAsync`), `TranscriptionException` (`.AudioFileMissing`, `.UnsupportedAudioFile`, `.EmptyTranscript`, `.ModelLoadFailed`), `TranscriptionErrorKind` — Phase 1 Task 11. ✓
- `StreamingTranscriptionSession(Func<float[],Task<string>>, ChunkPlanner.Config?, int pollMilliseconds=1000)`, `Start(string)`, `Task<string?> Finish()`, `Task Cancel()` — Phase 1 Task 10. ✓
- `ChunkPlanner.Config` (default ctor) — Phase 1 Task 9. ✓
- `VocabularyPrompt.Text(IReadOnlyList<string>)` returning `string?`, `MaxWords`, `MaxPromptTokens` — Phase 1 Task 3. ✓
- `RegurgitationRecovery.Decode(bool, IReadOnlyList<string>, Func<bool,Task<string>>)` — Phase 1 Task 7. ✓
- `RepetitionGuard.Scrub` (reached via RegurgitationRecovery) — Phase 1 Task 6. ✓
- `TextProcessor.StripDecoderArtifacts(string)`, `TextProcessor.Process(string, ToneStyle, IReadOnlyDictionary<string,string>?, bool, IReadOnlyList<string>?)`, `TextProcessor.BuildUserDictionary(IReadOnlyList<string>)` — Phase 1 Task 5. ✓
- `WavTail.ParseHeader(ReadOnlySpan<byte>)→WavInfo?`, `WavTail.FloatSamples(ReadOnlySpan<short>)`, `WavTail.HeaderProbeBytes`, `WavTailReader.Open`/`.Samples(int)`, `WavInfo(DataOffset, SampleRate, Channels, BytesPerSample)` — Phase 1 Task 8. ✓
- `WhisperModelOption { Tiny, Base, Small, LargeTurbo }`, `.GgmlFileName()` — Phase 1 Task 2. ✓
- `TranscriptionLanguage { English, Romanian }`, `.WhisperCode()` — Phase 1 Task 2. ✓
- `ToneStyle.Casual` — Phase 1 Task 2. ✓
- `JVoice.Core.AppTimings.StreamingPollMs` (= 1000) — Phase 1 Task 2. ✓

Produced names match overview §4.6 exactly: `namespace JVoice.App.Whisper`; `sealed class WhisperNetTranscriptionEngine : ITranscriptionEngine` with ctor `(WhisperModelOption model, TranscriptionLanguage language, IReadOnlyList<string> vocabulary, bool useVocabularyPrompt = true, WhisperModelStore store)`; `sealed class WhisperModelStore` with `string ModelsDirectory`, `string? CompleteModelPath(WhisperModelOption)`, `Task DownloadAsync(WhisperModelOption, IProgress<double>, CancellationToken)`, and the per-model URL+SHA record; plus the `WhisperRuntime` static. No drift.

> **Ctor parameter-order note (logged assumption):** the overview lists `useVocabularyPrompt = true` *before* the (non-optional) `store` parameter. C# forbids a required parameter after an optional one, so the implementation keeps the order but makes `useVocabularyPrompt` required (callers always pass it: the bench passes `useDecoderPrompt`, the coordinator in Phase 4 passes `true`). The signature is `(WhisperModelOption model, TranscriptionLanguage language, IReadOnlyList<string> vocabulary, bool useVocabularyPrompt, WhisperModelStore store)` — same names, same order, `useVocabularyPrompt` non-defaulted. This is the only deviation from the literal §4.6 default and is intentional + forced by the language. Phase 4 wiring must pass `useVocabularyPrompt: true` explicitly.

*Next: Phase 3 (`2026-06-22-windows-port-03-platform.md`).*
