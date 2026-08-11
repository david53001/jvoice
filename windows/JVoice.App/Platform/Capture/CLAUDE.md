# Platform / Capture — microphone capture & routing

Turns the mic into a growing WAV the streaming brain (`Core/Audio`) consumes.

## Key files
- `IAudioRecorder.cs` — capture abstraction (so the coordinator/tests don't bind to NAudio).
- `NAudioRecorder.cs` — the NAudio implementation; writes the growing WAV and sweeps orphan WAVs.
  Mirrors macOS `RecordingManager`.
- `AudioInputRouter.cs` — resolves WHICH endpoint to open: the user's Settings pick first, else the
  Bluetooth-avoidance fallback that keeps BT mics on A2DP (pairs with the pure
  `Core/Audio/CaptureDeviceSelection` + `BluetoothDevicePolicy`). Also `ListInputDevices()` for the
  Settings picker and `ResolveDeviceName()` for error messages.
- `CaptureSignal.cs` — measures a finished WAV's exact-zero sample ratio for the dead-input check
  (pairs with the pure `Core/Policy/SilentCaptureDetector`).

## Traps
- Don't add gain to the captured audio to chase accuracy (see the App/Whisper brief + memory
  `win-mic-low-capture-level`). Capture clean PCM; the brain does the rest.
- **"No speech / gibberish" is often the INPUT DEVICE, not the brain** (root `CLAUDE.md` §7 #46). The
  system default capture endpoint is not reliably a real microphone — virtual devices (Voicemod, NVIDIA
  Broadcast, VB-Cable, Elgato Wave Link, OBS) commonly own it and emit **bit-exact digital silence** when
  their app isn't running, and whisper turns silence into hallucinated filler. Run
  `windows/tools/audio-input-probe` FIRST; check `rawRms=0.0000` in diagnostic.log. Don't debug the
  decoder until you've proved real samples reached the WAV.
- **Never dispose/join the WASAPI capture while holding `_gate`** (root `CLAUDE.md` §7 #37): NAudio's
  `WasapiCapture.Dispose` joins the capture thread, and `OnDataAvailable` takes `_gate` — dispose-under-
  gate is the deadlock that froze the app on a stop press. Teardown = detach under the gate, dispose
  outside (`DetachLocked`/`DisposeDetached`); repro seam `JVOICE_TEST_SLOW_CAPTURE_MS=200`.

## Verify
Dogfood the live loop; `BluetoothDevicePolicyTests` covers the routing policy (the pure half).
