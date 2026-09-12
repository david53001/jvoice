# tools — standalone dev CLIs

Small, separate console projects for dogfooding / diagnostics. Each is its own `.csproj` and builds
independently; only some are wired into `JVoice.sln`.

- `whisper-smoke/` — minimal on-device Whisper.net decode (verifies the model/runtime works, GPU + CPU).
- `hotkey-probe/` — exercises the global hotkey hook in isolation. **Not in the .sln** — build it directly.
- `nospeech-probe/` — feeds clips to check the model-driven no-speech path.
- `generate-icon/` — regenerates the app icon (SkiaSharp); the Windows analog of
  `scripts/generate-icon.swift`.
- `audio-input-probe/` — **the "is the microphone actually sending audio?" tool** (§7 #46). Compiles the
  REAL `AudioInputRouter` / `NAudioRecorder` / `CaptureSignal`, so it reports what the shipping app does,
  not a copy. No args = passive enumeration (every capture endpoint with mute state, master level, form
  factor, mix format, + which one the router picks, + the inactive/unplugged ones). `--record <s> [--all]`
  opens endpoints directly and grades peak/RMS/non-zero. `--recorder <s>` is the end-to-end check: reads
  `settings.json`, records through the real recorder, grades with the real
  `CaptureSignal`/`SilentCaptureDetector`. `--measure <wav…>` replays existing captures through the same
  decision with **no microphone needed**. Start here whenever dictation returns nothing or gibberish —
  a virtual mic (Voicemod/NVIDIA Broadcast/VB-Cable/Wave Link) holding the system default and emitting
  digital silence is the failure this was written for.

## Note
These are throwaway / diagnostic, **not shipped**. They may reference `JVoice.Core` / `JVoice.App`
types; keep them building, but they aren't part of the product surface.
