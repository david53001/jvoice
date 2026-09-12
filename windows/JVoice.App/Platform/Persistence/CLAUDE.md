# Platform / Persistence — on-disk user state

Reads/writes the app's JSON state under the user's profile. Privacy-sensitive: transcripts are
user data.

## Key files
- `PlatformPaths.cs` — the single source of truth for **where** files live (`%APPDATA%` / local
  paths). Other stores ask it; don't hard-code paths elsewhere.
- `SettingsStore.cs` — load/save `SettingsState` (JSON via the `Core/Models` DTO). Restore Defaults
  also clears transcript history.
- `StatsStore.cs` — usage stats.
- `LastTranscriptStore.cs` — the most-recent transcript.
- `TranscriptHistoryStore.cs` — Recent Transcripts (last 30, persisted to `transcript-history.json`;
  root `CLAUDE.md` §7 #26).

## Traps
- The JSON shape is a **versioned contract** (`SettingsStateJson`, schema v2). Don't rename fields
  without a migration / schema bump — you'll silently break a user's existing file.
- Transcripts are private user content. Keep them local; never log their text or send them anywhere
  (the zero-network invariant).

## Verify
`dotnet test windows/JVoice.Tests` — SettingsStoreJsonTests, SettingsStateTests,
TranscriptHistoryTests, StatsMathTests.
