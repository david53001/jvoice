# JVoice — Windows port (area index)

Native Windows port of JVoice (the macOS menu-bar voice-dictation app). .NET 9, WPF,
`win-x64`. Speech via Whisper.net (whisper.cpp / GGML) with CUDA/Vulkan GPU + a CPU
fallback. The macOS Swift app (`../Sources/`) is the **read-only** source-of-truth for the
accuracy "brain".

Full as-built state, pinned versions, and every deviation live in
`../docs/HANDOFF-WINDOWS.md`. Hard rules + the Windows section are in `../CLAUDE.md`.

## Projects & `@`-mentionable areas (each has its own `CLAUDE.md`)
- `JVoice.Core/` — the portable brain (no Win32). Sub-areas: `Text/`, `Audio/`,
  `Transcription/`, `Models/`, `Policy/`.
- `JVoice.App/` — the WPF Windows shell. Sub-areas: `Whisper/`, `UI/`,
  `Platform/{Capture,Persistence,System}/`. Orchestrator: `VoiceCoordinator.cs`.
- `JVoice.Tests/` — xUnit suite (819 tests) translated from the Swift tests; locks the brain.
- `tools/` — standalone probe/utility CLIs (whisper-smoke, hotkey-probe, nospeech-probe,
  capture-stop-probe, generate-icon).

## Build / test
- `dotnet build windows/JVoice.sln -c Release` — 0 errors.
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` — 819 green.
- **Gotcha:** if the tray app is running it locks `JVoice.Core.dll` in `JVoice.App\bin`, so a
  build reports MSB3021/MSB3026 *copy* errors (not compile errors). Close it, or build to a
  throwaway dir with `-o <tmp>`.

## Layout invariant (read before "tidying")
Areas are **folders**; C# namespaces are declared **in-file**. The 2026-06-26 reorg moved
files into area folders **without** changing namespaces, so folder ≠ namespace is expected and
harmless (e.g. `JVoice.App/Platform/System/*.cs` are still `namespace JVoice.App.Platform`).
Don't realign namespaces to folders as a drive-by — that's a cross-cutting rename touching
every `using`, not a layout change.
