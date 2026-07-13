# Core / Audio — streaming-while-recording (pure logic)

Decides how a growing recording is cut into chunks and decoded live, with a hard
**no-data-loss guarantee**. Pure logic only — no audio-device access (that lives in
`JVoice.App/Platform/Capture`).

## Key files
- `WavTail.cs` — parser for a growing WAV file (reads newly-appended PCM as recording continues).
- `ChunkPlanner.cs` — pure silence-cut chunk policy (where to split).
- `StreamingTranscriptionSession.cs` — decodes completed chunks during recording. **Any failure,
  or an empty non-silent chunk, falls back to whole-file transcription — it NEVER silently drops
  audio.** Two Windows divergences from Swift (both David's-mic bugs — his speech reads below the
  0.005 silence floor): a quiet *final tail* forces the whole-file fallback (2026-06-23), and
  *silent-classified mid-stream chunks are DECODED, never dropped unheard* — the model decides:
  empty ⇒ confirmed silence, skip; non-empty ⇒ rescued speech (2026-07-03, §7 #39). Optional `log`
  callback for diagnostics (the app wires `DiagnosticLog.Write`).
- `HighPassSilence.cs` — Windows-only, now **metrics-only** (the no-speech decision moved to
  `Core/Text/NonSpeechAnnotation`).
- `BluetoothDevicePolicy.cs` — pure policy for keeping Bluetooth mics on A2DP (record from the
  built-in input instead). The device-side action lives in `Platform/Capture/AudioInputRouter`.

## Invariant (do not break)
The streaming path must never lose speech. Empty non-silent chunk ⇒ whole-file fallback; a
silent-classified chunk is decoded and only skipped when the MODEL confirms it empty (never
dropped on the RMS classification alone — §7 #39). Verified by `scripts/verify-streaming.sh` on
macOS and `StreamingSessionTests` here.

## Verify
`dotnet test windows/JVoice.Tests` — StreamingSessionTests, ChunkPlannerTests, WavTailTests,
HighPassSilenceTests, BluetoothDevicePolicyTests.
