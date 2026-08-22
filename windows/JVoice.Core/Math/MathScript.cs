namespace JVoice.Core.Text;

/// Unicode super/subscript rendering, with a plain-text fallback.
///
/// Unicode only covers PART of the alphabet in each script (there is no subscript "b", no
/// superscript "q"), so every attachment is all-or-nothing: if every character of the operand
/// has a form, the pretty version is used ("x" + "2" → "x²", "a" + "n" → "aₙ"); otherwise the
/// universally-readable caret/underscore notation is emitted instead ("x^b", "lim_(x→0)").
/// Never a partial mix — "a_(i+1)" reads correctly, "aᵢ₊1" does not.
public static class MathScript
{
    private const string SuperFrom = "0123456789+-=()abcdefghijklmnoprstuvwxyzABDEGHIJKLMNOPRTUVW";
    private const string SuperTo = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ";

    private const string SubFrom = "0123456789+-=()aehijklmnoprstuvxβγρφχ";
    private const string SubTo = "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵦᵧᵨᵩᵪ";

    /// The operand rendered as superscript characters, or null when any character lacks one.
    public static string? Super(string plain) => Map(plain, SuperFrom, SuperTo);

    /// The operand rendered as subscript characters, or null when any character lacks one.
    public static string? Sub(string plain) => Map(plain, SubFrom, SubTo);

    /// <paramref name="baseText"/> with <paramref name="operand"/> attached as a script.
    /// Falls back to "^"/"_" (bracketing anything longer than one character) when the operand
    /// cannot be rendered in Unicode.
    public static string Attach(string baseText, string operand, bool superscript)
    {
        string? pretty = superscript ? Super(operand) : Sub(operand);
        if (pretty is not null) return baseText + pretty;

        // A single character needs no brackets ("a_b"); anything longer only reaches this
        // fallback because it contains something unscriptable, and reads far better closed
        // ("e^(iπ)", "lim_(x→0)", "∫₀^(√2)") than run together.
        char marker = superscript ? '^' : '_';
        return operand.Length == 1
            ? $"{baseText}{marker}{operand}"
            : $"{baseText}{marker}({operand})";
    }

    private static string? Map(string plain, string from, string to)
    {
        if (plain.Length == 0) return null;
        var sb = new System.Text.StringBuilder(plain.Length);
        foreach (char c in plain)
        {
            int i = from.IndexOf(c);
            if (i < 0) return null;
            sb.Append(to[i]);
        }
        return sb.ToString();
    }
}
