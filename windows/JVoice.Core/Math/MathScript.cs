using System.Globalization;
using System.Text;

namespace JVoice.Core.Text;

/// Unicode super/subscript and fraction rendering, with a plain-text fallback.
///
/// Unicode only covers PART of the alphabet in each script (there is no subscript "b", no
/// superscript "q"), so every attachment is all-or-nothing: if every character of the operand
/// has a form, the pretty version is used ("x" + "2" → "x²", "a" + "n" → "aₙ"); otherwise the
/// universally-readable caret/underscore notation is emitted instead ("x^b", "lim_(x→0)").
/// Never a partial mix — "a_(i+1)" reads correctly, "aᵢ₊1" does not.
///
/// The second half of the file is the LAYOUT of the shared notation format
/// (`docs/mac-reference/math-notation-format.md`, Mac 2026-09-29 — the same format
/// BetterScreenshot's Capture Text pastes): "over" is a slash fraction whose sides get
/// parentheses when they hold a space or an operator (`(a + b)/2`, `1/(x ln 2)`), a radicand is
/// bracketed when it is more than one number or letter (`√(2x)`), trig and log functions take a
/// one-token argument after a space (`sin θ`, `ln 2`, `log₂8`), and a spoken "times" is `×`
/// between numbers but juxtaposition between letter terms (`6 × 7`, `2ab`, `(n - 1)d`).
/// Ported 1:1 from the Mac's `MathScript.swift` (parity rows 22–25).
///
/// <see cref="Fraction"/> (the stacked "½", "²²⁄₇") is UNUSED by <see cref="MathSpeech"/> since
/// the shared format: many fonts draw the stacked form badly and it cannot be edited. Kept, as
/// on the Mac.
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

    // ─────────────────────── layout (math-notation-format.md) ───────────────────────
    //
    // Every test below walks Unicode SCALARS (Runes): each symbol it looks for is a single
    // scalar, and a long chain ("x squared squared …") re-tests a growing operand at every step.

    /// Operators that make an operand "more than one term" when they sit at its top level.
    private static readonly HashSet<int> GroupingOperators = Codes("+-×÷±∓·/*=<>≤≥≠≈→∈∉∪∩∖∣⇒⇔≡∝");
    private static readonly HashSet<int> Openers = Codes("([{⟨⌊⌈");
    private static readonly HashSet<int> Closers = Codes(")]}⟩⌋⌉");

    /// Script characters and postfixes that decorate a single number or letter without making
    /// it a second one: the "2" of "x²", the "n" of "aₙ", "!", "′", "°".
    private static readonly HashSet<int> Decorations = Codes(SuperTo + SubTo + "′″‴!°%ᵀ†");

    private static HashSet<int> Codes(string chars)
    {
        var set = new HashSet<int>();
        foreach (Rune r in chars.EnumerateRunes()) set.Add(r.Value);
        return set;
    }

    private static Rune[] Scalars(string text)
    {
        var list = new List<Rune>(text.Length);
        foreach (Rune r in text.EnumerateRunes()) list.Add(r);
        return list.ToArray();
    }

    private static bool IsDecoration(Rune r) =>
        Decorations.Contains(r.Value) || Rune.GetUnicodeCategory(r) == UnicodeCategory.NonSpacingMark;

    private static bool IsLetter(Rune r) => Rune.IsLetter(r);

    private static bool IsDigit(Rune r) => r.Value is >= '0' and <= '9';

    /// True when <paramref name="operand"/> holds a space or an operator OUTSIDE every bracket
    /// and |bars| — the test for "more than one term" (spec principle 6). A leading sign counts
    /// only when <paramref name="leadingSign"/> is true (a denominator, `1/(-3)`); a numerator
    /// keeps `-b/2`. A slash counts only when <paramref name="slash"/> is true: a numerator that
    /// is itself a fraction needs no brackets ("a/b/c" is already (a/b)/c).
    public static bool NeedsGrouping(string operand, bool leadingSign = true, bool slash = true)
    {
        int depth = 0;
        bool inBars = false, first = true;
        foreach (Rune r in operand.EnumerateRunes())
        {
            bool atStart = first;
            first = false;
            int v = r.Value;
            if (Openers.Contains(v)) { depth++; continue; }
            if (Closers.Contains(v)) { depth--; continue; }
            if (v == '|') { inBars = !inBars; continue; }
            if (depth != 0 || inBars) continue;
            if (v == ' ') return true;
            if (GroupingOperators.Contains(v))
            {
                if (atStart && !leadingSign && (v == '-' || v == '+' || v == '±')) continue;
                if (v == '/' && !slash) continue;
                return true;
            }
        }
        return false;
    }

    /// True when the whole operand sits inside ONE pair of brackets or bars: "(x + 1)",
    /// "|x - 1|" — not "(a)(b)" or "|a||b|".
    public static bool IsWrapped(string operand) => IsWrapped(Scalars(operand));

    private static bool IsWrapped(ReadOnlySpan<Rune> s)
    {
        if (s.Length < 2) return false;
        int first = s[0].Value, last = s[^1].Value;
        if (first == '|')
        {
            if (last != '|') return false;
            int bars = 0;
            foreach (Rune r in s) if (r.Value == '|') bars++;
            return bars == 2;
        }
        if (!Openers.Contains(first) || !Closers.Contains(last)) return false;
        int depth = 0;
        for (int i = 0; i < s.Length; i++)
        {
            int v = s[i].Value;
            if (Openers.Contains(v)) depth++;
            else if (Closers.Contains(v))
            {
                depth--;
                if (depth == 0 && i != s.Length - 1) return false;
            }
        }
        return depth == 0;
    }

    /// A named function applied in brackets: "f(x)", "C(n, k)", "P(A ∣ B)", "log₂(x + 1)".
    public static bool IsApplication(string operand) => IsApplication(Scalars(operand));

    private static bool IsApplication(ReadOnlySpan<Rune> s)
    {
        if (s.Length == 0 || s[^1].Value != ')') return false;
        int open = -1;
        for (int i = 0; i < s.Length; i++) if (s[i].Value == '(') { open = i; break; }
        if (open <= 0) return false;
        if (!IsLetter(s[0]) || Decorations.Contains(s[0].Value)) return false;
        for (int i = 0; i < open; i++)
        {
            Rune r = s[i];
            if (!(IsLetter(r) || IsDigit(r) || IsDecoration(r) || r.Value == '_')) return false;
        }
        return IsWrapped(s[open..]);
    }

    /// Contains no letter at all — "7", "2.5", "10⁸", "5!", "½", "√2" — so a "divided by"
    /// between two of them keeps the school ÷ (spec §3: "6 × 7 ÷ 2").
    public static bool IsNumeric(string operand)
    {
        if (operand.Length == 0) return false;
        foreach (Rune r in operand.EnumerateRunes()) if (IsLetter(r)) return false;
        return true;
    }

    /// "over" (and "divided by" in algebra) as a slash: "π/6", "(a + b)/2", "1/(x ln 2)",
    /// "(sin x)/x". A side gets parentheses when it holds a space or an operator — and a
    /// DENOMINATOR also when it is a juxtaposed product ("1/(2a)"), because "x/2a" reads as
    /// (x/2)·a everywhere a formula is evaluated; a numerator product needs none.
    public static string SlashFraction(string numerator, string denominator)
    {
        string top = NeedsGrouping(numerator, leadingSign: false, slash: false) ? $"({numerator})" : numerator;
        string bottom = NeedsGrouping(denominator) || IsJuxtaposedProduct(denominator)
            ? $"({denominator})" : denominator;
        return top + "/" + bottom;
    }

    /// How many factors stand side by side at the top level: "2a" 2, "ab" 2, "2(x + 1)" 2,
    /// "πr²" 2, "(n - k)!" 1, "x²" 1, "10⁸" 1, "2.5" 1 — a bracketed group and a digit run are
    /// one factor each, script characters and postfixes none.
    private static int TopLevelFactors(ReadOnlySpan<Rune> s)
    {
        int factors = 0, depth = 0;
        bool inNumber = false;
        foreach (Rune r in s)
        {
            if (IsDecoration(r)) continue;
            int v = r.Value;
            if (Openers.Contains(v))
            {
                if (depth == 0) factors++;
                depth++;
                inNumber = false;
                continue;
            }
            if (Closers.Contains(v)) { depth--; continue; }
            if (depth > 0) continue;
            if (IsDigit(r) || v == '.')
            {
                if (!inNumber) factors++;
                inNumber = true;
            }
            else
            {
                inNumber = false;
                if (IsLetter(r)) factors++;
            }
        }
        return factors;
    }

    /// Two or more factors standing together with no operator: "2a", "ab", "2π", "πr²", "2√3".
    /// Not a single decorated atom ("x²", "aₙ", "10⁸"), a differential ("dx"), an application
    /// ("f(x)", "C(52, 5)"), a bracketed group, or a caret/underscore fallback.
    private static bool IsJuxtaposedProduct(string operand)
    {
        if (IsWrapped(operand) || IsApplication(operand) || IsDifferential(operand)) return false;
        if (operand.Contains('_') || operand.Contains('^')) return false;
        return TopLevelFactors(Scalars(operand)) >= 2;
    }

    /// "√14", "√x", "√x²", "√-1" — and "√(2x)", "√(b² - 4ac)": the radicand is bracketed when
    /// it is more than one number or letter.
    public static string Radical(string sign, string radicand) =>
        RadicandNeedsBrackets(radicand) ? $"{sign}({radicand})" : sign + radicand;

    private static bool RadicandNeedsBrackets(string radicand)
    {
        if (IsWrapped(radicand)) return false;
        if (NeedsGrouping(radicand, leadingSign: false)) return true;
        ReadOnlySpan<Rune> core = Scalars(radicand);
        if (core.Length > 0 && core[0].Value is '-' or '+' or '±') core = core[1..];
        if (IsWrapped(core) || IsApplication(core)) return false;
        return TopLevelFactors(core) >= 2;
    }

    /// Functions written WITHOUT brackets around a one-token argument: "sin θ", "cos 2θ",
    /// "ln 2" — and tight after a script, "sin²θ", "log₂8". Every other function keeps its
    /// brackets: "f(x)", "det(A)", "max(x)".
    private static readonly HashSet<string> SpacedFunctions = new()
    {
        "sin", "cos", "tan", "sec", "csc", "cot", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "coth", "arcsinh", "arccosh", "arctanh", "log", "ln",
    };

    private static string AsciiLetterPrefix(string text)
    {
        int n = 0;
        while (n < text.Length && char.IsAsciiLetter(text[n])) n++;
        return text[..n];
    }

    private static bool SpacedFunctionName(string text) => SpacedFunctions.Contains(AsciiLetterPrefix(text));

    /// <paramref name="name"/> applied to <paramref name="argument"/>: "sin θ", "sin²θ",
    /// "log₂8", "sin(x + 1)", "log_b(x)", "f(x)". The brackets appear only when the argument is
    /// more than one term, or the name needs them.
    public static string ApplyFunction(string name, string argument)
    {
        if (argument.StartsWith('(') && IsWrapped(argument)) return name + argument;
        string bare = AsciiLetterPrefix(name);
        if (!SpacedFunctions.Contains(bare) || NeedsGrouping(argument)) return $"{name}({argument})";
        string script = name[bare.Length..];
        if (script.Length == 0) return $"{name} {argument}";
        // A fallback base or power ("log_b", "sin^(…)") would run into the argument.
        if (script.Contains('_') || script.Contains('^')) return $"{name}({argument})";
        return name + argument;
    }

    /// How a spoken "times" joins its two sides (spec principle 4): "×" between numbers and
    /// wherever standing together would misread ("x × 2", "V/2 × T", "C(26, 4) × C(10, 3)"), a
    /// space before a trig/log function or a differential ("2 sin x cos x", "x² dx"), and
    /// nothing at all otherwise — letters, brackets and roots multiply by juxtaposition ("2y",
    /// "ab", "(n - 1)d", "(x - 2)(x - 3)", "3√2").
    public static string ProductSeparator(string left, string right)
    {
        const string cross = " × ";
        if (right.Length == 0 || left.Length == 0) return cross;
        Rune r = Rune.GetRuneAt(right, 0);
        Rune l = Scalars(left)[^1];
        if (Rune.IsNumber(r) || "+-±∓.∞".Contains(r.ToString(), StringComparison.Ordinal)) return cross;
        if (l.Value is '%' or '°' || ContainsTopLevelSlash(left)) return cross;
        // "√K³" then "Kx²": standing together they would read as one radicand, √(K³Kx²).
        if (EndsInOpenRadical(left)) return cross;
        if (SpacedFunctionName(right) || IsDifferential(right)) return " ";
        if (IsApplication(left) || IsApplication(right)) return cross;
        if (NeedsGrouping(left, leadingSign: false) || NeedsGrouping(right)) return cross;
        return "";
    }

    /// What a power attaches to: a slash fraction is bracketed first — "5 over 6 to the fourth"
    /// is (5/6)⁴, never 5/6⁴.
    public static string PowerBase(string baseText) =>
        ContainsTopLevelSlash(baseText) ? $"({baseText})" : baseText;

    private static bool IsDifferential(string operand)
    {
        Rune[] s = Scalars(operand);
        return s.Length == 2 && s[0].Value == 'd' && IsLetter(s[1]);
    }

    /// A root sign at the top level whose radicand is NOT bracketed ("√K³", "3√2"): whatever is
    /// written straight after it would look like more radicand.
    private static bool EndsInOpenRadical(string operand)
    {
        Rune[] s = Scalars(operand);
        int depth = 0;
        for (int i = 0; i < s.Length; i++)
        {
            int v = s[i].Value;
            if (Openers.Contains(v)) depth++;
            else if (Closers.Contains(v)) depth--;
            if (depth != 0 || !(v is '√' or '∛' or '∜')) continue;
            if (i + 1 < s.Length && s[i + 1].Value != '(') return true;
        }
        return false;
    }

    private static bool ContainsTopLevelSlash(string operand)
    {
        int depth = 0;
        foreach (Rune r in operand.EnumerateRunes())
        {
            int v = r.Value;
            if (Openers.Contains(v)) depth++;
            else if (Closers.Contains(v)) depth--;
            if (v == '/' && depth == 0) return true;
        }
        return false;
    }

    /// A grouped script is written without its brackets or its spaces: "x to the quantity n
    /// plus 1" → "xⁿ⁺¹", "a sub open paren n plus 1 close paren" → "aₙ₊₁" (principle 3:
    /// nothing goes inside scripts but the script).
    public static string ScriptOperand(string operand)
    {
        Rune[] s = Scalars(operand);
        if (s.Length > 0 && s[0].Value == '(' && IsWrapped(operand)) s = s[1..^1];
        var sb = new StringBuilder(operand.Length);
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i].Value == ' ')
            {
                int before = i > 0 ? s[i - 1].Value : ' ';
                int after = i + 1 < s.Length ? s[i + 1].Value : ' ';
                if (GroupingOperators.Contains(before) || GroupingOperators.Contains(after)) continue;
            }
            sb.Append(s[i].ToString());
        }
        return sb.ToString();
    }

    private static string? Map(string plain, string from, string to)
    {
        if (plain.Length == 0) return null;
        var sb = new StringBuilder(plain.Length);
        foreach (char c in plain)
        {
            int i = from.IndexOf(c);
            if (i < 0) return null;
            sb.Append(to[i]);
        }
        return sb.ToString();
    }
}
