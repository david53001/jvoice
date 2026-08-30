namespace JVoice.Core.Text;

/// Unicode super/subscript and fraction rendering, with a plain-text fallback.
///
/// Unicode only covers PART of the alphabet in each script (there is no subscript "b", no
/// superscript "q"), so every attachment is all-or-nothing: if every character of the operand
/// has a form, the pretty version is used ("x" + "2" → "x²", "a" + "n" → "aₙ"); otherwise the
/// universally-readable caret/underscore notation is emitted instead ("x^b", "lim_(x→0)").
/// Never a partial mix — "a_(i+1)" reads correctly, "aᵢ₊1" does not.
///
/// <see cref="Fraction"/> follows the same all-or-nothing discipline for the stacked form
/// David asked for ("1 over 2" → "½", "22 over 7" → "²²⁄₇"); when the two sides are not both
/// small enough to stack, it returns null and <see cref="MathSpeech"/> writes "÷" instead.
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

    /// Fractions Unicode has a single precomposed glyph for — the best-looking form and the
    /// most widely supported. The recent additions (⅐ ⅑ ⅒ ↉) are deliberately absent: too many
    /// fonts still draw them as a blank box, and the built form ("¹⁄₇") reads the same everywhere.
    private static readonly Dictionary<string, string> Vulgar = new()
    {
        ["1/2"] = "½",
        ["1/3"] = "⅓", ["2/3"] = "⅔",
        ["1/4"] = "¼", ["3/4"] = "¾",
        ["1/5"] = "⅕", ["2/5"] = "⅖", ["3/5"] = "⅗", ["4/5"] = "⅘",
        ["1/6"] = "⅙", ["5/6"] = "⅚",
        ["1/8"] = "⅛", ["3/8"] = "⅜", ["5/8"] = "⅝", ["7/8"] = "⅞",
    };

    /// The two operands written as ONE stacked fraction — "½", "²²⁄₇", "ˣ⁄ₙ" — or null when
    /// they cannot be: either side that is not a plain number or a single letter, or a letter
    /// with no script form (there is no subscript "y"), would produce something less readable
    /// than the division sign the caller falls back to. "sin(x) over x" is exactly that case:
    /// "ˢⁱⁿ⁽ˣ⁾⁄ₓ" is technically renderable and completely illegible.
    public static string? Fraction(string numerator, string denominator)
    {
        if (!IsAtomic(numerator) || !IsAtomic(denominator)) return null;
        if (Vulgar.TryGetValue(numerator + "/" + denominator, out string? glyph)) return glyph;
        if (Super(numerator) is not { } top || Sub(denominator) is not { } bottom) return null;
        return top + FractionSlash + bottom;
    }

    /// U+2044, the typographic fraction slash — it leans further than "/" and tells a font
    /// that these digits are a fraction.
    private const char FractionSlash = '⁄';

    private static bool IsAtomic(string operand) =>
        operand.Length > 0
        && (operand.All(char.IsAsciiDigit) || (operand.Length == 1 && char.IsLetter(operand[0])));

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
