# Platform / Capture — microphone capture & routing

Turns the mic into a growing WAV the streaming brain (`Core/Audio`) consumes.

## Key files
- `IAudioRecorder.cs` — capture abstraction (so the coordinator/tests don't bind to NAudio).
- `NAudioRecorder.cs` — the NAudio implementation; writes the growing WAV and sweeps orphan WAVs.
  Mirrors macOS `RecordingManager`.
- `AudioInputRouter.cs` — keeps Bluetooth mics on A2DP by recording from the built-in/default input
  instead (pairs with the pure `Core/Audio/BluetoothDevicePolicy`).

## Traps
- Don't add gain to the captured audio to chase accuracy (see the App/Whisper brief + memory
  `win-mic-low-capture-level`). Capture clean PCM; the brain does the rest.
- **Never dispose/join the WASAPI capture while holding `_gate`** (root `CLAUDE.md` §7 #37): NAudio's
  `WasapiCapture.Dispose` joins the capture thread, and `OnDataAvailable` takes `_gate` — dispose-under-
  gate is the deadlock that froze the app on a stop press. Teardown = detach under the gate, dispose
  outside (`DetachLocked`/`DisposeDetached`); repro seam `JVOICE_TEST_SLOW_CAPTURE_MS=200`.

## Verify
Dogfood the live loop; `BluetoothDevicePolicyTests` covers the routing policy (the pure half).
