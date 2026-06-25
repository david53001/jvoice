# Services/Audio — recording & microphone routing

Captures microphone audio to a WAV file for the transcription pipeline.

## Files
- `RecordingManager.swift` — wraps `AVAudioRecorder` to capture the microphone to a WAV file.
  Sweeps orphaned WAV files left behind by a crash or interruption.
- `AudioInputRouter.swift` — keeps Bluetooth headphones on their high-quality A2DP output profile
  by recording from the built-in microphone, instead of letting macOS switch the headphones into
  the low-quality two-way headset profile (HFP) that recording would otherwise force.

## How to verify changes here
- `swift build` must pass. The relevant tests (`AudioInputRouterTests`,
  `RecordingManagerInterruptionTests`, `RecordingManagerDelegateTests`) run in CI
  (`.github/workflows/test.yml`); they compile locally but do not execute on this machine.
