using System.Text;

namespace JVoice.Core.Text;

/// Fuzzy phonetic matcher that corrects Whisper mishearings of user-defined
/// vocabulary ("jay voice" → "JVoice"). Faithful port of PhoneticMatcher.swift.
public static class PhoneticMatcher
{
    // MARK: Public API

    public static string Correct(string text, IReadOnlyList<string> vocabulary)
    {
        if (vocabulary.Count == 0 || text.Length == 0) return text;

        var entries = vocabulary
            .Select(w => new Entry(w))
            .Where(e => e.Letters.Length >= 3)
            .OrderByDescending(e => e.Letters.Length)
            .ToList();
        if (entries.Count == 0) return text;

        var tokens = text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(s => new Token(s)).ToList();
        int maxWindow = entries.Count == 0 ? 1 : entries.Max(e => e.MaxWindow);

        int i = 0;
        while (i < tokens.Count)
        {
            bool advanced = false;
            int upperWindow = Math.Min(maxWindow, tokens.Count - i);
            // Smallest window first so an exact single-token hit short-circuits
            // before a larger fuzzy window can swallow neighbors.
            for (int window = 1; window <= upperWindow; window++)
            {
                var slice = tokens.GetRange(i, window);
                string candidate = string.Concat(slice.Select(t => t.CoreLetters));
                if (candidate.Length < 3) continue;
                foreach (var entry in entries)
                {
                    if (window > entry.MaxWindow) continue;
                    if (!Matches(candidate, entry)) continue;
                    string renderedCore = string.Join(" ", slice.Select(t => t.Core));
                    if (renderedCore == entry.Word)
                    {
                        // Already exact (single- or multi-token) — stop probing here.
                        goto afterWindowSearch;
                    }
                    var replacement = new Token(slice[0].Leading, entry.Word, slice[^1].Trailing);
                    tokens.RemoveRange(i, window);
                    tokens.Insert(i, replacement);
                    i += 1;
                    advanced = true;
                    goto afterWindowSearch;
                }
            }
        afterWindowSearch:
            if (!advanced) i += 1;
        }

        return string.Join(" ", tokens.Select(t => t.Rendered));
    }

    // MARK: Matching

    private static bool Matches(string candidate, Entry entry)
    {
        if (candidate == entry.Letters) return true; // spacing/casing drift only

        if (Math.Abs(candidate.Length - entry.Letters.Length) > 2 + entry.Letters.Length / 3)
            return false;

        string candidateKey = PhoneticKey(candidate);
        // Initial-sound guard: "voice"(fs…) must never match "JVoice"(jfs…).
        if (candidateKey.Length == 0 || entry.Key.Length == 0 || candidateKey[0] != entry.Key[0])
            return false;

        int letterDistance = Levenshtein(candidate, entry.Letters, limit: 3);
        if (candidateKey == entry.Key && letterDistance <= Math.Max(1, entry.Letters.Length / 3))
            return true;
        if (entry.Letters.Length >= 6)
        {
            int keyDistance = Levenshtein(candidateKey, entry.Key, limit: 1);
            if (keyDistance <= 1 && letterDistance <= 2) return true;
        }
        return false;
    }

    // MARK: Phonetic key (simplified Metaphone)

    public static string PhoneticKey(string input)
    {
        var s = new List<char>();
        foreach (var c in input.ToLowerInvariant())
            if (char.IsLetter(c)) s.Add(c);
        if (s.Count == 0) return "";

        // Prefix simplifications.
        (char[] match, char[] replacement)[] prefixes =
        {
            (new[]{'k','n'}, new[]{'n'}),
            (new[]{'w','r'}, new[]{'r'}),
            (new[]{'p','s'}, new[]{'s'}),
            (new[]{'w','h'}, new[]{'w'}),
        };
        foreach (var (match, replacement) in prefixes)
        {
            if (s.Count >= match.Length && s.Take(match.Length).SequenceEqual(match))
            {
                s.RemoveRange(0, match.Length);
                s.InsertRange(0, replacement);
                break;
            }
        }

        // Pass 1: map letters (consuming digraphs), keeping vowels for now.
        var mapped = new List<char>();
        int i = 0;
        while (i < s.Count)
        {
            char ch = s[i];
            char? nxt = i + 1 < s.Count ? s[i + 1] : null;
            char outc;
            int consumed = 1;
            if (ch == 'p' && nxt == 'h') { outc = 'f'; consumed = 2; }
            else if ((ch == 's' && nxt == 'h') || (ch == 'c' && nxt == 'h')) { outc = 'x'; consumed = 2; }
            else if (ch == 't' && nxt == 'h') { outc = '0'; consumed = 2; }
            else if ((ch == 'c' && nxt == 'k') || (ch == 'q' && nxt == 'u') || (ch == 'g' && nxt == 'h')) { outc = 'k'; consumed = 2; }
            else
            {
                switch (ch)
                {
                    case 'b': outc = 'p'; break;
                    case 'c': outc = (nxt is char n && "eiy".Contains(n)) ? 's' : 'k'; break;
                    case 'd': outc = 't'; break;
                    case 'g': case 'j': outc = 'j'; break;
                    case 'k': case 'q': outc = 'k'; break;
                    case 'v': outc = 'f'; break;
                    case 'x': case 'z': outc = 's'; break;
                    default: outc = ch; break;
                }
            }
            mapped.Add(outc);
            i += consumed;
        }

        // Pass 2: keep position 0; drop vowels elsewhere. Pass 3: dedupe runs.
        var vowels = new HashSet<char> { 'a', 'e', 'i', 'o', 'u', 'y' };
        var key = new List<char>();
        for (int idx = 0; idx < mapped.Count; idx++)
        {
            char ch = mapped[idx];
            if (idx > 0 && vowels.Contains(ch)) continue;
            if (key.Count > 0 && key[^1] == ch) continue;
            key.Add(ch);
        }
        return new string(key.ToArray());
    }

    // MARK: Edit distance (bounded, early-exit)

    public static int Levenshtein(string a, string b, int limit)
    {
        if (Math.Abs(a.Length - b.Length) > limit) return limit + 1;
        if (a.Length == 0) return b.Length;
        if (b.Length == 0) return a.Length;

        var previous = new int[b.Length + 1];
        var current = new int[b.Length + 1];
        for (int j = 0; j <= b.Length; j++) previous[j] = j;

        for (int i = 0; i < a.Length; i++)
        {
            char ca = a[i];
            current[0] = i + 1;
            int rowMin = current[0];
            for (int j = 0; j < b.Length; j++)
            {
                int cost = ca == b[j] ? 0 : 1;
                current[j + 1] = Math.Min(Math.Min(previous[j + 1] + 1, current[j] + 1), previous[j] + cost);
                rowMin = Math.Min(rowMin, current[j + 1]);
            }
            if (rowMin > limit) return limit + 1;
            (previous, current) = (current, previous);
        }
        return Math.Min(previous[b.Length], limit + 1);
    }

    // MARK: Internals

    private sealed class Entry
    {
        public string Word { get; }
        public string Letters { get; }
        public string Key { get; }
        public int MaxWindow { get; }

        public Entry(string word)
        {
            Word = word;
            Letters = new string(word.ToLowerInvariant().Where(char.IsLetter).ToArray());
            Key = PhoneticKey(Letters);
            int spokenWords = 0;
            foreach (var part in word.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                int boundaries = 1;
                for (int i = 0; i < part.Length; i++)
                    if (i > 0 && char.IsUpper(part[i])) boundaries++;
                spokenWords += boundaries;
            }
            MaxWindow = Math.Max(1, spokenWords) + 1;
        }
    }

    private readonly struct Token
    {
        public string Leading { get; }
        public string Core { get; }
        public string Trailing { get; }

        public Token(string leading, string core, string trailing)
        {
            Leading = leading; Core = core; Trailing = trailing;
        }

        public Token(string raw)
        {
            int start = 0, end = raw.Length;
            while (start < end && !char.IsLetter(raw[start]) && !char.IsNumber(raw[start])) start++;
            while (end > start && !char.IsLetter(raw[end - 1]) && !char.IsNumber(raw[end - 1])) end--;
            Leading = raw[..start];
            Core = raw[start..end];
            Trailing = raw[end..];
        }

        public string CoreLetters => new(Core.ToLowerInvariant().Where(char.IsLetter).ToArray());
        public string Rendered => Leading + Core + Trailing;
    }
}
