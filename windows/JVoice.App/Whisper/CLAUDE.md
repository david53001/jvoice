# App / Whisper — the on-device speech engine

Wraps **Whisper.net** (managed whisper.cpp, GGML models) behind `Core`'s `ITranscriptionEngine`,
with CUDA/Vulkan GPU + CPU fallback. The macOS app uses WhisperKit/CoreML; this is the Windows
replacement.

## Key files
- `WhisperNetTranscriptionEngine.cs` — implements `ITranscriptionEngine`; runs the decode, applies
  the duration-gated options, hands results to the brain (`Core/Text`).
- `WhisperRuntime.cs` — picks/loads the native runtime (GPU vs CPU fallback).
- `WhisperModelStore.cs` — locates/downloads the GGML model. ⚠ **This is the ONLY runtime network
  call in the entire app** (the one-time model download). Privacy invariant: zero network at
  runtime otherwise. Don't add telemetry/network here.
- `BenchRunner.cs` — the hidden `--bench` CLI (speed + vocab/streaming checks on-device).

## Invariant (do not break)
Do **not** add digital gain to the transcription audio to "fix accuracy" — whisper normalizes
log-mel energy; gain scales noise equally (no SNR win) and risks clipping (root `CLAUDE.md` §7 #22;
memory `win-mic-low-capture-level`). The real levers are mic SNR + the `Core/Text` pipeline.

## Verify
`JVoice.exe --bench <wav> [--model …] [--stream]` on-device; the engine contract is exercised
offline by `FileBackedEngineTests` (no GPU).
