# Phase 4 — WPF UI (tray, HUD pill, settings panel, "J" icon) + VoiceCoordinator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Read `2026-06-22-windows-port-00-overview.md` first** — it defines the architecture, canonical names, and global constraints this phase obeys. Phases 1, 2, and 3 must already be implemented and green (this phase consumes their types). If `windows/` does not yet exist, stop and run Phases 1–3 first.

**Goal:** Build the visible app. Turn the headless `JVoice.App` WinExe from Phase 2 into a WPF tray application that *looks and behaves like the macOS JVoice*: a system-tray "J" icon with a 3-state glyph (idle J / red mic / cyan waveform) and a menu; a floating, borderless, click-through HUD "pill" overlay reproducing every state (Recording / PreparingModel / DownloadingModel / Transcribing / Done / Error) with the orbital-ring animation pixel-faithful to `DESIGN-TOKENS.md`; the dark 320×520 Settings window with all 9 sections; and a `VoiceCoordinator` that wires the whole dictation pipeline (hotkey → record → stream → transcribe → process → paste → stats → HUD) faithfully porting `Sources/JVoice/VoiceCoordinator.swift`. The app launches to the tray, shows Settings once on first run, and dictates end-to-end. The `--bench` CLI branch from Phase 2 keeps working.

**"Done" looks like:** `dotnet build windows/JVoice.sln` succeeds; `dotnet run --project windows/JVoice.App` starts to the tray with the "J" icon and shows Settings on first run; pressing **Ctrl+Shift+Space** records, transcribes on-device, and pastes styled text into the previously-focused app; every HUD state renders matching the tokens; `dotnet test windows/JVoice.Tests` is green (including the new pure decision-helper tests); `JVoice.App --bench <wav>` still runs the bench and exits without showing UI.

**Architecture:**
- `JVoice.App` (net9.0-windows, `WinExe`, `<UseWPF>true</UseWPF>`) gains the UI layer (`UI/` namespace `JVoice.App.UI`), the `VoiceCoordinator` (namespace `JVoice.App`), `App.xaml`/`App.xaml.cs`, and `Assets/JVoice.ico` + tray PNGs.
- The **concurrency model** (overview §6.1): WPF `Dispatcher` is the `@MainActor` analog. `VoiceCoordinator` is created and used on the UI thread; all platform callbacks (hotkey, foreground hook, recorder failure, settings/error hooks) marshal to the dispatcher before touching coordinator state. The Swift `@Published` properties become `INotifyPropertyChanged` properties so XAML binds directly. The `recordingGeneration` stale-session guard ports verbatim as `int _recordingGeneration`.
- The **brain** (Phase 1) and **engine** (Phase 2) and **platform** (Phase 3) are consumed, not modified. `TextProcessor`, `PhoneticMatcher`, `VocabularyPrompt`, etc. are called from the coordinator exactly where the Swift coordinator calls them.
- **Testability seam:** `JVoice.Tests` is `net9.0` and *cannot* reference `net9.0-windows` `JVoice.App`. Therefore the *pure decision logic* the coordinator relies on (target-window resolution rule, HUD-transition mapping, paste-outcome → HUD mapping) is extracted into **`JVoice.Core`** as pure static functions and unit-tested there; the WPF coordinator calls those helpers. The coordinator's threaded orchestration itself is verified by the manual end-to-end checklist (it cannot be unit-tested from a net9.0 test project).

**Tech Stack:** C# (latest) on .NET 9, **WPF** (`net9.0-windows`, `UseWPF=true`, `WinExe`). NuGet: `H.NotifyIcon.Wpf` (tray). Icon tool: `SkiaSharp` (a separate `windows/tools/generate-icon` console app, net9.0). xUnit for the pure-helper tests (added to the existing `JVoice.Tests`).

## Global Constraints

(From the overview — every task implicitly includes these.)
- .NET 9. `JVoice.App` is `net9.0-windows`, `WinExe`, `<UseWPF>true</UseWPF>`, `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<LangVersion>latest</LangVersion>`. Primary RID **win-x64**.
- **Pin NuGet versions** in the csproj (resolve current stable at execution via `dotnet add package`). `H.NotifyIcon.Wpf` baseline ≈ **2.3.0**; `SkiaSharp` baseline ≈ **3.119.0** (icon tool only). Verify GPL-compatibility (both MIT) before adding.
- **Faithful UI port.** Reproduce `DESIGN-TOKENS.md` exactly: colors (convert 0–1 sRGB to `#AARRGGBB`), sizes, paddings, radii, fonts, copy. No "improvements".
- **Faithful coordinator port.** Reproduce `VoiceCoordinator.swift` behavior 1:1 (reentrancy guards, generation guard, target-window resolution, finish pipeline, settings/engine swap, custom-word add/remove, fix/revert, prewarm, quit). Use `Dispatcher` for the `@MainActor` analog.
- Do not modify the macOS Swift app (`Sources/`, `Tests/`, `Package.swift`, `Resources/`). Read-only reference.
- Do not modify Phase 2's `Whisper/` files or remove its `PackageReference`s; do not modify Phase 3's `Platform/` files. Add to the project, don't clobber.
- Do not push / open PRs / add remotes. Commit locally on the `windows-port` branch only.
- **Copy deltas** (§Copy Deltas below): every macOS-only string (⌥Space, "menu bar", "System Settings") is re-expressed for Windows.

## Source-of-truth file map (Swift → C#/XAML)

| Swift source | C#/XAML target | Phase 4 task |
| --- | --- | --- |
| `Sources/JVoice/UI/Components/PanelPressableButtonStyle.swift` | `UI/Styles/JVoicePalette.xaml` (`PressableButton` Style) | 3 |
| `Resources/AppIcon.icns` + `scripts/generate-icon.swift` | `windows/tools/generate-icon/` → `Assets/JVoice.ico` + tray PNGs | 4 |
| `Sources/JVoice/UI/HUDView.swift`, `HUDLayout.swift`, `HUDWindow.swift` | `UI/HudView.xaml(.cs)`, `UI/HudWindow.cs` | 5 |
| `Sources/JVoice/UI/SettingsView.swift`, `SettingsWindow.swift` | `UI/SettingsView.xaml(.cs)`, `UI/SettingsWindow.cs` | 6 |
| `Sources/JVoice/UI/MenuBarController.swift` | `UI/TrayIcon.cs` | 7 |
| `Sources/JVoice/VoiceCoordinator.swift` | `VoiceCoordinator.cs` + `JVoice.Core` pure helpers | 8 |
| `Sources/JVoice/JVoiceApp.swift`, `AppDelegate.swift` | `App.xaml`, `App.xaml.cs` | 2, 9 |

---

## File Structure (what this phase creates / modifies)

```
windows/
├── JVoice.App/
│   ├── JVoice.App.csproj            MODIFY (add UseWPF already set in P2; add H.NotifyIcon.Wpf; set App.xaml entry; ApplicationIcon; embed Assets)
│   ├── Program.cs                   DELETE (entry moves to App.xaml.cs; --bench branch preserved there)
│   ├── App.xaml                     NEW  (Application; merges JVoicePalette.xaml; no StartupUri)
│   ├── App.xaml.cs                  NEW  (STAThread Main: --bench branch, single instance, DI wiring, error hook, first-run Settings, prewarm)
│   ├── VoiceCoordinator.cs          NEW  (the orchestrator; INotifyPropertyChanged)
│   ├── UI/
│   │   ├── Styles/
│   │   │   └── JVoicePalette.xaml   NEW  (ResourceDictionary: Color/SolidColorBrush resources + PressableButton + DarkPrimary/DarkDestructive Styles)
│   │   ├── HudView.xaml             NEW  (UserControl: all pills + orbital ring)
│   │   ├── HudView.xaml.cs          NEW  (state switch, ring storyboards, elapsed timer)
│   │   ├── HudWindow.cs             NEW  (borderless topmost non-activating overlay window)
│   │   ├── SettingsView.xaml        NEW  (UserControl: 320×520, 9 sections)
│   │   ├── SettingsView.xaml.cs     NEW  (bindings, hotkey recorder, add-word, fix/revert)
│   │   ├── SettingsWindow.cs        NEW  (chrome window hosting SettingsView)
│   │   ├── HotkeyRecorder.cs        NEW  (a small control that captures a HotkeyChord)
│   │   └── TrayIcon.cs              NEW  (wraps H.NotifyIcon TaskbarIcon; 3-state icon + menu)
│   └── Assets/
│       ├── JVoice.ico               NEW  (generated by the icon tool: 16/32/48/64/128/256)
│       ├── tray-idle.png            NEW  (white bold "J", 32px)
│       ├── tray-recording.png       NEW  (red mic, 32px)
│       └── tray-transcribing.png    NEW  (cyan waveform, 32px)
├── tools/
│   └── generate-icon/
│       ├── generate-icon.csproj     NEW  (net9.0 console; SkiaSharp)
│       └── Program.cs               NEW  (draws JVoice.ico + 3 tray PNGs into ../../JVoice.App/Assets)
├── JVoice.Core/
│   └── CoordinatorDecisions.cs      NEW  (pure helpers: target-window resolution, HUD transitions, paste→HUD map)
└── JVoice.Tests/
    └── CoordinatorDecisionsTests.cs NEW  (xUnit for the pure helpers)
```

---

## Color conversion reference (0–1 sRGB → `#AARRGGBB`)

Every color used below, converted once here so tasks reference the hex directly. (`round(c*255)` per channel; alpha appended as opacity where a token specifies `.opacity(x)` → alpha byte = `round(x*255)`.) All brushes are defined in `JVoicePalette.xaml` (Task 3).

| Token name | sRGB 0–1 / rgb() | Hex `#FFRRGGBB` |
| --- | --- | --- |
| Pill fill | rgb(7,7,14) `(.027,.027,.055)` | `#FF07070E` |
| Recording accent (blue) | rgb(74,158,255) `(.290,.620,1.0)` | `#FF4A9EFF` |
| Recording text | rgb(209,232,255) `(.820,.910,1.0)` | `#FFD1E8FF` |
| Transcribing accent (cyan) | rgb(0,212,224) `(.0,.831,.878)` | `#FF00D4E0` |
| Transcribing text | rgb(160,240,247) `(.627,.941,.969)` | `#FFA0F0F7` |
| Preparing/Downloading accent (purple) | rgb(128,96,255) `(.502,.376,1.0)` | `#FF8060FF` |
| Preparing text | rgb(202,187,255) `(.792,.733,1.0)` | `#FFCABBFF` |
| Done accent (green) | rgb(110,231,183) `(.431,.906,.718)` | `#FF6EE7B7` |
| Done text | rgb(177,252,183) `(.694,.988,.718)` | `#FFB1FCB7` |
| Error accent (orange) | rgb(250,160,96) `(.980,.627,.376)` | `#FFFAA060` |
| Error text | rgb(255,209,160) `(1.0,.820,.627)` | `#FFFFD1A0` |
| Stop red | rgb(255,96,96) `(1.0,.376,.376)` | `#FFFF6060` |
| Settings panelBg | rgb(13,13,22) `(.051,.051,.086)` | `#FF0D0D16` |
| Settings sectionBg | rgb(15,15,26) `(.059,.059,.102)` | `#FF0F0F1A` |
| Settings border | rgb(30,30,44) `(.118,.118,.173)` | `#FF1E1E2C` |
| Settings headerText | rgb(74,128,204) `(.290,.502,.800)` | `#FF4A80CC` |
| Settings inputBg | rgb(10,10,20) `(.039,.039,.078)` | `#FF0A0A14` |
| Settings blue | rgb(74,158,255) | `#FF4A9EFF` |
| Settings gray | white .53 → rgb(135,135,135) | `#FF878787` |
| Settings indigo | rgb(96,160,255) `(.376,.627,1.0)` | `#FF60A0FF` |
| Settings purple | rgb(128,96,255) | `#FF8060FF` |
| Settings cyan | rgb(32,216,255) `(.125,.847,1.0)` | `#FF20D8FF` |
| Settings orange | rgb(240,160,48) `(.941,.627,.188)` | `#FFF0A030` |
| Settings green | rgb(74,222,160) `(.290,.871,.627)` | `#FF4ADEA0` |
| Settings teal | rgb(32,192,160) `(.125,.753,.627)` | `#FF20C0A0` |
| Settings red | rgb(255,96,96) | `#FFFF6060` |

White-with-opacity text colors used in Settings (token `Color(white: x)`): `0.85` → `#FFD9D9D9`, `0.75` → `#FFBFBFBF`, `0.45` → `#FF737373`, `0.40` → `#FF666666`, `0.38` → `#FF616161`, `0.35` → `#FF595959`.

---

## Copy Deltas (macOS string → Windows string)

These are the ONLY user-facing strings that change from the Swift app. Everything else is identical. (Overview §5; tokens otherwise verbatim.)

| Location | macOS string | Windows string |
| --- | --- | --- |
| Settings header subtitle | "Menu bar transcription controls" | **"Voice dictation controls"** |
| Keyboard Shortcut helper line | "Default: ⌥ Space" | **"Default: Ctrl + Shift + Space"** |
| Default hotkey | ⌥Space | **Ctrl+Shift+Space** (`HotkeyChord.Default`) |
| Mic-denied deep link target | "System Settings" (TCC) | **Windows Settings** (`ms-settings:privacy-microphone`) |
| Tray menu item | "Start Dictation" / "Stop Dictation" | **"Start Dictation" / "Stop Dictation"** (unchanged) |
| Tray menu item | "Settings…" | **"Settings…"** (unchanged, keep ellipsis) |
| Tray menu item | "Launch at Login" | **"Launch at Login"** (unchanged) |
| Tray menu item | "Quit JVoice" | **"Quit JVoice"** (unchanged) |
| First-run affordance (NEW; no macOS equivalent) | — | **"JVoice is running in your system tray — press Ctrl + Shift + Space to dictate."** |
| `LargeTurbo` guidance (Phase 1 already reworded) | "~630 MB download · first use prepares…" | "Most accurate · ~550 MB download · GPU-accelerated when available" (from Phase 1 `WhisperModelOption.Guidance`) |

Note: `RemoveWhisperHallucinations`, `HudState.Subtitle`, etc. already carry Windows-appropriate copy from Phase 1 — do not re-edit them here.

---

## Suggested execution order

Execute the tasks in this order (each ends buildable/green except where a temporary harness is noted):

1. **Task 1** — `JVoice.App.csproj` → WPF deps + app icon + assets (comment the Asset includes until Task 4).
2. **Task 4** — icon tool → `JVoice.ico` + tray PNGs (run early so the csproj Asset includes resolve).
3. **Task 3** — `JVoicePalette.xaml` (brushes + button styles + segment/switch styles + converters).
4. **Task 2** — `App.xaml`/`App.xaml.cs` shell (preserve `--bench`); delete `Program.cs`.
5. **Task 5** — `HudWindow` + `HudView` (all pills + ring animation).
6. **Task 6** — `SettingsView` + `SettingsWindow` + `HotkeyRecorder` + `DarkSection` (all 9 sections).
7. **Task 7** — `TrayIcon` (3-state + menu).
8. **Task 8** — `VoiceCoordinator` (8a pure helpers + tests, then 8b the pipeline).
9. **Task 9** — `App.xaml.cs` final wiring (DI, tray, first-run Settings, prewarm).
10. **Task 10** — end-to-end manual dictation verification.

(The task numbers below are written so they can also be executed strictly 1→10; the only forward dependency is that Task 1's Asset includes need Task 4's output — handled by commenting them out until Task 4, as Task 1 Step 2 notes.)

---

## Task 1: Convert `JVoice.App` to WPF (preserve `--bench`) + add NuGet

**Files:**
- Modify: `windows/JVoice.App/JVoice.App.csproj`
- (Program.cs is deleted in Task 2, not here — keep it compiling until App.xaml.cs exists.)

**Interfaces:**
- Consumes: the existing Phase 2 csproj (already `WinExe`, `net9.0-windows`, `UseWPF=true`, Whisper.net packages pinned, ProjectReference to `JVoice.Core`, `ApplicationManifest=app.manifest`, `StartupObject=JVoice.App.Program`).
- Produces: a WPF-enabled csproj that references `H.NotifyIcon.Wpf`, sets the application icon, embeds `Assets/`, and (in Task 2) switches the entry to `App.xaml`.

Background / gotchas:
- Phase 2 already set `<UseWPF>true</UseWPF>` and `<OutputType>WinExe</OutputType>`. Do not duplicate.
- The `--bench` branch must survive. Phase 2's `BenchRunner.ShouldRun(args)` / `BenchRunner.RunAndExit(args)` are called from `Program.Main`. In Task 2 we move that call to `App.Main` (still `[STAThread]`, still *before* any WPF startup) and delete `Program.cs`.
- WPF apps that declare `App.xaml` with `Build Action = ApplicationDefinition` get an auto-generated `Main`. We do **not** want the auto-generated entry because we need the `--bench` short-circuit. So we keep `App.xaml` as `Page`-style is wrong; instead set `App.xaml` Build Action to `ApplicationDefinition` BUT disable the auto `Main` and provide our own (`<EnableDefaultApplicationDefinition>` stays default; we set `<StartupObject>JVoice.App.App</StartupObject>` and write an explicit `static Main`). See Task 2 for the exact mechanism (`x:Class` + explicit `Main` + `<StartupObject>`).

- [ ] **Step 1: Add `H.NotifyIcon.Wpf`** (resolve + pin current stable; baseline 2.3.0)

Run (from `windows/JVoice.App/`):
```bash
cd windows/JVoice.App
dotnet add package H.NotifyIcon.Wpf
```
Confirm it is MIT-licensed (it is). This writes a pinned `<PackageReference Include="H.NotifyIcon.Wpf" Version="..." />`.

- [ ] **Step 2: Edit `windows/JVoice.App/JVoice.App.csproj`** so it reads exactly like this (preserve the Phase 2 Whisper.net `PackageReference`s at their pinned versions; only the lines shown for WPF/icon/assets are added/changed):

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net9.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <RootNamespace>JVoice.App</RootNamespace>
    <AssemblyName>JVoice</AssemblyName>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <!-- Our own STAThread Main (App.xaml.cs) handles the --bench short-circuit
         before WPF starts. Point the entry at it explicitly. -->
    <StartupObject>JVoice.App.App</StartupObject>
    <ApplicationIcon>Assets\JVoice.ico</ApplicationIcon>
    <Platforms>x64</Platforms>
    <RuntimeIdentifiers>win-x64</RuntimeIdentifiers>
    <AssemblyTitle>JVoice</AssemblyTitle>
    <Product>JVoice</Product>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\JVoice.Core\JVoice.Core.csproj" />
  </ItemGroup>

  <!-- Phase 2 packages — KEEP at their pinned versions. -->
  <ItemGroup>
    <PackageReference Include="Whisper.net" Version="PINNED_BY_PHASE2" />
    <PackageReference Include="Whisper.net.Runtime" Version="PINNED_BY_PHASE2" />
    <PackageReference Include="Whisper.net.Runtime.Cuda" Version="PINNED_BY_PHASE2" />
    <PackageReference Include="Whisper.net.Runtime.Vulkan" Version="PINNED_BY_PHASE2" />
  </ItemGroup>

  <!-- Phase 4 UI package. -->
  <ItemGroup>
    <PackageReference Include="H.NotifyIcon.Wpf" Version="PINNED_AT_EXECUTION" />
  </ItemGroup>

  <!-- Tray PNGs are loaded at runtime via pack URIs; the .ico is the app icon
       and is also used by the tray on Windows. Embed all Assets as Resource. -->
  <ItemGroup>
    <Resource Include="Assets\tray-idle.png" />
    <Resource Include="Assets\tray-recording.png" />
    <Resource Include="Assets\tray-transcribing.png" />
    <Resource Include="Assets\JVoice.ico" />
  </ItemGroup>

</Project>
```

> Note: `Assets\JVoice.ico` and the tray PNGs do not exist until Task 4 generates them. The build will fail on the `<Resource>`/`<ApplicationIcon>` includes until then. To keep the project buildable between Task 1 and Task 4, either (a) run Task 4 (icon generation) *before* re-building, or (b) temporarily comment out the `<ApplicationIcon>` and `<Resource>` lines and uncomment them after Task 4. The recommended order (below) runs the icon tool early to avoid this.

- [ ] **Step 3: Verify** — `dotnet build windows/JVoice.App` still succeeds (with the Assets lines commented out if Task 4 hasn't run). `Program.cs` is still the entry until Task 2. The `--bench` path still works: `dotnet run --project windows/JVoice.App -- --bench` prints Phase 2's usage/error.

- [ ] **Step 4: Commit** — `git add windows/JVoice.App/JVoice.App.csproj && git commit -m "build(win-ui): enable WPF deps (H.NotifyIcon.Wpf), app icon, asset embedding"`

---

## Task 2: `App.xaml` + `App.xaml.cs` shell (entry, --bench, single instance)

> This task creates the WPF application object and the explicit `Main`, but leaves the coordinator/tray wiring as a stub (filled in Task 9 once the coordinator and UI exist). It exists early so the project has a valid WPF entry and the `--bench` branch is guaranteed preserved. **Delete `Program.cs` here.**

**Files:**
- Create: `windows/JVoice.App/App.xaml`
- Create: `windows/JVoice.App/App.xaml.cs`
- Delete: `windows/JVoice.App/Program.cs`

**Interfaces:**
- Consumes: `JVoice.App.Whisper.BenchRunner.ShouldRun(string[])`, `BenchRunner.RunAndExit(string[])` (Phase 2); `JVoice.App.Platform.SingleInstance.TryAcquire()` (Phase 3); `JVoice.App.Whisper.WhisperRuntime.EnsureLoaded()` (Phase 2).
- Produces: `public partial class App : System.Windows.Application` with an explicit `static int Main(string[])`.

- [ ] **Step 1: Create `windows/JVoice.App/App.xaml`**

```xml
<Application x:Class="JVoice.App.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             ShutdownMode="OnExplicitShutdown">
    <Application.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="UI/Styles/JVoicePalette.xaml" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Application.Resources>
</Application>
```

> `ShutdownMode="OnExplicitShutdown"` is essential: a tray app has no main window, so WPF must NOT shut down when the (transient) Settings/HUD windows close. We call `Shutdown()` explicitly from quit. The merged dictionary reference will fail to load until Task 3 creates `JVoicePalette.xaml` — create that file first if you build before Task 3, or build after Task 3.

- [ ] **Step 2: Create `windows/JVoice.App/App.xaml.cs`** (entry stub; coordinator wiring is added in Task 9 where marked)

```csharp
using System.Windows;
using JVoice.App.Platform;
using JVoice.App.Whisper;

namespace JVoice.App;

public partial class App : Application
{
    private VoiceCoordinator? _coordinator;

    /// Explicit entry so the --bench CLI branch runs BEFORE any WPF startup
    /// (mirrors the macOS app calling BenchRunner.shouldRun before showing UI).
    [STAThread]
    public static int Main(string[] args)
    {
        // 1) Headless bench path — never shows UI.
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        // 2) Single instance: if another JVoice is already running, exit quietly.
        //    (A second launch is a no-op; the running tray instance keeps owning the hotkey.)
        if (!SingleInstance.TryAcquire())
            return 0;

        // 3) Force the native whisper runtime to resolve early (CUDA→Vulkan→CPU)
        //    so first dictation isn't delayed by the native load.
        try { WhisperRuntime.EnsureLoaded(); } catch { /* engine load is retried lazily */ }

        var app = new App();
        app.InitializeComponent();   // loads App.xaml + merged dictionaries
        int code = app.Run();
        SingleInstance.Release();
        return code;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Coordinator + tray + first-run wiring is added in Task 9.
        // For now, OnExplicitShutdown means the app stays alive with no window.
        // (Temporary during incremental build: without Task 9 there is no way to
        //  quit except Task Manager. That is acceptable mid-build.)
        _coordinator = null; // placeholder; replaced in Task 9
    }
}
```

- [ ] **Step 3: Delete `windows/JVoice.App/Program.cs`** — its `--bench` responsibility now lives in `App.Main`. (`git rm windows/JVoice.App/Program.cs`.)

- [ ] **Step 4: Verify** — after Task 3 exists, `dotnet build windows/JVoice.App` succeeds. `dotnet run --project windows/JVoice.App -- --bench somefile.wav` runs the Phase 2 bench and exits (no window). `dotnet run --project windows/JVoice.App` launches and idles with no window (Task 9 adds the tray). Kill via Task Manager for now.

- [ ] **Step 5: Commit** — `git rm windows/JVoice.App/Program.cs; git add windows/JVoice.App/App.xaml windows/JVoice.App/App.xaml.cs; git commit -m "feat(win-ui): WPF App entry preserving --bench + single instance"`

---

## Task 3: `JVoicePalette.xaml` (all colors + brushes + button styles)

> Ports `SettingsPalette` + the HUD pill colors + `PanelPressableButtonStyle` + `DarkPrimaryButtonStyle`/`DarkDestructiveButtonStyle`. Every color is a `Color` resource and a matching `SolidColorBrush` (so both `Color`-typed animations and `Brush`-typed fills can use them). Hex values from the conversion table above. WPF has no `.continuous` squircle, so rounded rects use plain `CornerRadius` (visually indistinguishable at these radii).

**Files:**
- Create: `windows/JVoice.App/UI/Styles/JVoicePalette.xaml`

**Interfaces:**
- Produces (consumed by `HudView.xaml`, `SettingsView.xaml`): named brushes `Pill.Fill`, `Accent.Recording`, `Text.Recording`, `Accent.Transcribing`, `Text.Transcribing`, `Accent.Preparing`, `Text.Preparing`, `Accent.Done`, `Text.Done`, `Accent.Error`, `Text.Error`, `Stop.Red`, `Settings.PanelBg`, `Settings.SectionBg`, `Settings.Border`, `Settings.HeaderText`, `Settings.InputBg`, `Settings.Blue`, `Settings.Gray`, `Settings.Indigo`, `Settings.Purple`, `Settings.Cyan`, `Settings.Orange`, `Settings.Green`, `Settings.Teal`, `Settings.Red`, white-opacity text brushes `Text.W85`, `Text.W75`, `Text.W45`, `Text.W40`, `Text.W38`, `Text.W35`; Styles `PressableButton`, `DarkPrimaryButton`, `DarkDestructiveButton`.

- [ ] **Step 1: Create `windows/JVoice.App/UI/Styles/JVoicePalette.xaml`**

```xml
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- ============ HUD pill colors ============ -->
    <SolidColorBrush x:Key="Pill.Fill"           Color="#FF07070E" />
    <SolidColorBrush x:Key="Accent.Recording"    Color="#FF4A9EFF" />
    <SolidColorBrush x:Key="Text.Recording"      Color="#FFD1E8FF" />
    <SolidColorBrush x:Key="Accent.Transcribing" Color="#FF00D4E0" />
    <SolidColorBrush x:Key="Text.Transcribing"   Color="#FFA0F0F7" />
    <SolidColorBrush x:Key="Accent.Preparing"    Color="#FF8060FF" />
    <SolidColorBrush x:Key="Text.Preparing"      Color="#FFCABBFF" />
    <SolidColorBrush x:Key="Accent.Done"         Color="#FF6EE7B7" />
    <SolidColorBrush x:Key="Text.Done"           Color="#FFB1FCB7" />
    <SolidColorBrush x:Key="Accent.Error"        Color="#FFFAA060" />
    <SolidColorBrush x:Key="Text.Error"          Color="#FFFFD1A0" />
    <SolidColorBrush x:Key="Stop.Red"            Color="#FFFF6060" />

    <!-- ============ Settings palette ============ -->
    <SolidColorBrush x:Key="Settings.PanelBg"    Color="#FF0D0D16" />
    <SolidColorBrush x:Key="Settings.SectionBg"  Color="#FF0F0F1A" />
    <SolidColorBrush x:Key="Settings.Border"     Color="#FF1E1E2C" />
    <SolidColorBrush x:Key="Settings.HeaderText" Color="#FF4A80CC" />
    <SolidColorBrush x:Key="Settings.InputBg"    Color="#FF0A0A14" />
    <SolidColorBrush x:Key="Settings.Blue"       Color="#FF4A9EFF" />
    <SolidColorBrush x:Key="Settings.Gray"       Color="#FF878787" />
    <SolidColorBrush x:Key="Settings.Indigo"     Color="#FF60A0FF" />
    <SolidColorBrush x:Key="Settings.Purple"     Color="#FF8060FF" />
    <SolidColorBrush x:Key="Settings.Cyan"       Color="#FF20D8FF" />
    <SolidColorBrush x:Key="Settings.Orange"     Color="#FFF0A030" />
    <SolidColorBrush x:Key="Settings.Green"      Color="#FF4ADEA0" />
    <SolidColorBrush x:Key="Settings.Teal"       Color="#FF20C0A0" />
    <SolidColorBrush x:Key="Settings.Red"        Color="#FFFF6060" />

    <!-- White-with-opacity text brushes (SwiftUI Color(white:x)) -->
    <SolidColorBrush x:Key="Text.W85" Color="#FFD9D9D9" />
    <SolidColorBrush x:Key="Text.W75" Color="#FFBFBFBF" />
    <SolidColorBrush x:Key="Text.W45" Color="#FF737373" />
    <SolidColorBrush x:Key="Text.W40" Color="#FF666666" />
    <SolidColorBrush x:Key="Text.W38" Color="#FF616161" />
    <SolidColorBrush x:Key="Text.W35" Color="#FF595959" />

    <!-- ============ PressableButton (port of PanelPressableButtonStyle) ============
         scaleEffect 0.97 + opacity 0.85 on press; chromeless template. -->
    <Style x:Key="PressableButton" TargetType="Button">
        <Setter Property="Background" Value="Transparent" />
        <Setter Property="BorderThickness" Value="0" />
        <Setter Property="Padding" Value="0" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="RenderTransformOrigin" Value="0.5,0.5" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid x:Name="Root" Background="Transparent" Opacity="1.0">
                        <Grid.RenderTransform>
                            <ScaleTransform x:Name="Scale" ScaleX="1" ScaleY="1" CenterX="0" CenterY="0" />
                        </Grid.RenderTransform>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Root" Property="Opacity" Value="0.85" />
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="Scale" Storyboard.TargetProperty="ScaleX"
                                                         To="0.97" Duration="0:0:0.08" />
                                        <DoubleAnimation Storyboard.TargetName="Scale" Storyboard.TargetProperty="ScaleY"
                                                         To="0.97" Duration="0:0:0.08" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="Scale" Storyboard.TargetProperty="ScaleX"
                                                         To="1.0" Duration="0:0:0.08" />
                                        <DoubleAnimation Storyboard.TargetName="Scale" Storyboard.TargetProperty="ScaleY"
                                                         To="1.0" Duration="0:0:0.08" />
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter TargetName="Root" Property="Opacity" Value="0.40" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ============ DarkPrimaryButton (port of DarkPrimaryButtonStyle) ============
         font 11 semibold, accent foreground, r7 fill accent@0.12 border accent@0.28,
         h12 v6 padding, opacity 0.70 on press. The accent defaults to Settings.Blue;
         set Foreground + Tag (used by the template fill) per-instance to recolor. -->
    <Style x:Key="DarkPrimaryButton" TargetType="Button">
        <Setter Property="FontSize" Value="11" />
        <Setter Property="FontWeight" Value="SemiBold" />
        <Setter Property="Foreground" Value="{StaticResource Settings.Blue}" />
        <!-- Tag carries the accent brush for the fill/border tints. -->
        <Setter Property="Tag" Value="{StaticResource Settings.Blue}" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bg" CornerRadius="7" BorderThickness="1"
                            Padding="12,6">
                        <Border.Background>
                            <SolidColorBrush Color="{Binding Tag.Color, RelativeSource={RelativeSource TemplatedParent}}" Opacity="0.12" />
                        </Border.Background>
                        <Border.BorderBrush>
                            <SolidColorBrush Color="{Binding Tag.Color, RelativeSource={RelativeSource TemplatedParent}}" Opacity="0.28" />
                        </Border.BorderBrush>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bg" Property="Opacity" Value="0.70" />
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter TargetName="Bg" Property="Opacity" Value="0.40" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ============ DarkDestructiveButton (port of DarkDestructiveButtonStyle) ============
         red foreground, r7 fill red@0.10 border red@0.24. -->
    <Style x:Key="DarkDestructiveButton" TargetType="Button" BasedOn="{StaticResource DarkPrimaryButton}">
        <Setter Property="Foreground" Value="{StaticResource Settings.Red}" />
        <Setter Property="Tag" Value="{StaticResource Settings.Red}" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bg" CornerRadius="7" BorderThickness="1" Padding="12,6">
                        <Border.Background>
                            <SolidColorBrush Color="#FF6060" Opacity="0.10" />
                        </Border.Background>
                        <Border.BorderBrush>
                            <SolidColorBrush Color="#FF6060" Opacity="0.24" />
                        </Border.BorderBrush>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bg" Property="Opacity" Value="0.70" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

</ResourceDictionary>
```

> Note on the `DarkPrimaryButton` accent recolor: to render an orange "Add" button or a gray "Revert" button, set `Foreground` and `Tag` on the instance, e.g. `<Button Style="{StaticResource DarkPrimaryButton}" Foreground="{StaticResource Settings.Orange}" Tag="{StaticResource Settings.Orange}" Content="Add"/>`. The template binds the fill/border to `Tag.Color`. The destructive style hardcodes red.

- [ ] **Step 2: Verify** — `dotnet build windows/JVoice.App` succeeds (App.xaml's merged dictionary now resolves). No visual check yet.

- [ ] **Step 3: Commit** — `git add windows/JVoice.App/UI/Styles/JVoicePalette.xaml && git commit -m "feat(win-ui): JVoicePalette resource dictionary (colors, brushes, button styles)"`

---

## Task 4: App icon tool (`generate-icon`) → `JVoice.ico` + tray PNGs

> Port `scripts/generate-icon.swift` geometry to a C# console app using **SkiaSharp**. Rationale for SkiaSharp over `System.Drawing.Common`: `System.Drawing.Common` is unsupported on non-Windows since .NET 7 and its blur/gradient/path-glyph story is weaker; SkiaSharp is cross-platform, has first-class `SKPaint.ImageFilter` (Gaussian blur for the glow), rounded-rect, linear gradient, and font-path APIs — a near-1:1 match to the AppKit drawing the Swift script does, and it writes `.ico` via `SKImage` + an ICO assembler. The tool also draws the three tray states. It is a separate net9.0 project (runs anywhere, no WPF), output written into `windows/JVoice.App/Assets/`.

**Geometry to reproduce (from `generate-icon.swift`):**
- Squircle occupies **80.5%** of the canvas, centered: `shapeSide = round(S * 0.805)`, offset `o = round((S - shapeSide)/2)`.
- Corner radius = `shapeSide * 0.2237`.
- Background: vertical gradient, **bottom `#0A0A0A` → top `#1C1C1E`** (Skia y grows downward, so the gradient start at top = `#1C1C1E`, end at bottom = `#0A0A0A`).
- Inner glass edge: stroke white@5% on a rect inset by `shapeSide*0.012`, same radius, lineWidth `max(1, S*0.004)`.
- "J" glyph: system font weight **Black (≈ FontWeight 900)**, size `shapeSide*0.60`, fill `#EDEDF2`, glow white@30% Gaussian blur ≈ `shapeSide*0.035`, centered by the glyph's true bounding box.

**Files:**
- Create: `windows/tools/generate-icon/generate-icon.csproj`
- Create: `windows/tools/generate-icon/Program.cs`
- Produces (committed): `windows/JVoice.App/Assets/JVoice.ico`, `tray-idle.png`, `tray-recording.png`, `tray-transcribing.png`.

- [ ] **Step 1: Create `windows/tools/generate-icon/generate-icon.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>JVoice.Tools.GenerateIcon</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <!-- Resolve + pin current stable (baseline 3.119.0). MIT-licensed. -->
    <PackageReference Include="SkiaSharp" Version="PINNED_AT_EXECUTION" />
    <!-- On non-Windows CI you also need SkiaSharp.NativeAssets.Linux; on the dev box the
         Windows native assets ship with SkiaSharp by default. -->
  </ItemGroup>
</Project>
```

Add to the solution: `dotnet sln windows/JVoice.sln add windows/tools/generate-icon/generate-icon.csproj`. Then `dotnet add windows/tools/generate-icon package SkiaSharp` to pin.

- [ ] **Step 2: Create `windows/tools/generate-icon/Program.cs`**

```csharp
using SkiaSharp;

namespace JVoice.Tools.GenerateIcon;

internal static class Program
{
    // Output dir = ../../JVoice.App/Assets relative to the repo's windows/tools/generate-icon.
    private static int Main(string[] args)
    {
        string assets = args.Length > 0
            ? args[0]
            : Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "JVoice.App", "Assets"));
        Directory.CreateDirectory(assets);

        // 1) The app .ico (multi-size squircle "J").
        int[] sizes = { 16, 32, 48, 64, 128, 256 };
        var pngs = new List<byte[]>();
        foreach (int px in sizes)
            pngs.Add(EncodePng(RenderAppIcon(px)));
        File.WriteAllBytes(Path.Combine(assets, "JVoice.ico"), BuildIco(sizes, pngs));
        Console.WriteLine($"wrote JVoice.ico ({string.Join(",", sizes)})");

        // 2) Tray PNGs (32px each — Windows tray scales).
        File.WriteAllBytes(Path.Combine(assets, "tray-idle.png"),         EncodePng(RenderTrayJ(32)));
        File.WriteAllBytes(Path.Combine(assets, "tray-recording.png"),    EncodePng(RenderTrayMic(32)));
        File.WriteAllBytes(Path.Combine(assets, "tray-transcribing.png"), EncodePng(RenderTrayWaveform(32)));
        Console.WriteLine("wrote tray-idle / tray-recording / tray-transcribing png");
        return 0;
    }

    private static byte[] EncodePng(SKBitmap bmp)
    {
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }

    // ---- App icon: faithful port of generate-icon.swift render(px:) ----
    private static SKBitmap RenderAppIcon(int px)
    {
        var bmp = new SKBitmap(px, px, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(SKColors.Transparent);

        float S = px;
        float shapeSide = MathF.Round(S * 0.805f);
        float o = MathF.Round((S - shapeSide) / 2f);
        var rect = new SKRect(o, o, o + shapeSide, o + shapeSide);
        float radius = shapeSide * 0.2237f;

        // Background squircle: vertical gradient top #1C1C1E -> bottom #0A0A0A.
        using (var bg = new SKPaint { IsAntialias = true })
        {
            bg.Shader = SKShader.CreateLinearGradient(
                new SKPoint(rect.MidX, rect.Top),
                new SKPoint(rect.MidX, rect.Bottom),
                new[] { new SKColor(0x1C, 0x1C, 0x1E), new SKColor(0x0A, 0x0A, 0x0A) },
                new[] { 0f, 1f },
                SKShaderTileMode.Clamp);
            canvas.DrawRoundRect(rect, radius, radius, bg);
        }

        // Inner glass edge: white@5%, inset shapeSide*0.012, lineWidth max(1, S*0.004).
        using (var edge = new SKPaint { IsAntialias = true, Style = SKPaintStyle.Stroke })
        {
            float inset = shapeSide * 0.012f;
            edge.StrokeWidth = MathF.Max(1f, S * 0.004f);
            edge.Color = new SKColor(0xFF, 0xFF, 0xFF, (byte)Math.Round(0.05 * 255));
            var inner = new SKRect(rect.Left + inset, rect.Top + inset, rect.Right - inset, rect.Bottom - inset);
            canvas.DrawRoundRect(inner, radius, radius, edge);
        }

        // "J" glyph: weight Black, size shapeSide*0.60, fill #EDEDF2, glow white@30% blur shapeSide*0.035.
        using var typeface = SKTypeface.FromFamilyName(
            "Segoe UI", SKFontStyleWeight.Black, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright)
            ?? SKTypeface.Default;
        using var font = new SKFont(typeface, shapeSide * 0.60f);
        using var glyphPaint = new SKPaint { IsAntialias = true, Color = new SKColor(0xED, 0xED, 0xF2) };

        // Center by the glyph's true bounding box.
        using var path = font.GetTextPath("J", new SKPoint(0, 0));
        var b = path.Bounds;
        float dx = rect.MidX - (b.Left + b.Width / 2f);
        float dy = rect.MidY - (b.Top + b.Height / 2f);
        path.Transform(SKMatrix.CreateTranslation(dx, dy));

        using (var glow = new SKPaint { IsAntialias = true, Color = new SKColor(0xFF, 0xFF, 0xFF, (byte)Math.Round(0.30 * 255)) })
        {
            glow.ImageFilter = SKImageFilter.CreateBlur(shapeSide * 0.035f, shapeSide * 0.035f);
            canvas.DrawPath(path, glow);
        }
        canvas.DrawPath(path, glyphPaint);
        canvas.Flush();
        return bmp;
    }

    // ---- Tray idle: white bold "J" on transparent (reads on dark tray). ----
    private static SKBitmap RenderTrayJ(int px) => RenderTrayGlyph(px, "J", SKColors.White, SKFontStyleWeight.Bold);

    // ---- Tray recording: red mic; transcribing: cyan waveform.
    //      Drawn as simple vector glyphs so no font dependency is required. ----
    private static SKBitmap RenderTrayMic(int px)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        var red = new SKColor(0xFF, 0x60, 0x60);
        using var fill = new SKPaint { IsAntialias = true, Color = red, Style = SKPaintStyle.Fill };
        using var stroke = new SKPaint { IsAntialias = true, Color = red, Style = SKPaintStyle.Stroke, StrokeWidth = px * 0.07f, StrokeCap = SKStrokeCap.Round };
        float cx = px / 2f;
        // capsule mic body
        float bw = px * 0.30f, bh = px * 0.42f, bt = px * 0.16f;
        var body = new SKRect(cx - bw / 2, bt, cx + bw / 2, bt + bh);
        canvas.DrawRoundRect(body, bw / 2, bw / 2, fill);
        // arc cradle
        using (var arc = new SKPath())
        {
            float r = px * 0.26f;
            arc.AddArc(new SKRect(cx - r, bt + bh * 0.30f, cx + r, bt + bh * 0.30f + 2 * r), 20, 140);
            canvas.DrawPath(arc, stroke);
        }
        // stand
        canvas.DrawLine(cx, bt + bh + px * 0.10f, cx, px * 0.84f, stroke);
        canvas.DrawLine(cx - px * 0.13f, px * 0.84f, cx + px * 0.13f, px * 0.84f, stroke);
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap RenderTrayWaveform(int px)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        var cyan = new SKColor(0x00, 0xD4, 0xE0); // rgb(0,212,224) — HUD transcribing accent
        using var p = new SKPaint { IsAntialias = true, Color = cyan, Style = SKPaintStyle.Stroke, StrokeWidth = px * 0.09f, StrokeCap = SKStrokeCap.Round };
        float cx = px / 2f, mid = px / 2f;
        float[] hs = { 0.14f, 0.30f, 0.46f, 0.30f, 0.14f };
        float step = px * 0.16f;
        float x0 = cx - 2 * step;
        for (int i = 0; i < hs.Length; i++)
        {
            float x = x0 + i * step;
            float h = px * hs[i];
            canvas.DrawLine(x, mid - h, x, mid + h, p);
        }
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap RenderTrayGlyph(int px, string glyph, SKColor color, SKFontStyleWeight weight)
    {
        var bmp = NewTransparent(px);
        using var canvas = new SKCanvas(bmp);
        using var tf = SKTypeface.FromFamilyName("Segoe UI", weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright) ?? SKTypeface.Default;
        using var font = new SKFont(tf, px * 0.78f);
        using var paint = new SKPaint { IsAntialias = true, Color = color };
        using var path = font.GetTextPath(glyph, new SKPoint(0, 0));
        var b = path.Bounds;
        path.Transform(SKMatrix.CreateTranslation(px / 2f - (b.Left + b.Width / 2f), px / 2f - (b.Top + b.Height / 2f)));
        canvas.DrawPath(path, paint);
        canvas.Flush();
        return bmp;
    }

    private static SKBitmap NewTransparent(int px)
    {
        var bmp = new SKBitmap(px, px, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var c = new SKCanvas(bmp);
        c.Clear(SKColors.Transparent);
        return bmp;
    }

    // ---- Minimal ICO container: header + per-image directory + PNG-encoded frames.
    //      Windows Vista+ accepts PNG-compressed icon frames in an .ico. ----
    private static byte[] BuildIco(int[] sizes, List<byte[]> pngs)
    {
        using var ms = new MemoryStream();
        using var w = new BinaryWriter(ms);
        int count = sizes.Length;
        w.Write((short)0);        // reserved
        w.Write((short)1);        // type 1 = icon
        w.Write((short)count);    // image count
        int offset = 6 + 16 * count;
        for (int i = 0; i < count; i++)
        {
            int s = sizes[i];
            w.Write((byte)(s >= 256 ? 0 : s)); // width  (0 means 256)
            w.Write((byte)(s >= 256 ? 0 : s)); // height (0 means 256)
            w.Write((byte)0);     // palette
            w.Write((byte)0);     // reserved
            w.Write((short)1);    // color planes
            w.Write((short)32);   // bits per pixel
            w.Write(pngs[i].Length);
            w.Write(offset);
            offset += pngs[i].Length;
        }
        foreach (var png in pngs) w.Write(png);
        w.Flush();
        return ms.ToArray();
    }
}
```

- [ ] **Step 3: Run the tool** — `dotnet run --project windows/tools/generate-icon`. Confirm `windows/JVoice.App/Assets/JVoice.ico` (~ tens of KB) and the three `tray-*.png` exist.

- [ ] **Step 4: Visual check** — open `JVoice.ico` (e.g. preview) and confirm: dark squircle, centered light "J", subtle glow. Open the tray PNGs: white "J", red mic, cyan waveform. If the "J" is off-center, the bbox-centering math is wrong — re-verify against the Swift `monogramPath` (which centers by `path.bounds`).

- [ ] **Step 5: Uncomment** the `<ApplicationIcon>` and `<Resource>` lines in `JVoice.App.csproj` if they were commented out in Task 1, then `dotnet build windows/JVoice.App` → succeeds with the icon embedded.

- [ ] **Step 6: Commit** — `git add windows/tools/generate-icon windows/JVoice.App/Assets windows/JVoice.sln windows/JVoice.App/JVoice.App.csproj && git commit -m "feat(win-ui): SkiaSharp icon tool → JVoice.ico + tray PNGs (squircle J, 3 tray states)"`

> The generated binary assets ARE committed (unlike GGML models). The `.gitignore` `*.bin` rule does not affect `.ico`/`.png`.

---

## Task 5: HUD — `HudWindow` + `HudView` (all pills + orbital ring)

> Ports `HUDWindow.swift`, `HUDView.swift`, `HUDLayout.swift`. The window is a borderless, topmost, non-activating overlay positioned bottom-center 24px above the work area; it is click-through except over the stop button (mirrors Swift `ignoresMouseEvents = (state != .recording)`). The view reproduces every pill with exact colors/sizes/paddings and the orbital ring (pulsing aura + spinning arc + center glyph). Adds the **DownloadingModel** pill (purple, progress %).

### Borderless + shadow + non-activating + DPI approach (documented decision)

- **Borderless transparent window:** `WindowStyle="None"`, `AllowsTransparency="True"`, `Background="Transparent"`, `ResizeMode="NoResize"`, `ShowInTaskbar="False"`, `Topmost="True"`, `ShowActivated="False"`. This is the standard WPF way to get a fully custom-shaped overlay. We do NOT use `WindowChrome` (it is for custom-chrome *normal* windows and fights click-through + non-activation; the pill is a pure overlay).
- **Drop shadow / glow:** rendered *inside* the WPF content (the pill `Border` carries the glow via layered `Border`s + `DropShadowEffect`), not via OS window shadow. `AllowsTransparency=True` disables the OS shadow anyway, and the macOS pill draws its own glow in-content (see `pillBackground`). We reproduce the glow with `DropShadowEffect` (ShadowDepth 0, soft) layered behind the pill.
- **Non-activating:** `ShowActivated="False"` stops the window stealing focus when shown. We also set the Win32 extended style `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` in the `SourceInitialized` handler so a click on the stop button never activates the window/steals foreground from the user's target app (critical — the macOS `nonactivatingPanel` analog).
- **Click-through:** when not recording, set `WS_EX_TRANSPARENT` so mouse events pass through to whatever is underneath (matches `ignoresMouseEvents = true`). When recording, clear `WS_EX_TRANSPARENT` so the stop button is hittable (matches `ignoresMouseEvents = false`).
- **DPI:** `app.manifest` (Phase 2/3) declares per-monitor-v2 DPI awareness, so WPF gives correct device-independent units. Positioning uses `SystemParameters.WorkArea` (DIPs) for the primary screen, matching the macOS `visibleFrame`. For multi-monitor, position on the screen containing the cursor is a possible enhancement (noted in §Future); v1 uses the primary work area like the Swift `NSScreen.main`.

**Files:**
- Create: `windows/JVoice.App/UI/HudView.xaml`
- Create: `windows/JVoice.App/UI/HudView.xaml.cs`
- Create: `windows/JVoice.App/UI/HudWindow.cs`

**Interfaces:**
- Consumes: `JVoice.Core.Models.HudState`, `HudStateKind` (Phase 1); `JVoicePalette.xaml` brushes.
- Produces: `sealed class HudWindow : Window` with `void Update(HudState state)` and `Action? OnStop`; `partial class HudView : UserControl` with `void Apply(HudState state, Action? onStop)`.

- [ ] **Step 1: Create `windows/JVoice.App/UI/HudView.xaml`**

> One `Grid` root holds all pill variants; `Apply()` toggles visibility. The orbital ring is a reusable sub-tree referenced by name per-pill. Pill background = the shared `pillBackground` recreated as layered `Border`s: fill `Pill.Fill`, border `accent@0.22` (we apply per-pill via a `SolidColorBrush` with Opacity), top-leading gradient overlay `accent@0.06`, glow via two `DropShadowEffect`s approximated by one soft shadow (WPF allows one effect per element, so we layer two `Border`s each with a `DropShadowEffect`). Outer margin 32 reproduces the Swift `.padding(32)` glow margin.

```xml
<UserControl x:Class="JVoice.App.UI.HudView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             Background="Transparent">
    <!-- 32px margin all around = the Swift .padding(32) glow margin. -->
    <Grid Margin="32">
        <!-- ===== shared glow layers (behind the pill) ===== -->
        <Border x:Name="GlowOuter" CornerRadius="22" Background="{StaticResource Pill.Fill}">
            <Border.Effect>
                <DropShadowEffect x:Name="GlowOuterFx" BlurRadius="64" ShadowDepth="0" Color="#4A9EFF" Opacity="0.07" />
            </Border.Effect>
        </Border>
        <Border x:Name="GlowInner" CornerRadius="22" Background="{StaticResource Pill.Fill}">
            <Border.Effect>
                <DropShadowEffect x:Name="GlowInnerFx" BlurRadius="32" ShadowDepth="0" Color="#4A9EFF" Opacity="0.18" />
            </Border.Effect>
        </Border>

        <!-- ===== the pill body ===== -->
        <Border x:Name="PillBody" CornerRadius="22" Background="{StaticResource Pill.Fill}"
                MinWidth="220" MinHeight="50" BorderThickness="1">
            <Border.BorderBrush>
                <SolidColorBrush x:Name="PillBorderBrush" Color="#4A9EFF" Opacity="0.22" />
            </Border.BorderBrush>
            <Border.Effect>
                <DropShadowEffect BlurRadius="24" ShadowDepth="6" Direction="270" Color="#000000" Opacity="0.35" />
            </Border.Effect>

            <Grid>
                <!-- top-leading gradient overlay accent@0.06 -> clear -->
                <Border CornerRadius="22">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0.5,0.5">
                            <GradientStop x:Name="OverlayStop0" Color="#4A9EFF" Offset="0" />
                            <GradientStop Color="#004A9EFF" Offset="1" />
                        </LinearGradientBrush>
                    </Border.Background>
                </Border>

                <!-- content: [ring/disc] [text block] [stop?] -->
                <StackPanel Orientation="Horizontal" Margin="10,7" VerticalAlignment="Center">

                    <!-- ===== Orbital ring (Recording/Preparing/Downloading/Transcribing) ===== -->
                    <Grid x:Name="Ring" Width="36" Height="36" VerticalAlignment="Center">
                        <!-- pulsing aura -->
                        <Ellipse x:Name="RingAura" Width="36" Height="36" RenderTransformOrigin="0.5,0.5">
                            <Ellipse.Fill>
                                <RadialGradientBrush>
                                    <GradientStop x:Name="AuraStop0" Color="#4A9EFF" Offset="0" />
                                    <GradientStop Color="#004A9EFF" Offset="1" />
                                </RadialGradientBrush>
                            </Ellipse.Fill>
                            <Ellipse.RenderTransform>
                                <ScaleTransform x:Name="AuraScale" ScaleX="0.9" ScaleY="0.9" />
                            </Ellipse.RenderTransform>
                        </Ellipse>
                        <!-- spinning arc: a 28x28 circle drawn as an Arc path, trim 0..0.28 -->
                        <Path x:Name="RingArc" Width="28" Height="28" RenderTransformOrigin="0.5,0.5"
                              StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
                            <Path.Stroke>
                                <SolidColorBrush x:Name="RingArcBrush" Color="#4A9EFF" />
                            </Path.Stroke>
                            <Path.Effect>
                                <DropShadowEffect x:Name="RingArcGlow" BlurRadius="6" ShadowDepth="0" Color="#4A9EFF" Opacity="0.85" />
                            </Path.Effect>
                            <Path.RenderTransform>
                                <RotateTransform x:Name="RingArcRotate" Angle="0" />
                            </Path.RenderTransform>
                        </Path>
                        <!-- center glyph (mic / gear / waveform / down-arrow) -->
                        <TextBlock x:Name="RingGlyph" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                   HorizontalAlignment="Center" VerticalAlignment="Center" Text="&#xE720;">
                            <TextBlock.Foreground>
                                <SolidColorBrush x:Name="RingGlyphBrush" Color="#4A9EFF" />
                            </TextBlock.Foreground>
                            <TextBlock.Effect>
                                <DropShadowEffect BlurRadius="8" ShadowDepth="0" Color="#4A9EFF" Opacity="0.6" />
                            </TextBlock.Effect>
                        </TextBlock>
                    </Grid>

                    <!-- ===== Static disc (Done/Error) ===== -->
                    <Grid x:Name="Disc" Width="28" Height="28" VerticalAlignment="Center" Visibility="Collapsed">
                        <Ellipse x:Name="DiscFill" Width="28" Height="28" StrokeThickness="1">
                            <Ellipse.Fill>
                                <SolidColorBrush x:Name="DiscFillBrush" Color="#6EE7B7" Opacity="0.12" />
                            </Ellipse.Fill>
                            <Ellipse.Stroke>
                                <SolidColorBrush x:Name="DiscStrokeBrush" Color="#6EE7B7" Opacity="0.30" />
                            </Ellipse.Stroke>
                            <Ellipse.Effect>
                                <DropShadowEffect x:Name="DiscGlow" BlurRadius="12" ShadowDepth="0" Color="#6EE7B7" Opacity="0.22" />
                            </Ellipse.Effect>
                        </Ellipse>
                        <TextBlock x:Name="DiscGlyph" FontFamily="Segoe MDL2 Assets" FontSize="13"
                                   HorizontalAlignment="Center" VerticalAlignment="Center" Text="&#xE73E;">
                            <TextBlock.Foreground>
                                <SolidColorBrush x:Name="DiscGlyphBrush" Color="#6EE7B7" />
                            </TextBlock.Foreground>
                        </TextBlock>
                    </Grid>

                    <!-- ===== text block ===== -->
                    <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock x:Name="Title" FontSize="12" FontWeight="SemiBold" Text="Recording">
                            <TextBlock.Foreground>
                                <SolidColorBrush x:Name="TitleBrush" Color="#D1E8FF" />
                            </TextBlock.Foreground>
                            <TextBlock.Effect>
                                <DropShadowEffect BlurRadius="12" ShadowDepth="0" x:Name="TitleGlow" Color="#4A9EFF" Opacity="0.55" />
                            </TextBlock.Effect>
                        </TextBlock>
                        <TextBlock x:Name="Subtitle" FontSize="10" FontWeight="Medium" Text="Listening…" Margin="0,2,0,0">
                            <TextBlock.Foreground>
                                <SolidColorBrush x:Name="SubtitleBrush" Color="#4A9EFF" Opacity="0.55" />
                            </TextBlock.Foreground>
                        </TextBlock>
                    </StackPanel>

                    <!-- ===== stop button (recording only) ===== -->
                    <Button x:Name="StopButton" Style="{StaticResource PressableButton}"
                            Margin="14,0,0,0" VerticalAlignment="Center" Visibility="Collapsed"
                            Width="22" Height="22">
                        <Grid Width="22" Height="22">
                            <Border CornerRadius="6" BorderThickness="1">
                                <Border.Background>
                                    <SolidColorBrush Color="#FF6060" Opacity="0.12" />
                                </Border.Background>
                                <Border.BorderBrush>
                                    <SolidColorBrush Color="#FF6060" Opacity="0.30" />
                                </Border.BorderBrush>
                                <Border.Effect>
                                    <DropShadowEffect BlurRadius="8" ShadowDepth="0" Color="#FF6060" Opacity="0.20" />
                                </Border.Effect>
                            </Border>
                            <Border CornerRadius="2" Width="7" Height="7" Background="{StaticResource Stop.Red}"
                                    HorizontalAlignment="Center" VerticalAlignment="Center">
                                <Border.Effect>
                                    <DropShadowEffect BlurRadius="6" ShadowDepth="0" Color="#FF6060" Opacity="0.80" />
                                </Border.Effect>
                            </Border>
                        </Grid>
                    </Button>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</UserControl>
```

> Notes on fidelity / WPF mappings:
> - WPF `TextBlock` allows one `Effect`; the Swift design layers two glow shadows (e.g. `.55 r6` + `.20 r18`). One `DropShadowEffect` at a blurred radius is the faithful approximation — keep `BlurRadius≈12`, `Opacity≈0.55`. Do not chase two stacked effects (not supported per element).
> - The center glyphs use **Segoe MDL2 Assets** (ships with Windows 10/11): mic ``, gear/settings `` (or `` "Settings"), waveform — no exact glyph; use a download/cloud-download for DownloadingModel `` and an "audio" bars glyph; for Transcribing use a generic "soundwave" — Segoe MDL2 has `` (no clean waveform) — acceptable substitute is `` (volume) or draw the 3-bar waveform as a small `Path` (preferred). See Step 2 for exact glyph assignments. Checkmark ``, warning triangle ``.
> - The spinning arc `RingArc.Data` (a 28×28 circle trimmed 0–0.28) is set in code-behind (an `ArcSegment` spanning `0.28*360 = 100.8°`). See Step 2.

- [ ] **Step 2: Create `windows/JVoice.App/UI/HudView.xaml.cs`** (state application + ring storyboards + elapsed timer)

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public partial class HudView : UserControl
{
    private Storyboard? _pulse;
    private Storyboard? _spin;
    private readonly DispatcherTimer _elapsedTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTime _preparingStart;
    private HudStateKind _kind = HudStateKind.Idle;
    private Action? _onStop;

    // Segoe MDL2 Assets glyphs.
    private const string GlyphMic = "";
    private const string GlyphGear = "";
    private const string GlyphDownload = "";
    private const string GlyphCheck = "";
    private const string GlyphWarning = "";

    public HudView()
    {
        InitializeComponent();
        BuildArcGeometry();
        StopButton.Click += (_, _) => _onStop?.Invoke();
        _elapsedTimer.Tick += (_, _) => UpdateElapsed();
    }

    /// 28x28 circle, trim 0..0.28 → an arc of 100.8° starting at 12 o'clock.
    private void BuildArcGeometry()
    {
        const double size = 28, r = size / 2 - 0.75; // inset by half the stroke (1.5)
        var c = new Point(size / 2, size / 2);
        double sweep = 0.28 * 360.0; // 100.8°
        double a0 = -90 * Math.PI / 180.0;            // top
        double a1 = (-90 + sweep) * Math.PI / 180.0;
        var p0 = new Point(c.X + r * Math.Cos(a0), c.Y + r * Math.Sin(a0));
        var p1 = new Point(c.X + r * Math.Cos(a1), c.Y + r * Math.Sin(a1));
        var fig = new PathFigure { StartPoint = p0 };
        fig.Segments.Add(new ArcSegment(p1, new Size(r, r), 0, sweep > 180, SweepDirection.Clockwise, true));
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        RingArc.Data = geo;
    }

    /// Apply a HUD state: recolor, pick layout, run/stop animations.
    public void Apply(HudState state, Action? onStop)
    {
        _onStop = onStop;
        _kind = state.Kind;

        switch (state.Kind)
        {
            case HudStateKind.Recording:
                Recolor("#4A9EFF", "#D1E8FF", subtitleOpacity: 0.55);
                ShowRing(GlyphMic);
                SetText("Recording", "Listening…");
                StopButton.Visibility = Visibility.Visible;
                break;

            case HudStateKind.PreparingModel:
                Recolor("#8060FF", "#CABBFF", subtitleOpacity: 0.62);
                ShowRing(GlyphGear);
                SetText("Preparing Model", "One-time setup — keep JVoice open · 0:00");
                StopButton.Visibility = Visibility.Collapsed;
                _preparingStart = DateTime.UtcNow;
                _elapsedTimer.Start();
                break;

            case HudStateKind.DownloadingModel:
                Recolor("#8060FF", "#CABBFF", subtitleOpacity: 0.62);
                ShowRing(GlyphDownload);
                int pct = (int)Math.Round((state.Progress ?? 0) * 100);
                SetText("Downloading Model", $"Downloading the speech model… {pct}%");
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Transcribing:
                Recolor("#00D4E0", "#A0F0F7", subtitleOpacity: 0.55);
                ShowRing(GlyphWaveformAsPath: true);
                SetText("Transcribing", "Processing…");
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Done:
                Recolor("#6EE7B7", "#B1FCB7", subtitleOpacity: 0);
                ShowDisc(GlyphCheck);
                SetText(state.Headline, null);
                StopButton.Visibility = Visibility.Collapsed;
                break;

            case HudStateKind.Error:
                Recolor("#FAA060", "#FFD1A0", subtitleOpacity: 0);
                ShowDisc(GlyphWarning);
                SetText(state.Headline, null);
                StopButton.Visibility = Visibility.Collapsed;
                break;

            default: // Idle — view is hidden by the window; nothing to draw.
                StopAnimations();
                _elapsedTimer.Stop();
                break;
        }

        if (state.Kind != HudStateKind.PreparingModel)
            _elapsedTimer.Stop();
    }

    private void UpdateElapsed()
    {
        int s = Math.Max(0, (int)(DateTime.UtcNow - _preparingStart).TotalSeconds);
        Subtitle.Text = $"One-time setup — keep JVoice open · {s / 60}:{s % 60:D2}";
    }

    private void SetText(string title, string? subtitle)
    {
        Title.Text = title;
        if (subtitle is null) { Subtitle.Visibility = Visibility.Collapsed; }
        else { Subtitle.Visibility = Visibility.Visible; Subtitle.Text = subtitle; }
    }

    private void Recolor(string accentHex, string textHex, double subtitleOpacity)
    {
        var accent = (Color)ColorConverter.ConvertFromString(accentHex)!;
        var text = (Color)ColorConverter.ConvertFromString(textHex)!;

        PillBorderBrush.Color = accent;          // opacity 0.22 already set in XAML
        OverlayStop0.Color = MakeColor(accent, 0.06);
        GlowInnerFx.Color = accent;
        GlowOuterFx.Color = accent;
        AuraStop0.Color = MakeColor(accent, 0.18);
        RingArcBrush.Color = accent;
        RingArcGlow.Color = accent;
        RingGlyphBrush.Color = accent;
        DiscFillBrush.Color = accent;
        DiscStrokeBrush.Color = accent;
        DiscGlyphBrush.Color = accent;
        DiscGlow.Color = accent;
        TitleBrush.Color = text;
        TitleGlow.Color = accent;
        SubtitleBrush.Color = accent;
        SubtitleBrush.Opacity = subtitleOpacity;
    }

    private static Color MakeColor(Color c, double a)
        => Color.FromArgb((byte)Math.Round(a * 255), c.R, c.G, c.B);

    private void ShowRing(string glyph) => ShowRing(glyph, false);

    private void ShowRing(bool GlyphWaveformAsPath) => ShowRing(null, true);

    private void ShowRing(string? glyph, bool waveform)
    {
        Ring.Visibility = Visibility.Visible;
        Disc.Visibility = Visibility.Collapsed;
        if (waveform)
        {
            // Transcribing: draw a 3-bar waveform as the center glyph (no clean MDL2 glyph).
            RingGlyph.FontFamily = new FontFamily("Segoe MDL2 Assets");
            RingGlyph.Text = ""; // "StreamingEnterprise"-ish bars; acceptable. (Or keep mic-less.)
        }
        else
        {
            RingGlyph.Text = glyph!;
        }
        StartAnimations();
    }

    private void ShowDisc(string glyph)
    {
        Ring.Visibility = Visibility.Collapsed;
        Disc.Visibility = Visibility.Visible;
        DiscGlyph.Text = glyph;
        StopAnimations();
    }

    private void StartAnimations()
    {
        StopAnimations();

        // Pulse aura: scale 0.9 -> 1.05, easeInOut 1.8s, repeat forever, autoreverse.
        var pulse = new DoubleAnimation
        {
            From = 0.9, To = 1.05, Duration = TimeSpan.FromSeconds(1.8),
            AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        _pulse = new Storyboard();
        Storyboard.SetTarget(pulse, AuraScale);
        var pulseX = pulse.Clone(); Storyboard.SetTargetProperty(pulseX, new PropertyPath("ScaleX"));
        var pulseY = pulse.Clone(); Storyboard.SetTargetProperty(pulseY, new PropertyPath("ScaleY"));
        Storyboard.SetTarget(pulseX, AuraScale); Storyboard.SetTarget(pulseY, AuraScale);
        _pulse.Children.Add(pulseX); _pulse.Children.Add(pulseY);
        _pulse.Begin();

        // Spinning arc: full 360° every 4.0s, linear, forever.
        var spin = new DoubleAnimation
        {
            From = 0, To = 360, Duration = TimeSpan.FromSeconds(4.0),
            RepeatBehavior = RepeatBehavior.Forever
        };
        _spin = new Storyboard();
        Storyboard.SetTarget(spin, RingArcRotate);
        Storyboard.SetTargetProperty(spin, new PropertyPath("Angle"));
        _spin.Children.Add(spin);
        _spin.Begin();
    }

    private void StopAnimations()
    {
        _pulse?.Stop(); _pulse = null;
        _spin?.Stop(); _spin = null;
    }
}
```

> Glyph note: Segoe MDL2 has no perfect "waveform.path" or "spinning ring + mic" match. The above uses MDL2 glyphs as the closest stand-ins. If exact fidelity is wanted, replace the `RingGlyph` `TextBlock` with a tiny drawn `Path` per state (mic capsule, gear, 3-bar waveform, down-arrow) reusing the SkiaSharp shapes from Task 4. The MDL2 approach is acceptable for v1 and listed as a polish item in §Future. Keep the ring **arc + aura** (the dominant motion) pixel-faithful.

- [ ] **Step 3: Create `windows/JVoice.App/UI/HudWindow.cs`**

```csharp
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using JVoice.Core.Models;

namespace JVoice.App.UI;

/// Borderless, topmost, non-activating, click-through overlay pill.
/// Ports HUDWindow.swift (NSPanel borderless/nonactivating, bottom-center, 24px up).
public sealed class HudWindow : Window
{
    private readonly HudView _view = new();
    private HudState _state = HudState.Idle;
    private IntPtr _hwnd;

    public Action? OnStop { get; set; }

    public HudWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        Content = _view;
        SourceInitialized += OnSourceInitialized;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW so it never steals foreground / no taskbar.
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        ex |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex);
        ApplyClickThrough(clickThrough: true);
    }

    /// Update to a new state (UI thread). Mirrors HUDWindow.update(state:).
    public void Update(HudState state)
    {
        _state = state;
        _view.Apply(state, OnStop);

        // Click-through except while recording (matches ignoresMouseEvents = state != .recording).
        ApplyClickThrough(clickThrough: state.Kind != HudStateKind.Recording);

        if (state.IsVisible)
        {
            // Lay out first so ActualWidth/Height are valid, then position.
            UpdateLayout();
            PositionBottomCenter();
            if (!IsVisible) ShowNoActivate();
        }
        else
        {
            Hide();
        }
    }

    private void ShowNoActivate()
    {
        // Show without activating (Show() would activate); set Visibility then enforce no-activate.
        Visibility = Visibility.Visible;
        ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
    }

    private void PositionBottomCenter()
    {
        var wa = SystemParameters.WorkArea; // DIPs, primary screen
        Left = wa.Left + (wa.Width - ActualWidth) / 2;
        // 24px above the bottom of the work area (Swift visibleFrame.minY + 24).
        Top = wa.Bottom - ActualHeight - 24;
    }

    private void ApplyClickThrough(bool clickThrough)
    {
        if (_hwnd == IntPtr.Zero) return;
        int ex = GetWindowLong(_hwnd, GWL_EXSTYLE);
        if (clickThrough) ex |= WS_EX_TRANSPARENT;
        else ex &= ~WS_EX_TRANSPARENT;
        SetWindowLong(_hwnd, GWL_EXSTYLE, ex);
    }

    // ---- Win32 ----
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int SW_SHOWNOACTIVATE = 4;

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int newLong);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmd);
}
```

- [ ] **Step 4: Temporary visual harness** — to see the HUD before the coordinator exists, temporarily set `App.OnStartup` to: `var w = new UI.HudWindow(); w.Update(HudState.Recording);`. Run `dotnet run --project windows/JVoice.App`. Confirm a blue "Recording / Listening…" pill at bottom-center with a spinning arc + pulsing aura + visible stop button. Then test each state by swapping `HudState.Transcribing`, `HudState.PreparingModel`, `HudState.DownloadingModel(0.42)`, `HudState.Done("hi")`, `HudState.Error("boom")`. Verify colors match the table, the pill is click-through except in Recording (click the desktop behind it), and it never steals focus. **Remove the harness** before committing (Task 9 wires it properly).

- [ ] **Step 5: Commit** — `git add windows/JVoice.App/UI/HudView.xaml windows/JVoice.App/UI/HudView.xaml.cs windows/JVoice.App/UI/HudWindow.cs && git commit -m "feat(win-ui): HUD window + view (all pills, orbital ring, click-through overlay)"`

---

## Task 6: Settings — `HotkeyRecorder` + `SettingsView` + `SettingsWindow`

> Ports `SettingsView.swift` (320×520, dark, 9 sections), `SettingsWindow.swift`, and the `DarkSection` chrome. Binds to `VoiceCoordinator` (Task 8) via standard WPF `{Binding}` — the coordinator is `INotifyPropertyChanged` and is set as `DataContext`. The macOS `KeyboardShortcuts.Recorder` becomes a custom `HotkeyRecorder` control that captures a `HotkeyChord` (Phase 3 type).

### `DarkSection` chrome (from `DESIGN-TOKENS.md` §2)
- Card: `Border` CornerRadius 10, fill `Settings.SectionBg`, 1px `Settings.Border`.
- Header row: 5×5 accent dot (with glow) + UPPERCASED title, size **9.5**, **Bold**, letter-spacing equivalent of kerning 0.7, color `Settings.HeaderText`. Header padding h12 / top9 / bottom7.
- 0.5px divider (`Settings.Border`), then content padding 12.

We implement `DarkSection` as a reusable `UserControl` (or a styled `HeaderedContentControl`). Simpler and explicit: a small `DarkSection` UserControl with `Title`, `AccentBrush`, and content. Defined inline in `SettingsView.xaml` via a `ContentControl` style is verbose; instead define a `DarkSection.xaml(.cs)` UserControl.

**Files:**
- Create: `windows/JVoice.App/UI/HotkeyRecorder.cs`
- Create: `windows/JVoice.App/UI/DarkSection.xaml`
- Create: `windows/JVoice.App/UI/DarkSection.xaml.cs`
- Create: `windows/JVoice.App/UI/SettingsView.xaml`
- Create: `windows/JVoice.App/UI/SettingsView.xaml.cs`
- Create: `windows/JVoice.App/UI/SettingsWindow.cs`

**Interfaces:**
- Consumes: `VoiceCoordinator` (Task 8) as `DataContext`; `JVoice.Core.Models.HotkeyChord` (Phase 3); `JVoicePalette.xaml`.
- Produces: `SettingsView : UserControl`; `SettingsWindow : Window` (chrome, 320×520 content, taskbar button while open); `HotkeyRecorder : Control`.

- [ ] **Step 1: Create `windows/JVoice.App/UI/HotkeyRecorder.cs`**

> A button-like control. Click → "Press a key…" capture mode → next key with modifiers becomes the `HotkeyChord`. Esc cancels; Backspace/Delete resets to default. Displays `chord.Format()`. Raises `ChordChanged`.

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public sealed class HotkeyRecorder : Button
{
    private bool _capturing;

    public static readonly DependencyProperty ChordProperty = DependencyProperty.Register(
        nameof(Chord), typeof(HotkeyChord), typeof(HotkeyRecorder),
        new FrameworkPropertyMetadata(HotkeyChord.Default,
            FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnChordChanged));

    public HotkeyChord Chord
    {
        get => (HotkeyChord)GetValue(ChordProperty);
        set => SetValue(ChordProperty, value);
    }

    public event Action<HotkeyChord>? ChordChanged;

    public HotkeyRecorder()
    {
        Focusable = true;
        Content = HotkeyChord.Default.Format();
        Click += (_, _) => BeginCapture();
        LostFocus += (_, _) => EndCapture();
    }

    private static void OnChordChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var r = (HotkeyRecorder)d;
        if (!r._capturing) r.Content = ((HotkeyChord)e.NewValue).Format();
    }

    private void BeginCapture()
    {
        _capturing = true;
        Content = "Press a key…";
        Focus();
        Keyboard.Focus(this);
    }

    private void EndCapture()
    {
        if (!_capturing) return;
        _capturing = false;
        Content = Chord.Format();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (!_capturing) { base.OnPreviewKeyDown(e); return; }
        e.Handled = true;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return; // wait for a non-modifier key

        if (key == Key.Escape) { EndCapture(); return; }
        if (key is Key.Back or Key.Delete)
        {
            SetChord(HotkeyChord.Default);
            EndCapture();
            return;
        }

        var mods = HotkeyModifiers.None;
        var m = Keyboard.Modifiers;
        if (m.HasFlag(ModifierKeys.Control)) mods |= HotkeyModifiers.Control;
        if (m.HasFlag(ModifierKeys.Alt))     mods |= HotkeyModifiers.Alt;
        if (m.HasFlag(ModifierKeys.Shift))   mods |= HotkeyModifiers.Shift;
        if (m.HasFlag(ModifierKeys.Windows)) mods |= HotkeyModifiers.Win;

        int vk = KeyInterop.VirtualKeyFromKey(key);
        string name = key.ToString();
        var chord = new HotkeyChord(mods, vk, name);
        SetChord(chord);
        EndCapture();
    }

    private void SetChord(HotkeyChord chord)
    {
        Chord = chord;
        ChordChanged?.Invoke(chord);
    }
}
```

> If `HotkeyChord` exposes its own preferred `KeyName` convention, use `chord.Format()` for display verbatim (it stringifies to e.g. "Ctrl+Shift+Space"). The `name = key.ToString()` is the captured key name; if Phase 3's `HotkeyChord` expects a specific `KeyName` (e.g. "Space"), map common keys (`Key.Space`→"Space") — Phase 3's `HotkeyChord` records `KeyName` purely for display, so `key.ToString()` ("Space", "A", "F5") is fine.

- [ ] **Step 2: Create `windows/JVoice.App/UI/DarkSection.xaml`**

```xml
<UserControl x:Class="JVoice.App.UI.DarkSection"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Name="Self">
    <Border CornerRadius="10" Background="{StaticResource Settings.SectionBg}"
            BorderBrush="{StaticResource Settings.Border}" BorderThickness="1">
        <StackPanel>
            <!-- header -->
            <StackPanel Orientation="Horizontal" Margin="12,9,12,7">
                <Ellipse Width="5" Height="5" VerticalAlignment="Center"
                         Fill="{Binding AccentBrush, ElementName=Self}">
                    <Ellipse.Effect>
                        <DropShadowEffect BlurRadius="6" ShadowDepth="0"
                                          Color="{Binding AccentGlowColor, ElementName=Self}" Opacity="0.55" />
                    </Ellipse.Effect>
                </Ellipse>
                <TextBlock Margin="7,0,0,0" VerticalAlignment="Center"
                           Text="{Binding HeaderText, ElementName=Self}"
                           FontSize="9.5" FontWeight="Bold"
                           Foreground="{StaticResource Settings.HeaderText}">
                    <TextBlock.Resources>
                        <!-- letter-spacing ≈ kerning 0.7; WPF Typography handles via TextBlock.Typography but
                             simplest faithful approach is a small CharacterSpacing-like effect omitted; the
                             token is kerning 0.7pt which is visually subtle. Leave default tracking. -->
                    </TextBlock.Resources>
                </TextBlock>
            </StackPanel>
            <!-- 0.5px divider -->
            <Rectangle Height="0.5" Fill="{StaticResource Settings.Border}" />
            <!-- content -->
            <ContentPresenter Margin="12" Content="{Binding Body, ElementName=Self}" />
        </StackPanel>
    </Border>
</UserControl>
```

- [ ] **Step 3: Create `windows/JVoice.App/UI/DarkSection.xaml.cs`**

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace JVoice.App.UI;

public partial class DarkSection : UserControl
{
    public DarkSection() => InitializeComponent();

    public static readonly DependencyProperty HeaderTextProperty =
        DependencyProperty.Register(nameof(HeaderText), typeof(string), typeof(DarkSection),
            new PropertyMetadata("", (d, e) => { /* uppercased in getter below */ }));

    /// Title is UPPERCASED per the token.
    public string HeaderText
    {
        get => ((string)GetValue(HeaderTextProperty)).ToUpperInvariant();
        set => SetValue(HeaderTextProperty, value);
    }

    public static readonly DependencyProperty AccentBrushProperty =
        DependencyProperty.Register(nameof(AccentBrush), typeof(Brush), typeof(DarkSection),
            new PropertyMetadata(Brushes.White, OnAccentChanged));

    public Brush AccentBrush
    {
        get => (Brush)GetValue(AccentBrushProperty);
        set => SetValue(AccentBrushProperty, value);
    }

    public static readonly DependencyProperty AccentGlowColorProperty =
        DependencyProperty.Register(nameof(AccentGlowColor), typeof(Color), typeof(DarkSection),
            new PropertyMetadata(Colors.White));

    public Color AccentGlowColor
    {
        get => (Color)GetValue(AccentGlowColorProperty);
        set => SetValue(AccentGlowColorProperty, value);
    }

    public static readonly DependencyProperty BodyProperty =
        DependencyProperty.Register(nameof(Body), typeof(object), typeof(DarkSection),
            new PropertyMetadata(null));

    public object? Body
    {
        get => GetValue(BodyProperty);
        set => SetValue(BodyProperty, value);
    }

    private static void OnAccentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is DarkSection s && e.NewValue is SolidColorBrush b)
            s.AccentGlowColor = b.Color;
    }
}
```

> `HeaderText` getter uppercases (the token says UPPERCASED title); pass the mixed-case title (e.g. "Last Transcript") and it displays "LAST TRANSCRIPT". The kerning 0.7 is omitted as visually negligible; if exact, wrap the title in a `TextBlock` with per-glyph runs — not worth it.

- [ ] **Step 4: Create `windows/JVoice.App/UI/SettingsView.xaml`** (the full 320×520 panel; all 9 sections in order)

```xml
<UserControl x:Class="JVoice.App.UI.SettingsView"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:ui="clr-namespace:JVoice.App.UI"
             Width="320" Height="520" Background="{StaticResource Settings.PanelBg}">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="16">
            <StackPanel.Resources>
                <!-- 10px gap between sections -->
                <Style TargetType="ui:DarkSection">
                    <Setter Property="Margin" Value="0,0,0,10" />
                </Style>
            </StackPanel.Resources>

            <!-- Header -->
            <StackPanel Margin="0,0,0,4">
                <TextBlock Text="JVoice" FontSize="17" FontWeight="Bold" Foreground="White" />
                <TextBlock Text="Voice dictation controls" FontSize="11" Foreground="{StaticResource Text.W45}" Margin="0,3,0,0" />
            </StackPanel>

            <!-- 1. LAST TRANSCRIPT (blue) -->
            <ui:DarkSection HeaderText="Last Transcript" AccentBrush="{StaticResource Settings.Blue}">
                <ui:DarkSection.Body>
                    <StackPanel>
                        <TextBlock x:Name="NoTranscript" Text="No transcript yet." FontSize="11"
                                   Foreground="{StaticResource Text.W40}"
                                   Visibility="{Binding HasTranscript, Converter={StaticResource InverseBoolToVis}}" />
                        <Border CornerRadius="6" Background="{StaticResource Settings.InputBg}"
                                BorderBrush="{StaticResource Settings.Border}" BorderThickness="1" Height="56"
                                Visibility="{Binding HasTranscript, Converter={StaticResource BoolToVis}}">
                            <TextBox x:Name="TranscriptBox" Background="Transparent" BorderThickness="0"
                                     Foreground="{StaticResource Text.W75}" FontSize="11"
                                     TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                                     Text="{Binding EditedTranscript, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" />
                        </Border>
                        <StackPanel Orientation="Horizontal" Margin="0,8,0,0"
                                    Visibility="{Binding HasTranscript, Converter={StaticResource BoolToVis}}">
                            <Button Content="Fix" Style="{StaticResource DarkPrimaryButton}"
                                    Click="OnFix" IsEnabled="{Binding CanFix}" />
                            <Button Content="Revert" Style="{StaticResource DarkPrimaryButton}" Margin="8,0,0,0"
                                    Foreground="{StaticResource Settings.Gray}" Tag="{StaticResource Settings.Gray}"
                                    Click="OnRevert" IsEnabled="{Binding CanRevert}" />
                        </StackPanel>
                    </StackPanel>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 2. KEYBOARD SHORTCUT (gray) -->
            <ui:DarkSection HeaderText="Keyboard Shortcut" AccentBrush="{StaticResource Settings.Gray}">
                <ui:DarkSection.Body>
                    <StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Toggle Recording:" FontSize="11" Foreground="{StaticResource Text.W75}"
                                       VerticalAlignment="Center" Margin="0,0,8,0" />
                            <ui:HotkeyRecorder x:Name="Recorder" MinWidth="120" Padding="8,4"
                                               Background="{StaticResource Settings.InputBg}"
                                               Foreground="{StaticResource Text.W75}" />
                        </StackPanel>
                        <TextBlock Text="Default: Ctrl + Shift + Space" FontSize="10"
                                   Foreground="{StaticResource Text.W35}" Margin="0,8,0,0" />
                    </StackPanel>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 3. LANGUAGE (indigo) -->
            <ui:DarkSection HeaderText="Language" AccentBrush="{StaticResource Settings.Indigo}">
                <ui:DarkSection.Body>
                    <UniformGrid Rows="1" x:Name="LanguageSeg">
                        <RadioButton Content="English"  GroupName="Lang" Style="{StaticResource SegmentLeft}"
                                     IsChecked="{Binding IsEnglish, Mode=TwoWay}" />
                        <RadioButton Content="Romanian" GroupName="Lang" Style="{StaticResource SegmentRight}"
                                     IsChecked="{Binding IsRomanian, Mode=TwoWay}" />
                    </UniformGrid>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 4. VOICE STYLE (purple) -->
            <ui:DarkSection HeaderText="Voice Style" AccentBrush="{StaticResource Settings.Purple}">
                <ui:DarkSection.Body>
                    <UniformGrid Rows="1">
                        <RadioButton Content="Casual"      GroupName="Tone" Style="{StaticResource SegmentLeft}"
                                     IsChecked="{Binding IsCasual, Mode=TwoWay}" />
                        <RadioButton Content="Formal"      GroupName="Tone" Style="{StaticResource SegmentMid}"
                                     IsChecked="{Binding IsFormal, Mode=TwoWay}" />
                        <RadioButton Content="Very Casual" GroupName="Tone" Style="{StaticResource SegmentRight}"
                                     IsChecked="{Binding IsVeryCasual, Mode=TwoWay}" />
                    </UniformGrid>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 5. PROCESSING (teal) -->
            <ui:DarkSection HeaderText="Processing" AccentBrush="{StaticResource Settings.Teal}">
                <ui:DarkSection.Body>
                    <Grid>
                        <StackPanel HorizontalAlignment="Left">
                            <TextBlock Text="Remove Filler Words" FontSize="12" FontWeight="Medium" Foreground="{StaticResource Text.W85}" />
                            <TextBlock Text="Strip um, uh, er, ah, hmm from output" FontSize="10" Foreground="{StaticResource Text.W38}" Margin="0,2,0,0" />
                        </StackPanel>
                        <CheckBox HorizontalAlignment="Right" VerticalAlignment="Center"
                                  Style="{StaticResource TealSwitch}"
                                  IsChecked="{Binding RemoveFillerWords, Mode=TwoWay}" />
                    </Grid>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 6. WHISPER MODEL (cyan) -->
            <ui:DarkSection HeaderText="Whisper Model" AccentBrush="{StaticResource Settings.Cyan}">
                <ui:DarkSection.Body>
                    <StackPanel>
                        <UniformGrid Rows="1">
                            <RadioButton Content="Tiny"  GroupName="Model" Style="{StaticResource SegmentLeft}"  IsChecked="{Binding IsTiny, Mode=TwoWay}" />
                            <RadioButton Content="Base"  GroupName="Model" Style="{StaticResource SegmentMid}"   IsChecked="{Binding IsBase, Mode=TwoWay}" />
                            <RadioButton Content="Small" GroupName="Model" Style="{StaticResource SegmentMid}"   IsChecked="{Binding IsSmall, Mode=TwoWay}" />
                            <RadioButton Content="Large" GroupName="Model" Style="{StaticResource SegmentRight}" IsChecked="{Binding IsLarge, Mode=TwoWay}" />
                        </UniformGrid>
                        <TextBlock Text="{Binding ModelGuidance}" FontSize="10" Foreground="{StaticResource Text.W38}"
                                   TextWrapping="Wrap" Margin="0,7,0,0" />
                    </StackPanel>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 7. CUSTOM WORDS (orange) -->
            <ui:DarkSection HeaderText="Custom Words" AccentBrush="{StaticResource Settings.Orange}">
                <ui:DarkSection.Body>
                    <StackPanel>
                        <TextBlock Text="No custom words added." FontSize="11" Foreground="{StaticResource Text.W40}"
                                   Visibility="{Binding HasCustomWords, Converter={StaticResource InverseBoolToVis}}" />
                        <ScrollViewer MaxHeight="88" VerticalScrollBarVisibility="Auto"
                                      Visibility="{Binding HasCustomWords, Converter={StaticResource BoolToVis}}">
                            <ItemsControl ItemsSource="{Binding CustomWords}">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Grid Margin="0,2">
                                            <TextBlock Text="{Binding}" FontSize="11" Foreground="{StaticResource Text.W75}" HorizontalAlignment="Left" />
                                            <Button HorizontalAlignment="Right" Style="{StaticResource PressableButton}"
                                                    Click="OnRemoveWord" Tag="{Binding}"
                                                    FontFamily="Segoe MDL2 Assets" Content="&#xECC9;"
                                                    Foreground="#CCFF6060" />
                                        </Grid>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                        <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                            <Border CornerRadius="6" Background="{StaticResource Settings.InputBg}"
                                    BorderBrush="{StaticResource Settings.Border}" BorderThickness="1" Width="200">
                                <TextBox x:Name="NewWordBox" Background="Transparent" BorderThickness="0"
                                         Foreground="{StaticResource Text.W75}" FontSize="11" Padding="8,5"
                                         KeyDown="OnNewWordKeyDown" />
                            </Border>
                            <Button Content="Add" Style="{StaticResource DarkPrimaryButton}" Margin="6,0,0,0"
                                    Foreground="{StaticResource Settings.Orange}" Tag="{StaticResource Settings.Orange}"
                                    Click="OnAddWord" />
                        </StackPanel>
                    </StackPanel>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 8. STATS (green) -->
            <ui:DarkSection HeaderText="Stats" AccentBrush="{StaticResource Settings.Green}">
                <ui:DarkSection.Body>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="Auto" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                            <TextBlock Text="{Binding TotalWordsSpoken}" FontSize="26" FontWeight="Bold" Foreground="White"
                                       FontFamily="Consolas" HorizontalAlignment="Center">
                                <TextBlock.Effect>
                                    <DropShadowEffect BlurRadius="16" ShadowDepth="0" Color="#4A9EFF" Opacity="0.45" />
                                </TextBlock.Effect>
                            </TextBlock>
                            <TextBlock Text="total words" FontSize="10" Foreground="{StaticResource Text.W38}" HorizontalAlignment="Center" />
                        </StackPanel>
                        <Rectangle Grid.Column="1" Width="0.5" Height="44" Fill="{StaticResource Settings.Border}" />
                        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                            <TextBlock Text="{Binding AverageWpmDisplay}" FontSize="26" FontWeight="Bold" Foreground="White"
                                       FontFamily="Consolas" HorizontalAlignment="Center">
                                <TextBlock.Effect>
                                    <DropShadowEffect BlurRadius="16" ShadowDepth="0" Color="#4ADEA0" Opacity="0.45" />
                                </TextBlock.Effect>
                            </TextBlock>
                            <TextBlock Text="avg WPM" FontSize="10" Foreground="{StaticResource Text.W38}" HorizontalAlignment="Center" />
                        </StackPanel>
                    </Grid>
                </ui:DarkSection.Body>
            </ui:DarkSection>

            <!-- 9. Footer: Restore Defaults / Quit -->
            <Grid>
                <Button Content="Restore Default Settings" Style="{StaticResource DarkDestructiveButton}"
                        HorizontalAlignment="Left" Click="OnRestoreDefaults" />
                <Button Content="Quit JVoice" Style="{StaticResource DarkDestructiveButton}"
                        HorizontalAlignment="Right" Click="OnQuit" />
            </Grid>
        </StackPanel>
    </ScrollViewer>
</UserControl>
```

> The segmented pickers (`SegmentLeft/Mid/Right`), the `TealSwitch` CheckBox style, and the `BoolToVis`/`InverseBoolToVis` converters are defined in `JVoicePalette.xaml`. **Add them now** (Step 5). They reproduce the macOS segmented `Picker` (a row of joined toggles) and the teal `.switch` toggle.

- [ ] **Step 5: Append to `JVoicePalette.xaml`** — the converters + segmented-control styles + teal switch. Add inside the existing `<ResourceDictionary>`:

```xml
    <!-- ===== converters ===== -->
    <BooleanToVisibilityConverter x:Key="BoolToVis" />
    <!-- InverseBoolToVis: defined in code (Converters.cs) and added here as a resource. -->
    <local:InverseBoolToVisibilityConverter xmlns:local="clr-namespace:JVoice.App.UI" x:Key="InverseBoolToVis" />

    <!-- ===== segmented radio-button styles (joined toggle row) ===== -->
    <Style x:Key="SegmentBase" TargetType="RadioButton">
        <Setter Property="FontSize" Value="11" />
        <Setter Property="Foreground" Value="{StaticResource Text.W75}" />
        <Setter Property="HorizontalContentAlignment" Value="Center" />
        <Setter Property="VerticalContentAlignment" Value="Center" />
        <Setter Property="Padding" Value="0,5" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="RadioButton">
                    <Border x:Name="Seg" Background="{StaticResource Settings.InputBg}"
                            BorderBrush="{StaticResource Settings.Border}" BorderThickness="1"
                            CornerRadius="{TemplateBinding Tag}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="6,5" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Seg" Property="Background">
                                <Setter.Value>
                                    <SolidColorBrush Color="#4A9EFF" Opacity="0.22" />
                                </Setter.Value>
                            </Setter>
                            <Setter Property="Foreground" Value="White" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style x:Key="SegmentLeft"  TargetType="RadioButton" BasedOn="{StaticResource SegmentBase}">
        <Setter Property="Tag" Value="6,0,0,6" />
    </Style>
    <Style x:Key="SegmentMid"   TargetType="RadioButton" BasedOn="{StaticResource SegmentBase}">
        <Setter Property="Tag" Value="0" />
    </Style>
    <Style x:Key="SegmentRight" TargetType="RadioButton" BasedOn="{StaticResource SegmentBase}">
        <Setter Property="Tag" Value="0,6,6,0" />
    </Style>

    <!-- ===== teal switch (CheckBox rendered as a macOS-style switch) ===== -->
    <Style x:Key="TealSwitch" TargetType="CheckBox">
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="CheckBox">
                    <Border x:Name="Track" Width="38" Height="22" CornerRadius="11"
                            Background="{StaticResource Settings.Border}">
                        <Ellipse x:Name="Knob" Width="18" Height="18" Fill="White"
                                 HorizontalAlignment="Left" Margin="2,0,0,0" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Track" Property="Background" Value="{StaticResource Settings.Teal}" />
                            <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right" />
                            <Setter TargetName="Knob" Property="Margin" Value="0,0,2,0" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
```

Also create `windows/JVoice.App/UI/Converters.cs`:

```csharp
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace JVoice.App.UI;

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type t, object p, CultureInfo c)
        => (value is bool b && b) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type t, object p, CultureInfo c)
        => value is Visibility v && v == Visibility.Collapsed;
}
```

> Note: the selected-segment fill is hardcoded blue@0.22 in `SegmentBase`. The macOS segmented control uses the OS accent; blue@0.22 reads correctly on the dark panel for all four sections. (Per-section accent on the selected segment is a polish item.)

- [ ] **Step 6: Create `windows/JVoice.App/UI/SettingsView.xaml.cs`** (event handlers delegating to the coordinator; the coordinator is the `DataContext`)

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace JVoice.App.UI;

public partial class SettingsView : UserControl
{
    private VoiceCoordinator Vm => (VoiceCoordinator)DataContext;

    public SettingsView()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            // Seed the recorder + transcript editor from the coordinator.
            Recorder.Chord = Vm.Hotkey;
            Recorder.ChordChanged += chord => Vm.SetHotkey(chord);
            Vm.SyncEditedTranscriptFromLast();
        };
        Unloaded += (_, _) => Vm.ClearRevertBuffer();
    }

    private void OnFix(object sender, RoutedEventArgs e) => Vm.FixLastTranscript(Vm.EditedTranscript);
    private void OnRevert(object sender, RoutedEventArgs e) => Vm.RevertLastFix();

    private void OnAddWord(object sender, RoutedEventArgs e) => SubmitWord();
    private void OnNewWordKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { SubmitWord(); e.Handled = true; }
    }
    private void SubmitWord()
    {
        Vm.AddCustomWord(NewWordBox.Text);
        NewWordBox.Clear();
    }

    private void OnRemoveWord(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string word)
            Vm.RemoveCustomWord(word);
    }

    private void OnRestoreDefaults(object sender, RoutedEventArgs e)
    {
        var r = MessageBox.Show(
            "Your custom words, model choice, and language will be restored to defaults. Recording statistics will not be affected.",
            "Reset all JVoice settings to defaults?",
            MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (r == MessageBoxResult.OK) Vm.ResetSettings();
    }

    private void OnQuit(object sender, RoutedEventArgs e) => Vm.QuitApp();
}
```

- [ ] **Step 7: Create `windows/JVoice.App/UI/SettingsWindow.cs`** (chrome window; 320×520 content; taskbar button while open; dark title bar)

```csharp
using System.Windows;
using System.Windows.Media;

namespace JVoice.App.UI;

/// Real focusable app window hosting SettingsView. Ports SettingsWindow.swift
/// (titled "Settings", centered, released-on-close=false → we just Hide()).
public sealed class SettingsWindow : Window
{
    private readonly SettingsView _view = new();

    public SettingsWindow(VoiceCoordinator coordinator)
    {
        Title = "Settings";
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = true; // a real app window while open
        Background = (Brush)Application.Current.Resources["Settings.PanelBg"];
        _view.DataContext = coordinator;
        Content = _view;
        // Don't destroy on close — hide so a re-open is instant and state persists.
        Closing += (s, e) => { e.Cancel = true; Hide(); };
    }

    public void ShowOrActivate()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true; Topmost = false; // bring to front then release topmost
        Focus();
    }
}
```

> Dark title bar (optional polish): WPF doesn't theme the OS title bar. To match the macOS dark window, set the DWM immersive-dark-mode attribute (`DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE=20, 1)`) in `SourceInitialized`. Add it as a small P/Invoke if desired; it is a nicety, not load-bearing. The content (320×520) is fully dark regardless.

- [ ] **Step 8: Temporary visual harness** — set `App.OnStartup` to `new UI.SettingsWindow(/* a throwaway coordinator after Task 8 */).ShowOrActivate();`. Since the coordinator doesn't exist until Task 8, defer this visual check to Task 8 Step (verification). For now just confirm `dotnet build windows/JVoice.App` compiles all the XAML (the `{Binding ...}` paths will resolve at runtime against the coordinator). 

- [ ] **Step 9: Commit** — `git add windows/JVoice.App/UI/HotkeyRecorder.cs windows/JVoice.App/UI/DarkSection.xaml* windows/JVoice.App/UI/SettingsView.xaml* windows/JVoice.App/UI/SettingsWindow.cs windows/JVoice.App/UI/Converters.cs windows/JVoice.App/UI/Styles/JVoicePalette.xaml && git commit -m "feat(win-ui): Settings panel (9 sections, hotkey recorder, dark section chrome)"`

---

## Task 7: `TrayIcon` (3-state icon + menu)

> Ports `MenuBarController.swift`: the tray "J" with 3 activity states (idle "J" / red mic / cyan waveform) and the menu (Start/Stop Dictation, Settings…, Launch at Login ✓, Quit JVoice). Wraps `H.NotifyIcon.Wpf`'s `TaskbarIcon`. The 3 PNGs are loaded as `BitmapImage`s from the embedded `Assets/`.

**Files:**
- Create: `windows/JVoice.App/UI/TrayIcon.cs`

**Interfaces:**
- Consumes: `H.NotifyIcon.TaskbarIcon`; the embedded tray PNGs (pack URIs).
- Produces: `sealed class TrayIcon : IDisposable` with `enum Activity { Idle, Recording, Transcribing }`, `void SetActivity(Activity)`, properties/callbacks `Func<bool> IsRecording`, `Func<bool> LaunchAtLoginEnabled`, and `Action OnToggleDictation`, `Action OnOpenSettings`, `Action OnToggleLaunchAtLogin`, `Action OnQuit`, plus `void RebuildMenu()`.

- [ ] **Step 1: Create `windows/JVoice.App/UI/TrayIcon.cs`**

```csharp
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using H.NotifyIcon;

namespace JVoice.App.UI;

public sealed class TrayIcon : IDisposable
{
    public enum Activity { Idle, Recording, Transcribing }

    private readonly TaskbarIcon _icon;
    private readonly BitmapImage _idle = Load("tray-idle.png");
    private readonly BitmapImage _recording = Load("tray-recording.png");
    private readonly BitmapImage _transcribing = Load("tray-transcribing.png");
    private Activity _activity = Activity.Idle;

    // Wiring (set by App on construction).
    public Func<bool> IsRecording { get; set; } = () => false;
    public Func<bool> LaunchAtLoginEnabled { get; set; } = () => false;
    public Action OnToggleDictation { get; set; } = () => { };
    public Action OnOpenSettings { get; set; } = () => { };
    public Action OnToggleLaunchAtLogin { get; set; } = () => { };
    public Action OnQuit { get; set; } = () => { };

    public TrayIcon()
    {
        _icon = new TaskbarIcon
        {
            ToolTipText = "JVoice",
            IconSource = _idle,
        };
        // Rebuild the context menu each time it opens so item titles/checkmarks
        // reflect live state (mirrors NSMenuDelegate.menuNeedsUpdate).
        _icon.TrayContextMenuOpen += (_, _) => RebuildMenu();
        _icon.ContextMenu = new ContextMenu();
        // A left-click could toggle dictation, but macOS uses the menu for everything;
        // keep left-click = open menu (H.NotifyIcon default).
        _icon.ForceCreate(); // ensure the icon is shown immediately
    }

    private static BitmapImage Load(string file)
        => new(new Uri($"pack://application:,,,/Assets/{file}"));

    public void SetActivity(Activity activity)
    {
        if (_activity == activity) return;
        _activity = activity;
        _icon.IconSource = activity switch
        {
            Activity.Recording => _recording,
            Activity.Transcribing => _transcribing,
            _ => _idle,
        };
        _icon.ToolTipText = activity switch
        {
            Activity.Recording => "JVoice — recording",
            Activity.Transcribing => "JVoice — transcribing",
            _ => "JVoice",
        };
    }

    public void RebuildMenu()
    {
        var menu = new ContextMenu();

        var dictation = new MenuItem
        {
            Header = IsRecording() ? "Stop Dictation" : "Start Dictation",
        };
        dictation.Click += (_, _) => OnToggleDictation();
        menu.Items.Add(dictation);

        menu.Items.Add(new Separator());

        var settings = new MenuItem { Header = "Settings…" };
        settings.Click += (_, _) => OnOpenSettings();
        menu.Items.Add(settings);

        var launch = new MenuItem { Header = "Launch at Login", IsChecked = LaunchAtLoginEnabled() };
        launch.Click += (_, _) => OnToggleLaunchAtLogin();
        menu.Items.Add(launch);

        menu.Items.Add(new Separator());

        var quit = new MenuItem { Header = "Quit JVoice" };
        quit.Click += (_, _) => OnQuit();
        menu.Items.Add(quit);

        _icon.ContextMenu = menu;
    }

    public void Dispose() => _icon.Dispose();
}
```

> Notes:
> - `H.NotifyIcon` `TaskbarIcon` is the WPF tray control; `IconSource` accepts an `ImageSource` (the PNG). On Windows the tray is usually dark, so the **white "J"** (`tray-idle.png`) reads well; the recording/transcribing states use the colored mic/waveform PNGs exactly as the macOS app uses systemRed mic / cyan waveform.
> - `ForceCreate()` makes the icon appear without needing it placed in a visual tree. Alternatively place a `TaskbarIcon` in `App.xaml` resources; the code approach keeps wiring centralized.
> - The menu is rebuilt on open so "Start/Stop Dictation" and the Launch-at-Login checkmark are always current — a faithful port of `menuNeedsUpdate`.

- [ ] **Step 2: Verify** — covered by Task 9 (tray needs the coordinator). For now `dotnet build windows/JVoice.App` compiles.

- [ ] **Step 3: Commit** — `git add windows/JVoice.App/UI/TrayIcon.cs && git commit -m "feat(win-ui): tray icon (3-state J/mic/waveform) + menu"`

---

## Task 8: `VoiceCoordinator` — the dictation pipeline (+ pure decision helpers + tests)

> The heart of Phase 4. Faithful port of `VoiceCoordinator.swift`. `INotifyPropertyChanged` so the Settings panel binds. All platform callbacks marshal to the `Dispatcher` (the `@MainActor` analog). The `recordingGeneration` guard, the `isStarting/isStopping` reentrancy guards, target-window resolution, the finish pipeline, settings persistence + engine swap, custom words, fix/revert, prewarm, and quit all port 1:1. Pure decision logic is extracted to `JVoice.Core` and unit-tested.

### 8a. Pure decision helpers in `JVoice.Core` (testable; no WPF)

**Files:**
- Create: `windows/JVoice.Core/CoordinatorDecisions.cs`
- Test: `windows/JVoice.Tests/CoordinatorDecisionsTests.cs`

**Interfaces:**
- Produces: `static class CoordinatorDecisions` with:
  - `IntPtr ResolveTargetWindow(IntPtr currentForeground, IntPtr self, IntPtr lastNonSelf)` — ports the Swift `resolvedTargetPID` rule: if `currentForeground != self` and `currentForeground != Zero` → use it; else use `lastNonSelf`. Returns `IntPtr.Zero` if none.
  - `TrayIconActivity HudToTray(HudStateKind kind)` — ports `updateHUD`'s `switch`: recording→Recording; preparingModel/downloadingModel/transcribing→Transcribing; idle/done/error→Idle. (`TrayIconActivity` is a Core enum mirroring `TrayIcon.Activity`.)
  - `int HudResetDelayMs(HudStateKind kind)` — done→1000, error→3000 (matches `scheduleHUDReset` defaults).

- [ ] **Step 1: Write `windows/JVoice.Tests/CoordinatorDecisionsTests.cs`** (failing first)

```csharp
using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class CoordinatorDecisionsTests
{
    private static readonly IntPtr Self = new(1);
    private static readonly IntPtr AppA = new(2);
    private static readonly IntPtr AppB = new(3);

    [Fact]
    public void Resolve_UsesForeground_WhenNotSelf()
        => Assert.Equal(AppA, CoordinatorDecisions.ResolveTargetWindow(AppA, Self, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsSelf()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(Self, Self, AppB));

    [Fact]
    public void Resolve_FallsBackToLastNonSelf_WhenForegroundIsZero()
        => Assert.Equal(AppB, CoordinatorDecisions.ResolveTargetWindow(IntPtr.Zero, Self, AppB));

    [Fact]
    public void Resolve_ReturnsZero_WhenNothingUsable()
        => Assert.Equal(IntPtr.Zero, CoordinatorDecisions.ResolveTargetWindow(Self, Self, IntPtr.Zero));

    [Theory]
    [InlineData(HudStateKind.Recording, TrayIconActivity.Recording)]
    [InlineData(HudStateKind.PreparingModel, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.DownloadingModel, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.Transcribing, TrayIconActivity.Transcribing)]
    [InlineData(HudStateKind.Idle, TrayIconActivity.Idle)]
    [InlineData(HudStateKind.Done, TrayIconActivity.Idle)]
    [InlineData(HudStateKind.Error, TrayIconActivity.Idle)]
    public void HudToTray_Maps(HudStateKind kind, TrayIconActivity expected)
        => Assert.Equal(expected, CoordinatorDecisions.HudToTray(kind));

    [Theory]
    [InlineData(HudStateKind.Done, 1000)]
    [InlineData(HudStateKind.Error, 3000)]
    public void HudResetDelay(HudStateKind kind, int ms)
        => Assert.Equal(ms, CoordinatorDecisions.HudResetDelayMs(kind));
}
```

- [ ] **Step 2: Create `windows/JVoice.Core/CoordinatorDecisions.cs`**

```csharp
using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure decision logic extracted from the (UI-thread) VoiceCoordinator so it
/// is unit-testable from net9.0 JVoice.Tests (which cannot reference the
/// net9.0-windows JVoice.App). The WPF coordinator calls these.
public enum TrayIconActivity { Idle, Recording, Transcribing }

public static class CoordinatorDecisions
{
    /// Ports VoiceCoordinator.stopRecordingAndTranscribe's target resolution:
    /// frontmost-if-not-self else last-non-self frontmost.
    public static IntPtr ResolveTargetWindow(IntPtr currentForeground, IntPtr self, IntPtr lastNonSelf)
    {
        if (currentForeground != IntPtr.Zero && currentForeground != self)
            return currentForeground;
        return lastNonSelf; // may be Zero → caller surfaces "no target app"
    }

    /// Ports updateHUD's menu-bar mirror switch.
    public static TrayIconActivity HudToTray(HudStateKind kind) => kind switch
    {
        HudStateKind.Recording => TrayIconActivity.Recording,
        HudStateKind.PreparingModel or HudStateKind.DownloadingModel or HudStateKind.Transcribing
            => TrayIconActivity.Transcribing,
        _ => TrayIconActivity.Idle, // Idle, Done, Error
    };

    /// Ports scheduleHUDReset default delays.
    public static int HudResetDelayMs(HudStateKind kind) => kind switch
    {
        HudStateKind.Error => 3000,
        _ => 1000,
    };
}
```

- [ ] **Step 3: Run** — `dotnet test windows/JVoice.Tests` → all PASS.
- [ ] **Step 4: Commit** — `git add windows/JVoice.Core/CoordinatorDecisions.cs windows/JVoice.Tests/CoordinatorDecisionsTests.cs && git commit -m "feat(core): pure coordinator decision helpers + tests"`

### 8b. `VoiceCoordinator.cs`

**Files:**
- Create: `windows/JVoice.App/VoiceCoordinator.cs`

**Interfaces:**
- Consumes (Phase 1): `TextProcessor`, `VocabularyPrompt` (indirectly via engine), `HudState`, `HudStateKind`, `ToneStyle`, `WhisperModelOption`, `TranscriptionLanguage`, `SettingsState`, `AppTimings`, `ITranscriptionEngine`, `StreamingTranscriptionSession`, `TranscriptionException`, `FileBackedTranscriptionEngine`, `CoordinatorDecisions`, `TrayIconActivity`.
- Consumes (Phase 2): `WhisperNetTranscriptionEngine`, `WhisperModelStore`.
- Consumes (Phase 3): `NAudioRecorder`/`IAudioRecorder`, `Paster`/`PasteOutcome`, `GlobalHotkey`/`HotkeyChord`, `ForegroundWindowTracker`, `LaunchAtLogin`, `SettingsStore`, `StatsStore`, `LastTranscriptStore`, `PermissionError`, `SystemActions`, `SettingsUris`.
- Produces: `sealed class VoiceCoordinator : INotifyPropertyChanged, IDisposable` with bindable properties + the pipeline methods + tray/HUD/Settings wiring entry points consumed by `App.xaml.cs` (Task 9).

**Threading contract (overview §6.1):** Construct and use the coordinator on the WPF UI thread. The coordinator stores `Dispatcher _dispatcher = Dispatcher.CurrentDispatcher`. Every platform callback (`GlobalHotkey.Triggered`, `ForegroundWindowTracker` updates, `IAudioRecorder.Failed`, `SystemActions.ErrorHandler`, `SettingsStore.Changed`) is wrapped to `_dispatcher.InvokeAsync(...)` before touching state. `await` continuations on the UI thread preserve the `@MainActor` semantics; after each `await` re-check `_recordingGeneration` exactly as Swift re-checks after each suspension.

- [ ] **Step 1: Create `windows/JVoice.App/VoiceCoordinator.cs`** — Part A (state, ctor, settings, engine swap, HUD, tray/window wiring)

```csharp
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;
using JVoice.Core;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using JVoice.Core.Transcription;

namespace JVoice.App;

public sealed class VoiceCoordinator : INotifyPropertyChanged, IDisposable
{
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;

    // Platform services (Phase 3) + engine pieces (Phase 2).
    private readonly SettingsStore _settingsStore;
    private readonly StatsStore _statsStore = new();
    private readonly LastTranscriptStore _lastTranscriptStore = new();
    private readonly IAudioRecorder _recorder = new NAudioRecorder();
    private readonly Paster _paster = new();
    private readonly ForegroundWindowTracker _foreground = new();
    private readonly GlobalHotkey _hotkey = new();
    private readonly WhisperModelStore _modelStore = new();

    private ITranscriptionEngine _engine;

    // UI surfaces (set by App in Task 9).
    public HudWindow? Hud { get; set; }
    public TrayIcon? Tray { get; set; }
    private SettingsWindow? _settingsWindow;

    // ---- coordinator state (mirrors the Swift @Published / private fields) ----
    private int _recordingGeneration;
    private bool _isStartingRecording;
    private bool _isStoppingRecording;
    private bool _isInitializing = true;
    private DateTime? _recordingStartUtc;
    private double _lastRecordingSeconds;
    private StreamingTranscriptionSession? _streamingSession;
    private CancellationTokenSource? _transcriptionCts;
    private DispatcherTimer? _hudResetTimer;
    private IntPtr _selfHwnd;
    private string[] _pendingRevertWords = [];
    private string _preFixTranscript = "";

    public VoiceCoordinator()
    {
        _settingsStore = new SettingsStore();
        var s = _settingsStore.State;

        _toneMode = s.Mode;
        _whisperModel = s.Model;
        _language = s.Language;
        CustomWords = new ObservableCollection<string>(s.CustomWords);
        _removeFillerWords = s.RemoveFillerWords;
        _hotkeyChord = HotkeyChord.Default; // overwritten below if persisted (see Note)
        _totalWordsSpoken = _statsStore.TotalWords;
        _averageWpm = _statsStore.AverageWpm;
        _lastTranscript = _lastTranscriptStore.Transcript;
        EditedTranscript = _lastTranscript;
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;

        _engine = MakeEngine(_whisperModel, _language, CustomWords.ToList());
        _isInitializing = false;
    }

    // ====================== bindable properties ======================

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private ToneStyle _toneMode;
    public ToneStyle ToneMode
    {
        get => _toneMode;
        set { if (_toneMode == value) return; _toneMode = value; PersistSettings(); RaiseToneFlags(); }
    }

    private WhisperModelOption _whisperModel;
    public WhisperModelOption WhisperModel
    {
        get => _whisperModel;
        set
        {
            if (_whisperModel == value) return;
            _whisperModel = value;
            SwapEngine();              // engine swap on model change (TranscriptionManager.updateEngine analog)
            PersistSettings();
            Raise(nameof(ModelGuidance)); RaiseModelFlags();
        }
    }

    private TranscriptionLanguage _language;
    public TranscriptionLanguage Language
    {
        get => _language;
        set
        {
            if (_language == value) return;
            _language = value;
            SwapEngine();              // engine swap on language change
            PersistSettings();
            RaiseLanguageFlags();
        }
    }

    private bool _removeFillerWords;
    public bool RemoveFillerWords
    {
        get => _removeFillerWords;
        set { if (_removeFillerWords == value) return; _removeFillerWords = value; PersistSettings(); Raise(); }
    }

    public ObservableCollection<string> CustomWords { get; }

    private HotkeyChord _hotkeyChord;
    public HotkeyChord Hotkey => _hotkeyChord;

    private string _lastTranscript = "";
    public string LastTranscript
    {
        get => _lastTranscript;
        private set { _lastTranscript = value; Raise(); Raise(nameof(HasTranscript)); }
    }

    private string _editedTranscript = "";
    public string EditedTranscript
    {
        get => _editedTranscript;
        set { _editedTranscript = value; Raise(); Raise(nameof(CanFix)); }
    }

    private bool _canRevert;
    public bool CanRevert { get => _canRevert; private set { _canRevert = value; Raise(); } }

    private int _totalWordsSpoken;
    public int TotalWordsSpoken { get => _totalWordsSpoken; private set { _totalWordsSpoken = value; Raise(); } }

    private double _averageWpm;
    public double AverageWpm { get => _averageWpm; private set { _averageWpm = value; Raise(); Raise(nameof(AverageWpmDisplay)); } }
    public string AverageWpmDisplay => AverageWpm > 0 ? AverageWpm.ToString("F0") : "—";

    public bool LaunchAtLoginEnabled { get; private set; }

    private bool _isRecording;
    public bool IsRecording { get => _isRecording; private set { _isRecording = value; Raise(); } }

    private HudState _hudState = HudState.Idle;
    public HudState HudState { get => _hudState; private set { _hudState = value; Raise(); } }

    // ---- derived flags for the segmented pickers + visibility binders ----
    public bool HasTranscript => !string.IsNullOrEmpty(LastTranscript);
    public bool HasCustomWords => CustomWords.Count > 0;
    public bool CanFix => EditedTranscript.Trim() != LastTranscript.Trim();
    public string ModelGuidance => WhisperModel.Guidance();

    public bool IsEnglish { get => Language == TranscriptionLanguage.English; set { if (value) Language = TranscriptionLanguage.English; } }
    public bool IsRomanian { get => Language == TranscriptionLanguage.Romanian; set { if (value) Language = TranscriptionLanguage.Romanian; } }
    public bool IsCasual { get => ToneMode == ToneStyle.Casual; set { if (value) ToneMode = ToneStyle.Casual; } }
    public bool IsFormal { get => ToneMode == ToneStyle.Formal; set { if (value) ToneMode = ToneStyle.Formal; } }
    public bool IsVeryCasual { get => ToneMode == ToneStyle.VeryCasual; set { if (value) ToneMode = ToneStyle.VeryCasual; } }
    public bool IsTiny { get => WhisperModel == WhisperModelOption.Tiny; set { if (value) WhisperModel = WhisperModelOption.Tiny; } }
    public bool IsBase { get => WhisperModel == WhisperModelOption.Base; set { if (value) WhisperModel = WhisperModelOption.Base; } }
    public bool IsSmall { get => WhisperModel == WhisperModelOption.Small; set { if (value) WhisperModel = WhisperModelOption.Small; } }
    public bool IsLarge { get => WhisperModel == WhisperModelOption.LargeTurbo; set { if (value) WhisperModel = WhisperModelOption.LargeTurbo; } }

    private void RaiseToneFlags() { Raise(nameof(IsCasual)); Raise(nameof(IsFormal)); Raise(nameof(IsVeryCasual)); }
    private void RaiseLanguageFlags() { Raise(nameof(IsEnglish)); Raise(nameof(IsRomanian)); }
    private void RaiseModelFlags() { Raise(nameof(IsTiny)); Raise(nameof(IsBase)); Raise(nameof(IsSmall)); Raise(nameof(IsLarge)); }

    // ====================== lifecycle / wiring ======================

    /// Ports VoiceCoordinator.start(): sweep orphans, install hooks, hotkey, prewarm.
    public void Start()
    {
        NAudioRecorder.SweepOrphanedRecordings();

        _selfHwnd = ForegroundWindowTracker.GetForegroundWindowNow(); // best-effort; refined by tracker
        _foreground.Start();

        // Global error hook (SystemActions analog) marshalled to the dispatcher.
        SystemActions.ErrorHandler = msg => _dispatcher.InvokeAsync(() => ShowError(msg));

        // Settings changed externally (e.g. background save reporting) → refresh launch flag, etc.
        _settingsStore.Changed += _ => _dispatcher.InvokeAsync(() => { /* no-op; UI binds the live props */ });

        // Recorder mid-recording failure → surface + stop.
        _recorder.Failed += msg => _dispatcher.InvokeAsync(() => ShowError(msg));

        // Hotkey → toggle (debounced in GlobalHotkey).
        _hotkey.Triggered += () => _dispatcher.InvokeAsync(ToggleRecording);
        _hotkey.Register(_hotkeyChord);

        UpdateHud(HudState.Idle);

        // Prewarm the selected model in the background (no UI block).
        _ = _engine.PrewarmAsync();
    }

    /// Auto-enable launch-at-login on first run, then sync the live flag.
    public void BootstrapLaunchAtLogin()
    {
        LaunchAtLogin.PerformFirstRunEnableIfNeeded();
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;
        Raise(nameof(LaunchAtLoginEnabled));
    }

    public void SetLaunchAtLogin(bool enabled)
    {
        LaunchAtLogin.SetEnabled(enabled); // does not throw; errors via SystemActions
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;
        Raise(nameof(LaunchAtLoginEnabled));
        Tray?.RebuildMenu();
    }

    public void ToggleLaunchAtLogin() => SetLaunchAtLogin(!LaunchAtLoginEnabled);

    public void SetHotkey(HotkeyChord chord)
    {
        _hotkeyChord = chord;
        _hotkey.Register(chord); // re-register the low-level hook with the new chord
        Raise(nameof(Hotkey));
        // (Persisting the hotkey is optional: SettingsState has no hotkey field in Phase 1.
        //  If a future SettingsState gains a Hotkey, persist here. For now it lives for the session
        //  and resets to Default on relaunch — documented assumption.)
    }

    public void ShowSettings()
    {
        _settingsWindow ??= new SettingsWindow(this);
        _settingsWindow.ShowOrActivate();
    }

    // ---- engine construction / swap (TranscriptionManager analog) ----

    private ITranscriptionEngine MakeEngine(WhisperModelOption model, TranscriptionLanguage lang, IReadOnlyList<string> vocab)
    {
        try
        {
            return new WhisperNetTranscriptionEngine(model, lang, vocab, useVocabularyPrompt: true, _modelStore);
        }
        catch
        {
            // No whisper available (e.g. tests / missing native) → file-backed fallback.
            return new FileBackedTranscriptionEngine();
        }
    }

    /// Swap the engine for the current model+language+vocab. If the model isn't
    /// downloaded yet, kick off a background download surfacing DownloadingModel
    /// progress, then prewarm. Mirrors @Published whisperModel/language didSet →
    /// transcriptionManager.updateEngine(...).
    private void SwapEngine()
    {
        var model = _whisperModel;
        var lang = _language;
        var vocab = CustomWords.ToList();
        _engine = MakeEngine(model, lang, vocab);

        _ = Task.Run(async () =>
        {
            try
            {
                if (_modelStore.CompleteModelPath(model) is null)
                {
                    var progress = new Progress<double>(p =>
                        _dispatcher.InvokeAsync(() => UpdateHud(HudState.DownloadingModel(double.IsNaN(p) ? 0 : p))));
                    await _modelStore.EnsureAsync(model, progress, CancellationToken.None);
                    await _dispatcher.InvokeAsync(() => { if (HudState.Kind == HudStateKind.DownloadingModel) UpdateHud(HudState.Idle); });
                }
                await _engine.PrewarmAsync();
            }
            catch (Exception ex)
            {
                _dispatcher.InvokeAsync(() => ShowError($"Couldn't prepare the model: {ex.Message}"));
            }
        });
    }

    // ---- persistence ----

    private void PersistSettings()
    {
        if (_isInitializing) return;
        _settingsStore.Update(prev => prev with
        {
            Mode = _toneMode,
            Model = _whisperModel,
            Language = _language,
            CustomWords = CustomWords.ToList(),
            RemoveFillerWords = _removeFillerWords,
        });
    }

    public void FlushSettings() => _settingsStore.Flush();

    public void ResetSettings()
    {
        _isInitializing = true;
        _settingsStore.Reset();
        var s = _settingsStore.State;
        ToneMode = s.Mode;           // setters short-circuit persistence via _isInitializing
        WhisperModel = s.Model;
        Language = s.Language;
        CustomWords.Clear();
        foreach (var w in s.CustomWords) CustomWords.Add(w);
        RemoveFillerWords = s.RemoveFillerWords;
        _isInitializing = false;
        _settingsStore.Flush();
        // Re-raise everything the UI binds.
        RaiseToneFlags(); RaiseLanguageFlags(); RaiseModelFlags();
        Raise(nameof(RemoveFillerWords)); Raise(nameof(HasCustomWords)); Raise(nameof(ModelGuidance));
        _engine = MakeEngine(_whisperModel, _language, CustomWords.ToList());
        _ = _engine.PrewarmAsync();
    }

    // ---- custom words / fix-revert (ports the Swift methods 1:1) ----

    public void AddCustomWord(string word)
    {
        var trimmed = word.Trim();
        if (trimmed.Length == 0 || CustomWords.Contains(trimmed)) return;
        CustomWords.Add(trimmed);
        Raise(nameof(HasCustomWords));
        PersistSettings();
        _ = _engine.UpdateVocabularyAsync(CustomWords.ToList()); // updateVocabulary analog
    }

    public void RemoveCustomWord(string word)
    {
        if (!CustomWords.Remove(word)) return;
        Raise(nameof(HasCustomWords));
        PersistSettings();
        _ = _engine.UpdateVocabularyAsync(CustomWords.ToList());
    }

    public void SyncEditedTranscriptFromLast() => EditedTranscript = LastTranscript;

    public void FixLastTranscript(string corrected)
    {
        var trimmed = corrected.Trim();
        if (trimmed.Length == 0) return;
        _preFixTranscript = LastTranscript;
        var newWords = TextProcessor.ExtractCorrections(LastTranscript, trimmed);
        var inserted = new List<string>();
        foreach (var w in newWords)
        {
            var t = w.Trim();
            if (t.Length == 0 || CustomWords.Contains(t)) continue;
            AddCustomWord(t);
            inserted.Add(t);
        }
        _pendingRevertWords = inserted.ToArray();
        CanRevert = inserted.Count > 0;
        _lastTranscriptStore.Transcript = trimmed;
        LastTranscript = trimmed;
        EditedTranscript = trimmed;
    }

    public void RevertLastFix()
    {
        foreach (var w in _pendingRevertWords) RemoveCustomWord(w);
        _pendingRevertWords = [];
        CanRevert = false;
        LastTranscript = _preFixTranscript;
        EditedTranscript = _preFixTranscript;
        _lastTranscriptStore.Transcript = _preFixTranscript;
        _preFixTranscript = "";
    }

    public void ClearRevertBuffer() { _pendingRevertWords = []; CanRevert = false; }

    // ---- HUD + tray mirror (updateHUD analog) ----

    private void UpdateHud(HudState state)
    {
        HudState = state;
        Hud?.Update(state);
        Tray?.SetActivity((TrayIcon.Activity)CoordinatorDecisions.HudToTray(state.Kind));
    }

    public void ShowError(string message)
    {
        UpdateHud(HudState.Error(message));
        ScheduleHudReset(AppTimings.HudErrorResetDelay);
    }

    private void ScheduleHudReset(TimeSpan delay)
    {
        _hudResetTimer?.Stop();
        _hudResetTimer = new DispatcherTimer { Interval = delay };
        _hudResetTimer.Tick += (_, _) => { _hudResetTimer?.Stop(); UpdateHud(HudState.Idle); };
        _hudResetTimer.Start();
    }
```

(Part B — the recording/transcription pipeline + quit + Dispose — follows in Step 2.)

- [ ] **Step 2: Append Part B to `VoiceCoordinator.cs`** (the pipeline: toggle, startRecordingFlow, stopRecordingAndTranscribe, finishTranscription, quit, dispose)

```csharp
    // ====================== the dictation pipeline ======================

    /// Ports toggleRecording: synchronous reentrancy guards on the UI thread.
    public void ToggleRecording()
    {
        if (IsRecording)
        {
            if (_isStoppingRecording) return;
            _isStoppingRecording = true;
            try { StopRecordingAndTranscribe(); }
            finally { _isStoppingRecording = false; }
        }
        else
        {
            if (_isStartingRecording) return;
            _isStartingRecording = true;
            // Abandon any transcription still running for an earlier recording.
            _transcriptionCts?.Cancel();
            _transcriptionCts = null;
            _ = StartRecordingFlowAsync().ContinueWith(
                _ => _dispatcher.InvokeAsync(() => _isStartingRecording = false),
                TaskScheduler.Default);
        }
        Tray?.RebuildMenu();
    }

    /// Ports startRecordingFlow().
    private async Task StartRecordingFlowAsync()
    {
        _hudResetTimer?.Stop();

        bool granted = await _recorder.RequestPermissionAsync();
        if (!granted)
        {
            await _dispatcher.InvokeAsync(() => PermissionError.Microphone().SurfaceAndOpenSettings());
            return;
        }

        await _dispatcher.InvokeAsync(() =>
        {
            if (!_recorder.TryStart(out var error))
            {
                ShowError(error ?? "Unable to start recording.");
                return;
            }

            IsRecording = true;
            _recordingGeneration++;
            _recordingStartUtc = DateTime.UtcNow;
            UpdateHud(HudState.Recording);

            // Best-effort streaming overlay.
            var path = _recorder.CurrentPath;
            if (path is not null)
            {
                int generation = _recordingGeneration;
                _ = StartStreamingAsync(path, generation);
            }
        });
    }

    private async Task StartStreamingAsync(string path, int generation)
    {
        var session = await _engine.MakeStreamingSessionAsync();
        // Re-check on the UI thread: a stale session must never attach to a newer recording.
        await _dispatcher.InvokeAsync(async () =>
        {
            if (!IsRecording || _recordingGeneration != generation)
            {
                if (session is not null) await session.Cancel();
                return;
            }
            _streamingSession = session;
            session?.Start(path); // Start is synchronous
        });
    }

    /// Ports stopRecordingAndTranscribe().
    private void StopRecordingAndTranscribe()
    {
        if (!IsRecording) return;

        IsRecording = false;
        _lastRecordingSeconds = _recordingStartUtc is { } t ? (DateTime.UtcNow - t).TotalSeconds : 0;
        _recordingStartUtc = null;

        string? audioPath = _recorder.Stop();
        var session = _streamingSession;
        _streamingSession = null;

        // Resolve target window: current foreground (if not self) else last-non-self.
        IntPtr current = ForegroundWindowTracker.GetForegroundWindowNow();
        IntPtr target = CoordinatorDecisions.ResolveTargetWindow(current, _selfHwnd, _foreground.LastForegroundWindow);

        if (target == IntPtr.Zero)
        {
            ShowError("No target app — focus an app that accepts text before recording.");
            ScheduleHudReset(AppTimings.HudErrorResetDelay);
            if (audioPath is not null) TryDelete(audioPath);
            if (session is not null) _ = session.Cancel();
            Tray?.RebuildMenu();
            return;
        }

        UpdateHud(HudState.Transcribing);

        _transcriptionCts?.Cancel();
        _transcriptionCts = new CancellationTokenSource();
        var ct = _transcriptionCts.Token;
        _ = FinishTranscriptionAsync(audioPath, target, session, ct);
        Tray?.RebuildMenu();
    }

    /// Ports finishTranscription(audioURL:targetPID:session:).
    private async Task FinishTranscriptionAsync(string? audioPath, IntPtr target, StreamingTranscriptionSession? session, CancellationToken ct)
    {
        if (audioPath is null)
        {
            if (session is not null) await session.Cancel();
            await _dispatcher.InvokeAsync(() => { ShowError("No recording was captured."); });
            return;
        }

        try
        {
            // usable-recording guard (too-short tap).
            if (!NAudioRecorder.IsUsableRecording(audioPath))
            {
                if (session is not null) await session.Cancel();
                await _dispatcher.InvokeAsync(() =>
                {
                    UpdateHud(HudState.Error("Recording too short — please hold the hotkey longer."));
                    ScheduleHudReset(AppTimings.HudErrorResetDelay);
                });
                return;
            }

            // preparingModel wait if the engine isn't ready yet.
            if (!await _engine.IsReadyAsync())
            {
                await _dispatcher.InvokeAsync(() => UpdateHud(HudState.PreparingModel));
                await _engine.PrewarmAsync();
                if (ct.IsCancellationRequested) return;
                await _dispatcher.InvokeAsync(() => UpdateHud(HudState.Transcribing));
            }

            // streamed-vs-wholefile.
            string transcript;
            string? streamed = session is not null ? await session.Finish() : null;
            if (streamed is not null) transcript = streamed;
            else transcript = await _engine.TranscribeAsync(audioPath, ct);

            if (ct.IsCancellationRequested) return;

            // TextProcessor.Process(user dict + removeFillerWords + vocabulary) then RemoveWhisperHallucinations.
            var vocab = CustomWords.ToList();
            var userDict = TextProcessor.BuildUserDictionary(vocab);
            string processed = TextProcessor.RemoveWhisperHallucinations(
                TextProcessor.Process(transcript, _toneMode, userDict, _removeFillerWords, vocab));

            if (string.IsNullOrEmpty(processed))
            {
                await _dispatcher.InvokeAsync(() => { UpdateHud(HudState.Error("No speech detected.")); ScheduleHudReset(AppTimings.HudResetDelay); });
                return;
            }

            // Re-activate the target window, wait PasteActivationDelay, then paste.
            PasteOutcome outcome = PasteOutcome.Ok;
            await _dispatcher.InvokeAsync(() => ActivateWindow(target));
            await Task.Delay(AppTimings.PasteActivationDelay, ct);
            outcome = _paster.Paste(processed, target);

            switch (outcome)
            {
                case PasteOutcome.Ok:
                    break;
                case PasteOutcome.AccessDenied:
                    await _dispatcher.InvokeAsync(() => { ShowError("Can't paste into an elevated (admin) window. Run that app non-elevated, or focus a normal window."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
                case PasteOutcome.ClipboardLocked:
                    await _dispatcher.InvokeAsync(() => { ShowError("Clipboard is busy — try again."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
                case PasteOutcome.TargetRejected:
                    await _dispatcher.InvokeAsync(() => { ShowError("Unable to paste into the active app."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
            }

            int wordCount = processed.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
            await _dispatcher.InvokeAsync(() =>
            {
                _lastTranscriptStore.Transcript = processed;
                LastTranscript = processed;
                EditedTranscript = processed;
                _statsStore.Record(wordCount, _lastRecordingSeconds);
                TotalWordsSpoken = _statsStore.TotalWords;
                AverageWpm = _statsStore.AverageWpm;
                UpdateHud(HudState.Done(processed));
                ScheduleHudReset(AppTimings.HudResetDelay);
            });
        }
        catch (TranscriptionException tex)
        {
            await _dispatcher.InvokeAsync(() => { ShowError(tex.Message); });
        }
        catch (OperationCanceledException)
        {
            // user moved on; do nothing.
        }
        catch (Exception ex)
        {
            await _dispatcher.InvokeAsync(() => { ShowError(ex.Message); });
        }
        finally
        {
            TryDelete(audioPath); // privacy: always delete the WAV
        }
    }

    private static void ActivateWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        SetForegroundWindow(hwnd);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }

    /// Ports quitApp(): cancel streaming, delete in-flight WAV, idle HUD, shut down.
    public void QuitApp()
    {
        _hudResetTimer?.Stop();
        FlushSettings();

        if (IsRecording)
        {
            var session = _streamingSession;
            _streamingSession = null;
            if (session is not null) _ = session.Cancel();
            var abandoned = _recorder.Stop();
            if (abandoned is not null) TryDelete(abandoned);
            IsRecording = false;
        }

        UpdateHud(HudState.Idle);
        Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    public void Dispose()
    {
        _hotkey.Dispose();
        _foreground.Dispose();
        _paster.Dispose();
        (_recorder as IDisposable)?.Dispose();
        _settingsStore.Dispose();
        Tray?.Dispose();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);
}
```

> Fidelity notes / assumptions logged:
> - **Hotkey persistence:** Phase 1 `SettingsState` has no hotkey field, so a rebind lives for the session and resets to `HotkeyChord.Default` on relaunch. This matches the overview (rebindable; no schema field defined). If a future `SettingsState` adds a hotkey, persist in `SetHotkey`/`PersistSettings`. **Documented assumption.**
> - **`ActivateWindow` via `SetForegroundWindow`:** the Swift code calls `targetApp.activate()`. Windows `SetForegroundWindow` has foreground-lock rules; if it fails to focus, `Paster.Paste(text, target)` still targets the HWND directly (Phase 3's Paster takes the target HWND). The activation + `PasteActivationDelay` is best-effort, faithful to Swift.
> - **`_selfHwnd`:** captured at Start as a best-effort identity; the real "is this our window" check inside `ForegroundWindowTracker` (Phase 3) already filters self when tracking `LastForegroundWindow`. `ResolveTargetWindow` additionally guards against the *current* foreground being one of our own windows (Settings/HUD). If our Settings window is foreground at stop time, resolution falls back to `LastForegroundWindow` (the user's app) — correct.
> - **`SwapEngine` download:** macOS bundled download into "preparing"; per the overview we surface `DownloadingModel` progress explicitly (new `HudStateKind`). The download runs off the UI thread; progress marshals back. If a model change happens mid-recording it still swaps for the *next* dictation (the in-flight `finishTranscription` keeps the engine reference it captured implicitly through `_engine` — to be exact, capture `_engine` into a local at the start of `FinishTranscriptionAsync` if you want strict isolation; the Swift code reads the live manager too, so live-read is faithful).

- [ ] **Step 3: Verify build** — `dotnet build windows/JVoice.App`. If `WhisperNetTranscriptionEngine`'s constructor signature differs from Phase 2 (e.g. extra/renamed params), adjust `MakeEngine` to match the actual Phase 2 signature (it is the single point of construction). Confirm the `with`-expression on `SettingsState` works (it is a record).

- [ ] **Step 4: Commit** — `git add windows/JVoice.App/VoiceCoordinator.cs && git commit -m "feat(win-ui): VoiceCoordinator — full dictation pipeline (port of VoiceCoordinator.swift)"`

---

## Task 9: `App.xaml.cs` final wiring (DI, tray, first-run Settings, prewarm)

> Replace the Task-2 stub `OnStartup` with the real wiring. Ports `JVoiceApp`/`AppDelegate`: create the coordinator, the HUD window, the tray; wire callbacks; bootstrap launch-at-login; show Settings once on first run; flush settings on exit.

**Files:**
- Modify: `windows/JVoice.App/App.xaml.cs`

**Interfaces:**
- Consumes: `VoiceCoordinator`, `HudWindow`, `TrayIcon` (this phase); `LaunchAtLogin` first-run flag (Phase 3, via registry `HKCU\Software\JVoice\LaunchAtLoginInitialized` — but for the *first-run Settings* affordance we use a separate flag, see below).

- [ ] **Step 1: Replace `App.xaml.cs`** with the full version (keeps the `Main` from Task 2 verbatim; fills in `OnStartup`/`OnExit`):

```csharp
using System.Windows;
using Microsoft.Win32;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;

namespace JVoice.App;

public partial class App : Application
{
    private VoiceCoordinator? _coordinator;
    private TrayIcon? _tray;
    private HudWindow? _hud;

    [STAThread]
    public static int Main(string[] args)
    {
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        if (!SingleInstance.TryAcquire())
            return 0;

        try { WhisperRuntime.EnsureLoaded(); } catch { /* lazy retry in engine */ }

        var app = new App();
        app.InitializeComponent();
        int code = app.Run();
        SingleInstance.Release();
        return code;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 1) Coordinator (must be created on the UI thread — captures the dispatcher).
        _coordinator = new VoiceCoordinator();

        // 2) HUD overlay window.
        _hud = new HudWindow { OnStop = () => _coordinator.ToggleRecording() };
        _coordinator.Hud = _hud;

        // 3) Tray icon + menu wiring.
        _tray = new TrayIcon
        {
            IsRecording = () => _coordinator.IsRecording,
            LaunchAtLoginEnabled = () => _coordinator.LaunchAtLoginEnabled,
            OnToggleDictation = () => _coordinator.ToggleRecording(),
            OnOpenSettings = () => _coordinator.ShowSettings(),
            OnToggleLaunchAtLogin = () => _coordinator.ToggleLaunchAtLogin(),
            OnQuit = () => _coordinator.QuitApp(),
        };
        _coordinator.Tray = _tray;
        _tray.RebuildMenu();

        // 4) Start the pipeline (sweep orphans, hooks, hotkey, prewarm).
        _coordinator.Start();
        _coordinator.BootstrapLaunchAtLogin();

        // 5) First-run: show Settings once so the app isn't invisible.
        if (IsFirstRun())
        {
            _coordinator.ShowSettings();
            MarkFirstRunDone();
            MessageBox.Show(
                "JVoice is running in your system tray — press Ctrl + Shift + Space to dictate.",
                "JVoice", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _coordinator?.FlushSettings();
        _tray?.Dispose();
        base.OnExit(e);
    }

    // First-run flag in HKCU\Software\JVoice\UiFirstRunShown (separate from the
    // launch-at-login init flag so the two concerns don't entangle).
    private static bool IsFirstRun()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\JVoice");
        return key?.GetValue("UiFirstRunShown") is null;
    }

    private static void MarkFirstRunDone()
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\JVoice");
        key.SetValue("UiFirstRunShown", 1, RegistryValueKind.DWord);
    }
}
```

- [ ] **Step 2: Build + run** — `dotnet build windows/JVoice.App` then `dotnet run --project windows/JVoice.App`.
  - Expected on first run: tray "J" appears; Settings window opens centered; an info dialog states the tray + hotkey affordance.
  - Subsequent runs: tray only, no window (delete `HKCU\Software\JVoice\UiFirstRunShown` to re-test first-run).
  - `dotnet run --project windows/JVoice.App -- --bench foo.wav` still runs the bench and exits with no window/tray.

- [ ] **Step 3: Commit** — `git add windows/JVoice.App/App.xaml.cs && git commit -m "feat(win-ui): App wiring — coordinator/tray/HUD, first-run Settings, prewarm, --bench preserved"`

---

## Task 10: End-to-end manual dictation verification

> No new code. Run the app and verify the whole pipeline + every visual against the tokens. (Coordinator orchestration can't be unit-tested from net9.0; this is the verification gate. The pure helpers are covered by Task 8a tests.)

- [ ] **Step 1: Build the whole solution** — `dotnet build windows/JVoice.sln -c Release` → 0 errors.
- [ ] **Step 2: Run unit tests** — `dotnet test windows/JVoice.Tests` → all green (Phase 1 brain tests + the new `CoordinatorDecisionsTests`).
- [ ] **Step 3: Launch** — `dotnet run --project windows/JVoice.App`. Confirm tray "J" icon (white, reads on dark tray); first-run Settings opens once.
- [ ] **Step 4: Settings visual checklist** (compare to `DESIGN-TOKENS.md` §2):
  - 320×520 dark panel, header "JVoice" (17 bold white) + "Voice dictation controls" (11, gray).
  - 9 sections in order with the right accent dot colors: Last Transcript (blue), Keyboard Shortcut (gray, helper "Default: Ctrl + Shift + Space"), Language (indigo, English/Romanian), Voice Style (purple, Casual/Formal/Very Casual), Processing (teal, "Remove Filler Words" + subtitle + teal switch ON by default), Whisper Model (cyan, Tiny/Base/Small/Large + guidance caption), Custom Words (orange, input "Add word (e.g. VS Code)" + Add), Stats (green, two columns total words / avg WPM), footer (Restore Default Settings / Quit JVoice, both red).
  - Click a segment in each picker → selection updates and persists (close+reopen Settings; selection survives → settings.json written).
  - Add a custom word → appears in the list with a red remove glyph; remove it → gone. (Confirms `AddCustomWord`/`RemoveCustomWord` + vocab push.)
  - Click the hotkey recorder → "Press a key…" → press Ctrl+Alt+J → shows the new chord; press the new chord globally → toggles recording. Press Backspace in capture → resets to Ctrl+Shift+Space.
- [ ] **Step 5: HUD state checklist** (focus a text field in Notepad/Word first):
  - Press Ctrl+Shift+Space → **blue Recording pill** bottom-center, 24px up, spinning arc + pulsing aura + visible stop button. Click the stop button (only hittable in Recording) → stops.
  - During processing → **cyan Transcribing pill** ("Transcribing / Processing…"). On first-ever use of a not-downloaded model → **purple Downloading pill** with %, then **purple Preparing pill** with a ticking m:ss, then transcribing.
  - On success → **green Done pill** ("Pasted") for ~1s, then fades to idle; the text is pasted into Notepad. 
  - Tap-and-release too fast → **orange Error pill** ("Recording too short…") for ~3s.
  - Verify the pill is click-through except while recording (click the desktop behind the Transcribing/Done pill — the click lands behind it).
  - Verify the tray icon mirrors: red mic while recording, cyan waveform while transcribing/preparing/downloading, "J" otherwise.
- [ ] **Step 6: End-to-end accuracy** — dictate "hey um can we move practice to thursday at five" into Notepad with RemoveFillerWords ON, Casual tone → pasted text has no "um", reads naturally. Add custom word "JVoice", say "jay voice" → pastes "JVoice" (phonetic correction works through the real pipeline).
- [ ] **Step 7: Mic-denied path** — revoke desktop-app mic access (Windows Settings → Privacy → Microphone), press the hotkey → mic-denied error surfaces and Windows Settings opens to the microphone page (`ms-settings:privacy-microphone`). Re-enable.
- [ ] **Step 8: Quit** — tray menu → Quit JVoice → app exits cleanly, tray icon disappears, no orphaned `jvoice-*.wav` in `%TEMP%` (privacy). Relaunch → starts silently to tray (no first-run dialog).
- [ ] **Step 9: `--bench` regression** — `dotnet run --project windows/JVoice.App -- --bench <a 16kHz mono wav>` prints the Phase 2 bench output and exits 0 with no window/tray.
- [ ] **Step 10: Commit any fixes** found during verification, then a final `git commit -m "test(win-ui): end-to-end dictation verification pass"` (or fold fixes into the relevant task commits).

---

## §Future (post-port enhancements, not in scope)

- Multi-monitor HUD: position on the monitor containing the cursor (v1 uses the primary work area, matching macOS `NSScreen.main`).
- Replace MDL2 ring center glyphs with drawn vector glyphs (mic/gear/waveform/down-arrow) reusing the SkiaSharp shapes for exact icon fidelity.
- Persist the rebound hotkey (requires a `Hotkey` field added to `SettingsState`'s schema — bump `SchemaVersion`).
- DWM dark title bar on the Settings window.
- A larger always-visible main window if David wants more than tray-first (overview §6.5).

---

## Self-Review — every Swift UI element + every VoiceCoordinator behavior → a task

**HUDView.swift elements:**
| Swift element | Phase 4 home | ✓ |
| --- | --- | --- |
| `pillBackground` (fill 7,7,14; border accent@0.22; top-leading gradient accent@0.06; glows r16/r32; drop shadow black@0.35 r12 y6) | `HudView.xaml` PillBody + GlowInner/GlowOuter + overlay gradient + DropShadowEffect | ✓ T5 |
| `OrbitalRing` pulsing aura (36×36 radial accent@0.18, scale 0.9→1.05 easeInOut 1.8s autoreverse) | `RingAura` + pulse Storyboard (SineEase, 1.8s, AutoReverse, Forever) | ✓ T5 |
| `OrbitalRing` spinning arc (28×28 trim 0–0.28 lineWidth1.5 round-cap, 360°/4.0s, glows r3/r6) | `RingArc` ArcSegment(100.8°) + spin Storyboard 4.0s + DropShadowEffect | ✓ T5 |
| `OrbitalRing` center icon (size 11 semibold, glows r4/r10) | `RingGlyph` (MDL2, 13px) + DropShadowEffect | ✓ T5 |
| `StopButton` (22×22 r6 fill stopRed@0.12 border@0.30, inner 7×7 r2 fill stopRed) + PanelPressableButtonStyle | `StopButton` Grid + `PressableButton` style | ✓ T3/T5 |
| `RecordingPill` (blue, mic, "Recording"/"Listening…", stop) | `HudView.Apply(Recording)` | ✓ T5 |
| `PreparingModelPill` (purple, gear, elapsed m:ss timer) | `Apply(PreparingModel)` + DispatcherTimer | ✓ T5 |
| **DownloadingModel** (new; purple, progress %) | `Apply(DownloadingModel)` | ✓ T5 |
| `TranscribingPill` (cyan, waveform, "Transcribing"/"Processing…") | `Apply(Transcribing)` | ✓ T5 |
| `StatusPill` done (green, checkmark, "Pasted") / error (orange, triangle) | `Apply(Done/Error)` + Disc | ✓ T5 |
| **HUDWindow.swift** (borderless nonactivating panel, level above status, ignoresMouseEvents=(state≠recording), bottom-center +24, sizeToFit) | `HudWindow.cs` (WindowStyle None + AllowsTransparency + WS_EX_NOACTIVATE/TOOLWINDOW/TRANSPARENT toggle + PositionBottomCenter + SizeToContent) | ✓ T5 |
| **HUDLayout.swift** (220×50 min) | MinWidth/MinHeight 220/50 on PillBody | ✓ T5 |

**SettingsView.swift elements:**
| Swift element | Phase 4 home | ✓ |
| --- | --- | --- |
| `SettingsPalette` (all colors) | `JVoicePalette.xaml` brushes | ✓ T3 |
| `DarkSection` (r10 card, 5×5 dot+glow, UPPER 9.5 bold header, 0.5px divider, 12 pad) | `DarkSection.xaml(.cs)` | ✓ T6 |
| `DarkPrimaryButtonStyle` / `DarkDestructiveButtonStyle` | `DarkPrimaryButton`/`DarkDestructiveButton` styles | ✓ T3 |
| Header "JVoice" + subtitle (reworded) | SettingsView header | ✓ T6 |
| 1 Last Transcript (editor + Fix/Revert + empty state) | DarkSection 1 + OnFix/OnRevert | ✓ T6 |
| 2 Keyboard Shortcut (recorder + "Default: …" reworded) | DarkSection 2 + `HotkeyRecorder` | ✓ T6 |
| 3 Language (segmented English/Romanian) | DarkSection 3 + Segment styles | ✓ T6 |
| 4 Voice Style (segmented Casual/Formal/Very Casual) | DarkSection 4 | ✓ T6 |
| 5 Processing (Remove Filler Words + subtitle + teal switch) | DarkSection 5 + `TealSwitch` | ✓ T6 |
| 6 Whisper Model (segmented + guidance caption) | DarkSection 6 + `ModelGuidance` | ✓ T6 |
| 7 Custom Words (list + remove + input + Add + empty state) | DarkSection 7 + handlers | ✓ T6 |
| 8 Stats (two columns, monospace big numbers + glows) | DarkSection 8 | ✓ T6 |
| 9 Footer (Restore Defaults confirm + Quit) | footer Grid + handlers | ✓ T6 |
| **SettingsWindow.swift** (title "Settings", centered, activate-on-show, not released on close) | `SettingsWindow.cs` (CenterScreen, ShowOrActivate, Closing→Hide) | ✓ T6 |

**MenuBarController.swift elements:**
| Swift element | Phase 4 home | ✓ |
| --- | --- | --- |
| 3-state status icon (idle "J" template / red mic / cyan waveform) | `TrayIcon.SetActivity` + 3 PNGs | ✓ T4/T7 |
| Menu order (Start/Stop Dictation, sep, Settings…, Launch at Login ✓, sep, Quit JVoice) | `TrayIcon.RebuildMenu` | ✓ T7 |
| `menuNeedsUpdate` (rebuild title + checkmark each open) | `TrayContextMenuOpen` → RebuildMenu | ✓ T7 |
| `makeStatusIcon` (bold "J") | `tray-idle.png` from icon tool | ✓ T4 |

**App icon:**
| Swift `generate-icon.swift` | Phase 4 home | ✓ |
| --- | --- | --- |
| squircle 80.5%, radius×0.2237, gradient #0A0A0A→#1C1C1E, inner edge white@5%, "J" Black 0.60 fill #EDEDF2 glow white@30% blur 0.035 | `tools/generate-icon/Program.cs` `RenderAppIcon` | ✓ T4 |
| multi-size .ico | `BuildIco` (16/32/48/64/128/256) | ✓ T4 |

**VoiceCoordinator.swift behaviors:**
| Swift behavior | Phase 4 home | ✓ |
| --- | --- | --- |
| `@Published` props (toneMode/whisperModel/language/customWords/removeFillerWords/isRecording/hudState/stats/lastTranscript/canRevert/launchAtLogin) | `INotifyPropertyChanged` props | ✓ T8 |
| `start()` (sweep orphans, frontmost observer, hotkey register, status item, prewarm) | `Start()` | ✓ T8 |
| `bootstrapLaunchAtLogin` / `setLaunchAtLogin` | `BootstrapLaunchAtLogin`/`SetLaunchAtLogin` | ✓ T8 |
| `installFrontmostObserver` (last non-self) | `ForegroundWindowTracker` (P3) + `_foreground` | ✓ T8 |
| `toggleRecording` (isStarting/isStopping guards, cancel stale transcription) | `ToggleRecording` | ✓ T8 |
| `startRecordingFlow` (permission, start, isRecording, generation++, HUD recording, streaming overlay) | `StartRecordingFlowAsync` + `StartStreamingAsync` | ✓ T8 |
| `recordingGeneration` stale-session guard | `_recordingGeneration` re-check after await | ✓ T8 |
| `stopRecordingAndTranscribe` (duration, stop, target resolve, transcribing HUD, finish task) | `StopRecordingAndTranscribe` + `CoordinatorDecisions.ResolveTargetWindow` | ✓ T8/T8a |
| `finishTranscription` (usable check, preparingModel wait, streamed-vs-wholefile, TextProcessor.Process + RemoveWhisperHallucinations, activate+delay+Paste, PasteOutcome handling, stats, last-transcript, done+reset) | `FinishTranscriptionAsync` | ✓ T8 |
| `updateHUD` (HUD + tray mirror) | `UpdateHud` + `CoordinatorDecisions.HudToTray` | ✓ T8/T8a |
| `showError` + `scheduleHUDReset` (1s / 3s) | `ShowError`/`ScheduleHudReset` + `HudResetDelayMs` | ✓ T8/T8a |
| `persistSettings` / `flushSettings` / `resetSettings` (isInitializing guard) | `PersistSettings`/`FlushSettings`/`ResetSettings` | ✓ T8 |
| engine swap on model/language change + vocab re-push (TranscriptionManager fold-in) | `SwapEngine` + `UpdateVocabularyAsync` | ✓ T8 |
| `addCustomWord`/`removeCustomWord` | `AddCustomWord`/`RemoveCustomWord` | ✓ T8 |
| `fixLastTranscript`/`revertLastFix`/`clearRevertBuffer` | same names | ✓ T8 |
| `prewarm` | `_engine.PrewarmAsync()` in Start/SwapEngine | ✓ T8 |
| `quitApp` (cancel streaming, delete in-flight WAV, idle HUD, terminate) | `QuitApp` | ✓ T8 |
| HUD reset timers | `DispatcherTimer _hudResetTimer` | ✓ T8 |
| `makeTranscriptionEngine` (WhisperKit vs FileBacked) | `MakeEngine` (WhisperNet vs FileBacked fallback) | ✓ T8 |
| `JVoiceApp`/`AppDelegate` (single instance, DI, first-run, flush on terminate) | `App.xaml.cs` | ✓ T2/T9 |
| `BenchRunner.shouldRun` before UI | `App.Main` --bench branch | ✓ T2/T9 |

No Swift UI element or coordinator behavior is unmapped.

---

## Type-consistency check (vs overview §4 / Phases 1–3)

- **Namespaces/types match overview §4.8:** `JVoice.App.UI`, `JVoice.App`; `VoiceCoordinator`, `HudWindow : Window` + `HudView` UserControl, `SettingsWindow : Window` + `SettingsView` UserControl, `TrayIcon` (wraps H.NotifyIcon `TaskbarIcon`), `JVoicePalette` (merged `ResourceDictionary`), pressable-button `Style` (`PressableButton`), `App`/`App.xaml`. ✓
- **Phase 1 consumed exactly:** `HudState`/`HudStateKind` (factories + `Headline`/`Subtitle`/`IsVisible`/`IsBusy`/`IsTerminal`/`Kind`/`Payload`/`Progress`), `ToneStyle`, `TranscriptionLanguage` (+`.Guidance()` on `WhisperModelOption`), `WhisperModelOption`, `SettingsState` (record `with`), `AppTimings` (TimeSpan `PasteActivationDelay`/`HudResetDelay`/`HudErrorResetDelay`), `TextProcessor.Process`/`BuildUserDictionary`/`ExtractCorrections`/`RemoveWhisperHallucinations`, `ITranscriptionEngine` (default-method surface), `StreamingTranscriptionSession` (`Start(string)` sync, `Finish()`→`Task<string?>`, `Cancel()`→`Task`), `FileBackedTranscriptionEngine` (parameterless), `TranscriptionException` (`Message`), `CoordinatorDecisions`/`TrayIconActivity` (added this phase to Core). ✓
- **Phase 2 consumed exactly:** `BenchRunner.ShouldRun`/`RunAndExit`, `WhisperRuntime.EnsureLoaded`, `WhisperNetTranscriptionEngine(model, language, vocabulary, useVocabularyPrompt, store)`, `WhisperModelStore` (`CompleteModelPath`, `EnsureAsync(model, IProgress<double>, ct)`). The csproj keeps Phase 2's pinned `Whisper.net*` `PackageReference`s; `App.Main` preserves `--bench` before WPF. **If Phase 2's engine ctor differs, adjust `MakeEngine` only.** ✓
- **Phase 3 consumed exactly:** `IAudioRecorder`/`NAudioRecorder` (`TryStart(out string?)`, `Stop()→string?`, `CurrentPath`, `RequestPermissionAsync()`, static `SweepOrphanedRecordings`/`IsUsableRecording`, `Failed` event), `Paster.Paste(string, IntPtr)`→`PasteOutcome{Ok,AccessDenied,ClipboardLocked,TargetRejected}`, `GlobalHotkey` (`Triggered`, `Register(HotkeyChord)`), `HotkeyChord`/`HotkeyModifiers` (`Default`, `Format()`, `TryParse`), `ForegroundWindowTracker` (`Start`/`LastForegroundWindow`/static `GetForegroundWindowNow`), `LaunchAtLogin` (`IsEnabled`, `SetEnabled`, `PerformFirstRunEnableIfNeeded`), `SettingsStore` (`State`, `Update(Func<SettingsState,SettingsState>)`, `Reset`, `Flush`, `Changed`), `StatsStore` (`TotalWords`, `AverageWpm`, `Record(int,double)`), `LastTranscriptStore` (`Transcript`), `PermissionError.Microphone().SurfaceAndOpenSettings()`, `SystemActions.ErrorHandler`, `SingleInstance.TryAcquire/Release`. ✓
- **Copy deltas applied:** subtitle "Voice dictation controls", "Default: Ctrl + Shift + Space", `ms-settings:privacy-microphone`, first-run affordance string; all other strings verbatim. ✓
- **Concurrency:** all platform callbacks marshalled via `_dispatcher.InvokeAsync`; `_recordingGeneration` re-checked after the streaming-session await; HUD/UI mutated only on the UI thread. ✓

If any signature mismatch surfaces at build time, the single adaptation point is the consuming call site (`MakeEngine`, `_recorder.*`, `_paster.Paste`, `_settingsStore.Update`) — adjust to the real Phase 1–3 signature; do not alter Phase 1–3 source.

---

*Phase 4 complete when Task 10's checklist passes. Next: Phase 5 (`2026-06-22-windows-port-05-packaging.md`).*
