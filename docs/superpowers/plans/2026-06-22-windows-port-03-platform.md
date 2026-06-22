# Phase 3 — Platform services (audio, hotkey, paste, persistence, launch-at-login) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended — fresh subagent per task, review between) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Read `2026-06-22-windows-port-00-overview.md` first** — it defines the architecture, every canonical name, and the global constraints this phase obeys. This phase depends only on **Phase 1** (`JVoice.Core`), not on Phase 2 (Whisper) or Phase 4 (WPF UI).

---

## Goal

Build the Windows **platform services** layer of the JVoice port — the OS-specific glue that Phase 4's `VoiceCoordinator` and UI will wire together:

- **Audio capture** to a growing 16 kHz / mono / 16-bit PCM WAV (`NAudioRecorder`), with launch-time orphan sweep, usable-recording check, microphone-permission probe, and Bluetooth-safe capture-device selection (`AudioInputRouter`).
- **Global hotkey** (`GlobalHotkey`) via a low-level keyboard hook, default **Ctrl+Shift+Space**, 150 ms debounce, rebindable via a `HotkeyChord` value type.
- **Paste** (`Paster`) — clipboard save/restore (all formats) + `SendInput` Ctrl+V into the previously-focused window, with the 300 ms restore delay, plus a `ForegroundWindowTracker` that remembers the last non-self foreground window.
- **Persistence** — `SettingsStore` (debounced JSON of Phase 1's `SettingsState`, forward-version refusal + per-field fallback + corruption backup), `StatsStore` (lifetime words/seconds → avg WPM), `LastTranscriptStore` (last transcript text).
- **Launch at login** (`LaunchAtLogin`) — registry Run key + one-time first-run auto-enable.
- **Single instance** (`SingleInstance`) — named mutex.
- **Settings deep-links + permission errors** (`SettingsUris`, `PermissionError`) — `ms-settings:` URIs and a microphone-denied error carrying a user message + deep link.

**Definition of done:** `JVoice.App` (net9.0-windows) compiles with all these types under `JVoice.App.Platform`; the unit-testable bits (settings JSON round-trip incl. forward-version refusal + per-field fallback, stats WPM math, `HotkeyChord` parse/format, `AudioInputRouter.PickNonBluetooth` policy, `NAudioRecorder.IsUsableRecording`/`SweepOrphanedRecordings`) pass in `JVoice.Tests` via `dotnet test`; the hardware bits (mic capture, global hotkey, paste) pass the explicit manual-verification scripts in each task. No network calls. `VoiceCoordinator` wiring is **Phase 4** — this phase produces the services and a tiny manual smoke harness only.

## Architecture

These services are **Windows-specific** (Win32 P/Invoke, WASAPI via NAudio, WPF `System.Windows.Clipboard`, registry), so they live in the **`JVoice.App`** project (target `net9.0-windows`), namespace **`JVoice.App.Platform`**. They are *not* in `JVoice.Core` (which is pure, cross-platform, BCL-only — see overview §3). They consume Phase 1's `JVoice.Core.Models.SettingsState` / `ToneStyle` / `WhisperModelOption` / `TranscriptionLanguage` / `HudState` and `JVoice.Core.AppTimings`.

**`JVoice.App` may not exist yet** when this phase runs (the overview's file tree lists it as created in Phase 2/4). **Task 1 of this phase creates a minimal `JVoice.App` csproj** (a `net9.0-windows` library/exe shell) if it is absent, so the platform classes have a home. The csproj uses `<UseWPF>true</UseWPF>` (needed for `System.Windows.Clipboard` in `Paster`) but adds **no WPF windows** here — those are Phase 4. If Phase 2 already created `JVoice.App`, reuse it (add the NuGet refs and `Platform/` folder).

**Testability seam:** the pure-policy and pure-math bits are factored into static methods / value types that `JVoice.Tests` (net9.0, no `-windows`, no WPF) can exercise **without** referencing `JVoice.App`. Because `JVoice.App` is `net9.0-windows` and `JVoice.Tests` is plain `net9.0`, `JVoice.Tests` **cannot reference `JVoice.App`**. Therefore the unit-testable logic that must be tested in `JVoice.Tests` is placed in **`JVoice.Core`** (cross-platform) where the test project can reach it: specifically `HotkeyChord` (a pure value type — lives in `JVoice.Core.Models`), the `AudioInputRouter` pick policy (pure — a static method `JVoice.Core.Audio.BluetoothDevicePolicy.PickNonBluetooth`), and the `SettingsState` JSON (de)serialization helpers (`JVoice.Core.Models.SettingsStateJson`). The Windows shells in `JVoice.App.Platform` then call into those pure helpers. This mirrors Phase 1's "pure brain in Core, platform shell in App" split and keeps the accuracy/logic invariants testable on CI without Windows audio/clipboard hardware. Anything that genuinely needs Win32/WASAPI/WPF (the recorder I/O, the hook, SendInput, the registry, the clipboard) is verified manually per task.

**Concurrency model (overview §6.1):** debounced writes (`SettingsStore`) use a `CancellationTokenSource` + `Task.Delay` cancel-and-replace pattern (port of the Swift `saveTask?.cancel()`); the paste restore uses the same cancel-prior-task pattern (port of `restoreTask?.cancel()`). The global hotkey hook runs on a **dedicated STA thread with its own Win32 message loop** (a `WH_KEYBOARD_LL` hook only delivers callbacks to a thread that pumps messages); the `Triggered` event is raised from that thread, so Phase 4 marshals it to the WPF dispatcher.

## Tech Stack

- C# (latest) on **.NET 9**. `JVoice.App` targets `net9.0-windows`; `JVoice.Core`/`JVoice.Tests` target `net9.0`. `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<LangVersion>latest</LangVersion>` (inherited from `windows/Directory.Build.props`, Phase 1 Task 1).
- **NuGet:** `NAudio` **2.3.0** (current stable as of 2026-06-22; pulls in `NAudio.Wasapi` 2.3.0 which provides `MMDeviceEnumerator` for capture-device enumeration). Resolve/confirm the current stable at execution time with `dotnet add package NAudio` and pin the exact resolved version in the csproj.
- Persistence: in-box **`System.Text.Json`** (no extra NuGet).
- Win32 interop: hand-written `[LibraryImport]`/`[DllImport]` P/Invoke against `user32.dll` / `kernel32.dll` (no extra NuGet). Registry via `Microsoft.Win32.Registry` (in-box on `net9.0-windows`).
- Clipboard: WPF `System.Windows.Clipboard` (requires `<UseWPF>true</UseWPF>`).
- Tests: xUnit (already configured in `JVoice.Tests`, Phase 1 Task 1).

## Global Constraints

(From the overview §5 — every task implicitly includes these.)

- **.NET 9.** App = `net9.0-windows`, primary RID `win-x64`. C# latest, nullable enable, implicit usings.
- **Faithful port.** Reproduce the Swift service's behavior exactly: temp filename pattern `jvoice-<guid>.wav`, orphan sweep `jvoice-*.wav`, `isUsableRecording` `minBytes = 1024`, paste restore delay `0.30 s = 300 ms` and failure restore `0.05 s = 50 ms`, hotkey debounce `0.15 s = 150 ms`, settings debounce `0.5 s = 500 ms`, stats `averageWPM = words/seconds*60`, the Bluetooth-redirect *policy* (prefer built-in, then any non-BT). Preserve every numeric constant verbatim. Units: macOS `TimeInterval` seconds → .NET `TimeSpan`/ms per overview §6.2.
- **Windows divergences are deliberate and documented** (overview §6.3–§6.4): default hotkey is **Ctrl+Shift+Space** (Alt+Space is the Windows system menu); paste needs **no accessibility permission** (only the UIPI elevated-target limitation applies — we run `asInvoker`); the macOS `AXIsProcessTrusted` / `didPromptAXOnLaunch` checks are **dropped** (no Windows equivalent); `AudioInputRouter` **does not change the system default device** — it picks a non-Bluetooth *capture endpoint* to record from and leaves the system default untouched (cleaner than the macOS default-device swap, which would disrupt other apps on Windows).
- **Privacy (product promise):** zero network calls in this phase. Raw WAVs are deleted after transcription (Phase 4) and swept on launch (this phase). No telemetry.
- **Do not modify the macOS Swift app** (`Sources/`, `Tests/`, `Package.swift`, `Resources/`). Read-only reference.
- **Do not push / open PRs / add remotes.** Commit locally only, on the `windows-port` branch (created in Phase 1 Task 1; if absent, `git checkout -b windows-port`).
- **TDD where testable:** write the xUnit test, watch it fail, implement, watch it pass, commit. For hardware bits, write the manual-verification script first, implement, run it, record the observed result. Frequent commits — each task ends with one.

## Source-of-truth file map (Swift → C#)

| Swift source | C# target | Test home |
| --- | --- | --- |
| `Sources/JVoice/Services/SettingsStore.swift` + `Models/SettingsState.swift` (custom decoder) | `JVoice.Core/Models/SettingsStateJson.cs` (pure JSON) + `JVoice.App/Platform/SettingsStore.cs` (debounced file I/O) | `JVoice.Tests/SettingsStoreJsonTests.cs` |
| `Sources/JVoice/Services/StatsStore.swift` | `JVoice.App/Platform/StatsStore.cs` (+ pure `JVoice.Core/StatsMath.cs`) | `JVoice.Tests/StatsMathTests.cs` |
| `Sources/JVoice/Services/LastTranscriptStore.swift` | `JVoice.App/Platform/LastTranscriptStore.cs` | manual |
| `Sources/JVoice/Services/LaunchAtLoginManager.swift` | `JVoice.App/Platform/LaunchAtLogin.cs` | manual (registry) |
| `Sources/JVoice/Services/SystemActions.swift` | `JVoice.App/Platform/SystemActions.cs` (event hook) | manual |
| `Sources/JVoice/Services/PermissionError.swift` | `JVoice.App/Platform/PermissionError.cs` | manual |
| `Sources/JVoice/Services/SettingsURLs.swift` | `JVoice.App/Platform/SettingsUris.cs` | manual |
| (new — single instance) | `JVoice.App/Platform/SingleInstance.cs` | manual |
| `Sources/JVoice/Services/RecordingManager.swift` | `JVoice.App/Platform/NAudioRecorder.cs` (+ `IAudioRecorder`) | partial unit (`IsUsableRecording`, `SweepOrphanedRecordings`) + manual mic |
| `Sources/JVoice/Services/AudioInputRouter.swift` | `JVoice.Core/Audio/BluetoothDevicePolicy.cs` (pure pick) + `JVoice.App/Platform/AudioInputRouter.cs` (NAudio glue) | `JVoice.Tests/BluetoothDevicePolicyTests.cs` + manual |
| `Sources/JVoice/Services/HotKeyManager.swift` | `JVoice.Core/Models/HotkeyChord.cs` (pure parse/format) + `JVoice.App/Platform/GlobalHotkey.cs` (hook) | `JVoice.Tests/HotkeyChordTests.cs` + manual |
| `Sources/JVoice/Services/PasteManager.swift` | `JVoice.App/Platform/Paster.cs` + `JVoice.App/Platform/ForegroundWindowTracker.cs` | manual paste |

---

## File Structure (what this phase creates)

```
windows/
├── JVoice.App/
│   ├── JVoice.App.csproj            (created here if absent; net9.0-windows, UseWPF, NAudio ref)
│   ├── app.manifest                 (asInvoker, perMonitorV2 DPI)  ← created here, finalized in Phase 4
│   └── Platform/
│       ├── IAudioRecorder.cs
│       ├── NAudioRecorder.cs
│       ├── AudioInputRouter.cs
│       ├── GlobalHotkey.cs
│       ├── Paster.cs
│       ├── ForegroundWindowTracker.cs
│       ├── LaunchAtLogin.cs
│       ├── SettingsStore.cs
│       ├── StatsStore.cs
│       ├── LastTranscriptStore.cs
│       ├── SettingsUris.cs
│       ├── PermissionError.cs
│       ├── SingleInstance.cs
│       ├── SystemActions.cs
│       └── PlatformPaths.cs          (helper: %APPDATA%\JVoice, %LOCALAPPDATA%\JVoice\models, temp)
├── JVoice.Core/
│   ├── Models/HotkeyChord.cs         (pure value type — testable in JVoice.Tests)
│   ├── Models/SettingsStateJson.cs   (pure JSON (de)serialization — testable)
│   ├── Audio/BluetoothDevicePolicy.cs (pure pick policy — testable)
│   └── StatsMath.cs                  (pure WPM math — testable)
└── JVoice.Tests/
    ├── HotkeyChordTests.cs
    ├── SettingsStoreJsonTests.cs
    ├── StatsMathTests.cs
    └── BluetoothDevicePolicyTests.cs
```

> **Why some "Core" files here, not in `JVoice.App`:** see Architecture → Testability seam. `JVoice.Tests` is `net9.0` and cannot reference the `net9.0-windows` `JVoice.App`, so the pure bits that need automated tests live in `JVoice.Core`. The Windows shells in `JVoice.App.Platform` delegate to them.

---

## Task 1: Create/prepare `JVoice.App` (net9.0-windows) + NuGet + Platform folder

**Files:**
- Create (if absent): `windows/JVoice.App/JVoice.App.csproj`
- Create (if absent): `windows/JVoice.App/app.manifest`
- Create: `windows/JVoice.App/Platform/PlatformPaths.cs`
- Modify: `windows/JVoice.sln` (add `JVoice.App` if not already added)

**Interfaces:**
- Produces: a building `JVoice.App` project referencing `JVoice.Core` + `NAudio`, with a `Platform/` folder and a `PlatformPaths` helper (`%APPDATA%\JVoice`, `%LOCALAPPDATA%\JVoice\models`, temp dir). Consumed by every later task in this phase.

- [ ] **Step 1: Check whether `JVoice.App` already exists**

Run: `dotnet sln windows/JVoice.sln list`
If `JVoice.App/JVoice.App.csproj` is listed (Phase 2 may have created it), skip to Step 4 (just add NuGet + folder + paths). Otherwise create it (Steps 2–3).

- [ ] **Step 2: Create `windows/JVoice.App/JVoice.App.csproj`** (only if absent)

> This is the minimal shell. Phase 4 turns it into the WinExe with `App.xaml`. For Phase 3 it builds as a library-style app shell (it has no entry point yet; that's fine — `dotnet build` succeeds for an `OutputType` of `Library`; Phase 4 switches it to `WinExe` and adds `App.xaml`). We set `OutputType` to `Library` here to avoid needing a `Main`/`App.xaml` before Phase 4.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Library</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
    <RootNamespace>JVoice.App</RootNamespace>
    <AssemblyName>JVoice.App</AssemblyName>
    <UseWPF>true</UseWPF>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <Platforms>x64;ARM64</Platforms>
    <RuntimeIdentifiers>win-x64;win-arm64</RuntimeIdentifiers>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="NAudio" Version="2.3.0" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\JVoice.Core\JVoice.Core.csproj" />
  </ItemGroup>
</Project>
```

> Pin `NAudio` to whatever `dotnet add package NAudio` resolves at execution time (2.3.0 known-good). `<UseWPF>true</UseWPF>` gives access to `System.Windows.Clipboard` (used by `Paster`). `<ApplicationManifest>` references the manifest from Step 3.

- [ ] **Step 3: Create `windows/JVoice.App/app.manifest`** (only if absent — Phase 4 finalizes UI-related bits)

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="JVoice.App" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v2">
        <!-- asInvoker: run non-elevated. UIPI then prevents pasting into elevated
             windows (documented limitation, overview §6.4); we do NOT request elevation. -->
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <!-- Per-monitor v2 DPI: HUD overlay positions correctly on mixed-DPI setups. -->
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/PM</dpiAware>
    </windowsSettings>
  </application>
</assembly>
```

- [ ] **Step 4: Add `NAudio` (if the project pre-existed) and confirm the pinned version**

Run (from `windows/`):
```bash
dotnet add JVoice.App/JVoice.App.csproj package NAudio
```
Then open `JVoice.App.csproj` and confirm the `NAudio` `Version` is the exact resolved stable (e.g. `2.3.0`). Leave it pinned.

- [ ] **Step 5: Add `JVoice.App` to the solution (if not listed)**

Run: `dotnet sln windows/JVoice.sln add windows/JVoice.App/JVoice.App.csproj`

- [ ] **Step 6: Create `windows/JVoice.App/Platform/PlatformPaths.cs`**

```csharp
namespace JVoice.App.Platform;

/// Canonical Windows file locations for JVoice (overview §4.9). Centralized so
/// every store agrees on the same %APPDATA%\JVoice folder and the recorder uses
/// the same temp pattern.
public static class PlatformPaths
{
    /// %APPDATA%\JVoice — settings.json, stats.json, last-transcript.txt live here.
    public static string AppDataDirectory
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "JVoice");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// %LOCALAPPDATA%\JVoice\models — GGML model cache (Phase 2 owns it; defined here for consistency).
    public static string ModelsDirectory
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "JVoice", "models");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string SettingsFile => Path.Combine(AppDataDirectory, "settings.json");
    public static string SettingsCorruptBackupFile => Path.Combine(AppDataDirectory, "settings.corrupt.bak");
    public static string StatsFile => Path.Combine(AppDataDirectory, "stats.json");
    public static string LastTranscriptFile => Path.Combine(AppDataDirectory, "last-transcript.txt");

    /// The system temp directory — recordings are written as jvoice-<guid>.wav here.
    public static string TempDirectory => Path.GetTempPath();

    public const string RecordingPrefix = "jvoice-";
    public const string RecordingExtension = ".wav";
    public const string RecordingSweepPattern = "jvoice-*.wav";
}
```

- [ ] **Step 7: Build**

Run: `dotnet build windows/JVoice.sln`
Expected: `Build succeeded` (0 errors). `JVoice.App` builds as a `net9.0-windows` library with the NAudio reference and `PlatformPaths`.

- [ ] **Step 8: Commit**

```bash
git add windows/JVoice.App windows/JVoice.sln
git commit -m "build(windows): scaffold JVoice.App (net9.0-windows) + NAudio + PlatformPaths"
```

---

## Task 2: SettingsState JSON (de)serialization — forward-version refusal + per-field fallback (TDD, pure, in Core)

> Ports the custom `Codable` behavior of `SettingsState.swift` (`init(from:)`) and `SettingsStore.loadState`'s corruption handling. The **logic** (parse JSON → `SettingsState`, refuse forward versions by throwing, fall back per-field on bad/missing values, always normalize `SchemaVersion` forward) is pure and lives in `JVoice.Core` so `JVoice.Tests` can test it. Phase 3 Task 3's `SettingsStore` then layers debounced file I/O + the corrupt-backup write on top.
>
> **Swift behaviors to reproduce exactly** (from `SettingsState.init(from:)`):
> 1. `schemaVersion` defaults to `0` if absent; the decoded value is checked but the *stored* version is always normalized to `CurrentSchemaVersion` (1).
> 2. If the file's `schemaVersion > CurrentSchemaVersion` → **throw** (caller treats this as corruption → reset to defaults + back up the blob). This is "refuse to read settings from a newer build".
> 3. Each field falls back to its default on a missing or **unparseable** value (`mode → Casual`, `model → Tiny`, `language → English`, `customWords → []`, `removeFillerWords → true`) — a single bad enum value never torpedoes the whole decode.
> 4. The Swift enums also remap a legacy model raw value `"large-v3_turbo"` → `LargeTurbo`. We reproduce that legacy remap.

**Files:**
- Create: `windows/JVoice.Core/Models/SettingsStateJson.cs`
- Test: `windows/JVoice.Tests/SettingsStoreJsonTests.cs`

**Interfaces:**
- Produces (in `JVoice.Core.Models`):
  - `static class SettingsStateJson` —
    - `string Serialize(SettingsState state)` — pretty JSON with string enum names + `schemaVersion` always = `CurrentSchemaVersion`.
    - `SettingsState Deserialize(string json)` — per-field fallback; **throws `ForwardVersionException`** when `schemaVersion > CurrentSchemaVersion`; throws `System.Text.Json.JsonException` on structurally invalid JSON.
  - `sealed class ForwardVersionException : Exception` — `int FileVersion`, `int CurrentVersion`.
- Consumes: `JVoice.Core.Models.SettingsState`, `ToneStyle`, `WhisperModelOption`, `TranscriptionLanguage` (Phase 1).

> **JSON shape decision (logged assumption):** the Windows settings file is brand-new (`%APPDATA%\JVoice\settings.json`); there is no existing Windows file to stay compatible with. We serialize enums as their **C# names** (`"Casual"`, `"Tiny"`, `"English"`, `"LargeTurbo"`) for human-readable, diff-friendly files, and the property names in camelCase to match the Swift keys (`schemaVersion`, `mode`, `model`, `language`, `customWords`, `removeFillerWords`). The deserializer accepts the C# names **case-insensitively** and also accepts the Swift legacy raw values for the model field (`"tiny"`, `"base"`, `"small"`, `"large-v3-v20240930"`, `"large-v3_turbo"`) so a hand-migrated macOS export still reads. Unknown values fall back to the field default.

- [ ] **Step 1: Write `windows/JVoice.Tests/SettingsStoreJsonTests.cs`** (failing — types don't exist)

```csharp
using System.Text.Json;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStoreJsonTests
{
    [Fact]
    public void RoundTrip_PreservesAllFields()
    {
        var original = new SettingsState(
            SchemaVersion: SettingsState.CurrentSchemaVersion,
            Mode: ToneStyle.Formal,
            Model: WhisperModelOption.LargeTurbo,
            Language: TranscriptionLanguage.Romanian,
            CustomWords: new[] { "JVoice", "Li-Fraumeni" },
            RemoveFillerWords: false);

        string json = SettingsStateJson.Serialize(original);
        var back = SettingsStateJson.Deserialize(json);

        Assert.Equal(original.Mode, back.Mode);
        Assert.Equal(original.Model, back.Model);
        Assert.Equal(original.Language, back.Language);
        Assert.Equal(original.CustomWords, back.CustomWords);
        Assert.Equal(original.RemoveFillerWords, back.RemoveFillerWords);
        Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
    }

    [Fact]
    public void Serialize_AlwaysWritesCurrentSchemaVersion()
    {
        // Even if a state somehow carries a stale version, serialize normalizes forward.
        var s = SettingsState.Default with { SchemaVersion = 0 };
        string json = SettingsStateJson.Serialize(s);
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion,
            doc.RootElement.GetProperty("schemaVersion").GetInt32());
    }

    [Fact]
    public void Deserialize_ForwardVersion_Throws()
    {
        string json = """
            { "schemaVersion": 2, "mode": "Casual", "model": "Tiny",
              "language": "English", "customWords": [], "removeFillerWords": true }
            """;
        var ex = Assert.Throws<ForwardVersionException>(() => SettingsStateJson.Deserialize(json));
        Assert.Equal(2, ex.FileVersion);
        Assert.Equal(SettingsState.CurrentSchemaVersion, ex.CurrentVersion);
    }

    [Fact]
    public void Deserialize_MissingSchemaVersion_DefaultsToZero_AndIsAcceptable()
    {
        // Absent version => treated as 0 (< current) => OK, normalized to current.
        string json = """{ "mode": "Formal" }""";
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion);
        Assert.Equal(ToneStyle.Formal, s.Mode);
    }

    [Fact]
    public void Deserialize_UnknownEnumValues_FallBackPerField()
    {
        string json = """
            { "schemaVersion": 1, "mode": "Banana", "model": "Quantum",
              "language": "Klingon", "removeFillerWords": "notabool" }
            """;
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(ToneStyle.Casual, s.Mode);                 // default
        Assert.Equal(WhisperModelOption.Tiny, s.Model);         // default
        Assert.Equal(TranscriptionLanguage.English, s.Language);// default
        Assert.True(s.RemoveFillerWords);                       // default true
        Assert.Empty(s.CustomWords);                            // default []
    }

    [Fact]
    public void Deserialize_MissingFields_UseDefaults()
    {
        var s = SettingsStateJson.Deserialize("{}");
        Assert.Equal(SettingsState.Default.Mode, s.Mode);
        Assert.Equal(SettingsState.Default.Model, s.Model);
        Assert.Equal(SettingsState.Default.Language, s.Language);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.CustomWords);
    }

    [Theory]
    [InlineData("tiny", WhisperModelOption.Tiny)]
    [InlineData("Tiny", WhisperModelOption.Tiny)]
    [InlineData("largeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("LargeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("large-v3_turbo", WhisperModelOption.LargeTurbo)]      // legacy macOS raw value
    [InlineData("large-v3-v20240930", WhisperModelOption.LargeTurbo)]  // legacy macOS raw value
    public void Deserialize_ModelAcceptsLegacyAndCSharpNames(string raw, WhisperModelOption expected)
    {
        string json = $$"""{ "schemaVersion": 1, "model": "{{raw}}" }""";
        Assert.Equal(expected, SettingsStateJson.Deserialize(json).Model);
    }

    [Fact]
    public void Deserialize_StructurallyInvalidJson_ThrowsJsonException()
        => Assert.Throws<JsonException>(() => SettingsStateJson.Deserialize("{ not json"));
}
```

- [ ] **Step 2: Run, verify FAIL** — `dotnet test windows/JVoice.Tests` → does not compile (types undefined).

- [ ] **Step 3: Create `windows/JVoice.Core/Models/SettingsStateJson.cs`**

```csharp
using System.Text.Json;

namespace JVoice.Core.Models;

/// Thrown when a settings file was written by a newer JVoice build
/// (schemaVersion > current). The caller (SettingsStore) treats this exactly
/// like corruption: reset to defaults and back up the original blob.
/// Ports the `DecodingError.dataCorruptedError` throw in SettingsState.init(from:).
public sealed class ForwardVersionException : Exception
{
    public int FileVersion { get; }
    public int CurrentVersion { get; }

    public ForwardVersionException(int fileVersion, int currentVersion)
        : base($"Settings written by a newer JVoice build (v{fileVersion} > v{currentVersion}). Refusing to read.")
    {
        FileVersion = fileVersion;
        CurrentVersion = currentVersion;
    }
}

/// Pure JSON (de)serialization for SettingsState. Faithful port of
/// SettingsState.swift's custom Codable: forward-version refusal, schemaVersion
/// normalized forward on write, and per-field fallback to defaults on missing or
/// unparseable values. No file I/O here (that's Platform/SettingsStore).
public static class SettingsStateJson
{
    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
    };

    public static string Serialize(SettingsState state)
    {
        var dto = new
        {
            schemaVersion = SettingsState.CurrentSchemaVersion, // always normalize forward
            mode = state.Mode.ToString(),
            model = state.Model.ToString(),
            language = state.Language.ToString(),
            customWords = state.CustomWords,
            removeFillerWords = state.RemoveFillerWords,
        };
        return JsonSerializer.Serialize(dto, WriteOptions);
    }

    /// Parses a settings JSON blob. Throws <see cref="ForwardVersionException"/>
    /// when the file version is newer than we understand, and
    /// <see cref="JsonException"/> when the JSON is structurally invalid; every
    /// individual field falls back to its default rather than throwing.
    public static SettingsState Deserialize(string json)
    {
        using var doc = JsonDocument.Parse(json); // throws JsonException on bad JSON
        JsonElement root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new JsonException("Settings root is not a JSON object.");

        int version = TryGetInt(root, "schemaVersion") ?? 0; // absent => 0 (Swift parity)
        if (version > SettingsState.CurrentSchemaVersion)
            throw new ForwardVersionException(version, SettingsState.CurrentSchemaVersion);

        return new SettingsState(
            SchemaVersion: SettingsState.CurrentSchemaVersion, // always normalized forward
            Mode: ParseTone(TryGetString(root, "mode")),
            Model: ParseModel(TryGetString(root, "model")),
            Language: ParseLanguage(TryGetString(root, "language")),
            CustomWords: ParseCustomWords(root),
            RemoveFillerWords: TryGetBool(root, "removeFillerWords") ?? true);
    }

    // MARK: field parsers (each falls back to the field default)

    private static ToneStyle ParseTone(string? raw)
    {
        if (raw is null) return ToneStyle.Casual;
        if (Enum.TryParse<ToneStyle>(raw, ignoreCase: true, out var v)) return v;
        return ToneStyle.Casual;
    }

    private static WhisperModelOption ParseModel(string? raw)
    {
        if (raw is null) return WhisperModelOption.Tiny;
        // Legacy macOS raw values (Swift WhisperModelOption rawValues + the pre-2026-06 alias).
        switch (raw)
        {
            case "large-v3_turbo":
            case "large-v3-v20240930":
                return WhisperModelOption.LargeTurbo;
            case "tiny": return WhisperModelOption.Tiny;
            case "base": return WhisperModelOption.Base;
            case "small": return WhisperModelOption.Small;
        }
        if (Enum.TryParse<WhisperModelOption>(raw, ignoreCase: true, out var v)) return v;
        return WhisperModelOption.Tiny;
    }

    private static TranscriptionLanguage ParseLanguage(string? raw)
    {
        if (raw is null) return TranscriptionLanguage.English;
        if (Enum.TryParse<TranscriptionLanguage>(raw, ignoreCase: true, out var v)) return v;
        return TranscriptionLanguage.English;
    }

    private static IReadOnlyList<string> ParseCustomWords(JsonElement root)
    {
        if (!root.TryGetProperty("customWords", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return Array.Empty<string>();
        var list = new List<string>();
        foreach (var el in arr.EnumerateArray())
            if (el.ValueKind == JsonValueKind.String && el.GetString() is { } s)
                list.Add(s);
        return list;
    }

    // MARK: lenient scalar readers (wrong type => null => field default)

    private static int? TryGetInt(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out int v)
            ? v : null;

    private static string? TryGetString(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String
            ? e.GetString() : null;

    private static bool? TryGetBool(JsonElement root, string name)
        => root.TryGetProperty(name, out var e) && e.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? e.GetBoolean() : null;
}
```

- [ ] **Step 4: Run tests** → `dotnet test windows/JVoice.Tests` → all SettingsStoreJsonTests PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/JVoice.Core/Models/SettingsStateJson.cs windows/JVoice.Tests/SettingsStoreJsonTests.cs
git commit -m "feat(core): SettingsState JSON (forward-version refusal + per-field fallback)"
```

---

## Task 3: SettingsStore (debounced file persistence) + SystemActions error hook

> Ports `SettingsStore.swift`: load on init (corruption → reset to defaults + back up the corrupt blob), 500 ms debounced async writes, `Flush()` (cancel debounce + write now), `Reset()`. Writes to `%APPDATA%\JVoice\settings.json`; on a corrupt/forward-version read, moves the bad file to `settings.corrupt.bak` and reports via `SystemActions.ErrorHandler`. `SystemActions` ports the global error-handler hook (Swift `SystemActions.errorHandler`) — Phase 4's `VoiceCoordinator` subscribes to it; this phase only defines and invokes it.
>
> This task is **not** unit-tested in `JVoice.Tests` (it lives in `net9.0-windows` `JVoice.App` and does real file I/O on a timer). The pure JSON logic it relies on is already locked by Task 2. Verify manually with a tiny console snippet (Step 6).

**Files:**
- Create: `windows/JVoice.App/Platform/SystemActions.cs`
- Create: `windows/JVoice.App/Platform/SettingsStore.cs`

**Interfaces:**
- Produces (in `JVoice.App.Platform`):
  - `static class SystemActions` — `static Action<string>? ErrorHandler { get; set; }`; `static void ReportError(string message)`.
  - `sealed class SettingsStore : IDisposable` —
    - ctor `SettingsStore(string? settingsPath = null, string? corruptBackupPath = null)` (defaults to `PlatformPaths`; params let tests/Phase 4 redirect).
    - `SettingsState State { get; }` (current value).
    - `void Update(Func<SettingsState, SettingsState> transform)` — apply, store, schedule debounced save, raise `Changed`.
    - `void Reset()` — set to `SettingsState.Default`, schedule save, raise `Changed`.
    - `void Flush()` — cancel pending debounce, write synchronously now.
    - `event Action<SettingsState>? Changed`.
    - `Dispose()` — flush + cancel.
- Consumes: `SettingsStateJson`, `SettingsState` (Phase 1), `PlatformPaths`, `SystemActions`. Timing: `AppTimings.SettingsDebounceMs` (= 500, Phase 1).

- [ ] **Step 1: Create `windows/JVoice.App/Platform/SystemActions.cs`**

```csharp
namespace JVoice.App.Platform;

/// Global hook for surfacing transient errors to the user. Phase 4 wires
/// ErrorHandler once (to forward to VoiceCoordinator.ShowError) so services that
/// can't reach the coordinator directly (e.g. SettingsStore) can still report
/// failures. Faithful port of SystemActions.swift. The handler is expected to be
/// invoked from arbitrary threads; the WPF subscriber marshals to the dispatcher.
public static class SystemActions
{
    public static Action<string>? ErrorHandler { get; set; }

    public static void ReportError(string message) => ErrorHandler?.Invoke(message);
}
```

- [ ] **Step 2: Create `windows/JVoice.App/Platform/SettingsStore.cs`**

```csharp
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// Debounced JSON persistence of SettingsState to %APPDATA%\JVoice\settings.json.
/// Faithful port of SettingsStore.swift: load-on-init with corruption recovery
/// (bad or forward-version file => reset to defaults, original moved to
/// settings.corrupt.bak, reported via SystemActions), 500 ms debounced async
/// writes, Flush(), Reset(). Thread-safety: Update/Reset/Flush are expected to be
/// called from the UI thread (Phase 4); the debounce timer writes on a pool thread.
public sealed class SettingsStore : IDisposable
{
    private readonly string _settingsPath;
    private readonly string _corruptBackupPath;
    private readonly object _gate = new();

    private SettingsState _state;
    private CancellationTokenSource? _saveCts;
    private bool _disposed;

    public event Action<SettingsState>? Changed;

    public SettingsState State
    {
        get { lock (_gate) return _state; }
    }

    public SettingsStore(string? settingsPath = null, string? corruptBackupPath = null)
    {
        _settingsPath = settingsPath ?? PlatformPaths.SettingsFile;
        _corruptBackupPath = corruptBackupPath ?? PlatformPaths.SettingsCorruptBackupFile;

        var (loaded, wasMissing) = Load();
        _state = loaded;
        // Swift wrote defaults to disk when nothing loaded — keep parity so a
        // fresh install has a settings.json immediately.
        if (wasMissing) PerformSave(_state);
    }

    public void Update(Func<SettingsState, SettingsState> transform)
    {
        SettingsState updated;
        lock (_gate)
        {
            updated = transform(_state);
            _state = updated;
        }
        ScheduleSave(updated);
        Changed?.Invoke(updated);
    }

    public void Reset()
    {
        SettingsState reset = SettingsState.Default;
        lock (_gate) _state = reset;
        ScheduleSave(reset);
        Changed?.Invoke(reset);
    }

    public void Flush()
    {
        SettingsState snapshot;
        lock (_gate)
        {
            _saveCts?.Cancel();
            _saveCts = null;
            snapshot = _state;
        }
        PerformSave(snapshot);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Flush();
    }

    // MARK: internals

    private void ScheduleSave(SettingsState snapshot)
    {
        CancellationTokenSource cts;
        lock (_gate)
        {
            _saveCts?.Cancel();
            _saveCts = cts = new CancellationTokenSource();
        }
        var token = cts.Token;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(AppTimings.SettingsDebounceMs, token); }
            catch (OperationCanceledException) { return; }
            if (token.IsCancellationRequested) return;
            PerformSave(snapshot);
        }, token);
    }

    private void PerformSave(SettingsState state)
    {
        try
        {
            string json = SettingsStateJson.Serialize(state);
            string dir = Path.GetDirectoryName(_settingsPath)!;
            Directory.CreateDirectory(dir);
            // Atomic-ish write: temp file then move, so a crash mid-write can't
            // truncate settings.json.
            string tmp = _settingsPath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _settingsPath, overwrite: true);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError(
                $"Failed to save settings — changes may be lost on next launch. {ex.Message}");
        }
    }

    /// Returns (state, wasMissing). On corruption/forward-version, backs up the
    /// bad file and returns defaults with wasMissing = false (so we don't clobber
    /// the backup with an immediate default write).
    private (SettingsState State, bool WasMissing) Load()
    {
        if (!File.Exists(_settingsPath))
            return (SettingsState.Default, WasMissing: true);

        string json;
        try { json = File.ReadAllText(_settingsPath); }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Settings file was unreadable. Using defaults. {ex.Message}");
            return (SettingsState.Default, WasMissing: false);
        }

        try
        {
            return (SettingsStateJson.Deserialize(json), WasMissing: false);
        }
        catch (ForwardVersionException ex)
        {
            BackupCorrupt(json,
                $"Settings were written by a newer JVoice build and reset to defaults. A backup was kept at {_corruptBackupPath}. ({ex.Message})");
            return (SettingsState.Default, WasMissing: false);
        }
        catch (Exception ex) // JsonException etc.
        {
            BackupCorrupt(json,
                $"Settings file was unreadable and reset to defaults. A backup was kept at {_corruptBackupPath}. ({ex.Message})");
            return (SettingsState.Default, WasMissing: false);
        }
    }

    private void BackupCorrupt(string originalJson, string message)
    {
        try { File.WriteAllText(_corruptBackupPath, originalJson); } catch { /* best effort */ }
        SystemActions.ReportError(message);
    }
}
```

- [ ] **Step 3: Build** — `dotnet build windows/JVoice.sln` → succeeds.

- [ ] **Step 4: Manual verification — debounce + persistence + corruption recovery**

> No automated test (file I/O on a timer, `net9.0-windows`). Run this throwaway snippet to confirm behavior, then delete it. Create `windows/JVoice.App/_ManualSettingsSmoke.cs` temporarily:

```csharp
// TEMP — delete after verifying. Add <OutputType>Exe</OutputType> override is NOT
// needed; instead run via a tiny xUnit-less console by temporarily flipping the
// csproj OutputType to Exe and adding this Main, OR exercise it from a scratch
// `dotnet script`. Simplest: write a one-off test in a throwaway net9.0-windows
// console. Steps below assume the throwaway console approach.
```

Concretely, create a throwaway console to drive it:
```bash
mkdir -p windows/_smoke && cd windows/_smoke
dotnet new console -n SettingsSmoke
dotnet add SettingsSmoke reference ../JVoice.App/JVoice.App.csproj
# edit SettingsSmoke/SettingsSmoke.csproj: set <TargetFramework>net9.0-windows</TargetFramework>
```
Put this in `windows/_smoke/SettingsSmoke/Program.cs`:
```csharp
using JVoice.App.Platform;
using JVoice.Core.Models;

string dir = Path.Combine(Path.GetTempPath(), "jvoice-smoke-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(dir);
string settings = Path.Combine(dir, "settings.json");
string backup = Path.Combine(dir, "settings.corrupt.bak");

// 1. fresh install writes defaults immediately
using (var store = new SettingsStore(settings, backup))
{
    Console.WriteLine($"fresh file exists: {File.Exists(settings)}");          // expect True
    store.Update(s => s with { Mode = ToneStyle.Formal, CustomWords = new[] { "JVoice" } });
    store.Flush();
}
Console.WriteLine("after flush, contains Formal: " +
    File.ReadAllText(settings).Contains("Formal"));                            // expect True

// 2. reload preserves it
using (var store = new SettingsStore(settings, backup))
    Console.WriteLine($"reloaded mode: {store.State.Mode}");                    // expect Formal

// 3. corruption recovery: scribble garbage, reopen
File.WriteAllText(settings, "{ not json");
SystemActions.ErrorHandler = msg => Console.WriteLine("REPORTED: " + msg);
using (var store = new SettingsStore(settings, backup))
    Console.WriteLine($"recovered mode: {store.State.Mode}");                   // expect Casual (default)
Console.WriteLine($"backup written: {File.Exists(backup)}");                    // expect True

// 4. forward-version refusal
File.WriteAllText(settings, "{ \"schemaVersion\": 99, \"mode\": \"Formal\" }");
using (var store = new SettingsStore(settings, backup))
    Console.WriteLine($"forward-version recovered mode: {store.State.Mode}");   // expect Casual

Directory.Delete(dir, recursive: true);
```
Run: `dotnet run --project windows/_smoke/SettingsSmoke`
Expected output (order):
```
fresh file exists: True
after flush, contains Formal: True
reloaded mode: Formal
REPORTED: Settings file was unreadable and reset to defaults...
recovered mode: Casual
backup written: True
forward-version recovered mode: Casual
```
Then remove the smoke project: `rm -rf windows/_smoke` (it is under `windows/`, ignored by `.gitignore`'s `obj/`/`bin/` but the source folder is not — make sure not to commit it).

- [ ] **Step 5: Commit**

```bash
git add windows/JVoice.App/Platform/SettingsStore.cs windows/JVoice.App/Platform/SystemActions.cs
git commit -m "feat(platform): SettingsStore (debounced JSON persistence + corruption recovery) + SystemActions"
```

---

## Task 4: StatsStore + pure WPM math (TDD for the math)

> Ports `StatsStore.swift`: lifetime `totalWords` (int) + `totalSeconds` (double); `averageWPM = totalWords/totalSeconds*60` (0 when no seconds); `Record(words, durationSeconds)` ignores non-positive inputs. macOS used UserDefaults; Windows persists to `%APPDATA%\JVoice\stats.json` as `{ "totalWords": int, "totalSeconds": double }` (overview §4.9). The WPM formula + the guard are pure → tested in `JVoice.Core`; the file I/O is in `JVoice.App`.

**Files:**
- Create: `windows/JVoice.Core/StatsMath.cs`
- Create: `windows/JVoice.App/Platform/StatsStore.cs`
- Test: `windows/JVoice.Tests/StatsMathTests.cs`

**Interfaces:**
- Produces:
  - `static class StatsMath` (in `JVoice.Core`) — `double AverageWpm(int totalWords, double totalSeconds)`.
  - `sealed class StatsStore` (in `JVoice.App.Platform`) — ctor `StatsStore(string? statsPath = null)`; `int TotalWords { get; }`; `double TotalSeconds { get; }`; `double AverageWpm { get; }`; `void Record(int words, double durationSeconds)` (persists immediately); `void Reset()`.
- Consumes: `PlatformPaths`, `StatsMath`.

- [ ] **Step 1: Write `windows/JVoice.Tests/StatsMathTests.cs`** (failing)

```csharp
using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

public class StatsMathTests
{
    [Fact]
    public void Zero_Seconds_ReturnsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, 0));

    [Fact]
    public void Negative_Seconds_ReturnsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, -5));

    [Theory]
    [InlineData(120, 60.0, 120.0)]   // 120 words in 60s = 120 wpm
    [InlineData(60, 30.0, 120.0)]    // 60 words in 30s = 120 wpm
    [InlineData(150, 120.0, 75.0)]   // 150 words in 120s = 75 wpm
    public void Computes_WordsPerMinute(int words, double seconds, double expected)
        => Assert.Equal(expected, StatsMath.AverageWpm(words, seconds), precision: 6);
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/StatsMath.cs`**

```csharp
namespace JVoice.Core;

/// Pure dictation-stats math. Faithful port of StatsStore.averageWPM:
/// words per minute = (totalWords / totalSeconds) * 60, guarded to 0 when no time.
public static class StatsMath
{
    public static double AverageWpm(int totalWords, double totalSeconds)
    {
        if (totalSeconds <= 0) return 0;
        return (double)totalWords / totalSeconds * 60.0;
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Create `windows/JVoice.App/Platform/StatsStore.cs`**

```csharp
using System.Text.Json;
using System.Text.Json.Serialization;
using JVoice.Core;

namespace JVoice.App.Platform;

/// Lifetime dictation stats persisted to %APPDATA%\JVoice\stats.json.
/// Faithful port of StatsStore.swift (totalWords + totalSeconds, averageWPM,
/// Record ignores non-positive inputs). Persists synchronously on every Record
/// (stats are small and written rarely — once per dictation).
public sealed class StatsStore
{
    private sealed class StatsDto
    {
        [JsonPropertyName("totalWords")] public int TotalWords { get; set; }
        [JsonPropertyName("totalSeconds")] public double TotalSeconds { get; set; }
    }

    private readonly string _path;
    private readonly object _gate = new();
    private StatsDto _data;

    public StatsStore(string? statsPath = null)
    {
        _path = statsPath ?? PlatformPaths.StatsFile;
        _data = Load();
    }

    public int TotalWords { get { lock (_gate) return _data.TotalWords; } }
    public double TotalSeconds { get { lock (_gate) return _data.TotalSeconds; } }
    public double AverageWpm { get { lock (_gate) return StatsMath.AverageWpm(_data.TotalWords, _data.TotalSeconds); } }

    public void Record(int words, double durationSeconds)
    {
        if (words <= 0 || durationSeconds <= 0) return; // Swift guard
        lock (_gate)
        {
            _data.TotalWords += words;
            _data.TotalSeconds += durationSeconds;
            Save(_data);
        }
    }

    public void Reset()
    {
        lock (_gate)
        {
            _data = new StatsDto();
            Save(_data);
        }
    }

    private StatsDto Load()
    {
        try
        {
            if (!File.Exists(_path)) return new StatsDto();
            string json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<StatsDto>(json) ?? new StatsDto();
        }
        catch
        {
            return new StatsDto(); // corrupt stats are non-critical: start fresh
        }
    }

    private void Save(StatsDto data)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            string tmp = _path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Failed to save stats. {ex.Message}");
        }
    }
}
```

- [ ] **Step 6: Build** — `dotnet build windows/JVoice.sln` → succeeds.

- [ ] **Step 7: Commit**

```bash
git add windows/JVoice.Core/StatsMath.cs windows/JVoice.App/Platform/StatsStore.cs windows/JVoice.Tests/StatsMathTests.cs
git commit -m "feat(platform): StatsStore (lifetime words/seconds → avg WPM) + pure StatsMath"
```

---

## Task 5: LastTranscriptStore

> Ports `LastTranscriptStore.swift`: a single persisted string (the last transcript), get/set. macOS used UserDefaults; Windows uses `%APPDATA%\JVoice\last-transcript.txt` (overview §4.9). Trivial; no automated test (plain file read/write) — verified in the build + a one-line manual check.

**Files:**
- Create: `windows/JVoice.App/Platform/LastTranscriptStore.cs`

**Interfaces:**
- Produces: `sealed class LastTranscriptStore` (in `JVoice.App.Platform`) — ctor `LastTranscriptStore(string? path = null)`; `string Transcript { get; set; }` (empty string when file absent; setter writes UTF-8).
- Consumes: `PlatformPaths`.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/LastTranscriptStore.cs`**

```csharp
using System.Text;

namespace JVoice.App.Platform;

/// Persists the last transcript text to %APPDATA%\JVoice\last-transcript.txt.
/// Faithful port of LastTranscriptStore.swift (a single get/set string, empty
/// when nothing stored).
public sealed class LastTranscriptStore
{
    private readonly string _path;

    public LastTranscriptStore(string? path = null)
        => _path = path ?? PlatformPaths.LastTranscriptFile;

    public string Transcript
    {
        get
        {
            try { return File.Exists(_path) ? File.ReadAllText(_path, Encoding.UTF8) : ""; }
            catch { return ""; }
        }
        set
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                File.WriteAllText(_path, value, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            }
            catch (Exception ex)
            {
                SystemActions.ReportError($"Failed to save last transcript. {ex.Message}");
            }
        }
    }
}
```

- [ ] **Step 2: Build + one-line manual check**

`dotnet build windows/JVoice.sln` → succeeds. Optionally extend the smoke console from Task 3 (if recreated) with:
```csharp
var lt = new LastTranscriptStore(Path.Combine(Path.GetTempPath(), "jv-lt-" + Guid.NewGuid().ToString("N") + ".txt"));
lt.Transcript = "hello world";
Console.WriteLine(lt.Transcript == "hello world"); // expect True
```

- [ ] **Step 3: Commit**

```bash
git add windows/JVoice.App/Platform/LastTranscriptStore.cs
git commit -m "feat(platform): LastTranscriptStore (last-transcript.txt)"
```

---

## Task 6: LaunchAtLogin (registry Run key + first-run auto-enable)

> Ports `LaunchAtLoginManager.swift`. macOS used `SMAppService` + a "did initialize" UserDefaults flag. Windows uses the registry (overview §4.9):
> - **Run entry:** `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value name `JVoice`, value = the quoted exe path. Present ⇒ enabled.
> - **Init flag:** `HKCU\Software\JVoice`, value name `LaunchAtLoginInitialized` (REG_DWORD). `PerformFirstRunEnableIfNeeded` sets it once and best-effort enables.
>
> No permission needed (HKCU is per-user, writable without elevation). No automated test (touches the live registry); verified manually + reverted.

**Files:**
- Create: `windows/JVoice.App/Platform/LaunchAtLogin.cs`

**Interfaces:**
- Produces: `static class LaunchAtLogin` (in `JVoice.App.Platform`) —
  - `bool IsEnabled { get; }` — true iff the Run value `JVoice` exists.
  - `void SetEnabled(bool enabled)` — write/delete the Run value.
  - `void PerformFirstRunEnableIfNeeded()` — if the init flag is unset, set it, then best-effort `SetEnabled(true)` (silent on failure).
  - `string CurrentExecutablePath { get; }` — the path written into the Run value (resolves the host exe).
- Consumes: `Microsoft.Win32.Registry`.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/LaunchAtLogin.cs`**

```csharp
using System.Diagnostics;
using Microsoft.Win32;

namespace JVoice.App.Platform;

/// Launch-at-login via the HKCU Run key. Faithful port of LaunchAtLoginManager.swift:
/// IsEnabled / SetEnabled, plus a one-time first-run auto-enable guarded by an init
/// flag so we never re-enable after the user deliberately turns it off.
/// No elevation required (all HKCU). Errors are swallowed/reported, never thrown to
/// the UI (a dev/unsigned copy may fail to write; the user can flip the toggle later).
public static class LaunchAtLogin
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "JVoice";
    private const string AppKeyPath = @"Software\JVoice";
    private const string InitFlagName = "LaunchAtLoginInitialized";

    /// The exe path written into the Run value. For a published self-contained
    /// single-file build this is the .exe; for `dotnet run` it is the apphost/dll
    /// host — fine for dev (launch-at-login is a release feature).
    public static string CurrentExecutablePath
    {
        get
        {
            // Process.MainModule.FileName is the actual host .exe (e.g. JVoice.exe),
            // not the managed dll — correct for the Run key.
            using var proc = Process.GetCurrentProcess();
            return proc.MainModule?.FileName
                ?? Environment.ProcessPath
                ?? AppContext.BaseDirectory;
        }
    }

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using RegistryKey? run = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
                return run?.GetValue(RunValueName) is string s && s.Length > 0;
            }
            catch { return false; }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using RegistryKey run = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (enabled)
                run.SetValue(RunValueName, Quote(CurrentExecutablePath), RegistryValueKind.String);
            else if (run.GetValue(RunValueName) is not null)
                run.DeleteValue(RunValueName, throwOnMissingValue: false);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Could not update launch-at-login. {ex.Message}");
        }
    }

    /// First launch only: set the init flag and best-effort enable. Silent by design.
    public static void PerformFirstRunEnableIfNeeded()
    {
        try
        {
            using RegistryKey app = Registry.CurrentUser.CreateSubKey(AppKeyPath, writable: true);
            object? flag = app.GetValue(InitFlagName);
            if (flag is int i && i != 0) return; // already initialized
            app.SetValue(InitFlagName, 1, RegistryValueKind.DWord);
        }
        catch
        {
            // If we can't even write the flag, don't risk repeatedly re-enabling; bail.
            return;
        }
        SetEnabled(true); // best-effort; SetEnabled already swallows/reports failures
    }

    /// Wrap the path in quotes so a space in the path (e.g. "C:\Program Files\...")
    /// is treated as a single argument by the shell at logon.
    private static string Quote(string path) => path.StartsWith('"') ? path : $"\"{path}\"";
}
```

- [ ] **Step 2: Build** — `dotnet build windows/JVoice.sln` → succeeds.

- [ ] **Step 3: Manual verification (registry — revert when done)**

> Inspect with `reg query` (PowerShell tool). Drive via a throwaway console (same approach as Task 3) or via the Phase 4 app once it exists. Manual flow:
> 1. `reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v JVoice` → expect "value not found" initially.
> 2. Call `LaunchAtLogin.SetEnabled(true)` → re-query → expect a `JVoice` REG_SZ value = quoted exe path; `LaunchAtLogin.IsEnabled` returns `true`.
> 3. Call `LaunchAtLogin.SetEnabled(false)` → re-query → value gone; `IsEnabled` returns `false`.
> 4. Delete the init flag (`reg delete "HKCU\Software\JVoice" /v LaunchAtLoginInitialized /f`), call `PerformFirstRunEnableIfNeeded()` → the flag is set to 1 and the Run value is created. Call it again → no change (idempotent).
>
> Record the observed results. **Revert**: `reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v JVoice /f` and `reg delete "HKCU\Software\JVoice" /f` so a dev machine isn't left auto-launching a dev build.

- [ ] **Step 4: Commit**

```bash
git add windows/JVoice.App/Platform/LaunchAtLogin.cs
git commit -m "feat(platform): LaunchAtLogin (HKCU Run key + first-run auto-enable)"
```

---

## Task 7: SingleInstance (named mutex)

> New on Windows (no Swift analog — macOS used the app bundle identity). A named `Mutex` ensures only one JVoice runs (a tray app must not spawn duplicates). Phase 4's `App.OnStartup` calls `SingleInstance.TryAcquire`; if it returns false, the second instance signals the first (Phase 4 wires the activation) and exits.

**Files:**
- Create: `windows/JVoice.App/Platform/SingleInstance.cs`

**Interfaces:**
- Produces: `static class SingleInstance` (in `JVoice.App.Platform`) —
  - `bool TryAcquire()` — returns true if this is the first instance (acquired the mutex), false if another instance holds it.
  - `void Release()` — release + dispose the mutex (call on shutdown).
- Consumes: `System.Threading.Mutex`.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/SingleInstance.cs`**

```csharp
namespace JVoice.App.Platform;

/// Ensures a single running JVoice instance via a named mutex. Phase 4 calls
/// TryAcquire() in App startup; a second instance gets false and exits (after
/// optionally signaling the first to show its window — Phase 4 wiring).
/// The Global\ prefix scopes the mutex to the machine; using a per-user suffix
/// keeps it single-instance per user session (a tray app is per-user).
public static class SingleInstance
{
    // Unique, stable name. Per-user (Local\) so two different users can each run one.
    private const string MutexName = @"Local\JVoice.SingleInstance.{8F3A1C2B-7E64-4D9A-9C1F-2A5B6E0D4F71}";

    private static Mutex? _mutex;

    public static bool TryAcquire()
    {
        if (_mutex is not null) return true; // already acquired in this process
        // createdNew == true means no other instance held it.
        _mutex = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);
        if (!createdNew)
        {
            _mutex.Dispose();
            _mutex = null;
            return false;
        }
        return true;
    }

    public static void Release()
    {
        try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { /* not owned */ }
        _mutex?.Dispose();
        _mutex = null;
    }
}
```

- [ ] **Step 2: Build** — succeeds.

- [ ] **Step 3: Manual verification (throwaway console)**

> Add a temporary console that calls `TryAcquire()` then `Console.ReadLine()` (holds the mutex while blocked). Run two copies:
> - First copy: `TryAcquire()` → prints `true`, blocks on ReadLine.
> - Second copy (separate terminal): `TryAcquire()` → prints `false` (mutex held).
> - Let the first exit (press Enter → `Release()`), rerun the second → now `true`.
> Record results, delete the throwaway.

- [ ] **Step 4: Commit**

```bash
git add windows/JVoice.App/Platform/SingleInstance.cs
git commit -m "feat(platform): SingleInstance (named mutex)"
```

---

## Task 8: SettingsUris + PermissionError (microphone)

> Ports `SettingsURLs.swift` and `PermissionError.swift`, keeping only the **microphone** case (overview §6.4: paste needs no accessibility permission on Windows; the other macOS cases — accessibility/automation/bluetooth/location/screen-recording — have no JVoice-relevant Windows equivalent and are dropped). Windows deep-links use the `ms-settings:` scheme. Microphone → `ms-settings:privacy-microphone`.

**Files:**
- Create: `windows/JVoice.App/Platform/SettingsUris.cs`
- Create: `windows/JVoice.App/Platform/PermissionError.cs`

**Interfaces:**
- Produces:
  - `static class SettingsUris` (in `JVoice.App.Platform`) — `const string Microphone = "ms-settings:privacy-microphone"`; `void Open(string uri)` (launches via the shell); `void OpenMicrophoneSettings()`.
  - `sealed class PermissionError : Exception` (in `JVoice.App.Platform`) — `PermissionErrorKind Kind`; `string UserMessage`; `string DeepLink`; static `Microphone()`; `void Surface()` (report via SystemActions); `void SurfaceAndOpenSettings()` (report + open the deep link).
  - `enum PermissionErrorKind { MicrophoneDenied }`.
- Consumes: `SystemActions`.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/SettingsUris.cs`**

```csharp
using System.Diagnostics;

namespace JVoice.App.Platform;

/// Deep links into Windows Settings via the ms-settings: scheme. Faithful port of
/// SettingsURLs.swift, re-expressed for Windows (overview §6.4). Only microphone is
/// relevant to JVoice on Windows (paste needs no permission).
public static class SettingsUris
{
    public const string Microphone = "ms-settings:privacy-microphone";

    /// Open a settings URI in the default handler (the Settings app).
    public static void Open(string uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Could not open Settings ({uri}). {ex.Message}");
        }
    }

    public static void OpenMicrophoneSettings() => Open(Microphone);
}
```

- [ ] **Step 2: Create `windows/JVoice.App/Platform/PermissionError.cs`**

```csharp
namespace JVoice.App.Platform;

public enum PermissionErrorKind
{
    MicrophoneDenied,
}

/// Permission failures surfaced to the user with a message + a Settings deep link.
/// Faithful port of PermissionError.swift, scoped to microphone (overview §6.4).
public sealed class PermissionError : Exception
{
    public PermissionErrorKind Kind { get; }
    public string UserMessage { get; }
    public string DeepLink { get; }

    private PermissionError(PermissionErrorKind kind, string userMessage, string deepLink)
        : base(userMessage)
    {
        Kind = kind;
        UserMessage = userMessage;
        DeepLink = deepLink;
    }

    public static PermissionError Microphone() => new(
        PermissionErrorKind.MicrophoneDenied,
        "Microphone access denied. Grant access in Settings → Privacy & security → Microphone (turn on \"Let desktop apps access your microphone\").",
        SettingsUris.Microphone);

    /// Report the message via the global error hook (HUD in Phase 4).
    public void Surface() => SystemActions.ReportError(UserMessage);

    /// Report and open the Settings deep link.
    public void SurfaceAndOpenSettings()
    {
        Surface();
        SettingsUris.Open(DeepLink);
    }
}
```

- [ ] **Step 3: Build** — succeeds.

- [ ] **Step 4: Manual verification**

> Call `SettingsUris.OpenMicrophoneSettings()` (from a throwaway console or Phase 4) → the Windows **Settings → Privacy & security → Microphone** page opens. Confirm visually. Confirm `PermissionError.Microphone().UserMessage` and `.DeepLink == "ms-settings:privacy-microphone"`.

- [ ] **Step 5: Commit**

```bash
git add windows/JVoice.App/Platform/SettingsUris.cs windows/JVoice.App/Platform/PermissionError.cs
git commit -m "feat(platform): SettingsUris (ms-settings deep links) + PermissionError (microphone)"
```

---

## Task 9: AudioInputRouter — pure non-Bluetooth pick policy (TDD) + NAudio glue

> Ports `AudioInputRouter.swift`, adapted per the overview (Task brief): **on Windows we do NOT change the system default device.** Instead we enumerate capture endpoints and, **only when the default capture endpoint is Bluetooth**, pick a non-Bluetooth capture endpoint to record from (leaving the system default untouched). The recorder then opens that specific endpoint. This avoids disrupting other apps and reproduces the *intent* of the macOS A2DP-preservation logic (never open the BT headset's mic, which would drag it from A2DP into HFP/SCO and wreck the user's music).
>
> **Pick policy (pure, identical to Swift `redirectTarget`):** if the default capture endpoint is **not** Bluetooth → return null (record from the system default, the normal case). If it **is** Bluetooth → among non-Bluetooth capture endpoints, prefer one whose form factor is a built-in/integrated mic; else the first non-Bluetooth endpoint; if there are no non-Bluetooth endpoints → return null (nothing safe to fall back to; record from default and accept the SCO switch).
>
> **Bluetooth detection (NAudio glue):** an `MMDevice`'s Bluetooth-ness is detected from device properties. NAudio exposes `MMDevice.Properties`. Two robust signals:
> - `PKEY_Device_EnumeratorName` (`{a45c254e-df1c-4efd-8020-67d146a850e0},24`) equals `"BTHENUM"` for classic Bluetooth audio endpoints (and the BLE enumerator for LE). This is the most reliable.
> - `PKEY_AudioEndpoint_FormFactor` (`{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0`) — a `Headset`/`Headphones`/`Microphone` form factor combined with the BTHENUM enumerator confirms it; `BuiltinMic`/`UnknownFormFactor` for the integrated mic helps the "prefer built-in" preference.
>
> The pure pick policy lives in `JVoice.Core` (testable in `JVoice.Tests`); the NAudio enumeration + property reads live in `JVoice.App`.

**Files:**
- Create: `windows/JVoice.Core/Audio/BluetoothDevicePolicy.cs`
- Create: `windows/JVoice.App/Platform/AudioInputRouter.cs`
- Test: `windows/JVoice.Tests/BluetoothDevicePolicyTests.cs`

**Interfaces:**
- Produces:
  - In `JVoice.Core.Audio`:
    - `readonly record struct CaptureEndpointInfo(string Id, bool IsBluetooth, bool IsBuiltIn)`.
    - `static class BluetoothDevicePolicy` — `string? PickNonBluetooth(bool defaultIsBluetooth, IReadOnlyList<CaptureEndpointInfo> endpoints)` — returns the endpoint **Id** to record from, or null to record from the system default.
  - In `JVoice.App.Platform`:
    - `static class AudioInputRouter` — `string? PreferredCaptureDeviceId()` — enumerates WASAPI capture endpoints, classifies Bluetooth/built-in, applies `BluetoothDevicePolicy`, returns the device id to record from (or null = use default). Robust to any enumeration failure (returns null).
- Consumes: `BluetoothDevicePolicy`, NAudio `MMDeviceEnumerator`/`MMDevice`/`PropertyKey`.

- [ ] **Step 1: Write `windows/JVoice.Tests/BluetoothDevicePolicyTests.cs`** (failing; mirrors Swift `AudioInputRouterTests` for `redirectTarget`)

```csharp
using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class BluetoothDevicePolicyTests
{
    private static CaptureEndpointInfo Bt(string id) => new(id, IsBluetooth: true, IsBuiltIn: false);
    private static CaptureEndpointInfo BuiltIn(string id) => new(id, IsBluetooth: false, IsBuiltIn: true);
    private static CaptureEndpointInfo Usb(string id) => new(id, IsBluetooth: false, IsBuiltIn: false);

    [Fact]
    public void DefaultNotBluetooth_ReturnsNull()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: false,
            new[] { BuiltIn("builtin"), Bt("airpods") });
        Assert.Null(pick); // record from the system default; do nothing
    }

    [Fact]
    public void DefaultBluetooth_PrefersBuiltIn()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Usb("usbmic"), BuiltIn("builtin") });
        Assert.Equal("builtin", pick);
    }

    [Fact]
    public void DefaultBluetooth_NoBuiltIn_FallsBackToFirstNonBluetooth()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Usb("usbmic"), Usb("usbmic2") });
        Assert.Equal("usbmic", pick);
    }

    [Fact]
    public void DefaultBluetooth_NoNonBluetooth_ReturnsNull()
    {
        var pick = BluetoothDevicePolicy.PickNonBluetooth(
            defaultIsBluetooth: true,
            new[] { Bt("airpods"), Bt("buds") });
        Assert.Null(pick); // nothing safe to fall back to
    }

    [Fact]
    public void EmptyEndpoints_ReturnsNull()
        => Assert.Null(BluetoothDevicePolicy.PickNonBluetooth(true, Array.Empty<CaptureEndpointInfo>()));
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Audio/BluetoothDevicePolicy.cs`**

```csharp
namespace JVoice.Core.Audio;

/// A capture endpoint, classified. Id is the platform device id (opaque here).
public readonly record struct CaptureEndpointInfo(string Id, bool IsBluetooth, bool IsBuiltIn);

/// Pure policy for choosing a non-Bluetooth capture endpoint to record from when
/// the system default is a Bluetooth device. Faithful port of
/// AudioInputRouter.redirectTarget: prefer a built-in mic, else the first
/// non-Bluetooth endpoint; null means "leave the default alone / nothing to do".
/// Unlike macOS we DON'T change the system default — the caller just opens the
/// returned device id (overview §6.4).
public static class BluetoothDevicePolicy
{
    public static string? PickNonBluetooth(bool defaultIsBluetooth, IReadOnlyList<CaptureEndpointInfo> endpoints)
    {
        if (!defaultIsBluetooth) return null; // default isn't BT → record from default

        var nonBluetooth = endpoints.Where(e => !e.IsBluetooth).ToList();
        if (nonBluetooth.Count == 0) return null; // no safe fallback → accept the default

        var builtIn = nonBluetooth.FirstOrDefault(e => e.IsBuiltIn);
        if (builtIn.Id is { Length: > 0 }) return builtIn.Id;
        return nonBluetooth[0].Id;
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Create `windows/JVoice.App/Platform/AudioInputRouter.cs`**

```csharp
using JVoice.Core.Audio;
using NAudio.CoreAudioApi;

namespace JVoice.App.Platform;

/// Picks a non-Bluetooth WASAPI capture endpoint to record from when the system
/// default capture endpoint is Bluetooth — so dictating never drags a BT headset
/// out of A2DP into HFP/SCO (which collapses the user's music to mono). Windows
/// analog of AudioInputRouter.swift; unlike macOS we do NOT change the system
/// default device — we just return the device id for NAudioRecorder to open.
/// Any enumeration failure returns null (record from the default, normal path).
public static class AudioInputRouter
{
    // PKEY_Device_EnumeratorName {a45c254e-df1c-4efd-8020-67d146a850e0},24
    private static readonly PropertyKey PkeyEnumeratorName =
        new(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 24);

    /// The device id to record from, or null = use the system default capture device.
    public static string? PreferredCaptureDeviceId()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();

            // The current default capture endpoint (Console role = what apps record from).
            MMDevice? defaultDevice = null;
            if (enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
                defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);

            bool defaultIsBluetooth = defaultDevice is not null && IsBluetooth(defaultDevice);

            var endpoints = new List<CaptureEndpointInfo>();
            foreach (var dev in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                endpoints.Add(new CaptureEndpointInfo(
                    Id: dev.ID,
                    IsBluetooth: IsBluetooth(dev),
                    IsBuiltIn: IsBuiltIn(dev)));
            }

            string? pick = BluetoothDevicePolicy.PickNonBluetooth(defaultIsBluetooth, endpoints);
            defaultDevice?.Dispose();
            return pick;
        }
        catch
        {
            return null; // any HAL/enumeration error → fall back to system default
        }
    }

    private static bool IsBluetooth(MMDevice device)
    {
        try
        {
            // Most reliable: the enumerator name is "BTHENUM" for classic BT audio,
            // and the BLE enumerator name for Bluetooth LE. Match either.
            if (device.Properties.Contains(PkeyEnumeratorName))
            {
                object value = device.Properties[PkeyEnumeratorName].Value;
                string enumName = value?.ToString() ?? string.Empty;
                if (enumName.Contains("BTHENUM", StringComparison.OrdinalIgnoreCase) ||
                    enumName.Contains("BTHLE", StringComparison.OrdinalIgnoreCase) ||
                    enumName.Contains("Bluetooth", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
        }
        catch { /* property read can throw on odd drivers — fall through */ }

        // Secondary signal: a Headset/Headphones form factor is overwhelmingly BT here.
        try
        {
            var ff = device.AudioEndpointFormFactor;
            if (ff == AudioEndpointFormFactor.Headset || ff == AudioEndpointFormFactor.Headphones)
                return true;
        }
        catch { /* ignore */ }

        // Last resort: a friendly name mentioning Bluetooth/AirPods/Hands-Free.
        try
        {
            string name = device.FriendlyName;
            if (name.Contains("Bluetooth", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("Hands-Free", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("AirPods", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        catch { /* ignore */ }

        return false;
    }

    private static bool IsBuiltIn(MMDevice device)
    {
        try
        {
            // Microphone form factor + not Bluetooth is the integrated/array mic.
            if (device.AudioEndpointFormFactor == AudioEndpointFormFactor.Microphone)
                return true;
        }
        catch { /* ignore */ }
        return false;
    }
}
```

> **NAudio API note:** `MMDevice.AudioEndpointFormFactor`, `MMDevice.Properties` (a `PropertyStore`), `MMDevice.ID`, `MMDevice.FriendlyName`, `MMDeviceEnumerator.EnumerateAudioEndPoints`, `GetDefaultAudioEndpoint`, `HasDefaultAudioEndpoint`, `PropertyKey(Guid, int)`, and `PropertyStore.Contains`/indexer + `PropertyStoreProperty.Value` all exist in NAudio 2.x (`NAudio.CoreAudioApi`). If `AudioEndpointFormFactor` is unavailable on the pinned version, drop the form-factor checks and rely on the enumerator-name + friendly-name signals (the policy still works — BTHENUM is the load-bearing signal).

- [ ] **Step 6: Build + manual verification**

`dotnet build windows/JVoice.sln` → succeeds.

Manual (hardware): from a throwaway console, print `AudioInputRouter.PreferredCaptureDeviceId()` and the enumerated endpoints with their `IsBluetooth`/`IsBuiltIn` flags:
- **No BT default** (built-in or USB mic is default) → returns `null`. ✓
- **Pair Bluetooth earbuds/headset and make them the default mic** → returns the built-in (or first non-BT) device id, NOT the earbuds' id, and **the system default is unchanged** (verify in Sound settings). ✓
Record observed device names + the returned id.

- [ ] **Step 7: Commit**

```bash
git add windows/JVoice.Core/Audio/BluetoothDevicePolicy.cs windows/JVoice.App/Platform/AudioInputRouter.cs windows/JVoice.Tests/BluetoothDevicePolicyTests.cs
git commit -m "feat(platform): AudioInputRouter (non-BT capture endpoint pick) + pure policy"
```

---

## Task 10: NAudioRecorder (16 kHz mono PCM WAV, growing file, orphan sweep)

> Ports `RecordingManager.swift`. Records mic audio to a temp WAV `%TEMP%\jvoice-<guid>.wav` at **16 kHz / mono / 16-bit PCM, little-endian**. The WAV must be **readable while growing** by Phase 1's `WavTailReader` (which opens with `FileShare.ReadWrite`), so the recorder writes via NAudio `WaveFileWriter` and **flushes periodically** so the tail reader sees new samples. Launch-time orphan sweep removes any leftover `jvoice-*.wav`. `IsUsableRecording(path, minBytes=1024)`. Microphone permission probe. Teardown-on-failure deletes the partial WAV (a failed recording never leaves raw audio behind). Uses `AudioInputRouter.PreferredCaptureDeviceId()` to pick a non-Bluetooth capture device when needed.
>
> **Capture API:** use NAudio `WasapiCapture` (modern WASAPI; lets us target a specific `MMDevice` for the BT-safe pick). WASAPI capture yields the device's native float/format; we resample/convert to 16 kHz mono 16-bit PCM on the fly into a `WaveFileWriter`. Concretely: open `WasapiCapture` on the chosen device, wrap its incoming samples through a resampler to the target `WaveFormat(16000, 16, 1)`, write to `WaveFileWriter`. NAudio's `MediaFoundationResampler`/`WdlResamplingSampleProvider` handle rate conversion; the simplest robust path is to capture, buffer to a `BufferedWaveProvider`, and pump through a `WdlResamplingSampleProvider` → `SampleToWaveProvider16` → `WaveFileWriter`. Step 3 gives the full implementation.
>
> **Testability:** `IsUsableRecording` and `SweepOrphanedRecordings` are pure-ish file ops — but they live in `JVoice.App` (`net9.0-windows`) and can't be reached from `JVoice.Tests`. They are simple enough to verify with a throwaway console (Step 5) rather than reproduced in Core. The capture itself is hardware — manual mic verification (Step 6).

**Files:**
- Create: `windows/JVoice.App/Platform/IAudioRecorder.cs`
- Create: `windows/JVoice.App/Platform/NAudioRecorder.cs`

**Interfaces:**
- Produces (in `JVoice.App.Platform`):
  - `interface IAudioRecorder` —
    - `bool TryStart(out string? error)` — begin recording; false + error message on failure.
    - `string? Stop()` — stop; returns the finished WAV path (or null if nothing usable).
    - `string? CurrentPath { get; }` — the path being written (null when idle).
    - `bool IsRecording { get; }`
    - `DateTime? StartedAt { get; }`
    - `Task<bool> RequestPermissionAsync()` — probe mic access.
    - `event Action<string>? Failed` — raised on mid-recording failure with a message (the SystemActions analog of the Swift delegate failures).
  - `sealed class NAudioRecorder : IAudioRecorder, IDisposable` implementing the above, plus:
    - `static void SweepOrphanedRecordings()` — delete `%TEMP%\jvoice-*.wav`.
    - `static bool IsUsableRecording(string path, int minBytes = 1024)`.
- Consumes: `AudioInputRouter`, `PlatformPaths`, `SystemActions`, NAudio (`WasapiCapture`, `WaveFileWriter`, `BufferedWaveProvider`, `WdlResamplingSampleProvider`, `SampleToWaveProvider16`, `MMDeviceEnumerator`).

- [ ] **Step 1: Create `windows/JVoice.App/Platform/IAudioRecorder.cs`**

```csharp
namespace JVoice.App.Platform;

/// Microphone capture to a growing 16 kHz/mono/16-bit PCM WAV. Faithful port of
/// the RecordingManager.swift surface (start/stop/permission/orphan sweep/usable
/// check). The DI seam lets Phase 4's VoiceCoordinator be tested with a fake.
public interface IAudioRecorder
{
    bool TryStart(out string? error);
    string? Stop();
    string? CurrentPath { get; }
    bool IsRecording { get; }
    DateTime? StartedAt { get; }
    Task<bool> RequestPermissionAsync();

    /// Raised when a recording fails mid-stream (device lost, write error). The
    /// partial WAV has already been torn down. Analog of the Swift delegate
    /// failure callbacks (encodeFailure / finishedUnsuccessfully / config change).
    event Action<string>? Failed;
}
```

- [ ] **Step 2: Build (interface only) — succeeds.**

- [ ] **Step 3: Create `windows/JVoice.App/Platform/NAudioRecorder.cs`**

```csharp
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace JVoice.App.Platform;

/// Records the microphone to %TEMP%\jvoice-<guid>.wav as 16 kHz / mono / 16-bit
/// PCM, written incrementally so Phase 1's WavTailReader can stream the growing
/// file. Faithful port of RecordingManager.swift: orphan sweep, usable-recording
/// check, permission probe, teardown-on-failure (a failed recording never leaves
/// raw audio behind). Picks a non-Bluetooth capture device when the default is BT
/// (AudioInputRouter) to keep the user's headset music in A2DP.
public sealed class NAudioRecorder : IAudioRecorder, IDisposable
{
    // Target format the brain expects (overview §1, §6.2): 16 kHz, mono, 16-bit PCM LE.
    private const int TargetSampleRate = 16_000;
    private const int TargetBits = 16;
    private const int TargetChannels = 1;
    // Flush the WAV writer roughly this often so WavTailReader sees fresh samples.
    private static readonly TimeSpan FlushInterval = TimeSpan.FromMilliseconds(250);

    private readonly object _gate = new();
    private WasapiCapture? _capture;
    private WaveFileWriter? _writer;
    private BufferedWaveProvider? _buffer;
    private ISampleProvider? _resampledMono;
    private SampleToWaveProvider16? _to16;
    private System.Threading.Timer? _pumpTimer;
    private MMDevice? _device;

    public string? CurrentPath { get; private set; }
    public bool IsRecording { get; private set; }
    public DateTime? StartedAt { get; private set; }

    public event Action<string>? Failed;

    public bool TryStart(out string? error)
    {
        lock (_gate)
        {
            if (IsRecording) { error = null; return false; }
            error = null;
            try
            {
                _device = ResolveCaptureDevice();
                _capture = new WasapiCapture(_device, useEventSync: true)
                {
                    // Keep the device's shared-mode mix format; we convert ourselves.
                };

                string path = MakeTemporaryRecordingPath();
                CurrentPath = path;

                var captureFormat = _capture.WaveFormat;
                _buffer = new BufferedWaveProvider(captureFormat)
                {
                    DiscardOnBufferOverflow = true,
                    BufferDuration = TimeSpan.FromSeconds(5),
                };

                // capture format -> float samples -> mono -> 16 kHz -> 16-bit PCM
                ISampleProvider sampleSource = _buffer.ToSampleProvider();
                if (captureFormat.Channels > 1)
                    sampleSource = new StereoToMonoSampleProvider(sampleSource) { LeftVolume = 0.5f, RightVolume = 0.5f };
                _resampledMono = sampleSource.SampleRate == TargetSampleRate
                    ? sampleSource
                    : new WdlResamplingSampleProvider(sampleSource, TargetSampleRate);
                _to16 = new SampleToWaveProvider16(_resampledMono);

                _writer = new WaveFileWriter(path, _to16.WaveFormat); // 16k/mono/16-bit header

                _capture.DataAvailable += OnDataAvailable;
                _capture.RecordingStopped += OnRecordingStopped;

                _capture.StartRecording();

                _pumpTimer = new System.Threading.Timer(_ => PumpToWriter(), null, FlushInterval, FlushInterval);

                IsRecording = true;
                StartedAt = DateTime.UtcNow;
                return true;
            }
            catch (Exception ex)
            {
                error = $"Could not start the microphone: {ex.Message}";
                TearDownLocked(deleteFile: true);
                return false;
            }
        }
    }

    public string? Stop()
    {
        lock (_gate)
        {
            if (!IsRecording) return CurrentPath;
            string? path = CurrentPath;
            try
            {
                _capture?.StopRecording();   // triggers OnRecordingStopped (drains + disposes)
            }
            catch { /* ignore */ }
            PumpToWriter();                  // final drain of anything buffered
            FinalizeWriterLocked();
            IsRecording = false;
            StartedAt = null;
            DisposeCaptureLocked();
            CurrentPath = null;
            return path is not null && IsUsableRecording(path) ? path : path; // caller checks usability
        }
    }

    /// Probe microphone access. There's no synchronous Windows API; the reliable
    /// probe is to briefly open a capture client and see whether it initializes.
    /// A denied mic (privacy gate off) throws on Init/Start with E_ACCESSDENIED.
    public Task<bool> RequestPermissionAsync()
    {
        return Task.Run(() =>
        {
            try
            {
                using var enumerator = new MMDeviceEnumerator();
                if (!enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
                    return false; // no mic at all
                using var dev = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
                using var probe = new WasapiCapture(dev, useEventSync: true);
                // Initializing the client is enough to surface the privacy denial.
                _ = probe.WaveFormat;
                probe.StartRecording();
                probe.StopRecording();
                return true;
            }
            catch (UnauthorizedAccessException) { return false; }
            catch (System.Runtime.InteropServices.COMException com)
            {
                // E_ACCESSDENIED (0x80070005) => privacy gate denies desktop apps.
                return com.HResult != unchecked((int)0x80070005);
            }
            catch { return false; }
        });
    }

    // MARK: capture callbacks

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        try
        {
            lock (_gate)
            {
                _buffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
            }
        }
        catch { /* buffered overflow is discarded; ignore */ }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is null) return; // clean stop handled by Stop()
        // Mid-recording failure: tear down the partial file and notify (Swift parity:
        // a broken recording must not be transcribed and must not orphan a WAV).
        string message = $"Recording stopped unexpectedly: {e.Exception.Message}";
        lock (_gate)
        {
            TearDownLocked(deleteFile: true);
            IsRecording = false;
            StartedAt = null;
        }
        Failed?.Invoke(message);
        SystemActions.ReportError(message);
    }

    // MARK: writer pumping

    /// Move buffered capture samples through the resampler into the WAV file and
    /// flush, so the growing file is continuously readable by WavTailReader.
    private void PumpToWriter()
    {
        lock (_gate)
        {
            if (_writer is null || _to16 is null) return;
            try
            {
                var temp = new byte[16384];
                int read;
                // Read everything currently available without blocking.
                while ((read = _to16.Read(temp, 0, temp.Length)) > 0)
                {
                    _writer.Write(temp, 0, read);
                    if (read < temp.Length) break;
                }
                _writer.Flush(); // critical: flush so the tail reader sees new bytes
            }
            catch (Exception ex)
            {
                string message = $"Recording write failed: {ex.Message}";
                TearDownLocked(deleteFile: true);
                IsRecording = false;
                StartedAt = null;
                Failed?.Invoke(message);
                SystemActions.ReportError(message);
            }
        }
    }

    private void FinalizeWriterLocked()
    {
        try { _writer?.Flush(); } catch { }
        try { _writer?.Dispose(); } catch { }
        _writer = null;
        _pumpTimer?.Dispose();
        _pumpTimer = null;
        _buffer = null;
        _resampledMono = null;
        _to16 = null;
    }

    private void DisposeCaptureLocked()
    {
        if (_capture is not null)
        {
            _capture.DataAvailable -= OnDataAvailable;
            _capture.RecordingStopped -= OnRecordingStopped;
            try { _capture.Dispose(); } catch { }
            _capture = null;
        }
        try { _device?.Dispose(); } catch { }
        _device = null;
    }

    /// Stop+dispose everything; optionally delete the partial WAV (failure path).
    private void TearDownLocked(bool deleteFile)
    {
        try { _capture?.StopRecording(); } catch { }
        FinalizeWriterLocked();
        DisposeCaptureLocked();
        if (deleteFile && CurrentPath is not null)
        {
            try { File.Delete(CurrentPath); } catch { }
            CurrentPath = null;
        }
    }

    public void Dispose()
    {
        lock (_gate) TearDownLocked(deleteFile: IsRecording);
    }

    // MARK: device selection

    private static MMDevice ResolveCaptureDevice()
    {
        var enumerator = new MMDeviceEnumerator();
        string? preferredId = AudioInputRouter.PreferredCaptureDeviceId();
        if (preferredId is not null)
        {
            try { return enumerator.GetDevice(preferredId); } catch { /* fall through */ }
        }
        return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
    }

    // MARK: static helpers (port of RecordingManager statics)

    private static string MakeTemporaryRecordingPath()
        => Path.Combine(PlatformPaths.TempDirectory,
            $"{PlatformPaths.RecordingPrefix}{Guid.NewGuid():N}{PlatformPaths.RecordingExtension}");

    /// Launch-time sweep of recordings orphaned by a crash/force-quit. Safe at
    /// startup (nothing is recording yet) and scoped to our jvoice-*.wav pattern.
    public static void SweepOrphanedRecordings()
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(
                         PlatformPaths.TempDirectory, PlatformPaths.RecordingSweepPattern))
            {
                try { File.Delete(file); } catch { /* best effort */ }
            }
        }
        catch { /* temp dir unreadable — nothing to sweep */ }
    }

    /// True if `path` is large enough to plausibly contain audio. 1024 bytes is
    /// roughly the minimum a non-empty 16 kHz/16-bit WAV occupies (header + ~32 ms).
    public static bool IsUsableRecording(string path, int minBytes = 1024)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists && info.Length >= minBytes;
        }
        catch { return false; }
    }
}
```

> **WdlResamplingSampleProvider / StereoToMonoSampleProvider / SampleToWaveProvider16** are in `NAudio.Wave.SampleProviders`. `WasapiCapture` and `WaveFileWriter` are in `NAudio.Wave`. `MMDeviceEnumerator.GetDevice(string id)` exists in NAudio 2.x. If `WasapiCapture(MMDevice, bool)` ctor signature differs on the pinned version, use `new WasapiCapture(device)` (default event-sync) — the rest is unchanged.

- [ ] **Step 4: Build** — `dotnet build windows/JVoice.sln` → succeeds.

- [ ] **Step 5: Manual verification — orphan sweep + usable check (no mic needed)**

Throwaway console (or extend Task 3's smoke):
```csharp
using JVoice.App.Platform;

// Plant fake orphans, sweep, confirm gone.
string temp = Path.GetTempPath();
string a = Path.Combine(temp, "jvoice-" + Guid.NewGuid().ToString("N") + ".wav");
string b = Path.Combine(temp, "jvoice-" + Guid.NewGuid().ToString("N") + ".wav");
string keep = Path.Combine(temp, "not-ours-" + Guid.NewGuid().ToString("N") + ".wav");
File.WriteAllBytes(a, new byte[2000]);
File.WriteAllBytes(b, new byte[10]);
File.WriteAllBytes(keep, new byte[2000]);
Console.WriteLine($"usable a (2000B): {NAudioRecorder.IsUsableRecording(a)}");   // True
Console.WriteLine($"usable b (10B): {NAudioRecorder.IsUsableRecording(b)}");      // False
NAudioRecorder.SweepOrphanedRecordings();
Console.WriteLine($"a swept: {!File.Exists(a)}");                                  // True
Console.WriteLine($"b swept: {!File.Exists(b)}");                                  // True
Console.WriteLine($"non-ours kept: {File.Exists(keep)}");                          // True
File.Delete(keep);
```
Run it; confirm the expected booleans.

- [ ] **Step 6: Manual verification — real microphone capture + growing-file read**

Throwaway console:
```csharp
using JVoice.App.Platform;
using JVoice.Core.Audio;

var rec = new NAudioRecorder();
Console.WriteLine($"permission: {await rec.RequestPermissionAsync()}");   // True if mic allowed
if (!rec.TryStart(out var err)) { Console.WriteLine("start failed: " + err); return; }
string path = rec.CurrentPath!;
Console.WriteLine("recording 4s — speak now...");
for (int i = 0; i < 4; i++)
{
    await Task.Delay(1000);
    // Prove the growing file is readable mid-recording via WavTailReader.
    var reader = WavTailReader.Open(path);
    var samples = reader?.Samples(0);
    Console.WriteLine($"t={i+1}s readable samples so far: {samples?.Length ?? -1}");
}
string? final = rec.Stop();
Console.WriteLine($"final path: {final}");
Console.WriteLine($"usable: {final is not null && NAudioRecorder.IsUsableRecording(final)}");
var info = new FileInfo(final!);
Console.WriteLine($"size: {info.Length} bytes");
// Verify header is 16k/mono/16-bit by parsing with the brain:
var hdr = WavTailReader.Open(final!);
Console.WriteLine($"sampleRate={hdr!.Info.SampleRate} channels={hdr.Info.Channels} bytesPerSample={hdr.Info.BytesPerSample}");
File.Delete(final!);
```
Expected:
- `permission: True` (with the mic privacy gate on; flip it off in Settings → re-run → `False`, and `TryStart` fails or `RequestPermissionAsync` returns False).
- The readable-samples count **increases each second** (proves the growing WAV is streamable by `WavTailReader` — the critical Phase 1 ↔ Phase 3 contract).
- `usable: True`, size grows with duration, and `sampleRate=16000 channels=1 bytesPerSample=2` (the brain accepts the file).
Record the per-second sample counts and the final header readout.

> **Failure-teardown spot check (optional):** start recording, then disable the capture device in Sound settings (or unplug a USB mic) mid-recording → `Failed` fires with a message, the partial `jvoice-*.wav` is deleted, and `IsRecording` goes false. Confirm no `jvoice-*.wav` remains.

- [ ] **Step 7: Commit**

```bash
git add windows/JVoice.App/Platform/IAudioRecorder.cs windows/JVoice.App/Platform/NAudioRecorder.cs
git commit -m "feat(platform): NAudioRecorder (16k mono PCM growing WAV, sweep, usable check, perms)"
```

---

## Task 11: ForegroundWindowTracker (last non-self foreground HWND)

> Ports the macOS `lastNonSelfFrontmostPID` concept (it lived in `VoiceCoordinator`/`MenuBarController` on macOS). When the user triggers the hotkey, JVoice's own HUD/tray must not steal the paste target — we need the window that was focused **before** JVoice took focus. This tracker installs a `WinEventHook` for `EVENT_SYSTEM_FOREGROUND` and remembers the last foreground HWND that is **not** owned by our own process. Phase 4 reads `LastForegroundWindow` right before pasting.

**Files:**
- Create: `windows/JVoice.App/Platform/ForegroundWindowTracker.cs`

**Interfaces:**
- Produces: `sealed class ForegroundWindowTracker : IDisposable` (in `JVoice.App.Platform`) —
  - `IntPtr LastForegroundWindow { get; }` — the most recent non-self foreground HWND (or `IntPtr.Zero`).
  - `void Start()` — install the WinEvent hook (must be called on a thread with a message loop; in Phase 4 that's the WPF UI thread).
  - `void Stop()` / `Dispose()` — uninstall.
  - `static IntPtr GetForegroundWindowNow()` — synchronous `GetForegroundWindow()` (a fallback if the hook missed an event).
- Consumes: `user32.dll` P/Invoke.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/ForegroundWindowTracker.cs`**

```csharp
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace JVoice.App.Platform;

/// Remembers the last foreground window that is NOT owned by this process, so the
/// paste target is the app the user was in before JVoice's HUD/tray took focus.
/// Windows analog of the macOS lastNonSelfFrontmostPID. Uses a SetWinEventHook for
/// EVENT_SYSTEM_FOREGROUND; must be created/Started on a thread that pumps Win32
/// messages (the WPF UI thread in Phase 4).
public sealed class ForegroundWindowTracker : IDisposable
{
    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;

    private readonly uint _ownProcessId = (uint)Environment.ProcessId;
    private WinEventDelegate? _callback; // keep the delegate alive (GC would collect it)
    private IntPtr _hook = IntPtr.Zero;

    public IntPtr LastForegroundWindow { get; private set; } = IntPtr.Zero;

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        // Seed with the current foreground window if it isn't ours.
        IntPtr current = GetForegroundWindow();
        if (current != IntPtr.Zero && !IsOwnWindow(current))
            LastForegroundWindow = current;

        _callback = OnForegroundChanged;
        _hook = SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, _callback, 0, 0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    public void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }
        _callback = null;
    }

    public void Dispose() => Stop();

    public static IntPtr GetForegroundWindowNow() => GetForegroundWindow();

    private void OnForegroundChanged(
        IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero) return;
        if (IsOwnWindow(hwnd)) return; // never target our own HUD/tray/settings window
        LastForegroundWindow = hwnd;
    }

    private bool IsOwnWindow(IntPtr hwnd)
    {
        _ = GetWindowThreadProcessId(hwnd, out uint pid);
        return pid == _ownProcessId;
    }

    // MARK: P/Invoke

    private delegate void WinEventDelegate(
        IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWinEventHook(
        uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
```

> **Note:** `SetWinEventHook` is used (not raw P/Invoke source-generated `LibraryImport`) because it takes a managed delegate marshalled to a native callback; the classic `DllImport` + a delegate field (kept alive to avoid GC) is the correct, idiomatic pattern.

- [ ] **Step 2: Build** — succeeds.

- [ ] **Step 3: Manual verification**

> The WinEvent hook needs a message loop, so verify inside a tiny WinForms/WPF throwaway (a console has no pump). Simplest: create a throwaway `net9.0-windows` WinForms app, `new ForegroundWindowTracker()`, `Start()`, a `Button` whose click prints `tracker.LastForegroundWindow` and the window title (via `GetWindowText`). Steps:
> 1. Launch the throwaway app, click into Notepad, then back — observe `LastForegroundWindow` updates to Notepad's HWND (not the throwaway's own window).
> 2. Confirm clicking the throwaway app's own button does **not** set `LastForegroundWindow` to the throwaway's window (own-process skipped) — it stays Notepad.
> Record the observed HWND/title transitions.
>
> (Full automated coverage is impractical for a global hook; Phase 4's end-to-end paste test exercises it for real.)

- [ ] **Step 4: Commit**

```bash
git add windows/JVoice.App/Platform/ForegroundWindowTracker.cs
git commit -m "feat(platform): ForegroundWindowTracker (last non-self foreground HWND)"
```

---

## Task 12: HotkeyChord (pure parse/format, TDD) + GlobalHotkey (low-level keyboard hook)

> Ports `HotKeyManager.swift`. Two pieces:
> 1. **`HotkeyChord`** — a pure value type describing a chord (modifiers + a main key), with `Parse`/`Format`/`Default` (= **Ctrl+Shift+Space**), used by the Phase 4 settings recorder and serialized into settings later. Pure → lives in `JVoice.Core.Models`, tested in `JVoice.Tests`.
> 2. **`GlobalHotkey`** — registers a system-wide hotkey and raises `Triggered` (debounced 150 ms). **Implementation choice: a low-level keyboard hook (`WH_KEYBOARD_LL`)**, NOT `RegisterHotKey`.
>
> **Why `WH_KEYBOARD_LL` over `RegisterHotKey` (decision, justified):**
> - **Flexibility:** a low-level hook sees every key down/up, so we can match arbitrary chords (Ctrl+Shift+Space, and later **push-to-talk** = key-down starts / key-up stops, which `RegisterHotKey` literally cannot express — it only fires on press).
> - **No global-atom conflicts:** `RegisterHotKey` reserves a global hotkey atom; if another app already owns the chord, registration silently fails and the user gets nothing. A hook coexists (we decide whether to swallow the key).
> - **Cost:** a low-level hook adds a tiny per-keystroke callback. We keep the callback trivial (compare modifiers + vkey, post to a queue) so it never stalls the input thread — Windows will silently drop a hook that takes too long, so the callback must return fast.
> - **Requirement:** `WH_KEYBOARD_LL` only delivers callbacks to a thread that runs a **message loop**. We therefore run the hook on a dedicated thread with `GetMessage` pump (implemented here). The `Triggered` event is raised from that thread; Phase 4 marshals it to the dispatcher.
>
> Debounce (150 ms, `AppTimings.HotkeyDebounceMs`) and the default chord are faithful to Swift. The hook is hardware/OS — manual verification.

**Files:**
- Create: `windows/JVoice.Core/Models/HotkeyChord.cs`
- Create: `windows/JVoice.App/Platform/GlobalHotkey.cs`
- Test: `windows/JVoice.Tests/HotkeyChordTests.cs`

**Interfaces:**
- Produces:
  - In `JVoice.Core.Models`:
    - `[Flags] enum HotkeyModifiers { None=0, Control=1, Alt=2, Shift=4, Win=8 }`.
    - `readonly record struct HotkeyChord(HotkeyModifiers Modifiers, int VirtualKey, string KeyName)` —
      - `static HotkeyChord Default` = Ctrl+Shift+Space (`VirtualKey = 0x20`, `KeyName = "Space"`).
      - `string Format()` — e.g. `"Ctrl+Shift+Space"`.
      - `static bool TryParse(string text, out HotkeyChord chord)` — inverse of Format.
  - In `JVoice.App.Platform`:
    - `sealed class GlobalHotkey : IDisposable` —
      - `event Action? Triggered`.
      - `void Register(HotkeyChord chord)` — start the hook thread (or re-target the chord).
      - `void Unregister()` — stop the hook.
      - 150 ms debounce internally.
- Consumes: `HotkeyChord`, `AppTimings.HotkeyDebounceMs`, `user32.dll` P/Invoke.

- [ ] **Step 1: Write `windows/JVoice.Tests/HotkeyChordTests.cs`** (failing)

```csharp
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class HotkeyChordTests
{
    [Fact]
    public void Default_IsCtrlShiftSpace()
    {
        var d = HotkeyChord.Default;
        Assert.True(d.Modifiers.HasFlag(HotkeyModifiers.Control));
        Assert.True(d.Modifiers.HasFlag(HotkeyModifiers.Shift));
        Assert.False(d.Modifiers.HasFlag(HotkeyModifiers.Alt));
        Assert.Equal(0x20, d.VirtualKey); // VK_SPACE
        Assert.Equal("Ctrl+Shift+Space", d.Format());
    }

    [Theory]
    [InlineData("Ctrl+Shift+Space")]
    [InlineData("ctrl+shift+space")]   // case-insensitive
    [InlineData("Control+Shift+Space")]// "Control" alias for "Ctrl"
    public void Parse_RoundTrips_Default(string text)
    {
        Assert.True(HotkeyChord.TryParse(text, out var c));
        Assert.Equal("Ctrl+Shift+Space", c.Format());
    }

    [Fact]
    public void Parse_SingleModifierLetter()
    {
        Assert.True(HotkeyChord.TryParse("Alt+A", out var c));
        Assert.True(c.Modifiers.HasFlag(HotkeyModifiers.Alt));
        Assert.Equal((int)'A', c.VirtualKey); // letters use their ASCII upper code as VK
        Assert.Equal("Alt+A", c.Format());
    }

    [Fact]
    public void Parse_FunctionKey()
    {
        Assert.True(HotkeyChord.TryParse("Ctrl+F5", out var c));
        Assert.Equal(0x74, c.VirtualKey); // VK_F5
        Assert.Equal("Ctrl+F5", c.Format());
    }

    [Fact]
    public void Parse_WinModifier()
    {
        Assert.True(HotkeyChord.TryParse("Win+Space", out var c));
        Assert.True(c.Modifiers.HasFlag(HotkeyModifiers.Win));
        Assert.Equal("Win+Space", c.Format());
    }

    [Theory]
    [InlineData("")]
    [InlineData("Ctrl+")]            // no key
    [InlineData("Ctrl+Shift")]       // modifiers only, no main key
    [InlineData("Bogus+Space")]      // unknown modifier
    [InlineData("Ctrl+NotAKey")]     // unknown key
    public void Parse_Invalid_ReturnsFalse(string text)
        => Assert.False(HotkeyChord.TryParse(text, out _));

    [Fact]
    public void Format_OrdersModifiers_CtrlAltShiftWin()
    {
        // Regardless of input order, Format emits a canonical order.
        Assert.True(HotkeyChord.TryParse("Shift+Ctrl+A", out var c));
        Assert.Equal("Ctrl+Shift+A", c.Format());
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Models/HotkeyChord.cs`**

```csharp
namespace JVoice.Core.Models;

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Control = 1,
    Alt = 2,
    Shift = 4,
    Win = 8,
}

/// A global-hotkey chord: a set of modifiers plus one main key. Pure value type
/// (parse/format) used by the settings recorder and serialization. Default is
/// Ctrl+Shift+Space (overview §5: Alt+Space is the Windows system menu, so the
/// macOS ⌥Space default can't carry over). VirtualKey holds the Win32 VK code.
public readonly record struct HotkeyChord(HotkeyModifiers Modifiers, int VirtualKey, string KeyName)
{
    public const int VkSpace = 0x20;

    public static HotkeyChord Default =>
        new(HotkeyModifiers.Control | HotkeyModifiers.Shift, VkSpace, "Space");

    public string Format()
    {
        var parts = new List<string>(4);
        if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
        parts.Add(KeyName);
        return string.Join("+", parts);
    }

    public static bool TryParse(string text, out HotkeyChord chord)
    {
        chord = default;
        if (string.IsNullOrWhiteSpace(text)) return false;

        var tokens = text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length == 0) return false;

        var mods = HotkeyModifiers.None;
        string? keyToken = null;
        foreach (var raw in tokens)
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl":
                case "control": mods |= HotkeyModifiers.Control; break;
                case "alt": mods |= HotkeyModifiers.Alt; break;
                case "shift": mods |= HotkeyModifiers.Shift; break;
                case "win":
                case "windows":
                case "cmd": mods |= HotkeyModifiers.Win; break;
                default:
                    if (keyToken is not null) return false; // two main keys → invalid
                    keyToken = raw;
                    break;
            }
        }
        if (keyToken is null) return false; // modifiers only, no main key

        if (!TryKeyNameToVk(keyToken, out int vk, out string canonicalName)) return false;
        chord = new HotkeyChord(mods, vk, canonicalName);
        return true;
    }

    /// Maps a friendly key name to a Win32 virtual-key code + a canonical display name.
    private static bool TryKeyNameToVk(string name, out int vk, out string canonical)
    {
        vk = 0; canonical = "";
        string n = name.Trim();
        if (n.Length == 0) return false;

        // Single letter A–Z → VK is the uppercase ASCII code.
        if (n.Length == 1 && char.IsLetter(n[0]))
        {
            char up = char.ToUpperInvariant(n[0]);
            vk = up; canonical = up.ToString();
            return true;
        }
        // Single digit 0–9 → VK is the ASCII code of the digit.
        if (n.Length == 1 && char.IsDigit(n[0]))
        {
            vk = n[0]; canonical = n[0].ToString();
            return true;
        }
        // Function keys F1–F24.
        if ((n.Length == 2 || n.Length == 3) && (n[0] is 'F' or 'f') && int.TryParse(n[1..], out int fn) && fn is >= 1 and <= 24)
        {
            vk = 0x70 + (fn - 1); // VK_F1 = 0x70
            canonical = "F" + fn;
            return true;
        }
        // Named keys.
        switch (n.ToLowerInvariant())
        {
            case "space": vk = 0x20; canonical = "Space"; return true;
            case "enter": case "return": vk = 0x0D; canonical = "Enter"; return true;
            case "tab": vk = 0x09; canonical = "Tab"; return true;
            case "esc": case "escape": vk = 0x1B; canonical = "Esc"; return true;
            case "backspace": vk = 0x08; canonical = "Backspace"; return true;
            case "delete": case "del": vk = 0x2E; canonical = "Delete"; return true;
            case "insert": case "ins": vk = 0x2D; canonical = "Insert"; return true;
            case "home": vk = 0x24; canonical = "Home"; return true;
            case "end": vk = 0x23; canonical = "End"; return true;
            case "pageup": case "pgup": vk = 0x21; canonical = "PageUp"; return true;
            case "pagedown": case "pgdn": vk = 0x22; canonical = "PageDown"; return true;
            case "up": vk = 0x26; canonical = "Up"; return true;
            case "down": vk = 0x28; canonical = "Down"; return true;
            case "left": vk = 0x25; canonical = "Left"; return true;
            case "right": vk = 0x27; canonical = "Right"; return true;
            default: return false;
        }
    }
}
```

- [ ] **Step 4: Run tests** → PASS. (If `Format_OrdersModifiers` fails, confirm the canonical order is Ctrl, Alt, Shift, Win — matching `Format()` above.)

- [ ] **Step 5: Create `windows/JVoice.App/Platform/GlobalHotkey.cs`**

```csharp
using System.Runtime.InteropServices;
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// System-wide hotkey via a low-level keyboard hook (WH_KEYBOARD_LL), running on a
/// dedicated thread with its own Win32 message loop (the hook only delivers to a
/// thread that pumps messages). Raises Triggered (debounced 150 ms) when the chord
/// is pressed. Faithful to HotKeyManager.swift's debounce + toggle semantics; the
/// hook approach (vs RegisterHotKey) is chosen for arbitrary-chord support, future
/// push-to-talk, and to avoid global-atom registration conflicts (see plan §Task 12).
public sealed class GlobalHotkey : IDisposable
{
    public event Action? Triggered;

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_QUIT = 0x0012;

    // Modifier virtual-key codes we read live via GetAsyncKeyState.
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;   // Alt
    private const int VK_SHIFT = 0x10;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;

    private readonly object _gate = new();
    private Thread? _thread;
    private uint _threadId;
    private IntPtr _hook = IntPtr.Zero;
    private LowLevelKeyboardProc? _proc; // keep alive
    private HotkeyChord _chord = HotkeyChord.Default;
    private long _lastFiredTicks; // Stopwatch-less debounce via Environment.TickCount64
    private volatile bool _running;

    public void Register(HotkeyChord chord)
    {
        lock (_gate)
        {
            _chord = chord;
            if (_running) return; // already hooked; chord swap takes effect immediately
            _running = true;
            _thread = new Thread(HookThreadMain)
            {
                IsBackground = true,
                Name = "JVoice-GlobalHotkey",
            };
            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();
        }
    }

    public void Unregister()
    {
        Thread? t;
        uint tid;
        lock (_gate)
        {
            if (!_running) return;
            _running = false;
            t = _thread;
            tid = _threadId;
            _thread = null;
        }
        if (tid != 0) PostThreadMessage(tid, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        t?.Join(1000);
    }

    public void Dispose() => Unregister();

    private void HookThreadMain()
    {
        _threadId = GetCurrentThreadId();
        _proc = HookCallback;
        IntPtr hmod = GetModuleHandle(null);
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, hmod, 0);

        // Standard message pump — required for WH_KEYBOARD_LL callbacks to fire.
        while (_running && GetMessage(out MSG msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }

        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
        _proc = null;
        _threadId = 0;
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = (int)wParam;
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if (MatchesChord((int)data.vkCode))
                {
                    if (TryDebounce())
                        Triggered?.Invoke(); // raised on the hook thread; Phase 4 marshals
                    // Do NOT swallow the key (return CallNextHookEx): keep behavior
                    // transparent. If a future build wants to suppress it, return (IntPtr)1.
                }
            }
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private bool MatchesChord(int vkCode)
    {
        HotkeyChord chord;
        lock (_gate) chord = _chord;
        if (vkCode != chord.VirtualKey) return false;

        bool ctrl = IsDown(VK_CONTROL);
        bool alt = IsDown(VK_MENU);
        bool shift = IsDown(VK_SHIFT);
        bool win = IsDown(VK_LWIN) || IsDown(VK_RWIN);

        bool wantCtrl = chord.Modifiers.HasFlag(HotkeyModifiers.Control);
        bool wantAlt = chord.Modifiers.HasFlag(HotkeyModifiers.Alt);
        bool wantShift = chord.Modifiers.HasFlag(HotkeyModifiers.Shift);
        bool wantWin = chord.Modifiers.HasFlag(HotkeyModifiers.Win);

        return ctrl == wantCtrl && alt == wantAlt && shift == wantShift && win == wantWin;
    }

    private bool TryDebounce()
    {
        long now = Environment.TickCount64;
        lock (_gate)
        {
            if (now - _lastFiredTicks < AppTimings.HotkeyDebounceMs) return false;
            _lastFiredTicks = now;
            return true;
        }
    }

    private static bool IsDown(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    // MARK: P/Invoke

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int pt_x;
        public int pt_y;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);
}
```

- [ ] **Step 6: Build** — succeeds.

- [ ] **Step 7: Manual verification — global hotkey fires + debounces**

Throwaway `net9.0-windows` console (a console works here because `GlobalHotkey` runs its own message-pump thread):
```csharp
using JVoice.App.Platform;
using JVoice.Core.Models;

int fires = 0;
var hk = new GlobalHotkey();
hk.Triggered += () => Console.WriteLine($"TRIGGERED #{++fires} at {DateTime.Now:HH:mm:ss.fff}");
hk.Register(HotkeyChord.Default); // Ctrl+Shift+Space
Console.WriteLine("Press Ctrl+Shift+Space anywhere (focus another app). ENTER to quit.");
Console.ReadLine();
hk.Unregister();
```
Expected:
- Pressing **Ctrl+Shift+Space** (even with another app focused) prints a `TRIGGERED` line. ✓
- Pressing **Ctrl+Space** or **Shift+Space** alone does NOT fire (exact-modifier match). ✓
- **Mashing** the chord rapidly fires at most once per 150 ms (debounce — observe timestamps ≥150 ms apart). ✓
- Re-target: call `hk.Register(parsed)` with `HotkeyChord.TryParse("Ctrl+Alt+J", out var c)` and confirm the new chord fires and the old no longer does.
Record observed fire timestamps proving the debounce.

- [ ] **Step 8: Commit**

```bash
git add windows/JVoice.Core/Models/HotkeyChord.cs windows/JVoice.App/Platform/GlobalHotkey.cs windows/JVoice.Tests/HotkeyChordTests.cs
git commit -m "feat(platform): HotkeyChord (pure parse/format) + GlobalHotkey (WH_KEYBOARD_LL hook)"
```

---

## Task 13: Paster (clipboard save/restore + SendInput Ctrl+V to target HWND)

> Ports `PasteManager.swift`. Saves the clipboard (all formats), sets our text, brings the target window to the foreground, synthesizes **Ctrl+V** via `SendInput`, then restores the prior clipboard after **300 ms** (`AppTimings.PasteRestoreDelay`) on success / **50 ms** on failure, cancelling any prior restore task (Swift `restoreTask?.cancel()`). Outcome maps to `enum PasteOutcome { Ok, AccessDenied, ClipboardLocked, TargetRejected }` (overview §4.7), mirroring the Swift cases (`accessibilityDenied → AccessDenied`, `pasteboardLocked → ClipboardLocked`, `targetRejected`).
>
> **Windows specifics (overview §6.4):**
> - Paste needs **no accessibility permission** — the macOS `AXIsProcessTrusted` check is dropped. The only `AccessDenied` source is the **UIPI** limitation: a non-elevated process can't `SendInput` into an **elevated** target window. We detect that (best-effort) and return `AccessDenied`.
> - `ClipboardLocked`: `OpenClipboard`/WPF `Clipboard.SetDataObject` can fail with `CLIPBRD_E_CANT_OPEN` when another app holds the clipboard — surfaced as `ClipboardLocked`.
> - We use WPF `System.Windows.Clipboard` (needs `[STAThread]` — the WPF UI thread in Phase 4 is STA; for the manual test we use an STA thread).
>
> Hardware/OS behavior → manual verification (Step 4).

**Files:**
- Create: `windows/JVoice.App/Platform/Paster.cs`

**Interfaces:**
- Produces (in `JVoice.App.Platform`):
  - `enum PasteOutcome { Ok, AccessDenied, ClipboardLocked, TargetRejected }`.
  - `sealed class Paster : IDisposable` —
    - `PasteOutcome Paste(string text, IntPtr targetHwnd)` — the full save→focus→Ctrl+V→restore flow.
    - `void Stage(string text)` — set the clipboard to `text` (no paste); used by Phase 4's "copy" affordances.
- Consumes: `JVoice.Core.AppTimings.PasteRestoreDelay`, `System.Windows.Clipboard`, `user32.dll` P/Invoke.

- [ ] **Step 1: Create `windows/JVoice.App/Platform/Paster.cs`**

```csharp
using System.Runtime.InteropServices;
using System.Windows; // System.Windows.Clipboard / IDataObject (WPF)

namespace JVoice.App.Platform;

public enum PasteOutcome
{
    Ok,
    AccessDenied,   // UIPI: target is an elevated window we can't send input to
    ClipboardLocked,// another app holds the clipboard
    TargetRejected, // no usable text, or focusing/SendInput to the target failed
}

/// Pastes text into another window by saving the clipboard, setting our text,
/// focusing the target HWND, synthesizing Ctrl+V via SendInput, then restoring the
/// prior clipboard after a delay (cancelling any prior restore). Faithful port of
/// PasteManager.swift, re-expressed for Win32. No accessibility permission needed
/// (overview §6.4); the only AccessDenied source is the UIPI elevated-target rule.
public sealed class Paster : IDisposable
{
    private readonly object _gate = new();
    private CancellationTokenSource? _restoreCts;

    /// Set the clipboard to `text` only (no paste). Returns true on success.
    public bool Stage(string text)
    {
        return TrySetClipboardText(text);
    }

    public PasteOutcome Paste(string text, IntPtr targetHwnd)
    {
        if (string.IsNullOrEmpty(text)) return PasteOutcome.TargetRejected;

        // UIPI: a non-elevated process cannot SendInput to an elevated window.
        if (targetHwnd != IntPtr.Zero && IsElevatedWindow(targetHwnd))
            return PasteOutcome.AccessDenied;

        // 1. Snapshot the current clipboard so we can restore it.
        IDataObject? saved = CaptureClipboard();

        // 2. Put our text on the clipboard.
        if (!TrySetClipboardText(text))
            return PasteOutcome.ClipboardLocked;

        // 3. Focus the target window so Ctrl+V lands there.
        bool focused = FocusTarget(targetHwnd);
        if (!focused)
        {
            ScheduleRestore(saved, AppTimings.PasteRestoreDelayFailureMs);
            return PasteOutcome.TargetRejected;
        }

        // Brief settle so the target is truly foreground before we type (Swift
        // pasteActivationDelay = 80 ms). Synchronous, short.
        Thread.Sleep(AppTimings_PasteActivationDelayMs);

        // 4. Synthesize Ctrl+V.
        bool sent = SendCtrlV();

        // 5. Always restore — after the target consumed the text on success, or
        //    promptly on failure so the user's clipboard isn't clobbered.
        ScheduleRestore(saved,
            sent ? (int)AppTimings.PasteRestoreDelay.TotalMilliseconds
                 : AppTimings.PasteRestoreDelayFailureMs);

        return sent ? PasteOutcome.Ok : PasteOutcome.TargetRejected;
    }

    public void Dispose()
    {
        lock (_gate) { _restoreCts?.Cancel(); _restoreCts?.Dispose(); _restoreCts = null; }
    }

    // 80 ms (AppTimings.PasteActivationDelay) — kept local as an int for Thread.Sleep.
    private const int AppTimings_PasteActivationDelayMs = 80;

    // MARK: clipboard (WPF, STA)

    private static IDataObject? CaptureClipboard()
    {
        try
        {
            // Clone all formats so a later SetText doesn't mutate what we hold.
            IDataObject current = Clipboard.GetDataObject();
            var clone = new DataObject();
            foreach (string fmt in current.GetFormats(autoConvert: false))
            {
                try
                {
                    object? data = current.GetData(fmt, autoConvert: false);
                    if (data is not null) clone.SetData(fmt, data);
                }
                catch { /* skip formats that won't round-trip */ }
            }
            return clone;
        }
        catch
        {
            return null; // empty/locked clipboard → nothing to restore
        }
    }

    private static bool TrySetClipboardText(string text)
    {
        // WPF Clipboard.SetText has internal retry, but can still throw when locked.
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                Clipboard.SetText(text);
                return true;
            }
            catch (COMException) { Thread.Sleep(20); }
            catch (System.Runtime.InteropServices.ExternalException) { Thread.Sleep(20); }
        }
        return false;
    }

    private void ScheduleRestore(IDataObject? snapshot, int delayMs)
    {
        if (snapshot is null) return; // nothing to restore
        CancellationTokenSource cts;
        lock (_gate)
        {
            _restoreCts?.Cancel(); // cancel a prior pending restore (Swift restoreTask?.cancel())
            _restoreCts?.Dispose();
            _restoreCts = cts = new CancellationTokenSource();
        }
        var token = cts.Token;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(delayMs, token); }
            catch (OperationCanceledException) { return; }
            if (token.IsCancellationRequested) return;
            // Restore must run on an STA thread for the WPF clipboard.
            RunOnSta(() =>
            {
                try { Clipboard.SetDataObject(snapshot, copy: true); } catch { /* best effort */ }
            });
        }, token);
    }

    private static void RunOnSta(Action action)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
        {
            action();
            return;
        }
        var t = new Thread(() => action()) { IsBackground = true };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join(1000);
    }

    // MARK: focus + SendInput

    private static bool FocusTarget(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        // SetForegroundWindow is subject to foreground-lock rules; AttachThreadInput
        // is the standard workaround to reliably steal focus to our paste target.
        uint targetThread = GetWindowThreadProcessId(hwnd, out _);
        uint thisThread = GetCurrentThreadId();
        bool attached = false;
        if (targetThread != thisThread)
            attached = AttachThreadInput(thisThread, targetThread, true);
        try
        {
            ShowWindowAsync(hwnd, SW_SHOW);
            return SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) AttachThreadInput(thisThread, targetThread, false);
        }
    }

    private static bool SendCtrlV()
    {
        // KEYEVENTF_KEYUP = 0x0002; VK_CONTROL = 0x11; V = 0x56.
        var inputs = new INPUT[4];
        inputs[0] = KeyInput(VK_CONTROL, keyUp: false);
        inputs[1] = KeyInput(0x56, keyUp: false); // V down
        inputs[2] = KeyInput(0x56, keyUp: true);  // V up
        inputs[3] = KeyInput(VK_CONTROL, keyUp: true);
        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        return sent == inputs.Length;
    }

    private static INPUT KeyInput(ushort vk, bool keyUp) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            }
        }
    };

    /// Best-effort detection of an elevated (higher-integrity) target window we
    /// cannot SendInput into from a non-elevated process (UIPI). Returns false if
    /// we can't tell (we then attempt the paste and report TargetRejected if it
    /// silently fails).
    private static bool IsElevatedWindow(IntPtr hwnd)
    {
        try
        {
            _ = GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return false;
            IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (hProc == IntPtr.Zero) return false; // can't open => likely higher integrity
            try
            {
                if (!OpenProcessToken(hProc, TOKEN_QUERY, out IntPtr hToken)) return false;
                try
                {
                    // Compare integrity by attempting to read elevation: if the target
                    // is elevated and we are not, GetTokenInformation(TokenElevation)
                    // on the target token will fail or report elevated.
                    int size = Marshal.SizeOf<int>();
                    IntPtr buf = Marshal.AllocHGlobal(size);
                    try
                    {
                        if (GetTokenInformation(hToken, TOKEN_ELEVATION, buf, size, out _))
                        {
                            int elevated = Marshal.ReadInt32(buf);
                            return elevated != 0 && !IsCurrentProcessElevated();
                        }
                        return false;
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
                finally { CloseHandle(hToken); }
            }
            finally { CloseHandle(hProc); }
        }
        catch { return false; }
    }

    private static bool IsCurrentProcessElevated()
    {
        try
        {
            using var id = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(id);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    // MARK: P/Invoke constants + structs

    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const int SW_SHOW = 5;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint TOKEN_QUERY = 0x0008;
    private const int TOKEN_ELEVATION = 20;

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public int type; public InputUnion u; }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, int TokenInformationLength, out int ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);
}
```

> **`AppTimings.PasteRestoreDelayFailureMs`:** Phase 1's `AppTimings` does not define the 50 ms failure-restore constant (the Swift code used a literal `0.05`). Add it to `JVoice.Core/AppTimings.cs` in this task (Step 2) so the constant lives with the others. (This is the only edit to a Phase 1 file; it's purely additive.)

- [ ] **Step 2: Add the failure-restore constant to `windows/JVoice.Core/AppTimings.cs`**

Add this member inside the existing `AppTimings` class (after `PasteRestoreDelay`):
```csharp
    /// PasteManager: restore the prior clipboard quickly after a *failed* paste so
    /// the user's clipboard isn't left clobbered (Swift used 0.05 s).
    public const int PasteRestoreDelayFailureMs = 50;
```

- [ ] **Step 3: Build** — `dotnet build windows/JVoice.sln` → succeeds.

- [ ] **Step 4: Manual verification — paste into another app + clipboard restore**

> WPF `Clipboard` requires STA. Use a throwaway `net9.0-windows` WinForms/WPF app, or a console whose `Main` is `[STAThread]`. Flow:
> 1. Put a known sentinel on the clipboard (e.g. copy "ORIGINAL-CLIP" in Notepad).
> 2. Open Notepad, type nothing, note its HWND (use `ForegroundWindowTracker.GetForegroundWindowNow()` while Notepad is focused, or Spy++).
> 3. From the test app: `new Paster().Paste("hello from JVoice", notepadHwnd)`.
> Expected:
> - Notepad receives **"hello from JVoice"** (the Ctrl+V landed in it). Returns `PasteOutcome.Ok`. ✓
> - After ~300 ms, the clipboard is **restored to "ORIGINAL-CLIP"** (paste again manually into Notepad to confirm). ✓
> 4. **Failure path:** call `Paste("x", IntPtr.Zero)` → returns `TargetRejected` (no target). Clipboard restored quickly.
> 5. **UIPI path (optional):** open an **elevated** (Run as administrator) Notepad/terminal, get its HWND, `Paste("x", elevatedHwnd)` from the non-elevated test app → returns `AccessDenied` (or `TargetRejected` if integrity detection couldn't determine it and SendInput was silently dropped). Document which.
> 6. **Restore-cancel:** call `Paste` twice within 300 ms into the same target → only the second restore runs; the clipboard ends as the snapshot taken at the *second* paste's start (no clobber). Confirm no exception.
> Record the observed outcomes for paste, restore, and the failure/UIPI paths.

- [ ] **Step 5: Commit**

```bash
git add windows/JVoice.App/Platform/Paster.cs windows/JVoice.Core/AppTimings.cs
git commit -m "feat(platform): Paster (clipboard save/restore + SendInput Ctrl+V) + failure-restore timing"
```

---

## Task 14: Phase gate — full build + unit tests + manual-verification checklist

**Files:** none (verification only).

- [ ] **Step 1: Full solution build**

Run: `dotnet build windows/JVoice.sln -c Release`
Expected: `Build succeeded`, 0 errors. (`JVoice.App` builds as `net9.0-windows` library with NAudio + WPF; `JVoice.Core`/`JVoice.Tests` build as `net9.0`.)

- [ ] **Step 2: Run the full unit-test suite**

Run: `dotnet test windows/JVoice.Tests --logger "console;verbosity=normal"`
Expected: **all tests pass**, 0 failures. New Phase 3 tests included: `SettingsStoreJsonTests` (8), `StatsMathTests` (5), `BluetoothDevicePolicyTests` (5), `HotkeyChordTests` (~8) — plus all Phase 1 tests still green. Note the total count.

- [ ] **Step 3: Confirm `JVoice.Core` stayed pure**

Run: `dotnet list windows/JVoice.Core/JVoice.Core.csproj package`
Expected: **no PackageReferences** (the new Core files — `SettingsStateJson`, `StatsMath`, `BluetoothDevicePolicy`, `HotkeyChord` — use only the BCL incl. `System.Text.Json`, which is in-box on net9.0). If anything else appears, remove it.

- [ ] **Step 4: Run the manual hardware/OS verification checklist**

Confirm each was performed and passed (record observed results in the session summary / `docs/HANDOFF-WINDOWS.md`):
- [ ] SettingsStore: fresh-write, reload, corruption recovery + backup, forward-version refusal (Task 3 Step 4).
- [ ] LaunchAtLogin: enable/disable Run value, first-run idempotency, **reverted** (Task 6 Step 3).
- [ ] SingleInstance: second instance gets `false` (Task 7 Step 3).
- [ ] SettingsUris: microphone settings page opens (Task 8 Step 4).
- [ ] AudioInputRouter: no-BT → null; BT default → non-BT pick, system default unchanged (Task 9 Step 6).
- [ ] NAudioRecorder: orphan sweep + usable check; real mic capture; **growing file readable by WavTailReader each second**; final header is 16k/mono/16-bit; failure teardown deletes the partial WAV (Task 10 Steps 5–6).
- [ ] ForegroundWindowTracker: tracks the last non-self HWND (Task 11 Step 3).
- [ ] GlobalHotkey: Ctrl+Shift+Space fires globally, exact-modifier match, 150 ms debounce, re-target works (Task 12 Step 7).
- [ ] Paster: pastes into Notepad, clipboard restored after 300 ms, failure/UIPI paths, restore-cancel (Task 13 Step 4).

- [ ] **Step 5: Ensure no throwaway smoke projects are committed**

Run: `git status` — confirm no `windows/_smoke/` or `_Manual*.cs` files are staged/tracked. Remove any that slipped in.

- [ ] **Step 6: Commit the phase gate (if any parity tests were added) + update the handoff log**

```bash
git add -A
git commit -m "test(platform): phase 3 gate — full build + unit tests green + manual checklist recorded"
```

Append a "Phase 3 — Platform services" section to `docs/HANDOFF-WINDOWS.md` (create it if absent) recording: what was built, the NAudio version pinned, the manual-verification observations (especially the growing-file sample counts and the hotkey debounce timestamps), and any assumptions (below).

---

## Self-Review (spec coverage map: every Swift service → a task)

| macOS Swift service | Windows type(s) | Task | Test/verify |
| --- | --- | --- | --- |
| `Services/SettingsStore.swift` + `Models/SettingsState.swift` custom decoder | `JVoice.Core/SettingsStateJson` (pure) + `JVoice.App/Platform/SettingsStore` | 2, 3 | unit (JSON: round-trip, forward-version refusal, per-field fallback) + manual (debounce, corruption backup) |
| `Services/StatsStore.swift` | `JVoice.Core/StatsMath` (pure) + `JVoice.App/Platform/StatsStore` | 4 | unit (WPM math) + build |
| `Services/LastTranscriptStore.swift` | `JVoice.App/Platform/LastTranscriptStore` | 5 | manual one-liner |
| `Services/LaunchAtLoginManager.swift` | `JVoice.App/Platform/LaunchAtLogin` | 6 | manual (registry, reverted) |
| `Services/SystemActions.swift` | `JVoice.App/Platform/SystemActions` (event hook) | 3 | wired in Phase 4; invoked by stores here |
| `Services/PermissionError.swift` | `JVoice.App/Platform/PermissionError` (microphone) | 8 | manual |
| `Services/SettingsURLs.swift` | `JVoice.App/Platform/SettingsUris` (`ms-settings:`) | 8 | manual (page opens) |
| (new) single instance | `JVoice.App/Platform/SingleInstance` (named mutex) | 7 | manual |
| `Services/AudioInputRouter.swift` | `JVoice.Core/BluetoothDevicePolicy` (pure pick) + `JVoice.App/Platform/AudioInputRouter` (NAudio) | 9 | unit (pick policy) + manual (BT pairing) |
| `Services/RecordingManager.swift` | `JVoice.App/Platform/IAudioRecorder` + `NAudioRecorder` | 10 | manual (mic, growing file, sweep, usable, teardown) |
| (new) last-foreground tracking (macOS `lastNonSelfFrontmostPID`) | `JVoice.App/Platform/ForegroundWindowTracker` | 11 | manual |
| `Services/HotKeyManager.swift` | `JVoice.Core/HotkeyChord` (pure) + `JVoice.App/Platform/GlobalHotkey` (WH_KEYBOARD_LL) | 12 | unit (parse/format) + manual (global fire, debounce) |
| `Services/PasteManager.swift` | `JVoice.App/Platform/Paster` (+ `PasteOutcome`) | 13 | manual (paste, restore, failure/UIPI) |
| `Services/AppTimings.swift` | `JVoice.Core/AppTimings` (Phase 1) — referenced; +`PasteRestoreDelayFailureMs` added here | 13 | n/a (constants) |

No Phase 3 Swift service is unmapped. (`BenchRunner.swift` and `TranscriptionManager.swift` are Phase 2/4/5, not platform — correctly out of scope here.)

## Type-consistency check vs overview §4.7 + Phase 1 names

- **Produced exactly as the overview §4.7 mandates:** `IAudioRecorder` + `NAudioRecorder` (with `TryStart`/`Stop`/`CurrentPath`/`RequestPermissionAsync` + static `SweepOrphanedRecordings`/`IsUsableRecording(path, minBytes=1024)`); `AudioInputRouter` (picks a non-BT capture device id, doesn't change system default); `GlobalHotkey` (event `Triggered`, `Register(chord)`/`Unregister`, 150 ms debounce, default Ctrl+Shift+Space; `HotkeyChord` value type with parse/format); `Paster` + `enum PasteOutcome { Ok, AccessDenied, ClipboardLocked, TargetRejected }` (300 ms restore via `AppTimings.PasteRestoreDelay`); `ForegroundWindowTracker` (last non-self foreground HWND); `LaunchAtLogin` (`IsEnabled`/`SetEnabled`/`PerformFirstRunEnableIfNeeded`); `SettingsStore`/`StatsStore`/`LastTranscriptStore`; `SettingsUris`; `SingleInstance` (named `Mutex`); `PermissionError`. ✓
- **Namespaces:** all Windows-specific types are in `JVoice.App.Platform`; the pure testable helpers (`HotkeyChord`, `SettingsStateJson`, `BluetoothDevicePolicy`, `CaptureEndpointInfo`, `StatsMath`) are in `JVoice.Core` (`JVoice.Core.Models` / `JVoice.Core.Audio` / `JVoice.Core`), reachable by `JVoice.Tests`. This is the only deliberate deviation from "everything in `JVoice.App.Platform`", and it's required by the test-project framework split (documented in Architecture). ✓
- **Consumes Phase 1 verbatim:** `SettingsState` (immutable record + `Default` + `CurrentSchemaVersion`), `ToneStyle`/`WhisperModelOption`/`TranscriptionLanguage` (+ their `ToString()` names used as JSON), `WavTailReader` (the recorder's growing WAV is read by it — verified end-to-end in Task 10), `AppTimings.PasteRestoreDelay`/`HotkeyDebounceMs`/`SettingsDebounceMs`. The only Phase 1 edit is additive (`AppTimings.PasteRestoreDelayFailureMs`). No drift. ✓
- **Persistence paths/keys (overview §4.9):** `%APPDATA%\JVoice\settings.json` (+ `settings.corrupt.bak`), `stats.json` (`{ "totalWords", "totalSeconds" }`), `last-transcript.txt`; registry `HKCU\Software\JVoice` value `LaunchAtLoginInitialized` + `HKCU\...\Run` value `JVoice`; temp `%TEMP%\jvoice-<guid>.wav` (sweep `jvoice-*.wav`). All match. ✓
- **NuGet:** `NAudio` (pinned, 2.3.0 known-good); persistence uses in-box `System.Text.Json`. ✓

## Assumptions (logged per global rules)

1. **`JVoice.App` is created here as `OutputType=Library` (net9.0-windows)** if Phase 2 hasn't already made it. Phase 4 flips it to `WinExe` and adds `App.xaml`. Rationale: platform classes need a `net9.0-windows` home with WPF (for `Clipboard`) before the UI exists, and a library shell builds without a `Main`/`App.xaml`.
2. **Pure testable bits live in `JVoice.Core`, not `JVoice.App.Platform`** (`HotkeyChord`, `SettingsStateJson`, `BluetoothDevicePolicy`, `StatsMath`). Forced by `JVoice.Tests` being `net9.0` and unable to reference the `net9.0-windows` `JVoice.App`. The `JVoice.App.Platform` shells delegate to them. Alternative (a `net9.0-windows` test project) was rejected: it would need Windows-only CI runners and couldn't run the rest of the cross-platform suite uniformly.
3. **Settings JSON uses C# enum names** (`"Casual"`, `"Tiny"`, `"LargeTurbo"`) with case-insensitive + legacy-macOS-rawValue acceptance for the model field. The Windows file is new, so there's no compatibility constraint; readability + a graceful path for a hand-migrated macOS export both win.
4. **`AudioInputRouter` does NOT change the system default device** — it returns a device id for `NAudioRecorder` to open, picking a non-Bluetooth capture endpoint only when the default is Bluetooth. This is the overview-mandated Windows adaptation (cleaner than the macOS default-swap; doesn't disrupt other apps). Bluetooth detection keys on `PKEY_Device_EnumeratorName == "BTHENUM"` primarily, with form-factor + friendly-name fallbacks.
5. **Global hotkey uses `WH_KEYBOARD_LL`, not `RegisterHotKey`** — justified in Task 12 (arbitrary chords, future push-to-talk, no global-atom conflicts). The hook runs on a dedicated STA thread with a message pump; `Triggered` is raised on that thread and Phase 4 marshals to the dispatcher.
6. **`Paster` does not gate on any accessibility permission** (none exists on Windows). The only `AccessDenied` source is the UIPI elevated-target rule; integrity detection is best-effort and falls back to `TargetRejected` if it can't tell. We run `asInvoker` (manifest) and document that pasting into elevated windows is unsupported.
7. **The `Failed` event on `IAudioRecorder`** is the Windows model of the Swift `AVAudioRecorderDelegate` mid-recording failures (encode error / unsuccessful finish / config change) — it tears down + deletes the partial WAV and notifies, matching `tearDownFailedRecording()`.
8. **Manual verification is the gate for hardware/OS bits** (mic, hotkey, paste, registry, BT). The pure logic underneath each is unit-tested; the OS integration is verified via the explicit scripts and recorded in the handoff. There is no practical headless automated test for a global keyboard hook or live audio capture.

*Next: Phase 4 (`2026-06-22-windows-port-04-ui.md`) — WPF UI + `VoiceCoordinator` wiring these platform services together.*
