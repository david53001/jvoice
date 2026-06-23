using JVoice.Core.Models;

namespace JVoice.Core.Text;

/// Folds the user's <see cref="CorrectionRule"/>s into the post-processing
/// "extra dictionary" that <see cref="TextProcessor.Process"/> already consumes.
///
/// This is the *only* glue the corrections feature needs on the brain side:
/// TextProcessor stays a verbatim port of the macOS source. The merged dictionary
/// is keyed by the lower-cased "heard" phrase (TextProcessor matches keys
/// case-insensitively and treats internal spaces as `\s+`, so single words and
/// multi-word phrases both work), and the value is the literal replacement.
public static class UserCorrections
{
    /// Returns <paramref name="spokenVariants"/> (from
    /// <see cref="TextProcessor.BuildUserDictionary"/>) overlaid with the user's
    /// correction rules. A rule overrides a spoken-variant entry on key collision;
    /// later rules win over earlier ones. Rules whose trimmed <c>From</c> or
    /// <c>To</c> is empty are skipped. The built-in
    /// <see cref="TextProcessor.CorrectionDictionary"/> still overrides everything
    /// here — that precedence is applied inside <see cref="TextProcessor.ApplyCorrections"/>.
    public static IReadOnlyDictionary<string, string> Merge(
        IReadOnlyDictionary<string, string> spokenVariants,
        IReadOnlyList<CorrectionRule> rules)
    {
        var dict = new Dictionary<string, string>(spokenVariants);
        foreach (var rule in rules)
        {
            string key = (rule.From ?? string.Empty).Trim().ToLowerInvariant();
            string value = (rule.To ?? string.Empty).Trim();
            if (key.Length == 0 || value.Length == 0) continue;
            dict[key] = value;
        }
        return dict;
    }
}
