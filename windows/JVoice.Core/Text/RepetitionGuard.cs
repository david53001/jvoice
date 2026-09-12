namespace JVoice.Core.Text;

/// Removes Whisper "prompt regurgitation" / repetition-loop output. Faithful port
/// of RepetitionGuard.swift (incl. the long-cycle fix). Conservative by construction:
/// only strips a sustained, repetitive, vocabulary/loop-dominated trailing run.
public static class RepetitionGuard
{
    public const int MinLoopTokens = 8;
    public const int TailWindow = 12;
    public const double DensityThreshold = 0.7;
    public const int MinRepeatCount = 3;
    public const int NonLoopyTolerance = 1;

    public readonly record struct ScrubResult(string Text, bool RemovedRegurgitation);

    public static string Strip(string text, IReadOnlyList<string> vocabulary)
        => Scrub(text, vocabulary).Text;

    public static ScrubResult Scrub(string text, IReadOnlyList<string> vocabulary)
    {
        var tokens = text.Split(new[] { ' ', '\n', '\t', '\r' }, StringSplitOptions.RemoveEmptyEntries);
        int n = tokens.Length;
        if (n < MinLoopTokens) return new ScrubResult(text, false);

        var cores = tokens.Select(Core).ToArray();
        var counts = new Dictionary<string, int>();
        foreach (var c in cores) if (c.Length > 0) counts[c] = counts.GetValueOrDefault(c) + 1;

        var vocabCores = VocabularyCores(vocabulary);
        var vocabKeys = new HashSet<string>(
            vocabCores.Select(PhoneticMatcher.PhoneticKey).Where(k => k.Length > 0));

        bool Loopy(int i)
        {
            string c = cores[i];
            if (c.Length == 0) return false;
            if (vocabCores.Contains(c)) return true;
            string key = PhoneticMatcher.PhoneticKey(c);
            if (key.Length > 0 && vocabKeys.Contains(key)) return true;
            return counts.GetValueOrDefault(c) >= MinRepeatCount && !Stopwords.Contains(c);
        }

        // 1. Quick gate: does the END look loopy at all (dense in loop tokens)?
        if (!IsDegenerate(Math.Max(0, n - TailWindow), n, cores, Loopy, requireRepeat: false))
            return new ScrubResult(text, false);

        // 2. Walk left to the loop onset, tolerating isolated mangled tokens.
        int onset = n;
        int consecutiveNonLoopy = 0;
        for (int i = n - 1; i >= 0; i--)
        {
            if (cores[i].Length == 0) continue; // pure punctuation: neutral
            if (Loopy(i)) { onset = i; consecutiveNonLoopy = 0; }
            else { consecutiveNonLoopy++; if (consecutiveNonLoopy > NonLoopyTolerance) break; }
        }

        // 3. Validate the stripped run is long AND repetitive enough.
        if (!(onset < n && IsDegenerate(onset, n, cores, Loopy)))
            return new ScrubResult(text, false);

        if (onset == 0) return new ScrubResult("", true);
        string kept = string.Join(" ", tokens[..onset]);
        return new ScrubResult(kept.Trim(' ', ',', ';', ':'), true);
    }

    // MARK: Internals

    private static bool IsDegenerate(int start, int end, string[] cores, Func<int, bool> loopy, bool requireRepeat = true)
    {
        var nonEmpty = new List<int>();
        for (int i = start; i < end; i++) if (cores[i].Length > 0) nonEmpty.Add(i);
        if (nonEmpty.Count < MinLoopTokens) return false;
        int loopCount = nonEmpty.Count(loopy);
        if ((double)loopCount / nonEmpty.Count < DensityThreshold) return false;
        if (!requireRepeat) return true;
        var counts = new Dictionary<string, int>();
        foreach (var idx in nonEmpty) counts[cores[idx]] = counts.GetValueOrDefault(cores[idx]) + 1;
        return counts.Count > 0 && counts.Values.Max() >= MinRepeatCount;
    }

    /// Lowercased alphanumerics only — strips surrounding punctuation. Mirrors Swift's
    /// `CharacterSet.alphanumerics` (Unicode categories L*, M*, N*), which — unlike
    /// `char.IsLetterOrDigit` (only L* + Nd) — keeps combining marks (Mn/Mc/Me) and the
    /// Nl/No number categories. Iterates Unicode scalars (runes) like Swift's `unicodeScalars`.
    internal static string Core(string token)
    {
        var sb = new System.Text.StringBuilder(token.Length);
        foreach (var rune in token.ToLowerInvariant().EnumerateRunes())
            if (IsAlphanumericScalar(rune)) sb.Append(rune.ToString());
        return sb.ToString();
    }

    private static bool IsAlphanumericScalar(System.Text.Rune rune)
        => System.Text.Rune.GetUnicodeCategory(rune) switch
        {
            System.Globalization.UnicodeCategory.UppercaseLetter or
            System.Globalization.UnicodeCategory.LowercaseLetter or
            System.Globalization.UnicodeCategory.TitlecaseLetter or
            System.Globalization.UnicodeCategory.ModifierLetter or
            System.Globalization.UnicodeCategory.OtherLetter or
            System.Globalization.UnicodeCategory.NonSpacingMark or
            System.Globalization.UnicodeCategory.SpacingCombiningMark or
            System.Globalization.UnicodeCategory.EnclosingMark or
            System.Globalization.UnicodeCategory.DecimalDigitNumber or
            System.Globalization.UnicodeCategory.LetterNumber or
            System.Globalization.UnicodeCategory.OtherNumber => true,
            _ => false,
        };

    internal static HashSet<string> VocabularyCores(IReadOnlyList<string> vocabulary)
    {
        var result = new HashSet<string>();
        foreach (var word in vocabulary)
        {
            string whole = Core(word);
            if (whole.Length >= 2) result.Add(whole);
            foreach (var part in word.Split(new[] { ' ', '-', '_', '/' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var current = new System.Text.StringBuilder();
                for (int idx = 0; idx < part.Length; idx++)
                {
                    char ch = part[idx];
                    if (idx > 0 && char.IsUpper(ch) && current.Length > 0)
                    {
                        string c = Core(current.ToString());
                        if (c.Length >= 2) result.Add(c);
                        current.Clear();
                    }
                    current.Append(ch);
                }
                string last = Core(current.ToString());
                if (last.Length >= 2) result.Add(last);
            }
        }
        return result;
    }

    internal static readonly HashSet<string> Stopwords = new()
    {
        "the","a","an","and","or","but","to","of","in","on","at","for","with","by","from",
        "is","are","was","were","be","been","being","am","do","does","did","have","has","had",
        "it","its","i","you","he","she","we","they","me","him","her","us","them","my","your",
        "this","that","these","those","so","as","if","then","there","here","not","no","yes",
        "just","like","what","which","who","when","where","how","why","about","up","out","now",
    };
}
