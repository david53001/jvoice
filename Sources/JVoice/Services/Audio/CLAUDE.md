# Services/Audio — recording & microphone routing

Captures microphone audio to a WAV file for the transcription pipeline.

## Files
- `RecordingManager.swift` — wraps `AVAudioRecorder` to capture the microphone to a WAV file.
  Sweeps orphaned WAV files left behind by a crash or interruption. **Latency contract (2026-09-12):**
  `startRecording()` is `async` — the `AVAudioRecorder` create/prepare/`record()` (20–90 ms, a
  cross-process call into the audio daemon) runs in a detached task so the recording pill, which the
  coordinator shows BEFORE calling this, never has its first frames blocked; a `startGeneration`
  counter makes a stop/quit that races the open discard the recorder + file. `requestPermission()`
  is a synchronous status lookup unless the authorization is still `.notDetermined` (first run).
  `prewarmAudioStack()` (called at launch) pays the cold first TCC lookup (TCC = macOS's
  Transparency, Consent, and Control privacy-permission database; ~35 ms) and first
  Core Audio device enumeration (~55 ms) off the main thread instead of on the first press.
- `AudioInputRouter.swift` — keeps Bluetooth headphones on their high-quality A2DP output profile
  by recording from the built-in microphone, instead of letting macOS switch the headphones into
  the low-quality two-way headset profile (HFP) that recording would otherwise force.

## How to verify changes here
- `swift build` must pass. The relevant tests (`AudioInputRouterTests`,
  `RecordingManagerInterruptionTests`, `RecordingManagerDelegateTests`) run in CI
  (`.github/workflows/test.yml`); they compile locally but do not execute on this machine.
