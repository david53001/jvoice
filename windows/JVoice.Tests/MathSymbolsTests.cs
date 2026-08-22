using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

/// The spoken-mathematics VOCABULARY contract (§7 #47).
///
/// <see cref="MathSpeechTests"/> owns the GRAMMAR; this file owns the DICTIONARY: that the
/// lookup behaves (longest match, case-insensitive), that the entries are the kind they claim
/// to be, and — the half that matters most — that growing the vocabulary never let it bleed
/// into ordinary talking. The exclusion audit in
/// <see cref="Vocabulary_ExcludesEverydayEnglishWords"/> is the record of every everyday word
/// that was considered and deliberately left out.
public class MathSymbolsTests
{
    // ===== dictionary hygiene =====

    [Fact]
    public void Phrases_CoverTheWholeSpokenMathematicsVocabulary()
        => Assert.True(MathSymbols.Phrases.Count >= 600,
            $"expected a comprehensive dictionary, found {MathSymbols.Phrases.Count} spoken forms");

    [Fact]
    public void Keys_AreLowercasedSingleSpaced_AndValuesNonEmpty()
    {
        foreach (var (key, symbol) in MathSymbols.Phrases)
        {
            Assert.Equal(key.Trim(), key);
            Assert.Equal(key.ToLowerInvariant(), key);
            Assert.NotEqual(0, key.Length);
            Assert.DoesNotContain("  ", key);
            Assert.NotEqual(0, symbol.Text.Length);
        }
    }

    // MathSpeech peels leading/trailing punctuation off a word before matching, so a key
    // that starts or ends with any of it could never be hit — it would be dead weight.
    [Fact]
    public void Keys_NeverStartOrEndWithPunctuationTheTokenizerPeelsOff()
    {
        const string lead = "([{\"'“‘¿¡";
        const string trail = ",.;:!?)]}\"'”’…";
        foreach (var key in MathSymbols.Phrases.Keys)
            foreach (var word in key.Split(' '))
            {
                Assert.DoesNotContain(word[0], lead);
                Assert.DoesNotContain(word[^1], trail);
            }
    }

    [Fact]
    public void VocabularyNeverShadowsAConstructTheEngineParses()
    {
        Assert.NotEmpty(MathSymbols.ReservedPhrases);
        foreach (var reserved in MathSymbols.ReservedPhrases)
            Assert.False(MathSymbols.Phrases.ContainsKey(reserved),
                $"\"{reserved}\" is parsed structurally by MathSpeech — it must not be a vocabulary key.");
    }

    [Fact]
    public void MaxPhraseWords_MatchesTheLongestKey()
    {
        // "is a subset of or equal to" — the scan window TryMatch counts down from.
        Assert.Equal(7, MathSymbols.MaxPhraseWords);
        Assert.Equal(
            MathSymbols.Phrases.Keys.Max(k => k.Count(c => c == ' ') + 1),
            MathSymbols.MaxPhraseWords);
    }

    // Every big operator must actually be reachable as a prefix, or its space-separated
    // layout rule ("∑ᵢ₌₁ⁿ i²") would be unreachable dead configuration.
    [Fact]
    public void EveryBigOperator_IsReachableAsAPrefix()
    {
        // ∑ / ∏ / lim are spoken as ordinary English nouns, so MathSpeech mints them itself
        // (only with bounds) rather than trusting the vocabulary — see ReservedPhrases.
        string[] engineOwned = { "∑", "∏", "lim" };
        foreach (var op in MathSymbols.BigOperators)
        {
            if (engineOwned.Contains(op)) continue;
            Assert.Contains(MathSymbols.Phrases.Values,
                s => s.Text == op && s.Kind == MathKind.Prefix);
        }
    }

    [Fact]
    public void BigOperatorPrefixes_LayOutTheirBodyAfterASpace()
    {
        Assert.True(MathSymbols.Phrases["double integral"].IsBigOperator);
        Assert.False(MathSymbols.Phrases["radical"].IsBigOperator);   // "√x" binds tight
    }

    // ===== TryMatch =====

    [Fact]
    public void TryMatch_PrefersTheLongestPhrase()
    {
        var words = new[] { "less", "than", "or", "equal", "to", "5" };
        Assert.True(MathSymbols.TryMatch(words, 0, out var symbol, out int consumed));
        Assert.Equal("≤", symbol.Text);
        Assert.Equal(5, consumed);
    }

    [Fact]
    public void TryMatch_FallsBackToTheShorterPhrase()
    {
        var words = new[] { "less", "than", "5" };
        Assert.True(MathSymbols.TryMatch(words, 0, out var symbol, out int consumed));
        Assert.Equal("<", symbol.Text);
        Assert.Equal(2, consumed);
    }

    [Fact]
    public void TryMatch_IsCaseInsensitive()
    {
        var words = new[] { "Capital", "SIGMA" };
        Assert.True(MathSymbols.TryMatch(words, 0, out var symbol, out int consumed));
        Assert.Equal("Σ", symbol.Text);
        Assert.Equal(2, consumed);
    }

    [Fact]
    public void TryMatch_MatchesAtAnIndexInsideTheSentence()
    {
        var words = new[] { "x", "is", "an", "element", "of", "the", "reals" };
        Assert.True(MathSymbols.TryMatch(words, 1, out var symbol, out int consumed));
        Assert.Equal("∈", symbol.Text);
        Assert.Equal(4, consumed);
    }

    [Fact]
    public void TryMatch_RefusesOrdinaryWords()
    {
        var words = new[] { "tomorrow", "morning" };
        Assert.False(MathSymbols.TryMatch(words, 0, out var symbol, out int consumed));
        Assert.Null(symbol);
        Assert.Equal(0, consumed);
    }

    [Fact]
    public void TryMatch_DoesNotRunPastTheEndOfTheSentence()
    {
        // "less than or equal to" is 5 words but only 2 remain — the window must shrink.
        var words = new[] { "x", "less", "than" };
        Assert.True(MathSymbols.TryMatch(words, 1, out var symbol, out int consumed));
        Assert.Equal("<", symbol.Text);
        Assert.Equal(2, consumed);
    }

    // ===== representative lookups, category by category =====

    public static TheoryData<string, string, MathKind> Lookups() => new()
    {
        // relations
        { "is not equal to", "≠", MathKind.Relation },
        { "at least", "≥", MathKind.Relation },
        { "much greater than", "≫", MathKind.Relation },
        { "is approximately equal to", "≈", MathKind.Relation },
        { "is congruent to", "≡", MathKind.Relation },
        { "is isomorphic to", "≅", MathKind.Relation },
        { "is defined as", "≔", MathKind.Relation },
        { "is proportional to", "∝", MathKind.Relation },
        { "is distributed as", "∼", MathKind.Relation },
        { "is a member of", "∈", MathKind.Relation },
        { "is a subset of", "⊆", MathKind.Relation },
        { "is a proper superset of", "⊃", MathKind.Relation },
        { "is perpendicular to", "⊥", MathKind.Relation },
        { "is parallel to", "∥", MathKind.Relation },
        { "divides", "∣", MathKind.Relation },
        { "such that", "∣", MathKind.Relation },
        { "does not divide", "∤", MathKind.Relation },

        // operators
        { "multiplied by", "×", MathKind.Operator },
        { "cross product", "×", MathKind.Operator },
        { "per", "/", MathKind.Operator },
        { "plus or minus", "±", MathKind.Operator },
        { "dot product", "·", MathKind.Operator },
        { "tensor product", "⊗", MathKind.Operator },
        { "direct sum", "⊕", MathKind.Operator },
        { "xor", "⊕", MathKind.Operator },
        { "set minus", "∖", MathKind.Operator },
        { "logical and", "∧", MathKind.Operator },
        { "modulo", "mod", MathKind.Operator },
        { "is mapped to", "↦", MathKind.Operator },
        { "if and only if", "⇔", MathKind.Operator },
        { "therefore", "∴", MathKind.Operator },
        { "because", "∵", MathKind.Operator },
        { "choose", "C", MathKind.Operator },

        // prefixes
        { "negative", "-", MathKind.Prefix },
        { "radical", "√", MathKind.Prefix },
        { "contour integral", "∮", MathKind.Prefix },
        { "triple integral", "∭", MathKind.Prefix },
        { "gradient of", "∇", MathKind.Prefix },
        { "the laplacian of", "∇²", MathKind.Prefix },
        { "the curl of", "∇×", MathKind.Prefix },
        { "logical not", "¬", MathKind.Prefix },
        { "big union", "⋃", MathKind.Prefix },
        { "direct sum over", "⨁", MathKind.Prefix },

        // postfixes
        { "factorial", "!", MathKind.Postfix },
        { "percent", "%", MathKind.Postfix },
        { "degrees celsius", "°C", MathKind.Postfix },
        { "double prime", "″", MathKind.Postfix },
        { "transpose", "ᵀ", MathKind.Postfix },
        { "inverse", "⁻¹", MathKind.Postfix },
        { "conjugate transpose", "†", MathKind.Postfix },
        { "ohms", "Ω", MathKind.Postfix },

        // operands — quantifiers are deliberately WEAK
        { "for all", "∀", MathKind.Operand },
        { "there exists", "∃", MathKind.Operand },
        { "there exists a unique", "∃!", MathKind.Operand },
        { "there does not exist", "∄", MathKind.Operand },

        // operands — constants, sets, greek
        { "infinity", "∞", MathKind.Operand },
        { "h bar", "ℏ", MathKind.Operand },
        { "aleph null", "ℵ₀", MathKind.Operand },
        { "the empty set", "∅", MathKind.Operand },
        { "the integers", "ℤ", MathKind.Operand },
        { "the quaternions", "ℍ", MathKind.Operand },
        { "the speed of light", "c", MathKind.Operand },
        { "epsilon", "ε", MathKind.Operand },
        { "omicron", "ο", MathKind.Operand },
        { "upsilon", "υ", MathKind.Operand },
        { "capital psi", "Ψ", MathKind.Operand },
        { "big xi", "Ξ", MathKind.Operand },
        { "uppercase theta", "Θ", MathKind.Operand },
        { "x bar", "x̄", MathKind.Operand },
        { "p hat", "p̂", MathKind.Operand },
        { "d theta", "dθ", MathKind.Operand },
        { "triangle", "△", MathKind.Operand },
        { "qed", "∎", MathKind.Operand },

        // functions
        { "cosine of", "cos", MathKind.Function },
        { "cosecant", "csc", MathKind.Function },
        { "arc tangent", "arctan", MathKind.Function },
        { "hyperbolic sine", "sinh", MathKind.Function },
        { "log base two", "log₂", MathKind.Function },
        { "natural logarithm", "ln", MathKind.Function },
        { "the determinant of", "det", MathKind.Function },
        { "the trace of", "tr", MathKind.Function },
        { "the greatest common divisor of", "gcd", MathKind.Function },
        { "the supremum of", "sup", MathKind.Function },
        { "the expected value of", "E", MathKind.Function },
        { "the variance of", "Var", MathKind.Function },
        { "the probability of", "P", MathKind.Function },
        { "the power set of", "𝒫", MathKind.Function },
        { "the norm of", "norm", MathKind.Function },

        // brackets
        { "the probability that", "P(", MathKind.Open },
        { "open paren", "(", MathKind.Open },
        { "close square bracket", "]", MathKind.Close },
        { "left curly brace", "{", MathKind.Open },
        { "open angle bracket", "⟨", MathKind.Open },
        { "left floor", "⌊", MathKind.Open },
        { "close ceiling bracket", "⌉", MathKind.Close },
    };

    [Theory]
    [MemberData(nameof(Lookups))]
    public void SpokenForm_MapsToTheExpectedSymbol(string spoken, string text, MathKind kind)
    {
        Assert.True(MathSymbols.Phrases.TryGetValue(spoken, out var symbol), $"missing: {spoken}");
        Assert.Equal(text, symbol!.Text);
        Assert.Equal(kind, symbol.Kind);
    }

    // ===== the exclusion audit =====

    // Everyday English words that were considered and deliberately NOT added. Each of them
    // could sit between (or in front of) things that look like operands in ordinary speech,
    // which is the one way this feature can bleed. They stay reachable through the user's own
    // custom words / correction rules and through "start equation … end equation".
    [Theory]
    [InlineData("and")]            // "God is the alpha and the omega" — only "logical and"
    [InlineData("or")]             // "give me a minute or two" — only "logical or"
    [InlineData("not")]            // only "logical not"
    [InlineData("is")]             // the connective tissue of every sentence
    [InlineData("are")]
    [InlineData("by")]             // only "multiplied by"
    [InlineData("in")]             // only "is in the set"
    [InlineData("on")]
    [InlineData("at")]             // only "at least" / "at most"
    [InlineData("than")]
    [InlineData("cross")]          // "the cross of Christ" — only "cross product"
    [InlineData("sin")]            // "my sin" — the trig function is "sine"
    [InlineData("cos")]            // "cos" is also slang for "because"
    [InlineData("tan")]            // "he got a tan"
    [InlineData("sec")]            // "wait a sec"
    [InlineData("cot")]            // a cot is a bed
    [InlineData("sign")]           // "a sign from God" — only "signum"
    [InlineData("cup")]            // "a cup of coffee" — ∪ is said "union"
    [InlineData("cap")]            // ∩ is said "intersect"
    [InlineData("power")]          // "the power of positive thinking"
    [InlineData("square")]         // the engine parses "square root of"
    [InlineData("change in")]      // "a change in 5 minutes" would become "Δ5 minutes"
    [InlineData("change of")]
    [InlineData("for some")]       // "for some 20 years he served" would become "∃20 years"
    [InlineData("for any")]        // "grateful for any 5 minutes"
    [InlineData("for each")]       // "for each one of us" would become "∀1 of us"
    [InlineData("union over")]     // "the union over 200 workers voted"
    [InlineData("since")]          // "since 1990" — "because" already covers ∵
    [InlineData("about")]          // "about 30 people"
    [InlineData("approximately")]  // "approximately 100 people came" — the long forms are in
    [InlineData("less")]           // only "less than"
    [InlineData("add")]
    [InlineData("subtract")]
    [InlineData("contains")]       // only "contains the set"
    [InlineData("arc")]            // "the arc of the story" — only "circular arc"
    [InlineData("image of")]       // "the image of God" — the linear-algebra sense is rarer
    [InlineData("x or")]           // would swallow the "x" that ⊕ needs on its left
    [InlineData("α")]              // greek GLYPHS collide with their capitals in a
    [InlineData("σ")]              // case-insensitive dictionary — greek is reached by name
    public void Vocabulary_ExcludesEverydayEnglishWords(string risky)
        => Assert.False(MathSymbols.Phrases.ContainsKey(risky),
            $"vocabulary must not contain the everyday word '{risky}'");

    // The other half of the rule: an ACTIVATING kind is the only thing that can switch a run
    // into mathematics, so no single ordinary English word may ever be one.
    [Fact]
    public void NoSingleEverydayWord_IsAnActivatingKind()
    {
        string[] everyday =
        {
            "prime", "degrees", "percent", "complement", "inverse", "transpose", "angle",
            "triangle", "log", "tangent", "mean of", "the mean of", "max of", "trace of",
            "the probability of", "for all", "there exists", "micro", "integers", "reals",
        };
        foreach (var word in everyday)
        {
            Assert.True(MathSymbols.Phrases.TryGetValue(word, out var symbol), $"missing: {word}");
            Assert.False(symbol!.Activates, $"'{word}' must stay weak — it is ordinary English");
        }
    }

    // ===== end-to-end: ordinary talking comes back byte-identical =====

    public static TheoryData<string> LeavesSpeechAlone() => new()
    {
        // the riskiest additions, in the kind of sentence David actually dictates
        "the cross of Christ is our only hope",
        "for all three of us it was a long day",
        "for every one of you there is a plan",
        "there exists a way out of every trial",
        "there is no such thing as a free lunch",
        "he was given 3 days to think it over",
        "on any given Sunday anything can happen",
        "for some 20 years he served the church",
        "my sin is always before me",
        "it is a sign of the times",
        "that was a prime example of grace",
        "the image of God is in every person",
        "the angle of that argument is off",
        "the alpha and omega of my faith",
        "his mercy is new every morning",
        "we set the table and said grace",
        "therefore we should trust him with everything",
        "because he loves us we can rest tonight",
        "we are not the same as we were",
        "she is at least as kind as he is",
        "the union over 200 workers voted to strike",
        // casual chat
        "I need a cup of coffee before we start",
        "let me choose 2 or 3 of them for the team",
        "she divides her time between work and family",
        "the river divides two cities in half",
        "we drove 60 miles per hour the whole way",
        "he got a tan while we were away",
        "he has a degree in theology",
        "I gave him 5 dollars and he gave me 3",
        "a change in 5 minutes is not enough",
        "delta airlines lost my bag again",
        "the mean thing would be to say nothing",
        // coding notes
        "the log file shows an error on line 40",
        "wait a sec while I check the trace of the bug",
        "the probability of rain is high today",
        "he finished in less than 3 minutes",
        "the maximum of what we can do is limited",
    };

    [Theory]
    [MemberData(nameof(LeavesSpeechAlone))]
    public void LeavesOrdinarySpeechByteIdentical(string prose)
        => Assert.Same(prose, MathSpeech.Convert(prose));

    // ===== end-to-end: the vocabulary really does render =====

    public static TheoryData<string, string> Converts() => new()
    {
        // relations
        { "x is congruent to y modulo n", "x ≡ y mod n" },
        { "n is a divisor of m", "n ∣ m" },
        { "A is a subset of B", "A ⊆ B" },
        { "x is not an element of the empty set", "x ∉ ∅" },
        { "u is perpendicular to v", "u ⊥ v" },
        { "alpha is proportional to beta", "α ∝ β" },
        { "x is distributed as the normal distribution", "x ∼ 𝒩" },
        { "lambda subscript 1 is much greater than lambda subscript 2", "λ₁ ≫ λ₂" },
        { "x squared plus y squared is less than or equal to 1", "x² + y² ≤ 1" },
        { "6 factorial is greater than 700", "6! > 700" },

        // operators & greek
        { "capital gamma equals capital lambda", "Γ = Λ" },
        { "v dot w equals 0", "v · w = 0" },
        { "h bar times omega", "ℏ × ω" },
        { "3 choose 2 equals 3", "3 C 2 = 3" },
        { "p hat plus or minus 2", "p̂ ± 2" },
        { "30 degrees celsius plus 5", "30°C + 5" },

        // postfixes
        { "v transpose times w", "vᵀ × w" },
        { "A inverse times A equals 1", "A⁻¹ × A = 1" },

        // functions
        { "the determinant of A equals 0", "det(A) = 0" },
        { "sigma squared equals the variance of x", "σ² = Var(x)" },
        { "the natural log of x is less than x", "the ln(x) < x" },
        { "the floor of x plus 1", "floor(x) + 1" },
        { "the probability of x equals 0.5", "P(x) = 0.5" },
        { "x bar equals mu", "x̄ = μ" },

        // brackets: "that <clause>" opens one, "of <thing>" takes a single operand
        { "the probability that x is greater than 5", "P(x > 5)" },
        { "the conditional probability of a given b", "P(a ∣ b)" },

        // prefixes & big operators
        { "for all x greater than 0", "∀ x > 0" },
        { "there exists exactly one x such that x squared equals 4", "∃! x ∣ x² = 4" },
        { "the gradient of f dot g", "the ∇f · g" },
        { "the double integral from 0 to 1 of x", "the ∬₀¹ x" },
        // NOTE: a VARIABLE upper bound followed by "of" is read as function application by the
        // engine ("… to n of a" → "n(a)"), so bounds are dictated as numbers or ∞.
        { "the big union from i equals 1 to 10 of a subscript i", "the ⋃ᵢ₌₁¹⁰ aᵢ" },
        { "the speed of light squared", "c²" },

        // the escape hatch reaches anything, even a bare weak operand
        { "start equation capital psi end equation", "Ψ" },
    };

    [Theory]
    [MemberData(nameof(Converts))]
    public void ConvertsSpokenMathematics(string spoken, string expected)
        => Assert.Equal(expected, MathSpeech.Convert(spoken));
}
