# JVoice.Core — the portable "brain"

Pure, platform-agnostic transcription logic. **No Win32, no WPF, no NAudio, no Whisper.net** —
this assembly references nothing platform-specific, so every rule here is unit-testable in
isolation and ports 1:1 from the macOS Swift app (`../../Sources/JVoice/`).

## Prime directive
Every constant and threshold in this project is **ported verbatim from the macOS source** and
**locked by `JVoice.Tests`** (xUnit, translated from the Swift tests). macOS is the source of
truth for the accuracy brain. If you change a number here you are diverging from macOS — don't,
unless that's the explicit task, and update the matching test in the same commit.

## Areas (each `@`-mentionable, each has its own brief)
- `Text/` — the custom-word accuracy + anti-hallucination pipeline.
- `Audio/` — streaming-while-recording: chunking, growing-WAV parsing, the no-data-loss guarantee.
- `Transcription/` — the `ITranscriptionEngine` seam the platform plugs a real Whisper engine into.
- `Models/` — domain types, enums, and the JSON DTOs persisted to disk.
- `Policy/` — pure cross-cutting decision logic (coordinator decisions, hotkey/game gating, stats, timings).

## Verify changes
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` — 865 tests, must stay green.
- `dotnet build windows/JVoice.sln -c Release` — 0 errors.

## Layout note
Folders here are organizational only. C# namespaces are declared in-file (e.g. `Policy/` files
are still `namespace JVoice.Core`), so moving a file between folders never changes a `using`.
