# Core / Transcription — the engine seam

The abstraction that lets the pure brain stay platform-free while the app plugs in a real Whisper
engine.

## Key files
- `ITranscriptionEngine.cs` — the contract that `JVoice.App/Whisper/WhisperNetTranscriptionEngine`
  implements (and that tests fake).
- `FileBackedTranscriptionEngine.cs` — a deterministic, file-driven engine used by tests/tools
  (no model, no GPU): feeds canned transcripts so brain logic can be exercised offline.
- `TranscriptionException.cs` — the typed failure surface.

## Verify
`dotnet test windows/JVoice.Tests` — FileBackedEngineTests.
