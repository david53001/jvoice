# tools — standalone dev CLIs

Small, separate console projects for dogfooding / diagnostics. Each is its own `.csproj` and builds
independently; only some are wired into `JVoice.sln`.

- `whisper-smoke/` — minimal on-device Whisper.net decode (verifies the model/runtime works, GPU + CPU).
- `hotkey-probe/` — exercises the global hotkey hook in isolation. **Not in the .sln** — build it directly.
- `nospeech-probe/` — feeds clips to check the model-driven no-speech path.
- `generate-icon/` — regenerates the app icon (SkiaSharp); the Windows analog of
  `scripts/generate-icon.swift`.

## Note
These are throwaway / diagnostic, **not shipped**. They may reference `JVoice.Core` / `JVoice.App`
types; keep them building, but they aren't part of the product surface.
