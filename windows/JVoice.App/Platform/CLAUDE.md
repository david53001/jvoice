# App / Platform — OS integration

The Win32-facing glue between the portable brain and Windows. Split into three `@`-mentionable
sub-areas:
- `Capture/` — microphone capture & input-device routing (NAudio).
- `Persistence/` — reading/writing user state to disk (settings, stats, transcripts).
- `System/` — everything else OS: hotkey hook, paste, elevation, game detection, display,
  single-instance, system actions.

## Layout note (important)
These files were split into the subfolders above during the 2026-06-26 reorg but **keep
`namespace JVoice.App.Platform`** — C# namespaces are declared in-file, so the folders are
organizational only and **no `using` changed**. Don't "fix" the namespaces to match folders without
updating every consumer; that's a separate cross-cutting rename, not a layout change.

## Verify
Logic-only pieces are covered by `JVoice.Tests`; device/OS behavior is verified by dogfood
(`docs/launch/windows-dogfood-checklist.md`).
