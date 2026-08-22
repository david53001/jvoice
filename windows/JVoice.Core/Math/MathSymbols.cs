namespace JVoice.Core.Text;

/// The spoken-mathematics VOCABULARY: "how it is said" → "what to print".
///
/// Data only. The grammar (subscripts, powers, roots, bounds, fractions, function
/// application, and the run-activation rules that keep ordinary speech untouched) lives in
/// <see cref="MathSpeech"/>; this file is the dictionary it reads.
///
/// Keys are lower-cased, single-spaced spoken forms and are matched LONGEST-FIRST, so
/// "less than or equal to" wins over "less than". Matching happens on punctuation-stripped
/// word cores, case-insensitively.
///
/// Curation rule (same discipline as <see cref="DeveloperTerms"/>): a phrase belongs here
/// only if, WHEN ITS OPERANDS ARE PRESENT, it is unambiguously mathematics. Everyday English
/// words that merely have a mathematical sense are dangerous in exactly one direction — they
/// can activate a run — so:
///   • <see cref="MathKind.Relation"/>/<see cref="MathKind.Operator"/>/<see cref="MathKind.Prefix"/>
///     entries must be safe to activate on. They still require operands, which is what makes
///     "two times a day" ("a day" is not an operand) and "plus I think we should go" safe.
///   • Weak kinds (Operand/Function/Postfix/Open/Close) never activate anything, so they can
///     be generous: "pi", "alpha", "percent", "degrees" only render inside a run that some
///     ACTIVATING construct already opened.
///
/// <see cref="ReservedPhrases"/> lists the spoken forms the ENGINE owns (it parses them with
/// their operands). They must never appear as keys here — <c>MathSymbolsTests</c> asserts it.
public static class MathSymbols
{
    /// Prefixes that do NOT count as evidence of mathematics. A spoken sign is a number FORM,
    /// not an operation: measured against 1,174 of David's real dictations, "negative" was the
    /// one prefix that fired in ordinary speech ("between 60 and negative 50" in a Minecraft
    /// design note). It still renders inside a run something else activated ("x = -5").
    public static readonly IReadOnlySet<string> WeakPrefixes = new HashSet<string> { "-" };

    /// Prefixes whose body follows after a SPACE ("∑ᵢ₌₁ⁿ i²") rather than binding tight ("√x").
    public static readonly IReadOnlySet<string> BigOperators =
        new HashSet<string> { "∑", "∏", "∫", "∬", "∭", "∮", "⋃", "⋂", "lim" };

    /// Spoken forms parsed structurally by <see cref="MathSpeech"/>. Never add these as keys.
    public static readonly IReadOnlySet<string> ReservedPhrases = new HashSet<string>
    {
        // scripts & powers
        "subscript", "sub", "superscript", "super", "sup",
        "squared", "cubed", "to the power of", "to the power", "raised to the power of",
        // roots
        "square root", "square root of", "cube root", "cube root of", "root", "root of",
        // fractions / grouping / bounds
        "over", "from", "to", "of", "point",
        // big-operator openers (bare "sum"/"product" are ordinary English — the engine only
        // accepts them with bounds, e.g. "sum from n equals 1 to infinity")
        "sum", "sums", "summation", "product", "products",
        // structural constructs
        "absolute value of", "absolute value", "derivative of", "partial derivative of",
        "with respect to", "limit", "limit as", "as", "approaches", "tends to", "goes to",
        "to the", "base", "choose", "the",
        // explicit span markers
        "start equation", "begin equation", "end equation", "end of equation",
    };

    /// Spoken phrase (lower-case, single-spaced) → symbol.
    public static readonly IReadOnlyDictionary<string, MathSymbol> Phrases = Build();

    /// Word count of the longest key — the window <see cref="TryMatch"/> scans down from.
    public static readonly int MaxPhraseWords =
        Phrases.Keys.Max(k => k.Count(c => c == ' ') + 1);

    /// Longest-match lookup of the vocabulary at <paramref name="index"/>.
    /// <paramref name="words"/> are punctuation-stripped word cores.
    public static bool TryMatch(
        IReadOnlyList<string> words, int index, out MathSymbol symbol, out int consumed)
    {
        int max = System.Math.Min(MaxPhraseWords, words.Count - index);
        for (int n = max; n >= 1; n--)
        {
            string key = string.Join(' ', words.Skip(index).Take(n)).ToLowerInvariant();
            if (Phrases.TryGetValue(key, out var found))
            {
                symbol = found;
                consumed = n;
                return true;
            }
        }
        symbol = null!;
        consumed = 0;
        return false;
    }

    private static Dictionary<string, MathSymbol> Build()
    {
        var d = new Dictionary<string, MathSymbol>(StringComparer.OrdinalIgnoreCase);

        void Add(string text, MathKind kind, params string[] spoken)
        {
            foreach (var s in spoken) d[s] = new MathSymbol(text, kind);
        }

        // ─────────────────────────── relations ───────────────────────────
        Add("=", MathKind.Relation, "equals", "equal to", "is equal to", "is equals to", "=");
        Add("≠", MathKind.Relation, "not equal to", "is not equal to", "does not equal", "not equals");
        Add("<", MathKind.Relation, "less than", "is less than", "<");
        Add(">", MathKind.Relation, "greater than", "is greater than", "more than", ">");
        Add("≤", MathKind.Relation, "less than or equal to", "is less than or equal to", "at most", "<=");
        Add("≥", MathKind.Relation, "greater than or equal to", "is greater than or equal to", "at least", ">=");
        Add("≈", MathKind.Relation, "approximately equal to", "approximately equals", "is approximately");
        Add("≡", MathKind.Relation, "is equivalent to", "equivalent to", "congruent modulo");
        Add("∝", MathKind.Relation, "is proportional to", "proportional to");

        // ─────────────────────────── operators ───────────────────────────
        Add("+", MathKind.Operator, "plus", "+");
        Add("-", MathKind.Operator, "minus", "take away");
        Add("×", MathKind.Operator, "times", "multiplied by");
        Add("÷", MathKind.Operator, "divided by");
        Add("±", MathKind.Operator, "plus or minus", "plus minus");
        Add("·", MathKind.Operator, "dot product", "dot");
        Add("∪", MathKind.Operator, "union", "union with");
        Add("∩", MathKind.Operator, "intersect", "intersection with", "intersected with");
        Add("∈", MathKind.Relation, "is an element of", "element of", "is in the set", "belongs to");
        Add("∉", MathKind.Relation, "is not an element of", "not an element of");
        Add("→", MathKind.Operator, "maps to", "arrow", "right arrow");
        Add("⇒", MathKind.Operator, "implies");
        Add("⇔", MathKind.Operator, "if and only if", "iff");
        Add("∧", MathKind.Operator, "logical and");
        Add("∨", MathKind.Operator, "logical or");
        Add("mod", MathKind.Operator, "modulo", "mod");

        // ──────────────────────────── prefixes ───────────────────────────
        Add("-", MathKind.Prefix, "negative");
        Add("√", MathKind.Prefix, "radical");
        Add("∫", MathKind.Prefix, "integral", "integral of", "the integral of");
        Add("∂", MathKind.Prefix, "partial");
        Add("∇", MathKind.Prefix, "nabla", "del", "gradient of", "gradient");
        Add("¬", MathKind.Prefix, "logical not", "negation of");
        Add("∀", MathKind.Prefix, "for all", "for every");
        Add("∃", MathKind.Prefix, "there exists", "there is some");

        // ──────────────────────────── postfixes ──────────────────────────
        Add("!", MathKind.Postfix, "factorial");
        Add("%", MathKind.Postfix, "percent");
        Add("°", MathKind.Postfix, "degrees", "degree");
        Add("′", MathKind.Postfix, "prime");
        Add("″", MathKind.Postfix, "double prime");

        // ──────────────────────────── operands ───────────────────────────
        Add("∞", MathKind.Operand, "infinity");
        Add("π", MathKind.Operand, "pi");
        Add("∅", MathKind.Operand, "empty set", "the empty set");
        Add("ℕ", MathKind.Operand, "the natural numbers", "natural numbers");
        Add("ℤ", MathKind.Operand, "the integers");
        Add("ℚ", MathKind.Operand, "the rationals", "the rational numbers");
        Add("ℝ", MathKind.Operand, "the reals", "the real numbers");
        Add("ℂ", MathKind.Operand, "the complex numbers");

        // greek (lower case)
        Add("α", MathKind.Operand, "alpha");
        Add("β", MathKind.Operand, "beta");
        Add("γ", MathKind.Operand, "gamma");
        Add("δ", MathKind.Operand, "delta");
        Add("ε", MathKind.Operand, "epsilon");
        Add("θ", MathKind.Operand, "theta");
        Add("λ", MathKind.Operand, "lambda");
        Add("μ", MathKind.Operand, "mu");
        Add("σ", MathKind.Operand, "sigma");
        Add("φ", MathKind.Operand, "phi");
        Add("ω", MathKind.Operand, "omega");
        // greek (capitals) — spoken explicitly
        Add("Δ", MathKind.Operand, "capital delta", "big delta");
        Add("Σ", MathKind.Operand, "capital sigma");
        Add("Ω", MathKind.Operand, "capital omega");

        // ──────────────────────────── functions ──────────────────────────
        Add("sin", MathKind.Function, "sine", "sine of");
        Add("cos", MathKind.Function, "cosine", "cosine of");
        Add("tan", MathKind.Function, "tangent", "tangent of");
        Add("log", MathKind.Function, "log", "logarithm", "logarithm of", "log of");
        Add("ln", MathKind.Function, "natural log", "natural log of", "natural logarithm");
        Add("exp", MathKind.Function, "exponential of");

        // ─────────────────────────── brackets ────────────────────────────
        Add("(", MathKind.Open, "open parenthesis", "open paren", "open bracket", "left parenthesis");
        Add(")", MathKind.Close, "close parenthesis", "close paren", "close bracket", "right parenthesis");
        Add("[", MathKind.Open, "open square bracket");
        Add("]", MathKind.Close, "close square bracket");
        Add("{", MathKind.Open, "open brace", "open curly brace");
        Add("}", MathKind.Close, "close brace", "close curly brace");

        return d;
    }
}
