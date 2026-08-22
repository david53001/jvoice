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
/// ── The exclusion audit (locked by <c>MathSymbolsTests</c>) ────────────────────────────
/// Everyday English words that are NOT here, and why. Each is reachable through the user's
/// own custom words / correction rules, or through the "start equation … end equation"
/// escape hatch, which outrank this pack by design:
///   • bare "and" / "or" / "not" — only "logical and/or/not" (a bare ∧ would eat
///     "God is the alpha and the omega").
///   • "is" / "are" / "by" / "in" / "on" / "at" / "than" — the connective tissue of every
///     sentence; as a Relation they would turn ordinary clauses into equations.
///   • "cross" — "the cross of Christ". Only "cross product" / "cartesian product" → ×.
///   • "sin" / "cos" / "tan" / "sec" / "cot" — the bare three-letter trig abbreviations are
///     ordinary English ("my sin", "a tan", "wait a sec"). The spelled-out spoken forms
///     ("sine", "cosine", "tangent" …) carry the whole trig vocabulary instead.
///   • "sign" — "a sign from God"; only "signum" → sgn.
///   • "cup" / "cap" — "a cup of coffee"; ∪/∩ are said as "union"/"intersect".
///   • "power" / "square" / "root" — the constructs the ENGINE parses ("to the power of",
///     "square root of") already cover these; the bare nouns are ordinary speech.
///   • "change in" / "change of" — a Prefix Δ would rewrite "a change in 5 minutes" as "Δ5".
///     A Prefix needs only ONE operand after it, so no everyday word may ever be one.
///   • "for some" / "for any" — "for some 20 years he served" would become "∃20 years".
///     The quantifiers that ARE here ("for all", "there exists") are weak Operands for the
///     same reason: as Prefixes they turned "for all three of us" into "∀3 of us".
///   • "union over" — "the union over 200 workers voted" is about a labour union. Only
///     "big union" opens ⋃.
///   • "since" / "about" / bare "approximately" — ordinary discourse markers; the gain over
///     "because" / "is approximately equal to" is nil.
///   • "less" / "add" / "subtract" / "contains" / "arc" / "image of" — everyday verbs and
///     nouns whose mathematical readings are already covered by longer, unambiguous forms.
///   • bare Greek GLYPH keys ("α", "Σ") — the dictionary is case-INSENSITIVE, so "Σ" and "σ"
///     would collide onto one entry and render the wrong case. Greek is reached by name.
///   • "!" / "(" / ")" / "…" — punctuation the tokenizer peels off a word before matching,
///     so such a key could never be hit. Only glyphs that survive peeling are listed.
///
/// <see cref="ReservedPhrases"/> lists the spoken forms the ENGINE owns (it parses them with
/// their operands). They must never appear as keys here — <c>MathSymbolsTests</c> asserts it.
public static class MathSymbols
{
    /// Prefixes whose body follows after a SPACE ("∑ᵢ₌₁ⁿ i²") rather than binding tight ("√x").
    public static readonly IReadOnlySet<string> BigOperators =
        new HashSet<string> { "∑", "∏", "∫", "∬", "∭", "∮", "⋃", "⋂", "⨁", "lim" };

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

        // One call per Greek letter, so the capitals are mechanical and COMPLETE: every letter
        // is reachable as "capital x" / "big x" / "uppercase x". Weak operands throughout —
        // "the alpha version" can never activate anything.
        void Greek(string lower, string upper, params string[] names)
        {
            Add(lower, MathKind.Operand, names);
            foreach (var n in names)
                Add(upper, MathKind.Operand, "capital " + n, "big " + n, "uppercase " + n);
        }

        // ═══════════════════════════ relations ═══════════════════════════
        // Infix, ACTIVATING, operand required on BOTH sides.

        // equality & inequality
        Add("=", MathKind.Relation,
            "equals", "equal to", "is equal to", "is equals to", "is the same as", "the same as", "=");
        Add("≠", MathKind.Relation,
            "not equal to", "is not equal to", "does not equal", "not equals", "isn't equal to",
            "is unequal to", "≠", "!=");
        Add("<", MathKind.Relation, "less than", "is less than", "is smaller than", "is fewer than", "<");
        Add(">", MathKind.Relation, "greater than", "is greater than", "more than", "is more than",
            "is bigger than", "is larger than", ">");
        Add("≤", MathKind.Relation, "less than or equal to", "is less than or equal to",
            "less than or equal", "at most", "is at most", "no more than", "<=", "≤");
        Add("≥", MathKind.Relation, "greater than or equal to", "is greater than or equal to",
            "greater than or equal", "at least", "is at least", "no less than", ">=", "≥");
        Add("≪", MathKind.Relation, "much less than", "is much less than", "far less than");
        Add("≫", MathKind.Relation, "much greater than", "is much greater than", "far greater than");

        // approximation, equivalence, definition
        Add("≈", MathKind.Relation, "approximately equal to", "approximately equals",
            "is approximately", "is approximately equal to", "is roughly equal to",
            "roughly equals", "≈");
        Add("≡", MathKind.Relation, "is equivalent to", "equivalent to", "congruent modulo",
            "is congruent to", "congruent to", "≡");
        Add("≅", MathKind.Relation, "is isomorphic to", "isomorphic to", "≅");
        Add("≔", MathKind.Relation, "is defined as", "is defined to be", "is defined by", "colon equals");
        Add("∝", MathKind.Relation, "is proportional to", "proportional to", "varies as",
            "varies directly as", "∝");
        Add("∼", MathKind.Relation, "is distributed as", "distributed as", "follows the distribution",
            "is similar to", "similar to", "∼");

        // set membership & containment
        Add("∈", MathKind.Relation, "is an element of", "element of", "is in the set", "belongs to",
            "is a member of", "member of", "∈");
        Add("∉", MathKind.Relation, "is not an element of", "not an element of",
            "does not belong to", "is not a member of", "∉");
        Add("⊆", MathKind.Relation, "is a subset of", "subset of", "is contained in",
            "is a subset of or equal to", "⊆");
        Add("⊂", MathKind.Relation, "is a proper subset of", "proper subset of", "⊂");
        Add("⊇", MathKind.Relation, "is a superset of", "superset of", "contains the set", "⊇");
        Add("⊃", MathKind.Relation, "is a proper superset of", "proper superset of", "⊃");
        Add("⊄", MathKind.Relation, "is not a subset of", "not a subset of");

        // geometry
        Add("⊥", MathKind.Relation, "is perpendicular to", "perpendicular to",
            "is orthogonal to", "orthogonal to", "⊥");
        Add("∥", MathKind.Relation, "is parallel to", "parallel to", "∥");

        // divisibility, conditioning, set-builder — all print the vertical bar.
        // KNOWN RESIDUAL: "given" needs an operand on both sides, which "for a given day" and
        // "he was given 5 dollars" never supply — but "for a given n" does, and comes out as
        // "for a ∣ n". Kept because conditional probability has no other spoken form; delete
        // the one word from this line if it ever bites.
        Add("∣", MathKind.Relation, "divides", "is a divisor of", "is a factor of",
            "given", "given that", "such that", "conditional on", "conditioned on");
        Add("∤", MathKind.Relation, "does not divide", "doesn't divide");

        // ═══════════════════════════ operators ═══════════════════════════
        // Infix, ACTIVATING, operand required on BOTH sides.

        // arithmetic
        Add("+", MathKind.Operator, "plus", "added to", "+");
        Add("-", MathKind.Operator, "minus", "take away");
        Add("×", MathKind.Operator, "times", "multiplied by", "cross product",
            "cartesian product", "×");
        Add("÷", MathKind.Operator, "divided by", "÷");
        Add("/", MathKind.Operator, "per");                 // "m per s" → "m / s"
        Add("±", MathKind.Operator, "plus or minus", "plus minus", "±");
        Add("∓", MathKind.Operator, "minus or plus");

        // products of vectors & spaces
        Add("·", MathKind.Operator, "dot product", "dot", "inner product", "scalar product", "·");
        Add("⊗", MathKind.Operator, "tensor product", "kronecker product", "outer product",
            "circle times", "⊗");
        Add("⊕", MathKind.Operator, "direct sum", "circle plus", "exclusive or", "xor", "⊕");
        Add("∘", MathKind.Operator, "composed with", "circle operator");

        // sets
        Add("∪", MathKind.Operator, "union", "union with", "∪");
        Add("∩", MathKind.Operator, "intersect", "intersection with", "intersected with",
            "intersect with", "∩");
        Add("∖", MathKind.Operator, "set minus", "set difference", "∖");

        // logic & modular arithmetic
        Add("∧", MathKind.Operator, "logical and", "∧");
        Add("∨", MathKind.Operator, "logical or", "∨");
        Add("mod", MathKind.Operator, "modulo", "mod", "reduced modulo");
        Add("⊢", MathKind.Operator, "entails", "logically entails", "⊢");

        // arrows
        Add("→", MathKind.Operator, "maps to", "arrow", "right arrow", "rightwards arrow", "→", "->");
        Add("↦", MathKind.Operator, "is mapped to", "gets mapped to", "↦");
        Add("←", MathKind.Operator, "left arrow", "leftwards arrow", "←");
        Add("↔", MathKind.Operator, "left right arrow", "two way arrow", "↔");
        Add("⇒", MathKind.Operator, "implies", "implies that", "double right arrow", "⇒", "=>");
        Add("⇐", MathKind.Operator, "is implied by", "implied by", "double left arrow", "⇐");
        Add("⇔", MathKind.Operator, "if and only if", "iff", "is logically equivalent to",
            "double arrow", "⇔", "<=>");

        // inference. NEVER a Prefix: "∴" would then rewrite "therefore 3 of us left". As an
        // Operator it needs an operand on BOTH sides, which sentence-initial "Therefore, …"
        // (the Biblical usage) never has. Residual: "psalm 3 therefore 4 makes sense".
        Add("∴", MathKind.Operator, "therefore", "thus", "hence", "∴");
        Add("∵", MathKind.Operator, "because", "∵");

        // combinatorics — "n choose k" → "n C k"
        Add("C", MathKind.Operator, "choose");

        // ════════════════════════════ prefixes ════════════════════════════
        // ACTIVATING on a SINGLE operand after them — the easiest kind to trigger by accident,
        // so every entry here is either a symbol name or ends in "of" (which forces the next
        // word to be an operand, not an article).

        Add("-", MathKind.Prefix, "negative", "negative of", "the negative of");
        Add("√", MathKind.Prefix, "radical", "√");

        // integrals (big operators: their body follows after a space)
        Add("∫", MathKind.Prefix, "integral", "integral of", "the integral of", "∫");
        Add("∬", MathKind.Prefix, "double integral", "double integral of", "∬");
        Add("∭", MathKind.Prefix, "triple integral", "triple integral of", "∭");
        Add("∮", MathKind.Prefix, "contour integral", "line integral", "closed integral", "∮");

        // vector calculus (tight-binding: "∇²u", "∇×F")
        Add("∂", MathKind.Prefix, "partial", "∂");
        Add("∇", MathKind.Prefix, "nabla", "del", "gradient of", "gradient", "∇");
        Add("∇²", MathKind.Prefix, "laplacian", "laplacian of", "the laplacian of");
        Add("∇×", MathKind.Prefix, "curl of", "the curl of");
        Add("∇·", MathKind.Prefix, "divergence of", "the divergence of");

        // logic
        Add("¬", MathKind.Prefix, "logical not", "negation of", "¬");

        // indexed set / algebra operators (big operators). "union over" is NOT here: "the
        // union over 200 workers voted" is ordinary English about a labour union, and a big
        // operator with a body would have rewritten it as "⋃ 200 workers voted".
        Add("⋃", MathKind.Prefix, "big union");
        Add("⋂", MathKind.Prefix, "big intersection", "intersection over", "the intersection over");
        Add("⨁", MathKind.Prefix, "big direct sum", "direct sum over");

        // ════════════════════════════ postfixes ═══════════════════════════
        // Weak: they attach to the operand before them and never activate a run.
        Add("!", MathKind.Postfix, "factorial");
        Add("!!", MathKind.Postfix, "double factorial");
        Add("%", MathKind.Postfix, "percent", "per cent", "%");
        Add("‰", MathKind.Postfix, "per mille", "permille");
        Add("°", MathKind.Postfix, "degrees", "degree", "°");
        Add("°C", MathKind.Postfix, "degrees celsius", "degrees centigrade");
        Add("°F", MathKind.Postfix, "degrees fahrenheit");
        Add("′", MathKind.Postfix, "prime", "arc minutes", "arcminutes");
        Add("″", MathKind.Postfix, "double prime", "arc seconds", "arcseconds");
        Add("‴", MathKind.Postfix, "triple prime");
        Add("ᵀ", MathKind.Postfix, "transpose", "transposed");
        Add("†", MathKind.Postfix, "dagger", "conjugate transpose", "hermitian conjugate");
        Add("⁻¹", MathKind.Postfix, "inverse");
        Add("ᶜ", MathKind.Postfix, "complement");
        Add("Ω", MathKind.Postfix, "ohms", "ohm");
        Add("Å", MathKind.Postfix, "angstroms", "angstrom");
        Add("rad", MathKind.Postfix, "radians", "radian");

        // ════════════════════════════ operands ════════════════════════════
        // Weak values. Generous by design — they only render inside an activated run.

        // quantifiers. Weak on PURPOSE, even though "∀x" would read better than "∀ x": a
        // Prefix needs only one operand after it, and "for all three of us" / "for every one
        // of you" put a NUMBER right there — "∀3 of us" is exactly the bleed this feature
        // must never produce. As operands they still render inside a run that a relation
        // opened ("for all x greater than 0" → "∀ x > 0") and stay words everywhere else.
        Add("∀", MathKind.Operand, "for all", "for every");
        Add("∃", MathKind.Operand, "there exists", "there exist", "there is some");
        Add("∃!", MathKind.Operand, "there exists a unique", "there is a unique",
            "there exists exactly one");
        Add("∄", MathKind.Operand, "there does not exist", "there is no such");

        // constants & infinities
        Add("∞", MathKind.Operand, "infinity", "∞");
        Add("ℏ", MathKind.Operand, "h bar", "reduced planck constant");
        Add("ℵ", MathKind.Operand, "aleph");
        Add("ℵ₀", MathKind.Operand, "aleph null", "aleph zero", "aleph naught");
        Add("∅", MathKind.Operand, "empty set", "the empty set", "null set", "the null set", "∅");

        // number sets
        Add("ℕ", MathKind.Operand, "the natural numbers", "natural numbers", "the naturals");
        Add("ℤ", MathKind.Operand, "the integers", "the whole numbers", "integers");
        Add("ℚ", MathKind.Operand, "the rationals", "the rational numbers", "rationals");
        Add("ℝ", MathKind.Operand, "the reals", "the real numbers", "reals");
        Add("ℂ", MathKind.Operand, "the complex numbers", "the complexes", "complex numbers");
        Add("ℍ", MathKind.Operand, "the quaternions");
        Add("ℙ", MathKind.Operand, "the primes", "the prime numbers");
        Add("𝒩", MathKind.Operand, "the normal distribution", "normal distribution");

        // physics constants (weak, so "the speed of light" stays prose outside an equation)
        Add("c", MathKind.Operand, "the speed of light");
        Add("h", MathKind.Operand, "planck's constant", "plancks constant");
        Add("k_B", MathKind.Operand, "boltzmann's constant", "boltzmanns constant");
        Add("N_A", MathKind.Operand, "avogadro's number", "avogadros number");
        Add("R", MathKind.Operand, "the gas constant");
        Add("G", MathKind.Operand, "the gravitational constant");
        Add("µ", MathKind.Operand, "micro");

        // greek — the complete alphabet, lower case by name and upper case as "capital x"
        Greek("α", "Α", "alpha");
        Greek("β", "Β", "beta");
        Greek("γ", "Γ", "gamma");
        Greek("δ", "Δ", "delta");
        Greek("ε", "Ε", "epsilon", "varepsilon");
        Greek("ζ", "Ζ", "zeta");
        Greek("η", "Η", "eta");
        Greek("θ", "Θ", "theta", "vartheta");
        Greek("ι", "Ι", "iota");
        Greek("κ", "Κ", "kappa");
        Greek("λ", "Λ", "lambda");
        Greek("μ", "Μ", "mu");
        Greek("ν", "Ν", "nu");
        Greek("ξ", "Ξ", "xi");
        Greek("ο", "Ο", "omicron");
        Greek("π", "Π", "pi");
        Greek("ρ", "Ρ", "rho", "varrho");
        Greek("σ", "Σ", "sigma");
        Greek("τ", "Τ", "tau");
        Greek("υ", "Υ", "upsilon");
        Greek("φ", "Φ", "phi", "varphi");
        Greek("χ", "Χ", "chi");
        Greek("ψ", "Ψ", "psi");
        Greek("ω", "Ω", "omega");
        Add("ς", MathKind.Operand, "varsigma", "final sigma");

        // statistics & vector notation spoken as two words
        Add("x̄", MathKind.Operand, "x bar");
        Add("ȳ", MathKind.Operand, "y bar");
        Add("x̃", MathKind.Operand, "x tilde");
        Add("p̂", MathKind.Operand, "p hat");
        Add("x̂", MathKind.Operand, "x hat");
        Add("î", MathKind.Operand, "i hat");
        Add("ĵ", MathKind.Operand, "j hat");
        Add("k̂", MathKind.Operand, "k hat");

        // differentials — whisper writes "dx" as one word, but dictates it as two
        Add("dx", MathKind.Operand, "d x");
        Add("dy", MathKind.Operand, "d y");
        Add("dz", MathKind.Operand, "d z");
        Add("dt", MathKind.Operand, "d t");
        Add("du", MathKind.Operand, "d u");
        Add("dv", MathKind.Operand, "d v");
        Add("dr", MathKind.Operand, "d r");
        Add("dθ", MathKind.Operand, "d theta");

        // geometry & proof glyphs
        Add("∠", MathKind.Operand, "angle", "the angle", "∠");
        Add("△", MathKind.Operand, "triangle", "△");
        Add("⌒", MathKind.Operand, "circular arc");
        Add("∎", MathKind.Operand, "q e d", "qed", "end of proof");
        Add("…", MathKind.Operand, "ellipsis", "dot dot dot");
        Add("✓", MathKind.Operand, "check mark", "checkmark");

        // ════════════════════════════ functions ═══════════════════════════
        // Weak: they wrap the ONE operand after them — "sine of x" → "sin(x)" — and never
        // activate. The bare abbreviations sin/cos/tan/sec/cot are deliberately absent.

        // trigonometry
        Add("sin", MathKind.Function, "sine", "sine of");
        Add("cos", MathKind.Function, "cosine", "cosine of");
        Add("tan", MathKind.Function, "tangent", "tangent of");
        Add("sec", MathKind.Function, "secant", "secant of");
        Add("csc", MathKind.Function, "cosecant", "cosecant of", "cosec");
        Add("cot", MathKind.Function, "cotangent", "cotangent of");
        Add("arcsin", MathKind.Function, "arc sine", "arcsine", "inverse sine", "arc sine of");
        Add("arccos", MathKind.Function, "arc cosine", "arccosine", "inverse cosine");
        Add("arctan", MathKind.Function, "arc tangent", "arctangent", "inverse tangent");
        Add("sinh", MathKind.Function, "hyperbolic sine", "hyperbolic sine of", "sinh");
        Add("cosh", MathKind.Function, "hyperbolic cosine", "hyperbolic cosine of", "cosh");
        Add("tanh", MathKind.Function, "hyperbolic tangent", "hyperbolic tangent of", "tanh");
        Add("coth", MathKind.Function, "hyperbolic cotangent", "coth");
        Add("arcsinh", MathKind.Function, "inverse hyperbolic sine", "arsinh");
        Add("arccosh", MathKind.Function, "inverse hyperbolic cosine", "arcosh");
        Add("arctanh", MathKind.Function, "inverse hyperbolic tangent", "artanh");

        // logs & exponentials
        Add("log", MathKind.Function, "log", "logarithm", "logarithm of", "log of");
        Add("log₁₀", MathKind.Function, "log base ten", "log base 10", "common logarithm");
        Add("log₂", MathKind.Function, "log base two", "log base 2", "binary logarithm");
        Add("ln", MathKind.Function, "natural log", "natural log of", "natural logarithm",
            "log base e", "ln");
        Add("exp", MathKind.Function, "exponential of", "the exponential of");
        Add("sgn", MathKind.Function, "signum", "signum of", "the signum of");

        // sizes & parts
        Add("norm", MathKind.Function, "norm of", "the norm of", "magnitude of",
            "the magnitude of", "modulus of", "the modulus of");
        Add("card", MathKind.Function, "cardinality of", "the cardinality of");
        Add("floor", MathKind.Function, "floor of", "the floor of");
        Add("ceil", MathKind.Function, "ceiling of", "the ceiling of");
        Add("Re", MathKind.Function, "real part of", "the real part of");
        Add("Im", MathKind.Function, "imaginary part of", "the imaginary part of");

        // linear algebra
        Add("det", MathKind.Function, "determinant of", "the determinant of");
        Add("tr", MathKind.Function, "trace of", "the trace of");
        Add("rank", MathKind.Function, "rank of", "the rank of");
        Add("dim", MathKind.Function, "dimension of", "the dimension of");
        Add("ker", MathKind.Function, "kernel of", "the kernel of");
        Add("span", MathKind.Function, "span of", "the span of");

        // number theory & extrema
        Add("gcd", MathKind.Function, "gcd of", "the gcd of",
            "greatest common divisor of", "the greatest common divisor of");
        Add("lcm", MathKind.Function, "lcm of", "the lcm of",
            "least common multiple of", "the least common multiple of");
        Add("max", MathKind.Function, "max of", "the max of", "maximum of", "the maximum of");
        Add("min", MathKind.Function, "min of", "the min of", "minimum of", "the minimum of");
        Add("sup", MathKind.Function, "supremum of", "the supremum of");
        Add("inf", MathKind.Function, "infimum of", "the infimum of");
        Add("argmax", MathKind.Function, "arg max of", "the arg max of");
        Add("argmin", MathKind.Function, "arg min of", "the arg min of");

        // probability & statistics
        Add("P", MathKind.Function, "probability of", "the probability of");
        Add("E", MathKind.Function, "expected value of", "the expected value of",
            "expectation of", "the expectation of");
        Add("Var", MathKind.Function, "variance of", "the variance of");
        Add("Cov", MathKind.Function, "covariance of", "the covariance of");
        Add("Corr", MathKind.Function, "correlation of", "the correlation of");
        Add("SD", MathKind.Function, "standard deviation of", "the standard deviation of");
        Add("mean", MathKind.Function, "mean of", "the mean of", "average of", "the average of");
        Add("median", MathKind.Function, "median of", "the median of");
        Add("mode", MathKind.Function, "mode of", "the mode of");
        Add("𝒫", MathKind.Function, "power set of", "the power set of");

        // ═══════════════════════════ brackets ════════════════════════════
        // "of <thing>" takes ONE operand (a Function); "that <clause>" takes a whole
        // proposition, so it opens a bracket the run closes for us:
        //   "the probability of x equals 0.5"        → "P(x) = 0.5"
        //   "the probability that x is more than 5"  → "P(x > 5)"
        Add("P(", MathKind.Open, "probability that", "the probability that",
            "conditional probability of", "the conditional probability of");

        Add("(", MathKind.Open, "open parenthesis", "open parentheses", "open paren",
            "open bracket", "left parenthesis", "left paren", "left bracket", "open round bracket");
        Add(")", MathKind.Close, "close parenthesis", "close parentheses", "close paren",
            "close bracket", "right parenthesis", "right paren", "right bracket",
            "close round bracket");
        Add("[", MathKind.Open, "open square bracket", "left square bracket", "open square");
        Add("]", MathKind.Close, "close square bracket", "right square bracket", "close square");
        Add("{", MathKind.Open, "open brace", "open curly brace", "left brace", "left curly brace");
        Add("}", MathKind.Close, "close brace", "close curly brace", "right brace",
            "right curly brace");
        Add("⟨", MathKind.Open, "open angle bracket", "left angle bracket", "open angle");
        Add("⟩", MathKind.Close, "close angle bracket", "right angle bracket", "close angle");
        Add("⌊", MathKind.Open, "left floor", "open floor bracket", "floor bracket");
        Add("⌋", MathKind.Close, "right floor", "close floor bracket");
        Add("⌈", MathKind.Open, "left ceiling", "open ceiling bracket", "ceiling bracket");
        Add("⌉", MathKind.Close, "right ceiling", "close ceiling bracket");

        return d;
    }
}
