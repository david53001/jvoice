# JVoice.App — the Windows shell

The WPF app that wraps the portable `JVoice.Core` brain: tray app, HUD, settings, global hotkey,
capture, paste, persistence, and the Whisper engine. `win-x64`, .NET 9, WinExe.

## Orchestrator
`VoiceCoordinator.cs` (kept at the project root) is the central flow:
hotkey → record → transcribe → process → paste, driving `HudState`. Mirrors macOS
`VoiceCoordinator.swift`.

## Areas (each has its own brief)
- `Whisper/` — the real Whisper.net engine + model store (the ONE network call).
- `UI/` — WPF HUD, Settings, tray (the monochrome black-&-white redesign).
- `Platform/` — OS integration, split into `Capture/`, `Persistence/`, `System/`.

## Path-coupled files — DO NOT move (referenced by path in `JVoice.App.csproj`)
`App.xaml`, `App.xaml.cs`, `app.manifest`, and `Assets/*` (`JVoice.ico`, `tray-*.png`). The
`.csproj` names these explicitly (ApplicationDefinition / Page / Resource / ApplicationManifest /
ApplicationIcon). The `.cs` source files are picked up by SDK glob and may be reorganized freely.

## Build gotcha (running app locks output)
If JVoice is running, `dotnet build` of this project fails with MSB3021/MSB3026 "file in use"
copying `JVoice.Core.dll` into `bin\` — that's a **file lock, not a compile error**. Either close
the tray app, or build to a throwaway dir:
`dotnet build windows/JVoice.App/JVoice.App.csproj -c Release -o <tmp>`.

## Verify
`dotnet build windows/JVoice.App/JVoice.App.csproj -c Release` (0 errors) ·
`dotnet test windows/JVoice.Tests` (880 green) ·
`JVoice.exe --hud-preview <state>` / `--settings-render <png>` / `--hud-render <png>` for visuals.
