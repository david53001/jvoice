# Phase 5 — Packaging, Distribution, CI, Docs & the End-to-End Verification Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended — fresh subagent per task, review between tasks) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Read `2026-06-22-windows-port-00-overview.md` (the master plan) in full before executing this phase**, and skim `…-01-core-brain.md`, `…-02-whisper-engine.md`, `…-03-platform.md`, `…-04-ui.md` for the final project layout and the canonical names. This phase is the LAST phase: it depends on Phase 4 (the running app) and on Phase 2 (the `--bench` CLI + Whisper.net packages). It produces nothing new in the brain or the engine — it packages, documents, CI-tests, and end-to-end-verifies what Phases 1–4 built.

**Goal:** Take the working Windows app (Phase 4) and make it *shippable, reproducible, verifiable, and documented* — for **$0**, **unsigned**, **GPL-3.0**, **privacy-preserving** (zero network at runtime except the one-time model download), and **without ever pushing/publishing**. Deliver, concretely:

1. A **single-file self-contained publish** recipe (CPU "lite" `.exe`) **and** a **folder-zip "with GPU" build** that bundles the CUDA native runtime, with the exact flags, the WPF/Whisper.net gotchas solved, and a verified description of what lands in the publish folder.
2. A full **`app.manifest`** (asInvoker, per-monitor-v2 DPI, supportedOS Win10/11, longPathAware, UTF-8 active code page) + **assembly metadata** mirroring `Resources/Info.plist` + `ApplicationIcon` wired to `Assets\JVoice.ico` + the `AppUserModelID` (`com.jvoice.app`) wiring note.
3. An optional **Inno Setup installer** (`windows/installer/JVoice.iss`) installing per-user to `%LOCALAPPDATA%\Programs\JVoice` (no admin), Start-Menu shortcut, uninstaller, **no code signing**, built with the free compiler.
4. **Unsigned-distribution + SmartScreen docs** (`docs/launch/windows-distribution.md`) — the Windows analog of `docs/launch/unsigned-distribution-findings.md`.
5. A **GitHub Actions Windows CI** workflow (`.github/workflows/windows.yml`) that builds + tests on `windows-latest`, asserts tests actually ran, never launches the GUI, and never publishes/pushes. The existing macOS `test.yml` is left untouched.
6. The **end-to-end verification harness** (`windows/tools/verify-transcription/`) — a C# console port of `scripts/verify-transcription.py` that generates spoken WAVs with Windows TTS, drives them through the App's `--bench` CLI (whole-file + `--stream`), scores LCS word-retention + spurious-vocab + vocab-accuracy exactly like the Python, prints a PASS/FAIL table, and exits non-zero on any failure.
7. **Docs:** `README-WINDOWS.md` (repo root), a `## Windows port` section appended to `CLAUDE.md` (content shown here; appending is a plan step), a `windows/README.md` dev quickstart, and an updated `docs/HANDOFF-WINDOWS.md` template.
8. A **dogfood checklist** (manual; can't be CI'd) covering first-run tray/Settings, hotkey record→paste across apps, custom-word accuracy on Large/GPU, long streaming dictation, Bluetooth A2DP preservation, rapid double-press, quit-mid-recording orphan check, model-download HUD, launch-at-login, and the elevated-window UIPI graceful failure.

**"Done" looks like:** from a clean checkout with Phases 1–4 green, an implementer can (a) run `dotnet publish` with the documented flags and get a runnable single-file `JVoice.exe` (CPU) and a GPU folder-zip; (b) build `JVoice.iss` with the free Inno Setup compiler into `JVoice-Setup.exe`; (c) push a branch touching `windows/**` and watch the new `windows.yml` workflow build + run `dotnet test` green on a Windows runner (with a guard that fails if 0 tests ran); (d) run `dotnet run --project windows/tools/verify-transcription -- --model tiny --quick` and see a PASS/FAIL accuracy table; (e) read `README-WINDOWS.md` and follow the SmartScreen "Run anyway" install flow; and confirm **nothing in this phase pushes, publishes, opens a PR, or adds a remote**.

**Architecture:** Phase 5 sits entirely *around* the app — it adds packaging/CI/docs/harness files. The only code it adds is the `verify-transcription` console tool (which shells out to the already-built `JVoice.exe --bench`, exactly as the Python shells out to `.build/release/JVoice --bench`). The manifest/assembly-metadata task *finalizes* files that Phase 2 stubbed (`app.manifest`) and Phase 4 created (`Assets\JVoice.ico`, the WPF entry point) — Phase 5 owns the *final, complete* versions of those packaging artifacts and the `.csproj` publish properties.

```
Phase 4 app (windows/JVoice.App, runs + dictates)
        │
        ├── Task 1: publish recipe (single-file CPU .exe  +  GPU folder-zip)   ← .csproj publish props
        ├── Task 2: app.manifest (final) + assembly metadata + AppUserModelID + ApplicationIcon
        ├── Task 3: windows/installer/JVoice.iss (Inno Setup, per-user, unsigned)
        ├── Task 4: docs/launch/windows-distribution.md (SmartScreen "Run anyway")
        ├── Task 5: .github/workflows/windows.yml (build + dotnet test, no GUI, no publish)
        ├── Task 6: windows/tools/verify-transcription (C# port of verify-transcription.py)
        ├── Task 7: README-WINDOWS.md + CLAUDE.md §Windows + windows/README.md + HANDOFF-WINDOWS.md
        └── Task 8: docs/launch/windows-dogfood-checklist.md (manual)
```

**Tech Stack:** C# on **.NET 9** (`net9.0-windows` WPF `WinExe` for the app; `net9.0` console for the harness); `dotnet publish` single-file + self-contained; **Inno Setup 6** (free, `JRSoftware.InnoSetup` via winget) for the optional installer; **GitHub Actions** `windows-latest` runner + `actions/setup-dotnet@v4`; **`System.Speech.Synthesis`** (in-box on Windows) + **NAudio** for TTS clip generation in the harness; the App's `--bench` CLI (Phase 2) as the transcription oracle. Primary RID **win-x64**; `win-arm64` noted (CPU runtime only).

---

## Global Constraints

(From the overview §5 — every task implicitly includes these. The packaging-specific ones are copied here verbatim; do not re-derive them.)

- **.NET 9.** App = `net9.0-windows` WPF `WinExe`; the harness = `net9.0` console. `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<LangVersion>latest</LangVersion>` (inherited from `windows/Directory.Build.props`). Primary RID **win-x64**.
- **$0 budget — NO paid code-signing certificate.** An Authenticode cert is ~$200+/yr (OV) and even then SmartScreen reputation takes time. We ship **unsigned**. The Windows analog of macOS Gatekeeper "Open Anyway" is the SmartScreen **"Windows protected your PC → More info → Run anyway"** flow. Document it (Task 4); do **not** buy a cert or use any paid service. This mirrors the macOS unsigned posture exactly.
- **GPL-3.0.** All bundled dependencies must be GPL-compatible (Whisper.net MIT, whisper.cpp MIT, NAudio MIT, H.NotifyIcon MIT, SkiaSharp MIT, GGML models MIT/Whisper license — all compatible). Inno Setup itself is a build-time tool (its own license is permissive for building/distributing installers of any software); the generated installer carries no copyleft obligation beyond JVoice's own GPL-3.0. Ship a copy of `LICENSE` with every distribution.
- **Privacy (product promise — do not break it):** zero runtime network calls **except** the one-time GGML model download from Hugging Face. No telemetry, analytics, accounts, or auto-update phone-home. The publish/installer/CI add **no** network behavior to the running app. The CI restores NuGet packages (build-time only) and the harness downloads `ggml-tiny.bin` on first run (the same one allowed download) — neither is a runtime call of the shipped app.
- **Do NOT publish / push / open PRs / add remotes / create releases.** No `gh release`, no `git push`, no upload step in CI. The CI workflow may keep a **build artifact** with `actions/upload-artifact` (that stays inside the Actions run, not a public release) **only as an optional, off-by-default job** — and even that is gated so it never runs on a fork/PR and never creates a Release. Commit locally on the `windows-port` branch only.
- **Do NOT modify the macOS Swift app** (`Sources/`, `Tests/`, `Package.swift`, `Resources/`) — read-only reference. Do NOT modify the existing `.github/workflows/test.yml` (the macOS CI) — add a *separate* `windows.yml`.
- **The brain ports faithfully.** The harness scores with the **exact same thresholds and formulas** as `scripts/verify-transcription.py`: non-vocab passages require `retention ≥ 0.85` **and** `spurious-vocab == 0`; vocab passages require `retention ≥ 0.80` **and** all expected vocab phrases present. No "improvements" to the scoring during the port.

---

## File Structure (what this phase creates / modifies)

```
JVoice-Windows/
├── CLAUDE.md                                    MODIFY — append a "## Windows port" section (Task 7)
├── README-WINDOWS.md                            CREATE — Windows-facing README (Task 7)
├── .github/workflows/
│   ├── test.yml                                 UNCHANGED (macOS CI — do not touch)
│   └── windows.yml                              CREATE — Windows build + dotnet test CI (Task 5)
├── docs/
│   ├── HANDOFF-WINDOWS.md                        MODIFY/CREATE — session handoff template (Task 7)
│   └── launch/
│       ├── windows-distribution.md              CREATE — SmartScreen/unsigned findings (Task 4)
│       └── windows-dogfood-checklist.md         CREATE — manual dogfood checklist (Task 8)
└── windows/
    ├── README.md                                CREATE — dev quickstart (Task 7)
    ├── JVoice.App/
    │   ├── JVoice.App.csproj                     MODIFY — finalize publish props + assembly metadata + ApplicationIcon (Tasks 1,2)
    │   ├── app.manifest                          MODIFY — finalize (asInvoker, DPI, supportedOS, longPathAware, UTF-8) (Task 2)
    │   └── App.xaml.cs (or Program.cs)           MODIFY — add SetCurrentProcessExplicitAppUserModelID (Task 2)
    ├── installer/
    │   └── JVoice.iss                            CREATE — Inno Setup script (Task 3)
    └── tools/
        └── verify-transcription/                CREATE — C# port of verify-transcription.py (Task 6)
            ├── verify-transcription.csproj
            └── Program.cs
```

**Decisions baked into this layout (logged):**

- **Single-file CPU build + GPU folder-zip (not one universal single-file).** The CUDA native runtime (`ggml-cuda` / `cublas*` / `cudart*`) is **hundreds of MB** and `IncludeNativeLibrariesForSelfExtract` would extract all of it to a temp dir on *every* launch — slow first-run and large download even for users with no NVIDIA GPU. So: the **public "lite" download is a single-file CPU `.exe`** (whisper.cpp CPU runtime only — small, one file, runs everywhere), and the **"with GPU" download is a folder build zipped up** that keeps the `runtimes/` tree intact so Whisper.net's loader finds the CUDA library next to the exe with no extraction cost. Both are produced by the same project with different publish properties (Task 1). This is the recommendation; the justification and the exact mechanics are in Task 1.
- **The harness is a separate console project**, not a unit test, because it shells out to the built `JVoice.exe --bench` (which needs the native whisper runtime + a downloaded model — not CI-appropriate). It mirrors `verify-transcription.py`'s structure 1:1.
- **CLAUDE.md is appended, not rewritten** — Task 7 shows the exact text to append so the macOS-focused doc keeps its provenance/launch sections.

---

## Task 1: Single-file self-contained publish (CPU "lite" `.exe`) + GPU folder-zip

> Solve the three WPF/Whisper.net single-file gotchas and produce **two** distributable artifacts from the one project: a small CPU single-file `.exe` and a CUDA folder-zip. Verify exactly what ends up in each.

**Files:**
- Modify: `windows/JVoice.App/JVoice.App.csproj` (add publish properties)

**Interfaces:** none (build configuration + verified commands).

**The three gotchas (read before editing):**

1. **WPF apps cannot be trimmed.** `PublishTrimmed=true` breaks WPF (XAML reflection, BAML, dependency properties resolved by name). We MUST set `<PublishTrimmed>false</PublishTrimmed>` (this is also the default for WPF, but we pin it so nobody "optimizes" it on). Single-file is fine; trimming is not.
2. **Native libraries must self-extract.** `PublishSingleFile=true` bundles managed DLLs into the `.exe`, but native DLLs (whisper.cpp `whisper.dll`/`ggml*.dll`, NAudio's none-managed bits, SkiaSharp's `libSkiaSharp.dll`) are **not** embedded by default. `<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>` embeds them and extracts them to a temp dir at first run so the loaders find them. This works fine for the **CPU** runtime (a few MB). It is the wrong choice for the **CUDA** runtime (hundreds of MB extracted every launch) — hence the two-artifact split below.
3. **CUDA natives are huge.** `Whisper.net.Runtime.Cuda` ships `whisper.dll` + `ggml-cuda` + the bundled CUDA `cublas64_*.dll` / `cudart64_*.dll` (a single-file self-extract of that is a multi-hundred-MB temp blob per launch). Decision (justified): **omit CUDA from the single-file build; ship CUDA only in the folder build.** Whisper.net auto-selects CUDA→Vulkan→CPU from whichever native runtimes are present next to the exe (or self-extracted), so a CPU-only single-file simply runs on CPU, and the GPU folder build runs on GPU.

- [ ] **Step 1: Add the publish property groups to `windows/JVoice.App/JVoice.App.csproj`**

Open `windows/JVoice.App/JVoice.App.csproj` (created in Phase 2, fleshed out in Phase 4). Add the following two property groups **inside `<Project>`** (after the main `<PropertyGroup>`). These are conditioned on a custom `JVoiceFlavor` MSBuild property so the same project produces both flavors:

```xml
  <!-- ========================= Publish configuration ========================= -->
  <!-- Shared publish properties (apply to every `dotnet publish`). -->
  <PropertyGroup Condition="'$(PublishProtocol)' != '' or '$(_IsPublishing)' == 'true' or '$(JVoiceFlavor)' != ''">
    <!-- WPF MUST NOT be trimmed (XAML/BAML reflection breaks). Pinned on purpose. -->
    <PublishTrimmed>false</PublishTrimmed>
    <!-- Faster cold start: precompile IL to native where possible. Safe for WPF. -->
    <PublishReadyToRun>true</PublishReadyToRun>
    <!-- Embed the .NET runtime so the user needs nothing pre-installed. -->
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <!-- Don't satellite-resolve cultures we don't ship. -->
    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>
    <!-- Deterministic, reproducible-ish output. -->
    <Deterministic>true</Deterministic>
    <DebugType>none</DebugType>
    <DebugSymbols>false</DebugSymbols>
  </PropertyGroup>

  <!-- "lite" = CPU single-file. CUDA runtime is excluded so the self-extract stays small. -->
  <PropertyGroup Condition="'$(JVoiceFlavor)' == 'cpu'">
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
    <EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>
    <!-- Strip the CUDA + Vulkan native packages from THIS flavor only (keep CPU). -->
    <DefineConstants>$(DefineConstants);JVOICE_CPU_ONLY</DefineConstants>
  </PropertyGroup>

  <!-- "gpu" = folder build keeping runtimes/ on disk (CUDA found next to the exe, no extract cost). -->
  <PropertyGroup Condition="'$(JVoiceFlavor)' == 'gpu'">
    <PublishSingleFile>false</PublishSingleFile>
  </PropertyGroup>

  <!-- Exclude the CUDA/Vulkan native runtime packages from the CPU single-file flavor.
       Without this, the single-file self-extract would balloon to hundreds of MB. -->
  <ItemGroup Condition="'$(JVoiceFlavor)' == 'cpu'">
    <PackageReference Update="Whisper.net.Runtime.Cuda" ExcludeAssets="all" PrivateAssets="all" />
    <PackageReference Update="Whisper.net.Runtime.Vulkan" ExcludeAssets="all" PrivateAssets="all" />
  </ItemGroup>
```

> **Why the `PackageReference Update … ExcludeAssets="all"`:** the CUDA/Vulkan runtime packages are referenced in the main `<ItemGroup>` (Phase 2, Task 1). `Update` (not `Include`) re-targets the *existing* reference for the `cpu` flavor and tells the SDK not to copy that package's native assets into the publish output — so the CPU single-file contains only the CPU `whisper.dll`/`ggml*.dll`. **Verify after publishing** (Step 4) that no `cublas`/`cudart`/`ggml-cuda` files were extracted. If `ExcludeAssets` on a runtime package proves ineffective with the installed Whisper.net version (some runtime packages copy via build targets, not assets), the fallback is to delete the CUDA files from the publish folder in the publish command (Step 3 shows the fallback `rm` line) — note which approach worked in HANDOFF-WINDOWS.md.

- [ ] **Step 2: Confirm the project still builds normally** (no flavor set = normal dev build, unaffected)

Run: `dotnet build windows/JVoice.App/JVoice.App.csproj -c Release`
Expected: `Build succeeded`, 0 errors. (The flavor-conditioned groups are inactive for a plain build.)

- [ ] **Step 3: Publish the CPU single-file "lite" build**

```bash
dotnet publish windows/JVoice.App/JVoice.App.csproj -c Release -r win-x64 \
  -p:JVoiceFlavor=cpu \
  -p:PublishSingleFile=true \
  -p:SelfContained=true \
  -p:PublishTrimmed=false \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:PublishReadyToRun=true \
  -o windows/artifacts/cpu
```

Expected: `… -> …\windows\artifacts\cpu\` and the folder contains essentially **one** big file: `JVoice.exe` (plus possibly `JVoice.pdb` if symbols leaked — `DebugType=none` should prevent it). The CPU `whisper.dll`/`ggml*.dll`, SkiaSharp, and NAudio natives are embedded inside `JVoice.exe`.

> **Fallback if CUDA assets still slipped in** (only if Step 4 finds them): publish the CPU flavor, then prune, then it's still a single file so this won't apply — but if you instead chose a folder CPU build, prune with:
> ```bash
> # (only the GPU folder build has a runtimes/ tree to prune; CPU single-file has none)
> find windows/artifacts/cpu -iname '*cuda*' -o -iname 'cublas*' -o -iname 'cudart*' | xargs -r rm -f
> ```

- [ ] **Step 4: Verify the CPU single-file is small and self-contained**

```bash
ls -lh windows/artifacts/cpu/
```
Expected: `JVoice.exe` is on the order of **~70–160 MB** (WPF + .NET runtime + CPU whisper natives + SkiaSharp), **not** 400 MB+. If it is 400 MB+, the CUDA natives leaked in — the `ExcludeAssets` did not take; apply the HANDOFF note and re-publish.

Confirm no CUDA temp extraction occurs at runtime by listing what the exe extracts on first launch (optional, dev machine):
```powershell
# Launch once, then inspect the self-extract temp dir (named after the app + a hash):
Get-ChildItem "$env:TEMP\.net\JVoice" -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'cuda|cublas|cudart' } |
  Select-Object FullName
```
Expected: **no rows** (no CUDA files extracted). The presence of `whisper.dll` + `ggml-cpu`/`ggml-base` is fine.

- [ ] **Step 5: Verify the CPU single-file actually runs (headless `--bench` smoke)**

Generate a tiny WAV and bench it through the published exe (proves the single-file self-extract resolves the CPU whisper runtime):
```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$out = Join-Path $env:TEMP 'jv-pub.wav'
$s.SetOutputToWaveFile($out, $fmt); $s.Speak('The quick brown fox jumps over the lazy dog.'); $s.Dispose()
& "windows/artifacts/cpu/JVoice.exe" --bench $out --model tiny
"exit=$LASTEXITCODE"
```
Expected: prints `runtime: whisper.cpp (Cpu)`, a non-empty `raw: "…"` line, `processed: "…"`, and `exit=0`. (First run downloads `ggml-tiny.bin`.) **This proves the single-file CPU build is a valid, runnable distributable.**

- [ ] **Step 6: Publish the GPU folder build and zip it**

```bash
dotnet publish windows/JVoice.App/JVoice.App.csproj -c Release -r win-x64 \
  -p:JVoiceFlavor=gpu \
  -p:PublishSingleFile=false \
  -p:SelfContained=true \
  -p:PublishTrimmed=false \
  -p:PublishReadyToRun=true \
  -o windows/artifacts/gpu
```

Expected: a **folder** containing `JVoice.exe` + many DLLs + a `runtimes/win-x64/native/` subtree holding the CPU **and** CUDA native libraries (`whisper.dll`, `ggml*.dll`, `cublas64_*.dll`, `cudart64_*.dll`, etc.). Whisper.net's loader finds the CUDA library here at runtime — no self-extract.

Zip the folder (PowerShell, since `Compress-Archive` is in-box):
```powershell
Compress-Archive -Path windows/artifacts/gpu/* -DestinationPath windows/artifacts/JVoice-gpu-win-x64.zip -Force
"zip bytes: $((Get-Item windows/artifacts/JVoice-gpu-win-x64.zip).Length)"
```
Expected: a multi-hundred-MB zip (CUDA natives dominate). This is the "with GPU" public download.

- [ ] **Step 7: Verify the GPU folder build runs on the GPU**

```powershell
& "windows/artifacts/gpu/JVoice.exe" --bench (Join-Path $env:TEMP 'jv-pub.wav') --model tiny
"exit=$LASTEXITCODE"
```
Expected: prints `runtime: whisper.cpp (Cuda)` on this RTX 3060 Ti dev machine, non-empty `raw:`, `exit=0`. (If CUDA isn't available it would fall back to CPU — still exit 0, but the dev machine should show CUDA.)

- [ ] **Step 8: Copy LICENSE into both artifact folders** (GPL-3.0 obligation: ship the license)

```bash
cp LICENSE windows/artifacts/cpu/LICENSE.txt
cp LICENSE windows/artifacts/gpu/LICENSE.txt
```

- [ ] **Step 9: `win-arm64` note (no build required here)** — record in HANDOFF-WINDOWS.md (Task 7):
  *"CUDA is x64-only. An ARM64 build (`-r win-arm64 -p:JVoiceFlavor=cpu`) is CPU-runtime-only and is not part of the standard release set. Build it on demand by swapping the RID; `Whisper.net.Runtime` ships ARM64 CPU binaries, `Whisper.net.Runtime.Cuda` does not. Verify `Whisper.net.Runtime` has a `win-arm64` native asset before promising an ARM64 build."*

- [ ] **Step 10: Add `windows/artifacts/` to `.gitignore`** (publish output is never committed)

Append to the repo-root `.gitignore` (the `windows/**/publish/` and `windows/**/bin/` lines already exist from Phase 1; add the artifacts dir):
```gitignore
windows/artifacts/
```

- [ ] **Step 11: Commit**

```bash
git add windows/JVoice.App/JVoice.App.csproj .gitignore
git commit -m "build(windows): publish recipe — CPU single-file lite + CUDA folder-zip (WPF no-trim, native self-extract, ReadyToRun)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `app.manifest` (final) + assembly metadata + `ApplicationIcon` + `AppUserModelID`

> Phase 2 stubbed `app.manifest` (DPI + asInvoker only). This task writes the **final** manifest (adds `<supportedOS>` Win10/11, `longPathAware`, `activeCodePage` UTF-8), fills in the assembly metadata to mirror `Resources/Info.plist`, wires `ApplicationIcon` to the generated `Assets\JVoice.ico`, and sets the `AppUserModelID` in app startup.

**Files:**
- Modify: `windows/JVoice.App/app.manifest`
- Modify: `windows/JVoice.App/JVoice.App.csproj` (assembly metadata + `ApplicationIcon`)
- Modify: `windows/JVoice.App/App.xaml.cs` (the WPF startup; or `Program.cs` if Phase 4 kept a custom entry) — add `SetCurrentProcessExplicitAppUserModelID`

**Interfaces:** none (metadata + a one-line P/Invoke).

**`Info.plist` → Windows mapping (each row reproduced):**

| `Resources/Info.plist` | Windows home |
| --- | --- |
| `CFBundleName` / `CFBundleDisplayName` = "JVoice" | `<Product>JVoice</Product>` + manifest `name` + file description |
| `CFBundleShortVersionString` = 1.0.0 | `<Version>1.0.0</Version>` (+ `AssemblyVersion`/`FileVersion`) + manifest `version="1.0.0.0"` |
| `CFBundleIdentifier` = com.jvoice.app | `AppUserModelID` "com.jvoice.app" (taskbar/toast grouping) |
| `LSMinimumSystemVersion` 14.0 | `<supportedOS>` Win10/11 GUIDs |
| `NSHighResolutionCapable` | per-monitor-v2 DPI awareness (manifest) |
| Copyright (implicit GPL-3.0) | `<Copyright>GPL-3.0</Copyright>` |
| Company "JVoice" | `<Company>JVoice</Company>` |

- [ ] **Step 1: Write the final `windows/JVoice.App/app.manifest`** (replace the Phase 2 stub entirely)

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="JVoice.app" />

  <!-- Run as the invoking user — NO UAC elevation. JVoice never needs admin.
       Consequence (documented, not worked around): a non-elevated process cannot
       SendInput into an elevated (admin) window (UIPI). See overview §6.4 and the
       dogfood checklist's elevated-window item. -->
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>

  <!-- Declare Windows 10 and Windows 11 support so the OS reports the real version
       (not the Windows 8.1 compatibility shim) and enables Win10+ behaviors. -->
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10 and Windows 11 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>

  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <!-- Per-monitor-v2 DPI so the HUD pill and Settings panel stay crisp across
           mixed-DPI monitors (the NSHighResolutionCapable analog). -->
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <!-- Legacy fallback for older shells that ignore PerMonitorV2. -->
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
      <!-- Opt into long paths (model/temp paths under deep user profiles). -->
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
      <!-- Make the process code page UTF-8 so non-ASCII transcripts (Romanian) and
           file paths round-trip through Win32 *A APIs and the console. -->
      <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
    </windowsSettings>
  </application>
</assembly>
```

> **Note on the supportedOS GUID:** `{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}` is the canonical Windows 10/11 compatibility GUID published by Microsoft (Windows 10 and later report through it). Do not invent a GUID. This single entry covers both Win10 and Win11.

- [ ] **Step 2: Add assembly metadata + `ApplicationIcon` to `windows/JVoice.App/JVoice.App.csproj`**

Add these into the **main** `<PropertyGroup>` of `JVoice.App.csproj` (the one with `<OutputType>WinExe</OutputType>`). `<Version>`/`<Company>`/`<Product>`/`<Copyright>` are also set in `Directory.Build.props` (Phase 1) — repeat the app-specific ones here for clarity and add the file-description/icon:

```xml
    <!-- Assembly metadata mirroring Resources/Info.plist -->
    <Product>JVoice</Product>
    <AssemblyTitle>JVoice</AssemblyTitle>
    <Description>JVoice — free, on-device voice dictation for Windows (Whisper, no cloud).</Description>
    <Company>JVoice</Company>
    <Copyright>GPL-3.0-only — © JVoice contributors</Copyright>
    <Version>1.0.0</Version>
    <AssemblyVersion>1.0.0.0</AssemblyVersion>
    <FileVersion>1.0.0.0</FileVersion>
    <NeutralLanguage>en</NeutralLanguage>
    <!-- The black-squircle "J" icon generated by windows/tools/generate-icon (Phase 4). -->
    <ApplicationIcon>Assets\JVoice.ico</ApplicationIcon>
```

> **`Assets\JVoice.ico` must exist** (Phase 4, overview §4.8 / §8 maps `scripts/generate-icon.swift` → `tools/generate-icon` + `Assets/JVoice.ico`). If this task runs before that asset exists, generate it first via `dotnet run --project windows/tools/generate-icon` (Phase 4). The `.ico` becomes the `.exe`'s shell icon (Explorer, taskbar, Alt-Tab).

- [ ] **Step 3: Set the `AppUserModelID` at app startup** (taskbar/toast grouping → `com.jvoice.app`)

Windows groups taskbar buttons and routes toast notifications by the process's **Application User Model ID (AppUserModelID / AUMID)**. Set it **as the very first thing** in startup, before any window is shown. Edit the WPF entry point. If Phase 4 made an `App.xaml`/`App.xaml.cs`, add the P/Invoke + call in the `OnStartup` override (or in the `[STAThread] Main` if Phase 4 kept a custom `Program.Main`). The canonical place is the earliest startup code.

Add this to `windows/JVoice.App/App.xaml.cs` (adjust the class/namespace to whatever Phase 4 produced):

```csharp
using System.Runtime.InteropServices;
using System.Windows;

namespace JVoice.App;

public partial class App : Application
{
    /// JVoice's stable Application User Model ID. Matches the macOS bundle id
    /// (com.jvoice.app). Windows uses it to group taskbar buttons and route toast
    /// notifications for this process. MUST be set before any window appears.
    private const string AppUserModelId = "com.jvoice.app";

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string AppID);

    protected override void OnStartup(StartupEventArgs e)
    {
        // Group the taskbar/toasts under "com.jvoice.app". Best-effort: a failure
        // here is non-fatal (the app simply falls back to the default per-exe AUMID).
        try { SetCurrentProcessExplicitAppUserModelID(AppUserModelId); } catch { /* non-fatal */ }

        base.OnStartup(e);
        // ... (Phase 4's existing startup: single-instance, tray, first-run Settings, --bench branch)
    }
}
```

> **Important ordering note for Phase 4 integration:** the `BenchRunner.ShouldRun(args)` branch (Phase 2) must still run *before* any UI and before `App.Run()`. If Phase 4 kept a custom `[STAThread] Main` that calls `BenchRunner` first, put the `SetCurrentProcessExplicitAppUserModelID` call there too (right after the bench branch returns false), not only in `OnStartup`. Either location is fine as long as it precedes the first window. Do not duplicate the call in both if `OnStartup` always runs.

- [ ] **Step 4: Build and confirm the icon + metadata are embedded**

```bash
dotnet build windows/JVoice.App/JVoice.App.csproj -c Release
```
Expected: `Build succeeded`. Then inspect the produced exe's metadata:
```powershell
$exe = (Get-ChildItem windows/JVoice.App/bin/Release -Recurse -Filter JVoice.exe | Select-Object -First 1).FullName
(Get-Item $exe).VersionInfo | Format-List ProductName, FileVersion, ProductVersion, CompanyName, LegalCopyright, FileDescription
```
Expected: `ProductName = JVoice`, `FileVersion = 1.0.0.0`, `CompanyName = JVoice`, `LegalCopyright` contains `GPL-3.0`, `FileDescription` = the `<Description>` text. The exe in Explorer shows the black-squircle "J" icon.

- [ ] **Step 5: Confirm the manifest is embedded** (DPI/asInvoker/longPath/UTF-8)

```powershell
# Extract the embedded manifest and confirm the key settings are present.
$exe = (Get-ChildItem windows/JVoice.App/bin/Release -Recurse -Filter JVoice.exe | Select-Object -First 1).FullName
# mt.exe ships with the Windows SDK; if absent, just confirm the manifest source compiled (build succeeded embeds it).
if (Get-Command mt.exe -ErrorAction SilentlyContinue) {
  & mt.exe -inputresource:"$exe;#1" -out:"$env:TEMP\jv.manifest" 2>$null
  Get-Content "$env:TEMP\jv.manifest" | Select-String 'asInvoker|PerMonitorV2|longPathAware|activeCodePage|supportedOS'
} else {
  "mt.exe not found; build succeeded => manifest embedded. Manifest source: windows/JVoice.App/app.manifest"
}
```
Expected: lines containing `asInvoker`, `PerMonitorV2`, `longPathAware`, `activeCodePage`, and `supportedOS` (or the mt.exe-not-found fallback message). Running the app and observing crisp text on a high-DPI monitor + no UAC prompt is the functional confirmation.

- [ ] **Step 6: Commit**

```bash
git add windows/JVoice.App/app.manifest windows/JVoice.App/JVoice.App.csproj windows/JVoice.App/App.xaml.cs
git commit -m "feat(windows): finalize app.manifest (DPI/asInvoker/longPath/UTF-8/supportedOS) + assembly metadata + AppUserModelID

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Optional Inno Setup installer (`windows/installer/JVoice.iss`)

> A per-user (no-admin) installer built with the **free** Inno Setup compiler. Installs to `%LOCALAPPDATA%\Programs\JVoice`, creates a Start-Menu shortcut, ships a clean uninstaller, and is **unsigned** (consistent with the $0 budget). Launch-at-login is handled inside the app (registry Run key, Phase 3 `LaunchAtLogin`), so the installer does NOT touch the Run key. The installer packages the **GPU folder build** output (or CPU folder build — see the `SourceDir` note).

**Files:**
- Create: `windows/installer/JVoice.iss`

**Interfaces:** none (build-time script + verified command).

- [ ] **Step 1: Install the free Inno Setup compiler** (one time, build machine only)

```powershell
winget install --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements
```
Expected: Inno Setup 6.x installed. The compiler is `ISCC.exe`, typically at `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`. Confirm:
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /? | Select-Object -First 3
```

- [ ] **Step 2: Produce the folder build the installer will package**

The installer packages a **folder** publish (not the single-file exe — Inno bundles the loose files itself). Use the GPU folder build from Task 1 Step 6 (it includes the CUDA + CPU runtimes, so the installed app gets GPU acceleration). For a CPU-only installer, publish a CPU **folder** build instead:
```bash
# CPU folder build (smaller installer, no CUDA):
dotnet publish windows/JVoice.App/JVoice.App.csproj -c Release -r win-x64 \
  -p:JVoiceFlavor=cpu -p:PublishSingleFile=false -p:SelfContained=true \
  -p:PublishTrimmed=false -p:PublishReadyToRun=true \
  -o windows/artifacts/installer-src
cp LICENSE windows/artifacts/installer-src/LICENSE.txt
```
> The `.iss` below points `SourceDir`-style `Source:` globs at `windows\artifacts\installer-src`. To build a GPU installer instead, point it at `windows\artifacts\gpu`.

- [ ] **Step 3: Create `windows/installer/JVoice.iss`** (complete script)

```iss
; JVoice — Windows installer (Inno Setup 6).
; Per-user, NO admin required. Unsigned (matches the $0-budget posture; users
; clear SmartScreen via "More info -> Run anyway" — see docs/launch/windows-distribution.md).
; Launch-at-login is handled inside the app (registry Run key), so this installer
; does NOT add a Run entry. Built with the free ISCC.exe (winget JRSoftware.InnoSetup).

#define MyAppName "JVoice"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "JVoice"
#define MyAppExeName "JVoice.exe"
; The publish output folder this installer packages (Task 3 Step 2).
; Change to ..\artifacts\gpu for the GPU build.
#define MyAppSrc "..\artifacts\installer-src"

[Setup]
AppId={{B2F1C7E4-9A3D-4C5E-8F6A-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Per-user install: no admin, no UAC prompt. Matches the app's asInvoker manifest.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Where the built setup .exe lands and what it's called.
OutputDir=..\artifacts\installer
OutputBaseFilename=JVoice-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app's own icon for the installer + Add/Remove Programs entry.
SetupIconFile=..\JVoice.App\Assets\JVoice.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; GPL-3.0: show the license during install.
LicenseFile=..\artifacts\installer-src\LICENSE.txt
; We are unsigned — no SignTool directive on purpose.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Copy the entire publish folder (exe + DLLs + runtimes\ tree + LICENSE).
Source: "{#MyAppSrc}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Offer to launch JVoice after install (it goes to the tray; Ctrl+Shift+Space to dictate).
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Leave user data (%APPDATA%\JVoice settings/stats) and downloaded models
; (%LOCALAPPDATA%\JVoice\models) in place on uninstall — the user may reinstall.
; Only the program files under {app} are removed by the standard uninstaller.
Type: filesandordirs; Name: "{app}"
```

> **Notes:**
> - `PrivilegesRequired=lowest` + `DefaultDirName={localappdata}\Programs\{#MyAppName}` = a true per-user install, no admin, no UAC. This matches the app's `asInvoker` manifest and the macOS "drag to /Applications then Open Anyway" no-elevation spirit.
> - **No `SignTool`/signing directive** — deliberately unsigned ($0 budget). The setup `.exe` will itself trip SmartScreen; the same "Run anyway" flow (Task 4) applies to the installer.
> - The installer does **not** write the launch-at-login Run key. The app's `LaunchAtLogin` service (Phase 3) owns that and does a first-run enable, so the installer staying out of it avoids a double-managed entry.
> - User settings/stats/models are intentionally preserved on uninstall (they live under `%APPDATA%\JVoice` / `%LOCALAPPDATA%\JVoice\models`, outside `{app}`).

- [ ] **Step 4: Build the installer**

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\JVoice.iss
```
Expected: compiles to `windows\artifacts\installer\JVoice-Setup-1.0.0.exe`. The compiler prints `Successful compile` and the output path.

- [ ] **Step 5: Smoke-test the installer (per-user, no admin)**

Run `windows\artifacts\installer\JVoice-Setup-1.0.0.exe`. Expected (you may hit SmartScreen — that is the point; click More info → Run anyway):
- No UAC prompt (per-user).
- License page shows GPL-3.0.
- Installs to `%LOCALAPPDATA%\Programs\JVoice`.
- Start-Menu "JVoice" shortcut created; the app launches to the tray.
- Add/Remove Programs (`appwiz.cpl` / Settings → Apps) lists "JVoice 1.0.0" with the "J" icon and an uninstaller that removes `{app}` cleanly.

Confirm the install location:
```powershell
Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\JVoice\JVoice.exe')
```
Expected: `True`. Then uninstall via Settings → Apps → JVoice → Uninstall, and confirm `{app}` is gone but `%APPDATA%\JVoice` (if you'd created settings) remains.

- [ ] **Step 6: Add installer output to `.gitignore`** (already covered by `windows/artifacts/` from Task 1 Step 10 — confirm it's there; the `.iss` source IS committed, the built `.exe` is not).

- [ ] **Step 7: Commit**

```bash
git add windows/installer/JVoice.iss
git commit -m "build(windows): optional Inno Setup installer (per-user, no admin, unsigned, Start-Menu + uninstaller)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Unsigned distribution + SmartScreen docs (`docs/launch/windows-distribution.md`)

> The Windows analog of `docs/launch/unsigned-distribution-findings.md`. Explains the SmartScreen "Run anyway" flow, why $0 budget means unsigned, the zip-vs-installer trade-offs, and that this matches the macOS posture. No paid services.

**Files:**
- Create: `docs/launch/windows-distribution.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `docs/launch/windows-distribution.md`** (complete content)

````markdown
# Windows Distribution & SmartScreen Findings

> The Windows counterpart of `unsigned-distribution-findings.md` (macOS). JVoice on
> Windows ships **unsigned** for the same reason it ships unsigned on macOS: **$0
> budget**. This documents the one-time SmartScreen warning users see, how they
> clear it, and the distribution choices that follow.

## Why unsigned

- An **Authenticode code-signing certificate costs ~$200+/yr** (OV) — and even after
  buying one, Microsoft **SmartScreen** still shows the warning until the binary
  builds up *reputation* (download volume + time). An **EV certificate** (instant
  reputation) is more expensive still and requires a hardware token / business
  identity. None of that fits the $0 budget.
- This is the **direct analog of the macOS posture**: macOS skips the $99/yr Apple
  Developer notarization, Windows skips the ~$200+/yr Authenticode cert. Both ship
  free, open-source, unsigned, and document the one-time "let me run it" click.
- **No paid services anywhere** — no signing, no notarization, no paid CDN. GitHub
  Releases (free) is the only distribution channel, exactly as on macOS.

## What the user sees (SmartScreen) and how they clear it

The **first time** a user runs an unsigned, low-reputation `.exe` downloaded from the
internet, Windows Defender SmartScreen shows a blue dialog:

> **Windows protected your PC**
> Microsoft Defender SmartScreen prevented an unrecognized app from starting.
> Running this app might put your PC at risk.

The **Run anyway** button is *hidden behind a link*. The exact steps to put in the
README (this is the Windows equivalent of macOS "System Settings → Open Anyway"):

1. Double-click `JVoice.exe` (or `JVoice-Setup-1.0.0.exe`).
2. SmartScreen says *"Windows protected your PC."* Click **More info**.
3. A **Run anyway** button appears. Click it. JVoice launches.
4. You only do this **once** per downloaded file — Windows remembers the choice for
   that exact file (it clears the Mark-of-the-Web on first allow).

> If the **Run anyway** button is missing entirely, the machine has SmartScreen set to
> *Block* by an admin/Group Policy (rare on personal machines). The workaround is to
> right-click the file → **Properties** → check **Unblock** at the bottom → **OK**,
> then launch. This removes the Mark-of-the-Web (the `Zone.Identifier` alternate data
> stream) that triggers SmartScreen.

## Distribution format: single-file `.exe` vs zip vs installer

| Format | Pros | Cons |
| --- | --- | --- |
| **Single-file `JVoice.exe` (CPU "lite")** | One file, smallest download, no install step, easy to verify. Best "download and run". | No GPU; first launch is slightly slower (self-extract of native libs to temp). |
| **Folder zip (GPU build)** | GPU (CUDA) acceleration; no per-launch extraction. | Large (CUDA natives are hundreds of MB); user must unzip before running; **keep the `runtimes\` folder next to the exe**. |
| **Inno Setup installer (`JVoice-Setup.exe`)** | Start-Menu shortcut, clean uninstaller, familiar UX, per-user (no admin). | Still unsigned (SmartScreen applies to the installer too); an extra build tool. |

**Recommendation** (mirrors macOS "DMG, not bare zip"):
- Primary public download = the **CPU single-file `.exe`** (works on every Windows
  PC, one file, easiest to trust/verify). Reputation accrues fastest on one stable
  file name.
- Secondary = the **GPU folder zip** for users with NVIDIA GPUs who want speed.
- Tertiary = the **installer** for users who prefer Start-Menu + uninstaller.
- **Mark-of-the-Web caveat:** a `.zip` carries MotW to the files it contains on
  extraction (Windows propagates the zone), so unzipping a GPU build and running its
  exe also trips SmartScreen once — same "Run anyway" flow. A single `.exe` only
  trips once. Prefer the single `.exe` as the headline download for this reason.

## Trust strategy for an unsigned app asking for the microphone

Lead loudly with the same trust signals as macOS:
- **Open source + 100% on-device + zero telemetry + no accounts.**
- A README section "First run on Windows" with the exact **More info → Run anyway**
  steps and (later) a screenshot.
- Build-from-source instructions (`dotnet publish`) so skeptics can produce the binary
  themselves and never touch the prebuilt one.

## Reputation over time (for later, once there's traction)

- SmartScreen reputation is **per-file-hash + per-signer**. An unsigned app earns
  reputation slowly as more people download the same hash and click "Run anyway";
  every new release resets it (new hash). A cheap OV cert *with the same signer across
  releases* would let reputation accumulate across versions — revisit if/when there's
  revenue (same trigger as the macOS $99 notarization decision).
- Until then: keep the headline download a **single, stable-named `.exe`**, host on
  **GitHub Releases** (free, trusted host helps), and document the one click.

## Caveats to re-verify near release

- Whether Windows 11 tightens SmartScreen defaults (the "Run anyway" link has moved /
  been demoted across builds). Re-screenshot the flow at release time.
- Whether `Compress-Archive`-produced zips propagate MotW identically to 7-Zip ones
  (they do today; re-check if users report no SmartScreen prompt — that would mean MotW
  isn't being applied and is a *worse* security story to advertise).
````

- [ ] **Step 2: Commit**

```bash
git add docs/launch/windows-distribution.md
git commit -m "docs(launch): Windows unsigned-distribution + SmartScreen 'Run anyway' findings (macOS-posture analog)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: GitHub Actions Windows CI (`.github/workflows/windows.yml`)

> A separate workflow (the macOS `test.yml` is untouched). On push/PR touching `windows/**`, on `windows-latest`, with .NET 9: restore, build `-c Release`, `dotnet test` the unit suite, and **assert tests actually ran** (fail if 0). Does NOT launch the GUI. Does NOT publish/push/release. An optional, gated build-artifact job is included but uploads only to the Actions run (never a public release).

**Files:**
- Create: `.github/workflows/windows.yml`

**Interfaces:** none (CI configuration).

- [ ] **Step 1: Create `.github/workflows/windows.yml`** (complete workflow)

```yaml
name: Windows

on:
  pull_request:
    paths:
      - "windows/**"
      - ".github/workflows/windows.yml"
  push:
    branches: [main, "windows-port", "feat/**", "fix/**"]
    paths:
      - "windows/**"
      - ".github/workflows/windows.yml"

# No special permissions — this workflow never writes to the repo, never releases.
permissions:
  contents: read

jobs:
  build-test:
    name: build + dotnet test
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up .NET 9
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "9.0.x"

      - name: Restore
        run: dotnet restore windows/JVoice.sln

      - name: Build (Release)
        run: dotnet build windows/JVoice.sln -c Release --no-restore

      # Run the xUnit suite (JVoice.Core's brain tests). The native Whisper engine,
      # the WPF GUI, and the verify-transcription harness are NOT exercised here —
      # they need a GPU/mic/model and a desktop session, which CI runners lack.
      # We collect a .trx so the next step can assert tests actually executed.
      - name: Test (JVoice.Tests)
        run: >
          dotnet test windows/JVoice.Tests/JVoice.Tests.csproj
          -c Release --no-build
          --logger "trx;LogFileName=test-results.trx"
          --results-directory "${{ github.workspace }}/test-results"

      # Guard against the silent "0 tests ran" trap (the Windows analog of the
      # macOS workflow's swift-testing count check). Parse the .trx counters and
      # fail if the executed/total count is 0.
      - name: Assert tests actually ran
        shell: pwsh
        run: |
          $trx = Get-ChildItem "${{ github.workspace }}/test-results" -Recurse -Filter *.trx | Select-Object -First 1
          if (-not $trx) {
            Write-Error "No .trx test result file was produced — the test run did not execute."
            exit 1
          }
          [xml]$doc = Get-Content $trx.FullName
          $counters = $doc.TestRun.ResultSummary.Counters
          $total    = [int]$counters.total
          $executed = [int]$counters.executed
          $passed   = [int]$counters.passed
          $failed   = [int]$counters.failed
          Write-Host "Tests — total=$total executed=$executed passed=$passed failed=$failed"
          if ($total -le 0 -or $executed -le 0) {
            Write-Error "0 tests executed (total=$total, executed=$executed). The suite is being silently skipped."
            exit 1
          }
          if ($failed -gt 0) {
            Write-Error "$failed test(s) failed."
            exit 1
          }
          Write-Host "PASS: $passed/$total tests passed."

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: windows-test-results
          path: "${{ github.workspace }}/test-results/*.trx"
          if-no-files-found: warn

  # OPTIONAL, OFF BY DEFAULT: produce the CPU single-file build as a CI artifact for
  # inspection. It does NOT create a Release, does NOT push, does NOT run on PRs/forks.
  # Manually triggered via the Actions "Run workflow" UI (workflow_dispatch) only.
  build-artifact:
    name: build CPU single-file (artifact only)
    needs: build-test
    if: github.event_name == 'workflow_dispatch'
    runs-on: windows-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Set up .NET 9
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: "9.0.x"
      - name: Publish CPU single-file
        run: >
          dotnet publish windows/JVoice.App/JVoice.App.csproj -c Release -r win-x64
          -p:JVoiceFlavor=cpu -p:PublishSingleFile=true -p:SelfContained=true
          -p:PublishTrimmed=false -p:IncludeNativeLibrariesForSelfExtract=true
          -p:PublishReadyToRun=true -o ${{ github.workspace }}/out/cpu
      - name: Upload exe artifact (NOT a release)
        uses: actions/upload-artifact@v4
        with:
          name: JVoice-cpu-win-x64
          path: ${{ github.workspace }}/out/cpu/JVoice.exe
          if-no-files-found: error
```

> **Add `workflow_dispatch` to enable the optional artifact job manually.** The `on:` block above triggers on push/PR; the `build-artifact` job is gated on `github.event_name == 'workflow_dispatch'`, so it only runs when a maintainer clicks "Run workflow". To make that possible, also add `workflow_dispatch:` under `on:`:
>
> ```yaml
> on:
>   workflow_dispatch:
>   pull_request:
>     paths: [...]
>   push:
>     branches: [...]
>     paths: [...]
> ```
>
> Add the `workflow_dispatch:` line when you create the file (it's omitted from the main block above only to keep the trigger list readable — include it). The artifact job **never** runs automatically and **never** creates a Release — it only attaches an `.exe` to a manually-triggered Actions run for inspection. This respects "no publishing/pushing".

- [ ] **Step 2: Lint the YAML locally** (no push)

```powershell
# Confirm the YAML parses (uses the in-box PowerShell; or `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/windows.yml'))"` if Python present).
Get-Content .github/workflows/windows.yml -Raw | Out-Null
"yaml file present: $(Test-Path .github/workflows/windows.yml)"
```
If `actionlint` is available (`winget install rhysd.actionlint` or `go install`), run:
```powershell
if (Get-Command actionlint -ErrorAction SilentlyContinue) { actionlint .github/workflows/windows.yml } else { "actionlint not installed; skipping (YAML present)" }
```
Expected: no errors (or the skip message).

- [ ] **Step 3: Locally reproduce what CI does** (the real verification — CI is just this on a runner)

```bash
dotnet restore windows/JVoice.sln
dotnet build windows/JVoice.sln -c Release --no-restore
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj -c Release --no-build \
  --logger "trx;LogFileName=test-results.trx" --results-directory ./test-results
```
Expected: `Build succeeded`; `dotnet test` prints `Passed!  - Failed: 0, Passed: N, …` with **N > 0**; a `test-results/test-results.trx` is produced. Confirm the count guard logic against the real trx:
```powershell
[xml]$doc = Get-Content (Get-ChildItem ./test-results -Recurse -Filter *.trx | Select-Object -First 1).FullName
$c = $doc.TestRun.ResultSummary.Counters
"total=$($c.total) executed=$($c.executed) passed=$($c.passed) failed=$($c.failed)"
```
Expected: `total` and `executed` both > 0, `failed=0`. This proves the CI guard will pass on green and fail on a silent-skip.

- [ ] **Step 4: Commit** (do NOT push — CI runs when David pushes later)

```bash
git add .github/workflows/windows.yml
git commit -m "ci(windows): add Windows build + dotnet test workflow (asserts tests ran; no GUI; no publish/push)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: End-to-end verification harness (`windows/tools/verify-transcription/`)

> A C# console port of `scripts/verify-transcription.py`. Generates spoken WAVs with Windows TTS (`System.Speech.Synthesis`, written directly at 16 kHz mono 16-bit — the recorder/engine format), runs each through the App's `--bench` CLI (whole-file and `--stream`), parses the `raw:`/`streamed:`/`wholefile:` lines, scores LCS retention + spurious-vocab + vocab-accuracy with the **exact same thresholds** as the Python, prints a PASS/FAIL table, and exits 1 on any failure.

**Files:**
- Create: `windows/tools/verify-transcription/verify-transcription.csproj`
- Create: `windows/tools/verify-transcription/Program.cs`
- Modify: `windows/JVoice.sln` (add the project)

**Interfaces:**
- Produces: a console app `verify-transcription [--model tiny|base|small|large] [--quick] [--bin <path-to-JVoice.exe>]` that prints a per-scenario PASS/FAIL table and exits non-zero on any FAIL.
- Consumes: the App's `--bench` CLI (Phase 2 `BenchRunner`) — it shells out to `JVoice.exe --bench <wav> --model … --vocab … [--stream]`, exactly as the Python shells out to `.build/release/JVoice --bench`.

**The Python → C# fidelity contract (each MUST match):**

| `verify-transcription.py` | C# port |
| --- | --- |
| `VOCAB = ["sub agents","claude","li-fraumeni","vs code"]` | same array, same order |
| 5 no-vocab passages (`tariffs/weather/cooking/travel/history`) | same 5 strings verbatim |
| 1 vocab passage (`dev`) with `expect=["vs code","claude","li-fraumeni","sub agents"]` | same string + same expect list |
| `build_clip_text`: pause `[[slnc N]]` every 12 words | **adapted** — macOS `say` markup `[[slnc N]]` does NOT work in System.Speech; insert a SSML `<break time="Nms"/>` every 12 words instead (same intent: low-confidence gaps) |
| `gen_clip` via `say` + `afconvert` → 16 kHz mono WAV | `SpeechSynthesizer.SetOutputToWaveFile` with a 16 kHz mono 16-bit `SpeechAudioFormatInfo` (direct, no resample); if a voice emits another format, resample via NAudio |
| `normalize` = lowercase, strip non-`[a-z0-9 ]`, split | identical regex + split |
| `lcs_len` DP | identical DP |
| `retention = lcs/len(gt)` | identical |
| `spurious_vocab` = vocab phrases in hyp beyond gt | identical (space-padded substring counting) |
| `run_bench`: parse `raw:` (whole) / `streamed:` + `wholefile:` (stream), `"session fell back"` handling | identical parsing of the `--bench` stdout (Phase 2's exact format) |
| no-vocab pass gate: `ret>=0.85 and spur==0` | identical |
| vocab pass gate: `ret>=0.80 and len(miss)==0` | identical |
| pause patterns: quick `{short:500,med:2200}` else `+long:6500` | identical |
| voices: macOS `["Samantha","Daniel"]` | **adapted** — Windows installed voices (e.g. "Microsoft David"/"Microsoft Zira"); pick up to 2 installed voices, quick uses 1 |
| `long3` = 3 passages concatenated, ~2 min | identical (concatenate with 2500 ms breaks) |
| print table, `n_pass/total`, exit 1 on fail | identical |

- [ ] **Step 1: Create `windows/tools/verify-transcription/verify-transcription.csproj`**

> `net9.0-windows` because `System.Speech` is a Windows-only assembly. Uses the same pinned **NAudio** version as the rest of the solution (Phase 3) for the optional resample path; resolve it with `dotnet add package NAudio` and pin.

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
    <UseWindowsForms>false</UseWindowsForms>
    <RootNamespace>JVoice.Tools.VerifyTranscription</RootNamespace>
    <AssemblyName>verify-transcription</AssemblyName>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
  </PropertyGroup>

  <ItemGroup>
    <!-- System.Speech is shipped as a NuGet package for net5.0+ (it left the BCL). -->
    <PackageReference Include="System.Speech" Version="PINNED_AT_EXECUTION" />
    <!-- Used only if a voice refuses to emit 16 kHz mono and we must resample. -->
    <PackageReference Include="NAudio" Version="PINNED_AT_EXECUTION" />
  </ItemGroup>

</Project>
```

> Run `dotnet add windows/tools/verify-transcription package System.Speech` and `dotnet add … package NAudio` to write + pin the current stable versions, then replace the `PINNED_AT_EXECUTION` placeholders. Both are MIT/MS-permissive (GPL-compatible). Record the versions in HANDOFF-WINDOWS.md.

- [ ] **Step 2: Create `windows/tools/verify-transcription/Program.cs`** (complete port)

```csharp
using System.Diagnostics;
using System.Globalization;
using System.Speech.AudioFormat;
using System.Speech.Synthesis;
using System.Text;
using System.Text.RegularExpressions;

namespace JVoice.Tools.VerifyTranscription;

/// End-to-end transcription verification harness — C# port of
/// scripts/verify-transcription.py. Generates real spoken WAVs (Windows TTS at
/// 16 kHz mono 16-bit — the recorder/engine format), runs each through the App's
/// `--bench` CLI (whole-file AND --stream), and scores:
///   * retention — fraction of ground-truth words present in order (LCS). A big
///                 dropped span tanks this.
///   * spurious  — custom-vocab phrases that appear though never spoken. Must be 0.
///   * accuracy  — for vocab clips, that each expected phrase is recovered.
///
/// Usage: verify-transcription [--model tiny|base|small|large] [--quick]
///                             [--bin <path-to-JVoice.exe>]
/// Exit 0 if every path-run passes; 1 if any fails.
internal static class Program
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };
    private static readonly string VocabArg = string.Join(", ", Vocab);

    // Ground-truth passages with NO vocabulary words — any vocab word in the
    // output is a hallucination. Verbatim from verify-transcription.py.
    private static readonly Dictionary<string, string> Passages = new()
    {
        ["tariffs"] = "So basically what tariffs are is when governments put taxes on products that come from other countries and ultimately who actually pays them is the people who are buying the item so if someone wanted to buy a product from a country that has a really high tariff then the price would go up quite a lot",
        ["weather"] = "The weather this week has been completely unpredictable with sunshine in the morning and heavy rain by the afternoon which makes it really hard to plan anything outdoors so most people have just decided to stay inside and wait for the weekend when things are supposed to finally calm down a little",
        ["cooking"] = "When you are making a really good pasta sauce the most important thing is to start with good tomatoes and to cook the garlic slowly so that it never burns because burnt garlic will make the whole sauce taste bitter and then you simply let it simmer for a long time until the flavours come together",
        ["travel"] = "Last summer we drove all the way across the country stopping in small towns that we had never heard of before and meeting people who were incredibly kind and generous with their time and by the end of the trip we had collected so many stories that we could barely remember which town each one happened in",
        ["history"] = "The industrial revolution changed almost everything about how people lived and worked because suddenly machines could do the work of dozens of people and that meant cities grew very quickly as workers moved in from the countryside looking for jobs in the new factories that were opening up everywhere",
    };

    // Passages that DO speak the vocabulary (accuracy check). Verbatim.
    private static readonly Dictionary<string, (string Text, string[] Expect)> VocabPassages = new()
    {
        ["dev"] = ("I use vs code and claude every single day my favourite tool is the one we built and in the lab we studied li fraumeni syndrome and then I created a whole system of sub agents",
                   new[] { "vs code", "claude", "li-fraumeni", "sub agents" }),
    };

    private static string _model = "base";
    private static bool _quick;
    private static string _bin = "";
    private static string _clipsDir = "";

    private static async Task<int> Main(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--model" when i + 1 < args.Length: _model = args[++i]; break;
                case "--quick": _quick = true; break;
                case "--bin" when i + 1 < args.Length: _bin = args[++i]; break;
            }
        }

        _bin = ResolveBin(_bin);
        if (!File.Exists(_bin))
        {
            Console.Error.WriteLine(
                $"JVoice binary not found: {_bin}\n" +
                "Build it first (dotnet build windows/JVoice.App -c Release) or pass --bin <path-to-JVoice.exe>.");
            return 2;
        }

        _clipsDir = Path.Combine(Path.GetTempPath(), "jv-verify-clips");
        Directory.CreateDirectory(_clipsDir);

        var voices = PickVoices(_quick ? 1 : 2);
        if (voices.Count == 0)
        {
            Console.Error.WriteLine("No installed TTS voices found (System.Speech). Cannot generate clips.");
            return 2;
        }

        var pausePatterns = _quick
            ? new (string Label, int Ms)[] { ("short", 500), ("med", 2200) }
            : new (string Label, int Ms)[] { ("short", 500), ("med", 2200), ("long", 6500) };

        // (name, text, voice, groundTruth, expectVocab-or-null)
        var scenarios = new List<(string Name, string Text, string Voice, string Gt, string[]? Expect)>();

        // No-vocab passages × pauses × voices.
        foreach (var (pname, passage) in Passages)
            foreach (var (plabel, pms) in pausePatterns)
                foreach (var voice in voices)
                    scenarios.Add(($"{pname}-{plabel}-{voice.Tag}", BuildClipText(passage, pms), voice.Name, passage, null));

        // Long (~2 min) clips: concatenate all passages with medium breaks.
        string longText = string.Join(Break(2500), Passages.Values);
        foreach (var voice in voices)
            scenarios.Add(($"long3-{voice.Tag}", BuildClipText(longText, 2500), voice.Name, longText, null));

        // Vocab-spoken accuracy clips.
        foreach (var voice in voices)
            foreach (var (vname, (vtext, expect)) in VocabPassages)
                scenarios.Add(($"vocab-{vname}-{voice.Tag}", BuildClipText(vtext, 1500), voice.Name, vtext, expect));

        Console.WriteLine($"model={_model}  bin={_bin}");
        Console.WriteLine($"scenarios={scenarios.Count}  (×2 paths = {scenarios.Count * 2} transcriptions)\n");

        int nPass = 0;
        var fails = new List<(string Name, string Tag, double Ret, int Spur, string VMiss, string Hyp)>();

        foreach (var (name, text, voice, gt, expect) in scenarios)
        {
            string wav = GenClip(name, text, voice);
            var row = new string[2];
            for (int s = 0; s < 2; s++)
            {
                bool stream = s == 1;
                var (hyp, fellBack) = await RunBench(wav, stream);
                double ret = Retention(gt, hyp);
                int spur = SpuriousVocab(hyp, gt);
                string tag = stream ? "stream" : "whole ";
                string fb = fellBack ? "*" : " ";
                bool ok;
                string vmiss = "";
                if (expect is null)
                {
                    ok = ret >= 0.85 && spur == 0;
                }
                else
                {
                    var miss = expect
                        .Where(v => !(" " + string.Join(" ", Normalize(hyp)) + " ")
                            .Contains(" " + string.Join(" ", Normalize(v)) + " "))
                        .ToArray();
                    ok = ret >= 0.80 && miss.Length == 0;
                    vmiss = miss.Length > 0 ? $" miss=[{string.Join(", ", miss)}]" : "";
                }
                string status = ok ? "PASS" : "FAIL";
                if (ok) nPass++;
                else fails.Add((name, tag.Trim(), ret, spur, vmiss, hyp));
                row[s] = $"{tag}{fb} ret={ret.ToString("0.00", CultureInfo.InvariantCulture)} spur={spur}{vmiss} {status}";
            }
            Console.WriteLine($"  {name,-28} | {row[0],-42} | {row[1]}");
        }

        int total = scenarios.Count * 2;
        Console.WriteLine($"\n{nPass}/{total} path-runs passed.");
        if (fails.Count > 0)
        {
            Console.WriteLine("\nFAILURES:");
            foreach (var (name, tag, ret, spur, vmiss, hyp) in fails)
            {
                Console.WriteLine($"  x {name} [{tag}] ret={ret.ToString("0.00", CultureInfo.InvariantCulture)} spur={spur}{vmiss}");
                Console.WriteLine($"      hyp: {(hyp.Length > 200 ? hyp[..200] : hyp)}");
            }
            return 1;
        }
        Console.WriteLine("ALL PASS");
        return 0;
    }

    /// Resolve the JVoice.exe to bench against: explicit --bin, else the most
    /// recently built Release/Debug JVoice.exe under windows/JVoice.App/bin.
    private static string ResolveBin(string explicitBin)
    {
        if (!string.IsNullOrEmpty(explicitBin)) return explicitBin;
        // Walk up to the repo root (this exe lives in windows/tools/verify-transcription/bin/...).
        string? dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8 && dir is not null; i++)
        {
            string appBin = Path.Combine(dir, "windows", "JVoice.App", "bin");
            if (Directory.Exists(appBin))
            {
                var exe = Directory.EnumerateFiles(appBin, "JVoice.exe", SearchOption.AllDirectories)
                    .OrderByDescending(File.GetLastWriteTimeUtc)
                    .FirstOrDefault();
                if (exe is not null) return exe;
            }
            dir = Directory.GetParent(dir)?.FullName;
        }
        // Fallback: assume it's on PATH or in the working dir.
        return "JVoice.exe";
    }

    private readonly record struct VoiceChoice(string Name, string Tag);

    /// Pick up to `count` installed TTS voices, preferring distinct ones.
    private static List<VoiceChoice> PickVoices(int count)
    {
        using var synth = new SpeechSynthesizer();
        var installed = synth.GetInstalledVoices()
            .Where(v => v.Enabled)
            .Select(v => v.VoiceInfo.Name)
            .ToList();
        var chosen = new List<VoiceChoice>();
        foreach (var name in installed)
        {
            if (chosen.Count >= count) break;
            // Short tag for the table (last word of the voice name, alnum only).
            string tag = Regex.Replace(name.Split(' ').Last(), "[^A-Za-z0-9]", "");
            if (tag.Length == 0) tag = $"v{chosen.Count}";
            chosen.Add(new VoiceChoice(name, tag));
        }
        return chosen;
    }

    /// SSML break (the System.Speech analog of macOS `say`'s [[slnc Nms]]).
    private static string Break(int ms) => $"<break time=\"{ms}ms\"/>";

    /// Insert a pause after roughly every ~12 words to create low-confidence gaps.
    /// Port of build_clip_text. NOTE: this produces SSML fragments; GenClip wraps
    /// the whole thing in a <speak> document so the breaks are honored.
    private static string BuildClipText(string passage, int pauseMs)
    {
        var words = passage.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var sb = new StringBuilder();
        for (int i = 0; i < words.Length; i++)
        {
            sb.Append(words[i]);
            sb.Append(' ');
            if ((i + 1) % 12 == 0) sb.Append(Break(pauseMs)).Append(' ');
        }
        return sb.ToString().Trim();
    }

    /// Synthesize `text` (SSML body) into a 16 kHz mono 16-bit WAV. Cached by name.
    private static string GenClip(string name, string text, string voice)
    {
        string wav = Path.Combine(_clipsDir, $"{name}.wav");
        if (File.Exists(wav)) return wav;

        using var synth = new SpeechSynthesizer();
        try { synth.SelectVoice(voice); } catch { /* fall back to default voice */ }

        // 16 kHz mono 16-bit — exactly the recorder/engine format (no resample needed).
        var fmt = new SpeechAudioFormatInfo(16000, AudioBitsPerSample.Sixteen, AudioChannel.Mono);
        synth.SetOutputToWaveFile(wav, fmt);

        // Wrap the SSML fragment in a complete <speak> document so <break/> works.
        string ssml =
            "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"en-US\">" +
            text + "</speak>";
        try { synth.SpeakSsml(ssml); }
        catch
        {
            // If a voice rejects SSML, strip the breaks and speak plain text.
            synth.SetOutputToWaveFile(wav, fmt);
            synth.Speak(Regex.Replace(text, "<break[^>]*/>", " "));
        }
        synth.SetOutputToNull();
        return wav;
    }

    private static string[] Normalize(string text)
        => Regex.Replace(text.ToLowerInvariant(), "[^a-z0-9 ]+", " ")
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);

    private static int LcsLen(string[] a, string[] b)
    {
        if (a.Length == 0 || b.Length == 0) return 0;
        var prev = new int[b.Length + 1];
        foreach (var x in a)
        {
            var cur = new int[b.Length + 1];
            for (int j = 0; j < b.Length; j++)
                cur[j + 1] = x == b[j] ? prev[j] + 1 : Math.Max(prev[j + 1], cur[j]);
            prev = cur;
        }
        return prev[^1];
    }

    private static double Retention(string gt, string hyp)
    {
        var g = Normalize(gt);
        var h = Normalize(hyp);
        return (double)LcsLen(g, h) / Math.Max(1, g.Length);
    }

    /// Vocab phrases in hyp beyond those in the ground truth. Port of spurious_vocab.
    private static int SpuriousVocab(string hyp, string gt)
    {
        string hn = " " + string.Join(" ", Normalize(hyp)) + " ";
        string gn = " " + string.Join(" ", Normalize(gt)) + " ";
        int total = 0;
        foreach (var v in Vocab)
        {
            string vn = " " + string.Join(" ", Normalize(v)) + " ";
            total += Math.Max(0, CountOccurrences(hn, vn) - CountOccurrences(gn, vn));
        }
        return total;
    }

    private static int CountOccurrences(string haystack, string needle)
    {
        if (needle.Length == 0) return 0;
        int count = 0, idx = 0;
        // Overlapping count to match Python str.count semantics (non-overlapping);
        // Python str.count is non-overlapping, so advance by needle.Length - matches
        // the padded-phrase usage where overlaps don't occur. Use non-overlapping.
        while ((idx = haystack.IndexOf(needle, idx, StringComparison.Ordinal)) >= 0)
        {
            count++;
            idx += needle.Length;
        }
        return count;
    }

    /// Run the App's --bench CLI and parse the transcript. Mirrors run_bench:
    /// whole-file → parse `raw: "..."`; stream → `streamed:` (or "session fell
    /// back") with `wholefile:` fallback. Returns (text, fellBack).
    private static async Task<(string Text, bool FellBack)> RunBench(string wav, bool stream)
    {
        var psi = new ProcessStartInfo
        {
            FileName = _bin,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        psi.ArgumentList.Add("--bench");
        psi.ArgumentList.Add(wav);
        psi.ArgumentList.Add("--model"); psi.ArgumentList.Add(_model);
        psi.ArgumentList.Add("--vocab"); psi.ArgumentList.Add(VocabArg);
        if (stream) psi.ArgumentList.Add("--stream");

        using var proc = Process.Start(psi)!;
        string stdout = await proc.StandardOutput.ReadToEndAsync();
        _ = await proc.StandardError.ReadToEndAsync();
        await proc.WaitForExitAsync();

        var lines = stdout.Split('\n');
        if (!stream)
        {
            foreach (var line in lines)
                if (line.StartsWith("raw:", StringComparison.Ordinal))
                    return (ExtractQuoted(line), false);
            return ("", false);
        }

        string? streamed = null;
        string wholefile = "";
        bool fellBack = false;
        foreach (var line in lines)
        {
            if (line.StartsWith("streamed:", StringComparison.Ordinal))
            {
                if (line.Contains("session fell back", StringComparison.Ordinal)) fellBack = true;
                else streamed = ExtractQuoted(line);
            }
            else if (line.StartsWith("wholefile:", StringComparison.Ordinal))
            {
                string q = ExtractQuoted(line);
                if (q.Length > 0) wholefile = q;
            }
        }
        // App behavior: streamed transcript if present, else whole-file fallback.
        return (streamed ?? wholefile, fellBack);
    }

    /// Extract the first double-quoted substring from a bench output line.
    private static string ExtractQuoted(string line)
    {
        var m = Regex.Match(line, "\"(.*)\"");
        return m.Success ? m.Groups[1].Value : "";
    }
}
```

> **Fidelity notes (logged assumptions):**
> - **`[[slnc Nms]]` → SSML `<break time="Nms"/>`.** macOS `say` uses the speech-markup `[[slnc N]]`; System.Speech ignores it. The functional intent (a pause every ~12 words to create low-confidence gaps) is preserved with SSML breaks, wrapped in a `<speak>` document. If a voice rejects SSML, `GenClip` strips the breaks and speaks plain text — the clip still tests retention, just without the engineered pauses.
> - **Voices.** macOS used `["Samantha","Daniel"]`. On Windows we use up to 2 *installed* voices (typically "Microsoft David"/"Microsoft Zira"); `--quick` uses 1. The voice set doesn't affect the scoring thresholds.
> - **`Process.ArgumentList`** is used (not a joined string) so the `--vocab "sub agents, claude, …"` argument with spaces/commas is passed as one argv element without quoting bugs.
> - **Scoring is identical** to the Python: thresholds `0.85`/`spur==0` (no-vocab) and `0.80`/`all-present` (vocab), LCS DP, normalize regex, space-padded spurious counting.

- [ ] **Step 3: Add to the solution + build**

```bash
cd windows
dotnet sln add tools/verify-transcription/verify-transcription.csproj
dotnet build tools/verify-transcription/verify-transcription.csproj -c Release
```
Expected: `Build succeeded`. (Replace `PINNED_AT_EXECUTION` in the csproj with the versions `dotnet add package` resolved, then rebuild if needed.)

- [ ] **Step 4: Build the App (the bench oracle) and run the harness in `--quick` mode with tiny**

```bash
dotnet build windows/JVoice.App/JVoice.App.csproj -c Release
dotnet run --project windows/tools/verify-transcription -c Release -- --model tiny --quick
echo "exit=$?"
```
Expected: a per-scenario table like:
```
model=tiny  bin=…\windows\JVoice.App\bin\Release\net9.0-windows\win-x64\JVoice.exe
scenarios=12  (×2 paths = 24 transcriptions)

  tariffs-short-David          | whole  ret=0.93 spur=0 PASS          | stream  ret=0.91 spur=0 PASS
  tariffs-med-David            | whole  ret=0.90 spur=0 PASS          | stream* ret=0.89 spur=0 PASS
  …
  vocab-dev-David              | whole  ret=0.88 spur=0 PASS          | stream  ret=0.85 spur=0 PASS

24/24 path-runs passed.
ALL PASS
```
and `exit=0`.

> **Important — tiny is the smallest model, so a couple of FAILs on tiny are acceptable for *this smoke run* only.** The harness's *contract* is the scoring logic, not that tiny passes everything. For a real verification gate use `--model base` or `--model small` (closer to the macOS Python runs, which used `base` by default). If `--model tiny --quick` shows a few FAILs purely from tiny's lower accuracy (not a crash, not a parsing bug, not spurious-vocab>0 from hallucination), that is the model's limitation. Re-run with `--model small` to confirm the harness reaches `ALL PASS` on a capable model — **that** is the gate. Record both runs in HANDOFF-WINDOWS.md.

- [ ] **Step 5: Run the real gate with a capable model** (the equivalent of the Python's `base`/`small` runs)

```bash
dotnet run --project windows/tools/verify-transcription -c Release -- --model small
echo "exit=$?"
```
Expected: `ALL PASS` and `exit=0` (allowing that the long/streaming clips on a slower model take a while — this downloads `ggml-small.bin` once). If a real FAIL appears (retention < 0.85 with a clearly dropped span, or spurious-vocab > 0), that is a genuine engine/brain regression — investigate via `systematic-debugging`; do NOT loosen the thresholds.

- [ ] **Step 6: Commit**

```bash
git add windows/tools/verify-transcription windows/JVoice.sln docs/HANDOFF-WINDOWS.md
git commit -m "tools(windows): verify-transcription harness (C# port of verify-transcription.py) — TTS clips, --bench scoring, PASS/FAIL table

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Docs — `README-WINDOWS.md`, `CLAUDE.md` §Windows, `windows/README.md`, `docs/HANDOFF-WINDOWS.md`

> Four documentation artifacts. (a) `README-WINDOWS.md` mirrors the macOS `README.md` tone for Windows users. (b) The `## Windows port` section is appended to `CLAUDE.md` (exact text shown; appending is a step). (c) `windows/README.md` is a dev quickstart. (d) `docs/HANDOFF-WINDOWS.md` gets a session-handoff template.

**Files:**
- Create: `README-WINDOWS.md` (repo root)
- Modify: `CLAUDE.md` (append a section)
- Create: `windows/README.md`
- Create/Modify: `docs/HANDOFF-WINDOWS.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `README-WINDOWS.md`** (repo root) — mirrors `README.md`, retargeted for Windows

````markdown
<div align="center">

# JVoice for Windows

**Free, open-source voice dictation for Windows. 100% on-device. No subscription, no cloud, no accounts.**

Press <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> anywhere, talk, and clean, tone-styled text lands at your cursor — in any app.

[Download](#install) · [First run on Windows](#first-run-on-windows) · [Build from source](#build-from-source)

</div>

---

> **Note:** This is the Windows port of [JVoice](README.md) (originally a macOS menu-bar app).
> The macOS app remains the reference implementation. The Windows app lives under `windows/`
> and is a native **.NET 9 / WPF** desktop app using **Whisper.net** (whisper.cpp) for
> on-device transcription, with **CUDA GPU acceleration** on NVIDIA cards and a CPU fallback.

## Why JVoice

Dictation tools like Wispr Flow and superwhisper cost $8–15/month for something your PC can do by itself. JVoice runs [Whisper](https://github.com/ggerganov/whisper.cpp) locally — your voice never leaves your machine, and it costs nothing, forever.

- 🎙️ **System-wide dictation** — global hotkey (<kbd>Ctrl+Shift+Space</kbd>), works in any app: chat, email, docs, your IDE
- 🧠 **On-device Whisper** — choose tiny → large models depending on your PC; nothing is sent anywhere. **GPU-accelerated** on NVIDIA (CUDA), CPU everywhere else
- ✍️ **Tone styles** — Casual, Formal, or Very Casual: JVoice rewrites your rambling into the register you want
- 🧹 **Filler-word removal** — "um", "uh", "like" are gone before the text lands
- 📖 **Custom dictionary** — teach it your name, your school, your project names. Words bias Whisper itself at recognition time, and a phonetic matcher catches the mishearings that slip through ("jay voice" → "JVoice")
- 🎧 **Headphone-friendly** — keeps Bluetooth audio quality intact (A2DP) by routing recording to a non-Bluetooth mic
- 📊 **Stats** — total words dictated and average WPM
- 🌍 **English & Romanian**

## Privacy

- **Zero network calls** during use. The only download ever is the Whisper model itself (fetched once from Hugging Face on first run).
- No telemetry, no analytics, no accounts.
- Open source — read the code, build it yourself.

## Requirements

- **Windows 10 or 11, 64-bit (x64).**
- The **self-contained** download needs **nothing pre-installed** (the .NET 9 runtime is bundled). If you build from source, you need the **.NET 9 SDK**.
- For GPU acceleration: an **NVIDIA GPU** (the "with GPU" download). The CPU "lite" build runs on any PC.

## Install

1. Download from the [latest release](#) (no release published yet — build from source for now):
   - **`JVoice.exe`** — CPU "lite" single file, runs on any Windows PC. *Recommended.*
   - **`JVoice-gpu-win-x64.zip`** — unzip and run `JVoice.exe` for NVIDIA GPU acceleration. **Keep the `runtimes\` folder next to the exe.**
   - **`JVoice-Setup.exe`** — optional installer (Start-Menu shortcut + uninstaller, per-user, no admin).
2. See [First run on Windows](#first-run-on-windows) — one extra click because this is a free, unsigned app.

### First run on Windows

JVoice is free and isn't code-signed (an Authenticode certificate costs $200+/yr). Windows SmartScreen will warn you **once**:

1. Double-click `JVoice.exe`. SmartScreen says *"Windows protected your PC."*
2. Click **More info**.
3. Click **Run anyway**. JVoice launches to your system tray. You only do this once.

> If **Run anyway** is missing, right-click the file → **Properties** → check **Unblock** → **OK**, then launch.
> Full details: [`docs/launch/windows-distribution.md`](docs/launch/windows-distribution.md).

On first run JVoice asks Windows for **microphone** access (Settings → Privacy & security → Microphone → *Let desktop apps access your microphone*) and downloads your chosen Whisper model. No accessibility permission is needed to type text into other apps — except that, like any non-admin app, JVoice can't paste into an *elevated* (admin) window.

## Usage

1. Press <kbd>Ctrl+Shift+Space</kbd> — a recording pill appears.
2. Talk. Press <kbd>Ctrl+Shift+Space</kbd> again to stop.
3. Transcribed, tone-styled text is pasted at your cursor.

Settings (tray icon → Settings…): language, tone style, Whisper model, filler-word removal, custom words, and your dictation stats. The last transcript is always editable from Settings. The hotkey is rebindable.

## Build from source

Don't trust an unsigned binary? Good instinct — build it yourself:

```powershell
git clone <repo-url> ; cd JVoice-Windows

# Build + run the unit tests (the accuracy "brain")
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj

# Run the app from source
dotnet run --project windows/JVoice.App -c Release

# Or publish a self-contained CPU single-file exe:
dotnet publish windows/JVoice.App -c Release -r win-x64 `
  -p:JVoiceFlavor=cpu -p:PublishSingleFile=true -p:SelfContained=true `
  -p:PublishTrimmed=false -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:PublishReadyToRun=true -o windows/artifacts/cpu
```

Requires Windows 10/11 x64 and the **.NET 9 SDK**. See [`windows/README.md`](windows/README.md) for the full developer guide and the GPU build.

## License

GPL-3.0 — free to use, build, and modify; derivatives must stay open.
````

- [ ] **Step 2: Append the `## Windows port` section to `CLAUDE.md`**

Append **exactly** the following block to the end of `CLAUDE.md` (after the "Current status & next steps" section). Do not edit the existing content.

```markdown

## Windows port

A native Windows port of JVoice lives under `windows/` (added 2026-06). The macOS Swift app
(`Sources/`, `Tests/`, `Package.swift`, `Resources/`) is **kept untouched as the reference
implementation** — same rule as `../MacOSUtils`: read-only. See
`docs/superpowers/plans/2026-06-22-windows-port-00-overview.md` for the full plan and every
canonical name.

### Stack
- **.NET 9 + WPF** (`net9.0-windows`, WinExe, win-x64). Tray-first app (the macOS menu-bar
  model) + floating HUD pill + a 320×520 dark Settings window.
- **Whisper.net** (managed whisper.cpp bindings) running **GGML** models, with **CUDA** GPU
  acceleration (CPU fallback). This replaces Apple-only WhisperKit/CoreML.
- **NAudio** (capture/WAV), **H.NotifyIcon.Wpf** (tray), **SkiaSharp** (HUD drawing).
- Solution: `windows/JVoice.sln` with `JVoice.Core` (pure brain, net9.0), `JVoice.App` (WPF
  app + Whisper engine + platform), `JVoice.Tests` (xUnit), and `windows/tools/*`.

### Build / test / publish
- Build all: `dotnet build windows/JVoice.sln -c Release`
- Test (the brain): `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj`
- Run from source: `dotnet run --project windows/JVoice.App -c Release`
- Hidden bench CLI: `JVoice.exe --bench <wav> [--model tiny|base|small|large] [--vocab "A,B"] [--stream] [--lang en|ro] [--no-prompt]`
- E2E accuracy harness: `dotnet run --project windows/tools/verify-transcription -- --model small`
- Publish CPU single-file: `dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=cpu -p:PublishSingleFile=true -p:SelfContained=true -p:PublishTrimmed=false -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishReadyToRun=true -o windows/artifacts/cpu`
- Publish GPU folder + zip: `dotnet publish … -p:JVoiceFlavor=gpu -p:PublishSingleFile=false …` then `Compress-Archive`.
- Optional installer: `ISCC.exe windows/installer/JVoice.iss` (free Inno Setup; `winget install JRSoftware.InnoSetup`).
- CI: `.github/workflows/windows.yml` (build + `dotnet test` on `windows-latest`; asserts tests ran; never launches the GUI). The macOS `test.yml` is separate and untouched.

### Hard rules (in addition to the repo-wide ones above)
- **The brain is ported faithfully.** TextProcessor, PhoneticMatcher, VocabularyPrompt,
  RepetitionGuard, RegurgitationRecovery, ChunkPlanner, WavTail, StreamingTranscriptionSession
  reproduce the Swift behavior line-for-line, every constant verbatim, and the translated
  xUnit tests must pass. No algorithm "improvements" during the port.
- **Do NOT modify the Swift macOS app.** It's the source of truth for the brain's invariants.
- **$0 budget, unsigned, no paid signing.** Distribute an unsigned single-file `.exe` (+ optional
  installer); document the SmartScreen "More info → Run anyway" flow
  (`docs/launch/windows-distribution.md`). No paid services.
- **NO publishing/pushing.** Same as the repo-wide rule — commit locally on `windows-port` only.
- **Privacy:** zero runtime network calls except the one-time GGML model download from Hugging Face.
- **Hotkey default is Ctrl+Shift+Space** (Alt+Space opens the Windows window menu, so ⌥Space
  has no Windows equivalent). Rebindable.
```

- [ ] **Step 3: Create `windows/README.md`** (dev quickstart)

````markdown
# JVoice for Windows — Developer Guide

Native Windows port of JVoice: a tray app that turns speech into tone-styled text on-device.
See `../docs/superpowers/plans/2026-06-22-windows-port-00-overview.md` for the architecture
and every canonical name. The macOS Swift app (`../Sources`) is the read-only reference.

## Prerequisites
- **Windows 10/11 x64** and the **.NET 9 SDK** (`dotnet --version` → 9.x).
- For GPU work: an NVIDIA GPU + recent driver (the CUDA native runtime is bundled via NuGet).
- (Optional) **Inno Setup 6** for the installer: `winget install JRSoftware.InnoSetup`.

## Solution layout
| Project | Target | Purpose |
| --- | --- | --- |
| `JVoice.Core` | `net9.0` | Pure accuracy brain — no UI, no Win32, no native deps. Fully unit-tested. |
| `JVoice.App` | `net9.0-windows` (WinExe) | WPF UI + Whisper.net engine + Win32 platform + `VoiceCoordinator` + `--bench`. |
| `JVoice.Tests` | `net9.0` (xUnit) | Brain tests, translated from `../Tests/JVoiceTests/`. |
| `tools/generate-icon` | console | Draws `JVoice.App/Assets/JVoice.ico`. |
| `tools/whisper-smoke` | console | WPF-free single-WAV transcription smoke test. |
| `tools/verify-transcription` | `net9.0-windows` console | E2E accuracy harness (TTS clips → `--bench` → scored table). |

## Common commands
```bash
# Build everything
dotnet build windows/JVoice.sln -c Release

# Unit tests (the brain)
dotnet test windows/JVoice.Tests/JVoice.Tests.csproj

# Run the app
dotnet run --project windows/JVoice.App -c Release

# Transcribe one WAV, no UI (downloads the model on first use)
dotnet run --project windows/JVoice.App -- --bench path\to\clip.wav --model tiny --vocab "VS Code,JVoice"

# End-to-end accuracy harness (generates TTS clips, scores retention/spurious/vocab)
dotnet run --project windows/tools/verify-transcription -- --model small        # full gate
dotnet run --project windows/tools/verify-transcription -- --model tiny --quick  # fast smoke
```

## Publishing
```powershell
# CPU "lite" single-file (recommended public download)
dotnet publish windows/JVoice.App -c Release -r win-x64 `
  -p:JVoiceFlavor=cpu -p:PublishSingleFile=true -p:SelfContained=true `
  -p:PublishTrimmed=false -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:PublishReadyToRun=true -o windows/artifacts/cpu

# GPU folder build (NVIDIA), then zip
dotnet publish windows/JVoice.App -c Release -r win-x64 `
  -p:JVoiceFlavor=gpu -p:PublishSingleFile=false -p:SelfContained=true `
  -p:PublishTrimmed=false -p:PublishReadyToRun=true -o windows/artifacts/gpu
Compress-Archive -Path windows/artifacts/gpu/* -DestinationPath windows/artifacts/JVoice-gpu-win-x64.zip -Force

# Optional installer (per-user, no admin, unsigned)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\JVoice.iss
```

## Notes
- **WPF can't be trimmed** — always `-p:PublishTrimmed=false`.
- **CUDA is huge** — it ships only in the GPU folder build, never the single-file (would self-extract hundreds of MB per launch).
- **Models** download to `%LOCALAPPDATA%\JVoice\models\`; settings/stats to `%APPDATA%\JVoice\`; temp recordings to `%TEMP%\jvoice-*.wav` (swept on launch).
- **Unsigned** — users clear SmartScreen via "More info → Run anyway" (`../docs/launch/windows-distribution.md`).
- **Never push/publish** without David's go-ahead. Commit on `windows-port`.
````

- [ ] **Step 4: Create/refresh `docs/HANDOFF-WINDOWS.md`** (session-handoff template)

> Phase 2 may already have created this file (it records pinned versions + E2E results). If it exists, **append** the template below under a new heading; do not clobber the recorded versions. If it doesn't exist, create it with the full content.

````markdown
# JVoice Windows Port — Session Handoff

Session-by-session state for the Windows port. The anchor plan is
`docs/superpowers/plans/2026-06-22-windows-port-00-overview.md`; the per-phase plans are
`…-01-core-brain.md` … `…-05-packaging.md`. Branch: `windows-port`. **No pushing/publishing.**

## Status snapshot (update every session)
- **Phase reached:** _e.g. Phase 5, Task 3 done_
- **Last green:** _e.g. `dotnet test` 187/187, `dotnet build windows/JVoice.sln -c Release` succeeded_
- **Last commit:** _hash + subject_

## Pinned dependency versions (record once resolved)
| Package | Version | Notes |
| --- | --- | --- |
| Whisper.net | _x.y.z_ | |
| Whisper.net.Runtime (CPU) | _x.y.z_ | |
| Whisper.net.Runtime.Cuda | _x.y.z_ | |
| Whisper.net.Runtime.Vulkan | _x.y.z / dropped_ | |
| NAudio | _x.y.z_ | |
| H.NotifyIcon.Wpf | _x.y.z_ | |
| SkiaSharp | _x.y.z_ | |
| System.Speech | _x.y.z_ | harness only |
| xunit / Microsoft.NET.Test.Sdk | _x.y.z_ | |

## GGML model sizes / checksums (record on first download)
| Model | File | ExpectedBytes | SHA-256 |
| --- | --- | --- | --- |
| Tiny | ggml-tiny.bin | _N_ | _hex_ |
| Base | ggml-base.bin | _N_ | _null/hex_ |
| Small | ggml-small.bin | _N_ | _null/hex_ |
| Large | ggml-large-v3-turbo-q5_0.bin | _N_ | _null/hex_ |

## Whisper.net API names confirmed (Phase 2 probe)
_e.g. WithPrompt / WithoutTimestamps / WithTemperature / WithTemperatureInc / ProcessAsync(float[]) …_

## E2E / verification results
- Selected runtime (`WhisperRuntime.Describe()`): _e.g. whisper.cpp (Cuda)_
- `verify-transcription --model small`: _ALL PASS / failures_
- Long-clip non-truncation: _PASS_
- Streaming corroboration: _PASS_

## Packaging (Phase 5)
- CPU single-file size: _MB_  | GPU zip size: _MB_
- CUDA leaked into single-file? _no/yes + fix_
- Installer built (`JVoice-Setup-1.0.0.exe`): _yes/no_

## Assumptions made (log every ambiguity resolved autonomously)
- _e.g. ctor param order; SSML breaks vs [[slnc]]; voice selection on Windows_

## Needs David's eyes
- _risky/uncertain items_

## Next steps
- _what's left_
````

- [ ] **Step 5: Verify the docs render and the CLAUDE.md append landed**

```powershell
"README-WINDOWS.md exists: $(Test-Path README-WINDOWS.md)"
"windows/README.md exists: $(Test-Path windows/README.md)"
"HANDOFF-WINDOWS exists: $(Test-Path docs/HANDOFF-WINDOWS.md)"
Select-String -Path CLAUDE.md -Pattern '## Windows port' | Select-Object -First 1
```
Expected: all `True`, and the `## Windows port` heading is found in `CLAUDE.md`.

- [ ] **Step 6: Commit**

```bash
git add README-WINDOWS.md CLAUDE.md windows/README.md docs/HANDOFF-WINDOWS.md
git commit -m "docs(windows): README-WINDOWS, CLAUDE.md Windows section, windows/README dev guide, HANDOFF template

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Dogfood checklist (`docs/launch/windows-dogfood-checklist.md`)

> A manual checklist of things CI cannot exercise (GUI, mic, GPU, Bluetooth, focus changes, elevation). These are the acceptance gates a human runs once before David ships. No code.

**Files:**
- Create: `docs/launch/windows-dogfood-checklist.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `docs/launch/windows-dogfood-checklist.md`** (complete content)

````markdown
# JVoice for Windows — Dogfood Checklist (manual)

Things the automated suite **can't** verify (GUI, microphone, GPU, Bluetooth, focus
changes, elevation). Run this once on a real machine before considering a build
shippable. Check each box; note the OS build, GPU, and JVoice build flavor (CPU/GPU)
at the top of your run.

> Environment: Windows ____ (build ____) · GPU ____ · JVoice build: CPU single-file / GPU zip / installer · date ____

## First run & tray
- [ ] First launch shows the **Settings window once** with the "running in your system
      tray — press Ctrl+Shift+Space to dictate" affordance (overview §6.5).
- [ ] The **tray icon is the black-squircle "J"** and its right-click menu has Settings… and Quit.
- [ ] Second launch starts **silently to the tray** (no Settings window).
- [ ] A second instance does **not** start (single-instance mutex) — launching again just
      surfaces the existing one (or no-ops cleanly).

## Core dictation loop (paste targets)
- [ ] **Ctrl+Shift+Space → speak → Ctrl+Shift+Space** pastes tone-styled text at the cursor in:
  - [ ] **Notepad**
  - [ ] **Microsoft Word**
  - [ ] a **browser** text field (e.g. address bar / a textarea)
  - [ ] **VS Code** editor
- [ ] The **HUD pill** cycles through states: recording → (transcribing) → done, and on
      error shows the error pill; the tray icon mirrors the state.

## Accuracy
- [ ] Add custom words ("Li-Fraumeni", "VS Code", a project name) in Settings; dictate a
      sentence containing them on the **Large** model with **GPU** — they come out correct
      (the vocabulary prompt + phonetic matcher working end-to-end).
- [ ] Dictate a normal paragraph with **no** custom words — none of the custom words
      hallucinate into the output (spurious-vocab == 0 in real use).

## Streaming / long audio
- [ ] A **long (>30 s) dictation with natural pauses** transcribes fully — no dropped
      chunk in the middle, no truncation of the tail (streaming-while-recording + the
      lossless whole-file fallback).
- [ ] If the streamed session falls back, the result is still correct (whole-file
      transcript), not empty.

## Audio routing / Bluetooth
- [ ] With a **Bluetooth headset connected**, dictation works **and the headset stays in
      high-quality A2DP** (music doesn't drop to the tinny hands-free profile) — JVoice
      records from a non-Bluetooth input (overview §4.7 AudioInputRouter).

## Robustness
- [ ] **Rapid hotkey double-press** (press twice fast) does not start two recordings or
      wedge the state — the 150 ms debounce holds.
- [ ] **Quit mid-recording** (Quit from the tray while recording) leaves **no orphan WAV**
      in `%TEMP%` — confirm: `Get-ChildItem $env:TEMP\jvoice-*.wav` returns nothing after
      quit (and the launch-time sweep also clears any strays).
- [ ] **Microphone denied** (Settings → Privacy → Microphone → off for desktop apps) →
      dictation shows a clear "microphone access denied" HUD error that deep-links to
      `ms-settings:privacy-microphone` (not a silent failure or crash).

## Model download
- [ ] Selecting a **new model** for the first time shows the **download-progress HUD**
      state, completes, and the model file appears under `%LOCALAPPDATA%\JVoice\models\`
      with the correct size. Subsequent uses skip the download.

## Launch at login
- [ ] **Launch-at-login** is enabled (first-run default) — confirm the Run key:
      `Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name JVoice`
      shows the exe path. Toggling it off in Settings removes the entry.
- [ ] After a **reboot**, JVoice starts to the tray automatically.

## Elevation / UIPI (documented limitation, verify it fails gracefully)
- [ ] Focus an **elevated (admin) window** (e.g. an admin PowerShell / Terminal), dictate,
      and confirm JVoice **fails gracefully** — it does NOT crash; it shows a paste-failed
      HUD/notification (UIPI blocks a non-elevated app from sending input to an elevated
      window — overview §6.4). The transcript is preserved (recoverable from Settings →
      last transcript), so nothing is lost.

## SmartScreen (the shipped, downloaded artifact)
- [ ] Download the built `.exe` through a browser (so it gets Mark-of-the-Web), run it,
      and confirm the **"Windows protected your PC → More info → Run anyway"** flow works
      and is a one-time click (matches `docs/launch/windows-distribution.md`).
````

- [ ] **Step 2: Commit**

```bash
git add docs/launch/windows-dogfood-checklist.md
git commit -m "docs(launch): Windows manual dogfood checklist (tray/paste/GPU accuracy/streaming/BT/UIPI/SmartScreen)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (run after all tasks)

- [ ] **Whole-solution build is green:**
  ```bash
  dotnet build windows/JVoice.sln -c Release
  ```
  Expected: `Build succeeded` for `JVoice.Core`, `JVoice.App`, `JVoice.Tests`, `tools/generate-icon`, `tools/whisper-smoke`, `tools/verify-transcription`.

- [ ] **Unit tests green:**
  ```bash
  dotnet test windows/JVoice.Tests/JVoice.Tests.csproj -c Release
  ```
  Expected: `Passed!  - Failed: 0, Passed: N` with N > 0.

- [ ] **CPU single-file publishes and runs:** Task 1 Steps 3–5 → non-empty `--bench` transcript, `exit=0`.

- [ ] **GPU folder build publishes and runs on GPU:** Task 1 Steps 6–7 → `runtime: whisper.cpp (Cuda)`, `exit=0`.

- [ ] **Installer builds:** Task 3 Step 4 → `JVoice-Setup-1.0.0.exe` produced.

- [ ] **E2E harness reaches ALL PASS on a capable model:** Task 6 Step 5 → `ALL PASS`, `exit=0`.

- [ ] **CI logic reproduces locally:** Task 5 Step 3 → build + `dotnet test` green, trx counters > 0.

- [ ] **No remote/push happened:**
  ```bash
  git remote -v        # expected: empty (or only what David configured; you added none)
  git log --oneline -12 # expected: your local Phase 5 commits on windows-port, nothing pushed
  git branch --show-current  # expected: windows-port
  ```

- [ ] **Append final results to `docs/HANDOFF-WINDOWS.md`** (Packaging section) and commit.

---

## Self-Review (deliverable → overview promise map)

Every Phase-5 deliverable maps to an overview §5 constraint / §7 "definition of done" / §8 component. Gaps would be plan failures.

| Overview promise | Phase 5 deliverable | Where |
| --- | --- | --- |
| "a self-contained `.exe` is produced" (§7 DoD) | CPU single-file publish recipe (WPF no-trim, native self-extract, ReadyToRun) + GPU folder-zip | Task 1 |
| `scripts/install.sh` → "Phase 5 publish" (§8) | `dotnet publish` recipes (no install script needed; folder/single-file + optional installer) | Tasks 1, 3 |
| `scripts/setup-signing.sh` → "(no signing)" (§8) | **No signing.** Unsigned distribution documented; SmartScreen "Run anyway" flow | Tasks 1, 4 |
| `Resources/Info.plist` → "app.manifest + assembly metadata + AppUserModelId" (§8) | Final `app.manifest` (asInvoker/DPI/longPath/UTF-8/supportedOS) + assembly metadata + `ApplicationIcon` + `SetCurrentProcessExplicitAppUserModelID("com.jvoice.app")` | Task 2 |
| "$0 budget … unsigned … document SmartScreen … No paid services" (§5) | `docs/launch/windows-distribution.md` (macOS-posture analog, no cert) + unsigned installer | Tasks 3, 4 |
| `.github/workflows/test.yml` → `windows.yml` (§8) | Separate `windows.yml` (build + `dotnet test` on `windows-latest`, asserts tests ran, no GUI, macOS `test.yml` untouched) | Task 5 |
| `scripts/verify-transcription.py` → `tools/verify-transcription` (§8) | C# port: TTS clips, `--bench` whole-file + `--stream`, LCS retention ≥0.85 + spurious==0 + vocab ≥0.80/all-present, PASS/FAIL table, exit 1 on fail | Task 6 |
| README mirrors + Windows section + dev guide | `README-WINDOWS.md`, `CLAUDE.md` §Windows, `windows/README.md`, `docs/HANDOFF-WINDOWS.md` | Task 7 |
| "no network calls except first-run model download" (§5, §7) | Publish/installer/CI add **no** runtime network behavior; documented in README + distribution doc | Tasks 1, 4, 7 |
| Manual gates (GUI/mic/GPU/BT/UIPI) | Dogfood checklist | Task 8 |
| "Do NOT publish/push/PR/remote" (§5) | No `gh release`, no `git push`, no upload-to-release step; optional CI artifact is gated to `workflow_dispatch` and stays inside the Actions run; final-verification asserts `git remote -v` empty | Tasks 5, Final |
| "brain ports faithfully" (§5) | Harness uses the **exact** Python thresholds/formulas; no loosening | Task 6 |
| GPL-3.0 (§5) | `LICENSE` shipped in every artifact + installer license page; all deps MIT/GPL-compatible | Tasks 1, 3 |

**Confirmation that nothing pushes/publishes:** This phase contains **zero** `git push`, `gh repo create`, `gh release`, remote-add, or upload-to-public-host commands. Every `git` command is a **local** `add`/`commit` on the `windows-port` branch. The only `actions/upload-artifact` use attaches files to the *Actions run* (not a public Release) and the publish-artifact CI job is gated behind a manual `workflow_dispatch` trigger that never fires on push/PR. The harness's only network access is the same one-allowed `ggml-tiny.bin` download (build-time tool, not the shipped app). All packaging is local-only and reversible.

*This is the final phase. With Phases 1–5 complete, JVoice for Windows launches to the tray with the "J" icon, dictates on-device via whisper.cpp (GPU when available), pastes styled text, matches the macOS look, has green CI, ships a self-contained unsigned `.exe`, and is fully documented — all for $0, with nothing pushed.*
