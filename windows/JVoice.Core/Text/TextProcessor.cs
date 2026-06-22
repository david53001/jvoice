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
        ["jvoice"] = "JVoice",
        ["keyboard shortcuts"] = "KeyboardShortcuts",
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
        var originalWords = original.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var correctedWords = corrected.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

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

        return variants.Where(v => v.Length > 0 && v != word).ToList();
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
            _ => trimmed,
        };
    }

    private static string NormalizeWhitespace(string text)
        => string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    public static string RemoveDisfluencies(string text)
    {
        string stripped = Regex.Replace(text, @"\b(um+h?|uh+|er+|a+h+|hmm+)\b[,.]?\s*", "", RegexOptions.IgnoreCase);
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
        return @"\b" + string.Join(@"\s+", components) + @"\b";
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

    private static string EnsureTerminalPeriod(string text)
    {
        if (text.Length == 0) return text;
        char last = text[^1];
        return ".!?".Contains(last) ? text : text + ".";
    }

    private static string CollapseRepeatedCommas(string text)
        => Regex.Replace(text, @"\s*,(?:\s*,)*\s*", ", ");

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
