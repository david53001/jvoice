import Foundation

/// Spoken mathematics → real notation: "a subscript n equals 1 plus 7n" → "aₙ = 1 + 7n".
///
/// ── The one hard requirement ───────────────────────────────────────────────────────────
/// It must NOT bleed into ordinary talking. "this is a subscript of the value" and "two
/// times a day" and "I'm 100 percent sure" have to come out byte-identical. That is not a
/// confidence score or a sentence classifier — it is a structural rule:
///
///   A word only becomes a symbol inside a RUN, and a run is only converted when some
///   ACTIVATING construct in it found its OPERANDS.
///
/// A run is a stretch of consecutive words that all lexed as mathematics; any ordinary word
/// (or a comma / full stop) ends it. Activating constructs are the ones that cannot mean
/// anything else once their operands are there: an infix relation or operator with an
/// operand on BOTH sides, a prefix (√, ∫, ¬) with an operand after it, or a structural
/// construct (subscript, power, root, fraction, bounds, derivative, limit, absolute value).
/// Everything else — π, α, %, °, sin, brackets, number words — is WEAK: it renders inside a
/// run that is already mathematics and stays a plain word otherwise.
///
/// Extra rules close the gaps that the operand requirement alone leaves open:
///   • "a"/"A" are only WEAK operands, and a weak operand is refused when it is the last
///     thing before an ordinary word — which is exactly what makes "two times a day" safe
///     while "a subscript n equals 1 plus 7n" and "a plus b" still work. Nor does an
///     operator between a weak operand and a bare number activate: "I'm bringing a plus one".
///   • "I" is never a variable, and "sum"/"product" only count as ∑/∏ when bounds follow,
///     so "the sum of my fears" and "an integral part of the plan" never activate.
///   • A bare "to the" only activates when its exponent is unmistakable ("x to the 3",
///     "10 to the fifth"), never between two plain numbers ("I gave 5 to the 3 kids"), and
///     the "x" whisper writes for a spoken "times" ("3 x 4") is a weak "·".
///
/// When nothing activates, `convert` returns the input string unchanged — not re-joined —
/// so the feature is provably invisible outside mathematics.
///
/// The one exception to "weak renders only inside an activated run" is dictation-level
/// CONTEXT PROMOTION (`MathContext`, 2026-10-04): a curated Greek name ("lambda", "theta",
/// "pi", …) outside any converted run becomes its letter when the rest of the dictation is
/// mathematics ("Find the value of lambda. … X equals 5." → "… of λ. … X = 5.") and no veto
/// applies. It never activates anything; with no such name the old path runs unchanged.
///
/// ── Grouping ───────────────────────────────────────────────────────────────────────────
/// Spoken maths has no brackets, so "choose", "over", "factorial", "f of" and "the
/// probability of" reach as far as a student means them ("n choose n minus k" → C(n, n - k),
/// "10 times 9 over 2 times 1" → (10 · 9) ÷ (2 · 1)) — the rule is on `Parser`.
///
/// ── Escape hatch ───────────────────────────────────────────────────────────────────────
/// Saying "start equation … end equation" forces every run between the markers to convert
/// (and drops the markers), for the rare symbol that is too ordinary a word to auto-activate.
///
/// The vocabulary lives in `MathSymbols`, number words in `SpokenNumbers`, and Unicode
/// script rendering in `MathScript`. This file owns the grammar and the activation rules.
///
/// Ported from the Windows port's `JVoice.Core/Math/MathSpeech.cs`. It diverges on purpose
/// (2026-09-23, David-approved) in the grouping rule, where Windows gives each of those
/// constructs one token, and in the "to the" / "x" / "a plus one" leak fixes.
public enum MathSpeech {
    // ─────────────────────────────── public API ───────────────────────────────

    /// Rewrites the spoken mathematics in `text` and leaves everything else exactly as it
    /// was. Returns the input unchanged when nothing converted.
    public static func convert(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        let raw = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !raw.isEmpty else { return text }

        let (toks, forced) = splitTokens(raw)
        guard !toks.isEmpty else { return text }

        let items = lex(toks)
        // Context promotion (`MathContext`) only does any work when a promotable Greek name
        // is in the dictation at all; otherwise this is exactly the old path.
        let contextOn = items.contains { isCandidate($0, toks) }
        let emitter = Emitter(toks: toks, forced: forced, items: contextOn ? items : nil)

        var buf: [Item] = []
        for (index, it) in items.enumerated() {
            if it.kind == .word || spansPunctuation(toks, it) || isArticleBeforeGreek(items, index, toks, runOpen: !buf.isEmpty) {
                emitter.flush(&buf, brokenByWord: true)
                emitter.word(it)
                continue
            }

            if !buf.isEmpty && !toks[it.start].lead.isEmpty {
                emitter.flush(&buf, brokenByWord: false)
            }

            buf.append(it)

            // Punctuation normally ends a run, because a converted run only keeps the
            // punctuation at its two ends and an interior comma would be swallowed. The one
            // exception is the comma dictation leaves right after an opening bracket
            // ("5000 parentheses open, 1 plus 1.03 over 100"): there the pause is INSIDE
            // the equation, and dropping that comma is exactly what should happen.
            if !toks[it.start + it.count - 1].trail.isEmpty && !opens(it) {
                emitter.flush(&buf, brokenByWord: false)
            }
        }
        emitter.flush(&buf, brokenByWord: false)
        if contextOn { emitter.promote() }
        emitter.joinPoweredLetters()

        return emitter.changed ? emitter.result() : text
    }

    // ─────────────────────────────── tokens ───────────────────────────────

    /// One whitespace-separated word, with its punctuation peeled off so a run can be
    /// spliced back in without losing the comma that ended it.
    private struct Tok {
        let lead: String
        let core: String
        let trail: String
        var raw: String { lead + core + trail }
    }

    private static let leadPunct = Set("([{\"'“‘¿¡")
    private static let trailPunct = Set(",.;:!?)]}\"'”’…")

    private static let spanOpen = ["start equation", "begin equation", "open equation"]
    private static let spanClose = ["end equation", "end of equation", "close equation"]

    private static func splitTokens(_ raw: [String]) -> (toks: [Tok], forced: [Bool]) {
        let all = raw.map(peel)
        let cores = all.map(\.core)

        var drop = [Bool](repeating: false, count: all.count)
        var forced = [Bool](repeating: false, count: all.count)
        var inSpan = false
        var i = 0
        while i < all.count {
            let openLength = matchesAny(cores, i, spanOpen)
            let closeLength = matchesAny(cores, i, spanClose)
            if let length = openLength ?? closeLength {
                inSpan = openLength != nil
                for k in 0..<length { drop[i + k] = true }
                i += length
                continue
            }
            forced[i] = inSpan
            i += 1
        }

        var toks: [Tok] = []
        var keptForced: [Bool] = []
        for index in 0..<all.count where !drop[index] {
            toks.append(all[index])
            keptForced.append(forced[index])
        }
        return (toks, keptForced)
    }

    private static func peel(_ raw: String) -> Tok {
        let chars = Array(raw)
        var start = 0
        var end = chars.count
        while start < end, leadPunct.contains(chars[start]) { start += 1 }
        while end > start, trailPunct.contains(chars[end - 1]) { end -= 1 }
        return Tok(
            lead: String(chars[0..<start]),
            core: String(chars[start..<end]),
            trail: String(chars[end...])
        )
    }

    private static func matchesAny(_ cores: [String], _ i: Int, _ phrases: [String]) -> Int? {
        for phrase in phrases {
            let words = phrase.split(separator: " ").map(String.init)
            guard i + words.count <= cores.count else { continue }
            var ok = true
            for k in 0..<words.count {
                if cores[i + k].caseInsensitiveCompare(words[k]) != .orderedSame {
                    ok = false
                    break
                }
            }
            if ok { return words.count }
        }
        return nil
    }

    /// "Is there a lambda such that …": a weak "a" that would OPEN a run right after an
    /// ordinary word, with a Greek letter after it, is the article — never the product "aλ".
    private static func isArticleBeforeGreek(_ items: [Item], _ index: Int, _ toks: [Tok], runOpen: Bool) -> Bool {
        let it = items[index]
        guard !runOpen, it.kind == .variable, it.weak, it.text == "a" || it.text == "A",
              it.start > 0, toks[it.start - 1].trail.isEmpty, toks[it.start].lead.isEmpty,
              toks[it.start].trail.isEmpty, index + 1 < items.count,
              let sym = items[index + 1].sym, items[index + 1].kind == .symbol, sym.kind == .operand else { return false }
        return Parser.isGreekLetter(sym.text)
    }

    private static func opens(_ it: Item) -> Bool {
        it.kind == .symbol && it.sym?.kind == .open
    }

    /// True when a multi-word item straddles punctuation ("x, subscript n") — such an item
    /// is demoted to an ordinary word so no comma is ever swallowed by a rewrite.
    private static func spansPunctuation(_ toks: [Tok], _ it: Item) -> Bool {
        for t in it.start..<(it.start + it.count) {
            if t != it.start && !toks[t].lead.isEmpty { return true }
            if t != it.start + it.count - 1 && !toks[t].trail.isEmpty { return true }
        }
        return false
    }

    // ─────────────────────────────── lexing ───────────────────────────────

    private enum ItemKind { case number, variable, symbol, keyword, word }

    /// A structural construct the ENGINE parses (with its operands) rather than the
    /// vocabulary looking it up — see `MathSymbols.reservedPhrases`.
    private enum Kw {
        case none, sub, sup, pow2, pow3, power, root, over, from, to, of
        case abs, deriv, partialDeriv, wrt, limit, asKeyword, approaches, base, choose, the
        // 2026-09-29, docs/math-notation-format.md
        case allOver, quantity, tendsTo, derivRatio
    }

    /// How an exponent after a power keyword was said: as a plain operand ("to the 3"), as
    /// an ordinal ("to the fifth", "to the 3rd"), or as an ordinal plus "power".
    private enum Ordinal { case none, bare, withPower }

    private struct Item {
        let kind: ItemKind
        let text: String
        let start: Int
        let count: Int
        var sym: MathSymbol?
        var key: Kw = .none
        var weak = false
        var ordinal: Ordinal = .none
        /// Two variables whisper glued into one word ("Kx"): an operand that never makes a
        /// construct around it count as mathematics (lexer step 5b).
        var glued = false
        /// A Greek name whisper glued notation onto ("lambda's", "Lambda²", "lambda=3"): an
        /// ordinary WORD for the grammar, which context promotion may still write as its letter
        /// (`sym`) followed by this suffix ("λ's", "λ²", "λ=3").
        var suffix: String?
        /// Whisper's minus or opening bracket glued BEFORE such a name ("-lambda", "sin(theta"),
        /// kept in front of its letter ("-λ", "sin(θ").
        var prefix = ""

        init(_ kind: ItemKind, _ text: String, _ start: Int, _ count: Int,
             sym: MathSymbol? = nil, key: Kw = .none, weak: Bool = false, ordinal: Ordinal = .none,
             glued: Bool = false, suffix: String? = nil, prefix: String = "") {
            self.glued = glued
            self.suffix = suffix
            self.prefix = prefix
            self.kind = kind
            self.text = text
            self.start = start
            self.count = count
            self.sym = sym
            self.key = key
            self.weak = weak
            self.ordinal = ordinal
        }
    }

    // NOTE: no "the ..." variants — a structural construct never swallows a spoken word.
    // "the derivative of y with respect to x" → "the dy/dx", exactly like "the square root
    // of 16" → "the √16". (Vocabulary NAMES may include an article, e.g. "the reals" → ℝ,
    // because there the article is part of the name.)
    private static let keywords: [String: (key: Kw, payload: String)] = [
        "subscript": (.sub, ""),
        "sub": (.sub, ""),
        "superscript": (.sup, ""),
        "super": (.sup, ""),
        "sup": (.sup, ""),
        "squared": (.pow2, ""),
        "cubed": (.pow3, ""),
        "to the power of": (.power, ""),
        "to the power": (.power, ""),
        "raised to the power of": (.power, ""),
        "raised to the power": (.power, ""),
        "raised to": (.power, ""),
        // "e to the x" is as common as "e to the power of x". Safe because a power still
        // needs an operand on the left AND a real operand on the right, so "listen to the
        // alpha version" and "go to the store" can never take it — and because the lexer
        // marks this bare form weak, so "I gave 5 to the 3 kids" can't either (see
        // `Parser.powerIsUnmistakable`).
        "to the": (.power, ""),
        "base": (.base, ""),          // after a function: "log base 2 of x" → log₂(x)
        // "the" belongs to the maths phrase when it sits in OPERAND position ("x equals the
        // square root of 2" → "x = √2") and to the sentence anywhere else. Lexing it as a
        // keyword lets the parser make that distinction instead of the run ending here.
        "the": (.the, ""),
        "choose": (.choose, ""),      // "n choose k" → C(n, k)
        "square root of": (.root, "2"),
        "square root": (.root, "2"),
        "cube root of": (.root, "3"),
        // Bare "root of" is the square root, WEAK (lexer): "the root of K cubed" converts inside
        // an equation or when its radicand is a power; "the root of the problem" never.
        "root of": (.root, "2"),
        "cube root": (.root, "3"),
        "over": (.over, ""),
        // "a plus b all over 2" → (a + b)/2: the whole side so far is the numerator. WEAK —
        // it never makes a run mathematics by itself ("there were 5 all over 2 floors"), and
        // a multi-term numerator has already activated through its own operator.
        "all over": (.allOver, ""),
        // "the square root of the quantity b squared minus 4 a c" → √(b² - 4ac): the spoken
        // open bracket. Weak like every bracket, and only a group when it holds more than one
        // term ("the quantity x equals 5" stays words).
        "the quantity": (.quantity, ""),
        "from": (.from, ""),
        "to": (.to, ""),
        "of": (.of, ""),
        "absolute value of": (.abs, ""),
        "absolute value": (.abs, ""),
        "derivative of": (.deriv, ""),
        "partial derivative of": (.partialDeriv, ""),
        "with respect to": (.wrt, ""),
        "limit": (.limit, ""),
        "lim": (.limit, ""),
        "as": (.asKeyword, ""),
        "approaches": (.approaches, ""),
        // Inside a limit it is "approaches"; on its own, "x tends to infinity" → x → ∞.
        "tends to": (.tendsTo, ""),
        "goes to": (.approaches, ""),
    ]

    private static let maxKeywordWords: Int =
        keywords.keys.map { $0.split(separator: " ").count }.max() ?? 1

    /// Big operators whose spoken name is an ordinary English noun: only mathematics when
    /// bounds follow ("sum from n equals 1 to ten"), never on their own.
    private static let boundedOnly: [String: String] = [
        "sum": "∑",
        "sums": "∑",
        "product": "∏",
        "products": "∏",
    ]

    /// "7n", "3x" — whisper writes coefficients glued to the variable.
    /// (The C# original uses the regex `^\d+(\.\d+)?[a-zA-Z]$`.)
    private static func isCoefficient(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 2, chars[chars.count - 1].isAsciiLetter else { return false }

        let number = Array(chars.dropLast())
        var i = 0
        while i < number.count, number[i].isAsciiDigit { i += 1 }
        guard i > 0 else { return false }
        if i < number.count {
            guard number[i] == "." else { return false }
            i += 1
            let fractionStart = i
            while i < number.count, number[i].isAsciiDigit { i += 1 }
            guard i > fractionStart else { return false }
        }
        return i == number.count
    }

    private static func lex(_ toks: [Tok]) -> [Item] {
        let cores = toks.map(\.core)
        var items: [Item] = []

        var i = 0
        while i < cores.count {
            let core = cores[i]
            if core.isEmpty {
                items.append(Item(.word, "", i, 1))
                i += 1
                continue
            }

            // 1) "<ordinal> root of x" → ⁿ√x
            if let ordinal = SpokenNumbers.tryReadOrdinal(cores, i),
               i + ordinal.consumed < cores.count,
               cores[i + ordinal.consumed].caseInsensitiveCompare("root") == .orderedSame {
                var length = ordinal.consumed + 1
                if i + length < cores.count,
                   cores[i + length].caseInsensitiveCompare("of") == .orderedSame {
                    length += 1
                }
                items.append(Item(.keyword, ordinal.digits, i, length, key: .root))
                i += length
                continue
            }

            // 1b) "x to the fifth", "x to the third power", "x to the 3rd": an ordinal right
            //     after a power keyword is the exponent (its digits; "nth" reads as "n").
            if let last = items.last, last.kind == .keyword, last.key == .power,
               let ordinal = SpokenNumbers.tryReadOrdinal(cores, i) {
                var length = ordinal.consumed
                let saidPower = i + length < cores.count
                    && cores[i + length].caseInsensitiveCompare("power") == .orderedSame
                if saidPower { length += 1 }
                items.append(Item(.number, ordinal.digits, i, length,
                                  ordinal: saidPower ? .withPower : .bare))
                i += length
                continue
            }

            // 1c) "d y by d x" / "dy by dx" → dy/dx, one activating operand. Without "by" only
            //     when both were SPOKEN letter by letter ("d y d x") and nothing stands before
            //     them that they could belong to: after an integrand or an integral sign "dy dx"
            //     is a double integral's two differentials.
            if let top = differential(cores, i) {
                var j = i + top.consumed
                let saidBy = j < cores.count && cores[j].caseInsensitiveCompare("by") == .orderedSame
                if saidBy { j += 1 }
                if let bottom = differential(cores, j),
                   saidBy || (top.consumed == 2 && bottom.consumed == 2 && !endsOperand(items.last)
                              && !(items.last?.sym?.kind == .prefix)) {
                    items.append(Item(.keyword, top.text + "/" + bottom.text, i, j + bottom.consumed - i,
                                      key: .derivRatio))
                    i = j + bottom.consumed
                    continue
                }
            }

            // 2) "sum"/"product" — only a big operator when bounds follow
            if let bigOp = boundedOnly[core.lowercased()], i + 1 < cores.count,
               cores[i + 1].caseInsensitiveCompare("from") == .orderedSame {
                items.append(Item(.symbol, bigOp, i, 1, sym: MathSymbol(bigOp, .prefix)))
                i += 1
                continue
            }

            // 2b) "sigma" is the SUM SIGN (David, 2026-09-29), never the letter σ — that is
            //     "lowercase sigma" / "small sigma" in the vocabulary. With bounds it is exactly
            //     "sum from … to …"; without them it is a WEAK ∑ that renders only inside a run
            //     something else made mathematics ("… Kx squared sigma of 3" → "… Kx² ∑ 3"),
            //     so "Six Sigma", "sigma male", "that's so sigma" stay words.
            if core.caseInsensitiveCompare("sigma") == .orderedSame {
                let bounded = i + 1 < cores.count && cores[i + 1].caseInsensitiveCompare("from") == .orderedSame
                items.append(Item(.symbol, "∑", i, 1, sym: MathSymbol("∑", .prefix), weak: !bounded))
                i += 1
                continue
            }

            // 3) numbers ("twenty five" → 25, "7", "7n")
            if isCoefficient(core) {
                items.append(Item(.number, core, i, 1))
                i += 1
                continue
            }
            // "one half" / "three quarters" is ONE operand ("1/2", "3/4"). Weak like any
            // number, so "three quarters of the class" never activates and stays words.
            if let fraction = SpokenNumbers.tryReadFraction(cores, i) {
                items.append(Item(.number, fraction.digits, i, fraction.consumed))
                i += fraction.consumed
                continue
            }
            // Round 3b (verify): "the one", "which one", "this one" is a pronoun, not the number 1
            // ("Is x the same as the one in part a?" had become "Is x = 1 in part a?").
            if let number = SpokenNumbers.tryRead(cores, i),
               !(number.consumed == 1 && cores[i].lowercased() == "one" && i > 0
                 && ["the", "this", "that", "which", "each", "every", "any", "no"].contains(cores[i - 1].lowercased())) {
                items.append(Item(.number, number.digits, i, number.consumed))
                i += number.consumed
                continue
            }

            // 4) structural keywords vs the vocabulary — the LONGER phrase wins, so the
            //    vocabulary name "the reals" (ℝ) beats the bare keyword "the"; a tie goes
            //    to the engine, which owns the reserved forms.
            let keyword = tryKeyword(cores, i)
            let symbol = MathSymbols.match(cores, i)
            if let keyword, !(symbol != nil && symbol!.consumed > keyword.consumed) {
                // The bare "to the" is weak; "to the power (of)" is not.
                let bareToThe = keyword.key == .power && keyword.consumed == 2
                    && core.caseInsensitiveCompare("to") == .orderedSame
                // "x to the quantity n plus 1": the "the" belongs to "the quantity", and a
                // grouped exponent is unmistakable.
                if bareToThe, i + 2 < cores.count,
                   cores[i + 2].caseInsensitiveCompare("quantity") == .orderedSame {
                    items.append(Item(.keyword, keyword.payload, i, 1, key: .power))
                    i += 1
                    continue
                }
                // A bare "root of" ("the root of K cubed") is weak too: "the root of 3 problems"
                // is English. "square root of" is not.
                let bareRoot = keyword.key == .root && core.caseInsensitiveCompare("root") == .orderedSame
                items.append(Item(.keyword, keyword.payload, i, keyword.consumed, key: keyword.key,
                                  weak: bareToThe || bareRoot))
                i += keyword.consumed
                continue
            }
            if let symbol {
                // 4a) "delta x" → Δx, the change in x (recall rework, 2026-10-04): "delta" right
                //     before a single letter (not a/A/i/I) is the capital, one operand. Without a
                //     letter after it "delta" stays the vocabulary's δ ("the discriminant delta").
                if symbol.symbol.text == "δ", symbol.consumed == 1, i + 1 < cores.count,
                   toks[i].trail.isEmpty, toks[i + 1].lead.isEmpty, cores[i + 1].count == 1,
                   let letter = cores[i + 1].first, letter.isAsciiLetter, !"aAiI".contains(letter) {
                    let text = "Δ" + cores[i + 1]
                    items.append(Item(.symbol, text, i, 2, sym: MathSymbol(text, .operand)))
                    i += 2
                    continue
                }
                // …and before a lower-case Greek name: "delta omega over delta t" → Δω/Δt (fix
                // round — it was δω/Δt, two deltas in one fraction).
                if symbol.symbol.text == "δ", symbol.consumed == 1, i + 1 < cores.count,
                   toks[i].trail.isEmpty, toks[i + 1].lead.isEmpty,
                   cores[i + 1].first?.isLowercase == true,
                   let greek = MathSymbols.phrases[cores[i + 1].lowercased()], greek.kind == .operand,
                   Parser.isGreekLetter(greek.text), greek.text != "δ" {
                    let text = "Δ" + greek.text
                    items.append(Item(.symbol, text, i, 2, sym: MathSymbol(text, .operand)))
                    i += 2
                    continue
                }
                items.append(Item(.symbol, symbol.symbol.text, i, symbol.consumed, sym: symbol.symbol))
                i += symbol.consumed
                continue
            }

            // 4b) "3 x 4": whisper writes a spoken "times" as the letter x. Between two numbers
            //     it is a spoken "times" (so "3 × 4") — and WEAK, so "a 2 x 4 board" and "my
            //     monitor is 1920 x 1080" stay words unless something else makes the run
            //     mathematics ("26 x 26 x 26 equals 17,576").
            if core == "x" || core == "X", let last = items.last, last.kind == .number,
               SpokenNumbers.tryRead(cores, i + 1) != nil {
                items.append(Item(.symbol, Parser.timesMarker, i, 1,
                                  sym: MathSymbol(Parser.timesMarker, .operatorSymbol), weak: true))
                i += 1
                continue
            }

            // 5) single-letter variables ("I" is the pronoun, never a variable)
            if core.count == 1, core.first!.isAsciiLetter, core != "I" {
                // "a"/"A" and lower-case "i" are WEAK: they are ordinary words at least as
                // often as they are variables ("two times a day", "…because i feel like…").
                // Weak only matters at the very end of a run that an ordinary word cut
                // short, so "a plus b", "x subscript i plus 1" and "sum from i equals 1 to
                // n" are all unaffected.
                items.append(Item(.variable, core, i, 1, weak: core == "a" || core == "A" || core == "i"))
                i += 1
                continue
            }

            // 5b) "times Kx squared": whisper glued two variables into one word. Only a
            //     two-letter, mixed- or lower-case token that is no English word, and only
            //     where it can only be an operand — right after an infix operator or right
            //     before a script ("squared", "sub", …). It is WEAK and GLUED: nothing around
            //     it activates because of it, so it renders only inside a run something else
            //     already made mathematics ("K squared plus … times Kx squared" → Kx²).
            if isGluedVariables(core),
               isInfix(items.last) || startsScript(cores, i + 1) {
                items.append(Item(.variable, core, i, 1, weak: true, glued: true))
                i += 1
                continue
            }

            // 5c) "C equals 2 pie r": whisper's spelling of a spoken "pi" — only between a
            //     number (digits or one number word) and a single letter other than a/A/I, with
            //     no punctuation in between. The same WEAK π as "pi", so "2 pie r" alone stays
            //     words; never promoted by context ("pie chart", "a pie" never reach here).
            //     Widened 2026-10-04 (verify): after any number ("4 thirds pie r") or an infix
            //     relation/operator ("A equals pie r squared"), before "over" ("theta equals pie
            //     over 2", "2 pie over omega") and, after a number, "root" ("2 pie root l over g").
            //     Fix round: also before whisper's powered letter or operator ("A = pie r²", "x =
            //     pie ÷ 2") and, after a relation or operator, at the end of the sentence ("θ =
            //     pie.").
            if core.caseInsensitiveCompare("pie") == .orderedSame, i > 0, toks[i - 1].trail.isEmpty,
               toks[i].lead.isEmpty, let last = items.last,
               ((last.kind == .number || isOperatorLike(last))
                && ((toks[i].trail.isEmpty && i + 1 < cores.count && toks[i + 1].lead.isEmpty
                     && ((cores[i + 1].count == 1 && cores[i + 1].first!.isAsciiLetter && !"aAI".contains(cores[i + 1]))
                         || (cores[i + 1].caseInsensitiveCompare("over") == .orderedSame)
                         || (last.kind == .number && cores[i + 1].caseInsensitiveCompare("root") == .orderedSame)
                         || MathContext.isPoweredLetter(cores[i + 1])
                         || ["÷", "/", "×", "·", "+", "-", "−"].contains(cores[i + 1])))
                    || (isOperatorLike(last) && toks[i].trail.contains { ".?!".contains($0) })))
                // "The area is pie r squared": the area formula, whatever stands before it.
                || (toks[i].trail.isEmpty && i + 2 < cores.count && toks[i + 1].lead.isEmpty && toks[i + 1].trail.isEmpty
                    && cores[i + 1].count == 1 && cores[i + 1].first!.isAsciiLetter && !"aAI".contains(cores[i + 1])
                    && ["squared", "cubed"].contains(cores[i + 2].lowercased())) {
                items.append(Item(.symbol, "π", i, 1, sym: MathSymbol("π", .operand)))
                i += 1
                continue
            }

            // 6) "lambda's", "Lambda²", "lambda=3", "-lambda", "sin(theta": a Greek name with
            //    whisper's notation glued on stays a WORD (so no run changes), marked for context
            //    promotion.
            if let glued = MathContext.gluedName(core),
               let sym = MathSymbols.phrases[glued.name] {
                items.append(Item(.word, core, i, 1, sym: sym, suffix: glued.suffix, prefix: glued.prefix))
                i += 1
                continue
            }

            items.append(Item(.word, core, i, 1))
            i += 1
        }
        return items
    }

    /// Two-letter words that are English (or units, or interjections) and never glued
    /// variables — compared case-insensitively. All-caps pairs (TV, PC, UK, AI) are refused
    /// separately as acronyms.
    private static let twoLetterWords: Set<String> = [
        "ab", "ad", "ah", "al", "am", "an", "as", "at", "aw", "ax", "ay", "be", "bi", "by", "cm",
        "co", "da", "do", "dr", "ed", "eh", "em", "en", "er", "ex", "fa", "ft", "go", "ha", "he",
        "hi", "hm", "ho", "hz", "id", "if", "im", "in", "is", "it", "jo", "ka", "kg", "km", "la",
        "lb", "li", "lo", "ma", "me", "mi", "ml", "mg", "mm", "mo", "mr", "ms", "mu", "my", "na",
        "nd", "ne", "no", "nu", "ob", "od", "of", "oh", "oi", "ok", "om", "on", "oo", "op", "or",
        "os", "ow", "ox", "oy", "oz", "pa", "pe", "pi", "pm", "po", "qi", "re", "rd", "sh", "si",
        "so", "st", "ta", "th", "ti", "to", "tv", "uh", "um", "un", "up", "ur", "us", "ut", "vs",
        "we", "wo", "xi", "ya", "ye", "yo", "yu", "za",
    ]

    /// "Kx", "xy", "kx" — a token whisper glued from two spoken variables. Two ASCII letters,
    /// not all capitals (acronyms), not an English/unit two-letter word.
    private static func isGluedVariables(_ core: String) -> Bool {
        let chars = Array(core)
        guard chars.count == 2, chars.allSatisfy({ $0.isAsciiLetter }),
              !chars.allSatisfy({ $0.isUppercase }) else { return false }
        return !twoLetterWords.contains(core.lowercased())
    }

    private static func isInfix(_ item: Item?) -> Bool {
        guard let item, item.kind == .symbol, let kind = item.sym?.kind else { return false }
        return kind == .relation || kind == .operatorSymbol
    }

    /// A script keyword starts at `i`: "squared", "cubed", "sub…", "super…", "to the power".
    private static func startsScript(_ cores: [String], _ i: Int) -> Bool {
        guard i < cores.count, let keyword = tryKeyword(cores, i) else { return false }
        switch keyword.key {
        case .pow2, .pow3, .sub, .sup: return true
        case .power: return keyword.consumed > 2 || cores[i].caseInsensitiveCompare("raised") == .orderedSame
        default: return false
        }
    }

    /// Letters a differential is written with — whisper's one-word "dy"/"dx"/"dt" form is only
    /// trusted for these, so "do", "de", "Dr" never read as one.
    private static let differentialLetters: Set<Character> = Array("xyztuvwrspqnk").reduce(into: []) { $0.insert($1) }

    /// One differential at `i`: whisper's "dy", or spoken "d y" / "d theta". Nil otherwise.
    private static func differential(_ cores: [String], _ i: Int) -> (text: String, consumed: Int)? {
        guard i < cores.count else { return nil }
        let word = Array(cores[i])
        if word.count == 2, word[0] == "d", differentialLetters.contains(word[1]) {
            return (cores[i], 1)
        }
        guard cores[i] == "d", i + 1 < cores.count else { return nil }
        let next = cores[i + 1]
        if next.count == 1, let letter = next.first, letter.isASCII, letter.isLetter, next != "I" {
            return ("d" + next, 2)
        }
        if let greek = MathSymbols.phrases[next.lowercased()], greek.kind == .operand,
           greek.text.count == 1, greek.text.first!.isLetter, !greek.text.first!.isASCII {
            return ("d" + greek.text, 2)
        }
        return nil
    }

    /// True when `item` is something a following operand would multiply (so "dy dx" after it
    /// is two differentials, not a derivative).
    private static func endsOperand(_ item: Item?) -> Bool {
        guard let item else { return false }
        switch item.kind {
        case .number, .variable: return true
        case .keyword: return [.pow2, .pow3, .derivRatio].contains(item.key)
        case .symbol:
            guard let kind = item.sym?.kind else { return false }
            return kind == .operand || kind == .postfix || kind == .close
        case .word: return false
        }
    }

    private static func tryKeyword(_ cores: [String], _ i: Int) -> (key: Kw, payload: String, consumed: Int)? {
        let maxWindow = min(maxKeywordWords, cores.count - i)
        guard maxWindow > 0 else { return nil }
        for n in stride(from: maxWindow, through: 1, by: -1) {
            let phrase = cores[i..<(i + n)].joined(separator: " ").lowercased()
            if let found = keywords[phrase] { return (found.key, found.payload, n) }
        }
        return nil
    }

    // ─────────────────────────────── emitting ───────────────────────────────

    /// Rebuilds the output string, run by run: a converted run is spliced in with the
    /// original punctuation around it, an unconverted one is copied out word for word.
    private final class Emitter {
        private let toks: [Tok]
        private let forced: [Bool]
        private var parts: [String] = []
        private(set) var changed = false

        /// Context promotion's bookkeeping — nil `items` means no candidate is in the
        /// dictation and none of this runs (`MathContext`).
        private let items: [Item]?
        /// A converted segment held a real letter operand: the dictation is mathematics.
        private var evidence = false
        /// The first token of every piece of evidence (converted runs here, whisper-written
        /// equations in `promote`) — which sentence and stretch hold maths.
        private var evidenceToks: [Int] = []
        /// Unconverted segments that hold candidates, in output order.
        private var pending: [Pending] = []
        /// Token ranges of runs that hold a broken equation: no name in the same stretch
        /// (punctuation to punctuation) is promoted.
        private var brokenRanges: [Range<Int>] = []
        /// Letters a converted run already wrote ("y is 2 minus lambda" → `2 - λ`): the same name
        /// elsewhere in the dictation is that letter too ("z is λ and y is 2 - λ").
        private var runLetters: Set<String> = []
        /// Converted runs: their part and last token, for `joinPoweredLetters`.
        private var runParts: [(part: Int, lastTok: Int)] = []
        /// The item each token belongs to (context promotion only).
        private lazy var itemIndex: [Int] = {
            var out = [Int](repeating: 0, count: toks.count)
            for (index, it) in (items ?? []).enumerated() {
                for t in it.start..<(it.start + it.count) { out[t] = index }
            }
            return out
        }()
        /// Sentences and stretches holding strong maths vocabulary (round 3, `MathContext.strongTerms`).
        private var termSentences: Set<Int> = []
        private var termStretches: Set<Int> = []
        /// Round 3b: tokens of candidate names, strong-term starts and evidence starts (for the
        /// rest-of-sentence checks of `quantity`, `operand` and `located`).
        private var candidateToks: Set<Int> = []
        private var termToks: Set<Int> = []
        private var evidenceSet: Set<Int> = []
        /// Tokens a converted run rewrote (one part for the whole run, not one per token).
        private lazy var convertedTok = [Bool](repeating: false, count: toks.count)

        private struct Pending {
            /// Index in `parts` of the segment's first token (`verbatim` writes one part per token).
            let part: Int
            let fromTok: Int
            let toTok: Int
            /// The segment's items. Once its names pass, each stretch of passing names, numbers,
            /// letters and functions in it is rendered by the parser ("2 pi r" → "2πr", "sine
            /// theta" → "sin θ"); anything else stays exactly as dictated.
            let segment: [Item]
            let candidates: [Item]
        }

        init(toks: [Tok], forced: [Bool], items: [Item]?) {
            self.toks = toks
            self.forced = forced
            self.items = items
        }

        func result() -> String { parts.joined(separator: " ") }

        func verbatim(_ fromTok: Int, _ toTok: Int) {
            for t in fromTok..<toTok { parts.append(toks[t].raw) }
        }

        /// An ordinary word, copied out. A Greek name with whisper's notation glued on
        /// ("lambda's", "Lambda²") is noted for context promotion like an unconverted run.
        func word(_ it: Item) {
            if items != nil, it.suffix != nil { note([it][...], part: parts.count) }
            verbatim(it.start, it.start + it.count)
        }

        func flush(_ buf: inout [Item], brokenByWord: Bool) {
            guard !buf.isEmpty else { return }

            // A weak operand ("a") that sits right before an ordinary word is not an
            // operand at all — this is what keeps "two times a day" out of mathematics.
            let weakCutoff = brokenByWord ? buf.count - 1 : -1
            let anyForced = buf.contains { item in
                (item.start..<(item.start + item.count)).contains { forced[$0] }
            }
            let run = Run(items: buf, weakCutoff: weakCutoff, cleanEnd: !brokenByWord)
            var verbatimAt = [Bool](repeating: false, count: buf.count)
            var unconverted: [(slice: Range<Int>, part: Int)] = []
            var pos = 0
            while pos < buf.count {
                let parser = Parser(run)
                let (text, activated, used) = parser.run(pos)
                if used == 0 {
                    verbatimAt[pos] = true
                    if items != nil { unconverted.append((pos..<(pos + 1), parts.count)) }
                    verbatim(buf[pos].start, buf[pos].start + buf[pos].count)
                    pos += 1
                    continue
                }

                let fromTok = buf[pos].start
                let toTok = buf[pos + used - 1].start + buf[pos + used - 1].count
                if (activated || anyForced) && !text.isEmpty {
                    if items != nil {
                        // E1: a letter operand AND a real construct — "x = 5", "x²", "c/λ"; never
                        // a countdown "T - 10", a button combo "X + Y" or "n + 1 tickets".
                        let slice = buf[pos..<(pos + used)]
                        // Whisper's own "÷" ("v ÷ r") is a written construct too.
                        if slice.contains(where: { isLetterOperand($0) })
                            && (anyForced || slice.contains { MathSpeech.isStrongConstruct($0) }
                                || slice.contains { $0.kind == .symbol && toks[$0.start].core == "÷" }) {
                            evidence = true
                            evidenceToks.append(fromTok)
                        }
                        for it in slice where MathSpeech.isCandidate(it, toks)
                            && !MathContext.nameLike(core: toks[it.start].core, sentenceInitial: sentenceInitial(it.start)) {
                            runLetters.insert(MathContext.letter(of: MathSpeech.phrase(it, toks)))
                        }
                    }
                    for t in fromTok..<toTok { convertedTok[t] = true }
                    runParts.append((parts.count, toTok - 1))
                    parts.append(toks[fromTok].lead + text + toks[toTok - 1].trail)
                    changed = true
                } else {
                    for k in pos..<(pos + used) { verbatimAt[k] = true }
                    if items != nil { unconverted.append((pos..<(pos + used), parts.count)) }
                    verbatim(fromTok, toTok)
                }

                pos += used
            }

            // A relation left as words (past the run's first item — "given that θ" opens a
            // clause) is a broken equation ("theta equals pie over 2", "sine 2 theta equals cos
            // theta"): promoting only its names would half-convert it, so context leaves every
            // name in that stretch alone. (A dangling "times" is not: "π times ∫ y² dx".) Only a
            // SPOKEN relation with something after it counts (recall rework): whisper's own "="
            // beside notation the lexer cannot read ("0 = β - 3") is no broken speech, and "what
            // is λ equal to when …" leaves nothing half-converted.
            if items != nil {
                let endTok = buf[buf.count - 1].start + buf[buf.count - 1].count
                // …or before whisper's own notation the lexer cannot read ("λ such that x² + …").
                let dangling = brokenByWord && endTok < toks.count
                    && (MathContext.clauseWords.contains(toks[endTok].core.lowercased())
                        || MathContext.isValueToken(toks[endTok].core))
                // (fix round) …and something other than a bare keyword stands before it: "beta has
                // to equal to 3" leaves "to = 3", which half-converts nothing.
                // (round 3) …and a relation PHRASE that ends the run before an ordinary word is a
                // comparison or a condition in English: "is the same as before", "such that the
                // vectors are perpendicular", "given that the block does not slide".
                let englishAfter = brokenByWord && endTok < toks.count && toks[endTok].lead.isEmpty
                    && !toks[endTok].core.isEmpty && toks[endTok].core.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" })
                    && toks[endTok].core.lowercased() != "pie" && !MathContext.promotable.contains(toks[endTok].core.lowercased())
                    && (SpokenNumbers.tryRead([toks[endTok].core], 0) == nil
                        // round 3b (verify): "the same as the one in part a" — a pronoun
                        || (toks[endTok].core.lowercased() == "one" && endTok > 0
                            && ["the", "this", "that", "which"].contains(toks[endTok - 1].core.lowercased())))
                // round 3b (verify): the run ends on a prefix WORD with nothing after it ("… the same
                // as the gradient?") — English after the comparison, like `englishAfter`.
                let wordPrefixEnds = verbatimAt[buf.count - 1] && buf[buf.count - 1].sym?.kind == .prefix
                    && toks[buf[buf.count - 1].start].core.allSatisfy { $0.isLetter }
                let broken = buf.indices.dropFirst().contains { k in
                    buf[..<k].contains { $0.kind != .keyword }
                    // round 3b (verify): "r = a + λb is the same as t" — a spoken comparison after
                    // a converted equation compares it (the parser refused to chain it); nothing
                    // is half-converted
                    && !(buf[k].sym?.text == "=" && buf[k].count >= 3 && !verbatimAt[k - 1])
                    // …and so is "such that"/"given that" before English, which the parser leaves as
                    // words ("Find the λ such that 2x + λy = 3 has no solutions.")
                    && !(buf[k].sym?.text == "∣" && buf[k].count >= 2 && brokenByWord)
                    && verbatimAt[k] && buf[k].kind == .symbol && !buf[k].weak && buf[k].sym?.kind == .relation
                        && !(dangling && k == buf.count - 1) && (toks[buf[k].start].core.first?.isLetter ?? false)
                        && !((englishAfter || wordPrefixEnds) && buf[k].count >= 2 && buf.indices.dropFirst(k + 1).allSatisfy { j in
                            buf[j].kind == .keyword || buf[j].weak || buf[j].sym?.activates == false
                                // round 3b (verify): a prefix with nothing after it is a word ("the
                                // same as gradient" — "gradient" is ∇ only before an operand)
                                || (j == buf.count - 1 && buf[j].sym?.kind == .prefix && verbatimAt[j])
                        })
                }
                if broken {
                    brokenRanges.append(buf[0].start..<(buf[buf.count - 1].start + buf[buf.count - 1].count))
                } else {
                    for (slice, part) in unconverted { note(buf[slice], part: part) }
                }
            }
            buf.removeAll()
        }

        // ─────────── context promotion (MathContext, docs/math-context-design.md) ───────────

        /// Records an unconverted segment's candidates; `part` is where `verbatim` wrote it.
        private func note(_ slice: ArraySlice<Item>, part: Int) {
            let candidates = slice.filter { MathSpeech.isCandidate($0, toks) }
            guard let first = slice.first, let last = slice.last, !candidates.isEmpty else { return }
            pending.append(Pending(part: part, fromTok: first.start, toTok: last.start + last.count,
                                   segment: Array(slice), candidates: candidates))
        }

        /// E1's letter operand: a real variable ("x", not "a"/"A"/"i"), a Greek letter not
        /// written like a name (all-caps "ETA" → η is no evidence), an accented letter ("x bar"
        /// → x̄) or a derivative ("d y by d x").
        private func isLetterOperand(_ it: Item) -> Bool {
            if it.kind == .variable { return !it.weak }
            if it.kind == .keyword { return it.key == .derivRatio }
            if MathSpeech.isChange(it) { return true }   // "delta x" → Δx
            guard it.kind == .symbol, let sym = it.sym, sym.kind == .operand else { return false }
            if Parser.isGreekLetter(sym.text) {
                return !MathContext.nameLike(core: toks[it.start].core, sentenceInitial: sentenceInitial(it.start))
            }
            let scalars = Array(sym.text.unicodeScalars)
            guard scalars.count >= 2, scalars[0].isASCII, CharacterSet.letters.contains(scalars[0]) else { return false }
            return scalars.dropFirst().allSatisfy { (0x300...0x36F).contains($0.value) }
        }

        /// "A = π r²" → "A = πr²", "(4/3)π r³" → "(4/3)πr³": a converted run that ends in a Greek
        /// letter takes whisper's powered letter right after it as one more factor (fix round).
        /// Only ever touches a dictation a run already changed; it goes last and back to front.
        func joinPoweredLetters() {
            for (part, last) in runParts.reversed() {
                let next = last + 1
                guard next < toks.count, joinedLeft(next), !convertedTok[next], part + 1 < parts.count,
                      MathContext.isPoweredLetter(toks[next].core), parts[part + 1] == toks[next].raw,
                      let end = parts[part].last, Parser.isGreekLetter(String(end)) else { continue }
                parts.replaceSubrange(part...(part + 1), with: [parts[part] + parts[part + 1]])
            }
        }

        /// Writes the passing candidates as their letters once the whole dictation is known.
        func promote() {
            guard let items, !pending.isEmpty else { return }
            var itemAt = [Int](repeating: 0, count: toks.count)
            for (index, it) in items.enumerated() {
                for t in it.start..<(it.start + it.count) { itemAt[t] = index }
            }
            let cores = toks.map(\.core)
            var blocked = MathContext.dictationVetoes(cores: cores)
            let indexed = indexedLetters(items)

            // Equations whisper already wrote as symbols are evidence like spoken ones ("x = 5",
            // "5x + 7z = 5", "y=mx+c", "lambda = -3" — a name counts as a letter term there); a
            // numbers-only one ("0 = 0") only beside maths vocabulary ("infinite solutions", "the
            // denominator"); an expression with no relation ("2 - lambda") only in a sentence with
            // a maths word.
            var nameToks: Set<Int> = []
            var termNames: Set<Int> = []
            for it in items where MathSpeech.isCandidate(it, toks) {
                nameToks.formUnion(it.start..<(it.start + it.count))
                if MathContext.gluedOwnTerm(prefix: it.prefix, suffix: it.suffix ?? "") { termNames.insert(it.start) }
            }
            candidateToks = nameToks
            let ends = toks.map { $0.trail.contains { ",.;:!?…".contains($0) } }
            let written = MathContext.writtenEquations(cores: cores, ends: ends, letters: nameToks, termNames: termNames)
            // Round 3: strong maths vocabulary ("eigenvalue", "both sides by", "standard deviation")
            // is evidence for the names of its own sentence (`MathContext.strongTerms`).
            let termStarts = MathContext.strongTermStarts(cores: cores, ends: ends)
            termSentences = Set(termStarts.map { sentenceAt[$0] })
            termStretches = Set(termStarts.map { stretchAt[$0] })
            termToks = Set(termStarts)
            // "x = pi/4", "The angle is pi/3.": whisper's fraction of π is evidence on its own —
            // never "I ate pi/4 of the pizza" (round 3b); nor are "c/lambda", "2pi/omega", "e^(-lambda".
            for it in items where it.suffix != nil
                && MathContext.isPiFraction(name: MathSpeech.phrase(it, toks), suffix: it.suffix, prefix: it.prefix)
                && wordAfter(it)?.lowercased() != "of" {
                evidence = true
                evidenceToks.append(it.start)
            }
            // Round 3b: an interval whisper wrote ("[0, 2pi]", "[0, pi]") — a name inside it is maths.
            for it in items where MathSpeech.isCandidate(it, toks) && inInterval(it) {
                evidence = true
                evidenceToks.append(it.start)
            }
            // Sentences that say "denominator", "solutions", … (`MathContext.isMathsWord`).
            let vocabularySentences = Set(cores.indices.filter { MathContext.isMathsWord(cores[$0]) }.map { sentenceAt[$0] })
            let vocabulary = !vocabularySentences.isEmpty
            // "the value of λ has to make 0 = 0": for a numbers-only equation that slot is maths
            // vocabulary too (never for the "value of" anchor itself: "Use the value of beta
            // from the survey.").
            let valueSlot = pending.contains { entry in
                entry.candidates.contains { c in
                    let b = wordsBefore(c.start, max: 2).map { $0.lowercased() }
                    return b.count == 2 && b[0] == "of" && (b[1] == "value" || b[1] == "values")
                }
            }
            if !written.letter.isEmpty { evidence = true; evidenceToks += written.letter }
            if (vocabulary || valueSlot) && !written.numeric.isEmpty { evidence = true; evidenceToks += written.numeric }
            let expressions = written.expression.filter { vocabularySentences.contains(sentenceAt[$0]) }
            if !expressions.isEmpty { evidence = true; evidenceToks += expressions }
            let writtenLetters = MathContext.writtenLetters(cores: written.letterTerms.map { cores[$0] })
            // A letter whisper wrote, or (not for the everyday letters) one a converted run wrote:
            // that name is maths in this dictation, whatever stands before it.
            var liftLetters = writtenLetters.union(runLetters)   // round 3b (verify): everyday letters too — the output writes them, so a second pass would lift them (idempotence)
            // Round 3, one meaning per dictation: a letter whisper or a converted run wrote (the
            // everyday letters included) is a letter in its other MATHS positions too — "Solve for
            // λ: 3λ - 6 = 0." (a colon no longer makes it a mention), "the β here is the
            // coefficient, y = 3 + βx".
            var convertedLetters = writtenLetters.union(runLetters)
            let evidenceSentences = Set(evidenceToks.map { sentenceAt[$0] })
            let evidenceStretches = Set(evidenceToks.map { stretchAt[$0] })
            let evidenceStarts = Set(evidenceToks)
            evidenceSet = evidenceStarts
            // Sentences with an equation that a condition word introduces ("… when x = 5").
            let conditionedSentences = Set(evidenceToks.filter { e in
                e > 0 && joinedLeft(e) && MathContext.conditionWords.contains(toks[e - 1].core.lowercased())
            }.map { sentenceAt[$0] })

            // Evidence in this sentence or the one before or after ("I have x = 5. Where's the λ?").
            func near(_ t: Int) -> Bool {
                let n = sentenceAt[t]
                return evidenceSentences.contains(n) || evidenceSentences.contains(n - 1) || evidenceSentences.contains(n + 1)
            }
            // V2 lift for a determiner ("the λ", "our θ", "my α"): the name's OWN neighbourhood
            // is maths (`MathContext.Determiner`). Nil when no determiner stands before it.
            func determinerLifted(_ it: Item) -> Bool? {
                // "sin(θ" has its bracket before it; a capital "A" mid-sentence is a variable ("A sin(ωt)").
                guard joinedLeft(it.start), it.prefix.isEmpty,
                      !(toks[it.start - 1].core == "A" && !sentenceInitial(it.start - 1)) else { return nil }
                let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
                let before = toks[it.start - 1].core.lowercased()
                guard let kind = MathContext.determiner(before, letter: letter) else { return nil }
                // "we know that λ is 3", "given that θ is acute": a conjunction, no determiner.
                if before == "that", joinedLeft(it.start - 1),
                   !MathContext.prepositions.contains(toks[it.start - 2].core.lowercased()) { return nil }
                // "the λ is down when x = 2", "the ω for x = 2 is fine": a thing's status; "the λ is
                // in the cloud": a thing's place (round 3). Round 3b: also when the dictation writes
                // the letter ("x = 2λ, and the λ is on my wrist", "the ω I bought is nice").
                if describesThing(it) { return false }
                if liftLetters.contains(letter) { return true }
                // Round 3: "the θ is 30 degrees", "the Δx is 0.1" (a quantity this letter stands
                // for); "the γ factor is 1.5" (a maths compound with a value, `quantity`) — round 3b:
                // never the compound alone ("the gamma factor is huge in this game").
                if kind == .article, quantity(it) { return true }
                if kind == .article, rangeStatement(it) { return true }   // "the θ goes from 0 to 2π" (round 3b)
                if kind == .article, let after = wordAfter(it)?.lowercased(),
                   MathContext.mathsCompounds[letter]?.contains(after) ?? false, near(it.start) { return true }
                let everyday = MathContext.everydayLetters.contains(letter)
                // Round 3b, one meaning per dictation: a letter (not an everyday one) this dictation
                // writes or converts is that letter wherever its sentence holds the maths — "So the
                // ω, it's 2π/T, so ω = 2π/4.", "The ε is the error, |x - 1| < ε."
                if kind == .article, !everyday, convertedLetters.contains(letter),
                   evidenceSentences.contains(sentenceAt[it.start]) { return true }
                // "And then the λ drops out when you subtract the two equations." — strong maths
                // vocabulary in the name's own stretch (round 3b).
                if kind == .article, !everyday, termStretches.contains(stretchAt[it.start]) { return true }
                let termSentence = termSentences.contains(sentenceAt[it.start])
                if kind == .article, convertedLetters.contains(letter),
                   valueStatement(it, items, itemAt, evidenceStarts) || inMaths(it, evidenceStarts)
                    || definesMaths(it) || asked(it) { return true }
                if kind == .article, definition(it, strong: true),
                   !MathContext.everydayLetters.contains(letter) || near(it.start) || termSentence { return true }
                let sentence = evidenceSentences.contains(sentenceAt[it.start])
                let stretch = evidenceStretches.contains(stretchAt[it.start])
                let value = valueStatement(it, items, itemAt, evidenceStarts)
                if kind == .possessive { return value && stretch }                     // "Their ω is 2 and v = 6."
                if value && near(it.start) { return true }                             // "the λ is 3, and …"
                // "Our α is 0.05, so we reject H0." — a value beside strong vocabulary (round 3)
                if value && termSentence { return true }
                if inMaths(it, evidenceStarts) { return true }                         // "the λ in 3y + 3z = 5"
                if definesMaths(it) && near(it.start) { return true }                  // "the θ is the angle …"
                // "The denominator gives 0 = 0, so what's the beta?"
                if asked(it) && sentence && vocabularySentences.contains(sentenceAt[it.start]) { return true }
                // "where's the λ … x = 5" ("I have x = 5. Where's the λ?"); an everyday letter
                // only inside the stretch;
                // our/your/my only inside the sentence ("x = 2. Where's our omega?" is a watch), a/an
                // only inside the stretch ("Just use a lambda, it's one line, and x = 2").
                if asked(it) && (MathContext.everydayLetters.contains(letter) || ["a", "an"].contains(before) ? stretch
                                 : ["the", "this", "that", "these", "those"].contains(before) ? near(it.start) : sentence) {
                    return true
                }
                if MathContext.everydayLetters.contains(letter) { return false }
                if conditionedSentences.contains(sentenceAt[it.start]) { return true }  // "… when x = 5"
                return near(it.start) && vocabularySentences.contains(sentenceAt[it.start])  // "… solutions"
            }

            // An occurrence that names something blocks its letter everywhere in the dictation —
            // unless only its capital says so and a comma put that capital there ("value of
            // lambda, Lambda is the wavelength"): then it stays a word but blocks nothing.
            let candidates = pending.flatMap(\.candidates)
            let dictationBlocked = blocked
            // One pass decides every candidate; it runs a second time when names promoted in the
            // first pass add letters to `convertedLetters` ("Find λ: λ² = 9." — the glued λ² is
            // written maths, so the labelled λ before the colon is that letter too, round 3).
            func decide() -> Set<Int> {
            var blocked = dictationBlocked
            var names: [Bool] = []
            var stopped: [Bool] = []
            var lifts: [Bool?] = []
            for it in candidates {
                let lifted = determinerLifted(it)
                lifts.append(lifted)
                let stretch = evidenceStretches.contains(stretchAt[it.start])
                var named = namesSomething(it, items, itemAt, ignoringCase: false, determinerLifted: lifted ?? true,
                                           stretchMaths: stretch)
                // Round 3b, vetoes per occurrence: a term of a written equation is the letter whatever
                // stands before it ("The alpha is wrong, α = 30°.", "I said θ = 35°."); "said θ" is a
                // letter once the dictation converts it ("Then I said θ is acute, so θ = 35°.").
                if named, joinedLeft(it.start), !MathContext.isDeliberateCapital(MathSpeech.phrase(it, toks)),
                   !MathContext.nameLike(core: toks[it.start].core, sentenceInitial: sentenceInitial(it.start)),
                   written.letterWindowToks.contains(it.start)
                    || (["said", "say", "says"].contains(toks[it.start - 1].core.lowercased())
                        && convertedLetters.contains(MathContext.letter(of: MathSpeech.phrase(it, toks)))
                        && wordAfter(it).map({ MathContext.continuation.contains($0.lowercased()) }) ?? true) {
                    named = false
                }
                names.append(named)
                let commaCapital = it.start > 0 && toks[it.start - 1].trail.contains(",")
                    && !namesSomething(it, items, itemAt, ignoringCase: true, determinerLifted: lifted ?? true,
                                       stretchMaths: stretch)
                let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
                if named && !commaCapital { blocked.insert(letter) }
                // An article before any other letter stops only this occurrence ("the lambda is
                // down"); a glued power or "'s" needs maths in its own stretch ("Alpha² is a band").
                let window = written.letterWindowToks.contains(it.start)
                let glued = !(it.suffix ?? "").isEmpty && !stretch && !window && !liftLetters.contains(letter)
                    && !(valueStatement(it, items, itemAt, evidenceStarts) && near(it.start))
                // Round 3b: a value in an everyday unit ("the β is 2 weeks away", "λ is 512 MB now",
                // "the π is 5 euros") or a person ("θ and I went to lunch") is never the letter —
                // not even when the dictation writes it elsewhere.
                stopped.append(lifted == false || glued || everydayValue(it) || personal(it))
            }
            // Whole-dictation evidence promotes every passing name. An anchor promotes its own
            // letter everywhere ("Given that theta is acute, find tan theta." → both θ) and the
            // other names of its own sentence ("Solve for theta in the interval 0 to 2 pi." →
            // 2π) — never names in other sentences ("In terms of …, the alpha team" stays).
            let unvetoed = candidates.indices.filter { k in
                !names[k] && !stopped[k]
                    // round 3b: another occurrence's name never blocks a term of a written equation
                    && !vetoed(candidates[k], items, itemAt,
                               written.letterWindowToks.contains(candidates[k].start) ? dictationBlocked : blocked,
                               indexed, convertedLetters)
                    && !inBrokenStretch(candidates[k])
                    // round 3: "delta" only as a term of an equation with a letter of its own
                    && (!MathContext.windowOnlyNames.contains(MathSpeech.phrase(candidates[k], toks))
                        || written.letterWindowToks.contains(candidates[k].start)
                        // round 3b: "So the δ is the discriminant, δ = b² - 4ac."
                        || (convertedLetters.contains(MathContext.letter(of: MathSpeech.phrase(candidates[k], toks)))
                            && lifts[k] == true))
            }
            let anchors = unvetoed.filter { k in
                let it = candidates[k]
                if anchored(it, items, itemAt, vocabulary || termSentences.contains(sentenceAt[it.start])) {
                    // round 3b: "Find λ such that …" needs maths after it ("… the lines intersect",
                    // never "Find omega such that he is happy")
                    let a = wordsAfter(it, max: 2).map { $0.lowercased() }
                    if a.count == 2, ["such", "given", "so"].contains(a[0]), a[1] == "that" {
                        return conditionHasMaths(from: it.start + it.count + 2)
                    }
                    return true
                }
                // Round 3b: "Differentiate with respect to θ." — the sentence ends on the name, and
                // it says what is differentiated or integrated ("We did it with respect to lambda."
                // is English).
                if wordsBefore(it.start, max: 3).map({ $0.lowercased() }) == ["to", "respect", "with"],
                   toks[it.start + it.count - 1].trail.contains(where: { ".?!".contains($0) }) || it.start + it.count == toks.count,
                   calculusBefore(it.start) {
                    return true
                }
                // Round 3b (verify): "Let α be the angle at A." — an everyday letter too, when the
                // let-definition's noun has a maths tail.
                if everydayLetDefinition(it) { return true }
                // "The θ goes from 0 to 2π." — a range with a bound only maths writes.
                if rangeStatement(it) { return true }
                // Round 3: a quantity ("θ is 30 degrees"), a definition ("λ is an eigenvalue of A"),
                // the operand of a maths verb ("Multiply both sides by λ.").
                let everyday = MathContext.everydayLetters.contains(MathContext.letter(of: MathSpeech.phrase(it, toks)))
                return quantity(it) || operand(it) || (!everyday && solvedFor(it))
                    || (definition(it, strong: true) && (!everyday || near(it.start) || termSentences.contains(sentenceAt[it.start])))
            }
            // A letter whisper already wrote ("2x = 5 - 2λ, and the lambda stays free") is maths in this
            // dictation: it promotes its own name like an anchor does.
            let anchoredLetters = Set(anchors.map { MathContext.letter(of: MathSpeech.phrase(candidates[$0], toks)) })
                .union(writtenLetters).union(runLetters)
            let anchoredSentences = Set(anchors.map { sentenceAt[candidates[$0].start] })
            // Evidence elsewhere promotes an everyday letter (alpha, beta, gamma, pi) only with
            // maths around it: evidence in its own stretch, a determiner lifted by its
            // neighbourhood, or a maths word in the dictation — "x = 2. He's alpha." and "x = 2.
            // Fortnite went from alpha to beta in 2017." stay English.
            func evidencePromotes(_ it: Item) -> Bool {
                // Round 3: strong vocabulary in the name's sentence ("λ is an eigenvalue of A") — for
                // an everyday letter only in its own stretch.
                // A name alone between commas is a list item ("squared, cosine, theta, integral"), no letter.
                // Round 3b: own STRETCH for every letter — at sentence scope "The quadratic was easy,
                // so θ and I went to lunch." bled.
                let alone = !joinedLeft(it.start) && wordAfter(it) == nil
                // A name in a maths position (in/of a maths noun, a value, a definition) still takes the
                // sentence's vocabulary: "… the right hand side, k + 1, and the λ was in the bracket".
                let termed = !alone && (termStretches.contains(stretchAt[it.start])
                    || (termSentences.contains(sentenceAt[it.start])
                        && (inMaths(it, evidenceStarts) || valueStatement(it, items, itemAt, evidenceStarts) || definesMaths(it))))
                guard evidence || termed else { return false }
                // "x = 2. ω is the best.", "… and μ is fine": away from the equation, a thing's status.
                if !evidenceStretches.contains(stretchAt[it.start]) && describesThing(it) { return false }
                // "Just let θ be, she's grumpy": "let … be" with no value is English.
                if joinedLeft(it.start), toks[it.start - 1].core.lowercased() == "let",
                   wordAfter(it)?.lowercased() == "be", !valueStatement(it, items, itemAt, evidenceStarts) {
                    // …but "let θ be the angle between …" defines it.
                    let be = it.start + it.count
                    let next = be + 1 < toks.count && joinedLeft(be + 1) ? toks[be + 1].core.lowercased() : nil
                    if next.map({ !MathContext.definitionWords.contains($0) }) ?? true { return false }
                }
                guard MathContext.everydayLetters.contains(MathContext.letter(of: MathSpeech.phrase(it, toks))) else { return true }
                if termed { return true }
                if vocabulary || evidenceStretches.contains(stretchAt[it.start]) || determinerLifted(it) == true
                    || written.letterWindowToks.contains(it.start) { return true }   // "(x - α)(x - β)" (round 3b)
                // "Can alpha be 4? Then z = 5 ÷ 0.", "2 pi, and x = 3": a value or a coefficient;
                // "Alpha is 0.05, so we reject the null hypothesis." (round 3).
                if valueStatement(it, items, itemAt, evidenceStarts)
                    && (near(it.start) || termSentences.contains(sentenceAt[it.start])) { return true }
                let index = itemAt[it.start]
                return index > 0 && joinedLeft(it.start) && items[index - 1].kind == .number
            }
            return Set(unvetoed.filter { k in
                evidencePromotes(candidates[k])
                    || anchoredLetters.contains(MathContext.letter(of: MathSpeech.phrase(candidates[k], toks)))
                    || anchoredSentences.contains(sentenceAt[candidates[k].start])
            }.map { candidates[$0].start })
            }
            var passing = decide()
            let promotedLetters = Set(candidates.filter { passing.contains($0.start) }.map {
                MathContext.letter(of: MathSpeech.phrase($0, toks))
            })
            if !promotedLetters.isSubset(of: convertedLetters) {
                convertedLetters.formUnion(promotedLetters)
                // Round 3b: a letter promoted in the first pass is WRITTEN in the output, so the
                // second pass treats it like one whisper wrote — the result stays the same when it
                // is converted again (idempotence: "The alpha is wrong, α = 30°." → "The α is wrong, …").
                liftLetters.formUnion(promotedLetters)
                passing = decide()
            }
            guard !passing.isEmpty else { return }

            // In reverse, so every earlier entry's part index stays valid.
            for entry in pending.reversed() where entry.candidates.contains(where: { passing.contains($0.start) }) {
                for (from, to, text) in rendering(entry.segment, passing, indexed).reversed() {
                    let at = entry.part + from - entry.fromTok
                    let last = to - 1
                    if last > from, convertedTok[last] {
                        // "sin(omega" + the run "t + φ)," → "sin(ωt + φ),": the absorbed letter opens
                        // the next part, a converted run.
                        let run = at + last - from
                        let letter = toks[last].core
                        if run < parts.count, parts[run].hasPrefix(letter) {
                            parts.replaceSubrange(at...run, with: [toks[from].lead + text.dropLast(letter.count) + parts[run]])
                        } else {
                            parts.replaceSubrange(at..<run, with: [toks[from].lead + text.dropLast(letter.count) + toks[last - 1].trail])
                        }
                        continue
                    }
                    parts.replaceSubrange(at..<(at + to - from), with: [toks[from].lead + text + toks[to - 1].trail])
                }
                changed = true
            }
        }

        /// What replaces which tokens of a segment: each maximal stretch of passing names,
        /// numbers, real letters and functions that holds a passing name is written as one
        /// product (`juxtapose`); when it is not one, only the names' own words are replaced.
        private func rendering(_ segment: [Item], _ passing: Set<Int>, _ indexed: Set<String>) -> [(Int, Int, String)] {
            func groupable(_ it: Item) -> Bool {
                if MathSpeech.isCandidate(it, toks) { return passing.contains(it.start) }
                switch it.kind {
                case .number: return true
                case .variable: return !it.weak && !it.glued
                case .symbol: return it.sym?.kind == .function
                // "pi r²" → πr²; whisper's signed coefficient "-2 lambda" → -2λ
                case .word: return MathContext.isPoweredLetter(it.text) || MathContext.isSignedNumber(it.text)
                default: return false
                }
            }
            var out: [(Int, Int, String)] = []
            var i = 0
            while i < segment.count {
                guard groupable(segment[i]) else { i += 1; continue }
                var j = i
                while j < segment.count, groupable(segment[j]) { j += 1 }
                var group = Array(segment[i..<j])
                i = j
                // "question 2 lambda": a number after a label word is no coefficient.
                if let first = group.first, first.kind == .number, joinedLeft(first.start),
                   MathContext.labelWords.contains(toks[first.start - 1].core.lowercased()) {
                    group.removeFirst()
                }
                let named = group.filter { MathSpeech.isCandidate($0, toks) }
                guard let first = group.first, let last = group.last, !named.isEmpty else { continue }
                // "x = -2 lambda": whisper's signed coefficient just before the segment.
                var signed = ""
                if MathSpeech.isCandidate(first, toks), first.prefix.isEmpty, first.start > 0, joinedLeft(first.start),
                   !convertedTok[first.start - 1], MathContext.isSignedNumber(toks[first.start - 1].core) {
                    signed = toks[first.start - 1].core
                }
                let from = signed.isEmpty ? first.start : first.start - 1
                // "pi r²": whisper's powered letter is a word right after the segment, so it
                // joins the product as one more factor ("πr²").
                let end = last.start + last.count
                // "sin(omega t)", "e^(-lambda t)", "det(A - lambda I)": inside brackets the letter
                // after the name is its factor (λt, λI).
                let bracketed = last.prefix.contains("(") || (end < toks.count && toks[end].trail.contains(")"))
                if j == segment.count, (last.suffix ?? "").isEmpty, MathSpeech.isCandidate(last, toks),
                   end < toks.count, joinedLeft(end), bracketed, toks[end].core.count == 1,
                   let letter = toks[end].core.first, letter.isAsciiLetter, letter != "a",
                   var text = juxtapose(group, indexed) {
                    text += toks[end].core
                    out.append((from, end + 1, signed + text))
                } else if j == segment.count, last.suffix == nil, end < toks.count, joinedLeft(end),
                   MathContext.isPoweredLetter(toks[end].core), var text = juxtapose(group, indexed) {
                    text += toks[end].core
                    out.append((from, end + 1, signed + text))
                } else if j == segment.count, MathSpeech.isCandidate(last, toks), end < toks.count, joinedLeft(end),
                          (last.suffix ?? "").allSatisfy({ "²³⁴⁵⁶⁷⁸⁹".contains($0) }),
                          !(last.suffix ?? "").isEmpty || last.prefix.allSatisfy({ $0.isAsciiDigit }) && !last.prefix.isEmpty,
                          toks[end].core.count == 1, let letter = toks[end].core.first, letter.isAsciiLetter,
                          !["a", "A", "I"].contains(letter), toks[end].lead.isEmpty,
                          var text = juxtapose(group, indexed) {
                    // Round 3b (verify): whisper's "omega² r", "2pi f" — a powered or coefficient
                    // name then one letter is one product ("ω²r", "2πf"; spec §1.3).
                    text += toks[end].core
                    out.append((from, end + 1, signed + text))
                } else if let text = juxtapose(group, indexed) {
                    out.append((from, last.start + last.count, signed + text))
                } else {
                    for it in named { out.append((it.start, it.start + it.count, letterText(it))) }
                }
            }
            return out
        }

        /// A promoted stretch written as the format spec writes a product (§6 item 3: letters
        /// multiply by juxtaposition): "2 pi r" → "2πr", "rho g h" → "ρgh", "alpha beta" → "αβ",
        /// "sine theta" → "sin θ", an indexed name "lambda 1" → "λ₁". Built here rather than by
        /// the parser, whose sequence-term rule reads "mu m" as μₘ. nil when the stretch is not
        /// such a product (a number after a letter or a number, a function with nothing after).
        private func juxtapose(_ group: [Item], _ indexed: Set<String>) -> String? {
            var text = ""
            var previous: Item?
            for (k, it) in group.enumerated() {
                defer { previous = it }
                if let suffix = it.suffix {
                    // "λ²", "λ's": whisper's suffix closes the product; "-λ", "sin(ω" open it.
                    // Round 3b (verify): a power then a letter is one product — "a = ω²r" (format
                    // spec §1.3: letters multiply by juxtaposition).
                    let power = !suffix.isEmpty && suffix.allSatisfy { "²³⁴⁵⁶⁷⁸⁹ⁿ".contains($0) }
                    guard suffix.isEmpty || k == group.count - 1 || (power && group[k + 1].kind == .variable),
                          it.prefix.isEmpty || k == 0 else { return nil }
                    text += letterText(it)
                    continue
                }
                switch it.kind {
                case .symbol where it.sym?.kind == .function:
                    if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
                    text += it.sym!.text + " "
                case .number:
                    guard let previous else { text += it.text; continue }
                    guard MathSpeech.isCandidate(previous, toks), previous.suffix == nil,
                          let sub = MathScript.subscriptText(it.text) else { return nil }
                    let family = ["0", "1", "2"].contains(it.text)
                        && indexed.contains(MathContext.letter(of: MathSpeech.phrase(previous, toks)))
                    // A lone index: "What's lambda 1 if x = 5?" → λ₁ — one digit that a verb or
                    // "if" follows; "Is λ 2 then?" asks for a value and keeps its space.
                    let lone = k == group.count - 1 && it.text.count == 1 && it.count == 1
                        && wordAfter(it).map { MathContext.indexFollowers.contains($0.lowercased()) } == true
                    guard family || lone else { return nil }
                    text += sub
                case .variable:
                    text += it.text
                case .word:
                    text += it.text
                default:
                    text += it.sym!.text
                }
            }
            return text.hasSuffix(" ") ? nil : text
        }

        /// A promoted name's text: its letter, plus whisper's glued suffix ("λ's", "λ²").
        private func letterText(_ it: Item) -> String {
            // round 3b: "2pi/omega" → "2π/ω" — a name in the glued text goes with it
            MathContext.greekified(it.prefix) + it.sym!.text + MathContext.greekified(it.suffix ?? "")
        }

        private func namesSomething(_ it: Item, _ items: [Item], _ itemAt: [Int], ignoringCase: Bool,
                                    determinerLifted: Bool, stretchMaths: Bool) -> Bool {
            let index = itemAt[it.start]
            let after = wordAfter(it)
            let next = after != nil ? items[index + 1] : nil
            // The Greek items touching it ("alpha beta", "Lambda Chi Alpha").
            var lo = index
            while lo > 0, joinedLeft(items[lo].start), MathSpeech.isGreekItem(items[lo - 1]) { lo -= 1 }
            var hi = index
            while hi + 1 < items.count, wordAfter(items[hi]) != nil, MathSpeech.isGreekItem(items[hi + 1]) { hi += 1 }
            let groupOK = lo == hi || (hi - lo == 1 && (lo...hi).allSatisfy { k in
                let phrase = MathSpeech.phrase(items[k], toks)
                return MathSpeech.isCandidate(items[k], toks) && !MathContext.isDeliberateCapital(phrase)
                    && !MathContext.nameLike(core: toks[items[k].start].core, sentenceInitial: sentenceInitial(items[k].start))
            })
            // "room 1 alpha": a label word, a number, the name.
            let previous = joinedLeft(it.start) && index > 0 ? items[index - 1] : nil
            var labelBefore = false
            if let previous, previous.kind == .number, joinedLeft(previous.start) {
                // …or a product name: "Pixel 9 beta", "iOS 27 beta", "Spider-Man 2 beta" (a
                // capital inside the word, or a capitalised word that is no sentence opener
                // like "So"/"Find"/"Then" — `MathContext.capitalBefore`).
                let label = toks[previous.start - 1].core
                let productName = label.dropFirst().contains { $0.isUppercase }
                    || (label.first?.isUppercase == true
                        && !(sentenceInitial(previous.start - 1) && MathContext.capitalBefore.contains(label.lowercased())))
                labelBefore = MathContext.labelWords.contains(label.lowercased()) || productName
            }
            // "alpha 2 builds": the word after its number.
            var afterNumberWord: String?
            if let next, next.kind == .number, wordAfter(next) != nil, index + 2 < items.count,
               items[index + 2].kind == .word {
                afterNumberWord = items[index + 2].text
            }
            return MathContext.namesSomething(
                phrase: MathSpeech.phrase(it, toks),
                firstCore: String(toks[it.start].core.dropFirst(it.prefix.count)),
                sentenceInitial: ignoringCase || sentenceInitial(it.start),
                before: joinedLeft(it.start) ? toks[it.start - 1].core : nil,
                labelBefore: labelBefore,
                after: after,
                afterIsWord: next?.kind == .word && next?.suffix == nil
                    && !MathContext.isPoweredLetter(next?.text ?? ""),
                afterNumberWord: afterNumberWord,
                greekGroupOK: groupOK,
                determinerLifted: determinerLifted,
                stretchMaths: stretchMaths && !(joinedLeft(it.start)
                    && toks[it.start - 1].core.first?.isUppercase == true && !sentenceInitial(it.start - 1)))
        }

        private func vetoed(_ it: Item, _ items: [Item], _ itemAt: [Int], _ blocked: Set<String>,
                            _ indexed: Set<String>, _ converted: Set<String>) -> Bool {
            let next = wordAfter(it) != nil ? items[itemAt[it.start] + 1] : nil
            let end = it.start + it.count
            let marks = toks[it.start].lead + toks[end - 1].trail
            let phrase = MathSpeech.phrase(it, toks)
            // A colon after the name labels it ("Alpha: the first letter") — unless the dictation
            // already wrote this letter in mathematics ("Solve for λ: 3λ - 6 = 0.", round 3).
            // Round 3b: not a heading at a sentence start ("Alpha: the team meets at 5.").
            let colon = toks[end - 1].trail.hasPrefix(":")
                && (!converted.contains(MathContext.letter(of: phrase))
                    || (sentenceInitial(it.start) && !evidenceSet.contains(end)))
            // Round 3b: an interval's bracket ("[0, pi]") is no quotation.
            let quoted = marks.contains { "\"'“”‘’".contains($0) }
                || (marks.contains { "[]".contains($0) } && !inInterval(it))
            let mention = quoted || colon
                || (it.start > 0 && MathSpeech.isDash(toks[it.start - 1]))
                || (end < toks.count && MathSpeech.isDash(toks[end]))
            return MathContext.vetoed(
                phrase: phrase,
                mention: mention,
                afterIsNumber: next?.kind == .number,
                indexed: indexed.contains(MathContext.letter(of: phrase)),
                blocked: blocked)
        }

        /// Which sentence each token is in: the number of sentence ends (". ? !") before it.
        /// Precomputed once, so promotion stays linear in the dictation.
        private lazy var sentenceAt: [Int] = {
            var out = [Int](repeating: 0, count: toks.count)
            var n = 0
            for t in toks.indices {
                out[t] = n
                if toks[t].trail.contains(where: { ".?!".contains($0) }) { n += 1 }
            }
            return out
        }()

        /// Which stretch (punctuation to punctuation, see `joinedLeft`) each token is in.
        private lazy var stretchAt: [Int] = {
            var out = [Int](repeating: 0, count: toks.count)
            for t in toks.indices where t > 0 { out[t] = out[t - 1] + (joinedLeft(t) ? 0 : 1) }
            return out
        }()

        private func inBrokenStretch(_ it: Item) -> Bool {
            guard !brokenRanges.isEmpty else { return false }
            var start = it.start
            while joinedLeft(start) { start -= 1 }
            var end = it.start + it.count
            while end < toks.count, joinedLeft(end) { end += 1 }
            return brokenRanges.contains { $0.overlaps(start..<end) }
        }

        /// "the λ is 3 and …", "my α is 4, so …", "an ω of 3", "the θ is 30 degrees, so …", "the
        /// ω here is v ÷ r", "Is the λ 3?": a value given to the name — a few linking words, then
        /// a number (a sign word and a unit allowed) or a letter term, then the clause ends.
        private func valueStatement(_ it: Item, _ items: [Item], _ itemAt: [Int], _ evidenceStarts: Set<Int>) -> Bool {
            var t = it.start + it.count
            // "λ's value is 3"
            if it.suffix == "'s" || it.suffix == "’s", t < toks.count, joinedLeft(t),
               toks[t].core.lowercased() == "value" { t += 1 }
            if value(it, from: t, items, itemAt, evidenceStarts) { return true }
            // "the μ between the box and the floor is 0.3", "the ρ of water is 1000": a short
            // phrase, then "is".
            guard t < toks.count, joinedLeft(t),
                  ["of", "between", "in", "for", "on", "at", "with"].contains(toks[t].core.lowercased()) else { return false }
            var k = t + 1
            while k < toks.count, k <= t + 6, joinedLeft(k), !["is", "was", "="].contains(toks[k].core.lowercased()),
                  !MathContext.isValueToken(toks[k].core) { k += 1 }
            guard k < toks.count, k <= t + 6, joinedLeft(k), ["is", "was", "="].contains(toks[k].core.lowercased()) else { return false }
            return value(it, from: k, items, itemAt, evidenceStarts)
        }

        /// The linking words from token `t` on, then the value and the clause end.
        private func value(_ it: Item, from start: Int, _ items: [Item], _ itemAt: [Int], _ evidenceStarts: Set<Int>) -> Bool {
            var t = start
            var steps = 0
            while steps < 4, t < toks.count, joinedLeft(t) {
                let word = toks[t].core.lowercased()
                let previous = toks[t - 1].core.lowercased()
                // "came out as", "has to be" — never "the beta is out", "set the alpha to 0.5"
                if word == "out" && !["came", "comes", "come", "turned", "turns"].contains(previous) { break }
                if word == "to" && !["has", "have", "had", "need", "needs", "ought", "equal", "equals", "is", "got",
                                     "supposed"].contains(previous) { break }
                guard MathContext.valueLinks.contains(word) else { break }
                t += 1
                steps += 1
            }
            guard t < toks.count, joinedLeft(t) else { return false }
            if steps == 0 {
                // "Is the λ 3?" — only straight after "is/was the".
                let b = wordsBefore(it.start, max: 2).map { $0.lowercased() }
                guard b.count == 2, ["is", "was"].contains(b[1]) else { return false }
            }
            if evidenceStarts.contains(t) { return true }                     // "is v ÷ r"
            // "is the λ supposed to be negative?"
            if MathContext.signWords.contains(toks[t].core.lowercased())
                && (t + 1 == toks.count || !joinedLeft(t + 1) || MathContext.connectives.contains(toks[t + 1].core.lowercased())) {
                return true
            }
            if ["negative", "minus"].contains(toks[t].core.lowercased()), t + 1 < toks.count, joinedLeft(t + 1) { t += 1 }
            let item = items[itemAt[t]]
            // round 3: "our α is 5%, so …"
            let percent = toks[t].core.range(of: "^[0-9]+(\\.[0-9]+)?%$", options: .regularExpression) != nil
            guard item.kind == .number || item.kind == .variable || percent || MathContext.isValueToken(toks[t].core) else { return false }
            var end = item.kind == .number ? item.start + item.count : t + 1
            if end < toks.count, joinedLeft(end), MathContext.valueUnits.contains(toks[end].core.lowercased()) { end += 1 }
            guard end < toks.count, joinedLeft(end) else { return true }
            return MathContext.connectives.contains(toks[end].core.lowercased())
        }

        /// "the θ is the angle with …", "our α is the significance level", "the α makes the
        /// denominator 0": a maths noun within the next three words.
        private func definesMaths(_ it: Item) -> Bool {
            for word in wordsAfter(it, max: 3).map({ $0.lowercased() }) {
                if MathContext.statusWords.contains(word) { return false }
                if MathContext.definesMaths(word) { return true }
            }
            return definition(it, strong: false)
        }

        /// Round 3 — a DEFINITION: "θ is the angle between …", "λ is an eigenvalue of A", "the β
        /// here is the coefficient", "the α is now the unknown", "Is μ the mean of …?": filler, a
        /// copula (or "is" before the name), an article, at most one adjective, then a noun that
        /// defines a letter (`MathContext.definesLetter`; `strong` = only the nouns that anchor).
        private func definition(_ it: Item, strong: Bool) -> Bool {
            var t = it.start + it.count
            var steps = 0
            func word(_ k: Int) -> String? { k < toks.count && joinedLeft(k) ? toks[k].core.lowercased() : nil }
            while steps < 3, let w = word(t), MathContext.fillerWords.contains(w), !(w == "in" && word(t + 1) != "front") {
                t += 1; steps += 1
            }
            let before = wordsBefore(it.start, max: 1).first?.lowercased()
            let asked = before.map { ["is", "was", "are"].contains($0) } ?? false
            // Round 3b: "Let θ be the angle at B.", "Let μ be the mean." — the let-frame defines it.
            let letFrame = before == "let" && word(t) == "be"
            if letFrame { t += 1 } else if let w = word(t), MathContext.copulas.contains(w) {
                t += 1
                while steps < 4, let w = word(t), ["just", "basically", "really", "actually", "now", "simply", "also", "then"].contains(w) {
                    t += 1; steps += 1
                }
            } else if !asked { return false }
            guard let article = word(t), ["the", "a", "an", "our", "its", "my", "your"].contains(article) else { return false }
            t += 1
            var mathsAdjective = false
            for _ in 0..<2 {
                guard let w = word(t), !MathContext.statusWords.contains(w) else { return false }
                if MathContext.definesLetter(w, strong: strong) {
                    // "… of my bed": a possessive after the tail makes it a thing's ("Phi is the angle of my bed").
                    if let after = word(t + 2), ["my", "your", "his", "her", "their"].contains(after) { return false }
                    // Round 3b: an everyday-sounding noun (slope, angle, multiplier, parameter, …)
                    // anchors on its own only with a maths tail ("θ is the angle between the two
                    // vectors", "μ is the mean of the distribution") — "Lambda is the angle for
                    // this story", "Theta is the slope at the ski resort" stay.
                    if strong, !letFrame, !mathsAdjective, MathContext.everydayDefinitionNouns.contains(w) {
                        return mathsTail(after: t + 1)
                    }
                    return word(t + 1).map { MathContext.definitionTails.contains($0) || MathContext.connectives.contains($0) } ?? true
                }
                // "the standard deviation", "the angular speed", "the significance level"
                if let next = word(t + 1), MathContext.strongTerms.contains(w + " " + next) { return true }
                // round 3b: "the POPULATION mean", "the SAMPLE mean"
                if MathContext.statsNouns.contains(w) || MathContext.tailNouns.contains(w) { mathsAdjective = true }
                t += 1
            }
            return false
        }

        /// Round 3 — a QUANTITY: a value with a unit THIS letter stands for (`MathContext.quantityUnits`):
        /// "θ is 30 degrees", "the λ we measured is 650 nm", "ω is 3 rad/s", "the ρ of water is 1000
        /// kg/m³"; for a change "the Δx is 0.1" any number. The clause must end after it.
        private func quantity(_ it: Item) -> Bool {
            guard let items else { return false }
            let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
            let change = MathSpeech.isChange(it)
            guard change || MathContext.quantityUnits[letter] != nil else { return false }
            func word(_ k: Int) -> String? { k < toks.count && joinedLeft(k) ? toks[k].core.lowercased() : nil }
            var t = it.start + it.count
            // Round 3b: "the γ factor is 1.5" — a maths compound takes a plain number.
            var compound = false
            if let w = word(t), MathContext.mathsCompounds[letter]?.contains(w) ?? false { t += 1; compound = true }
            if let s = word(t), MathContext.clauseSubjects.contains(s), let v = word(t + 1), MathContext.clauseVerbs.contains(v) {
                t += 2
            } else if let o = word(t), ["of", "between", "for", "in"].contains(o) {
                // "the ρ of water is …": a short phrase, then "is"
                var k = t + 1
                while k <= t + 5, let w = word(k), !["is", "was", "="].contains(w) { k += 1 }
                guard word(k) != nil else { return false }
                t = k
            }
            var links = 0
            while links < 4, let w = word(t), ["is", "was", "=", "equals", "be", "of", "about", "roughly", "around",
                                               "here", "now", "just", "then", "came", "comes", "out", "as", "exactly"].contains(w) {
                t += 1; links += 1
            }
            if links == 0 {
                // "Is the θ 30 degrees?"
                let b = wordsBefore(it.start, max: 2).map { $0.lowercased() }
                guard b.contains("is") || b.contains("was") else { return false }
            }
            guard t < toks.count, joinedLeft(t) else { return false }
            let core = toks[t].core
            let item = items[itemIndex[t]]
            var end: Int
            // Round 3b: whisper's glued unit ("600nm", "5rad/s").
            if core.first?.isNumber == true, let unitStart = core.firstIndex(where: { !$0.isNumber && $0 != "." }),
               (MathContext.quantityUnits[letter] ?? []).contains(String(core[unitStart...]).lowercased()) {
                return quantityEnds(it, at: t + 1)
            }
            // "The γ factor is 1/sqrt(1 - v²/c²)." — whisper's formula
            if compound, evidenceSet.contains(t)
                || (core.contains(where: { "/^(√".contains($0) }) && core.contains(where: { $0.isNumber })) { return true }
            if item.kind == .number { end = item.start + item.count }
            else if MathContext.isValueToken(core) { end = t + 1 } else { return false }
            if compound {
                // "the γ factor is 1.5", "The γ factor is 1/sqrt(1 - v²/c²)."
                guard item.kind == .number || evidenceSet.contains(t) else { return false }
                if evidenceSet.contains(t) { return true }
                return quantityEnds(it, at: end)
            }
            if core.hasSuffix("°") {
                guard MathContext.quantityUnits[letter]?.contains("°") ?? false else { return false }
            } else if !change || (end < toks.count && joinedLeft(end) && !MathContext.connectives.contains(toks[end].core.lowercased())) {
                var matched = false
                for n in stride(from: 3, through: 1, by: -1) where end + n <= toks.count && (end..<(end + n)).allSatisfy({ joinedLeft($0) }) {
                    let unit = toks[end..<(end + n)].map { $0.core.lowercased() }.joined(separator: " ")
                    if (MathContext.quantityUnits[letter] ?? []).contains(unit)
                        || (change && MathContext.valueUnits.contains(unit)) { end += n; matched = true; break }
                }
                guard matched else { return false }
            }
            return quantityEnds(it, at: end)
        }

        /// Round 3b — where a quantity statement may stop: the SENTENCE ends (after "here", "now",
        /// "then", or "for ⟨a few words⟩": "ρ is 1.2 kg/m³ for air."), or the clause ends and the
        /// rest of the sentence is maths ("θ is 30 degrees, so sin θ = 0.5"). A temperature or a
        /// walk ("Beta is 38 degrees, he has a fever.", "Theta is 25 degrees and sunny.", "Lambda is
        /// 500 m, so we can walk.") goes on in English, so it stays.
        private func quantityEnds(_ it: Item, at end: Int) -> Bool {
            var k = end
            func sentenceEndsBefore(_ k: Int) -> Bool {
                k >= toks.count || toks[k - 1].trail.contains { ".?!".contains($0) }
            }
            if sentenceEndsBefore(k) { return true }
            while k < toks.count, joinedLeft(k), ["here", "now", "then", "too", "exactly", "roughly", "approximately"].contains(toks[k].core.lowercased()) {
                k += 1
            }
            if sentenceEndsBefore(k) { return true }
            if k < toks.count, joinedLeft(k), toks[k].core.lowercased() == "for" {
                var f = k + 1
                while f < toks.count, f <= k + 3, joinedLeft(f) { f += 1 }
                if sentenceEndsBefore(f) { return true }
            }
            guard !joinedLeft(k) || MathContext.connectives.contains(toks[k].core.lowercased()) else { return false }
            return restHasMaths(from: k)
        }

        /// Round 3b — the rest of the sentence from token `k` holds maths: evidence, a strong term,
        /// another Greek name, a maths word or a maths verb ("add 5x", "so sin θ = 0.5").
        private func restHasMaths(from k: Int) -> Bool {
            var t = k
            while t < toks.count {
                if evidenceSet.contains(t) || termToks.contains(t) || candidateToks.contains(t)
                    || MathContext.isMathsWord(toks[t].core) || MathContext.mathsVerbs.contains(toks[t].core.lowercased()) {
                    return true
                }
                if toks[t].trail.contains(where: { ".?!".contains($0) }) { break }
                t += 1
            }
            return false
        }

        /// Round 3b — a definition's tail is maths: a preposition, then (past determiners) a
        /// letter, a number, a Greek name or a maths noun ("between the two vectors", "at B", "of
        /// the distribution", "of the fluid").
        private func mathsTail(after t: Int, depth: Int = 0) -> Bool {
            guard t < toks.count, joinedLeft(t),
                  ["of", "between", "at", "in", "for", "on", "with", "from", "to"].contains(toks[t].core.lowercased()) else { return false }
            var k = t + 1
            var words = 0
            while k < toks.count, joinedLeft(k), words < 4 {
                let core = toks[k].core
                let word = core.lowercased()
                if candidateToks.contains(k) || evidenceSet.contains(k) { return true }
                if core != "a", core != "I", MathContext.isValueToken(core) { return true }
                if MathContext.tailNouns.contains(word) || MathContext.mathsNouns.contains(word)
                    || MathContext.placeNouns.contains(word) || MathContext.statsNouns.contains(word)
                    || MathContext.definesMaths(word) || termToks.contains(k) {
                    // Round 3b (verify): the noun must END its phrase — "the angle of the light in
                    // this photo", "the parameter in the function call", "the angle of the mirror
                    // in the hallway" are things; "between the two vectors", "of the incline and
                    // the horizontal", "of the vectors in the diagram" are maths.
                    if tailEnds(k + 1, depth: depth) { return true }
                }
                if !["the", "a", "an", "this", "that", "these", "those", "two", "both", "each", "its"].contains(word) { words += 1 }
                k += 1
            }
            return false
        }

        /// Round 3b (verify) — what may follow a definition's tail noun: the clause ends, a
        /// coordination or another maths preposition ("… and the horizontal", "… of the
        /// distribution of heights"), a letter label ("the line AB"), or a place that is itself
        /// maths ("… in the diagram").
        private func tailEnds(_ k: Int, depth: Int) -> Bool {
            guard k < toks.count, joinedLeft(k) else { return true }
            let core = toks[k].core
            let word = core.lowercased()
            if ["and", "or", "of", "between", "with", "to", "from", "relative"].contains(word)
                || MathContext.connectives.contains(word) { return true }
            if candidateToks.contains(k) || evidenceSet.contains(k) { return true }
            if core != "a", core != "I", MathContext.isValueToken(core) { return true }
            if depth == 0, ["in", "at", "on", "for"].contains(word) { return mathsTail(after: k, depth: 1) }
            return false
        }

        /// Round 3b — a value in an EVERYDAY unit after the name: "the β is 2 weeks away", "the π is
        /// 5 euros", "λ is 512 MB now", "the ω is 40 mm", "θ is 30 degrees warmer", "the β is 50%
        /// off". Never a unit the letter stands for (`MathContext.quantityUnits`), and τ keeps time.
        private func everydayValue(_ it: Item) -> Bool {
            guard !MathSpeech.isChange(it) else { return false }                // "the Δt is 0.5 seconds"
            let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
            var t = it.start + it.count
            var links = 0
            while links < 3, t < toks.count, joinedLeft(t),
                  ["is", "was", "costs", "cost", "about", "around", "only", "just", "like", "now", "still", "over",
                   "under", "almost", "roughly", "are", "were"].contains(toks[t].core.lowercased()) {
                t += 1; links += 1
            }
            guard links > 0, t < toks.count, joinedLeft(t) else { return false }
            let core = toks[t].core
            // "$5", "5", "2.5", "50%"
            var digits = Substring(core)
            if let f = digits.first, "$€£".contains(f) { digits = digits.dropFirst() }
            if digits.last == "%" { digits = digits.dropLast() }
            guard let d = digits.first, d.isNumber, digits.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return false }
            if core.first.map({ "$€£".contains($0) }) ?? false { return true }
            guard t + 1 < toks.count, joinedLeft(t + 1) else { return false }
            let unit = toks[t + 1].core.lowercased()
            if (MathContext.quantityUnits[letter] ?? []).contains(unit) {
                // "θ is 30 degrees warmer", "the ω is 300 m water resistant"
                return t + 2 < toks.count && joinedLeft(t + 2)
                    && MathContext.everydayComparatives.contains(toks[t + 2].core.lowercased())
            }
            if letter == "tau", MathContext.timeUnits.contains(unit) { return false }
            return MathContext.everydayUnits.contains(unit)
        }

        /// Round 3b — the condition after "Find λ such that" is maths: a maths noun, word or verb, a
        /// physics object, evidence ("the lines intersect", "the box doesn't move", "the matrix has
        /// no inverse") — never "he is happy".
        private func conditionHasMaths(from k: Int) -> Bool {
            var t = k
            while t < toks.count {
                let word = toks[t].core.lowercased()
                if evidenceSet.contains(t) || termToks.contains(t) || candidateToks.contains(t)
                    || MathContext.isMathsWord(toks[t].core) || MathContext.tailNouns.contains(word)
                    || MathContext.mathsNouns.contains(word) || MathContext.placeNouns.contains(word)
                    || MathContext.conditionTerms.contains(word) { return true }
                if toks[t].trail.contains(where: { ".?!".contains($0) }) { break }
                t += 1
            }
            return false
        }

        /// Round 3b — a SOLUTION reported: "for λ I got 3 and for μ I got -1" — "for", the name, "I/we
        /// got/found", a number or letter term, then the clause ends.
        private func solvedFor(_ it: Item) -> Bool {
            guard wordsBefore(it.start, max: 1).first?.lowercased() == "for" else { return false }
            let a = wordsAfter(it, max: 3)
            guard a.count == 3, ["i", "we"].contains(a[0].lowercased()),
                  ["got", "get", "found", "find", "have", "had"].contains(a[1].lowercased()),
                  MathContext.isValueToken(a[2]), a[2] != "a" else { return false }
            let end = it.start + it.count + 3
            // Round 3b (verify): the report ends the sentence, or another "for ⟨name⟩ I got"
            // follows — "For omega I got 5, it was fun." and "For theta we got 4, the pizzas."
            // are scores and orders.
            if end >= toks.count || toks[end - 1].trail.contains(where: { ".?!".contains($0) }) { return true }
            return end + 1 < toks.count && ["and", "but"].contains(toks[end].core.lowercased())
                && toks[end + 1].core.lowercased() == "for" && candidateToks.contains(end + 2)
        }

        /// Round 3b (verify) — the sentence before token `t` says what is differentiated or
        /// integrated: "Differentiate with respect to θ.", "the derivative with respect to λ".
        private func calculusBefore(_ t: Int) -> Bool {
            var k = t - 1
            while k >= 0, sentenceAt[k] == sentenceAt[t] {
                let w = toks[k].core.lowercased()
                if w.hasPrefix("differentiat") || w.hasPrefix("integrat") || w.hasPrefix("derivative")
                    || w == "partial" || w == "partially" { return true }
                k -= 1
            }
            return false
        }

        /// Round 3b (verify) — "Let α be the angle at A.", "Let λ be the wavelength of the light":
        /// a let-definition whose noun (`MathContext.definitionNouns`) has a maths tail. Enough
        /// for an everyday letter too — "Let alpha be the team captain" has no such noun.
        private func everydayLetDefinition(_ it: Item) -> Bool {
            guard wordsBefore(it.start, max: 1).first?.lowercased() == "let" else { return false }
            func word(_ k: Int) -> String? { k < toks.count && joinedLeft(k) ? toks[k].core.lowercased() : nil }
            var t = it.start + it.count
            guard word(t) == "be", let article = word(t + 1), ["the", "a", "an"].contains(article) else { return false }
            t += 2
            for _ in 0..<2 {
                guard let w = word(t) else { return false }
                if MathContext.definitionNouns.contains(w) { return mathsTail(after: t + 1) }
                t += 1
            }
            return false
        }

        /// Round 3b (verify) — a RANGE: "the θ goes from 0 to 2π", "θ runs from -π to π", "θ
        /// goes from 0 to 360 degrees" — a bound only maths writes (π, a sign, a degree mark) or a
        /// unit this letter stands for, and the clause ends after it. "Lambda goes from 0 to 100
        /// in 3 seconds" and "the omega goes from 9 to 5 on weekdays" stay.
        private func rangeStatement(_ it: Item) -> Bool {
            func word(_ k: Int) -> String? { k < toks.count && joinedLeft(k) ? toks[k].core.lowercased() : nil }
            var t = it.start + it.count
            if let w = word(t), ["goes", "go", "went", "runs", "run", "ran", "ranges", "range", "varies", "vary",
                                 "lies", "is", "moves", "increases", "decreases", "changes"].contains(w) { t += 1 }
            guard word(t) == "from" else { return false }
            t += 1
            var special = false
            func bound() -> Bool {
                guard let w = word(t), w.range(of: "^[-−]?([0-9]+(\\.[0-9]+)?)?(pi|π)?(/[0-9]+)?°?$", options: .regularExpression) != nil,
                      w.contains(where: { $0.isNumber }) || w.contains("pi") || w.contains("π") else { return false }
                if w.contains("pi") || w.contains("π") || w.hasPrefix("-") || w.hasPrefix("−") || w.hasSuffix("°") { special = true }
                t += 1
                // spoken "2 pi"
                if w.allSatisfy({ $0.isNumber }), let next = word(t), next == "pi" || next == "π" { special = true; t += 1 }
                return true
            }
            guard bound(), word(t) == "to" else { return false }
            t += 1
            guard bound() else { return false }
            let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
            if let unit = word(t), MathContext.quantityUnits[letter]?.contains(unit) ?? false { special = true; t += 1 }
            guard special else { return false }
            return t >= toks.count || toks[t - 1].trail.contains(where: { ".?!".contains($0) })
                || (!joinedLeft(t) && toks[t - 1].trail.contains(","))
                || MathContext.connectives.contains(toks[t].core.lowercased())
        }

        /// Round 3b — a PERSON: the name coordinated with a personal pronoun ("θ and I went to lunch",
        /// "between us and θ", "me and ω").
        private func personal(_ it: Item) -> Bool {
            // "Beta, solve 2x + 3 = 7 first, then play." — an everyday letter called by name at a
            // sentence start, then an order or a question to that person (Indian-English "beta").
            let end = it.start + it.count
            if sentenceInitial(it.start), toks[it.start].core.first?.isUppercase == true,
               MathContext.everydayLetters.contains(MathContext.letter(of: MathSpeech.phrase(it, toks))),
               toks[end - 1].trail == ",", end < toks.count,
               MathContext.vocativeFollowers.contains(toks[end].core.lowercased()) { return true }
            let pronouns: Set<String> = ["i", "me", "us", "we", "you", "he", "she", "they", "him", "her", "them"]
            let b = wordsBefore(it.start, max: 2).map { $0.lowercased() }
            if b.count == 2, ["and", "or"].contains(b[0]), pronouns.contains(b[1]) { return true }
            // after it only the pronouns that cannot open a new clause ("θ and I went", never "λ and
            // you get x = 2")
            let a = wordsAfter(it, max: 2).map { $0.lowercased() }
            return a.count == 2 && ["and", "or"].contains(a[0]) && ["i", "me", "us", "him", "them"].contains(a[1])
        }

        /// Round 3b — the name sits inside an interval whisper wrote: "[0, 2pi]", "[0, pi]", "(0, pi)":
        /// a bracket opens on a number or letter term before it and closes on it (or after it).
        private func inInterval(_ it: Item) -> Bool {
            let end = it.start + it.count - 1
            guard toks[end].trail.first.map({ "])".contains($0) }) ?? false else { return false }
            var k = it.start
            var steps = 0
            while steps < 3 {
                if !toks[k].lead.isEmpty {
                    return toks[k].lead.last.map { "[(".contains($0) } == true && k < it.start
                        && MathContext.isValueToken(toks[k].core)
                }
                guard k > 0 else { return false }
                k -= 1; steps += 1
            }
            return false
        }

        /// Round 3 — the OPERAND of a maths verb: "Multiply both sides by λ.", "Divide by λ.", "So we
        /// multiply the first equation by λ.", "Multiply both sides by 2λ." — the object between the
        /// verb and "by" is maths (`MathContext.operationObjects`), and the clause ends after it.
        private func operand(_ it: Item) -> Bool {
            var b = wordsBefore(it.start, max: 10).map { $0.lowercased() }
            if let first = b.first, SpokenNumbers.tryRead([first], 0) != nil || Double(first) != nil { b.removeFirst() }
            guard b.first == "by", let verb = b.firstIndex(where: { MathContext.operationVerbs.contains($0) }),
                  b[1..<verb].allSatisfy({ MathContext.operationObjects.contains($0) || $0.count == 1 || Double($0) != nil })
            else { return false }
            // Round 3b: the sentence ends on the name ("Divide by λ."), or goes on with maths ("Now
            // multiply by λ and add 5x.") — never "Divide it by omega, the new tier."
            let end = it.start + it.count
            if end >= toks.count || toks[end - 1].trail.contains(where: { ".?!".contains($0) }) { return true }
            let after = wordAfter(it)?.lowercased()
            guard after == nil || MathContext.connectives.contains(after!) else { return false }
            var k = end
            while k < toks.count, candidateToks.contains(k) == false, !toks[k - 1].trail.contains(where: { ".?!".contains($0) }) {
                if evidenceSet.contains(k) || termToks.contains(k) || MathContext.mathsVerbs.contains(toks[k].core.lowercased())
                    || MathContext.isMathsWord(toks[k].core) { return true }
                k += 1
            }
            return false
        }

        /// "the λ in 3y + 3z = 5", "the μ in F = ma", "the λ goes in equation 3", "the π in this
        /// formula": in/of (after at most one verb) right before the equation or a maths noun.
        private func inMaths(_ it: Item, _ evidenceStarts: Set<Int>) -> Bool {
            var t = it.start + it.count
            // round 3b: two words ("cancel out in", "goes back into")
            for _ in 0..<2 where t < toks.count && joinedLeft(t) && ["goes", "go", "is", "appears", "comes", "sits", "stays",
                "belongs", "fits", "was", "back", "cancel", "cancels", "out", "drops", "appear", "go", "come"].contains(toks[t].core.lowercased()) {
                t += 1
            }
            guard t + 1 < toks.count, joinedLeft(t), joinedLeft(t + 1),
                  ["in", "of", "into"].contains(toks[t].core.lowercased()) else { return false }
            if evidenceStarts.contains(t + 1) { return true }
            var k = t + 1
            // round 3b: ordinals too ("the λ in the second equation")
            while k < toks.count, joinedLeft(k), ["this", "the", "that", "our", "each", "every", "my", "first", "second",
                                                  "third", "last", "next", "other", "same", "both"].contains(toks[k].core.lowercased()) {
                k += 1
            }
            guard k < toks.count, joinedLeft(k) else { return false }
            let noun = toks[k].core.lowercased()
            if MathContext.mathsNouns.contains(noun) { return true }
            // round 3b: "the μ of the distribution is 50" — a statistics noun only when it gives a value
            if MathContext.statsNouns.contains(noun), let items, valueStatement(it, items, itemIndex, evidenceStarts),
               k + 1 < toks.count, joinedLeft(k + 1), ["is", "was", "="].contains(toks[k + 1].core.lowercased()) { return true }
            // round 3: "the λ is in the power", "the θ is in the second quadrant", "the θ is in the
            // interval from 0 to 90" — an everyday-sounding place only where the phrase ends.
            var n = k
            if !MathContext.placeNouns.contains(noun), ["first", "second", "third", "fourth", "same", "other"].contains(noun) { n += 1 }
            guard n < toks.count, joinedLeft(n), MathContext.placeNouns.contains(toks[n].core.lowercased()) else { return false }
            let tail = n + 1
            return tail >= toks.count || !joinedLeft(tail)
                || ["of", "for", "from", "and", "so", "then", "when", "if", "is", "was", "here", "now", "too"].contains(toks[tail].core.lowercased())
                || MathContext.isValueToken(toks[tail].core)
        }

        /// "the λ is down", "ω is the best", "the λ for x = 2 crashes": a status word within the
        /// next six words of the name's stretch says it is a thing (`MathContext.statusWords`).
        private func describesThing(_ it: Item) -> Bool {
            wordsAfter(it, max: 6).contains { MathContext.statusWords.contains($0.lowercased()) } || located(it)
        }

        /// Round 3: "the λ is in the cloud", "the ω is in my bag", "λ lives in the cloud" — a
        /// name in an everyday PLACE is a thing. "… in the denominator", "… in equation 2", "… in
        /// 3y + 3z = 5", "… in the second quadrant" are maths places (`MathContext.placeNouns`).
        private func located(_ it: Item) -> Bool {
            var t = it.start + it.count
            var verb = false
            if t < toks.count, joinedLeft(t), MathContext.locationVerbs.contains(toks[t].core.lowercased()) { t += 1; verb = true }
            if t < toks.count, joinedLeft(t), toks[t].core.lowercased() == "still" { t += 1 }
            guard t + 1 < toks.count, joinedLeft(t), joinedLeft(t + 1),
                  MathContext.locationPrepositions.contains(toks[t].core.lowercased()) else { return false }
            if !verb {
                // "the λ in my equation is 0.5", "the λ in the formula booklet for x = 5": no verb, so
                // "in …" says WHICH λ — any maths within four words keeps it a letter (round 3).
                var k = t + 1
                var words = 0
                while k < toks.count, joinedLeft(k), words < 4 {
                    let word = toks[k].core.lowercased()
                    if MathContext.isValueToken(toks[k].core) || MathContext.mathsNouns.contains(word)
                        || MathContext.placeNouns.contains(word) || MathContext.definesMaths(word)
                        || MathContext.valueUnits.contains(word) || MathContext.strongTerms.contains(word)
                        || MathContext.promotable.contains(word) || evidenceSet.contains(k) { return false }
                    if !["the", "a", "an", "my", "our", "your", "this", "that", "both", "each", "every"].contains(word) {
                        words += 1
                    }
                    k += 1
                }
                return words > 0
            }
            // Round 3b: read the place's noun phrase up to a preposition, a connective or the
            // stretch end, and judge its HEAD — "the graph database", "the power bank", "the sample
            // folder" are everyday (a maths word only modifies them); "the square root", "the left
            // hand side", "the second quadrant here" are maths. A number after a noun is a label
            // ("room 5", "gate 12", "page 4"), maths only after a maths noun ("equation 2", "the
            // range 0 to 360"); a number alone is a time ("in 2027").
            var k = t + 1
            var determined = false
            var head: String?
            var labelled = false
            var count = 0
            let stops: Set<String> = ["of", "for", "from", "at", "with", "to", "on", "in", "here", "now", "too", "again",
                                      "today", "tonight", "yesterday", "tomorrow", "anyway", "though", "we", "i", "you",
                                      "they", "he", "she", "it", "is", "was", "are", "were", "should", "can", "could",
                                      "will", "would", "must", "has", "have", "had", "does", "did", "do", "that", "which",
                                      "where", "who"]
            while k < toks.count, joinedLeft(k), count < 5 {
                let core = toks[k].core
                let word = core.lowercased()
                if evidenceSet.contains(k) || candidateToks.contains(k) { return false }      // "in 3y + 3z = 5", "in the λ term"
                if stops.contains(word) || MathContext.connectives.contains(word) { break }
                count += 1
                if ["the", "a", "an", "my", "our", "your", "this", "that", "both", "each", "every", "these", "those",
                    "his", "her", "their", "its"].contains(word) { determined = true; k += 1; continue }
                if MathContext.isValueToken(core) && word != "a" && word != "i" {
                    if core.contains(where: { $0.isLetter }) && core.count <= 3 { return false }   // a letter term "x", "3y"
                    if head == nil { return true }                                               // "in 2027"
                    labelled = true
                    k += 1
                    break
                }
                head = word
                k += 1
            }
            guard let head else { return false }
            let maths = MathContext.mathsNouns.contains(head) || MathContext.placeNouns.contains(head)
                || MathContext.definesMaths(head) || MathContext.valueUnits.contains(head) || MathContext.strongTerms.contains(head)
            if labelled { return !maths }
            guard maths else { return true }
            // "in power now", "in question", "in series": an idiom without an article
            if !determined, MathContext.placeIdioms.contains(head) { return true }
            // "the circle of friends", "the second row of the bus": an of/for/from tail must be maths
            // too ("the power of 2", "the interval from 0 to 90", "the formula for v").
            if k < toks.count, joinedLeft(k), ["of", "for", "from"].contains(toks[k].core.lowercased()) {
                return !mathsTail(after: k)
            }
            // "the system now" — a computer's system unless something maths follows
            if head == "system" || head == "question" {
                let endsHere = k >= toks.count || !joinedLeft(k)
                return !(endsHere || mathsTail(after: k))
            }
            return false
        }

        /// "Where's the λ …", "what's this θ …", "find the λ …": a question or command about the
        /// name opens its stretch.
        private func asked(_ it: Item) -> Bool {
            wordsBefore(it.start, max: 5).contains { MathContext.askWords.contains($0.lowercased()) }
        }

        /// Letters the dictation numbers as a family: two or more occurrences each followed by a
        /// different index 0, 1 or 2 ("lambda 1 and lambda 2") — so "lambda 1" is λ₁, not
        /// "omega 3".
        private func indexedLetters(_ items: [Item]) -> Set<String> {
            var seen: [String: Set<String>] = [:]
            var bad: Set<String> = []
            for (k, it) in items.enumerated() where MathSpeech.isCandidate(it, toks) {
                guard wordAfter(it) != nil, k + 1 < items.count, items[k + 1].kind == .number else { continue }
                let letter = MathContext.letter(of: MathSpeech.phrase(it, toks))
                let index = items[k + 1].text
                if ["0", "1", "2"].contains(index) { seen[letter, default: []].insert(index) } else { bad.insert(letter) }
            }
            return Set(seen.filter { $0.value.count >= 2 && !bad.contains($0.key) }.keys)
        }

        private func anchored(_ it: Item, _ items: [Item], _ itemAt: [Int], _ vocabulary: Bool) -> Bool {
            let index = itemAt[it.start]
            let previous = joinedLeft(it.start) && index > 0 ? items[index - 1] : nil
            // "value of lambda mu": the second name of a pair shares the first one's slot.
            if let previous, MathSpeech.isCandidate(previous, toks) {
                return anchored(previous, items, itemAt, vocabulary)
            }
            // …and the first one ends the sentence where its pair does.
            var end = it
            if wordAfter(it) != nil, index + 1 < items.count, MathSpeech.isCandidate(items[index + 1], toks) {
                end = items[index + 1]
            }
            var start = it.start
            while joinedLeft(start) { start -= 1 }
            let after = wordsAfter(end, max: 5)
            let endIndex = itemAt[end.start]
            // "let λ be 3" — and the number closes the clause (punctuation, the end, or a
            // connective): "let beta be 2 hours late" is English.
            var afterAfterIsNumber = false
            if !after.isEmpty, endIndex + 2 < items.count, wordAfter(items[endIndex + 1]) != nil,
               items[endIndex + 2].kind == .number {
                let number = items[endIndex + 2]
                let following = wordAfter(number)?.lowercased()
                afterAfterIsNumber = following == nil
                    || ["and", "so", "then", "where", "when", "if", "since", "because"].contains(following!)
            }
            let last = toks[end.start + end.count - 1]
            let sentenceFinal = last.trail.contains { ".?!".contains($0) }
                || (end.start + end.count == toks.count && last.trail.isEmpty)
            let afterTrig = previous?.kind == .symbol && previous?.sym?.kind == .function
                && ["sin", "cos", "tan", "sec", "csc", "cot"].contains(previous?.sym?.text ?? "")
            return MathContext.anchored(
                before: wordsBefore(it.start, max: 12),
                stretchStartsClause: sentenceInitial(start) || (start > 0 && toks[start - 1].trail.contains(",")),
                after: after,
                afterAfterIsNumber: afterAfterIsNumber,
                sentenceFinal: sentenceFinal,
                afterTrig: afterTrig,
                deliberateCapital: MathContext.isDeliberateCapital(MathSpeech.phrase(it, toks)),
                mathsVocabulary: vocabulary,
                valueStated: valueStatement(it, items, itemAt, []))
        }

        /// No punctuation between token `t - 1` and token `t` — they share a stretch.
        private func joinedLeft(_ t: Int) -> Bool {
            t > 0 && toks[t - 1].trail.isEmpty && toks[t].lead.isEmpty
        }

        /// Up to `max` words before token `t` inside its stretch, nearest first.
        private func wordsBefore(_ t: Int, max: Int) -> [String] {
            var words: [String] = []
            var k = t
            while words.count < max, joinedLeft(k) {
                k -= 1
                words.append(toks[k].core)
            }
            return words
        }

        /// Up to `max` words after an item inside its stretch.
        private func wordsAfter(_ it: Item, max: Int) -> [String] {
            var words: [String] = []
            var t = it.start + it.count
            while words.count < max, t < toks.count, joinedLeft(t) {
                words.append(toks[t].core)
                t += 1
            }
            return words
        }

        private func wordAfter(_ it: Item) -> String? {
            let next = it.start + it.count
            guard next < toks.count, joinedLeft(next) else { return nil }
            return toks[next].core
        }

        /// Where a sentence starts, a capital is the tone style's, not a name's.
        private func sentenceInitial(_ t: Int) -> Bool {
            t == 0 || !toks[t].lead.isEmpty
                || toks[t - 1].trail.contains { ".?!:;…".contains($0) }
        }
    }

    /// A Greek name context may promote: a Greek-letter operand whose spoken phrase is in
    /// `MathContext.promotable` (so never delta, bare sigma, eta, …).
    private static func isCandidate(_ it: Item, _ toks: [Tok]) -> Bool {
        guard it.kind == .symbol || it.suffix != nil, let sym = it.sym, sym.kind == .operand else { return false }
        if isChange(it) { return true }
        guard Parser.isGreekLetter(String(sym.text.prefix(1))) else { return false }
        return MathContext.promotable.contains(phrase(it, toks))
    }

    /// "delta x" lexed as one Δx operand (lexer step 3b).
    private static func isChange(_ it: Item) -> Bool {
        guard it.kind == .symbol, let text = it.sym?.text else { return false }
        return text.count == 2 && text.first == "Δ" && it.count == 2
    }

    /// An item's words, lower-cased and single-spaced — how the vocabulary keys are written. A
    /// glued name ("lambda's") is its name alone.
    private static func phrase(_ it: Item, _ toks: [Tok]) -> String {
        if let suffix = it.suffix {
            return String(toks[it.start].core.dropFirst(it.prefix.count).dropLast(suffix.count)).lowercased()
        }
        return toks[it.start..<(it.start + it.count)].map { $0.core.lowercased() }.joined(separator: " ")
    }

    /// Any Greek letter — or the weak ∑ of a bare "sigma" ("Lambda Chi Alpha", "Phi Beta Kappa").
    private static func isGreekItem(_ it: Item) -> Bool {
        guard it.kind == .symbol, let sym = it.sym else { return false }
        return Parser.isGreekLetter(sym.text) || sym.text == "∑"
    }

    /// A non-weak infix relation or operator ("equals", "plus"): a run holding one that still
    /// left a segment unconverted is a broken equation, which context never half-converts.
    private static func isOperatorLike(_ it: Item) -> Bool {
        guard it.kind == .symbol, !it.weak, let sym = it.sym else { return false }
        return sym.kind == .relation || sym.kind == .operatorSymbol
    }

    /// E1's construct: something only mathematics says — a relation, a function, a power, a
    /// root, a fraction, a derivative, a limit, a big operator. A bare "+", "-" or "×" is not
    /// enough ("T minus 10", "press X plus Y", "n plus 1 tickets", "w times h").
    private static func isStrongConstruct(_ it: Item) -> Bool {
        switch it.kind {
        case .symbol:
            guard let sym = it.sym else { return false }
            switch sym.kind {
            case .relation, .function: return true
            case .prefix: return sym.text != "-" && sym.text != "¬"
            case .postfix: return MathSymbols.activatingPostfixes.contains(sym.text)
            default: return false
            }
        case .keyword:
            switch it.key {
            case .sup, .pow2, .pow3, .power, .root, .over, .allOver, .deriv, .partialDeriv, .derivRatio,
                 .limit, .abs, .tendsTo, .approaches, .choose:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    /// A dash standing alone between words ("our team name — alpha — is cool"): a mention. A
    /// lone hyphen-minus is whisper's minus ("x = ⁴⁄₃ - lambda"), no dash (recall rework).
    private static func isDash(_ tok: Tok) -> Bool {
        ["—", "–", "--"].contains(tok.core) || (tok.core.isEmpty && (tok.lead + tok.trail).contains { "—–".contains($0) })
    }

    // ─────────────────────────── expression building ───────────────────────────

    /// The rendered pieces of one run, plus the spacing rules that join them: relations and
    /// operators get air ("1 + 7n"), scripts and postfixes bind tight ("aₙ", "5!"), and a
    /// number followed by a letter is a coefficient ("7n", "2π").
    private final class Expr {
        private enum Role { case operand, infix, head }

        /// What built an operand. A finished binomial is a wall for a later choose or
        /// factorial reaching back over a sum ("n choose k plus n choose k minus 1"), a finished
        /// quotient is one for a later "over" reaching back over a product ("3 over 4 times 2
        /// over 3" → "¾ · ⅔").
        enum Made { case plain, binomial, quotient }

        private struct Part {
            var text: String
            let role: Role
            var tight: Bool
            var made: Made = .plain
            /// An infix that is a RELATION ("=", "<", "→"): where one side of an equation ends.
            var relation = false
        }

        private var parts: [Part] = []
        var tightNext = false

        var count: Int { parts.count }
        var lastIsOperand: Bool { parts.last?.role == .operand }
        var lastText: String { parts[parts.count - 1].text }
        /// False when the last operand is glued onto the one before it ("2a").
        var lastStandsAlone: Bool { !(parts.last?.tight ?? false) }

        func pushOperand(_ text: String) {
            // "u n" is a sequence term, not a product (David, 2026-08-30).
            if let last = parts.last, last.role == .operand, Expr.indexes(last.text, text) {
                replaceLast(MathScript.attach(last.text, text, superscript: false))
                tightNext = false
                return
            }

            let tight = tightNext
                || (parts.last.map { $0.role == .operand && Expr.juxtaposes($0.text, text) } ?? false)
                // "angle A B C" → ∠ABC, "triangle A B C" → △ABC: the glyph names the points.
                || (parts.last.map { $0.role == .operand && ($0.text == "∠" || $0.text == "△") } ?? false)
                    && text.first?.isLetter == true
            parts.append(Part(text: text, role: .operand, tight: tight))
            tightNext = false
        }

        /// A big operator or a "lim" head: the body that follows is separated by a space.
        func pushHead(_ text: String) {
            parts.append(Part(text: text, role: .head, tight: tightNext))
            tightNext = false
        }

        func pushInfix(_ text: String, relation: Bool = false) {
            parts.append(Part(text: text, role: .infix, tight: false, relation: relation))
            tightNext = false
        }

        /// Where the current side of the equation begins: just after the last relation or
        /// "lim"/"∑" head, else 0 — what "all over" takes as its numerator.
        func sideStart() -> Int {
            var s = parts.count
            while s > 0 {
                let part = parts[s - 1]
                if part.role == .head || (part.role == .infix && part.relation) { break }
                s -= 1
            }
            return s
        }

        /// "n minus 1 times d" is (n - 1)d — nobody multiplies by a spoken 1 on purpose, so a
        /// "times" straight after "<lettered term> ± 1" takes that whole difference (the
        /// arithmetic-sequence term aₙ = a₁ + (n - 1)d). Only the one term before the 1:
        /// "a₁ + n - 1 times d" groups "n - 1", never "a₁ + n - 1".
        func groupTrailingOne() {
            let c = parts.count
            guard c >= 3, parts[c - 1].role == .operand, parts[c - 1].text == "1", !parts[c - 1].tight,
                  parts[c - 2].role == .infix, parts[c - 2].text == "+" || parts[c - 2].text == "-",
                  parts[c - 3].role == .operand else { return }
            var s = c - 3
            while s > 0, parts[s].tight, parts[s - 1].role == .operand { s -= 1 }
            guard (s...(c - 3)).contains(where: { Expr.hasLetter(parts[$0].text) }) else { return }
            // …and a whole term: not the tail of a product ("2 times n minus 1 times d").
            if s > 0, parts[s - 1].role == .infix, Parser.products.contains(parts[s - 1].text) { return }
            collapse(from: s, into: "(\(render(from: s)))")
        }

        /// Unused — as in the C# original, which builds a bracketed group as one whole
        /// operand string instead. Kept so the two files stay diffable.
        func pushOpen(_ text: String) {
            parts.append(Part(text: text, role: .head, tight: tightNext))
            tightNext = true
        }

        func attachToLast(_ suffix: String) { replaceLast(parts[parts.count - 1].text + suffix) }

        func replaceLast(_ text: String) {
            let last = parts[parts.count - 1]
            parts[parts.count - 1] = Part(text: text, role: .operand, tight: last.tight, made: last.made)
        }

        func render() -> String { render(from: 0) }

        /// A spoken "times" is laid out only here, once both of its sides are final (a later
        /// "squared" or "factorial" still changes them): `MathScript.productSeparator` picks
        /// "×", a space, or juxtaposition.
        /// "F = 12 N", "Δx = 5 m", "τ = 10 N m" (fix round): unit letters that END an equation
        /// after a number keep their space — they are units, not factors (was "12N").
        static let unitLetters: Set<String> = ["N", "J", "V", "W", "m", "s"]
        var hasEquals: Bool { parts.contains { $0.role == .infix && $0.text == "=" } }

        func render(from start: Int) -> String {
            var out = ""
            var joined = false
            for index in start..<parts.count {
                let part = parts[index]
                if part.role == .infix, part.text == Parser.timesMarker,
                   index > start, index + 1 < parts.count {
                    out += MathScript.productSeparator(parts[index - 1].text, parts[index + 1].text)
                    joined = true
                    continue
                }
                if index > start && !part.tight && !joined { out += " " }
                joined = false
                out += part.text
            }
            return out
        }

        /// True when the parts from `start` on hold an infix operator — a side that needs
        /// brackets once it becomes one operand of a larger construct.
        func isCompound(from start: Int) -> Bool {
            parts[start...].contains { $0.role == .infix }
        }

        /// Where the trailing term that `joins` hold together begins: from the last operand
        /// back over "<operand> <join> <operand>" links and implicit products ("2π"),
        /// stopping at anything else — a relation, another operator, a head — and at an
        /// operand `wall` built.
        func tailStart(joinedBy joins: Set<String>, wall: Made) -> Int {
            var s = parts.count - 1
            while s > 0, parts[s].made != wall {
                if parts[s].tight, parts[s - 1].role == .operand, parts[s - 1].made != wall {
                    s -= 1
                    continue
                }
                guard s >= 2, parts[s - 1].role == .infix, joins.contains(parts[s - 1].text),
                      parts[s - 2].role == .operand, parts[s - 2].made != wall else { break }
                s -= 2
            }
            return s
        }

        /// Of the terms from `start` on, where the first one holding a LETTER begins — or the
        /// last term, when none does. A spoken sum joins a binomial or a factorial only from
        /// its first letter on: "n plus k minus 1 choose k" takes all of "n + k - 1", but "1
        /// minus 48 choose 5" and "2 to the 10 minus 10 choose 0" take only the number beside
        /// "choose" (rule 2).
        func firstLetterTerm(from start: Int) -> Int {
            var termStart = start
            var index = start
            var lastTermStart = start
            while index < parts.count {
                if parts[index].role == .infix {
                    termStart = index + 1
                    lastTermStart = termStart
                } else if Expr.hasLetter(parts[index].text) {
                    return termStart
                }
                index += 1
            }
            return lastTermStart
        }

        /// True when the first term (everything before the first operator) holds a letter.
        var firstTermHasLetter: Bool {
            parts.prefix { $0.role != .infix }.contains { Expr.hasLetter($0.text) }
        }

        /// True when the first factor is a factorial or a binomial — the shape of a counting
        /// formula's denominator ("over k factorial times n minus k factorial").
        var firstFactorCounts: Bool {
            let end = parts.firstIndex { $0.role == .infix } ?? parts.count
            guard end > 0 else { return false }
            let factor = parts[end - 1]
            return factor.made == .binomial || factor.text.hasSuffix("!")
        }

        /// True when the last operand is what a "÷" divides by.
        var lastIsDivisor: Bool {
            parts.count >= 2 && parts[parts.count - 2].role == .infix && parts[parts.count - 2].text == "÷"
        }

        func markLast(_ made: Made) { parts[parts.count - 1].made = made }

        /// Replaces the parts from `start` on with ONE operand.
        func collapse(from start: Int, into text: String, made: Made = .plain) {
            let tight = parts[start].tight
            parts.removeSubrange(start...)
            parts.append(Part(text: text, role: .operand, tight: tight, made: made))
        }

        static func hasLetter(_ s: String) -> Bool { s.contains { $0.isLetter } }

        /// Two ATOMIC operands side by side are implicit multiplication and are written
        /// closed up: "7 n" → "7n", "2 π" → "2π", "delta x" → "δx". Anything already
        /// composite ("aₙ", "sin(x)", "1/2") keeps its space, where the product is clearer
        /// spaced out.
        static func juxtaposes(_ left: String, _ right: String) -> Bool {
            (isSingleLetter(right) || isChange(right) || isConstant(right))
                && (isSingleLetter(left) || isPlainNumber(left) || isConstant(left) || isPoweredSingleLetter(left))
        }

        /// "v²", "ω³": a single letter with a superscript power multiplies on like a letter —
        /// "v squared r" → "v²r" (round 3b verify; spec §1.3). "x² dx" keeps its space (a
        /// differential is no single letter).
        private static func isPoweredSingleLetter(_ s: String) -> Bool {
            guard s.count >= 2, let first = s.first, first.isLetter else { return false }
            return s.dropFirst().allSatisfy { "²³⁴⁵⁶⁷⁸⁹".contains($0) }
        }

        /// "ε₀", "μ₀" — a letter with its one-digit index multiplies like a letter: 4πε₀ (fix round).
        private static func isConstant(_ s: String) -> Bool {
            s.count == 2 && s.first!.isLetter && !s.first!.isASCII && "₀₁₂".contains(s.last!)
        }

        /// "Δx", "ΔT" — "delta x" (lexer step 3b) multiplies like a letter: "m c delta T" → mcΔT.
        private static func isChange(_ s: String) -> Bool {
            s.count == 2 && s.first == "Δ" && s.last!.isLetter
        }

        /// An implicit product or a sequence index — the only ways one operand carries straight
        /// on into the next without an operator between them.
        static func continuesImplicitly(_ left: String, _ right: String) -> Bool {
            juxtaposes(left, right) || indexes(left, right)
        }

        /// A variable followed by a classic INDEX is a sequence term — "u n" → "uₙ",
        /// "u 1" → "u₁", "2 u n" → "2uₙ" — which is how David dictates a sequence without
        /// saying "subscript" every time.
        ///
        /// Deliberately narrow in both directions: only the traditional index letters count,
        /// so "x y" stays the product "xy"; and only a lone variable (with an optional
        /// numeric coefficient) can carry one, so "sin(x) n" and "aₙ k" are left alone. It
        /// is also WEAK — it renders inside a run that something else already turned into
        /// mathematics and never activates one itself, so "i think u n is fine" is still a
        /// sentence.
        private static let indexLetters: Set<Character> = ["n", "k", "i", "j", "m"]

        private static func indexes(_ left: String, _ right: String) -> Bool {
            guard canCarryIndex(left) && isIndex(right) else { return false }
            // A capital carries only n, k or a number ("S n" → Sₙ); "G M m" is the product GMm.
            if left.last!.isUppercase, let r = right.first, r.isLetter { return r == "n" || r == "k" }
            return true
        }

        private static func canCarryIndex(_ s: String) -> Bool {
            guard let last = s.last, last.isLetter else { return false }
            return isInteger(String(s.dropLast()))
        }

        private static func isIndex(_ s: String) -> Bool {
            if !s.isEmpty && isInteger(s) { return true }
            guard isSingleLetter(s), let first = s.first else { return false }
            // lower-case only: "λ N" is the product λN (A = λN), not λ_N (fix round)
            return indexLetters.contains(first)
        }

        private static func isSingleLetter(_ s: String) -> Bool {
            s.count == 1 && s.first!.isLetter
        }

        private static func isInteger(_ s: String) -> Bool {
            s.allSatisfy { $0.isAsciiDigit }
        }

        static func isPlainNumber(_ s: String) -> Bool {
            !s.isEmpty && s.allSatisfy { $0.isAsciiDigit || $0 == "." }
        }
    }

    // ─────────────────────────────── parsing ───────────────────────────────

    /// How far one expression reaches — which of the grouping rules on `Parser` is reading it.
    private enum Scope {
        /// A whole run, or the inside of a bracket: everything.
        case run
        /// The right side of "choose" (rule 2): a sum or difference.
        case sum
        /// The denominator of "over" (rule 3): a product.
        case product
        /// What "f of" and the statistics functions apply to (rule 4): a sum, and "given".
        case argument
        /// What "P of" / "the probability of" apply to (rule 5): the whole event.
        case event
        /// The denominator after "all over" (rule 6): everything up to the next relation.
        case side
    }

    /// One run's items plus the facts about them the parser asks over and over — computed
    /// once, right to left, on first use — so every such question is O(1) and a long run
    /// stays linear.
    private final class Run {
        let items: [Item]
        /// The weak operand that sits right before an ordinary word, or -1.
        let weakCutoff: Int
        /// True when the run ends at punctuation or at the end of the dictation, false when an
        /// ordinary word cut it short.
        let cleanEnd: Bool

        init(items: [Item], weakCutoff: Int, cleanEnd: Bool) {
            self.items = items
            self.weakCutoff = weakCutoff
            self.cleanEnd = cleanEnd
        }

        /// The sum starting at `k` runs into a "choose" before anything ends it.
        func sumReachesChoose(_ k: Int) -> Bool { k < items.count && reachesChoose[k] }

        /// The sum starting at `k` is closed by a factorial, which makes it ONE factor ("over
        /// k factorial times n minus k factorial").
        func sumEndsInFactorial(_ k: Int) -> Bool { k < items.count && endsInFactorial[k] }

        /// The term at `k` is where the next binomial's left side begins: the sum from `k`
        /// runs into a "choose", and this term holds a letter or is the last one before it
        /// (the same test `Expr.firstLetterTerm` applies once the binomial is built).
        func startsBinomial(_ k: Int) -> Bool {
            k < items.count && reachesChoose[k] && (letterInTerm[k] || !sumOperatorAhead[k])
        }

        /// The sum that runs up to `k` already holds a letter — so a "choose" ahead will take
        /// it in, operator and all ("over n minus 1 choose k").
        func sumBehindHasLetter(_ k: Int) -> Bool { k < items.count && letterBehind[k] }

        /// The product starting at `k` runs into another "over" — so it is that fraction's
        /// numerator, not part of this one's denominator ("3 over 4 times 2 over 3").
        func productReachesOver(_ k: Int) -> Bool { k < items.count && reachesOver[k] }

        /// A relation other than "given" follows at `k` or later.
        func relationAhead(_ k: Int) -> Bool { k < items.count && relations[k] }

        private lazy var reachesChoose: [Bool] = scan { item, rest in
            item.key == .choose || ((Run.continuesSum(item) || Run.isFactorial(item)) && rest)
        }

        private lazy var endsInFactorial: [Bool] = scan { item, rest in
            Run.isFactorial(item) || (Run.continuesSum(item) && rest)
        }

        private lazy var letterInTerm: [Bool] = scan { item, rest in
            Run.continuesSum(item) && !Run.isSumOperator(item) && (Run.isLettered(item) || rest)
        }

        private lazy var sumOperatorAhead: [Bool] = scan { item, rest in
            Run.isSumOperator(item) || ((Run.continuesSum(item) || Run.isFactorial(item)) && rest)
        }

        private lazy var letterBehind: [Bool] = {
            var out = [Bool](repeating: false, count: items.count)
            var seen = false
            for k in 0..<items.count {
                seen = Run.continuesSum(items[k]) && (seen || Run.isLettered(items[k]))
                out[k] = seen
            }
            return out
        }()

        private lazy var reachesOver: [Bool] = scan { item, rest in
            item.key == .over || (Run.continuesProduct(item) && rest)
        }

        private lazy var relations: [Bool] = scan { item, rest in
            (item.kind == .symbol && item.sym?.kind == .relation && item.sym?.text != "∣") || rest
        }

        private func scan(_ rule: (Item, Bool) -> Bool) -> [Bool] {
            var out = [Bool](repeating: false, count: items.count)
            var rest = false
            for k in stride(from: items.count - 1, through: 0, by: -1) {
                rest = rule(items[k], rest)
                out[k] = rest
            }
            return out
        }

        /// An item a spoken sum runs THROUGH: an atom, a + or −, "squared"/"cubed", or a
        /// postfix other than a factorial.
        private static func continuesSum(_ item: Item) -> Bool {
            switch item.kind {
            case .number, .variable:
                return true
            case .keyword:
                return item.key == .pow2 || item.key == .pow3
            case .symbol:
                guard let sym = item.sym else { return false }
                switch sym.kind {
                case .operand: return true
                case .postfix: return !Parser.isFactorial(sym.text)
                case .operatorSymbol: return Parser.additive.contains(sym.text)
                default: return false
                }
            case .word:
                return false
            }
        }

        /// An item a spoken product runs through on its way to a following "over".
        private static func continuesProduct(_ item: Item) -> Bool {
            switch item.kind {
            case .number, .variable:
                return true
            case .keyword:
                return item.key == .pow2 || item.key == .pow3 || item.key == .sub
            case .symbol:
                guard let sym = item.sym else { return false }
                return sym.kind == .operand || sym.kind == .postfix
                    || (sym.kind == .operatorSymbol && Parser.products.contains(sym.text))
            case .word:
                return false
            }
        }

        private static func isFactorial(_ item: Item) -> Bool {
            item.kind == .symbol && item.sym?.kind == .postfix && Parser.isFactorial(item.sym!.text)
        }

        private static func isSumOperator(_ item: Item) -> Bool {
            item.kind == .symbol && item.sym?.kind == .operatorSymbol
                && Parser.additive.contains(item.sym!.text)
        }

        /// A variable, or a number or symbol spelled with a letter ("7n", "π").
        private static func isLettered(_ item: Item) -> Bool {
            switch item.kind {
            case .variable: return true
            case .number: return Expr.hasLetter(item.text)
            case .symbol: return item.sym?.kind == .operand && Expr.hasLetter(item.text)
            default: return false
            }
        }
    }

    /// Walks one run left to right, folding items into an `Expr`. Stops at the first item it
    /// cannot consume and reports how far it got, so the caller can hand the leftovers back
    /// out as plain words.
    ///
    /// ── The grouping rule ─────────────────────────────────────────────────────────────
    /// Everything is written in the order it was said. Only these constructs decide how far
    /// their operands reach — tightest first — and a side with more than one term is
    /// bracketed so the result can never be misread:
    ///   1. FACTORIAL takes the sum in front of it (back to the nearest "·", "÷", relation,
    ///      bracket or binomial) from its first letter on: "n minus k factorial" → "(n - k)!",
    ///      "2 plus n minus 1 factorial" → "2 + (n - 1)!", but "5 plus 3 factorial" → "5 + 3!".
    ///      In a denominator it takes the whole sum — "over 3 factorial times 10 minus 3
    ///      factorial" → "÷ (3! · (10 - 3)!)" — because only a factorial lets a sum in there.
    ///   2. CHOOSE takes a sum on each side — never a product — when that sum starts with a
    ///      letter: "n plus k minus 1 choose k" → "C(n + k - 1, k)", "n choose n minus k" →
    ///      "C(n, n - k)"; otherwise just the term beside it: "1 minus 48 choose 5" → "1 -
    ///      C(48, 5)", "n choose 2 minus n" → "C(n, 2) - n", "26 choose 4 times 10 choose 3"
    ///      → "C(26, 4) · C(10, 3)". A sum after one choose that runs into another stops
    ///      where the next binomial's left side starts: "n choose k plus n choose k minus 1"
    ///      → "C(n, k) + C(n, k - 1)".
    ///   3. OVER divides a PRODUCT by a PRODUCT when one was dictated — the numerator is a
    ///      product, or the denominator starts with a factorial or a binomial, the shape of
    ///      every counting formula: "10 times 9 times 8 over 3 times 2 times 1" → "(10 · 9 ·
    ///      8) ÷ (3 · 2 · 1)", "n factorial over k factorial times n minus k factorial" → "n!
    ///      ÷ (k! · (n - k)!)". Otherwise it divides the factor beside it by the factor after
    ///      it, as it always did: "1 over 36 times 100 percent" → "¹⁄₃₆ · 100%", "3 over 4
    ///      plus 1 over 4" → "¾ + ¼". Either way a product that runs into another "over"
    ///      belongs to that one ("3 over 4 times 2 over 3" → "¾ · ⅔"), a binomial or a
    ///      factorial is one factor ("1 over 52 choose 5" → "1 ÷ C(52, 5)"), "squared" and
    ///      "cubed" stay on the denominator ("1 over n squared" → "1 ÷ n²") while "to the"
    ///      raises the whole fraction ("5 over 6 to the 4" → "⅚⁴"), and two single atoms
    ///      still stack ("½", "ˣ⁄ₙ").
    ///   4. "f of" (any letter applied with "of") and "the expected value / variance /
    ///      covariance / correlation / standard deviation of" take a sum and "given": "f of n
    ///      minus 1" → "f(n - 1)", "the variance of X plus Y" → "Var(X + Y)". A term that is
    ///      itself an application or a binomial starts the next term instead: "f of n minus 1
    ///      plus f of n minus 2" → "f(n - 1) + f(n - 2)". A power still lands on the whole
    ///      application ("E of X squared" → "E(X)²"), and every other function (sine, log, …)
    ///      takes one operand, as before.
    ///   5. "P of" / "the probability of" take the whole EVENT — rule 4 plus powers, ∪ ∩ ∖,
    ///      "over", and one relation on each side of "given": "P of X less than 3" → "P(X <
    ///      3)", "the
    ///      probability of A given B" → "P(A ∣ B)". "equals" joins the event only when another
    ///      relation follows it, because "the probability of A equals one half" is P(A) = ½:
    ///      "P of X equals 3 equals 0.2" → "P(X = 3) = 0.2". An unclosed bracket — "the
    ///      probability that …" — closes before its second relation the same way: "… that X
    ///      is at most 3 equals 0.65" → "P(X ≤ 3) = 0.65".
    ///   6. "ALL OVER" (2026-09-29) takes the whole side so far as its numerator and the rest
    ///      of the side, up to the next relation, as its denominator: "x squared minus 9 all
    ///      over x minus 3" → "(x² - 9)/(x - 3)". "THE QUANTITY" opens a bracket that closes
    ///      at "close bracket", else before the next relation or "all over", else at the end
    ///      of the run: "the square root of the quantity b squared minus 4 a c" → "√(b² -
    ///      4ac)". Without them every construct takes the SMALLEST reading (spec §6.1):
    ///      "the square root of x plus 1" → "√x + 1", "log base 3 of x plus 1" → "log₃x + 1".
    ///   7. "TIMES" after "<lettered term> ± 1" takes that difference: "n minus 1 times d" →
    ///      "(n - 1)d" (`Expr.groupTrailingOne`).
    /// None of this can make ordinary speech convert: grouping only decides where operands
    /// END. Every item it takes is one the flat fold would have read into the same run, and
    /// activation still comes only from the constructs themselves.
    private final class Parser {
        private let ctx: Run
        private let items: [Item]
        private let scope: Scope
        /// Rule 5's budget: an event — or an unclosed bracket — holds one relation on each
        /// side of "given"; the next one ends it.
        private let limitsRelations: Bool
        /// Rule 3: this denominator may run on over "·" because its numerator was a product.
        private let joinsProducts: Bool
        private var relationsInPart = 0
        private var activated = false

        static let additive: Set<String> = ["+", "-", "±", "∓"]
        /// The internal text of a spoken "times" / "multiplied by" (and whisper's "3 x 4").
        /// It never reaches the output: `Expr.render` lays it out as "×", a space or
        /// juxtaposition. "·" is the dot product alone.
        static let timesMarker = "*"
        static let products: Set<String> = ["·", timesMarker]
        /// Marks that turn a letter into a named function when "of" follows: "f prime of x"
        /// → f′(x), "f inverse of x" → f⁻¹(x).
        static let functionMarks: Set<String> = ["′", "″", "‴", "⁻¹"]
        private static let setOperations: Set<String> = ["∪", "∩", "∖"]

        /// The functions that apply to a whole expression (rules 4 and 5) rather than to one
        /// operand.
        private static let argumentScopes: [String: Scope] = [
            "P": .event, "E": .argument, "Var": .argument, "Cov": .argument,
            "Corr": .argument, "SD": .argument,
        ]

        static func isFactorial(_ text: String) -> Bool { text == "!" || text == "!!" }

        init(_ ctx: Run, scope: Scope = .run, limitsRelations: Bool = false, joinsProducts: Bool = false) {
            self.ctx = ctx
            self.items = ctx.items
            self.scope = scope
            self.limitsRelations = limitsRelations
            self.joinsProducts = joinsProducts
        }

        func run(_ start: Int) -> (text: String, activated: Bool, used: Int) {
            let expr = Expr()
            var i = start
            while i < items.count, step(expr, &i) {}
            return (spacingUnits(expr.render(), expr, start, i), activated, i - start)
        }

        /// The run's last items are unit letters after a number, in an equation: write them
        /// spaced ("12 N", "10 N m") instead of as a product ("12N").
        private func spacingUnits(_ text: String, _ expr: Expr, _ start: Int, _ end: Int) -> String {
            guard expr.hasEquals, end - start >= 3 else { return text }
            var k = end - 1
            var units: [String] = []
            while k > start, items[k].kind == .variable, Expr.unitLetters.contains(items[k].text) {
                units.insert(items[k].text, at: 0)
                k -= 1
            }
            guard !units.isEmpty, items[k].kind == .number else { return text }
            let glued = items[k].text + units.joined()
            // the rendered tail, spaces aside, must be exactly number + units
            var tail = 0
            var seen = ""
            for c in text.reversed() {
                if seen.count == glued.count { break }
                tail += 1
                if c != " " { seen.insert(c, at: seen.startIndex) }
            }
            guard seen == glued else { return text }
            return String(text.dropLast(tail)) + items[k].text + " " + units.joined(separator: " ")
        }

        private func step(_ expr: Expr, _ i: inout Int) -> Bool {
            let it = items[i]

            if it.kind == .keyword { return allows(it.key) && keyword(expr, &i) }

            if it.kind == .symbol, let sym = it.sym {
                if sym.kind == .relation || sym.kind == .operatorSymbol {
                    guard reaches(sym, i, expr), expr.lastIsOperand else { return false }

                    // "divided by" keeps the school ÷ between plain numbers ("6 × 7 ÷ 2") and
                    // is a fraction in algebra ("x divided by 2 y" → x/2y), its denominator
                    // read like one after "over" (a power stays on it: "x/y²").
                    if sym.text == "÷" {
                        // "4 ÷ 3 pi r³" → (4/3)π…, as for "over" (the sphere's coefficient).
                        let numerator = expr.lastText
                        if numerator != "1", Expr.isPlainNumber(numerator), !numerator.contains("."),
                           i + 2 < items.count, items[i + 1].kind == .number, !items[i + 1].text.contains("."),
                           items[i + 2].sym?.text == "π", let denominator = tryOperand(i + 1, allowApply: false),
                           denominator.next == i + 2 {
                            expr.collapse(from: expr.count - 1, into: "(" + numerator + "/" + denominator.text + ")",
                                          made: .quotient)
                            expr.tightNext = true
                            if sym.activates && !it.weak { activated = true }
                            i = denominator.next
                            return true
                        }
                        guard let bottom = subExpression(i + 1, .product) else { return false }
                        if MathScript.isNumeric(expr.lastText) && MathScript.isNumeric(bottom.text) {
                            expr.pushInfix("÷")
                            expr.pushOperand(bottom.text)
                        } else {
                            expr.collapse(from: expr.count - 1,
                                          into: MathScript.slashFraction(expr.lastText, bottom.text),
                                          made: .quotient)
                        }
                        if sym.activates && !it.weak { activated = true }
                        i = bottom.next
                        return true
                    }

                    // Round 3b (verify): a spoken comparison "is the same as" never chains onto an
                    // equation ("x = 2 is the same as 2x = 4", "r = a + λb is the same as t" — the
                    // English compares the two, it does not assert x = 2 = 2x); and "such that" /
                    // "given that" is the set-builder bar only when the condition ends the run
                    // ("Is there a λ ∣ 2x + y = 0?") — "Find k such that x = 2 is a root." goes on in
                    // English, so the phrase stays words.
                    if sym.kind == .relation, sym.text == "=", it.count >= 3, expr.hasEquals { return false }
                    if sym.kind == .relation, sym.text == "∣", it.count >= 2, scope == .run, !ctx.cleanEnd { return false }

                    guard let rhs = tryOperand(i + 1) else { return false }

                    let given = sym.kind == .relation && sym.text == "∣"
                    let budgeted = sym.kind == .relation && !given && (limitsRelations || scope == .event)
                    if budgeted {
                        guard relationsInPart == 0 else { return false }
                        if scope == .event, sym.text == "=",
                           startsApplication(i + 1) || !ctx.relationAhead(rhs.next) { return false }
                    }

                    // "I'm bringing a plus one": the article "a" (or the pronoun "i") joined to
                    // a bare number by an operator is English — the pair renders inside a run
                    // something else activated, but never activates one itself. ("a equals 5"
                    // is a relation and still converts.)
                    let articlePair = sym.kind == .operatorSymbol && expr.lastStandsAlone && i > 0
                        && items[i - 1].kind == .variable && items[i - 1].weak
                        && expr.lastText == items[i - 1].text
                        && items[i + 1].kind == .number && rhs.next == i + 2
                        && Expr.isPlainNumber(rhs.text)

                    if sym.text == Parser.timesMarker { expr.groupTrailingOne() }
                    expr.pushInfix(sym.text, relation: sym.kind == .relation)
                    expr.pushOperand(rhs.text)
                    // A glued "Kx" on either side is no evidence of mathematics (lexer 5b).
                    if sym.activates && !it.weak && !articlePair && !items[i + 1].glued
                        && !gluedBase(i) { activated = true }
                    if given { relationsInPart = 0 } else if budgeted { relationsInPart += 1 }
                    i = rhs.next
                    return true
                }
                if sym.kind == .postfix {
                    // After "choose" a postfix belongs to the binomial: "C(n, k)!".
                    guard scope != .sum, expr.lastIsOperand else { return false }
                    var start = expr.count - 1
                    if Parser.isFactorial(sym.text) {
                        // Rule 1: the sum in front of it, from its first letter on — all of
                        // it in a denominator.
                        start = expr.tailStart(joinedBy: Parser.additive, wall: .binomial)
                        if scope != .product { start = expr.firstLetterTerm(from: start) }
                    }
                    if expr.isCompound(from: start) {
                        expr.collapse(from: start, into: "(\(expr.render(from: start)))\(sym.text)")
                    } else {
                        expr.attachToLast(sym.text)
                    }
                    // "5 factorial" → 5! on its own — but only where it ENDS the dictation or
                    // sentence: "a 2 by 2 factorial design" is statistics English, and "5
                    // factorial ways" reads fine as words.
                    if sym.activates && i + 1 == items.count && ctx.cleanEnd { activated = true }
                    i += 1
                    return true
                }
                // A close bracket is normally swallowed by group(); a stray one is
                // unbalanced speech, so leave it (and everything after) as plain words.
                if sym.kind == .close { return false }
                if sym.isBigOperator { return scope == .run && bigOperator(expr, &i) }
            }

            let wasActivated = activated
            if let operand = tryOperand(i) {
                // A grouped operand carries on without an operator only in a denominator, and
                // only as an implicit product ("over 2 pi" → "2π"); anything else belongs to
                // the construct around it.
                if scope != .run, expr.lastIsOperand,
                   !((scope == .product || scope == .side) && Expr.continuesImplicitly(expr.lastText, operand.text)) {
                    activated = wasActivated
                    return false
                }
                expr.pushOperand(operand.text)
                if it.kind == .symbol, it.sym?.activates == true { activated = true }
                i = operand.next
                return true
            }
            return false
        }

        /// Whether the expression this parser is reading carries on through the infix `sym`
        /// at `i` — the grouping rule, asked at every operator.
        private func reaches(_ sym: MathSymbol, _ i: Int, _ expr: Expr) -> Bool {
            let isRelation = sym.kind == .relation
            let isSum = !isRelation && Parser.additive.contains(sym.text)
            switch scope {
            case .run:
                return true
            case .side:
                return !isRelation
            case .sum:
                return isSum && expr.firstTermHasLetter
                    && !startsApplication(i + 1) && !ctx.startsBinomial(i + 1)
            case .product:
                if !isRelation && Parser.products.contains(sym.text) {
                    return (joinsProducts || expr.firstFactorCounts) && !ctx.productReachesOver(i + 1)
                }
                // A sum gets into a denominator only as one factor: closed by a factorial, or
                // taken whole by a binomial.
                return isSum && (ctx.sumEndsInFactorial(i + 1)
                    || (ctx.sumReachesChoose(i + 1) && ctx.sumBehindHasLetter(i)))
            case .argument, .event:
                if isRelation {
                    return (scope == .event || sym.text == "∣") && !startsApplication(i + 1)
                }
                let joins = isSum || (scope == .event && Parser.setOperations.contains(sym.text))
                return joins && !startsApplication(i + 1) && !ctx.startsBinomial(i + 1)
            }
        }

        /// The structural keywords a grouped operand takes in; any other ends it and is left
        /// to the construct around it ("n choose k squared" → "C(n, k)²").
        private func allows(_ key: Kw) -> Bool {
            switch scope {
            case .run: return true
            case .side: return key != .allOver && key != .tendsTo
            case .sum: return key == .sub
            case .argument: return key == .sub || key == .choose
            case .product: return key == .sub || key == .pow2 || key == .pow3 || key == .choose
            case .event: return [.sub, .sup, .power, .pow2, .pow3, .over, .choose].contains(key)
            }
        }

        /// True when the operand at `k` is itself an application — "f of …", "sine of …",
        /// "the probability of/that …" — so it starts a new term rather than extending one.
        private func startsApplication(_ k: Int) -> Bool {
            var k = k
            if k < items.count, items[k].key == .the { k += 1 }
            guard k < items.count else { return false }
            let it = items[k]
            if it.kind == .variable, !it.weak, k + 1 < items.count, items[k + 1].key == .of { return true }
            guard it.kind == .symbol, let sym = it.sym else { return false }
            return sym.kind == .function || sym.text == "P("
        }

        /// The operand at `k` together with everything `scope` lets it reach — the grouping
        /// rule's one entry point. `compound` is true when it holds an infix operator, i.e.
        /// when it needs brackets as one side of a larger construct.
        private func subExpression(_ k: Int, _ scope: Scope,
                                   joinsProducts: Bool = false) -> (text: String, compound: Bool, next: Int)? {
            let child = Parser(ctx, scope: scope, joinsProducts: joinsProducts)
            guard let first = child.tryOperand(k) else { return nil }
            let expr = Expr()
            expr.pushOperand(first.text)
            var j = first.next
            while j < items.count, child.step(expr, &j) {}
            if child.activated { activated = true }
            return (expr.render(), expr.isCompound(from: 0), j)
        }

        private func keyword(_ expr: Expr, _ i: inout Int) -> Bool {
            let it = items[i]
            switch it.key {
            case .sub, .sup, .power:
                guard expr.lastIsOperand else { return false }
                let isSuper = it.key != .sub
                guard let script = isSuper ? tryExponent(i + 1) : tryScriptOperand(i + 1) else { return false }
                expr.replaceLast(MathScript.attach(isSuper ? MathScript.powerBase(expr.lastText) : expr.lastText,
                                                   MathScript.scriptOperand(script.text), superscript: isSuper))
                if (!it.weak || powerIsUnmistakable(i, script.next)) && !gluedBase(i) { activated = true }
                i = script.next
                return true

            case .pow2, .pow3:
                guard expr.lastIsOperand else { return false }
                expr.replaceLast(MathScript.attach(MathScript.powerBase(expr.lastText), it.key == .pow2 ? "2" : "3",
                                                   superscript: true))
                if !gluedBase(i) { activated = true }
                i += 1
                return true

            case .root, .abs, .derivRatio:
                // All three build a self-contained operand, so tryOperand owns the one
                // implementation and they also work in operand position ("x equals the
                // square root of 2", "from 0 to the square root of 2"). A bare "root of" is
                // weak: tryOperand decides whether it activates.
                guard let built = tryOperand(i) else { return false }
                expr.pushOperand(built.text)
                if !it.weak { activated = true }
                i = built.next
                return true

            case .quantity:
                // A bracket: weak, it renders inside a run something else made mathematics.
                guard let built = tryOperand(i) else { return false }
                expr.pushOperand(built.text)
                i = built.next
                return true

            case .over:
                // A division is a slash (docs/math-notation-format.md, 2026-09-29 — the format
                // BetterScreenshot pastes too): "π/6", "1/x²", "(10 × 9 × 8)/(3 × 2 × 1)",
                // with parentheses on a side that holds a space or an operator. How far each
                // side reaches is rule 3 of the grouping rule.
                guard expr.lastIsOperand else { return false }
                if scope == .event && startsApplication(i + 1) { return false }
                let top = expr.tailStart(joinedBy: Parser.products, wall: .quotient)
                let topIsProduct = expr.isCompound(from: top)
                // "4 over 3 pi r cubed" → (4/3)πr³ (fix round): an integer other than 1 over an
                // integer that π follows is the sphere's coefficient — "1 over 2 pi" stays 1/(2π).
                let numerator = expr.render(from: top)
                if !topIsProduct, numerator != "1", Expr.isPlainNumber(numerator), !numerator.contains("."),
                   i + 2 < items.count, items[i + 1].kind == .number, !items[i + 1].text.contains("."),
                   items[i + 2].sym?.text == "π", let denominator = tryOperand(i + 1, allowApply: false),
                   denominator.next == i + 2 {
                    expr.collapse(from: top, into: "(" + numerator + "/" + denominator.text + ")", made: .quotient)
                    expr.tightNext = true
                    activated = true
                    i = denominator.next
                    return true
                }
                guard let bottom = subExpression(i + 1, .product, joinsProducts: topIsProduct) else {
                    return false
                }
                // A product over a product; otherwise the factor beside "over" by the one after.
                let from = bottom.compound ? top : expr.count - 1
                expr.collapse(from: from, into: MathScript.slashFraction(expr.render(from: from), bottom.text),
                              made: .quotient)
                activated = true
                i = bottom.next
                return true

            case .allOver:
                // Rule 6: the whole side so far over the rest of the side. Weak.
                guard expr.lastIsOperand else { return false }
                let top = expr.sideStart()
                guard let bottom = subExpression(i + 1, .side) else { return false }
                expr.collapse(from: top, into: MathScript.slashFraction(expr.render(from: top), bottom.text),
                              made: .quotient)
                i = bottom.next
                return true

            case .tendsTo:
                // "x tends to infinity" → x → ∞. Only after a LOWER-CASE variable (with its
                // scripts: "aₙ tends to 0") or an application ("f(x)"): "type 2 tends to 3 times
                // more" and "plan B tends to 5 percent" are English, and so is the article "a".
                guard expr.lastIsOperand, Parser.canTend(expr.lastText),
                      let target = tryOperand(i + 1) else { return false }
                expr.pushInfix("→", relation: true)
                expr.pushOperand(target.text)
                activated = true
                i = target.next
                return true

            case .of:
                // "20 percent of 50" stays one operand inside an equation: "20% of 50 = 10".
                // Weak: "I'm 100 percent of the way there" is still a sentence.
                guard expr.lastIsOperand, expr.lastText.hasSuffix("%"),
                      let whole = tryOperand(i + 1) else { return false }
                expr.attachToLast(" of " + whole.text)
                i = whole.next
                return true

            case .choose:
                // "n choose k" → the binomial "C(n, k)"; how far each side reaches is rule 2.
                guard expr.lastIsOperand else { return false }
                guard let k = subExpression(i + 1, .sum) else { return false }
                let start = expr.firstLetterTerm(from: expr.tailStart(joinedBy: Parser.additive, wall: .binomial))
                expr.collapse(from: start, into: "C(\(expr.render(from: start)), \(k.text))", made: .binomial)
                activated = true
                i = k.next
                return true

            case .deriv, .partialDeriv:
                guard let of = tryPoweredOperand(i + 1) else { return false }
                guard of.next < items.count, items[of.next].key == .wrt else { return false }
                guard let wrt = tryOperand(of.next + 1) else { return false }
                let d = it.key == .deriv ? "d" : "∂"
                expr.pushOperand("\(d)\(Parser.bracket(of.text))/\(d)\(Parser.bracket(wrt.text))")
                activated = true
                i = wrt.next
                return true

            case .limit:
                let j = i + 1
                guard j < items.count, items[j].key == .asKeyword else { return false }
                guard let variable = tryOperand(j + 1) else { return false }
                guard variable.next < items.count,
                      items[variable.next].key == .approaches || items[variable.next].key == .tendsTo
                else { return false }
                // allowApply: false — the "of" after the target opens the limit's BODY.
                guard let target = tryOperand(variable.next + 1, allowApply: false) else { return false }
                var afterTarget = target.next
                if afterTarget < items.count, items[afterTarget].key == .of { afterTarget += 1 }
                expr.pushHead(MathScript.attach("lim", "\(variable.text)→\(target.text)", superscript: false))
                activated = true
                i = afterTarget
                return true

            default:
                return false // "of" / "from" / "to" / "as" with nothing to attach to
            }
        }

        /// A bare "to the" is ordinary English as often as it is a power — "I gave 5 to the 3
        /// kids", "compared 2019 to the 2020 season", "we moved to the fifth floor" — so on
        /// its own it only makes a run mathematics when the exponent leaves no doubt:
        ///   • "x to the fifth power" — the word "power";
        ///   • "10 to the fifth", "x to the 3rd" — an ordinal that ENDS the sentence or the
        ///     dictation (after "the", an English ordinal is followed by its noun), except
        ///     "first"/"second" after a number: "I gave 5 to the first, 3 to the second.";
        ///   • "x to the 3", "2 to the n" — anything but two plain numbers. "10 to the 5" alone
        ///     stays words, and still renders once something else activates the run: "2 to
        ///     the 10 equals 1024" → "2¹⁰ = 1024".
        private func powerIsUnmistakable(_ i: Int, _ end: Int) -> Bool {
            // A signed exponent is judged by its number: "from 5 to the minus 3" is no power.
            var exponent = items[i + 1]
            if isMinus(exponent), i + 2 < items.count { exponent = items[i + 2] }
            let base = items[i - 1]
            let plainBase = base.kind == .number || (base.kind == .variable && base.weak)
            switch exponent.ordinal {
            case .withPower:
                return true
            case .bare:
                return end == items.count && ctx.cleanEnd
                    && !(plainBase && (exponent.text == "1" || exponent.text == "2"))
            case .none:
                return !(plainBase && exponent.kind == .number)
            }
        }

        private static func rootSign(_ degree: String) -> String {
            switch degree {
            case "2": return "√"
            case "3": return "∛"
            case "4": return "∜"
            default: return (MathScript.superscript(degree) ?? degree) + "√"
            }
        }

        private func bigOperator(_ expr: Expr, _ i: inout Int) -> Bool {
            guard let sym = items[i].sym else { return false }
            var text = sym.text
            var j = i + 1
            var bounded = false

            if j < items.count, items[j].key == .from {
                guard let lower = tryBound(j + 1) else { return false }
                // "from 0 to the square root of 2" lexes "to the" as a power keyword; as a
                // bounds separator it means the same "to".
                guard lower.next < items.count,
                      items[lower.next].key == .to || items[lower.next].key == .power else { return false }
                guard let upper = tryBound(lower.next + 1) else { return false }
                text = MathScript.attach(
                    MathScript.attach(sym.text, lower.text, superscript: false),
                    upper.text,
                    superscript: true
                )
                j = upper.next
                bounded = true
            }

            if j < items.count, items[j].key == .of { j += 1 }

            // Without bounds a big operator must at least have a body, otherwise "an
            // integral part of the plan" would turn into "an ∫ part of the plan".
            if !bounded && tryOperand(j) == nil { return false }

            expr.pushHead(text)
            // A bare "sigma" (weak) activates nothing: "six sigma of 3 teams" is English.
            if bounded || !items[i].weak { activated = true }
            i = j
            return true
        }

        /// An operand plus anything that multiplies into it implicitly: "i pi" → "iπ",
        /// "2 a" → "2a". Used where the whole product belongs to one slot — an exponent, a
        /// subscript, a derivative.
        private func tryScriptOperand(_ k: Int) -> (text: String, next: Int)? {
            guard var current = tryOperand(k) else { return nil }
            while let more = tryOperand(current.next), Expr.juxtaposes(current.text, more.text) {
                current = (current.text + more.text, more.next)
            }
            return current
        }

        /// What may stand before "tends to": a lower-case variable — Greek included — with any
        /// scripts ("x", "aₙ", "θ"), or a function application ("f(x)"). Never "a" or "i".
        static func canTend(_ operand: String) -> Bool {
            if MathScript.isApplication(operand) { return true }
            guard let first = operand.first, first.isLetter, first.isLowercase,
                  operand != "a", operand != "i" else { return false }
            return operand.dropFirst().allSatisfy { !$0.isASCII || !$0.isLetter && !$0.isNumber }
        }

        /// The operand ending just before `i` (past any "squared"/"cubed") is a glued "Kx".
        private func gluedBase(_ i: Int) -> Bool {
            var j = i - 1
            while j >= 0, items[j].kind == .keyword, items[j].key == .pow2 || items[j].key == .pow3 { j -= 1 }
            return j >= 0 && items[j].glued
        }

        static func isGreekLetter(_ text: String) -> Bool {
            guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return false }
            return (0x391...0x3C9).contains(scalar.value)
        }

        private func isMinus(_ item: Item) -> Bool {
            item.kind == .symbol && item.sym?.kind == .operatorSymbol && item.sym?.text == "-"
        }

        /// An exponent: an operand with its implicit product and any "squared"/"cubed" that
        /// follows, optionally signed with a spoken "minus" — "10 to the power of minus 3" →
        /// 10⁻³, "e to the minus x squared" → e^(-x²) (the "²" has no superscript form, so the
        /// whole exponent falls back rather than mixing styles).
        private func tryExponent(_ k: Int) -> (text: String, next: Int)? {
            if k < items.count, isMinus(items[k]), let body = tryPoweredOperand(k + 1) {
                return ("-" + body.text, body.next)
            }
            return tryPoweredOperand(k)
        }

        /// As above, plus a trailing "squared"/"cubed" — without it "the derivative of x
        /// cubed with respect to x" would lose the whole construct at the word "cubed".
        private func tryPoweredOperand(_ k: Int) -> (text: String, next: Int)? {
            guard var current = tryScriptOperand(k) else { return nil }
            while current.next < items.count, items[current.next].kind == .keyword,
                  items[current.next].key == .pow2 || items[current.next].key == .pow3 {
                current = (
                    MathScript.attach(current.text, items[current.next].key == .pow2 ? "2" : "3", superscript: true),
                    current.next + 1
                )
            }
            return current
        }

        private static func bracket(_ operand: String) -> String {
            operand.count == 1 ? operand : "(\(operand))"
        }

        /// A summation/integration bound, which may be a small equation: "n equals 1" → "n=1".
        private func tryBound(_ k: Int) -> (text: String, next: Int)? {
            // allowApply: false — the "of" after a bound opens the operator's BODY
            // ("sum from i equals 1 to n OF i"), so it must never read as "n(i)".
            guard var current = tryOperand(k, allowApply: false) else { return nil }
            while current.next < items.count,
                  items[current.next].kind == .symbol,
                  let sym = items[current.next].sym,
                  sym.kind == .relation || sym.kind == .operatorSymbol,
                  sym.text == "=" || sym.text == "+" || sym.text == "-",
                  let rhs = tryOperand(current.next + 1) {
                current = (current.text + sym.text + rhs.text, rhs.next)
            }
            return current
        }

        /// Reads ONE operand: a number (with its coefficient variable), a variable, a symbol
        /// value, a bracketed group, a negated/rooted operand, or a function application.
        private func tryOperand(_ k: Int, allowApply: Bool = true) -> (text: String, next: Int)? {
            guard k < items.count else { return nil }
            let it = items[k]

            // The three constructs that build a whole operand by themselves.
            if it.kind == .keyword {
                switch it.key {
                case .the:
                    // "the" belongs to the maths phrase when the phrase is what we're reading.
                    return tryOperand(k + 1)

                case .root:
                    var j = k + 1
                    if j < items.count, items[j].key == .of { j += 1 }
                    if it.weak {
                        // Bare "root of": the radicand takes its power ("the root of K cubed" →
                        // √K³), and only a powered radicand makes it mathematics on its own —
                        // "the root of 3 problems" stays words unless the run is an equation.
                        guard let plain = tryOperand(j), let radicand = tryPoweredOperand(j) else { return nil }
                        if radicand.next > plain.next { activated = true }
                        return (MathScript.radical(Parser.rootSign(it.text), radicand.text), radicand.next)
                    }
                    guard let radicand = tryOperand(j) else { return nil }
                    activated = true
                    return (MathScript.radical(Parser.rootSign(it.text), radicand.text), radicand.next)

                case .abs:
                    guard let inner = tryOperand(k + 1) else { return nil }
                    activated = true
                    return ("|" + inner.text + "|", inner.next)

                case .derivRatio:
                    // "d y by d x" → dy/dx: never ordinary speech, so it activates.
                    activated = true
                    return (it.text, k + 1)

                case .quantity:
                    return quantity(k)

                default:
                    return nil
                }
            }

            switch it.kind {
            case .number:
                var text = it.text
                var next = k + 1
                // "7 n" → "7n" (a coefficient, but never on the weak "a")
                if next < items.count, items[next].kind == .variable,
                   !items[next].weak, next != ctx.weakCutoff {
                    text += items[next].text
                    next += 1
                }
                return (text, next)

            case .variable:
                if it.weak && k == ctx.weakCutoff { return nil }
                var name = it.text
                var next = k + 1
                // "f prime of x" → f′(x), "f inverse of x" → f⁻¹(x): the mark belongs to the
                // function's NAME when "of" follows it.
                var marked = false
                if allowApply, !it.weak, next + 1 < items.count, items[next].kind == .symbol,
                   let mark = items[next].sym, mark.kind == .postfix,
                   Parser.functionMarks.contains(mark.text), items[next + 1].key == .of {
                    name += mark.text
                    next += 1
                    marked = true
                }
                // "f of x" → "f(x)" — and, by rules 4 and 5, "f of n minus 1" → "f(n - 1)",
                // "P of X less than 3" → "P(X < 3)". Only a real (non-weak) variable may be
                // applied like a function: "5 of 10" and "a of the" must stay words. A bare
                // "f of x" never activates on its own — something else in the run has to be
                // mathematics — but a MARKED one does: "f inverse of x" is never English.
                if allowApply, !it.weak, next < items.count, items[next].key == .of,
                   let arg = subExpression(next + 1, it.text == "P" ? .event : .argument) {
                    if marked { activated = true }
                    return ("\(name)(\(arg.text))", arg.next)
                }
                if marked { return (it.text, k + 1) } // no argument after all: the mark is a postfix
                return (name, next)

            case .symbol:
                guard let sym = it.sym else { return nil }
                if sym.kind == .operand {
                    // "sigma of 3" → σ(3): a Greek letter applied with "of", like "f of x". Weak.
                    if allowApply, Parser.isGreekLetter(sym.text), k + 1 < items.count,
                       items[k + 1].key == .of, let arg = subExpression(k + 2, .argument) {
                        return ("\(sym.text)(\(arg.text))", arg.next)
                    }
                    return (sym.text, k + 1)
                }
                if sym.kind == .open { return group(k) }
                if sym.kind == .prefix && !sym.isBigOperator {
                    guard let inner = tryOperand(k + 1) else { return nil }
                    if sym.text == "√" { return (MathScript.radical(sym.text, inner.text), inner.next) }
                    return (sym.text + inner.text, inner.next)
                }
                if sym.kind == .function {
                    var j = k + 1
                    var name = sym.text
                    // "log base 2 of x" — and "log sub 2 of x", which is the same thing said
                    // differently. A named base ACTIVATES: a function with an explicit base
                    // is unambiguously mathematics, so it converts on its own ("log base 2
                    // of 8"), where a bare application stays weak ("the log of the tree").
                    // allowApply: false — the "of" after the base opens the ARGUMENT
                    // ("log base n OF x"), so the base must never read as "n(x)".
                    if j < items.count, items[j].key == .base || items[j].key == .sub,
                       let base = tryOperand(j + 1, allowApply: false) {
                        name = MathScript.attach(name, base.text, superscript: false)
                        j = base.next
                        activated = true
                    }
                    // "sine squared theta" → "sin²θ" — the power belongs to the name, and a
                    // powered function is never English, so it activates.
                    var powered = false
                    if j < items.count, items[j].kind == .keyword {
                        if items[j].key == .pow2 || items[j].key == .pow3 {
                            name = MathScript.attach(name, items[j].key == .pow2 ? "2" : "3", superscript: true)
                            j += 1
                            powered = true
                        } else if items[j].key == .power, let power = tryScriptOperand(j + 1) {
                            name = MathScript.attach(name, power.text, superscript: true)
                            j = power.next
                            powered = true
                        }
                    }
                    if j < items.count, items[j].key == .of { j += 1 }
                    // Rules 4 and 5: "the variance of X plus Y" → "Var(X + Y)", "the
                    // probability of A given B" → "P(A ∣ B)".
                    if let scope = Parser.argumentScopes[sym.text] {
                        guard let arg = subExpression(j, scope) else { return nil }
                        return ("\(name)(\(arg.text))", arg.next)
                    }
                    // One operand with its implicit product ("cosine 2 theta" → cos 2θ) — the
                    // SMALLEST reading (spec §6.1): "sine of x plus 1" is sin x + 1; say "sine
                    // of the quantity x plus 1" for sin(x + 1).
                    guard let arg = tryScriptOperand(j) else { return nil }
                    // "the natural log of 2" → ln 2 on its own: "natural log" is never English.
                    if powered || sym.text == "ln" { activated = true }
                    return (MathScript.applyFunction(name, arg.text), arg.next)
                }
                return nil

            default:
                return nil
            }
        }

        /// A bracketed group. An unclosed one (the speaker forgot "close paren") is closed
        /// at the end of the run rather than abandoning the whole construct — or, like an
        /// event, before its second relation ("the probability that X is at most 3 equals
        /// 0.65" → "P(X ≤ 3) = 0.65").
        private func group(_ k: Int) -> (text: String, next: Int)? {
            guard let open = items[k].sym?.text else { return nil }
            var depth = 0
            var end = -1
            for j in k..<items.count {
                guard items[j].kind == .symbol, let sym = items[j].sym else { continue }
                if sym.kind == .open {
                    depth += 1
                } else if sym.kind == .close {
                    depth -= 1
                    if depth == 0 { end = j; break }
                }
            }

            // An unclosed bracket also ends where "all over" takes the whole side (rule 6).
            var innerEnd = end < 0 ? items.count : end
            if end < 0, let allOver = (k + 1..<items.count).first(where: { items[$0].key == .allOver }) {
                innerEnd = allOver
            }
            let close = end < 0 ? Parser.closing(open) : (items[end].sym?.text ?? Parser.closing(open))
            guard innerEnd > k + 1 else { return nil }

            let inside = Run(items: Array(items[(k + 1)..<innerEnd]), weakCutoff: -1,
                             cleanEnd: end < 0 ? ctx.cleanEnd : true)
            let inner = Parser(inside, limitsRelations: end < 0)
            let (body, innerActivated, used) = inner.run(0)
            guard used > 0 else { return nil }
            activated = activated || innerActivated

            return (open + body + close, end < 0 ? k + 1 + used : end + 1)
        }

        /// "the quantity …" (rule 6): a spoken open bracket. It closes at a close bracket, else
        /// just before the next relation or "all over", else at the end of the run — and it is
        /// only a group when what it holds is more than one term, so "the quantity x equals 5"
        /// is left as words.
        private func quantity(_ k: Int) -> (text: String, next: Int)? {
            var depth = 0
            var end = items.count
            var closed = false
            var j = k + 1
            scan: while j < items.count {
                let item = items[j]
                if item.kind == .symbol, let sym = item.sym {
                    switch sym.kind {
                    case .open:
                        depth += 1
                    case .close:
                        if depth == 0 { end = j; closed = true; break scan }
                        depth -= 1
                    case .relation:
                        if depth == 0 { end = j; break scan }
                    default:
                        break
                    }
                } else if depth == 0, item.key == .allOver {
                    end = j
                    break
                }
                j += 1
            }
            guard end > k + 1 else { return nil }

            let inside = Run(items: Array(items[(k + 1)..<end]), weakCutoff: -1,
                             cleanEnd: end == items.count ? ctx.cleanEnd : true)
            let (body, innerActivated, used) = Parser(inside).run(0)
            guard used > 0, !closed || used == end - k - 1 else { return nil }
            let next = closed ? end + 1 : k + 1 + used
            activated = activated || innerActivated
            if MathScript.needsGrouping(body, leadingSign: false) { return ("(" + body + ")", next) }
            // One term built from several spoken pieces ("the quantity 5 over 6 to the 4" →
            // (5/6)⁴) needs no extra brackets; a lone word after it is no group at all.
            guard used > 1 else { return nil }
            return (body, next)
        }

        private static func closing(_ open: String) -> String {
            switch open {
            case "[": return "]"
            case "{": return "}"
            default: return ")"
            }
        }
    }
}
