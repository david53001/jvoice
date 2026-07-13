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
  *silent-classified mid-stream chunks are DECODED, never dropped unheard* (2026-07-03, §7 #39;
  refined 2026-07-13, §7 #41): empty decode ⇒ confirmed silence, skip; NON-EMPTY decode ⇒
  classifier/model disagreement — the isolated decode can be PARTIAL (whisper kept only the last
  40 chars of a real 16.35 s quiet chunk while claiming full timestamp coverage), so the session
  fails → lossless whole-file fallback. Optional `log` callback for diagnostics (the app wires
  `DiagnosticLog.Write`).
- `HighPassSilence.cs` — Windows-only, now **metrics-only** (the no-speech decision moved to
  `Core/Text/NonSpeechAnnotation`).
- `BluetoothDevicePolicy.cs` — pure policy for keeping Bluetooth mics on A2DP (record from the
  built-in input instead). The device-side action lives in `Platform/Capture/AudioInputRouter`.

## Invariant (do not break)
The streaming path must never lose speech. Empty non-silent chunk ⇒ whole-file fallback; a
silent-classified chunk is decoded and only skipped when the MODEL confirms it empty — and if it
decodes NON-empty its text is never pasted either (partial-decode risk ⇒ whole-file fallback;
§7 #39/#41). Verified by `scripts/verify-streaming.sh` on macOS and `StreamingSessionTests` here.

## Verify
`dotnet test windows/JVoice.Tests` — StreamingSessionTests, ChunkPlannerTests, WavTailTests,
HighPassSilenceTests, BluetoothDevicePolicyTests.
