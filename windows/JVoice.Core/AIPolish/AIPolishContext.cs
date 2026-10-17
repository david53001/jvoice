namespace JVoice.Core.AIPolish;

/// <summary>
/// The in-memory "previous sentences" ring (port of the Mac's <c>AIPolishContext</c>): the last few
/// PASTED results, so a dictation that only says "deploy it to versails" can be read in the light of
/// the one before it. <b>Never persisted.</b> Only entries for the same target app (on Windows the
/// paste window's exe name, <c>ForegroundApp.ExeName</c>) from the last 10 minutes are handed out,
/// oldest first, capped in total length (the oldest drop first). Not thread-safe: the coordinator
/// touches it on the UI thread only.
/// </summary>
public sealed class AIPolishContext
{
    public sealed record Entry(string Text, DateTime Date, string? AppId);

    public const int Capacity = 3;
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(10);
    public const int MaxCharacters = 1_500;

    private readonly List<Entry> _entries = [];

    public IReadOnlyList<Entry> Entries => _entries;

    public void Append(string text, string? appId, DateTime? at = null)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return;
        _entries.Add(new Entry(trimmed, at ?? DateTime.UtcNow, appId));
        if (_entries.Count > Capacity) _entries.RemoveRange(0, _entries.Count - Capacity);
    }

    public void Clear() => _entries.Clear();

    /// <summary>Context for a dictation into <paramref name="appId"/> at <paramref name="now"/>: an
    /// unknown target gets none.</summary>
    public IReadOnlyList<string> Previous(string? appId, DateTime? now = null)
    {
        if (appId is null) return [];
        var at = now ?? DateTime.UtcNow;
        var matching = _entries
            .Where(e => string.Equals(e.AppId, appId, StringComparison.OrdinalIgnoreCase)
                && at - e.Date <= Window && e.Date <= at)
            .Select(e => e.Text)
            .ToList();
        // Newest first until the budget is spent; a single newest entry over budget keeps its tail.
        var kept = new List<string>();
        int total = 0;
        for (int i = matching.Count - 1; i >= 0; i--)
        {
            string text = matching[i];
            int length = AIPolishRequest.Length(text);
            if (total + length <= MaxCharacters)
            {
                kept.Add(text);
                total += length;
            }
            else
            {
                if (kept.Count == 0) kept.Add(Suffix(text, MaxCharacters));
                break;
            }
        }
        kept.Reverse();
        return kept;
    }

    /// <summary>The last <paramref name="count"/> user-perceived characters (Swift <c>suffix</c>).</summary>
    private static string Suffix(string text, int count)
    {
        var info = new System.Globalization.StringInfo(text);
        int total = info.LengthInTextElements;
        return total <= count ? text : info.SubstringByTextElements(total - count);
    }
}
