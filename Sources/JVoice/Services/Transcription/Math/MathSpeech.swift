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
        let emitter = Emitter(toks: toks, forced: forced)

        var buf: [Item] = []
        for it in items {
            if it.kind == .word || spansPunctuation(toks, it) {
                emitter.flush(&buf, brokenByWord: true)
                emitter.verbatim(it.start, it.start + it.count)
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

        init(_ kind: ItemKind, _ text: String, _ start: Int, _ count: Int,
             sym: MathSymbol? = nil, key: Kw = .none, weak: Bool = false, ordinal: Ordinal = .none) {
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
        "cube root": (.root, "3"),
        "over": (.over, ""),
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
        "tends to": (.approaches, ""),
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

            // 2) "sum"/"product" — only a big operator when bounds follow
            if let bigOp = boundedOnly[core.lowercased()], i + 1 < cores.count,
               cores[i + 1].caseInsensitiveCompare("from") == .orderedSame {
                items.append(Item(.symbol, bigOp, i, 1, sym: MathSymbol(bigOp, .prefix)))
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
            if let number = SpokenNumbers.tryRead(cores, i) {
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
                items.append(Item(.keyword, keyword.payload, i, keyword.consumed, key: keyword.key,
                                  weak: bareToThe))
                i += keyword.consumed
                continue
            }
            if let symbol {
                items.append(Item(.symbol, symbol.symbol.text, i, symbol.consumed, sym: symbol.symbol))
                i += symbol.consumed
                continue
            }

            // 4b) "3 x 4": whisper writes a spoken "times" as the letter x. Between two numbers
            //     it is the multiplication dot — and WEAK, so "a 2 x 4 board" and "my monitor
            //     is 1920 x 1080" stay words unless something else makes the run mathematics
            //     ("26 x 26 x 26 equals 17,576").
            if core == "x" || core == "X", let last = items.last, last.kind == .number,
               SpokenNumbers.tryRead(cores, i + 1) != nil {
                items.append(Item(.symbol, "·", i, 1, sym: MathSymbol("·", .operatorSymbol), weak: true))
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

            items.append(Item(.word, core, i, 1))
            i += 1
        }
        return items
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

        init(toks: [Tok], forced: [Bool]) {
            self.toks = toks
            self.forced = forced
        }

        func result() -> String { parts.joined(separator: " ") }

        func verbatim(_ fromTok: Int, _ toTok: Int) {
            for t in fromTok..<toTok { parts.append(toks[t].raw) }
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
            var pos = 0
            while pos < buf.count {
                let parser = Parser(run)
                let (text, activated, used) = parser.run(pos)
                if used == 0 {
                    verbatim(buf[pos].start, buf[pos].start + buf[pos].count)
                    pos += 1
                    continue
                }

                let fromTok = buf[pos].start
                let toTok = buf[pos + used - 1].start + buf[pos + used - 1].count
                if (activated || anyForced) && !text.isEmpty {
                    parts.append(toks[fromTok].lead + text + toks[toTok - 1].trail)
                    changed = true
                } else {
                    verbatim(fromTok, toTok)
                }

                pos += used
            }
            buf.removeAll()
        }
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
            let tight: Bool
            var made: Made = .plain
        }

        private var parts: [Part] = []
        private var tightNext = false

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
            parts.append(Part(text: text, role: .operand, tight: tight))
            tightNext = false
        }

        /// A big operator or a "lim" head: the body that follows is separated by a space.
        func pushHead(_ text: String) {
            parts.append(Part(text: text, role: .head, tight: tightNext))
            tightNext = false
        }

        func pushInfix(_ text: String) {
            parts.append(Part(text: text, role: .infix, tight: false))
            tightNext = false
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

        func render(from start: Int) -> String {
            var out = ""
            for index in start..<parts.count {
                if index > start && !parts[index].tight { out += " " }
                out += parts[index].text
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
            isSingleLetter(right) && (isSingleLetter(left) || isPlainNumber(left))
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
            canCarryIndex(left) && isIndex(right)
        }

        private static func canCarryIndex(_ s: String) -> Bool {
            guard let last = s.last, last.isLetter else { return false }
            return isInteger(String(s.dropLast()))
        }

        private static func isIndex(_ s: String) -> Bool {
            if !s.isEmpty && isInteger(s) { return true }
            guard isSingleLetter(s), let first = s.first else { return false }
            return indexLetters.contains(Character(first.lowercased()))
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
        static let products: Set<String> = ["·"]
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
            return (expr.render(), activated, i - start)
        }

        private func step(_ expr: Expr, _ i: inout Int) -> Bool {
            let it = items[i]

            if it.kind == .keyword { return allows(it.key) && keyword(expr, &i) }

            if it.kind == .symbol, let sym = it.sym {
                if sym.kind == .relation || sym.kind == .operatorSymbol {
                    guard reaches(sym, i, expr), expr.lastIsOperand else { return false }
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

                    expr.pushInfix(sym.text)
                    expr.pushOperand(rhs.text)
                    if sym.activates && !it.weak && !articlePair { activated = true }
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
                   !(scope == .product && Expr.continuesImplicitly(expr.lastText, operand.text)) {
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
                guard let script = tryScriptOperand(i + 1) else { return false }
                expr.replaceLast(MathScript.attach(expr.lastText, script.text, superscript: it.key != .sub))
                if !it.weak || powerIsUnmistakable(i, script.next) { activated = true }
                i = script.next
                return true

            case .pow2, .pow3:
                guard expr.lastIsOperand else { return false }
                expr.replaceLast(MathScript.attach(expr.lastText, it.key == .pow2 ? "2" : "3", superscript: true))
                activated = true
                i += 1
                return true

            case .root, .abs:
                // Both build a self-contained operand, so tryOperand owns the one
                // implementation and they also work in operand position ("x equals the
                // square root of 2", "from 0 to the square root of 2").
                guard let built = tryOperand(i) else { return false }
                expr.pushOperand(built.text)
                activated = true
                i = built.next
                return true

            case .over:
                // A division is written the way it is written on paper (David, 2026-08-30):
                // stacked when the two sides are small enough to stack ("1 over 2" → "½",
                // "22 over 7" → "²²⁄₇"), and with the division SIGN when they are not
                // ("1 over n squared" → "1 ÷ n²"). Never a bare slash. How far each side
                // reaches is rule 3 of the grouping rule.
                guard expr.lastIsOperand else { return false }
                if scope == .event && startsApplication(i + 1) { return false }
                let top = expr.tailStart(joinedBy: Parser.products, wall: .quotient)
                let topIsProduct = expr.isCompound(from: top)
                guard let bottom = subExpression(i + 1, .product, joinsProducts: topIsProduct) else {
                    return false
                }
                if bottom.compound {
                    // A product over a product.
                    let numerator = expr.render(from: top)
                    let shown = topIsProduct ? "(\(numerator))" : numerator
                    expr.collapse(from: top, into: "\(shown) ÷ (\(bottom.text))", made: .quotient)
                } else if !expr.lastIsDivisor,
                          let stacked = MathScript.fraction(expr.lastText, bottom.text) {
                    // The factor beside "over" by the one after it, stacked.
                    expr.collapse(from: expr.count - 1, into: stacked, made: .quotient)
                } else {
                    // …or with the sign — always after a "÷", since "a over b over 2" is
                    // a ÷ b ÷ 2, never a ÷ ᵇ⁄₂.
                    expr.pushInfix("÷")
                    expr.pushOperand(bottom.text)
                    expr.markLast(.quotient)
                }
                activated = true
                i = bottom.next
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
                guard variable.next < items.count, items[variable.next].key == .approaches else { return false }
                guard let target = tryOperand(variable.next + 1) else { return false }
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
            let exponent = items[i + 1]
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
            activated = true
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
                    guard let radicand = tryOperand(j) else { return nil }
                    activated = true
                    return (Parser.rootSign(it.text) + radicand.text, radicand.next)

                case .abs:
                    guard let inner = tryOperand(k + 1) else { return nil }
                    activated = true
                    return ("|" + inner.text + "|", inner.next)

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
                var text = it.text
                var next = k + 1
                // "f of x" → "f(x)" — and, by rules 4 and 5, "f of n minus 1" → "f(n - 1)",
                // "P of X less than 3" → "P(X < 3)". Only a real (non-weak) variable may be
                // applied like a function: "5 of 10" and "a of the" must stay words. Never
                // activating on its own — something else in the run has to be mathematics.
                if allowApply, !it.weak, next < items.count, items[next].key == .of,
                   let arg = subExpression(next + 1, it.text == "P" ? .event : .argument) {
                    text = "\(it.text)(\(arg.text))"
                    next = arg.next
                }
                return (text, next)

            case .symbol:
                guard let sym = it.sym else { return nil }
                if sym.kind == .operand {
                    return (sym.text, k + 1)
                }
                if sym.kind == .open { return group(k) }
                if sym.kind == .prefix && !sym.isBigOperator {
                    guard let inner = tryOperand(k + 1) else { return nil }
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
                    // "sine squared theta" → "sin²θ" — the power belongs to the name.
                    if j < items.count, items[j].kind == .keyword {
                        if items[j].key == .pow2 || items[j].key == .pow3 {
                            name = MathScript.attach(name, items[j].key == .pow2 ? "2" : "3", superscript: true)
                            j += 1
                        } else if items[j].key == .power, let power = tryScriptOperand(j + 1) {
                            name = MathScript.attach(name, power.text, superscript: true)
                            j = power.next
                        }
                    }
                    if j < items.count, items[j].key == .of { j += 1 }
                    // Rules 4 and 5: "the variance of X plus Y" → "Var(X + Y)", "the
                    // probability of A given B" → "P(A ∣ B)".
                    if let scope = Parser.argumentScopes[sym.text] {
                        guard let arg = subExpression(j, scope) else { return nil }
                        return ("\(name)(\(arg.text))", arg.next)
                    }
                    guard let arg = tryOperand(j) else { return nil }
                    return ("\(name)(\(arg.text))", arg.next)
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

            let innerEnd = end < 0 ? items.count : end
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

        private static func closing(_ open: String) -> String {
            switch open {
            case "[": return "]"
            case "{": return "}"
            default: return ")"
            }
        }
    }
}
