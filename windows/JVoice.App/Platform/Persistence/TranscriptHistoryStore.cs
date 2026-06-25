using System.IO;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// Persists the Recent Transcripts history (the most recent finalized dictations,
/// newest first) to %APPDATA%\JVoice\transcript-history.json.
///
/// Windows-only feature. Mirrors the StatsStore / LastTranscriptStore shape: the pure
/// list + JSON logic lives in JVoice.Core (TranscriptHistory, unit-tested); this wrapper
/// only does file I/O. Persists synchronously on each mutation (a few dozen short snippets
/// is only a few KB, written rarely — once per dictation or per edit).
///
/// Privacy: stored in plaintext, and the list is erased ONLY by explicit user action
/// (per-row delete, Clear all, or Restore Default Settings) — never automatically. A
/// missing or corrupt file loads as an empty list, exactly like a fresh install.
public sealed class TranscriptHistoryStore
{
    private readonly string _path;
    private readonly object _gate = new();
    private List<TranscriptHistoryEntry> _entries;

    public TranscriptHistoryStore(string? path = null)
    {
        _path = path ?? PlatformPaths.TranscriptHistoryFile;
        _entries = TranscriptHistory.Deserialize(ReadAllOrNull(_path)).ToList();
    }

    /// Current entries, newest first. A snapshot copy — callers can't mutate our list.
    public IReadOnlyList<TranscriptHistoryEntry> Entries
    {
        get { lock (_gate) return _entries.ToList(); }
    }

    /// Prepend a finalized transcript. Trims whitespace; blank text is ignored and
    /// returns null. Caps the list at TranscriptHistory.MaxEntries and persists.
    /// Returns the newly-added entry so the UI can insert just that row.
    public TranscriptHistoryEntry? Add(string text)
    {
        lock (_gate)
        {
            var (list, added) = TranscriptHistory.Add(_entries, text, Guid.NewGuid());
            if (added is null) return null;
            _entries = list.ToList();
            Save();
            return added;
        }
    }

    /// Remove the one entry with this id (if present) and persist.
    public void Remove(Guid id)
    {
        lock (_gate)
        {
            var updated = TranscriptHistory.Remove(_entries, id);
            if (updated.Count == _entries.Count) return; // nothing matched
            _entries = updated.ToList();
            Save();
        }
    }

    /// Empty the whole history and persist.
    public void Clear()
    {
        lock (_gate)
        {
            if (_entries.Count == 0) return;
            _entries = [];
            Save();
        }
    }

    private static string? ReadAllOrNull(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path) : null; }
        catch { return null; }
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            string json = TranscriptHistory.Serialize(_entries);
            // Atomic-ish write: temp file then move, so a crash mid-write can't truncate
            // the history file (same pattern as SettingsStore / StatsStore).
            string tmp = _path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Failed to save transcript history. {ex.Message}");
        }
    }
}
