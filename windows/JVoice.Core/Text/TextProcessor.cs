using System.Text;
using System.Text.RegularExpressions;
using JVoice.Core.Models;

namespace JVoice.Core.Text;

/// Post-processing pipeline: tone styles, filler removal, exact custom-word
/// corrections, hallucination-sentinel stripping. Faithful port of TextProcessor.swift.
public static class TextProcessor
{
    public static readonly IReadOnlyDictionary<string, string> CorrectionDictionary = new Dictionary<string, string>
    {
        ["app kit"] = "AppKit",
        ["appkit"] = "AppKit",
        ["j voice"] = "JVoice",
        ["j-voice"] = "JVoice", // whisper hyphenates it under a cased prompt (Mac 000a8b0)
        ["jvoice"] = "JVoice",
        // NOT "keyboard shortcuts": that is everyday English ("my favourite keyboard shortcuts") and
        // this dictionary is always on (Mac b0bb390).
        ["keyboardshortcuts"] = "KeyboardShortcuts",
        ["mac os"] = "macOS",
        ["whisper kit"] = "WhisperKit",
        ["whisperkit"] = "WhisperKit",
    };

    public static string Process(
        string text,
        ToneStyle mode,
        IReadOnlyDictionary<string, string>? extraDictionary = null,
        bool removeFillerWords = false,
        IReadOnlyList<string>? vocabulary = null)
    {
        extraDictionary ??= new Dictionary<string, string>();
        vocabulary ??= Array.Empty<string>();

        string normalized = NormalizeWhitespace(text);
        string clean = removeFillerWords ? RemoveDisfluencies(normalized) : normalized;
        // Very Casual lowercases first so corrections (applied after) win over the lowering.
        string cased = mode == ToneStyle.VeryCasual ? clean.ToLowerInvariant() : clean;
        string corrected = ApplyCorrections(cased, extraDictionary);
        string phonetic = PhoneticMatcher.Correct(corrected, vocabulary);
        return Format(phonetic, mode);
    }

    public static string ApplyCorrections(string text, IReadOnlyDictionary<string, string>? extraDictionary = null)
    {
        extraDictionary ??= new Dictionary<string, string>();
        var combined = new Dictionary<string, string>(extraDictionary);
        foreach (var kv in CorrectionDictionary) combined[kv.Key] = kv.Value; // builtin wins on conflict

        string result = text;
        foreach (var kv in combined.OrderByDescending(kv => kv.Key.Length))
            result = ReplaceOccurrences(kv.Key, result, kv.Value);
        return result;
    }

    public static IReadOnlyDictionary<string, string> BuildUserDictionary(IReadOnlyList<string> words)
    {
        var dict = new Dictionary<string, string>();
        foreach (var word in words)
            foreach (var variant in SpokenVariants(word))
                if (!CorrectionDictionary.ContainsKey(variant))
                    dict[variant] = word;
        return dict;
    }

    public static IReadOnlyList<string> ExtractCorrections(string original, string corrected)
    {
        var originalWords = SplitOnWhitespacesOnly(original);
        var correctedWords = SplitOnWhitespacesOnly(corrected);

        var results = new List<string>();
        if (originalWords.Length == correctedWords.Length)
        {
            for (int i = 0; i < originalWords.Length; i++)
            {
                if (originalWords[i] == correctedWords[i]) continue;
                var stripped = TrimPunctuation(correctedWords[i]);
                if (stripped.Length > 0) results.Add(stripped);
            }
        }
        else
        {
            var originalExact = new HashSet<string>(originalWords);
            foreach (var word in correctedWords)
            {
                if (originalExact.Contains(word)) continue;
                var stripped = TrimPunctuation(word);
                if (stripped.Length > 0) results.Add(stripped);
            }
        }
        return results.Distinct().Where(s => s.Length > 1).ToList();
    }

    public static IReadOnlyList<string> SpokenVariants(string word)
    {
        var variants = new HashSet<string>();
        string lower = word.ToLowerInvariant();

        variants.Add(lower);
        variants.Add(lower.Replace(" ", ""));
        variants.Add(lower.Replace(".", "").Replace(" ", ""));
        variants.Add(lower.Replace(".", " "));

        var camel = new StringBuilder();
        for (int i = 0; i < word.Length; i++)
        {
            if (char.IsUpper(word[i]) && i > 0) camel.Append(' ');
            camel.Append(char.ToLowerInvariant(word[i]));
        }
        variants.Add(camel.ToString());
        variants.Add(camel.ToString().Replace(" ", ""));

        // Drop any variant that is a PROPER substring of the canonical word (case-insensitive): ".NET"
        // would otherwise register "net", whose pattern re-matches inside the inserted ".NET" and turns
        // it into "..NET" (Mac TRX-01). The plain lower-cased word is always kept — it fixes casing
        // drift ("claude" → "Claude") and can't self-overlap. Trim first: "." → " " makes " net".
        return variants
            .Select(v => v.Trim())
            .Where(v => v.Length > 0 && v != word && (v == lower || !lower.Contains(v, StringComparison.Ordinal)))
            .Distinct()
            .ToList();
    }

    public static string Format(string text, ToneStyle mode)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return "";

        return mode switch
        {
            ToneStyle.Casual => RemoveTerminalPunctuation(trimmed),
            ToneStyle.Formal => EnsureTerminalPeriod(CapitalizeFirstCharacter(trimmed)),
            ToneStyle.VeryCasual => EnsureTerminalDotOrQuestion(CollapseRepeatedCommas(trimmed)),
            // Code (Windows-only): minimal formatting — leave casing/symbols/punctuation as spoken.
            ToneStyle.Code => trimmed,
            _ => trimmed,
        };
    }

    private static string NormalizeWhitespace(string text)
        => string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    /// Mirrors Swift's `CharacterSet.whitespaces`: tab (U+0009) + Unicode Space_Separator (Zs).
    /// It deliberately EXCLUDES newlines / line- & paragraph-separators — unlike `char.IsWhiteSpace`
    /// (i.e. `Split((char[]?)null, …)`). `extractCorrections` tokenizes on this exact set, so a word
    /// containing a newline must stay intact (TextProcessor.swift uses `.whitespaces` here, not
    /// `.whitespacesAndNewlines`).
    private static string[] SplitOnWhitespacesOnly(string text)
    {
        var words = new List<string>();
        int i = 0;
        while (i < text.Length)
        {
            while (i < text.Length && IsSwiftWhitespace(text[i])) i++;
            int start = i;
            while (i < text.Length && !IsSwiftWhitespace(text[i])) i++;
            if (i > start) words.Add(text[start..i]);
        }
        return words.ToArray();
    }

    private static bool IsSwiftWhitespace(char c)
        => c == '\t'
           || char.GetUnicodeCategory(c) == System.Globalization.UnicodeCategory.SpaceSeparator;

    public static string RemoveDisfluencies(string text)
    {
        // Case-aware (Mac b0bb390): a filler is lower-case or sentence-capitalised ("um", "Um"), never
        // ALL CAPS ("ER", "UM" are acronyms). "er" but never "err" — a verb ("to err is human"); a
        // drawn-out "errr" is still a filler. The lookarounds refuse a filler glued to a word by a
        // hyphen or apostrophe, so "Uh-oh", "Uh-huh" and "Mm-hmm" are words, not a filler plus debris.
        string stripped = Regex.Replace(text,
            @"(?<![\w'’-])(?:[Uu]m+h?|[Uu]hm+|[Uu]h+|[Ee]rm+|[Ee]r(?:rr+)?|[Aa]a*h+|[Hh]mm+)(?![\w'’-])[,.]?\s*", "");
        string result = NormalizeWhitespace(stripped.Trim());
        if (result.EndsWith(",")) result = result[..^1];
        return result;
    }

    /// Removes "[BLANK_AUDIO]"-style all-caps/underscore bracket sentinels.
    public static string StripDecoderArtifacts(string text)
    {
        string stripped = Regex.Replace(text, @"\[[A-Z_][A-Z_ ]*\]", " ");
        return NormalizeWhitespace(stripped).Trim();
    }

    /// Returns "" when the whole input is hallucination noise (silence sentinels).
    public static string RemoveWhisperHallucinations(string text)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return "";
        if (trimmed.All(c => ".,;:!? ".Contains(c))) return "";
        string[] blanklike =
        {
            "[BLANK_TEXT]", "BLANK_TEXT",
            "Thanks for watching!", "Thanks for watching.",
            "Thank you.", "Thank you for watching.",
            "Subscribe to my channel", "Subscribe to my channel.",
            "Please subscribe to my channel.",
            "Bye.", "Bye!",
        };
        foreach (var p in blanklike)
            if (string.Equals(trimmed, p, StringComparison.OrdinalIgnoreCase))
                return "";
        // Whisper's sub-second near-silence fingerprint (§7 #49): a recording under ~1 s of hum
        // (whisper pads it to 1 s) decodes to exactly the bare lowercase token "you" — observed
        // pasted three times from 0.7–0.9 s accidental presses (rawRms ≤ 0.005). Matched
        // case-SENSITIVELY and without punctuation, so a real one-word reply ("You." / "You!")
        // — which whisper capitalizes and punctuates — is untouched.
        if (string.Equals(trimmed, "you", StringComparison.Ordinal))
            return "";
        return text;
    }

    private static string ReplaceOccurrences(string needle, string text, string replacement)
    {
        string pattern = PhrasePattern(needle);
        // MatchEvaluator => literal replacement (no .NET $-group substitution surprises).
        return Regex.Replace(text, pattern, _ => replacement, RegexOptions.IgnoreCase);
    }

    private static string PhrasePattern(string phrase)
    {
        var components = phrase.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(Regex.Escape);
        // "Not glued to a word character" on both sides: exactly \b for letter/digit edges, and a
        // punctuated custom word (".NET", "C#") also matches standalone (Mac b0bb390).
        return @"(?<!\w)" + string.Join(@"\s+", components) + @"(?!\w)";
    }

    private static string RemoveTerminalPunctuation(string text)
    {
        int end = text.Length;
        while (end > 0 && ".!?".Contains(text[end - 1])) end--;
        return text[..end];
    }

    private static string CapitalizeFirstCharacter(string text)
    {
        if (text.Length == 0) return text;
        return char.ToUpperInvariant(text[0]) + text[1..];
    }

    /// Closing quotes/brackets that may follow a sentence's own terminal mark.
    private const string ClosingMarks = "\"'”’»)]}";

    private static string EnsureTerminalPeriod(string text)
    {
        if (text.Length == 0) return text;
        // Look past closing quotes/brackets (`He said "hello."` already ends); a colon, semicolon or
        // ellipsis is a deliberate ending too ("steps:").
        for (int i = text.Length - 1; i >= 0; i--)
        {
            if (ClosingMarks.Contains(text[i])) continue;
            return ".!?…:;".Contains(text[i]) ? text : text + ".";
        }
        return text + ".";
    }

    /// Collapses comma runs into ", " — but a lone comma between two digits is a thousands separator
    /// ("$1,000,000"), not a clause break, and is left alone (Mac b0bb390).
    private static string CollapseRepeatedCommas(string text)
        => Regex.Replace(text, @"(?!(?<=\d),\d)\s*,(?:\s*,)*\s*", ", ");

    private static string EnsureTerminalDotOrQuestion(string text)
    {
        int end = text.Length;
        while (end > 0 && (text[end - 1] == ' ' || text[end - 1] == ',')) end--;
        string result = text[..end];
        if (result.Length == 0) return result;
        char last = result[^1];
        if (last == '?' || last == '.') return result;
        if (last == '!') return result[..^1] + ".";
        return result + ".";
    }

    private static string TrimPunctuation(string s)
    {
        int start = 0, end = s.Length;
        while (start < end && char.IsPunctuation(s[start])) start++;
        while (end > start && char.IsPunctuation(s[end - 1])) end--;
        return s[start..end];
    }
}
