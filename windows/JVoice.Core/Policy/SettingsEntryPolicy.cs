namespace JVoice.Core;

/// <summary>
/// What a value typed into a Settings text field becomes, and — when it is turned away — the one-line reason shown
/// under the field, which keeps what was typed (parity row 19, doc §6.6; Mac <c>SettingsEntryPolicy.swift</c>). Before,
/// a refused entry was silently cleared (custom words) or silently ignored (app rules, corrections).
/// Blank input is never a rejection: the field just doesn't submit it.
/// </summary>
public static class SettingsEntryPolicy
{
    /// <summary>The Mac's custom-word length guard.</summary>
    public const int CustomWordMaxLength = 60;

    /// <summary>Why a custom word is turned away, or null when it would be added (or is blank).</summary>
    public static string? CustomWordRejection(string word, IEnumerable<string> existing)
    {
        var trimmed = word.Trim();
        if (trimmed.Length == 0) return null;
        if (trimmed.Length > CustomWordMaxLength)
            return $"Too long: a custom word can be up to {CustomWordMaxLength} characters.";
        if (!trimmed.Any(char.IsLetterOrDigit))
            return "A custom word needs at least one letter or number.";
        if (existing.FirstOrDefault(e => string.Equals(e, trimmed, StringComparison.OrdinalIgnoreCase)) is { } dup)
            return $"“{dup}” is already in your list.";
        return null;
    }

    /// <summary>
    /// Why an App Modes entry is turned away, or null when it becomes a rule. Windows rules match the foreground app's
    /// exe name by substring (<see cref="AppModeResolver"/>), so any name with a letter or number can match — only an
    /// app that already has a rule is refused (the Mac's "not found in Applications" has no Windows equivalent: the
    /// field's picker lists the open apps instead).
    /// </summary>
    public static string? AppRuleRejection(string typed, IEnumerable<string> existingMatches)
    {
        var trimmed = typed.Trim();
        if (trimmed.Length == 0) return null;
        if (!trimmed.Any(char.IsLetterOrDigit))
            return "An app name needs at least one letter or number.";
        if (existingMatches.FirstOrDefault(e => string.Equals(e.Trim(), trimmed, StringComparison.OrdinalIgnoreCase)) is { } dup)
            return $"“{dup.Trim()}” already has a mode. Remove it first to change it.";
        return null;
    }

    /// <summary>Why a correction is turned away, or null when it is added (or both fields are blank).</summary>
    public static string? CorrectionRejection(string from, string to, IEnumerable<string> existingFroms)
    {
        var f = from.Trim();
        var t = to.Trim();
        if (f.Length == 0 && t.Length == 0) return null;
        if (f.Length == 0) return "Type what JVoice hears on the left.";
        if (t.Length == 0) return "Type what it should become on the right.";
        if (string.Equals(f, t, StringComparison.Ordinal)) return "Both sides are the same, so there's nothing to fix.";
        if (existingFroms.FirstOrDefault(e => string.Equals(e.Trim(), f, StringComparison.OrdinalIgnoreCase)) is { } dup)
            return $"“{dup.Trim()}” already has a correction. Remove it first to change it.";
        return null;
    }
}
