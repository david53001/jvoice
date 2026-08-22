using System.Globalization;
using System.Text;

namespace JVoice.Core.Text;

/// Spoken number words → digits ("twenty five" → "25", "three point one four" → "3.14").
///
/// Used ONLY inside a run that <see cref="MathSpeech"/> has already recognised as
/// mathematics, so it can be greedy: turning "one" into "1" is right in "x = one half" and
/// would be wrong in "one of my friends", and the run rules — not this parser — are what
/// tell the two apart.
///
/// Every entry point is a "try-read at this index" so the caller stays in control of the
/// token stream: they return the digits plus how many words were consumed, or null.
///
/// ── The one hard rule: never over-consume ──────────────────────────────────────────────
/// <c>Consumed</c> is how many of the CALLER's words disappear into the number, so a word is
/// taken only when the grammar says it belongs to it. Everything ambiguous is settled by
/// lookahead rather than greed:
///   • "and" is the number's own connective only after a magnitude AND before a tail that
///     finishes it — "one hundred and five" is 105, "five and my friend" stops at "five",
///     and "one hundred and two hundred" stops at "one hundred" (the tail starts a NEW
///     number, so that "and" was ordinary English).
///   • "point" is a decimal point only when spoken digits follow it, so "at some point five
///     people left" can never become a decimal.
///   • "a" is an implicit one only immediately before a magnitude ("a hundred", "a
///     thousand"), never on its own. <see cref="MathSpeech"/> treats a bare "a" as a WEAK
///     variable, and that is exactly what keeps "two times a day" out of mathematics —
///     swallowing the article here would break it. "there were about a hundred people
///     there" still comes back byte-identical, because a run that is nothing but a number
///     never activates a conversion and is re-emitted word for word.
///   • A hyphenated token is all-or-nothing: whisper writes "twenty-five" as readily as
///     "twenty five" (25), while "five-year" is not a number at all.
///
/// A continuation that is not well-formed ENDS the number instead of being guessed at:
/// "nineteen eighty four" reads as 19 followed by 84, not the year 1984. Year reading needs
/// context this parser does not have ("sixty seventy people" is two numbers), and it could
/// only ever fire inside an equation, where two spoken groups do not mean a year. Prose is
/// unaffected either way — nothing there converts.
///
/// Output is always plain digits: no thousands separators, and commas whisper already wrote
/// are stripped ("1,000" → "1000").
public static class SpokenNumbers
{
    private static readonly Dictionary<string, int> Units = new(StringComparer.OrdinalIgnoreCase)
    {
        ["zero"] = 0, ["nought"] = 0, ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4,
        ["five"] = 5, ["six"] = 6, ["seven"] = 7, ["eight"] = 8, ["nine"] = 9, ["ten"] = 10,
        ["eleven"] = 11, ["twelve"] = 12, ["thirteen"] = 13, ["fourteen"] = 14,
        ["fifteen"] = 15, ["sixteen"] = 16, ["seventeen"] = 17, ["eighteen"] = 18,
        ["nineteen"] = 19,
    };

    private static readonly Dictionary<string, int> Tens = new(StringComparer.OrdinalIgnoreCase)
    {
        ["twenty"] = 20, ["thirty"] = 30, ["forty"] = 40, ["fifty"] = 50,
        ["sixty"] = 60, ["seventy"] = 70, ["eighty"] = 80, ["ninety"] = 90,
    };

    /// Magnitudes that CLOSE the group they multiply: "three thousand four" starts a fresh
    /// group at "four". "hundred" is deliberately not one of them — it scales the group in
    /// place, so "three hundred and five" keeps building on 300.
    private static readonly Dictionary<string, long> Scales = new(StringComparer.OrdinalIgnoreCase)
    {
        ["thousand"] = 1_000L,
        ["million"] = 1_000_000L,
        ["billion"] = 1_000_000_000L,
        ["trillion"] = 1_000_000_000_000L,
    };

    private const string Hundred = "hundred";

    /// True when the word is already numeric as transcribed ("7", "3.14", "1,000").
    public static bool IsDigits(string word)
    {
        if (word.Length == 0) return false;
        bool digit = false;
        foreach (char c in word)
        {
            if (char.IsAsciiDigit(c)) { digit = true; continue; }
            if (c is '.' or ',') continue;
            return false;
        }
        return digit;
    }

    /// Reads a cardinal number (or an already-numeric token) starting at
    /// <paramref name="index"/>. Returns the digits and how many words were consumed.
    public static (string Digits, int Consumed)? TryRead(IReadOnlyList<string> words, int index)
    {
        if (index < 0 || index >= words.Count) return null;

        string text;
        int consumed;
        bool fromDigits = IsDigits(words[index]);

        if (fromDigits)
        {
            text = words[index].Replace(",", "");
            consumed = 1;
        }
        else
        {
            var (state, read) = ReadCardinal(words, index);
            if (read == 0) return null;
            text = state.Value.ToString(CultureInfo.InvariantCulture);
            consumed = read;
        }

        // "three point one four" → "3.14". A token whisper already wrote with a decimal
        // point ("3.14") is finished as it stands.
        bool hasFraction = false;
        if (!text.Contains('.')
            && TryReadDecimals(words, index + consumed, out string decimals, out int pointWords))
        {
            text += "." + decimals;
            consumed += pointWords;
            hasFraction = true;
        }

        // "two point five million" / "3 million" — a trailing magnitude the cardinal loop
        // cannot already have eaten, because a decimal or a digit token ended it.
        int after = index + consumed;
        if ((hasFraction || fromDigits) && after < words.Count
            && Scales.TryGetValue(words[after], out long scale)
            && TryScale(text, scale, out string scaled))
        {
            text = scaled;
            consumed++;
        }

        return (text, consumed);
    }

    /// Ordinal names, plus the two magnitudes an "&lt;ordinal&gt; root" could plausibly use.
    /// "second" is here as the number 2 — the time unit is a different sense, and the only
    /// caller today asks for an ordinal explicitly (it must be followed by "root").
    private static readonly Dictionary<string, int> Ordinals = new(StringComparer.OrdinalIgnoreCase)
    {
        ["first"] = 1, ["second"] = 2, ["third"] = 3, ["fourth"] = 4, ["fifth"] = 5,
        ["sixth"] = 6, ["seventh"] = 7, ["eighth"] = 8, ["ninth"] = 9, ["tenth"] = 10,
        ["eleventh"] = 11, ["twelfth"] = 12, ["thirteenth"] = 13, ["fourteenth"] = 14,
        ["fifteenth"] = 15, ["sixteenth"] = 16, ["seventeenth"] = 17, ["eighteenth"] = 18,
        ["nineteenth"] = 19, ["twentieth"] = 20, ["thirtieth"] = 30, ["fortieth"] = 40,
        ["fiftieth"] = 50, ["sixtieth"] = 60, ["seventieth"] = 70, ["eightieth"] = 80,
        ["ninetieth"] = 90, ["hundredth"] = 100, ["thousandth"] = 1_000,
    };

    /// Reads an ordinal ("fourth" → "4", "twenty first" → "21", "4th" → "4", "nth" → "n"),
    /// used for "&lt;ordinal&gt; root of x". It returns the DEGREE, which is why "nth" comes
    /// back as the letter it is spoken as: ⁿ√x.
    public static (string Digits, int Consumed)? TryReadOrdinal(IReadOnlyList<string> words, int index)
    {
        if (index < 0 || index >= words.Count) return null;

        // "twenty-first" / "n-th" — one token, so the whole compound costs one word.
        if (SplitHyphen(words[index]) is { } parts)
            return ReadOrdinal(parts, 0) is { } hyphenated ? (hyphenated.Digits, 1) : null;

        return ReadOrdinal(words, index);
    }

    /// Denominator names, for <see cref="TryReadFraction"/>. "second(s)" is left out on
    /// purpose — "two seconds" is a duration far more often than a half.
    private static readonly Dictionary<string, int> Denominators = new(StringComparer.OrdinalIgnoreCase)
    {
        ["half"] = 2, ["halves"] = 2, ["quarter"] = 4, ["quarters"] = 4,
        ["third"] = 3, ["thirds"] = 3, ["fourth"] = 4, ["fourths"] = 4,
        ["fifth"] = 5, ["fifths"] = 5, ["sixth"] = 6, ["sixths"] = 6,
        ["seventh"] = 7, ["sevenths"] = 7, ["eighth"] = 8, ["eighths"] = 8,
        ["ninth"] = 9, ["ninths"] = 9, ["tenth"] = 10, ["tenths"] = 10,
        ["hundredth"] = 100, ["hundredths"] = 100, ["thousandth"] = 1_000, ["thousandths"] = 1_000,
    };

    /// Reads a spoken fraction ("three quarters" → "3/4", "two-thirds" → "2/3").
    ///
    /// NOT called by <see cref="MathSpeech"/> yet: a fraction is a whole operand, so the
    /// engine has to decide where it may appear before it can be wired in — "one half of
    /// the team" must stay English. Kept here because the vocabulary belongs with the rest
    /// of the number words.
    public static (string Digits, int Consumed)? TryReadFraction(IReadOnlyList<string> words, int index)
    {
        if (index < 0 || index >= words.Count) return null;

        if (SplitHyphen(words[index]) is { } parts)
            return ReadFraction(parts, 0) is { } hyphenated ? (hyphenated.Digits, 1) : null;

        return ReadFraction(words, index);
    }

    // ─────────────────────────────── cardinals ───────────────────────────────

    /// Runs the cardinal grammar from <paramref name="index"/> and reports how many words it
    /// legitimately consumed (0 = the words there are not a number).
    private static (Cardinal State, int Consumed) ReadCardinal(IReadOnlyList<string> words, int index)
    {
        var state = new Cardinal();
        int consumed = 0;

        while (index + consumed < words.Count)
        {
            string word = words[index + consumed];

            if (word.Equals("and", StringComparison.OrdinalIgnoreCase))
            {
                if (!state.WantsConnective || !Continues(words, index + consumed + 1, state)) break;
                consumed++;
                continue;
            }

            // "a hundred" — "a" is an implicit one, but only as the first word and only when
            // a magnitude follows it (see the class doc for why a bare "a" is left alone).
            if (consumed == 0 && word.Equals("a", StringComparison.OrdinalIgnoreCase)
                && index + 1 < words.Count && IsMagnitude(words[index + 1]))
                word = "one";

            var trial = state;
            if (!trial.Feed(word)) break;
            state = trial;
            consumed++;
        }

        return (state, consumed);
    }

    /// True when the words after an "and" FINISH the current number rather than starting a
    /// new one. The tail is fed to a copy of the live state, so the grammar itself decides:
    /// in "one hundred and two hundred" the copy chokes on the second "hundred", and a
    /// magnitude sitting right where the tail stopped is the tell that the "and" was joining
    /// two numbers ("five hundred and twenty three thousand" is one number, and its tail
    /// swallows the "thousand" itself).
    private static bool Continues(IReadOnlyList<string> words, int index, Cardinal state)
    {
        int length = 0;
        while (index + length < words.Count)
        {
            var trial = state;
            if (!trial.Feed(words[index + length])) break;
            state = trial;
            length++;
        }

        if (length == 0) return false;
        int next = index + length;
        return next >= words.Count || !IsMagnitude(words[next]);
    }

    private static bool IsMagnitude(string word)
        => word.Equals(Hundred, StringComparison.OrdinalIgnoreCase) || Scales.ContainsKey(word);

    /// The cardinal grammar, as a tiny state machine. Copy semantics are the point: a caller
    /// feeds a COPY and keeps it only when the word was accepted, so a word the grammar
    /// rejects is never half-applied to the number it ended.
    private struct Cardinal
    {
        private long _total;        // groups already closed by a magnitude ("two million")
        private long _group;        // the group being built, below 1000
        private long _lastScale;    // 0 = none yet; magnitudes must strictly descend
        private bool _started;      // at least one word has been accepted
        private bool _pendingUnit;  // a units/teens value is in the group — nothing may extend it
        private bool _pendingTens;  // a tens value is in the group — only 1..9 may follow
        private bool _usedHundred;

        public readonly long Value => _total + _group;

        /// True once the number is big enough for the spoken "and" ("one hundred and five",
        /// "two thousand and five"). Below a hundred there is no such connective, which is
        /// what makes "seven and made coffee" stop at "seven".
        public readonly bool WantsConnective => _usedHundred || _total > 0;

        /// Accepts one spoken word. A hyphen-joined compound counts as ONE word and is
        /// all-or-nothing, so "twenty-five" is 25 while "five-year" is not a number.
        public bool Feed(string word)
        {
            if (word.IndexOf('-') < 0) return FeedPart(word);

            var parts = word.Split('-', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return false;

            var trial = this;
            foreach (string part in parts)
                if (!trial.FeedPart(part)) return false;

            this = trial;
            return true;
        }

        private bool FeedPart(string part)
        {
            if (Units.TryGetValue(part, out int unit))
            {
                if (_pendingUnit) return false;                          // "five six" is two numbers
                if (_pendingTens && unit is < 1 or > 9) return false;    // "twenty fifteen" likewise
                _group += unit;
                _pendingUnit = true;
                _pendingTens = false;
                return Accept();
            }

            if (Tens.TryGetValue(part, out int tens))
            {
                if (_pendingUnit || _pendingTens) return false;          // "nineteen eighty" is two
                _group += tens;
                _pendingTens = true;
                return Accept();
            }

            if (part.Equals(Hundred, StringComparison.OrdinalIgnoreCase))
            {
                if (_usedHundred) return false;                          // "one hundred two hundred"
                _group = (_group == 0 ? 1 : _group) * 100;               // bare/"a" hundred → 100
                _usedHundred = true;
                _pendingUnit = _pendingTens = false;
                return Accept();
            }

            if (Scales.TryGetValue(part, out long scale))
            {
                if (_lastScale != 0 && scale >= _lastScale) return false;    // "two thousand million"
                long multiplier = _group != 0 ? _group : (_started ? 0 : 1); // bare "thousand" → 1000
                if (multiplier == 0) return false;                          // two magnitudes in a row
                _total += multiplier * scale;
                _group = 0;
                _lastScale = scale;
                _pendingUnit = _pendingTens = _usedHundred = false;
                return Accept();
            }

            return false;
        }

        private bool Accept()
        {
            _started = true;
            return true;
        }
    }

    // ─────────────────────────────── decimals ───────────────────────────────

    /// "point one four" → "14". The digits after a decimal point are spoken ONE AT A TIME,
    /// so "three point fourteen" is deliberately not a decimal — that number ends at
    /// "three". Returns false when "point" is not followed by digits at all, which is what
    /// keeps the ordinary word out of the parser ("at some point five people left").
    private static bool TryReadDecimals(
        IReadOnlyList<string> words, int index, out string decimals, out int consumed)
    {
        decimals = "";
        consumed = 0;
        if (index >= words.Count || !words[index].Equals("point", StringComparison.OrdinalIgnoreCase))
            return false;

        var sb = new StringBuilder();
        int k = index + 1;
        while (k < words.Count && TryDigit(words[k], out string digit)) { sb.Append(digit); k++; }
        if (sb.Length == 0) return false;

        decimals = sb.ToString();
        consumed = k - index;
        return true;
    }

    /// One spoken decimal digit — a units word 0..9, or a bare digit token whisper wrote
    /// numerically ("three point 1 4").
    private static bool TryDigit(string word, out string digit)
    {
        if (Units.TryGetValue(word, out int unit) && unit <= 9)
        {
            digit = unit.ToString(CultureInfo.InvariantCulture);
            return true;
        }
        if (word.Length > 0 && word.All(char.IsAsciiDigit))
        {
            digit = word;
            return true;
        }
        digit = "";
        return false;
    }

    /// "2.5" × million → "2500000", with the trailing zeros a decimal would keep trimmed off.
    /// Refuses (rather than throws) on a mantissa too big to scale — whisper can write an
    /// arbitrarily long digit token, and losing the magnitude beats losing the number.
    private static bool TryScale(string mantissa, long scale, out string scaled)
    {
        scaled = "";
        if (!decimal.TryParse(mantissa, NumberStyles.Number, CultureInfo.InvariantCulture, out decimal value))
            return false;
        if (value > decimal.MaxValue / scale) return false;

        scaled = (value * scale).ToString("0.############################", CultureInfo.InvariantCulture);
        return true;
    }

    // ─────────────────────────────── ordinals & fractions ───────────────────────────────

    private static (string Digits, int Consumed)? ReadOrdinal(IReadOnlyList<string> words, int index)
    {
        string word = words[index];

        // "nth root" is spoken as a letter and reads back as one (ⁿ√x); "kth" works the same
        // way. No ordinary English word is a single letter followed by "th".
        if (word.Length == 3 && char.IsAsciiLetter(word[0])
            && word.AsSpan(1).Equals("th", StringComparison.OrdinalIgnoreCase))
            return (word[..1], 1);

        // "21st", "4th" — whisper writes ordinals numerically as often as it spells them.
        // The suffix is not checked against the number: "2th" happens, and rejecting it
        // would only lose an ordinal that was clearly meant.
        if (word.Length > 2 && word[..^2].All(char.IsAsciiDigit) && IsOrdinalSuffix(word[^2..]))
            return (word[..^2], 1);

        // "twenty first" — a tens word plus a unit ordinal.
        if (Tens.TryGetValue(word, out int tens) && index + 1 < words.Count
            && Ordinals.TryGetValue(words[index + 1], out int unit) && unit is >= 1 and <= 9)
            return ((tens + unit).ToString(CultureInfo.InvariantCulture), 2);

        return Ordinals.TryGetValue(word, out int value)
            ? (value.ToString(CultureInfo.InvariantCulture), 1)
            : null;
    }

    private static bool IsOrdinalSuffix(string suffix)
        => suffix.Equals("st", StringComparison.OrdinalIgnoreCase)
           || suffix.Equals("nd", StringComparison.OrdinalIgnoreCase)
           || suffix.Equals("rd", StringComparison.OrdinalIgnoreCase)
           || suffix.Equals("th", StringComparison.OrdinalIgnoreCase);

    private static (string Digits, int Consumed)? ReadFraction(IReadOnlyList<string> words, int index)
    {
        if (TryRead(words, index) is not { } numerator || numerator.Digits.Contains('.')) return null;

        int k = index + numerator.Consumed;
        if (k >= words.Count || !Denominators.TryGetValue(words[k], out int denominator)) return null;

        return ($"{numerator.Digits}/{denominator}", numerator.Consumed + 1);
    }

    /// The two halves of a hyphenated token ("twenty-first"), or null when there is no
    /// hyphen to split on. "n-th" is just "nth" written with a hyphen, so it is rejoined.
    private static string[]? SplitHyphen(string word)
    {
        int dash = word.IndexOf('-');
        if (dash <= 0 || dash >= word.Length - 1) return null;

        string left = word[..dash], right = word[(dash + 1)..];
        return right.Equals("th", StringComparison.OrdinalIgnoreCase)
            ? new[] { left + right }
            : new[] { left, right };
    }
}
