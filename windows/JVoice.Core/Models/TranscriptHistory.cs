using System.Text.Json;

namespace JVoice.Core.Models;

/// Pure, file-I/O-free operations + JSON (de)serialization for the Recent
/// Transcripts history (the most recent finalized dictations, newest first). The
/// App-layer TranscriptHistoryStore wraps this with persistence.
///
/// Windows-only feature (no macOS counterpart). Mirrors the SettingsStateJson split:
/// the brain and all the edge cases live here (unit-tested by JVoice.Tests); the store
/// does only file I/O. A corrupt or missing blob decodes to an empty list — never throws.
public static class TranscriptHistory
{
    /// Maximum retained entries. Older entries fall off the end once exceeded.
    public const int MaxEntries = 30;

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    /// Prepend a new entry for <paramref name="text"/> (newest first), capping the
    /// list at <see cref="MaxEntries"/>. Leading/trailing whitespace is trimmed; if the
    /// text is blank after trimming it is ignored — the list is returned unchanged and
    /// the returned entry is null. <paramref name="id"/> gives the new entry its stable
    /// identity. The input list is never mutated.
    public static (IReadOnlyList<TranscriptHistoryEntry> List, TranscriptHistoryEntry? Added)
        Add(IReadOnlyList<TranscriptHistoryEntry> current, string text, Guid id)
    {
        string trimmed = (text ?? string.Empty).Trim();
        if (trimmed.Length == 0) return (current, null);

        var entry = new TranscriptHistoryEntry(id, trimmed);
        var list = new List<TranscriptHistoryEntry>(current.Count + 1) { entry };
        list.AddRange(current);
        if (list.Count > MaxEntries)
            list.RemoveRange(MaxEntries, list.Count - MaxEntries);
        return (list, entry);
    }

    /// Remove the entry with the given id (if present). Returns a new list; the input
    /// list is never mutated. Removing an absent id yields an equal-length copy.
    public static IReadOnlyList<TranscriptHistoryEntry> Remove(
        IReadOnlyList<TranscriptHistoryEntry> current, Guid id)
        => current.Where(e => e.Id != id).ToList();

    public static string Serialize(IReadOnlyList<TranscriptHistoryEntry> entries)
        => JsonSerializer.Serialize(entries, Options);

    /// Decode a persisted blob. A null/blank/corrupt blob decodes to an empty list
    /// rather than throwing, so a damaged file behaves exactly like a fresh install.
    /// Blank-text entries are dropped, entries with no id get a fresh one, and the
    /// result is capped at <see cref="MaxEntries"/>.
    public static IReadOnlyList<TranscriptHistoryEntry> Deserialize(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            var raw = JsonSerializer.Deserialize<List<TranscriptHistoryEntry>>(json, Options);
            if (raw is null) return [];
            return raw
                .Where(e => e is not null && !string.IsNullOrWhiteSpace(e.Text))
                .Select(e => e.Id == Guid.Empty ? e with { Id = Guid.NewGuid() } : e)
                .Take(MaxEntries)
                .ToList();
        }
        catch
        {
            return []; // corrupt history is non-critical: start fresh
        }
    }
}
