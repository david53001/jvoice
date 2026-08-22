namespace JVoice.Core.Text;

/// Spoken number words → digits ("twenty five" → "25", "three point one four" → "3.14").
///
/// Used ONLY inside a run that <see cref="MathSpeech"/> has already recognised as
/// mathematics, so it can be greedy: turning "one" into "1" is right in "x = one half" and
/// would be wrong in "one of my friends", and the run rules — not this parser — are what
/// tell the two apart.
///
/// Every entry point is a "try-read at this index" so the caller stays in control of the
/// token stream: they return the digits plus how many words were consumed, or null.
public static class SpokenNumbers
{
    private static readonly Dictionary<string, int> Units = new(StringComparer.OrdinalIgnoreCase)
    {
        ["zero"] = 0, ["nought"] = 0, ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4,
        ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8, ["nine"] = 9, ["ten"] = 10,
        ["eleven"] = 11, ["twelve"] = 12, ["thirteen"] = 13, ["fourteen"] = 14,
        ["fifteen"] = 15, ["sixteen"] = 16, ["seventeen"] = 17, ["eighteen"] = 18,
        ["nineteen"] = 19,
    };

    private static readonly Dictionary<string, int> Tens = new(StringComparer.OrdinalIgnoreCase)
    {
        ["twenty"] = 20, ["thirty"] = 30, ["forty"] = 40, ["fifty"] = 50,
        ["sixty"] = 60, ["seventy"] = 70, ["eighty"] = 80, ["ninety"] = 90,
    };

    /// True when the word is already numeric as transcribed ("7", "3.14", "1,000").
    public static bool IsDigits(string word)
    {
        if (word.Length == 0) return false;
        bool digit = false;
        foreach (char c in word)
        {
            if (char.IsAsciiDigit(c)) { digit = true; continue; }
            if (c is '.' or ',') continue;
            return false;
        }
        return digit;
    }

    /// Reads a cardinal number (or an already-numeric token) starting at
    /// <paramref name="index"/>. Returns the digits and how many words were consumed.
    public static (string Digits, int Consumed)? TryRead(IReadOnlyList<string> words, int index)
    {
        if (index < 0 || index >= words.Count) return null;

        if (IsDigits(words[index]))
            return (words[index].Replace(",", ""), 1);

        int consumed = 0;
        long total = 0, current = 0;
        bool any = false;

        while (index + consumed < words.Count)
        {
            string w = words[index + consumed];
            if (Units.TryGetValue(w, out int unit)) { current += unit; }
            else if (Tens.TryGetValue(w, out int ten)) { current += ten; }
            else if (w.Equals("hundred", StringComparison.OrdinalIgnoreCase)) { current = (current == 0 ? 1 : current) * 100; }
            else if (w.Equals("thousand", StringComparison.OrdinalIgnoreCase)) { total += (current == 0 ? 1 : current) * 1000; current = 0; }
            else break;

            any = true;
            consumed++;
        }

        return any ? ((total + current).ToString(), consumed) : null;
    }

    private static readonly Dictionary<string, string> Ordinals = new(StringComparer.OrdinalIgnoreCase)
    {
        ["second"] = "2", ["third"] = "3", ["fourth"] = "4", ["fifth"] = "5", ["sixth"] = "6",
        ["seventh"] = "7", ["eighth"] = "8", ["ninth"] = "9", ["tenth"] = "10",
        // "nth root" is spoken as a letter, and reads back as a letter: ⁿ√x.
        ["nth"] = "n",
    };

    /// Reads an ordinal ("fourth" → "4", "nth" → "n"), used for "&lt;ordinal&gt; root of x".
    public static (string Digits, int Consumed)? TryReadOrdinal(IReadOnlyList<string> words, int index)
    {
        if (index < 0 || index >= words.Count) return null;
        return Ordinals.TryGetValue(words[index], out string? d) ? (d, 1) : null;
    }
}
