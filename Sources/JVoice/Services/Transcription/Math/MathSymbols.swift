import Foundation

/// The spoken-mathematics VOCABULARY: "how it is said" → "what to print".
///
/// Data only. The grammar (subscripts, powers, roots, bounds, fractions, function
/// application, and the run-activation rules that keep ordinary speech untouched) lives in
/// `MathSpeech`; this file is the dictionary it reads.
///
/// Keys are lower-cased, single-spaced spoken forms and are matched LONGEST-FIRST, so
/// "less than or equal to" wins over "less than". Matching happens on punctuation-stripped
/// word cores, case-insensitively.
///
/// Curation rule (same discipline as `DeveloperTerms`): a phrase belongs here only if, WHEN
/// ITS OPERANDS ARE PRESENT, it is unambiguously mathematics. Everyday English words that
/// merely have a mathematical sense are dangerous in exactly one direction — they can
/// activate a run — so:
///   • `.relation`/`.operatorSymbol`/`.prefix` entries must be safe to activate on. They
///     still require operands, which is what makes "two times a day" ("a day" is not an
///     operand) and "plus I think we should go" safe.
///   • Weak kinds (operand/function/postfix/open/close) never activate anything, so they
///     can be generous: "pi", "alpha", "percent", "degrees" only render inside a run that
///     some ACTIVATING construct already opened.
///
/// ── The exclusion audit (locked by `MathSymbolsTests`) ────────────────────────────────
/// Everyday English words that are NOT here, and why. Each is reachable through the user's
/// own custom words / correction rules, or through the "start equation … end equation"
/// escape hatch, which outrank this pack by design:
///   • bare "and" / "or" / "not" — only "logical and/or/not" (a bare ∧ would eat "God is
///     the alpha and the omega").
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
///   • "change in" / "change of" — a Prefix Δ would rewrite "a change in 5 minutes" as
///     "Δ5". A Prefix needs only ONE operand after it, so no everyday word may ever be one.
///   • "for some" / "for any" — "for some 20 years he served" would become "∃20 years".
///     The quantifiers that ARE here ("for all", "there exists") are weak Operands for the
///     same reason: as Prefixes they turned "for all three of us" into "∀3 of us".
///   • "union over" — "the union over 200 workers voted" is about a labour union. Only
///     "big union" opens ⋃.
///   • "since" / "about" / bare "approximately" — ordinary discourse markers.
///   • "less" / "add" / "subtract" / "contains" / "arc" / "image of" — everyday verbs and
///     nouns whose mathematical readings are already covered by longer, unambiguous forms.
///   • bare Greek GLYPH keys ("α", "Σ") — the dictionary is case-INSENSITIVE, so "Σ" and
///     "σ" would collide onto one entry and render the wrong case. Greek is reached by name.
///   • "!" / "(" / ")" / "…" — punctuation the tokenizer peels off a word before matching,
///     so such a key could never be hit. Only glyphs that survive peeling are listed.
///
/// `reservedPhrases` lists the spoken forms the ENGINE owns (it parses them with their
/// operands). They must never appear as keys here — `MathSymbolsTests` asserts it.
///
/// Ported 1:1 from the Windows port's `JVoice.Core/Math/MathSymbols.cs`.
public enum MathSymbols {
    /// Prefixes that do NOT count as evidence of mathematics. A spoken sign is a number
    /// FORM, not an operation: measured against 1,174 of David's real Windows dictations,
    /// "negative" was the one prefix that fired in ordinary speech ("between 60 and
    /// negative 50"). It still renders inside a run something else activated ("x = -5").
    public static let weakPrefixes: Set<String> = ["-"]

    /// Prefixes whose body follows after a SPACE ("∑ᵢ₌₁ⁿ i²") rather than binding tight ("√x").
    public static let bigOperators: Set<String> = ["∑", "∏", "∫", "∬", "∭", "∮", "⋃", "⋂", "⨁", "lim"]

    /// Spoken forms parsed structurally by `MathSpeech`. Never add these as keys.
    public static let reservedPhrases: Set<String> = [
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
    ]

    /// Spoken phrase (lower-case, single-spaced) → symbol.
    public static let phrases: [String: MathSymbol] = build()

    /// Word count of the longest key — the window `match` scans down from.
    public static let maxPhraseWords: Int =
        phrases.keys.map { $0.split(separator: " ").count }.max() ?? 1

    /// Longest-match lookup of the vocabulary at `index`.
    /// `words` are punctuation-stripped word cores.
    public static func match(_ words: [String], _ index: Int) -> (symbol: MathSymbol, consumed: Int)? {
        let maxWindow = min(maxPhraseWords, words.count - index)
        guard maxWindow > 0 else { return nil }
        for n in stride(from: maxWindow, through: 1, by: -1) {
            let key = words[index..<(index + n)].joined(separator: " ").lowercased()
            if let found = phrases[key] { return (found, n) }
        }
        return nil
    }

    private static func build() -> [String: MathSymbol] {
        var d: [String: MathSymbol] = [:]

        func add(_ text: String, _ kind: MathKind, _ spoken: String...) {
            for s in spoken { d[s.lowercased()] = MathSymbol(text, kind) }
        }

        // One call per Greek letter, so the capitals are mechanical and COMPLETE: every
        // letter is reachable as "capital x" / "big x" / "uppercase x". Weak operands
        // throughout — "the alpha version" can never activate anything.
        func greek(_ lower: String, _ upper: String, _ names: String...) {
            for n in names {
                d[n.lowercased()] = MathSymbol(lower, .operand)
                for form in ["capital " + n, "big " + n, "uppercase " + n] {
                    d[form.lowercased()] = MathSymbol(upper, .operand)
                }
            }
        }

        // ═══════════════════════════ relations ═══════════════════════════
        // Infix, ACTIVATING, operand required on BOTH sides.

        // equality & inequality
        add("=", .relation,
            "equals", "equal to", "is equal to", "is equals to", "is the same as", "the same as", "=")
        add("≠", .relation,
            "not equal to", "is not equal to", "does not equal", "not equals", "isn't equal to",
            "is unequal to", "≠", "!=")
        add("<", .relation, "less than", "is less than", "is smaller than", "is fewer than", "<")
        add(">", .relation, "greater than", "is greater than", "more than", "is more than",
            "is bigger than", "is larger than", ">")
        add("≤", .relation, "less than or equal to", "is less than or equal to",
            "less than or equal", "at most", "is at most", "no more than", "<=", "≤")
        add("≥", .relation, "greater than or equal to", "is greater than or equal to",
            "greater than or equal", "at least", "is at least", "no less than", ">=", "≥")
        add("≪", .relation, "much less than", "is much less than", "far less than")
        add("≫", .relation, "much greater than", "is much greater than", "far greater than")

        // approximation, equivalence, definition
        add("≈", .relation, "approximately equal to", "approximately equals",
            "is approximately", "is approximately equal to", "is roughly equal to",
            "roughly equals", "≈")
        add("≡", .relation, "is equivalent to", "equivalent to", "congruent modulo",
            "is congruent to", "congruent to", "≡")
        add("≅", .relation, "is isomorphic to", "isomorphic to", "≅")
        add("≔", .relation, "is defined as", "is defined to be", "is defined by", "colon equals")
        add("∝", .relation, "is proportional to", "proportional to", "varies as",
            "varies directly as", "∝")
        add("∼", .relation, "is distributed as", "distributed as", "follows the distribution",
            "is similar to", "similar to", "∼")

        // set membership & containment
        add("∈", .relation, "is an element of", "element of", "is in the set", "belongs to",
            "is a member of", "member of", "∈")
        add("∉", .relation, "is not an element of", "not an element of",
            "does not belong to", "is not a member of", "∉")
        add("⊆", .relation, "is a subset of", "subset of", "is contained in",
            "is a subset of or equal to", "⊆")
        add("⊂", .relation, "is a proper subset of", "proper subset of", "⊂")
        add("⊇", .relation, "is a superset of", "superset of", "contains the set", "⊇")
        add("⊃", .relation, "is a proper superset of", "proper superset of", "⊃")
        add("⊄", .relation, "is not a subset of", "not a subset of")

        // geometry
        add("⊥", .relation, "is perpendicular to", "perpendicular to",
            "is orthogonal to", "orthogonal to", "⊥")
        add("∥", .relation, "is parallel to", "parallel to", "∥")

        // divisibility, conditioning, set-builder — all print the vertical bar.
        // KNOWN RESIDUAL: "given" needs an operand on both sides, which "for a given day"
        // and "he was given 5 dollars" never supply — but "for a given n" does, and comes
        // out as "for a ∣ n". Kept because conditional probability has no other spoken
        // form; delete the one word from this line if it ever bites.
        add("∣", .relation, "divides", "is a divisor of", "is a factor of",
            "given", "given that", "such that", "conditional on", "conditioned on")
        add("∤", .relation, "does not divide", "doesn't divide")

        // ═══════════════════════════ operators ═══════════════════════════
        // Infix, ACTIVATING, operand required on BOTH sides.

        // arithmetic
        add("+", .operatorSymbol, "plus", "added to", "+")
        add("-", .operatorSymbol, "minus", "take away")
        // Multiplication prints the MIDDLE DOT, not "×" (David, 2026-08-30): "3 · 4" is how
        // a multiplication is written once the operands are symbols, and "×" stays what it
        // is uniquely — the cross product. A resolution ("1600 times 1080") therefore also
        // comes out with a dot; consistency beats a special case here.
        add("·", .operatorSymbol, "times", "multiplied by", "dot product", "dot",
            "inner product", "scalar product", "·")
        add("×", .operatorSymbol, "cross product", "cartesian product", "×")
        add("÷", .operatorSymbol, "divided by", "÷")
        add("/", .operatorSymbol, "per")                 // "m per s" → "m / s"
        add("±", .operatorSymbol, "plus or minus", "plus minus", "±")
        add("∓", .operatorSymbol, "minus or plus")

        // products of vectors & spaces
        add("⊗", .operatorSymbol, "tensor product", "kronecker product", "outer product",
            "circle times", "⊗")
        add("⊕", .operatorSymbol, "direct sum", "circle plus", "exclusive or", "xor", "⊕")
        add("∘", .operatorSymbol, "composed with", "circle operator")

        // sets
        add("∪", .operatorSymbol, "union", "union with", "∪")
        add("∩", .operatorSymbol, "intersect", "intersection with", "intersected with",
            "intersect with", "∩")
        add("∖", .operatorSymbol, "set minus", "set difference", "∖")

        // logic & modular arithmetic
        add("∧", .operatorSymbol, "logical and", "∧")
        add("∨", .operatorSymbol, "logical or", "∨")
        add("mod", .operatorSymbol, "modulo", "mod", "reduced modulo")
        add("⊢", .operatorSymbol, "entails", "logically entails", "⊢")

        // arrows
        add("→", .operatorSymbol, "maps to", "arrow", "right arrow", "rightwards arrow", "→", "->")
        add("↦", .operatorSymbol, "is mapped to", "gets mapped to", "↦")
        add("←", .operatorSymbol, "left arrow", "leftwards arrow", "←")
        add("↔", .operatorSymbol, "left right arrow", "two way arrow", "↔")
        add("⇒", .operatorSymbol, "implies", "implies that", "double right arrow", "⇒", "=>")
        add("⇐", .operatorSymbol, "is implied by", "implied by", "double left arrow", "⇐")
        add("⇔", .operatorSymbol, "if and only if", "iff", "is logically equivalent to",
            "double arrow", "⇔", "<=>")

        // inference — the SPELLED-OUT connectives are deliberately absent. "because" as an
        // Operator was measured firing on real dictation ("…contradict genesis one because
        // i feel like…" → "genesis 1 ∵ i feel like"): a chapter number on the left and a
        // bare pronoun on the right satisfy an infix operator perfectly well, and
        // "therefore / thus / hence / because" are among the most common words in ordinary
        // speech. Only the glyphs stay, for a transcript that already contains them.
        add("∴", .operatorSymbol, "∴")
        add("∵", .operatorSymbol, "∵")

        // NOTE: "choose" is NOT here — MathSpeech parses it structurally so that
        // "n choose k" renders as the real binomial "C(n, k)".

        // ════════════════════════════ prefixes ════════════════════════════
        // ACTIVATING on a SINGLE operand after them — the easiest kind to trigger by
        // accident, so every entry here is either a symbol name or ends in "of" (which
        // forces the next word to be an operand, not an article).

        add("-", .prefix, "negative", "negative of", "the negative of")
        add("√", .prefix, "radical", "√")

        // integrals (big operators: their body follows after a space)
        add("∫", .prefix, "integral", "integral of", "the integral of", "∫")
        add("∬", .prefix, "double integral", "double integral of", "∬")
        add("∭", .prefix, "triple integral", "triple integral of", "∭")
        add("∮", .prefix, "contour integral", "line integral", "closed integral", "∮")

        // vector calculus (tight-binding: "∇²u", "∇×F")
        add("∂", .prefix, "partial", "∂")
        add("∇", .prefix, "nabla", "del", "gradient of", "gradient", "∇")
        add("∇²", .prefix, "laplacian", "laplacian of", "the laplacian of")
        add("∇×", .prefix, "curl of", "the curl of")
        add("∇·", .prefix, "divergence of", "the divergence of")

        // logic
        add("¬", .prefix, "logical not", "negation of", "¬")

        // indexed set / algebra operators (big operators). "union over" is NOT here: "the
        // union over 200 workers voted" is ordinary English about a labour union.
        add("⋃", .prefix, "big union")
        add("⋂", .prefix, "big intersection", "intersection over", "the intersection over")
        add("⨁", .prefix, "big direct sum", "direct sum over")

        // ════════════════════════════ postfixes ═══════════════════════════
        // Weak: they attach to the operand before them and never activate a run.
        add("!", .postfix, "factorial")
        add("!!", .postfix, "double factorial")
        add("%", .postfix, "percent", "per cent", "%")
        add("‰", .postfix, "per mille", "permille")
        add("°", .postfix, "degrees", "degree", "°")
        add("°C", .postfix, "degrees celsius", "degrees centigrade")
        add("°F", .postfix, "degrees fahrenheit")
        add("′", .postfix, "prime", "arc minutes", "arcminutes")
        add("″", .postfix, "double prime", "arc seconds", "arcseconds")
        add("‴", .postfix, "triple prime")
        add("ᵀ", .postfix, "transpose", "transposed")
        add("†", .postfix, "dagger", "conjugate transpose", "hermitian conjugate")
        add("⁻¹", .postfix, "inverse")
        add("ᶜ", .postfix, "complement")
        add("Ω", .postfix, "ohms", "ohm")
        add("Å", .postfix, "angstroms", "angstrom")
        add("rad", .postfix, "radians", "radian")

        // ════════════════════════════ operands ════════════════════════════
        // Weak values. Generous by design — they only render inside an activated run.

        // quantifiers. Weak on PURPOSE, even though "∀x" would read better than "∀ x": a
        // Prefix needs only one operand after it, and "for all three of us" / "for every
        // one of you" put a NUMBER right there — "∀3 of us" is exactly the bleed this
        // feature must never produce.
        add("∀", .operand, "for all", "for every")
        add("∃", .operand, "there exists", "there exist", "there is some")
        add("∃!", .operand, "there exists a unique", "there is a unique",
            "there exists exactly one")
        add("∄", .operand, "there does not exist", "there is no such")

        // constants & infinities
        add("∞", .operand, "infinity", "∞")
        add("ℏ", .operand, "h bar", "reduced planck constant")
        add("ℵ", .operand, "aleph")
        add("ℵ₀", .operand, "aleph null", "aleph zero", "aleph naught")
        add("∅", .operand, "empty set", "the empty set", "null set", "the null set", "∅")

        // number sets
        add("ℕ", .operand, "the natural numbers", "natural numbers", "the naturals")
        add("ℤ", .operand, "the integers", "the whole numbers", "integers")
        add("ℚ", .operand, "the rationals", "the rational numbers", "rationals")
        add("ℝ", .operand, "the reals", "the real numbers", "reals")
        add("ℂ", .operand, "the complex numbers", "the complexes", "complex numbers")
        add("ℍ", .operand, "the quaternions")
        add("ℙ", .operand, "the primes", "the prime numbers")
        add("𝒩", .operand, "the normal distribution", "normal distribution")

        // physics constants (weak, so "the speed of light" stays prose outside an equation)
        add("c", .operand, "the speed of light")
        add("h", .operand, "planck's constant", "plancks constant")
        add("k_B", .operand, "boltzmann's constant", "boltzmanns constant")
        add("N_A", .operand, "avogadro's number", "avogadros number")
        add("R", .operand, "the gas constant")
        add("G", .operand, "the gravitational constant")
        add("µ", .operand, "micro")

        // greek — the complete alphabet, lower case by name and upper case as "capital x"
        greek("α", "Α", "alpha")
        greek("β", "Β", "beta")
        greek("γ", "Γ", "gamma")
        greek("δ", "Δ", "delta")
        greek("ε", "Ε", "epsilon", "varepsilon")
        greek("ζ", "Ζ", "zeta")
        greek("η", "Η", "eta")
        greek("θ", "Θ", "theta", "vartheta")
        greek("ι", "Ι", "iota")
        greek("κ", "Κ", "kappa")
        greek("λ", "Λ", "lambda")
        greek("μ", "Μ", "mu")
        greek("ν", "Ν", "nu")
        greek("ξ", "Ξ", "xi")
        greek("ο", "Ο", "omicron")
        greek("π", "Π", "pi")
        greek("ρ", "Ρ", "rho", "varrho")
        greek("σ", "Σ", "sigma")
        greek("τ", "Τ", "tau")
        greek("υ", "Υ", "upsilon")
        greek("φ", "Φ", "phi", "varphi")
        greek("χ", "Χ", "chi")
        greek("ψ", "Ψ", "psi")
        greek("ω", "Ω", "omega")
        add("ς", .operand, "varsigma", "final sigma")

        // statistics & vector notation spoken as two words
        add("x̄", .operand, "x bar")
        add("ȳ", .operand, "y bar")
        add("x̃", .operand, "x tilde")
        add("p̂", .operand, "p hat")
        add("x̂", .operand, "x hat")
        add("î", .operand, "i hat")
        add("ĵ", .operand, "j hat")
        add("k̂", .operand, "k hat")

        // differentials — whisper writes "dx" as one word, but dictates it as two
        add("dx", .operand, "d x")
        add("dy", .operand, "d y")
        add("dz", .operand, "d z")
        add("dt", .operand, "d t")
        add("du", .operand, "d u")
        add("dv", .operand, "d v")
        add("dr", .operand, "d r")
        add("dθ", .operand, "d theta")

        // geometry & proof glyphs
        add("∠", .operand, "angle", "the angle", "∠")
        add("△", .operand, "triangle", "△")
        add("⌒", .operand, "circular arc")
        add("∎", .operand, "q e d", "qed", "end of proof")
        add("…", .operand, "ellipsis", "dot dot dot")
        add("✓", .operand, "check mark", "checkmark")

        // ════════════════════════════ functions ═══════════════════════════
        // Weak: they wrap the ONE operand after them — "sine of x" → "sin(x)" — and never
        // activate. The bare abbreviations sin/cos/tan/sec/cot are deliberately absent.

        // trigonometry
        add("sin", .function, "sine", "sine of")
        add("cos", .function, "cosine", "cosine of")
        add("tan", .function, "tangent", "tangent of")
        add("sec", .function, "secant", "secant of")
        add("csc", .function, "cosecant", "cosecant of", "cosec")
        add("cot", .function, "cotangent", "cotangent of")
        add("arcsin", .function, "arc sine", "arcsine", "inverse sine", "arc sine of")
        add("arccos", .function, "arc cosine", "arccosine", "inverse cosine")
        add("arctan", .function, "arc tangent", "arctangent", "inverse tangent")
        add("sinh", .function, "hyperbolic sine", "hyperbolic sine of", "sinh")
        add("cosh", .function, "hyperbolic cosine", "hyperbolic cosine of", "cosh")
        add("tanh", .function, "hyperbolic tangent", "hyperbolic tangent of", "tanh")
        add("coth", .function, "hyperbolic cotangent", "coth")
        add("arcsinh", .function, "inverse hyperbolic sine", "arsinh")
        add("arccosh", .function, "inverse hyperbolic cosine", "arcosh")
        add("arctanh", .function, "inverse hyperbolic tangent", "artanh")

        // logs & exponentials
        // "log base <n>" is NOT spelled out here: the engine parses "base" structurally, so
        // a vocabulary key like "log base 2" would win the longest-match and quietly bypass
        // the construct — printing the same "log₂" but never ACTIVATING the run.
        add("log", .function, "log", "logarithm", "logarithm of", "log of")
        add("log₁₀", .function, "common logarithm")
        add("log₂", .function, "binary logarithm")
        add("ln", .function, "natural log", "natural log of", "natural logarithm", "ln")
        add("exp", .function, "exponential of", "the exponential of")
        add("sgn", .function, "signum", "signum of", "the signum of")

        // sizes & parts
        add("norm", .function, "norm of", "the norm of", "magnitude of",
            "the magnitude of", "modulus of", "the modulus of")
        add("card", .function, "cardinality of", "the cardinality of")
        add("floor", .function, "floor of", "the floor of")
        add("ceil", .function, "ceiling of", "the ceiling of")
        add("Re", .function, "real part of", "the real part of")
        add("Im", .function, "imaginary part of", "the imaginary part of")

        // linear algebra
        add("det", .function, "determinant of", "the determinant of")
        add("tr", .function, "trace of", "the trace of")
        add("rank", .function, "rank of", "the rank of")
        add("dim", .function, "dimension of", "the dimension of")
        add("ker", .function, "kernel of", "the kernel of")
        add("span", .function, "span of", "the span of")

        // number theory & extrema
        add("gcd", .function, "gcd of", "the gcd of",
            "greatest common divisor of", "the greatest common divisor of")
        add("lcm", .function, "lcm of", "the lcm of",
            "least common multiple of", "the least common multiple of")
        add("max", .function, "max of", "the max of", "maximum of", "the maximum of")
        add("min", .function, "min of", "the min of", "minimum of", "the minimum of")
        add("sup", .function, "supremum of", "the supremum of")
        add("inf", .function, "infimum of", "the infimum of")
        add("argmax", .function, "arg max of", "the arg max of")
        add("argmin", .function, "arg min of", "the arg min of")

        // probability & statistics
        add("P", .function, "probability of", "the probability of")
        add("E", .function, "expected value of", "the expected value of",
            "expectation of", "the expectation of")
        add("Var", .function, "variance of", "the variance of")
        add("Cov", .function, "covariance of", "the covariance of")
        add("Corr", .function, "correlation of", "the correlation of")
        add("SD", .function, "standard deviation of", "the standard deviation of")
        add("mean", .function, "mean of", "the mean of", "average of", "the average of")
        add("median", .function, "median of", "the median of")
        add("mode", .function, "mode of", "the mode of")
        add("𝒫", .function, "power set of", "the power set of")

        // ═══════════════════════════ brackets ════════════════════════════
        // "of <thing>" takes ONE operand (a Function); "that <clause>" takes a whole
        // proposition, so it opens a bracket the run closes for us:
        //   "the probability of x equals 0.5"        → "P(x) = 0.5"
        //   "the probability that x is more than 5"  → "P(x > 5)"
        add("P(", .open, "probability that", "the probability that",
            "conditional probability of", "the conditional probability of")

        // Both word orders: David dictates "parentheses open" as readily as "open
        // parentheses" (measured — "5000 parentheses open, 1 plus 1.03 over 100" came out
        // with the words still in it because only one order was listed).
        add("(", .open, "open parenthesis", "open parentheses", "open paren",
            "open bracket", "left parenthesis", "left paren", "left bracket", "open round bracket",
            "parenthesis open", "parentheses open", "paren open", "bracket open")
        add(")", .close, "close parenthesis", "close parentheses", "close paren",
            "close bracket", "right parenthesis", "right paren", "right bracket",
            "close round bracket",
            "parenthesis close", "parentheses close", "paren close", "bracket close",
            "parenthesis closed", "parentheses closed", "bracket closed")
        add("[", .open, "open square bracket", "left square bracket", "open square",
            "square bracket open")
        add("]", .close, "close square bracket", "right square bracket", "close square",
            "square bracket close", "square bracket closed")
        add("{", .open, "open brace", "open curly brace", "left brace", "left curly brace",
            "brace open", "curly brace open")
        add("}", .close, "close brace", "close curly brace", "right brace",
            "right curly brace", "brace close", "curly brace close", "brace closed")
        add("⟨", .open, "open angle bracket", "left angle bracket", "open angle")
        add("⟩", .close, "close angle bracket", "right angle bracket", "close angle")
        add("⌊", .open, "left floor", "open floor bracket", "floor bracket")
        add("⌋", .close, "right floor", "close floor bracket")
        add("⌈", .open, "left ceiling", "open ceiling bracket", "ceiling bracket")
        add("⌉", .close, "right ceiling", "close ceiling bracket")

        return d
    }
}
