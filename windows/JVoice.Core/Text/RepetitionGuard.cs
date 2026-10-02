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
    /// Spoken maths repeats its operands and operators legitimately ("26 times 26 times 26 …",
    /// "minus 3 minus 3 minus 3"), so a maths token (<see cref="IsMathToken"/>) only counts as a
    /// loop token on repetition alone when it occurs <see cref="MathMinRepeatCount"/> times within
    /// the last <see cref="MathRepeatWindow"/> tokens — a stuck decoder repeats far past that, and
    /// counting only recent tokens stops a long maths dictation accumulating "3"/"times" counts
    /// (Mac 2026-09-23, ffbca8a).
    public const int MathRepeatWindow = 24;
    public const int MathMinRepeatCount = 8;
    /// The net under that exemption: a transcript ENDING in one exact phrase of ≤
    /// <see cref="MaxLoopPhraseTokens"/> tokens repeated ≥ <see cref="MinPhraseRepeats"/> times is a
    /// loop whatever its tokens ("page 1 of 10, page 1 of 10, …"); 6 leaves a dictated power
    /// ("26 times" ×5) alone.
    public const int MinPhraseRepeats = 6;
    public const int MaxLoopPhraseTokens = 12;
    /// The repeats a phrase made only of maths / stopword tokens needs before the phrase net strips it.
    public const int MathPhraseRepeats = 12;

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
        var recentCounts = new Dictionary<string, int>();
        foreach (var c in cores.Skip(Math.Max(0, n - MathRepeatWindow))) if (c.Length > 0) recentCounts[c] = recentCounts.GetValueOrDefault(c) + 1;

        var vocabCores = VocabularyCores(vocabulary);
        var vocabKeys = new HashSet<string>(
            vocabCores.Select(PhoneticMatcher.PhoneticKey).Where(k => k.Length > 0));
        var phraseLoopCores = TrailingPhraseLoop(cores.Where(c => c.Length > 0).ToArray());

        bool Loopy(int i)
        {
            string c = cores[i];
            if (c.Length == 0) return false;
            if (vocabCores.Contains(c) || phraseLoopCores.Contains(c)) return true;
            string key = PhoneticMatcher.PhoneticKey(c);
            if (key.Length > 0 && vocabKeys.Contains(key)) return true;
            // A word repeated ≥3× is a loop too — but stopwords repeat naturally in prose, and maths
            // tokens need a sustained run near the end (MathMinRepeatCount in MathRepeatWindow).
            if (Stopwords.Contains(c)) return false;
            if (IsMathToken(c)) return recentCounts.GetValueOrDefault(c) >= MathMinRepeatCount;
            return counts.GetValueOrDefault(c) >= MinRepeatCount;
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

        // 4. Spoken arithmetic ("2 times 2 …" with 9-12 operands) or a run of stopwords ("no no no …") shorter than
        //    MathRepeatWindow is dictation, not a stuck decoder — which runs far past that ("the" ×40). Stripping it
        //    deleted the dictation, or all of it with no lead-in (review round 2 JV #2). A bare repeated number
        //    ("½ ½ ½ …", "10, 10, …") has no operator and stays a loop, as on the Mac.
        //    Only when no trailing phrase loop was found: one that repeated MathPhraseRepeats (12) times is already
        //    past what dictation does, so "you" ×20 (Whisper's classic short-clip silence loop) still goes (round 3
        //    JV #2 — this rule had let 12-23 repeats through, against TrailingPhraseLoop's documented threshold).
        var run = cores[onset..].Where(c => c.Length > 0).ToArray();
        bool arithmetic = run.Any(SpokenOperators.Contains) && run.All(c => IsMathToken(c) || Stopwords.Contains(c));
        bool chatter = run.All(Stopwords.Contains);
        if (phraseLoopCores.Count == 0 && run.Length < MathRepeatWindow && (arithmetic || chatter))
            return new ScrubResult(text, false);
        // 5. Spoken arithmetic is never reduced to nothing: a long sum (13+ operands) with no lead-in is dictation,
        //    and an empty paste would silently lose it all (round 3 JV #2). A phrase-loop of it is still stripped
        //    back to whatever preceded it.
        if (onset == 0 && arithmetic && phraseLoopCores.Count == 0)
            return new ScrubResult(text, false);

        if (onset == 0) return new ScrubResult("", true);
        string kept = string.Join(" ", tokens[..onset]);
        return new ScrubResult(kept.Trim(' ', ',', ';', ':'), true);
    }

    // MARK: Internals

    /// The cores of the phrase the transcript ends by repeating ≥ <see cref="MinPhraseRepeats"/> times
    /// (a trailing partial cycle counts — a loop cut off by the token budget stops mid-phrase); empty otherwise.
    internal static HashSet<string> TrailingPhraseLoop(string[] cores)
    {
        int n = cores.Length;
        for (int period = 1; period <= MaxLoopPhraseTokens && period * MinPhraseRepeats <= n; period++)
        {
            int i = n - 1;
            while (i - period >= 0 && cores[i] == cores[i - period]) i--;
            // cores[(i + 1 - period)..] is periodic with this period.
            int run = n - (i + 1 - period);
            if (run < period * MinPhraseRepeats) continue;
            var phrase = cores[(n - period)..];
            // A phrase of only maths / stopword tokens is often dictation ("2 times 2 times …" ×6,
            // "no no no …" ×8): it needs twice the repeats before it counts as a loop — a stuck
            // decoder runs far past that ("the" ×40, "1, 2, 3, 4" ×50). Stripping it at 6 deleted
            // whole dictations (review round 1 JV #3).
            if (run < period * MathPhraseRepeats && phrase.All(c => IsMathToken(c) || Stopwords.Contains(c)))
                return new HashSet<string>();
            return new HashSet<string>(phrase);
        }
        return new HashSet<string>();
    }

    /// A number ("26", "14950" — <see cref="Core"/> drops the separators), a single letter (a variable,
    /// or the "x" Whisper writes for "times"), a number word, or a spoken operator.
    internal static bool IsMathToken(string core)
    {
        if (core.Length == 0) return false;
        if (core.EnumerateRunes().Count() == 1) return true;
        if (core.EnumerateRunes().All(System.Text.Rune.IsNumber)) return true;
        return MathWords.Contains(core);
    }

    /// <summary>The words that make a run of maths tokens spoken arithmetic rather than a repeated number.</summary>
    internal static readonly HashSet<string> SpokenOperators = new()
    {
        "plus", "minus", "times", "x", "over", "equals", "equal", "divided", "multiplied", "mod",
    };

    internal static readonly HashSet<string> MathWords = new()
    {
        "plus", "minus", "times", "over", "equals", "equal", "divided", "multiplied", "squared", "cubed",
        "factorial", "choose", "power", "root", "point", "negative", "mod", "sub",
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
    };

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
                    // Split at a word boundary only: camelCase ("WhisperKit") or an acronym running into a
                    // word ("JVoice") — never inside an acronym, which would shred "VS" into single letters.
                    if (idx > 0 && char.IsUpper(ch) && current.Length > 0
                        && (char.IsLower(part[idx - 1]) || (idx + 1 < part.Length && char.IsLower(part[idx + 1]))))
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
