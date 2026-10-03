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
/// Two extra rules close the gaps that the operand requirement alone leaves open:
///   • "a"/"A" are only WEAK operands, and a weak operand is refused when it is the last
///     thing before an ordinary word — which is exactly what makes "two times a day" safe
///     while "a subscript n equals 1 plus 7n" and "a plus b" still work.
///   • "I" is never a variable, and "sum"/"product" only count as ∑/∏ when bounds follow,
///     so "the sum of my fears" and "an integral part of the plan" never activate.
///
/// When nothing activates, `convert` returns the input string unchanged — not re-joined —
/// so the feature is provably invisible outside mathematics.
///
/// ── Escape hatch ───────────────────────────────────────────────────────────────────────
/// Saying "start equation … end equation" forces every run between the markers to convert
/// (and drops the markers), for the rare symbol that is too ordinary a word to auto-activate.
///
/// The vocabulary lives in `MathSymbols`, number words in `SpokenNumbers`, and Unicode
/// script rendering in `MathScript`. This file owns the grammar and the activation rules.
///
/// Ported 1:1 from the Windows port's `JVoice.Core/Math/MathSpeech.cs`.
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

    private struct Item {
        let kind: ItemKind
        let text: String
        let start: Int
        let count: Int
        var sym: MathSymbol?
        var key: Kw = .none
        var weak = false

        init(_ kind: ItemKind, _ text: String, _ start: Int, _ count: Int,
             sym: MathSymbol? = nil, key: Kw = .none, weak: Bool = false) {
            self.kind = kind
            self.text = text
            self.start = start
            self.count = count
            self.sym = sym
            self.key = key
            self.weak = weak
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
        // alpha version" and "go to the store" can never take it.
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
                items.append(Item(.keyword, keyword.payload, i, keyword.consumed, key: keyword.key))
                i += keyword.consumed
                continue
            }
            if let symbol {
                items.append(Item(.symbol, symbol.symbol.text, i, symbol.consumed, sym: symbol.symbol))
                i += symbol.consumed
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

            var pos = 0
            while pos < buf.count {
                let parser = Parser(items: buf, weakCutoff: weakCutoff)
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
        private var parts: [(text: String, operand: Bool, tight: Bool)] = []
        private var tightNext = false

        var lastIsOperand: Bool { parts.last?.operand ?? false }
        var lastText: String { parts[parts.count - 1].text }

        func pushOperand(_ text: String) {
            // "u n" is a sequence term, not a product (David, 2026-08-30).
            if let last = parts.last, last.operand, Expr.indexes(last.text, text) {
                replaceLast(MathScript.attach(last.text, text, superscript: false))
                tightNext = false
                return
            }

            let tight = tightNext || (parts.last.map { $0.operand && Expr.juxtaposes($0.text, text) } ?? false)
            parts.append((text, true, tight))
            tightNext = false
        }

        /// A big operator or a "lim" head: the body that follows is separated by a space.
        func pushHead(_ text: String) {
            parts.append((text, false, tightNext))
            tightNext = false
        }

        func pushInfix(_ text: String) {
            parts.append((text, false, false))
            tightNext = false
        }

        /// Unused — as in the C# original, which builds a bracketed group as one whole
        /// operand string instead. Kept so the two files stay diffable.
        func pushOpen(_ text: String) {
            parts.append((text, false, tightNext))
            tightNext = true
        }

        func attachToLast(_ suffix: String) { replaceLast(parts[parts.count - 1].text + suffix) }

        func replaceLast(_ text: String) {
            parts[parts.count - 1] = (text, true, parts[parts.count - 1].tight)
        }

        func render() -> String {
            var out = ""
            for (index, part) in parts.enumerated() {
                if index > 0 && !part.tight { out += " " }
                out += part.text
            }
            return out
        }

        /// Two ATOMIC operands side by side are implicit multiplication and are written
        /// closed up: "7 n" → "7n", "2 π" → "2π", "delta x" → "δx". Anything already
        /// composite ("aₙ", "sin(x)", "1/2") keeps its space, where the product is clearer
        /// spaced out.
        static func juxtaposes(_ left: String, _ right: String) -> Bool {
            isSingleLetter(right) && (isSingleLetter(left) || isPlainNumber(left))
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

        private static func isPlainNumber(_ s: String) -> Bool {
            !s.isEmpty && s.allSatisfy { $0.isAsciiDigit || $0 == "." }
        }
    }

    // ─────────────────────────────── parsing ───────────────────────────────

    /// Walks one run left to right, folding items into an `Expr`. Stops at the first item it
    /// cannot consume and reports how far it got, so the caller can hand the leftovers back
    /// out as plain words.
    private final class Parser {
        private let items: [Item]
        private let weakCutoff: Int
        private var activated = false

        init(items: [Item], weakCutoff: Int) {
            self.items = items
            self.weakCutoff = weakCutoff
        }

        func run(_ start: Int) -> (text: String, activated: Bool, used: Int) {
            let expr = Expr()
            var i = start
            while i < items.count, step(expr, &i) {}
            return (expr.render(), activated, i - start)
        }

        private func step(_ expr: Expr, _ i: inout Int) -> Bool {
            let it = items[i]

            if it.kind == .keyword { return keyword(expr, &i) }

            if it.kind == .symbol, let sym = it.sym {
                if sym.kind == .relation || sym.kind == .operatorSymbol {
                    guard expr.lastIsOperand else { return false }
                    guard let rhs = tryOperand(i + 1) else { return false }
                    expr.pushInfix(sym.text)
                    expr.pushOperand(rhs.text)
                    activated = true
                    i = rhs.next
                    return true
                }
                if sym.kind == .postfix {
                    guard expr.lastIsOperand else { return false }
                    expr.attachToLast(sym.text)
                    i += 1
                    return true
                }
                // A close bracket is normally swallowed by group(); a stray one is
                // unbalanced speech, so leave it (and everything after) as plain words.
                if sym.kind == .close { return false }
                if sym.isBigOperator { return bigOperator(expr, &i) }
            }

            if let operand = tryOperand(i) {
                expr.pushOperand(operand.text)
                if it.kind == .symbol, it.sym?.activates == true { activated = true }
                i = operand.next
                return true
            }
            return false
        }

        private func keyword(_ expr: Expr, _ i: inout Int) -> Bool {
            let it = items[i]
            switch it.key {
            case .sub, .sup, .power:
                guard expr.lastIsOperand else { return false }
                guard let script = tryScriptOperand(i + 1) else { return false }
                expr.replaceLast(MathScript.attach(expr.lastText, script.text, superscript: it.key != .sub))
                activated = true
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
                // ("1 over n squared" → "1 ÷ n²"). Never a bare slash.
                //
                // The denominator takes a trailing power with it, which is also the correct
                // reading: "one over n squared" is 1/(n²), not (1/n)².
                guard expr.lastIsOperand else { return false }
                guard let denominator = tryPoweredOperand(i + 1) else { return false }
                if let stacked = MathScript.fraction(expr.lastText, denominator.text) {
                    expr.replaceLast(stacked)
                } else {
                    expr.pushInfix("÷")
                    expr.pushOperand(denominator.text)
                }
                activated = true
                i = denominator.next
                return true

            case .choose:
                guard expr.lastIsOperand else { return false }
                guard let k = tryOperand(i + 1) else { return false }
                expr.replaceLast("C(\(expr.lastText), \(k.text))")
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
        /// subscript, a denominator.
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
                   !items[next].weak, next != weakCutoff {
                    text += items[next].text
                    next += 1
                }
                return (text, next)

            case .variable:
                if it.weak && k == weakCutoff { return nil }
                var text = it.text
                var next = k + 1
                // "f of x" → "f(x)". Only a real (non-weak) variable may be applied like a
                // function: "5 of 10" and "a of the" must stay words. Never activating on
                // its own — something else in the run has to be mathematics.
                if allowApply, !it.weak, next < items.count, items[next].key == .of,
                   let arg = tryOperand(next + 1) {
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
                    guard let arg = tryOperand(j) else { return nil }
                    return ("\(name)(\(arg.text))", arg.next)
                }
                return nil

            default:
                return nil
            }
        }

        /// A bracketed group. An unclosed one (the speaker forgot "close paren") is closed
        /// at the end of the run rather than abandoning the whole construct.
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

            let inner = Parser(items: Array(items[(k + 1)..<innerEnd]), weakCutoff: -1)
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
