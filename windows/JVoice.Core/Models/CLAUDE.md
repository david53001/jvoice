# Core / Models — domain types & DTOs

Plain data shared across the app: enums, value types, and the JSON shapes persisted to disk.

## Key files
- `SettingsState.cs` / `SettingsStateJson.cs` — the settings model + its on-disk JSON DTO
  (schema v2; `GameMode` added). The DTO is the persistence contract.
- `ToneStyle.cs`, `TranscriptionLanguage.cs`, `WhisperModelOption.cs`, `GameDetectionMode.cs`,
  `HotkeyChord.cs` — user-facing enums/choices.
- `HudState.cs` — the HUD state machine the UI mirrors (idle / recording / preparing /
  transcribing / error).
- `TranscriptHistory.cs` / `TranscriptHistoryEntry.cs` — the Recent Transcripts model
  (last 30; root `CLAUDE.md` §7 #26).
- `CorrectionRule.cs` — a custom-word correction entry.

## Trap
These types are serialized to JSON on disk (settings, stats, transcript history). Renaming a
property or enum member can silently break loading a user's existing file — treat them as a
**versioned contract** (bump the schema, don't repurpose fields). `SettingsStateTests` /
`ModelTests` / `TranscriptHistoryTests` guard the shape.

## Verify
`dotnet test windows/JVoice.Tests` — ModelTests, SettingsStateTests, HotkeyChordTests,
HudStateTests, TranscriptHistoryTests.
