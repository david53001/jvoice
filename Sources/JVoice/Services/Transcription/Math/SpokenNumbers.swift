import Foundation

/// Spoken number words → digits ("twenty five" → "25", "three point one four" → "3.14").
///
/// Used ONLY inside a run that `MathSpeech` has already recognised as mathematics, so it
/// can be greedy: turning "one" into "1" is right in "x = one half" and would be wrong in
/// "one of my friends", and the run rules — not this parser — are what tell the two apart.
///
/// Every entry point is a "try-read at this index" so the caller stays in control of the
/// token stream: they return the digits plus how many words were consumed, or nil.
///
/// ── The one hard rule: never over-consume ──────────────────────────────────────────────
/// `consumed` is how many of the CALLER's words disappear into the number, so a word is
/// taken only when the grammar says it belongs to it. Everything ambiguous is settled by
/// lookahead rather than greed:
///   • "and" is the number's own connective only after a magnitude AND before a tail that
///     finishes it — "one hundred and five" is 105, "five and my friend" stops at "five",
///     and "one hundred and two hundred" stops at "one hundred" (the tail starts a NEW
///     number, so that "and" was ordinary English).
///   • "point" is a decimal point only when spoken digits follow it, so "at some point five
///     people left" can never become a decimal.
///   • "a" is an implicit one only immediately before a magnitude ("a hundred", "a
///     thousand"), never on its own. `MathSpeech` treats a bare "a" as a WEAK variable, and
///     that is exactly what keeps "two times a day" out of mathematics — swallowing the
///     article here would break it.
///   • A hyphenated token is all-or-nothing: whisper writes "twenty-five" as readily as
///     "twenty five" (25), while "five-year" is not a number at all.
///
/// A continuation that is not well-formed ENDS the number instead of being guessed at:
/// "nineteen eighty four" reads as 19 followed by 84, not the year 1984.
///
/// Output is always plain digits: no thousands separators, and commas whisper already
/// wrote are stripped ("1,000" → "1000").
///
/// Ported 1:1 from the Windows port's `JVoice.Core/Math/SpokenNumbers.cs`.
public enum SpokenNumbers {
    public typealias Reading = (digits: String, consumed: Int)

    private static let units: [String: Int] = [
        "zero": 0, "nought": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Magnitudes that CLOSE the group they multiply: "three thousand four" starts a fresh
    /// group at "four". "hundred" is deliberately not one of them — it scales the group in
    /// place, so "three hundred and five" keeps building on 300.
    private static let scales: [String: Int64] = [
        "thousand": 1_000,
        "million": 1_000_000,
        "billion": 1_000_000_000,
        "trillion": 1_000_000_000_000,
    ]

    private static let hundred = "hundred"

    /// True when the word is already numeric as transcribed ("7", "3.14", "1,000").
    public static func isDigits(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        var sawDigit = false
        for character in word {
            if character.isAsciiDigit { sawDigit = true; continue }
            if character == "." || character == "," { continue }
            return false
        }
        return sawDigit
    }

    /// Reads a cardinal number (or an already-numeric token) starting at `index`.
    /// Returns the digits and how many words were consumed.
    public static func tryRead(_ words: [String], _ index: Int) -> Reading? {
        guard index >= 0, index < words.count else { return nil }

        var text: String
        var consumed: Int
        let fromDigits = isDigits(words[index])

        if fromDigits {
            text = words[index].replacingOccurrences(of: ",", with: "")
            consumed = 1
        } else {
            let (state, read) = readCardinal(words, index)
            guard read > 0 else { return nil }
            text = String(state.value)
            consumed = read
        }

        // "three point one four" → "3.14". A token whisper already wrote with a decimal
        // point ("3.14") is finished as it stands.
        var hasFraction = false
        if !text.contains("."), let decimals = tryReadDecimals(words, index + consumed) {
            text += "." + decimals.digits
            consumed += decimals.consumed
            hasFraction = true
        }

        // "two point five million" / "3 million" — a trailing magnitude the cardinal loop
        // cannot already have eaten, because a decimal or a digit token ended it.
        let after = index + consumed
        if hasFraction || fromDigits, after < words.count,
           let scale = scales[words[after].lowercased()],
           let scaled = tryScale(text, scale) {
            text = scaled
            consumed += 1
        }

        return (text, consumed)
    }

    /// Ordinal names, plus the two magnitudes an "<ordinal> root" could plausibly use.
    /// "second" is here as the number 2 — the time unit is a different sense, and the only
    /// caller today asks for an ordinal explicitly (it must be followed by "root").
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40,
        "fiftieth": 50, "sixtieth": 60, "seventieth": 70, "eightieth": 80,
        "ninetieth": 90, "hundredth": 100, "thousandth": 1_000,
    ]

    /// Reads an ordinal ("fourth" → "4", "twenty first" → "21", "4th" → "4", "nth" → "n"),
    /// used for "<ordinal> root of x". It returns the DEGREE, which is why "nth" comes back
    /// as the letter it is spoken as: ⁿ√x.
    public static func tryReadOrdinal(_ words: [String], _ index: Int) -> Reading? {
        guard index >= 0, index < words.count else { return nil }

        // "twenty-first" / "n-th" — one token, so the whole compound costs one word.
        if let parts = splitHyphen(words[index]) {
            guard let hyphenated = readOrdinal(parts, 0) else { return nil }
            return (hyphenated.digits, 1)
        }

        return readOrdinal(words, index)
    }

    /// Denominator names, for `tryReadFraction`. "second(s)" is left out on purpose —
    /// "two seconds" is a duration far more often than a half.
    private static let denominators: [String: Int] = [
        "half": 2, "halves": 2, "quarter": 4, "quarters": 4,
        "third": 3, "thirds": 3, "fourth": 4, "fourths": 4,
        "fifth": 5, "fifths": 5, "sixth": 6, "sixths": 6,
        "seventh": 7, "sevenths": 7, "eighth": 8, "eighths": 8,
        "ninth": 9, "ninths": 9, "tenth": 10, "tenths": 10,
        "hundredth": 100, "hundredths": 100, "thousandth": 1_000, "thousandths": 1_000,
    ]

    /// Reads a spoken fraction ("three quarters" → "¾", "two-thirds" → "⅔").
    ///
    /// The result is ONE operand, and a weak one: `MathSpeech` lexes it as a number, so
    /// "one half of the team" stays English and only a run that something else activated
    /// ever shows "½".
    public static func tryReadFraction(_ words: [String], _ index: Int) -> Reading? {
        guard index >= 0, index < words.count else { return nil }

        if let parts = splitHyphen(words[index]) {
            guard let hyphenated = readFraction(parts, 0) else { return nil }
            return (hyphenated.digits, 1)
        }

        return readFraction(words, index)
    }

    // ─────────────────────────────── cardinals ───────────────────────────────

    /// Runs the cardinal grammar from `index` and reports how many words it legitimately
    /// consumed (0 = the words there are not a number).
    private static func readCardinal(_ words: [String], _ index: Int) -> (state: Cardinal, consumed: Int) {
        var state = Cardinal()
        var consumed = 0

        while index + consumed < words.count {
            var word = words[index + consumed]

            if word.caseInsensitiveCompare("and") == .orderedSame {
                if !state.wantsConnective || !continues(words, index + consumed + 1, state) { break }
                consumed += 1
                continue
            }

            // "a hundred" — "a" is an implicit one, but only as the first word and only
            // when a magnitude follows it (see the type doc for why a bare "a" is left).
            if consumed == 0, word.caseInsensitiveCompare("a") == .orderedSame,
               index + 1 < words.count, isMagnitude(words[index + 1]) {
                word = "one"
            }

            var trial = state
            if !trial.feed(word) { break }
            state = trial
            consumed += 1
        }

        return (state, consumed)
    }

    /// True when the words after an "and" FINISH the current number rather than starting a
    /// new one. The tail is fed to a copy of the live state, so the grammar itself decides:
    /// in "one hundred and two hundred" the copy chokes on the second "hundred", and a
    /// magnitude sitting right where the tail stopped is the tell that the "and" was
    /// joining two numbers.
    private static func continues(_ words: [String], _ index: Int, _ state: Cardinal) -> Bool {
        var state = state
        var length = 0
        while index + length < words.count {
            var trial = state
            if !trial.feed(words[index + length]) { break }
            state = trial
            length += 1
        }

        if length == 0 { return false }
        let next = index + length
        return next >= words.count || !isMagnitude(words[next])
    }

    private static func isMagnitude(_ word: String) -> Bool {
        let lower = word.lowercased()
        return lower == hundred || scales[lower] != nil
    }

    /// The cardinal grammar, as a tiny state machine. Copy semantics are the point: a
    /// caller feeds a COPY and keeps it only when the word was accepted, so a word the
    /// grammar rejects is never half-applied to the number it ended.
    private struct Cardinal {
        private var total: Int64 = 0        // groups already closed by a magnitude
        private var group: Int64 = 0        // the group being built, below 1000
        private var lastScale: Int64 = 0    // 0 = none yet; magnitudes must strictly descend
        private var started = false         // at least one word has been accepted
        private var pendingUnit = false     // a units/teens value is in the group
        private var pendingTens = false     // a tens value is in the group — only 1..9 may follow
        private var usedHundred = false

        var value: Int64 { total + group }

        /// True once the number is big enough for the spoken "and" ("one hundred and five",
        /// "two thousand and five"). Below a hundred there is no such connective, which is
        /// what makes "seven and made coffee" stop at "seven".
        var wantsConnective: Bool { usedHundred || total > 0 }

        /// Accepts one spoken word. A hyphen-joined compound counts as ONE word and is
        /// all-or-nothing, so "twenty-five" is 25 while "five-year" is not a number.
        mutating func feed(_ word: String) -> Bool {
            guard word.contains("-") else { return feedPart(word) }

            let parts = word.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
            if parts.isEmpty { return false }

            var trial = self
            for part in parts {
                if !trial.feedPart(part) { return false }
            }
            self = trial
            return true
        }

        private mutating func feedPart(_ part: String) -> Bool {
            let lower = part.lowercased()

            if let unit = units[lower] {
                if pendingUnit { return false }                          // "five six" is two numbers
                if pendingTens && (unit < 1 || unit > 9) { return false } // "twenty fifteen" likewise
                group += Int64(unit)
                pendingUnit = true
                pendingTens = false
                return accept()
            }

            if let tensValue = tens[lower] {
                if pendingUnit || pendingTens { return false }           // "nineteen eighty" is two
                group += Int64(tensValue)
                pendingTens = true
                return accept()
            }

            if lower == hundred {
                if usedHundred { return false }                          // "one hundred two hundred"
                group = (group == 0 ? 1 : group) * 100                   // bare/"a" hundred → 100
                usedHundred = true
                pendingUnit = false
                pendingTens = false
                return accept()
            }

            if let scale = scales[lower] {
                if lastScale != 0 && scale >= lastScale { return false }     // "two thousand million"
                let multiplier = group != 0 ? group : (started ? 0 : 1)      // bare "thousand" → 1000
                if multiplier == 0 { return false }                          // two magnitudes in a row
                total += multiplier * scale
                group = 0
                lastScale = scale
                pendingUnit = false
                pendingTens = false
                usedHundred = false
                return accept()
            }

            return false
        }

        private mutating func accept() -> Bool {
            started = true
            return true
        }
    }

    // ─────────────────────────────── decimals ───────────────────────────────

    /// "point one four" → "14". The digits after a decimal point are spoken ONE AT A TIME,
    /// so "three point fourteen" is deliberately not a decimal — that number ends at
    /// "three". Returns nil when "point" is not followed by digits at all, which is what
    /// keeps the ordinary word out of the parser ("at some point five people left").
    private static func tryReadDecimals(_ words: [String], _ index: Int) -> Reading? {
        guard index < words.count, words[index].caseInsensitiveCompare("point") == .orderedSame else {
            return nil
        }

        var out = ""
        var k = index + 1
        while k < words.count, let digit = tryDigit(words[k]) {
            out += digit
            k += 1
        }
        guard !out.isEmpty else { return nil }

        return (out, k - index)
    }

    /// One spoken decimal digit — a units word 0..9, or a bare digit token whisper wrote
    /// numerically ("three point 1 4").
    private static func tryDigit(_ word: String) -> String? {
        if let unit = units[word.lowercased()], unit <= 9 { return String(unit) }
        if !word.isEmpty, word.allSatisfy({ $0.isAsciiDigit }) { return word }
        return nil
    }

    /// "2.5" × million → "2500000", with the trailing zeros a decimal would keep trimmed
    /// off. Refuses (rather than trapping) on a mantissa too big to scale — whisper can
    /// write an arbitrarily long digit token, and losing the magnitude beats losing the
    /// number.
    private static func tryScale(_ mantissa: String, _ scale: Int64) -> String? {
        guard let value = Decimal(string: mantissa, locale: posix) else { return nil }
        let scaleValue = Decimal(scale)
        guard scaleValue > 0, value <= Decimal.greatestFiniteMagnitude / scaleValue else { return nil }

        var product = value * scaleValue
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 28, .plain)
        return "\(rounded)"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    // ─────────────────────────── ordinals & fractions ───────────────────────────

    private static func readOrdinal(_ words: [String], _ index: Int) -> Reading? {
        let word = words[index]

        // "nth root" is spoken as a letter and reads back as one (ⁿ√x); "kth" works the
        // same way. No ordinary English word is a single letter followed by "th".
        if word.count == 3, word.first!.isAsciiLetter,
           String(word.dropFirst()).caseInsensitiveCompare("th") == .orderedSame {
            return (String(word.prefix(1)), 1)
        }

        // "21st", "4th" — whisper writes ordinals numerically as often as it spells them.
        // The suffix is not checked against the number: "2th" happens, and rejecting it
        // would only lose an ordinal that was clearly meant.
        if word.count > 2 {
            let stem = String(word.dropLast(2))
            let suffix = String(word.suffix(2))
            if stem.allSatisfy({ $0.isAsciiDigit }), isOrdinalSuffix(suffix) {
                return (stem, 1)
            }
        }

        // "twenty first" — a tens word plus a unit ordinal.
        if let tensValue = tens[word.lowercased()], index + 1 < words.count,
           let unit = ordinals[words[index + 1].lowercased()], unit >= 1, unit <= 9 {
            return (String(tensValue + unit), 2)
        }

        guard let value = ordinals[word.lowercased()] else { return nil }
        return (String(value), 1)
    }

    private static func isOrdinalSuffix(_ suffix: String) -> Bool {
        ["st", "nd", "rd", "th"].contains(suffix.lowercased())
    }

    private static func readFraction(_ words: [String], _ index: Int) -> Reading? {
        guard let numerator = tryRead(words, index), !numerator.digits.contains(".") else { return nil }

        let k = index + numerator.consumed
        guard k < words.count, let denominator = denominators[words[k].lowercased()] else { return nil }

        // Stacked, like any other dictated fraction ("three quarters" → "¾", "five
        // sevenths" → "⁵⁄₇"). Both sides are plain integers here, so MathScript always has
        // a form.
        let stacked = MathScript.fraction(numerator.digits, String(denominator))
            ?? "\(numerator.digits)/\(denominator)"
        return (stacked, numerator.consumed + 1)
    }

    /// The two halves of a hyphenated token ("twenty-first"), or nil when there is no
    /// hyphen to split on. "n-th" is just "nth" written with a hyphen, so it is rejoined.
    private static func splitHyphen(_ word: String) -> [String]? {
        guard let dash = word.firstIndex(of: "-") else { return nil }
        let dashOffset = word.distance(from: word.startIndex, to: dash)
        guard dashOffset > 0, dashOffset < word.count - 1 else { return nil }

        let left = String(word[word.startIndex..<dash])
        let right = String(word[word.index(after: dash)...])
        return right.caseInsensitiveCompare("th") == .orderedSame ? [left + right] : [left, right]
    }
}

extension Character {
    var isAsciiDigit: Bool { isASCII && ("0"..."9").contains(self) }
    var isAsciiLetter: Bool { isASCII && (("a"..."z").contains(self) || ("A"..."Z").contains(self)) }
}
