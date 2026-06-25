namespace JVoice.Core.Models;

/// One Recent-Transcripts row: a finalized transcript (<see cref="Text"/>) plus a
/// stable <see cref="Id"/>. The id gives the row an identity independent of its
/// text, so a per-row delete targets the right entry even when two transcripts are
/// identical. Persisted as JSON by the App-layer TranscriptHistoryStore.
///
/// Windows-only feature (no macOS counterpart).
public sealed record TranscriptHistoryEntry(Guid Id, string Text);
