# Core / Audio — streaming-while-recording (pure logic)

Decides how a growing recording is cut into chunks and decoded live, with a hard
**no-data-loss guarantee**. Pure logic only — no audio-device access (that lives in
`JVoice.App/Platform/Capture`).

## Key files
- `WavTail.cs` — parser for a growing WAV file (reads newly-appended PCM as recording continues).
- `ChunkPlanner.cs` — pure silence-cut chunk policy (where to split).
- `StreamingTranscriptionSession.cs` — decodes completed chunks during recording. **Any failure,
  or an empty non-silent chunk, falls back to whole-file transcription — it NEVER silently drops
  audio.** Also no longer drops a quiet sentence *tail*.
- `HighPassSilence.cs` — Windows-only, now **metrics-only** (the no-speech decision moved to
  `Core/Text/NonSpeechAnnotation`).
- `BluetoothDevicePolicy.cs` — pure policy for keeping Bluetooth mics on A2DP (record from the
  built-in input instead). The device-side action lives in `Platform/Capture/AudioInputRouter`.

## Invariant (do not break)
The streaming path must never lose speech. Empty non-silent chunk ⇒ whole-file fallback. Verified
by `scripts/verify-streaming.sh` on macOS and `StreamingSessionTests` here.

## Verify
`dotnet test windows/JVoice.Tests` — StreamingSessionTests, ChunkPlannerTests, WavTailTests,
HighPassSilenceTests, BluetoothDevicePolicyTests.
