#if canImport(Testing)
import Testing
@testable import JVoice

/// The spoken-mathematics VOCABULARY contract — the Swift side of the Windows port's
/// `MathSymbolsTests.cs`.
///
/// `MathSpeechTests` owns the GRAMMAR; this file owns the DICTIONARY: that the lookup
/// behaves (longest match, case-insensitive), that entries are the kind they claim to be,
/// and — the half that matters most — that growing the vocabulary never lets it bleed into
/// ordinary talking. The exclusion audit below is the record of every everyday word that
/// was considered and deliberately left out.

// MARK: - dictionary hygiene

@Test func phrasesCoverTheWholeSpokenMathematicsVocabulary() {
    #expect(MathSymbols.phrases.count >= 600,
            "expected a comprehensive dictionary, found \(MathSymbols.phrases.count) spoken forms")
}

@Test func keysAreLowercasedSingleSpacedAndValuesNonEmpty() {
    for (key, symbol) in MathSymbols.phrases {
        #expect(key.trimmingCharacters(in: .whitespaces) == key, "\(key)")
        #expect(key.lowercased() == key, "\(key)")
        #expect(!key.isEmpty)
        #expect(!key.contains("  "), "\(key)")
        #expect(!symbol.text.isEmpty, "\(key)")
    }
}

/// MathSpeech peels leading/trailing punctuation off a word before matching, so a key that
/// starts or ends with any of it could never be hit — it would be dead weight.
@Test func keysNeverStartOrEndWithPunctuationTheTokenizerPeelsOff() {
    let lead = Set("([{\"'\u{201C}\u{2018}\u{00BF}\u{00A1}")
    let trail = Set(",.;:!?)]}\"'\u{201D}\u{2019}\u{2026}")
    for key in MathSymbols.phrases.keys {
        for word in key.split(separator: " ") {
            #expect(!lead.contains(word.first!), "\(key)")
            #expect(!trail.contains(word.last!), "\(key)")
        }
    }
}

@Test func maxPhraseWordsMatchesTheLongestKey() {
    // "is a subset of or equal to" — the scan window `match` counts down from.
    #expect(MathSymbols.maxPhraseWords == 7)
    #expect(MathSymbols.maxPhraseWords
            == MathSymbols.phrases.keys.map { $0.split(separator: " ").count }.max())
}

/// Every big operator must actually be reachable as a prefix, or its space-separated
/// layout rule ("∑ᵢ₌₁ⁿ i²") would be unreachable dead configuration.
@Test func everyBigOperatorIsReachableAsAPrefix() {
    // ∑ / ∏ / lim are spoken as ordinary English nouns, so MathSpeech mints them itself
    // (only with bounds) rather than trusting the vocabulary — see reservedPhrases.
    let engineOwned: Set<String> = ["∑", "∏", "lim"]
    for op in MathSymbols.bigOperators where !engineOwned.contains(op) {
        #expect(MathSymbols.phrases.values.contains { $0.text == op && $0.kind == .prefix }, "\(op)")
    }
}

@Test func bigOperatorPrefixesLayOutTheirBodyAfterASpace() {
    #expect(MathSymbols.phrases["double integral"]?.isBigOperator == true)
    #expect(MathSymbols.phrases["radical"]?.isBigOperator == false)   // "√x" binds tight
}

// MARK: - match

@Test func matchPrefersTheLongestPhrase() {
    let m = MathSymbols.match(["less", "than", "or", "equal", "to", "5"], 0)
    #expect(m?.symbol.text == "≤")
    #expect(m?.consumed == 5)
}

@Test func matchFallsBackToTheShorterPhrase() {
    let m = MathSymbols.match(["less", "than", "5"], 0)
    #expect(m?.symbol.text == "<")
    #expect(m?.consumed == 2)
}

@Test func matchIsCaseInsensitive() {
    let m = MathSymbols.match(["Capital", "SIGMA"], 0)
    #expect(m?.symbol.text == "Σ")
    #expect(m?.consumed == 2)
}

@Test func matchMatchesAtAnIndexInsideTheSentence() {
    let m = MathSymbols.match(["x", "is", "an", "element", "of", "the", "reals"], 1)
    #expect(m?.symbol.text == "∈")
    #expect(m?.consumed == 4)
}

@Test func matchRefusesOrdinaryWords() {
    #expect(MathSymbols.match(["tomorrow", "morning"], 0) == nil)
}

@Test func matchDoesNotRunPastTheEndOfTheSentence() {
    // "less than or equal to" is 5 words but only 2 remain — the window must shrink.
    let m = MathSymbols.match(["x", "less", "than"], 1)
    #expect(m?.symbol.text == "<")
    #expect(m?.consumed == 2)
}

// MARK: - representative lookups, category by category

private let lookups: [(String, String, MathKind)] = [
    ("is not equal to", "\u{2260}", .relation), ("at least", "\u{2265}", .relation),
    ("much greater than", "\u{226B}", .relation), ("is approximately equal to", "\u{2248}", .relation),
    ("is congruent to", "\u{2261}", .relation), ("is isomorphic to", "\u{2245}", .relation),
    ("is defined as", "\u{2254}", .relation), ("is proportional to", "\u{221D}", .relation),
    ("is distributed as", "\u{223C}", .relation), ("is a member of", "\u{2208}", .relation),
    ("is a subset of", "\u{2286}", .relation), ("is a proper superset of", "\u{2283}", .relation),
    ("is perpendicular to", "\u{22A5}", .relation), ("is parallel to", "\u{2225}", .relation),
    ("divides", "\u{2223}", .relation), ("such that", "\u{2223}", .relation),
    ("does not divide", "\u{2224}", .relation),
    ("multiplied by", "\u{00B7}", .operatorSymbol), ("cross product", "\u{00D7}", .operatorSymbol),
    ("per", "/", .operatorSymbol), ("plus or minus", "\u{00B1}", .operatorSymbol),
    ("dot product", "\u{00B7}", .operatorSymbol), ("tensor product", "\u{2297}", .operatorSymbol),
    ("direct sum", "\u{2295}", .operatorSymbol), ("xor", "\u{2295}", .operatorSymbol),
    ("set minus", "\u{2216}", .operatorSymbol), ("logical and", "\u{2227}", .operatorSymbol),
    ("modulo", "mod", .operatorSymbol), ("is mapped to", "\u{21A6}", .operatorSymbol),
    ("if and only if", "\u{21D4}", .operatorSymbol),
    ("negative", "-", .prefix), ("radical", "\u{221A}", .prefix),
    ("contour integral", "\u{222E}", .prefix), ("triple integral", "\u{222D}", .prefix),
    ("gradient of", "\u{2207}", .prefix), ("the laplacian of", "\u{2207}\u{00B2}", .prefix),
    ("the curl of", "\u{2207}\u{00D7}", .prefix), ("logical not", "\u{00AC}", .prefix),
    ("big union", "\u{22C3}", .prefix), ("direct sum over", "\u{2A01}", .prefix),
    ("factorial", "!", .postfix), ("percent", "%", .postfix),
    ("degrees celsius", "\u{00B0}C", .postfix), ("double prime", "\u{2033}", .postfix),
    ("transpose", "\u{1D40}", .postfix), ("inverse", "\u{207B}\u{00B9}", .postfix),
    ("conjugate transpose", "\u{2020}", .postfix), ("ohms", "\u{03A9}", .postfix),
    ("for all", "\u{2200}", .operand), ("there exists", "\u{2203}", .operand),
    ("there exists a unique", "\u{2203}!", .operand), ("there does not exist", "\u{2204}", .operand),
    ("infinity", "\u{221E}", .operand), ("h bar", "\u{210F}", .operand),
    ("aleph null", "\u{2135}\u{2080}", .operand), ("the empty set", "\u{2205}", .operand),
    ("the integers", "\u{2124}", .operand), ("the quaternions", "\u{210D}", .operand),
    ("the speed of light", "c", .operand), ("epsilon", "\u{03B5}", .operand),
    ("omicron", "\u{03BF}", .operand), ("upsilon", "\u{03C5}", .operand),
    ("capital psi", "\u{03A8}", .operand), ("big xi", "\u{039E}", .operand),
    ("uppercase theta", "\u{0398}", .operand), ("x bar", "x\u{0304}", .operand),
    ("p hat", "p\u{0302}", .operand), ("d theta", "d\u{03B8}", .operand),
    ("triangle", "\u{25B3}", .operand), ("qed", "\u{220E}", .operand),
    ("cosine of", "cos", .function), ("cosecant", "csc", .function),
    ("arc tangent", "arctan", .function), ("hyperbolic sine", "sinh", .function),
    ("binary logarithm", "log\u{2082}", .function), ("natural logarithm", "ln", .function),
    ("the determinant of", "det", .function), ("the trace of", "tr", .function),
    ("the greatest common divisor of", "gcd", .function), ("the supremum of", "sup", .function),
    ("the expected value of", "E", .function), ("the variance of", "Var", .function),
    ("the probability of", "P", .function), ("the power set of", "\u{1D4AB}", .function),
    ("the norm of", "norm", .function),
    ("the probability that", "P(", .open), ("open paren", "(", .open),
    ("close square bracket", "]", .close), ("left curly brace", "{", .open),
    ("open angle bracket", "\u{27E8}", .open), ("left floor", "\u{230A}", .open),
    ("close ceiling bracket", "\u{2309}", .close),
]

@Test func spokenFormMapsToTheExpectedSymbol() {
    for (spoken, text, kind) in lookups {
        guard let symbol = MathSymbols.phrases[spoken] else {
            Issue.record("missing vocabulary entry: \(spoken)")
            continue
        }
        #expect(symbol.text == text, "\(spoken)")
        #expect(symbol.kind == kind, "\(spoken)")
    }
}

// MARK: - the exclusion audit

/// Everyday English words that were considered and deliberately NOT added. Each of them
/// could sit between (or in front of) things that look like operands in ordinary speech,
/// which is the one way this feature can bleed. They stay reachable through the user's own
/// custom words / correction rules and through "start equation … end equation".
private let excluded = [
    "and", "or", "not", "is", "are", "by", "in", "on", "at", "than", "cross",
    "sin", "cos", "tan", "sec", "cot", "sign", "cup", "cap", "power", "square",
    "change in", "change of", "for some", "for any", "for each", "union over",
    "since", "because", "therefore", "thus", "hence", "about", "approximately",
    "less", "add", "subtract", "contains", "arc", "image of", "x or",
    "\u{03B1}", "\u{03C3}",
]

@Test func vocabularyExcludesEverydayEnglishWords() {
    for risky in excluded {
        #expect(MathSymbols.phrases[risky] == nil,
                "vocabulary must not contain the everyday word \(risky)")
    }
}

/// The other half of the rule: an ACTIVATING kind is the only thing that can switch a run
/// into mathematics, so no single ordinary English word may ever be one.
private let everyday = [
    "prime", "degrees", "percent", "complement", "inverse", "transpose", "angle",
    "triangle", "log", "tangent", "mean of", "the mean of", "max of", "trace of",
    "the probability of", "for all", "there exists", "micro", "integers", "reals",
]

@Test func noSingleEverydayWordIsAnActivatingKind() {
    for word in everyday {
        guard let symbol = MathSymbols.phrases[word] else {
            Issue.record("missing: \(word)")
            continue
        }
        #expect(!symbol.activates, "\(word) must stay weak — it is ordinary English")
    }
}

// MARK: - end-to-end

private let vocabularyLeavesSpeechAlone = [
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
]

@Test func vocabularyLeavesOrdinarySpeechByteIdentical() {
    for prose in vocabularyLeavesSpeechAlone {
        #expect(MathSpeech.convert(prose) == prose, "\(prose)")
    }
}

private let vocabularyConverts: [(String, String)] = [
    // relations
    ("x is congruent to y modulo n", "x ≡ y mod n"),
    ("n is a divisor of m", "n ∣ m"),
    ("A is a subset of B", "A ⊆ B"),
    ("x is not an element of the empty set", "x ∉ ∅"),
    ("u is perpendicular to v", "u ⊥ v"),
    ("alpha is proportional to beta", "α ∝ β"),
    ("x is distributed as the normal distribution", "x ∼ 𝒩"),
    ("lambda subscript 1 is much greater than lambda subscript 2", "λ₁ ≫ λ₂"),
    ("x squared plus y squared is less than or equal to 1", "x² + y² ≤ 1"),
    ("6 factorial is greater than 700", "6! > 700"),
    // operators & greek
    ("capital gamma equals capital lambda", "Γ = Λ"),
    ("v dot w equals 0", "v · w = 0"),
    ("h bar times omega", "ℏ · ω"),
    ("3 choose 2 equals 3", "C(3, 2) = 3"),
    ("p hat plus or minus 2", "p̂ ± 2"),
    ("30 degrees celsius plus 5", "30°C + 5"),
    // postfixes
    ("v transpose times w", "vᵀ · w"),
    ("A inverse times A equals 1", "A⁻¹ · A = 1"),
    // functions
    ("the determinant of A equals 0", "det(A) = 0"),
    ("sigma squared equals the variance of x", "σ² = Var(x)"),
    ("the natural log of x is less than x", "the ln(x) < x"),
    ("the floor of x plus 1", "floor(x) + 1"),
    ("the probability of x equals 0.5", "P(x) = 0.5"),
    ("x bar equals mu", "x̄ = μ"),
    // brackets: "that <clause>" opens one, "of <thing>" takes a single operand
    ("the probability that x is greater than 5", "P(x > 5)"),
    ("the conditional probability of a given b", "P(a ∣ b)"),
    // prefixes & big operators
    ("for all x greater than 0", "∀ x > 0"),
    ("there exists exactly one x such that x squared equals 4", "∃! x ∣ x² = 4"),
    ("the gradient of f dot g", "the ∇f · g"),
    ("the double integral from 0 to 1 of x", "the ∬₀¹ x"),
    // NOTE: a VARIABLE upper bound followed by "of" is read as function application by the
    // engine ("… to n of a" → "n(a)"), so bounds are dictated as numbers or ∞.
    ("the big union from i equals 1 to 10 of a subscript i", "the ⋃ᵢ₌₁¹⁰ aᵢ"),
    ("the speed of light squared", "c²"),
    // the escape hatch reaches anything, even a bare weak operand
    ("start equation capital psi end equation", "Ψ"),
]

@Test func vocabularyConvertsSpokenMathematics() {
    for (spoken, expected) in vocabularyConverts {
        #expect(MathSpeech.convert(spoken) == expected, "\(spoken)")
    }
}
#endif
