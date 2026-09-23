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
  **Spare recorder:** `prepareSpareRecorder()` (at launch and after every stop) creates and
  `prepareToRecord()`s the next `AVAudioRecorder` while idle — measured 20–55 ms, and it engages
  NO device while idle (verified via `kAudioDevicePropertyDeviceIsRunningSomewhere`) — leaving
  only `record()` (~60–105 ms, the Core Audio HAL start) on the press. `discardSpareRecorder()` on
  quit. **Not used after a Bluetooth redirect** (fixed 2026-09-23): a spare prepared while the
  headset was the default input follows the redirect only once the default-input change reaches
  its audio queue, and `record()` 0.2 ms after the switch sometimes won that race and opened the
  headset's mic (HFP/SCO — music jumps; 2 of 34 presses in the logs). So a press that redirects
  drops the spare and creates a fresh recorder after the switch (the 1.1.0 ordering, ~20–55 ms
  slower to open the mic — the pill still appears instantly), and a stop after a redirected press
  prepares no spare. Still timing-based (bad presses: ~16 ms switch→`record()`; fresh open: 20–55 ms
  of create + prepare in between) — the robust fix is capturing from the built-in mic directly
  (AVAudioEngine/AUHAL) without changing the system default input. Check a press with
  `/usr/bin/log show --last 10m --predicate 'process == "coreaudiod"' | grep -E "HFPInputShimDevice: StartIO"`
  — any hit during a dictation means the headset's mic was opened.
- `AudioInputRouter.swift` — keeps Bluetooth headphones on their high-quality A2DP output profile
  by recording from the built-in microphone, instead of letting macOS switch the headphones into
  the low-quality two-way headset profile (HFP) that recording would otherwise force.

## How to verify changes here
- `swift build` must pass. The relevant tests (`AudioInputRouterTests`,
  `RecordingManagerInterruptionTests`, `RecordingManagerDelegateTests`) run in CI
  (`.github/workflows/test.yml`); they compile locally but do not execute on this machine.
