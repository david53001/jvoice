using System.Text;

namespace JVoice.Core.Text;

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
/// anything else once their operands are there: an infix relation or operator with an operand
/// on BOTH sides, a prefix (√, ∫, ¬) with an operand after it, or a structural construct
/// (subscript, power, root, fraction, bounds, derivative, limit, absolute value). Everything
/// else — π, α, %, °, sin, brackets, number words — is WEAK: it renders inside a run that is
/// already mathematics and stays a plain word otherwise.
///
/// Extra rules close the gaps that the operand requirement alone leaves open:
///   • "a"/"A" are only WEAK operands, and a weak operand is refused when it is the last thing
///     before an ordinary word — which is exactly what makes "two times a day" safe while
///     "a subscript n equals 1 plus 7n" and "a plus b" still work. Nor does an operator
///     between a weak operand and a bare number activate: "I'm bringing a plus one".
///   • "I" is never a variable, and "sum"/"product" only count as ∑/∏ when bounds follow, so
///     "the sum of my fears" and "an integral part of the plan" never activate.
///   • A bare "to the" only activates when its exponent is unmistakable ("x to the 3",
///     "10 to the fifth"), never between two plain numbers ("I gave 5 to the 3 kids"), and
///     the "x" whisper writes for a spoken "times" ("3 x 4") is a weak times.
///
/// When nothing activates, <see cref="Convert"/> returns the input string itself — untouched,
/// not re-joined — so the feature is provably invisible outside mathematics.
///
/// ── Notation ───────────────────────────────────────────────────────────────────────────
/// The output is the SHARED notation format (`docs/mac-reference/math-notation-format.md`,
/// the same format BetterScreenshot's Capture Text pastes): slash fractions, "×" between
/// numbers and juxtaposition between letter terms, `sin θ`, `√(2x)` — see <see cref="MathScript"/>.
///
/// ── Grouping ───────────────────────────────────────────────────────────────────────────
/// Spoken maths has no brackets, so "choose", "over", "factorial", "f of", "the probability
/// of", "all over" and "the quantity" reach as far as a student means them — the rule is on
/// <see cref="Parser"/>.
///
/// ── Escape hatch ───────────────────────────────────────────────────────────────────────
/// Saying "start equation … end equation" forces every run between the markers to convert
/// (and drops the markers), for the rare symbol that is too ordinary a word to auto-activate.
///
/// The vocabulary lives in <see cref="MathSymbols"/>, number words in
/// <see cref="SpokenNumbers"/>, and Unicode script rendering in <see cref="MathScript"/>.
/// This file owns the grammar and the activation rules. Ported 1:1 from the Mac's
/// `MathSpeech.swift` (2026-09-29, parity rows 22–25), which itself began as a port of this file.
public static class MathSpeech
{
    // ─────────────────────────────── public API ───────────────────────────────

    /// Rewrites the spoken mathematics in <paramref name="text"/> and leaves everything else
    /// exactly as it was. Returns the same string instance when nothing converted.
    public static string Convert(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return text;

        var raw = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (raw.Length == 0) return text;

        var (toks, forced) = SplitTokens(raw);
        if (toks.Count == 0) return text;

        var items = Lex(toks);
        var emitter = new Emitter(toks, forced);

        var buf = new List<Item>();
        foreach (var it in items)
        {
            if (it.Kind == ItemKind.Word || SpansPunctuation(toks, it))
            {
                emitter.Flush(buf, brokenByWord: true);
                emitter.Verbatim(it.Start, it.Start + it.Count);
                continue;
            }

            if (buf.Count > 0 && toks[it.Start].Lead.Length > 0)
                emitter.Flush(buf, brokenByWord: false);

            buf.Add(it);

            // Punctuation normally ends a run, because a converted run only keeps the
            // punctuation at its two ends and an interior comma would be swallowed. The one
            // exception is the comma dictation leaves right after an opening bracket
            // ("5000 parentheses open, 1 plus 1.03 over 100"): there the pause is INSIDE the
            // equation, and dropping that comma is exactly what should happen.
            if (toks[it.Start + it.Count - 1].Trail.Length > 0 && !Opens(it))
                emitter.Flush(buf, brokenByWord: false);
        }
        emitter.Flush(buf, brokenByWord: false);

        return emitter.Changed ? emitter.Result() : text;
    }

    // ─────────────────────────────── tokens ───────────────────────────────

    /// One whitespace-separated word, with its punctuation peeled off so a run can be spliced
    /// back in without losing the comma that ended it.
    private sealed record Tok(string Lead, string Core, string Trail)
    {
        public string Raw => Lead + Core + Trail;
    }

    private const string LeadPunct = "([{\"'“‘¿¡";
    private const string TrailPunct = ",.;:!?)]}\"'”’…";

    private static readonly string[] SpanOpen = { "start equation", "begin equation", "open equation" };
    private static readonly string[] SpanClose = { "end equation", "end of equation", "close equation" };

    private static (List<Tok> Toks, List<bool> Forced) SplitTokens(string[] raw)
    {
        var all = raw.Select(Peel).ToList();
        var cores = all.Select(t => t.Core).ToList();

        var drop = new bool[all.Count];
        var forced = new bool[all.Count];
        bool inSpan = false;
        for (int i = 0; i < all.Count; i++)
        {
            if (MatchesAny(cores, i, SpanOpen, out int len) || MatchesAny(cores, i, SpanClose, out len))
            {
                inSpan = MatchesAny(cores, i, SpanOpen, out _);
                for (int k = 0; k < len; k++) drop[i + k] = true;
                i += len - 1;
                continue;
            }
            forced[i] = inSpan;
        }

        var toks = new List<Tok>();
        var keptForced = new List<bool>();
        for (int i = 0; i < all.Count; i++)
        {
            if (drop[i]) continue;
            toks.Add(all[i]);
            keptForced.Add(forced[i]);
        }
        return (toks, keptForced);
    }

    private static Tok Peel(string raw)
    {
        int start = 0, end = raw.Length;
        while (start < end && LeadPunct.IndexOf(raw[start]) >= 0) start++;
        while (end > start && TrailPunct.IndexOf(raw[end - 1]) >= 0) end--;
        return new Tok(raw[..start], raw[start..end], raw[end..]);
    }

    private static bool MatchesAny(List<string> cores, int i, string[] phrases, out int consumed)
    {
        foreach (var phrase in phrases)
        {
            var words = phrase.Split(' ');
            if (i + words.Length > cores.Count) continue;
            bool ok = true;
            for (int k = 0; k < words.Length && ok; k++)
                ok = Eq(cores[i + k], words[k]);
            if (ok) { consumed = words.Length; return true; }
        }
        consumed = 0;
        return false;
    }

    private static bool Eq(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    private static bool Opens(Item it)
        => it.Kind == ItemKind.Symbol && it.Sym?.Kind == MathKind.Open;

    /// True when a multi-word item straddles punctuation ("x, subscript n") — such an item is
    /// demoted to an ordinary word so no comma is ever swallowed by a rewrite.
    private static bool SpansPunctuation(List<Tok> toks, Item it)
    {
        for (int t = it.Start; t < it.Start + it.Count; t++)
        {
            if (t != it.Start && toks[t].Lead.Length > 0) return true;
            if (t != it.Start + it.Count - 1 && toks[t].Trail.Length > 0) return true;
        }
        return false;
    }

    // ─────────────────────────────── lexing ───────────────────────────────

    private enum ItemKind { Number, Variable, Symbol, Keyword, Word }

    /// A structural construct the ENGINE parses (with its operands) rather than the vocabulary
    /// looking it up — see <see cref="MathSymbols.ReservedPhrases"/>.
    private enum Kw
    {
        None, Sub, Sup, Pow2, Pow3, Power, Root, Over, From, To, Of,
        Abs, Deriv, PartialDeriv, Wrt, Limit, As, Approaches, Base, Choose, The,
        // Mac 2026-09-29, math-notation-format.md
        AllOver, Quantity, TendsTo, DerivRatio,
    }

    /// How an exponent after a power keyword was said: as a plain operand ("to the 3"), as an
    /// ordinal ("to the fifth", "to the 3rd"), or as an ordinal plus "power".
    private enum OrdinalForm { None, Bare, WithPower }

    private sealed record Item(ItemKind Kind, string Text, int Start, int Count)
    {
        public MathSymbol? Sym { get; init; }
        public Kw Key { get; init; } = Kw.None;
        public bool Weak { get; init; }
        public OrdinalForm Ordinal { get; init; } = OrdinalForm.None;
        /// Two variables whisper glued into one word ("Kx"): an operand that never makes a
        /// construct around it count as mathematics (lexer step 5b).
        public bool Glued { get; init; }
    }

    // NOTE: no "the ..." variants — a structural construct never swallows a spoken word. "the
    // derivative of y with respect to x" → "the dy/dx", exactly like "the square root of 16" →
    // "the √16". (Vocabulary NAMES may include an article, e.g. "the reals" → ℝ, because there
    // the article is part of the name.)
    private static readonly Dictionary<string, (Kw Key, string Payload)> Keywords =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["subscript"] = (Kw.Sub, ""),
            ["sub"] = (Kw.Sub, ""),
            ["superscript"] = (Kw.Sup, ""),
            ["super"] = (Kw.Sup, ""),
            ["sup"] = (Kw.Sup, ""),
            ["squared"] = (Kw.Pow2, ""),
            ["cubed"] = (Kw.Pow3, ""),
            ["to the power of"] = (Kw.Power, ""),
            ["to the power"] = (Kw.Power, ""),
            ["raised to the power of"] = (Kw.Power, ""),
            ["raised to the power"] = (Kw.Power, ""),
            ["raised to"] = (Kw.Power, ""),
            // "e to the x" is as common as "e to the power of x". Safe because a power still
            // needs an operand on the left AND a real operand on the right, so "listen to the
            // alpha version" and "go to the store" can never take it — and because the lexer
            // marks this bare form weak, so "I gave 5 to the 3 kids" can't either (see
            // Parser.PowerIsUnmistakable).
            ["to the"] = (Kw.Power, ""),
            ["base"] = (Kw.Base, ""),          // after a function: "log base 2 of x" → log₂x
            // "the" belongs to the maths phrase when it sits in OPERAND position ("x equals the
            // square root of 2" → "x = √2") and to the sentence anywhere else. Lexing it as a
            // keyword lets the parser make that distinction instead of the run ending here.
            ["the"] = (Kw.The, ""),
            ["choose"] = (Kw.Choose, ""),      // "n choose k" → C(n, k)
            ["square root of"] = (Kw.Root, "2"),
            ["square root"] = (Kw.Root, "2"),
            ["cube root of"] = (Kw.Root, "3"),
            // Bare "root of" is the square root, WEAK (lexer): "the root of K cubed" converts
            // inside an equation or when its radicand is a power; "the root of the problem" never.
            ["root of"] = (Kw.Root, "2"),
            ["cube root"] = (Kw.Root, "3"),
            ["over"] = (Kw.Over, ""),
            // "a plus b all over 2" → (a + b)/2: the whole side so far is the numerator. WEAK —
            // it never makes a run mathematics by itself ("there were 5 all over 2 floors"), and
            // a multi-term numerator has already activated through its own operator.
            ["all over"] = (Kw.AllOver, ""),
            // "the square root of the quantity b squared minus 4 a c" → √(b² - 4ac): the spoken
            // open bracket. Weak like every bracket, and only a group when it holds more than
            // one term ("the quantity x equals 5" stays words).
            ["the quantity"] = (Kw.Quantity, ""),
            ["from"] = (Kw.From, ""),
            ["to"] = (Kw.To, ""),
            ["of"] = (Kw.Of, ""),
            ["absolute value of"] = (Kw.Abs, ""),
            ["absolute value"] = (Kw.Abs, ""),
            ["derivative of"] = (Kw.Deriv, ""),
            ["partial derivative of"] = (Kw.PartialDeriv, ""),
            ["with respect to"] = (Kw.Wrt, ""),
            ["limit"] = (Kw.Limit, ""),
            ["lim"] = (Kw.Limit, ""),
            ["as"] = (Kw.As, ""),
            ["approaches"] = (Kw.Approaches, ""),
            // Inside a limit it is "approaches"; on its own, "x tends to infinity" → x → ∞.
            ["tends to"] = (Kw.TendsTo, ""),
            ["goes to"] = (Kw.Approaches, ""),
        };

    private static readonly int MaxKeywordWords = Keywords.Keys.Max(k => k.Count(c => c == ' ') + 1);

    /// Big operators whose spoken name is an ordinary English noun: only mathematics when
    /// bounds follow ("sum from n equals 1 to ten"), never on their own.
    private static readonly Dictionary<string, string> BoundedOnly = new(StringComparer.OrdinalIgnoreCase)
    {
        ["sum"] = "∑",
        ["sums"] = "∑",
        ["product"] = "∏",
        ["products"] = "∏",
    };

    /// "7n", "3x" — whisper writes coefficients glued to the variable (`^\d+(\.\d+)?[a-zA-Z]$`).
    private static bool IsCoefficient(string word)
    {
        if (word.Length < 2 || !char.IsAsciiLetter(word[^1])) return false;
        int n = word.Length - 1, i = 0;
        while (i < n && char.IsAsciiDigit(word[i])) i++;
        if (i == 0) return false;
        if (i < n)
        {
            if (word[i] != '.') return false;
            i++;
            int fractionStart = i;
            while (i < n && char.IsAsciiDigit(word[i])) i++;
            if (i == fractionStart) return false;
        }
        return i == n;
    }

    private static List<Item> Lex(List<Tok> toks)
    {
        var cores = toks.Select(t => t.Core).ToList();
        var items = new List<Item>();

        int i = 0;
        while (i < cores.Count)
        {
            string core = cores[i];
            if (core.Length == 0)
            {
                items.Add(new Item(ItemKind.Word, "", i, 1));
                i++;
                continue;
            }
            Item? last = items.Count > 0 ? items[^1] : null;

            // 1) "<ordinal> root of x" → ⁿ√x
            if (SpokenNumbers.TryReadOrdinal(cores, i) is { } rootOrdinal
                && i + rootOrdinal.Consumed < cores.Count
                && Eq(cores[i + rootOrdinal.Consumed], "root"))
            {
                int length = rootOrdinal.Consumed + 1;
                if (i + length < cores.Count && Eq(cores[i + length], "of")) length++;
                items.Add(new Item(ItemKind.Keyword, rootOrdinal.Digits, i, length) { Key = Kw.Root });
                i += length;
                continue;
            }

            // 1b) "x to the fifth", "x to the third power", "x to the 3rd": an ordinal right
            //     after a power keyword is the exponent (its digits; "nth" reads as "n").
            if (last is { Kind: ItemKind.Keyword, Key: Kw.Power }
                && SpokenNumbers.TryReadOrdinal(cores, i) is { } ordinal)
            {
                int length = ordinal.Consumed;
                bool saidPower = i + length < cores.Count && Eq(cores[i + length], "power");
                if (saidPower) length++;
                items.Add(new Item(ItemKind.Number, ordinal.Digits, i, length)
                {
                    Ordinal = saidPower ? OrdinalForm.WithPower : OrdinalForm.Bare,
                });
                i += length;
                continue;
            }

            // 1c) "d y by d x" / "dy by dx" → dy/dx, one activating operand. Without "by" only
            //     when both were SPOKEN letter by letter ("d y d x") and nothing stands before
            //     them that they could belong to: after an integrand or an integral sign "dy dx"
            //     is a double integral's two differentials.
            if (Differential(cores, i) is { } top)
            {
                int j = i + top.Consumed;
                bool saidBy = j < cores.Count && Eq(cores[j], "by");
                if (saidBy) j++;
                if (Differential(cores, j) is { } bottom
                    && (saidBy || (top.Consumed == 2 && bottom.Consumed == 2 && !EndsOperand(last)
                                   && last?.Sym?.Kind != MathKind.Prefix)))
                {
                    items.Add(new Item(ItemKind.Keyword, top.Text + "/" + bottom.Text, i, j + bottom.Consumed - i)
                    {
                        Key = Kw.DerivRatio,
                    });
                    i = j + bottom.Consumed;
                    continue;
                }
            }

            // 2) "sum"/"product" — only a big operator when bounds follow
            if (BoundedOnly.TryGetValue(core, out string? bigOp)
                && i + 1 < cores.Count && Eq(cores[i + 1], "from"))
            {
                items.Add(new Item(ItemKind.Symbol, bigOp, i, 1) { Sym = new MathSymbol(bigOp, MathKind.Prefix) });
                i++;
                continue;
            }

            // 2b) "sigma" is the SUM SIGN (David, Mac 2026-09-29), never the letter σ — that is
            //     "lowercase sigma" / "small sigma" in the vocabulary. With bounds it is exactly
            //     "sum from … to …"; without them it is a WEAK ∑ that renders only inside a run
            //     something else made mathematics ("… Kx squared sigma of 3" → "… Kx² ∑ 3"), so
            //     "Six Sigma", "sigma male", "that's so sigma" stay words.
            if (Eq(core, "sigma"))
            {
                bool bounded = i + 1 < cores.Count && Eq(cores[i + 1], "from");
                items.Add(new Item(ItemKind.Symbol, "∑", i, 1)
                {
                    Sym = new MathSymbol("∑", MathKind.Prefix),
                    Weak = !bounded,
                });
                i++;
                continue;
            }

            // 3) numbers ("twenty five" → 25, "7", "7n")
            if (IsCoefficient(core))
            {
                items.Add(new Item(ItemKind.Number, core, i, 1));
                i++;
                continue;
            }
            // "one half" / "three quarters" is ONE operand ("1/2", "3/4"). Weak like any number,
            // so "three quarters of the class" never activates and stays words.
            if (SpokenNumbers.TryReadFraction(cores, i) is { } fraction)
            {
                items.Add(new Item(ItemKind.Number, fraction.Digits, i, fraction.Consumed));
                i += fraction.Consumed;
                continue;
            }
            if (SpokenNumbers.TryRead(cores, i) is { } number)
            {
                items.Add(new Item(ItemKind.Number, number.Digits, i, number.Consumed));
                i += number.Consumed;
                continue;
            }

            // 4) structural keywords vs the vocabulary — the LONGER phrase wins, so the
            //    vocabulary name "the reals" (ℝ) beats the bare keyword "the"; a tie goes to the
            //    engine, which owns the reserved forms.
            bool hasKeyword = TryKeyword(cores, i, out var kw, out string payload, out int kwLen);
            bool hasSymbol = MathSymbols.TryMatch(cores, i, out var symbol, out int symLen);
            if (hasKeyword && !(hasSymbol && symLen > kwLen))
            {
                // The bare "to the" is weak; "to the power (of)" is not.
                bool bareToThe = kw == Kw.Power && kwLen == 2 && Eq(core, "to");
                // "x to the quantity n plus 1": the "the" belongs to "the quantity", and a
                // grouped exponent is unmistakable.
                if (bareToThe && i + 2 < cores.Count && Eq(cores[i + 2], "quantity"))
                {
                    items.Add(new Item(ItemKind.Keyword, payload, i, 1) { Key = Kw.Power });
                    i++;
                    continue;
                }
                // A bare "root of" ("the root of K cubed") is weak too: "the root of 3 problems"
                // is English. "square root of" is not.
                bool bareRoot = kw == Kw.Root && Eq(core, "root");
                items.Add(new Item(ItemKind.Keyword, payload, i, kwLen) { Key = kw, Weak = bareToThe || bareRoot });
                i += kwLen;
                continue;
            }
            if (hasSymbol)
            {
                items.Add(new Item(ItemKind.Symbol, symbol.Text, i, symLen) { Sym = symbol });
                i += symLen;
                continue;
            }

            // 4b) "3 x 4": whisper writes a spoken "times" as the letter x. Between two numbers it
            //     is a spoken "times" (so "3 × 4") — and WEAK, so "a 2 x 4 board" and "my monitor
            //     is 1920 x 1080" stay words unless something else makes the run mathematics
            //     ("26 x 26 x 26 equals 17,576").
            if (core is "x" or "X" && last?.Kind == ItemKind.Number && SpokenNumbers.TryRead(cores, i + 1) is not null)
            {
                items.Add(new Item(ItemKind.Symbol, Parser.TimesMarker, i, 1)
                {
                    Sym = new MathSymbol(Parser.TimesMarker, MathKind.Operator),
                    Weak = true,
                });
                i++;
                continue;
            }

            // 5) single-letter variables ("I" is the pronoun, never a variable)
            if (core.Length == 1 && char.IsAsciiLetter(core[0]) && core != "I")
            {
                // "a"/"A" and lower-case "i" are WEAK: they are ordinary words at least as often
                // as they are variables ("two times a day", "…because i feel like…"). Weak only
                // matters at the very end of a run that an ordinary word cut short, so "a plus
                // b", "x subscript i plus 1" and "sum from i equals 1 to n" are all unaffected.
                items.Add(new Item(ItemKind.Variable, core, i, 1) { Weak = core is "a" or "A" or "i" });
                i++;
                continue;
            }

            // 5b) "times Kx squared": whisper glued two variables into one word. Only a
            //     two-letter, mixed- or lower-case token that is no English word, and only where
            //     it can only be an operand — right after an infix operator or right before a
            //     script ("squared", "sub", …). It is WEAK and GLUED: nothing around it activates
            //     because of it, so it renders only inside a run something else already made
            //     mathematics ("K squared plus … times Kx squared" → Kx²).
            if (IsGluedVariables(core) && (IsInfix(last) || StartsScript(cores, i + 1)))
            {
                items.Add(new Item(ItemKind.Variable, core, i, 1) { Weak = true, Glued = true });
                i++;
                continue;
            }

            items.Add(new Item(ItemKind.Word, core, i, 1));
            i++;
        }
        return items;
    }

    /// Two-letter words that are English (or units, or interjections) and never glued
    /// variables — compared case-insensitively. All-caps pairs (TV, PC, UK, AI) are refused
    /// separately as acronyms.
    private static readonly HashSet<string> TwoLetterWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "ab", "ad", "ah", "al", "am", "an", "as", "at", "aw", "ax", "ay", "be", "bi", "by", "cm",
        "co", "da", "do", "dr", "ed", "eh", "em", "en", "er", "ex", "fa", "ft", "go", "ha", "he",
        "hi", "hm", "ho", "hz", "id", "if", "im", "in", "is", "it", "jo", "ka", "kg", "km", "la",
        "lb", "li", "lo", "ma", "me", "mi", "ml", "mg", "mm", "mo", "mr", "ms", "mu", "my", "na",
        "nd", "ne", "no", "nu", "ob", "od", "of", "oh", "oi", "ok", "om", "on", "oo", "op", "or",
        "os", "ow", "ox", "oy", "oz", "pa", "pe", "pi", "pm", "po", "qi", "re", "rd", "sh", "si",
        "so", "st", "ta", "th", "ti", "to", "tv", "uh", "um", "un", "up", "ur", "us", "ut", "vs",
        "we", "wo", "xi", "ya", "ye", "yo", "yu", "za",
    };

    /// "Kx", "xy", "kx" — a token whisper glued from two spoken variables. Two ASCII letters,
    /// not all capitals (acronyms), not an English/unit two-letter word.
    private static bool IsGluedVariables(string core) =>
        core.Length == 2 && core.All(char.IsAsciiLetter) && !core.All(char.IsAsciiLetterUpper)
        && !TwoLetterWords.Contains(core);

    private static bool IsInfix(Item? item) =>
        item is { Kind: ItemKind.Symbol, Sym: { } sym } && sym.Kind is MathKind.Relation or MathKind.Operator;

    /// A script keyword starts at <paramref name="i"/>: "squared", "cubed", "sub…", "super…",
    /// "to the power".
    private static bool StartsScript(List<string> cores, int i)
    {
        if (i >= cores.Count || !TryKeyword(cores, i, out var key, out _, out int consumed)) return false;
        return key switch
        {
            Kw.Pow2 or Kw.Pow3 or Kw.Sub or Kw.Sup => true,
            Kw.Power => consumed > 2 || Eq(cores[i], "raised"),
            _ => false,
        };
    }

    /// Letters a differential is written with — whisper's one-word "dy"/"dx"/"dt" form is only
    /// trusted for these, so "do", "de", "Dr" never read as one.
    private const string DifferentialLetters = "xyztuvwrspqnk";

    /// One differential at <paramref name="i"/>: whisper's "dy", or spoken "d y" / "d theta".
    private static (string Text, int Consumed)? Differential(List<string> cores, int i)
    {
        if (i >= cores.Count) return null;
        string word = cores[i];
        if (word.Length == 2 && word[0] == 'd' && DifferentialLetters.Contains(word[1])) return (word, 1);
        if (word != "d" || i + 1 >= cores.Count) return null;
        string next = cores[i + 1];
        if (next.Length == 1 && char.IsAsciiLetter(next[0]) && next != "I") return ("d" + next, 2);
        if (MathSymbols.Phrases.TryGetValue(next, out var greek) && greek.Kind == MathKind.Operand
            && greek.Text.Length == 1 && char.IsLetter(greek.Text[0]) && !char.IsAscii(greek.Text[0]))
            return ("d" + greek.Text, 2);
        return null;
    }

    /// True when <paramref name="item"/> is something a following operand would multiply (so
    /// "dy dx" after it is two differentials, not a derivative).
    private static bool EndsOperand(Item? item)
    {
        if (item is null) return false;
        return item.Kind switch
        {
            ItemKind.Number or ItemKind.Variable => true,
            ItemKind.Keyword => item.Key is Kw.Pow2 or Kw.Pow3 or Kw.DerivRatio,
            ItemKind.Symbol => item.Sym?.Kind is MathKind.Operand or MathKind.Postfix or MathKind.Close,
            _ => false,
        };
    }

    private static bool TryKeyword(List<string> cores, int i, out Kw key, out string payload, out int consumed)
    {
        int max = System.Math.Min(MaxKeywordWords, cores.Count - i);
        for (int n = max; n >= 1; n--)
        {
            string phrase = string.Join(' ', cores.Skip(i).Take(n));
            if (Keywords.TryGetValue(phrase, out var found))
            {
                (key, payload, consumed) = (found.Key, found.Payload, n);
                return true;
            }
        }
        (key, payload, consumed) = (Kw.None, "", 0);
        return false;
    }

    // ─────────────────────────────── emitting ───────────────────────────────

    /// Rebuilds the output string, run by run: a converted run is spliced in with the original
    /// punctuation around it, an unconverted one is copied out word for word.
    private sealed class Emitter(List<Tok> toks, List<bool> forced)
    {
        private readonly List<string> _parts = new();
        public bool Changed { get; private set; }

        public string Result() => string.Join(' ', _parts);

        public void Verbatim(int fromTok, int toTok)
        {
            for (int t = fromTok; t < toTok; t++) _parts.Add(toks[t].Raw);
        }

        public void Flush(List<Item> buf, bool brokenByWord)
        {
            if (buf.Count == 0) return;

            // A weak operand ("a") that sits right before an ordinary word is not an operand
            // at all — this is what keeps "two times a day" out of mathematics.
            int weakCutoff = brokenByWord ? buf.Count - 1 : -1;
            bool anyForced = buf.Any(x => Enumerable.Range(x.Start, x.Count).Any(t => forced[t]));

            var run = new Run(buf.ToList(), weakCutoff, cleanEnd: !brokenByWord);
            int pos = 0;
            while (pos < buf.Count)
            {
                var parser = new Parser(run);
                var (text, activated, used) = parser.RunFrom(pos);
                if (used == 0)
                {
                    Verbatim(buf[pos].Start, buf[pos].Start + buf[pos].Count);
                    pos++;
                    continue;
                }

                int fromTok = buf[pos].Start;
                int toTok = buf[pos + used - 1].Start + buf[pos + used - 1].Count;
                if ((activated || anyForced) && text.Length > 0)
                {
                    _parts.Add(toks[fromTok].Lead + text + toks[toTok - 1].Trail);
                    Changed = true;
                }
                else Verbatim(fromTok, toTok);

                pos += used;
            }
            buf.Clear();
        }
    }

    // ─────────────────────────── expression building ───────────────────────────

    /// The rendered pieces of one run, plus the spacing rules that join them: relations and
    /// operators get air ("1 + 7n"), scripts and postfixes bind tight ("aₙ", "5!"), and a
    /// number followed by a letter is a coefficient ("7n", "2π").
    private sealed class Expr
    {
        private enum Role { Operand, Infix, Head }

        /// What built an operand. A finished binomial is a wall for a later choose or factorial
        /// reaching back over a sum ("n choose k plus n choose k minus 1"), a finished quotient
        /// is one for a later "over" reaching back over a product ("3 over 4 times 2 over 3").
        public enum Made { Plain, Binomial, Quotient }

        private sealed class Part(string text, Role role, bool tight, Made made = Made.Plain, bool relation = false)
        {
            public string Text = text;
            public readonly Role Role = role;
            public readonly bool Tight = tight;
            public Made Made = made;
            /// An infix that is a RELATION ("=", "<", "→"): where one side of an equation ends.
            public readonly bool Relation = relation;
        }

        private readonly List<Part> _parts = new();
        private bool _tightNext;

        public int Count => _parts.Count;
        public bool LastIsOperand => _parts.Count > 0 && _parts[^1].Role == Role.Operand;
        public string LastText => _parts[^1].Text;
        /// False when the last operand is glued onto the one before it ("2a").
        public bool LastStandsAlone => !(_parts.Count > 0 && _parts[^1].Tight);

        public void PushOperand(string text)
        {
            Part? last = _parts.Count > 0 ? _parts[^1] : null;
            // "u n" is a sequence term, not a product (David, 2026-08-30).
            if (last is { Role: Role.Operand } && Indexes(last.Text, text))
            {
                ReplaceLast(MathScript.Attach(last.Text, text, superscript: false));
                _tightNext = false;
                return;
            }

            bool tight = _tightNext
                || (last is { Role: Role.Operand } && Juxtaposes(last.Text, text))
                // "angle A B C" → ∠ABC, "triangle A B C" → △ABC: the glyph names the points.
                || (last is { Role: Role.Operand } && last.Text is "∠" or "△" && FirstIsLetter(text));
            _parts.Add(new Part(text, Role.Operand, tight));
            _tightNext = false;
        }

        /// A big operator or a "lim" head: the body that follows is separated by a space.
        public void PushHead(string text)
        {
            _parts.Add(new Part(text, Role.Head, _tightNext));
            _tightNext = false;
        }

        public void PushInfix(string text, bool relation = false)
        {
            _parts.Add(new Part(text, Role.Infix, false, relation: relation));
            _tightNext = false;
        }

        /// Where the current side of the equation begins: just after the last relation or
        /// "lim"/"∑" head, else 0 — what "all over" takes as its numerator.
        public int SideStart()
        {
            int s = _parts.Count;
            while (s > 0)
            {
                var part = _parts[s - 1];
                if (part.Role == Role.Head || (part.Role == Role.Infix && part.Relation)) break;
                s--;
            }
            return s;
        }

        /// "n minus 1 times d" is (n - 1)d — nobody multiplies by a spoken 1 on purpose, so a
        /// "times" straight after "&lt;lettered term&gt; ± 1" takes that whole difference (the
        /// arithmetic-sequence term aₙ = a₁ + (n - 1)d). Only the one term before the 1:
        /// "a₁ + n - 1 times d" groups "n - 1", never "a₁ + n - 1".
        public void GroupTrailingOne()
        {
            int c = _parts.Count;
            if (c < 3 || _parts[c - 1].Role != Role.Operand || _parts[c - 1].Text != "1" || _parts[c - 1].Tight
                || _parts[c - 2].Role != Role.Infix || _parts[c - 2].Text is not ("+" or "-")
                || _parts[c - 3].Role != Role.Operand) return;
            int s = c - 3;
            while (s > 0 && _parts[s].Tight && _parts[s - 1].Role == Role.Operand) s--;
            bool lettered = false;
            for (int k = s; k <= c - 3; k++) lettered |= HasLetter(_parts[k].Text);
            if (!lettered) return;
            // …and a whole term: not the tail of a product ("2 times n minus 1 times d").
            if (s > 0 && _parts[s - 1].Role == Role.Infix && Parser.Products.Contains(_parts[s - 1].Text)) return;
            Collapse(s, $"({Render(s)})");
        }

        public void AttachToLast(string suffix) => ReplaceLast(_parts[^1].Text + suffix);

        public void ReplaceLast(string text)
        {
            var last = _parts[^1];
            _parts[^1] = new Part(text, Role.Operand, last.Tight, last.Made);
        }

        public string Render() => Render(0);

        /// A spoken "times" is laid out only here, once both of its sides are final (a later
        /// "squared" or "factorial" still changes them): <see cref="MathScript.ProductSeparator"/>
        /// picks "×", a space, or juxtaposition.
        public string Render(int start)
        {
            var sb = new StringBuilder();
            bool joined = false;
            for (int index = start; index < _parts.Count; index++)
            {
                var part = _parts[index];
                if (part.Role == Role.Infix && part.Text == Parser.TimesMarker
                    && index > start && index + 1 < _parts.Count)
                {
                    sb.Append(MathScript.ProductSeparator(_parts[index - 1].Text, _parts[index + 1].Text));
                    joined = true;
                    continue;
                }
                if (index > start && !part.Tight && !joined) sb.Append(' ');
                joined = false;
                sb.Append(part.Text);
            }
            return sb.ToString();
        }

        /// True when the parts from <paramref name="start"/> on hold an infix operator — a side
        /// that needs brackets once it becomes one operand of a larger construct.
        public bool IsCompound(int start)
        {
            for (int k = start; k < _parts.Count; k++) if (_parts[k].Role == Role.Infix) return true;
            return false;
        }

        /// Where the trailing term that <paramref name="joins"/> hold together begins: from the
        /// last operand back over "&lt;operand&gt; &lt;join&gt; &lt;operand&gt;" links and
        /// implicit products ("2π"), stopping at anything else — a relation, another operator, a
        /// head — and at an operand <paramref name="wall"/> built.
        public int TailStart(IReadOnlySet<string> joins, Made wall)
        {
            int s = _parts.Count - 1;
            while (s > 0 && _parts[s].Made != wall)
            {
                if (_parts[s].Tight && _parts[s - 1].Role == Role.Operand && _parts[s - 1].Made != wall)
                {
                    s--;
                    continue;
                }
                if (s < 2 || _parts[s - 1].Role != Role.Infix || !joins.Contains(_parts[s - 1].Text)
                    || _parts[s - 2].Role != Role.Operand || _parts[s - 2].Made == wall) break;
                s -= 2;
            }
            return s;
        }

        /// Of the terms from <paramref name="start"/> on, where the first one holding a LETTER
        /// begins — or the last term, when none does. A spoken sum joins a binomial or a
        /// factorial only from its first letter on: "n plus k minus 1 choose k" takes all of
        /// "n + k - 1", but "1 minus 48 choose 5" takes only the number beside "choose" (rule 2).
        public int FirstLetterTerm(int start)
        {
            int termStart = start, lastTermStart = start;
            for (int index = start; index < _parts.Count; index++)
            {
                if (_parts[index].Role == Role.Infix)
                {
                    termStart = index + 1;
                    lastTermStart = termStart;
                }
                else if (HasLetter(_parts[index].Text)) return termStart;
            }
            return lastTermStart;
        }

        /// True when the first term (everything before the first operator) holds a letter.
        public bool FirstTermHasLetter =>
            _parts.TakeWhile(p => p.Role != Role.Infix).Any(p => HasLetter(p.Text));

        /// True when the first factor is a factorial or a binomial — the shape of a counting
        /// formula's denominator ("over k factorial times n minus k factorial").
        public bool FirstFactorCounts
        {
            get
            {
                int end = _parts.FindIndex(p => p.Role == Role.Infix);
                if (end < 0) end = _parts.Count;
                if (end == 0) return false;
                var factor = _parts[end - 1];
                return factor.Made == Made.Binomial || factor.Text.EndsWith('!');
            }
        }

        public void MarkLast(Made made) => _parts[^1].Made = made;

        /// Replaces the parts from <paramref name="start"/> on with ONE operand.
        public void Collapse(int start, string text, Made made = Made.Plain)
        {
            bool tight = _parts[start].Tight;
            _parts.RemoveRange(start, _parts.Count - start);
            _parts.Add(new Part(text, Role.Operand, tight, made));
        }

        public static bool HasLetter(string s)
        {
            foreach (Rune r in s.EnumerateRunes()) if (Rune.IsLetter(r)) return true;
            return false;
        }

        private static bool FirstIsLetter(string s) => s.Length > 0 && Rune.IsLetter(Rune.GetRuneAt(s, 0));

        /// Two ATOMIC operands side by side are implicit multiplication and are written closed
        /// up: "7 n" → "7n", "2 π" → "2π", "delta x" → "δx". Anything already composite
        /// ("aₙ", "sin(x)", "1/2") keeps its space, where the product is clearer spaced out.
        public static bool Juxtaposes(string left, string right)
            => IsSingleLetter(right) && (IsSingleLetter(left) || IsPlainNumber(left));

        /// An implicit product or a sequence index — the only ways one operand carries straight
        /// on into the next without an operator between them.
        public static bool ContinuesImplicitly(string left, string right)
            => Juxtaposes(left, right) || Indexes(left, right);

        /// A variable followed by a classic INDEX is a sequence term — "u n" → "uₙ",
        /// "u 1" → "u₁", "2 u n" → "2uₙ" — which is how David dictates a sequence without
        /// saying "subscript" every time.
        ///
        /// Deliberately narrow in both directions: only the traditional index letters count,
        /// so "x y" stays the product "xy"; and only a lone variable (with an optional numeric
        /// coefficient) can carry one, so "sin(x) n" and "aₙ k" are left alone. It is also WEAK
        /// — it renders inside a run that something else already turned into mathematics and
        /// never activates one itself, so "i think u n is fine" is still a sentence.
        private const string IndexLetters = "nkijm";

        private static bool Indexes(string left, string right)
            => CanCarryIndex(left) && IsIndex(right);

        private static bool CanCarryIndex(string s)
            => s.Length > 0 && char.IsLetter(s[^1]) && IsInteger(s[..^1]);

        private static bool IsIndex(string s)
            => (s.Length > 0 && IsInteger(s))
               || (IsSingleLetter(s) && IndexLetters.Contains(char.ToLowerInvariant(s[0])));

        private static bool IsSingleLetter(string s) => s.Length == 1 && char.IsLetter(s[0]);

        private static bool IsInteger(string s) => s.All(char.IsAsciiDigit);

        public static bool IsPlainNumber(string s)
            => s.Length > 0 && s.All(c => char.IsAsciiDigit(c) || c == '.');
    }

    // ─────────────────────────────── parsing ───────────────────────────────

    /// How far one expression reaches — which of the grouping rules on <see cref="Parser"/> is
    /// reading it.
    private enum Scope
    {
        /// A whole run, or the inside of a bracket: everything.
        Run,
        /// The right side of "choose" (rule 2): a sum or difference.
        Sum,
        /// The denominator of "over" (rule 3): a product.
        Product,
        /// What "f of" and the statistics functions apply to (rule 4): a sum, and "given".
        Argument,
        /// What "P of" / "the probability of" apply to (rule 5): the whole event.
        Event,
        /// The denominator after "all over" (rule 6): everything up to the next relation.
        Side,
    }

    /// One run's items plus the facts about them the parser asks over and over — computed
    /// once, right to left, on first use — so every such question is O(1) and a long run stays
    /// linear.
    private sealed class Run(List<Item> items, int weakCutoff, bool cleanEnd)
    {
        public List<Item> Items { get; } = items;
        /// The weak operand that sits right before an ordinary word, or -1.
        public int WeakCutoff { get; } = weakCutoff;
        /// True when the run ends at punctuation or at the end of the dictation, false when an
        /// ordinary word cut it short.
        public bool CleanEnd { get; } = cleanEnd;

        private bool[]? _reachesChoose, _endsInFactorial, _letterInTerm, _sumOperatorAhead,
            _letterBehind, _reachesOver, _relations;

        /// The sum starting at <paramref name="k"/> runs into a "choose" before anything ends it.
        public bool SumReachesChoose(int k) => k < Items.Count && ReachesChoose[k];

        /// The sum starting at <paramref name="k"/> is closed by a factorial, which makes it ONE
        /// factor ("over k factorial times n minus k factorial").
        public bool SumEndsInFactorial(int k) => k < Items.Count && EndsInFactorial[k];

        /// The term at <paramref name="k"/> is where the next binomial's left side begins: the
        /// sum from k runs into a "choose", and this term holds a letter or is the last one
        /// before it (the same test <see cref="Expr.FirstLetterTerm"/> applies once built).
        public bool StartsBinomial(int k) =>
            k < Items.Count && ReachesChoose[k] && (LetterInTerm[k] || !SumOperatorAhead[k]);

        /// The sum that runs up to <paramref name="k"/> already holds a letter — so a "choose"
        /// ahead will take it in, operator and all ("over n minus 1 choose k").
        public bool SumBehindHasLetter(int k) => k < Items.Count && LetterBehind[k];

        /// The product starting at <paramref name="k"/> runs into another "over" — so it is that
        /// fraction's numerator, not part of this one's denominator ("3 over 4 times 2 over 3").
        public bool ProductReachesOver(int k) => k < Items.Count && ReachesOver[k];

        /// A relation other than "given" follows at <paramref name="k"/> or later.
        public bool RelationAhead(int k) => k < Items.Count && Relations[k];

        private bool[] ReachesChoose => _reachesChoose ??= Scan((item, rest) =>
            item.Key == Kw.Choose || ((ContinuesSum(item) || IsFactorial(item)) && rest));

        private bool[] EndsInFactorial => _endsInFactorial ??= Scan((item, rest) =>
            IsFactorial(item) || (ContinuesSum(item) && rest));

        private bool[] LetterInTerm => _letterInTerm ??= Scan((item, rest) =>
            ContinuesSum(item) && !IsSumOperator(item) && (IsLettered(item) || rest));

        private bool[] SumOperatorAhead => _sumOperatorAhead ??= Scan((item, rest) =>
            IsSumOperator(item) || ((ContinuesSum(item) || IsFactorial(item)) && rest));

        private bool[] LetterBehind
        {
            get
            {
                if (_letterBehind is not null) return _letterBehind;
                var output = new bool[Items.Count];
                bool seen = false;
                for (int k = 0; k < Items.Count; k++)
                {
                    seen = ContinuesSum(Items[k]) && (seen || IsLettered(Items[k]));
                    output[k] = seen;
                }
                return _letterBehind = output;
            }
        }

        private bool[] ReachesOver => _reachesOver ??= Scan((item, rest) =>
            item.Key == Kw.Over || (ContinuesProduct(item) && rest));

        private bool[] Relations => _relations ??= Scan((item, rest) =>
            (item.Kind == ItemKind.Symbol && item.Sym?.Kind == MathKind.Relation && item.Sym.Text != "∣") || rest);

        private bool[] Scan(Func<Item, bool, bool> rule)
        {
            var output = new bool[Items.Count];
            bool rest = false;
            for (int k = Items.Count - 1; k >= 0; k--)
            {
                rest = rule(Items[k], rest);
                output[k] = rest;
            }
            return output;
        }

        /// An item a spoken sum runs THROUGH: an atom, a + or −, "squared"/"cubed", or a
        /// postfix other than a factorial.
        private static bool ContinuesSum(Item item) => item.Kind switch
        {
            ItemKind.Number or ItemKind.Variable => true,
            ItemKind.Keyword => item.Key is Kw.Pow2 or Kw.Pow3,
            ItemKind.Symbol => item.Sym switch
            {
                { Kind: MathKind.Operand } => true,
                { Kind: MathKind.Postfix } sym => !Parser.IsFactorial(sym.Text),
                { Kind: MathKind.Operator } sym => Parser.Additive.Contains(sym.Text),
                _ => false,
            },
            _ => false,
        };

        /// An item a spoken product runs through on its way to a following "over".
        private static bool ContinuesProduct(Item item) => item.Kind switch
        {
            ItemKind.Number or ItemKind.Variable => true,
            ItemKind.Keyword => item.Key is Kw.Pow2 or Kw.Pow3 or Kw.Sub,
            ItemKind.Symbol => item.Sym is { } sym
                && (sym.Kind is MathKind.Operand or MathKind.Postfix
                    || (sym.Kind == MathKind.Operator && Parser.Products.Contains(sym.Text))),
            _ => false,
        };

        private static bool IsFactorial(Item item) =>
            item.Kind == ItemKind.Symbol && item.Sym is { Kind: MathKind.Postfix } sym && Parser.IsFactorial(sym.Text);

        private static bool IsSumOperator(Item item) =>
            item.Kind == ItemKind.Symbol && item.Sym is { Kind: MathKind.Operator } sym && Parser.Additive.Contains(sym.Text);

        /// A variable, or a number or symbol spelled with a letter ("7n", "π").
        private static bool IsLettered(Item item) => item.Kind switch
        {
            ItemKind.Variable => true,
            ItemKind.Number => Expr.HasLetter(item.Text),
            ItemKind.Symbol => item.Sym?.Kind == MathKind.Operand && Expr.HasLetter(item.Text),
            _ => false,
        };
    }

    /// Walks one run left to right, folding items into an <see cref="Expr"/>. Stops at the
    /// first item it cannot consume and reports how far it got, so the caller can hand the
    /// leftovers back out as plain words.
    ///
    /// ── The grouping rule ─────────────────────────────────────────────────────────────
    /// Everything is written in the order it was said. Only these constructs decide how far
    /// their operands reach — tightest first — and a side with more than one term is bracketed
    /// so the result can never be misread:
    ///   1. FACTORIAL takes the sum in front of it (back to the nearest product, "÷", relation,
    ///      bracket or binomial) from its first letter on: "n minus k factorial" → "(n - k)!",
    ///      "2 plus n minus 1 factorial" → "2 + (n - 1)!", but "5 plus 3 factorial" → "5 + 3!".
    ///      In a denominator it takes the whole sum, because only a factorial lets a sum in there.
    ///   2. CHOOSE takes a sum on each side — never a product — when that sum starts with a
    ///      letter: "n plus k minus 1 choose k" → "C(n + k - 1, k)", "n choose n minus k" →
    ///      "C(n, n - k)"; otherwise just the term beside it: "1 minus 48 choose 5" →
    ///      "1 - C(48, 5)". A sum after one choose that runs into another stops where the next
    ///      binomial's left side starts: "n choose k plus n choose k minus 1" →
    ///      "C(n, k) + C(n, k - 1)".
    ///   3. OVER divides a PRODUCT by a PRODUCT when one was dictated — the numerator is a
    ///      product, or the denominator starts with a factorial or a binomial, the shape of every
    ///      counting formula: "10 times 9 times 8 over 3 times 2 times 1" →
    ///      "(10 × 9 × 8)/(3 × 2 × 1)". Otherwise it divides the factor beside it by the factor
    ///      after it: "3 over 4 plus 1 over 4" → "3/4 + 1/4". A product that runs into another
    ///      "over" belongs to that one, a binomial or a factorial is one factor, "squared" and
    ///      "cubed" stay on the denominator ("1 over n squared" → "1/n²").
    ///   4. "f of" (any letter applied with "of") and "the expected value / variance /
    ///      covariance / correlation / standard deviation of" take a sum and "given": "f of n
    ///      minus 1" → "f(n - 1)". A term that is itself an application or a binomial starts the
    ///      next term instead. Every other function (sine, log, …) takes one operand.
    ///   5. "P of" / "the probability of" take the whole EVENT — rule 4 plus powers, ∪ ∩ ∖,
    ///      "over", and one relation on each side of "given": "P of X less than 3" → "P(X < 3)",
    ///      "the probability of A given B" → "P(A ∣ B)". "equals" joins the event only when
    ///      another relation follows it ("P of X equals 3 equals 0.2" → "P(X = 3) = 0.2"). An
    ///      unclosed bracket closes before its second relation the same way.
    ///   6. "ALL OVER" takes the whole side so far as its numerator and the rest of the side, up
    ///      to the next relation, as its denominator: "x squared minus 9 all over x minus 3" →
    ///      "(x² - 9)/(x - 3)". "THE QUANTITY" opens a bracket that closes at "close bracket",
    ///      else before the next relation or "all over", else at the end of the run. Without them
    ///      every construct takes the SMALLEST reading: "the square root of x plus 1" →
    ///      "√x + 1", "log base 3 of x plus 1" → "log₃x + 1".
    ///   7. "TIMES" after "&lt;lettered term&gt; ± 1" takes that difference: "n minus 1 times d"
    ///      → "(n - 1)d" (<see cref="Expr.GroupTrailingOne"/>).
    /// None of this can make ordinary speech convert: grouping only decides where operands END.
    /// Every item it takes is one the flat fold would have read into the same run, and
    /// activation still comes only from the constructs themselves.
    private sealed class Parser
    {
        private readonly Run _ctx;
        private readonly List<Item> _items;
        private readonly Scope _scope;
        /// Rule 5's budget: an event — or an unclosed bracket — holds one relation on each side
        /// of "given"; the next one ends it.
        private readonly bool _limitsRelations;
        /// Rule 3: this denominator may run on over a product because its numerator was one.
        private readonly bool _joinsProducts;
        private int _relationsInPart;
        private bool _activated;

        public static readonly IReadOnlySet<string> Additive = new HashSet<string> { "+", "-", "±", "∓" };
        /// The internal text of a spoken "times" / "multiplied by" (and whisper's "3 x 4"). It
        /// never reaches the output: <see cref="Expr.Render(int)"/> lays it out as "×", a space
        /// or juxtaposition. "·" is the dot product alone.
        public const string TimesMarker = "*";
        public static readonly IReadOnlySet<string> Products = new HashSet<string> { "·", TimesMarker };
        /// Marks that turn a letter into a named function when "of" follows: "f prime of x" →
        /// f′(x), "f inverse of x" → f⁻¹(x).
        private static readonly IReadOnlySet<string> FunctionMarks = new HashSet<string> { "′", "″", "‴", "⁻¹" };
        private static readonly IReadOnlySet<string> SetOperations = new HashSet<string> { "∪", "∩", "∖" };

        /// The functions that apply to a whole expression (rules 4 and 5) rather than to one
        /// operand.
        private static readonly Dictionary<string, Scope> ArgumentScopes = new()
        {
            ["P"] = Scope.Event, ["E"] = Scope.Argument, ["Var"] = Scope.Argument,
            ["Cov"] = Scope.Argument, ["Corr"] = Scope.Argument, ["SD"] = Scope.Argument,
        };

        public static bool IsFactorial(string text) => text is "!" or "!!";

        public Parser(Run ctx, Scope scope = Scope.Run, bool limitsRelations = false, bool joinsProducts = false)
        {
            _ctx = ctx;
            _items = ctx.Items;
            _scope = scope;
            _limitsRelations = limitsRelations;
            _joinsProducts = joinsProducts;
        }

        public (string Text, bool Activated, int Used) RunFrom(int start)
        {
            var expr = new Expr();
            int i = start;
            while (i < _items.Count && Step(expr, ref i)) { }
            return (expr.Render(), _activated, i - start);
        }

        private bool Step(Expr expr, ref int i)
        {
            var it = _items[i];

            if (it.Kind == ItemKind.Keyword) return Allows(it.Key) && Keyword(expr, ref i);

            if (it.Kind == ItemKind.Symbol && it.Sym is { } sym)
            {
                if (sym.Kind is MathKind.Relation or MathKind.Operator)
                {
                    if (!Reaches(sym, i, expr) || !expr.LastIsOperand) return false;

                    // "divided by" keeps the school ÷ between plain numbers ("6 × 7 ÷ 2") and is a
                    // fraction in algebra ("x divided by 2 y" → x/2y), its denominator read like
                    // one after "over" (a power stays on it: "x/y²").
                    if (sym.Text == "÷")
                    {
                        if (SubExpression(i + 1, Scope.Product) is not { } bottom) return false;
                        if (MathScript.IsNumeric(expr.LastText) && MathScript.IsNumeric(bottom.Text))
                        {
                            expr.PushInfix("÷");
                            expr.PushOperand(bottom.Text);
                        }
                        else
                        {
                            expr.Collapse(expr.Count - 1, MathScript.SlashFraction(expr.LastText, bottom.Text),
                                Expr.Made.Quotient);
                        }
                        if (sym.Activates && !it.Weak) _activated = true;
                        i = bottom.Next;
                        return true;
                    }

                    if (TryOperand(i + 1) is not { } rhs) return false;

                    bool given = sym.Kind == MathKind.Relation && sym.Text == "∣";
                    bool budgeted = sym.Kind == MathKind.Relation && !given
                        && (_limitsRelations || _scope == Scope.Event);
                    if (budgeted)
                    {
                        if (_relationsInPart != 0) return false;
                        if (_scope == Scope.Event && sym.Text == "="
                            && (StartsApplication(i + 1) || !_ctx.RelationAhead(rhs.Next))) return false;
                    }

                    // "I'm bringing a plus one": the article "a" (or the pronoun "i") joined to a
                    // bare number by an operator is English — the pair renders inside a run
                    // something else activated, but never activates one itself. ("a equals 5" is
                    // a relation and still converts.)
                    bool articlePair = sym.Kind == MathKind.Operator && expr.LastStandsAlone && i > 0
                        && _items[i - 1].Kind == ItemKind.Variable && _items[i - 1].Weak
                        && expr.LastText == _items[i - 1].Text
                        && _items[i + 1].Kind == ItemKind.Number && rhs.Next == i + 2
                        && Expr.IsPlainNumber(rhs.Text);

                    // "Python 3 dot 11", "version 2 dot 1": a dot between two bare numbers is a
                    // version / decimal read aloud, not a dot product — it never activates a run
                    // on its own (review round 1 JV #2).
                    bool numberDot = sym.Text == "·" && expr.LastStandsAlone && Expr.IsPlainNumber(expr.LastText)
                        && _items[i + 1].Kind == ItemKind.Number && rhs.Next == i + 2 && Expr.IsPlainNumber(rhs.Text);

                    if (sym.Text == TimesMarker) expr.GroupTrailingOne();
                    expr.PushInfix(sym.Text, relation: sym.Kind == MathKind.Relation);
                    expr.PushOperand(rhs.Text);
                    // A glued "Kx" on either side is no evidence of mathematics (lexer 5b).
                    if (sym.Activates && !it.Weak && !articlePair && !numberDot && !_items[i + 1].Glued && !GluedBase(i))
                        _activated = true;
                    if (given) _relationsInPart = 0;
                    else if (budgeted) _relationsInPart++;
                    i = rhs.Next;
                    return true;
                }
                if (sym.Kind == MathKind.Postfix)
                {
                    // After "choose" a postfix belongs to the binomial: "C(n, k)!".
                    if (_scope == Scope.Sum || !expr.LastIsOperand) return false;
                    int start = expr.Count - 1;
                    if (IsFactorial(sym.Text))
                    {
                        // Rule 1: the sum in front of it, from its first letter on — all of it in
                        // a denominator.
                        start = expr.TailStart(Additive, Expr.Made.Binomial);
                        if (_scope != Scope.Product) start = expr.FirstLetterTerm(start);
                    }
                    if (expr.IsCompound(start)) expr.Collapse(start, $"({expr.Render(start)}){sym.Text}");
                    else expr.AttachToLast(sym.Text);
                    // "5 factorial" → 5! on its own — but only where it ENDS the dictation or
                    // sentence: "a 2 by 2 factorial design" is statistics English, and "5
                    // factorial ways" reads fine as words.
                    if (sym.Activates && i + 1 == _items.Count && _ctx.CleanEnd) _activated = true;
                    i++;
                    return true;
                }
                // A close bracket is normally swallowed by Group(); a stray one is unbalanced
                // speech, so leave it (and everything after) as plain words.
                if (sym.Kind == MathKind.Close) return false;
                if (sym.IsBigOperator) return _scope == Scope.Run && BigOperator(expr, ref i);
            }

            bool wasActivated = _activated;
            if (TryOperand(i) is { } operand)
            {
                // A grouped operand carries on without an operator only in a denominator, and
                // only as an implicit product ("over 2 pi" → "2π"); anything else belongs to the
                // construct around it.
                if (_scope != Scope.Run && expr.LastIsOperand
                    && !((_scope is Scope.Product or Scope.Side) && Expr.ContinuesImplicitly(expr.LastText, operand.Text)))
                {
                    _activated = wasActivated;
                    return false;
                }
                expr.PushOperand(operand.Text);
                if (it.Kind == ItemKind.Symbol && it.Sym?.Activates == true) _activated = true;
                i = operand.Next;
                return true;
            }
            return false;
        }

        /// Whether the expression this parser is reading carries on through the infix
        /// <paramref name="sym"/> at <paramref name="i"/> — the grouping rule, asked at every
        /// operator.
        private bool Reaches(MathSymbol sym, int i, Expr expr)
        {
            bool isRelation = sym.Kind == MathKind.Relation;
            bool isSum = !isRelation && Additive.Contains(sym.Text);
            switch (_scope)
            {
                case Scope.Run:
                    return true;
                case Scope.Side:
                    return !isRelation;
                case Scope.Sum:
                    return isSum && expr.FirstTermHasLetter
                        && !StartsApplication(i + 1) && !_ctx.StartsBinomial(i + 1);
                case Scope.Product:
                    if (!isRelation && Products.Contains(sym.Text))
                        return (_joinsProducts || expr.FirstFactorCounts) && !_ctx.ProductReachesOver(i + 1);
                    // A sum gets into a denominator only as one factor: closed by a factorial, or
                    // taken whole by a binomial.
                    return isSum && (_ctx.SumEndsInFactorial(i + 1)
                        || (_ctx.SumReachesChoose(i + 1) && _ctx.SumBehindHasLetter(i)));
                default: // Argument, Event
                    if (isRelation)
                        return (_scope == Scope.Event || sym.Text == "∣") && !StartsApplication(i + 1);
                    bool joins = isSum || (_scope == Scope.Event && SetOperations.Contains(sym.Text));
                    return joins && !StartsApplication(i + 1) && !_ctx.StartsBinomial(i + 1);
            }
        }

        /// The structural keywords a grouped operand takes in; any other ends it and is left to
        /// the construct around it ("n choose k squared" → "C(n, k)²").
        private bool Allows(Kw key) => _scope switch
        {
            Scope.Run => true,
            Scope.Side => key is not (Kw.AllOver or Kw.TendsTo),
            Scope.Sum => key == Kw.Sub,
            Scope.Argument => key is Kw.Sub or Kw.Choose,
            Scope.Product => key is Kw.Sub or Kw.Pow2 or Kw.Pow3 or Kw.Choose,
            _ => key is Kw.Sub or Kw.Sup or Kw.Power or Kw.Pow2 or Kw.Pow3 or Kw.Over or Kw.Choose,
        };

        /// True when the operand at <paramref name="k"/> is itself an application — "f of …",
        /// "sine of …", "the probability of/that …" — so it starts a new term rather than
        /// extending one.
        private bool StartsApplication(int k)
        {
            if (k < _items.Count && _items[k].Key == Kw.The) k++;
            if (k >= _items.Count) return false;
            var it = _items[k];
            if (it.Kind == ItemKind.Variable && !it.Weak && k + 1 < _items.Count && _items[k + 1].Key == Kw.Of)
                return true;
            if (it.Kind != ItemKind.Symbol || it.Sym is not { } sym) return false;
            return sym.Kind == MathKind.Function || sym.Text == "P(";
        }

        /// The operand at <paramref name="k"/> together with everything <paramref name="scope"/>
        /// lets it reach — the grouping rule's one entry point. Compound is true when it holds an
        /// infix operator, i.e. when it needs brackets as one side of a larger construct.
        private (string Text, bool Compound, int Next)? SubExpression(int k, Scope scope, bool joinsProducts = false)
        {
            var child = new Parser(_ctx, scope, joinsProducts: joinsProducts);
            if (child.TryOperand(k) is not { } first) return null;
            var expr = new Expr();
            expr.PushOperand(first.Text);
            int j = first.Next;
            while (j < _items.Count && child.Step(expr, ref j)) { }
            if (child._activated) _activated = true;
            return (expr.Render(), expr.IsCompound(0), j);
        }

        private bool Keyword(Expr expr, ref int i)
        {
            var it = _items[i];
            switch (it.Key)
            {
                case Kw.Sub or Kw.Sup or Kw.Power:
                {
                    if (!expr.LastIsOperand) return false;
                    bool isSuper = it.Key != Kw.Sub;
                    if ((isSuper ? TryExponent(i + 1) : TryScriptOperand(i + 1)) is not { } script) return false;
                    expr.ReplaceLast(MathScript.Attach(isSuper ? MathScript.PowerBase(expr.LastText) : expr.LastText,
                        MathScript.ScriptOperand(script.Text), superscript: isSuper));
                    if ((!it.Weak || PowerIsUnmistakable(i, script.Next)) && !GluedBase(i)) _activated = true;
                    i = script.Next;
                    return true;
                }

                case Kw.Pow2 or Kw.Pow3:
                    if (!expr.LastIsOperand) return false;
                    expr.ReplaceLast(MathScript.Attach(MathScript.PowerBase(expr.LastText),
                        it.Key == Kw.Pow2 ? "2" : "3", superscript: true));
                    if (!GluedBase(i)) _activated = true;
                    i++;
                    return true;

                case Kw.Root or Kw.Abs or Kw.DerivRatio:
                {
                    // All three build a self-contained operand, so TryOperand owns the one
                    // implementation and they also work in operand position ("x equals the square
                    // root of 2", "from 0 to the square root of 2"). A bare "root of" is weak:
                    // TryOperand decides whether it activates.
                    if (TryOperand(i) is not { } built) return false;
                    expr.PushOperand(built.Text);
                    if (!it.Weak) _activated = true;
                    i = built.Next;
                    return true;
                }

                case Kw.Quantity:
                {
                    // A bracket: weak, it renders inside a run something else made mathematics.
                    if (TryOperand(i) is not { } built) return false;
                    expr.PushOperand(built.Text);
                    i = built.Next;
                    return true;
                }

                case Kw.Over:
                {
                    // A division is a slash (math-notation-format.md — the format BetterScreenshot
                    // pastes too): "π/6", "1/x²", "(10 × 9 × 8)/(3 × 2 × 1)", with parentheses on a
                    // side that holds a space or an operator. How far each side reaches is rule 3.
                    if (!expr.LastIsOperand) return false;
                    if (_scope == Scope.Event && StartsApplication(i + 1)) return false;
                    int top = expr.TailStart(Products, Expr.Made.Quotient);
                    bool topIsProduct = expr.IsCompound(top);
                    if (SubExpression(i + 1, Scope.Product, joinsProducts: topIsProduct) is not { } bottom) return false;
                    // A product over a product; otherwise the factor beside "over" by the one after.
                    int from = bottom.Compound ? top : expr.Count - 1;
                    expr.Collapse(from, MathScript.SlashFraction(expr.Render(from), bottom.Text), Expr.Made.Quotient);
                    _activated = true;
                    i = bottom.Next;
                    return true;
                }

                case Kw.AllOver:
                {
                    // Rule 6: the whole side so far over the rest of the side. Weak.
                    if (!expr.LastIsOperand) return false;
                    int top = expr.SideStart();
                    if (SubExpression(i + 1, Scope.Side) is not { } bottom) return false;
                    expr.Collapse(top, MathScript.SlashFraction(expr.Render(top), bottom.Text), Expr.Made.Quotient);
                    i = bottom.Next;
                    return true;
                }

                case Kw.TendsTo:
                {
                    // "x tends to infinity" → x → ∞. Only after a LOWER-CASE variable (with its
                    // scripts: "aₙ tends to 0") or an application ("f(x)"): "type 2 tends to 3
                    // times more" and "plan B tends to 5 percent" are English, and so is "a".
                    if (!expr.LastIsOperand || !CanTend(expr.LastText) || TryOperand(i + 1) is not { } target)
                        return false;
                    expr.PushInfix("→", relation: true);
                    expr.PushOperand(target.Text);
                    _activated = true;
                    i = target.Next;
                    return true;
                }

                case Kw.Of:
                {
                    // "20 percent of 50" stays one operand inside an equation: "20% of 50 = 10".
                    // Weak: "I'm 100 percent of the way there" is still a sentence.
                    if (!expr.LastIsOperand || !expr.LastText.EndsWith('%') || TryOperand(i + 1) is not { } whole)
                        return false;
                    expr.AttachToLast(" of " + whole.Text);
                    i = whole.Next;
                    return true;
                }

                case Kw.Choose:
                {
                    // "n choose k" → the binomial "C(n, k)"; how far each side reaches is rule 2.
                    if (!expr.LastIsOperand) return false;
                    if (SubExpression(i + 1, Scope.Sum) is not { } k) return false;
                    int start = expr.FirstLetterTerm(expr.TailStart(Additive, Expr.Made.Binomial));
                    expr.Collapse(start, $"C({expr.Render(start)}, {k.Text})", Expr.Made.Binomial);
                    _activated = true;
                    i = k.Next;
                    return true;
                }

                case Kw.Deriv or Kw.PartialDeriv:
                {
                    if (TryPoweredOperand(i + 1) is not { } of) return false;
                    if (of.Next >= _items.Count || _items[of.Next].Key != Kw.Wrt) return false;
                    if (TryOperand(of.Next + 1) is not { } wrt) return false;
                    string d = it.Key == Kw.Deriv ? "d" : "∂";
                    expr.PushOperand($"{d}{Bracket(of.Text)}/{d}{Bracket(wrt.Text)}");
                    _activated = true;
                    i = wrt.Next;
                    return true;
                }

                case Kw.Limit:
                {
                    int j = i + 1;
                    if (j >= _items.Count || _items[j].Key != Kw.As) return false;
                    if (TryOperand(j + 1) is not { } variable) return false;
                    if (variable.Next >= _items.Count
                        || _items[variable.Next].Key is not (Kw.Approaches or Kw.TendsTo)) return false;
                    // allowApply: false — the "of" after the target opens the limit's BODY.
                    if (TryOperand(variable.Next + 1, allowApply: false) is not { } target) return false;
                    int afterTarget = target.Next;
                    if (afterTarget < _items.Count && _items[afterTarget].Key == Kw.Of) afterTarget++;
                    expr.PushHead(MathScript.Attach("lim", $"{variable.Text}→{target.Text}", superscript: false));
                    _activated = true;
                    i = afterTarget;
                    return true;
                }

                default:
                    return false; // "of" / "from" / "to" / "as" with nothing to attach to
            }
        }

        /// A bare "to the" is ordinary English as often as it is a power — "I gave 5 to the 3
        /// kids", "compared 2019 to the 2020 season", "we moved to the fifth floor" — so on its
        /// own it only makes a run mathematics when the exponent leaves no doubt:
        ///   • "x to the fifth power" — the word "power";
        ///   • "10 to the fifth", "x to the 3rd" — an ordinal that ENDS the sentence or the
        ///     dictation (after "the", an English ordinal is followed by its noun), except
        ///     "first"/"second" after a number: "I gave 5 to the first, 3 to the second.";
        ///   • "x to the 3", "2 to the n" — anything but two plain numbers. "10 to the 5" alone
        ///     stays words, and still renders once something else activates the run: "2 to the
        ///     10 equals 1024" → "2¹⁰ = 1024".
        private bool PowerIsUnmistakable(int i, int end)
        {
            // A signed exponent is judged by its number: "from 5 to the minus 3" is no power.
            var exponent = _items[i + 1];
            if (IsMinus(exponent) && i + 2 < _items.Count) exponent = _items[i + 2];
            var baseItem = _items[i - 1];
            bool plainBase = baseItem.Kind == ItemKind.Number || (baseItem.Kind == ItemKind.Variable && baseItem.Weak);
            return exponent.Ordinal switch
            {
                OrdinalForm.WithPower => true,
                OrdinalForm.Bare => end == _items.Count && _ctx.CleanEnd
                    && !(plainBase && exponent.Text is "1" or "2"),
                _ => !(plainBase && exponent.Kind == ItemKind.Number),
            };
        }

        private static string RootSign(string degree) => degree switch
        {
            "2" => "√",
            "3" => "∛",
            "4" => "∜",
            _ => (MathScript.Super(degree) ?? degree) + "√",
        };

        private bool BigOperator(Expr expr, ref int i)
        {
            if (_items[i].Sym is not { } sym) return false;
            string text = sym.Text;
            int j = i + 1;
            bool bounded = false;

            if (j < _items.Count && _items[j].Key == Kw.From)
            {
                if (TryBound(j + 1) is not { } lower) return false;
                // "from 0 to the square root of 2" lexes "to the" as a power keyword; as a
                // bounds separator it means the same "to".
                if (lower.Next >= _items.Count || _items[lower.Next].Key is not (Kw.To or Kw.Power)) return false;
                if (TryBound(lower.Next + 1) is not { } upper) return false;
                text = MathScript.Attach(MathScript.Attach(sym.Text, lower.Text, superscript: false),
                    upper.Text, superscript: true);
                j = upper.Next;
                bounded = true;
            }

            if (j < _items.Count && _items[j].Key == Kw.Of) j++;

            // Without bounds a big operator must at least have a body, otherwise "an integral
            // part of the plan" would turn into "an ∫ part of the plan".
            if (!bounded && TryOperand(j) is null) return false;

            expr.PushHead(text);
            // A bare "sigma" (weak) activates nothing: "six sigma of 3 teams" is English.
            if (bounded || !_items[i].Weak) _activated = true;
            i = j;
            return true;
        }

        /// An operand plus anything that multiplies into it implicitly: "i pi" → "iπ", "2 a" →
        /// "2a". Used where the whole product belongs to one slot — an exponent, a subscript, a
        /// derivative.
        private (string Text, int Next)? TryScriptOperand(int k)
        {
            if (TryOperand(k) is not { } current) return null;
            while (TryOperand(current.Next) is { } more && Expr.Juxtaposes(current.Text, more.Text))
                current = (current.Text + more.Text, more.Next);
            return current;
        }

        /// What may stand before "tends to": a lower-case variable — Greek included — with any
        /// scripts ("x", "aₙ", "θ"), or a function application ("f(x)"). Never "a" or "i".
        private static bool CanTend(string operand)
        {
            if (MathScript.IsApplication(operand)) return true;
            if (operand.Length == 0 || operand is "a" or "i") return false;
            Rune first = Rune.GetRuneAt(operand, 0);
            if (!Rune.IsLetter(first) || !Rune.IsLower(first)) return false;
            foreach (char c in operand[first.Utf16SequenceLength..])
                if (char.IsAscii(c) && (char.IsLetter(c) || char.IsDigit(c))) return false;
            return true;
        }

        /// The operand ending just before <paramref name="i"/> (past any "squared"/"cubed") is a
        /// glued "Kx".
        private bool GluedBase(int i)
        {
            int j = i - 1;
            while (j >= 0 && _items[j].Kind == ItemKind.Keyword && _items[j].Key is Kw.Pow2 or Kw.Pow3) j--;
            return j >= 0 && _items[j].Glued;
        }

        private static bool IsGreekLetter(string text) =>
            text.Length == 1 && text[0] >= 'Α' && text[0] <= 'ω';

        private static bool IsMinus(Item item) =>
            item.Kind == ItemKind.Symbol && item.Sym is { Kind: MathKind.Operator, Text: "-" };

        /// An exponent: an operand with its implicit product and any "squared"/"cubed" that
        /// follows, optionally signed with a spoken "minus" — "10 to the power of minus 3" →
        /// 10⁻³, "e to the minus x squared" → e^(-x²) (the "²" has no superscript form, so the
        /// whole exponent falls back rather than mixing styles).
        private (string Text, int Next)? TryExponent(int k)
        {
            if (k < _items.Count && IsMinus(_items[k]) && TryPoweredOperand(k + 1) is { } body)
                return ("-" + body.Text, body.Next);
            return TryPoweredOperand(k);
        }

        /// As <see cref="TryScriptOperand"/>, plus a trailing "squared"/"cubed" — without it "the
        /// derivative of x cubed with respect to x" would lose the whole construct at "cubed".
        private (string Text, int Next)? TryPoweredOperand(int k)
        {
            if (TryScriptOperand(k) is not { } current) return null;
            while (current.Next < _items.Count && _items[current.Next].Kind == ItemKind.Keyword
                   && _items[current.Next].Key is Kw.Pow2 or Kw.Pow3)
            {
                current = (MathScript.Attach(current.Text, _items[current.Next].Key == Kw.Pow2 ? "2" : "3",
                    superscript: true), current.Next + 1);
            }
            return current;
        }

        private static string Bracket(string operand) => operand.Length == 1 ? operand : $"({operand})";

        /// A summation/integration bound, which may be a small equation: "n equals 1" → "n=1".
        private (string Text, int Next)? TryBound(int k)
        {
            // allowApply: false — the "of" after a bound opens the operator's BODY ("sum from
            // i equals 1 to n OF i"), so it must never read as "n(i)".
            if (TryOperand(k, allowApply: false) is not { } current) return null;
            while (current.Next < _items.Count
                   && _items[current.Next].Kind == ItemKind.Symbol
                   && _items[current.Next].Sym is { } sym
                   && sym.Kind is MathKind.Relation or MathKind.Operator
                   && sym.Text is "=" or "+" or "-"
                   && TryOperand(current.Next + 1) is { } rhs)
            {
                current = (current.Text + sym.Text + rhs.Text, rhs.Next);
            }
            return current;
        }

        /// Reads ONE operand: a number (with its coefficient variable), a variable, a symbol
        /// value, a bracketed group, a negated/rooted operand, or a function application.
        private (string Text, int Next)? TryOperand(int k, bool allowApply = true)
        {
            if (k >= _items.Count) return null;
            var it = _items[k];

            // The constructs that build a whole operand by themselves.
            if (it.Kind == ItemKind.Keyword)
            {
                switch (it.Key)
                {
                    case Kw.The:
                        // "the" belongs to the maths phrase when the phrase is what we're reading.
                        return TryOperand(k + 1);

                    case Kw.Root:
                    {
                        int j = k + 1;
                        if (j < _items.Count && _items[j].Key == Kw.Of) j++;
                        if (it.Weak)
                        {
                            // Bare "root of": the radicand takes its power ("the root of K cubed"
                            // → √K³), and only a powered radicand makes it mathematics on its own
                            // — "the root of 3 problems" stays words unless the run is an equation.
                            if (TryOperand(j) is not { } plain || TryPoweredOperand(j) is not { } powered) return null;
                            if (powered.Next > plain.Next) _activated = true;
                            return (MathScript.Radical(RootSign(it.Text), powered.Text), powered.Next);
                        }
                        if (TryOperand(j) is not { } radicand) return null;
                        _activated = true;
                        return (MathScript.Radical(RootSign(it.Text), radicand.Text), radicand.Next);
                    }

                    case Kw.Abs:
                    {
                        if (TryOperand(k + 1) is not { } inner) return null;
                        _activated = true;
                        return ("|" + inner.Text + "|", inner.Next);
                    }

                    case Kw.DerivRatio:
                        // "d y by d x" → dy/dx: never ordinary speech, so it activates.
                        _activated = true;
                        return (it.Text, k + 1);

                    case Kw.Quantity:
                        return Quantity(k);

                    default:
                        return null;
                }
            }

            switch (it.Kind)
            {
                case ItemKind.Number:
                {
                    string text = it.Text;
                    int next = k + 1;
                    // "7 n" → "7n" (a coefficient, but never on the weak "a")
                    if (next < _items.Count && _items[next].Kind == ItemKind.Variable
                        && !_items[next].Weak && next != _ctx.WeakCutoff)
                    {
                        text += _items[next].Text;
                        next++;
                    }
                    return (text, next);
                }

                case ItemKind.Variable:
                {
                    if (it.Weak && k == _ctx.WeakCutoff) return null;
                    string name = it.Text;
                    int next = k + 1;
                    // "f prime of x" → f′(x), "f inverse of x" → f⁻¹(x): the mark belongs to the
                    // function's NAME when "of" follows it.
                    bool marked = false;
                    if (allowApply && !it.Weak && next + 1 < _items.Count
                        && _items[next].Kind == ItemKind.Symbol
                        && _items[next].Sym is { Kind: MathKind.Postfix } mark
                        && FunctionMarks.Contains(mark.Text) && _items[next + 1].Key == Kw.Of)
                    {
                        name += mark.Text;
                        next++;
                        marked = true;
                    }
                    // "f of x" → "f(x)" — and, by rules 4 and 5, "f of n minus 1" → "f(n - 1)",
                    // "P of X less than 3" → "P(X < 3)". Only a real (non-weak) variable may be
                    // applied like a function: "5 of 10" and "a of the" must stay words. A bare
                    // "f of x" never activates on its own — something else in the run has to be
                    // mathematics — but a MARKED one does: "f inverse of x" is never English.
                    if (allowApply && !it.Weak && next < _items.Count && _items[next].Key == Kw.Of
                        && SubExpression(next + 1, it.Text == "P" ? Scope.Event : Scope.Argument) is { } arg)
                    {
                        if (marked) _activated = true;
                        return ($"{name}({arg.Text})", arg.Next);
                    }
                    if (marked) return (it.Text, k + 1); // no argument after all: the mark is a postfix
                    return (name, next);
                }

                case ItemKind.Symbol:
                {
                    if (it.Sym is not { } sym) return null;
                    if (sym.Kind == MathKind.Operand)
                    {
                        // "sigma of 3" → σ(3): a Greek letter applied with "of", like "f of x". Weak.
                        if (allowApply && IsGreekLetter(sym.Text) && k + 1 < _items.Count
                            && _items[k + 1].Key == Kw.Of && SubExpression(k + 2, Scope.Argument) is { } arg)
                            return ($"{sym.Text}({arg.Text})", arg.Next);
                        return (sym.Text, k + 1);
                    }
                    if (sym.Kind == MathKind.Open) return Group(k);
                    if (sym.Kind == MathKind.Prefix && !sym.IsBigOperator)
                    {
                        if (TryOperand(k + 1) is not { } inner) return null;
                        if (sym.Text == "√") return (MathScript.Radical(sym.Text, inner.Text), inner.Next);
                        return (sym.Text + inner.Text, inner.Next);
                    }
                    if (sym.Kind == MathKind.Function)
                    {
                        int j = k + 1;
                        string name = sym.Text;
                        // "log base 2 of x" — and "log sub 2 of x", which is the same thing said
                        // differently. A named base ACTIVATES: a function with an explicit base is
                        // unambiguously mathematics, so it converts on its own ("log base 2 of 8"),
                        // where a bare application stays weak ("the log of the tree").
                        // allowApply: false — the "of" after the base opens the ARGUMENT ("log
                        // base n OF x"), so the base must never read as "n(x)".
                        if (j < _items.Count && _items[j].Key is Kw.Base or Kw.Sub
                            && TryOperand(j + 1, allowApply: false) is { } baseOperand)
                        {
                            name = MathScript.Attach(name, baseOperand.Text, superscript: false);
                            j = baseOperand.Next;
                            _activated = true;
                        }
                        // "sine squared theta" → "sin²θ" — the power belongs to the name, and a
                        // powered function is never English, so it activates.
                        bool powered = false;
                        if (j < _items.Count && _items[j].Kind == ItemKind.Keyword)
                        {
                            if (_items[j].Key is Kw.Pow2 or Kw.Pow3)
                            {
                                name = MathScript.Attach(name, _items[j].Key == Kw.Pow2 ? "2" : "3", superscript: true);
                                j++;
                                powered = true;
                            }
                            else if (_items[j].Key == Kw.Power && TryScriptOperand(j + 1) is { } power)
                            {
                                name = MathScript.Attach(name, power.Text, superscript: true);
                                j = power.Next;
                                powered = true;
                            }
                        }
                        if (j < _items.Count && _items[j].Key == Kw.Of) j++;
                        // Rules 4 and 5: "the variance of X plus Y" → "Var(X + Y)", "the
                        // probability of A given B" → "P(A ∣ B)".
                        if (ArgumentScopes.TryGetValue(sym.Text, out var scope))
                        {
                            if (SubExpression(j, scope) is not { } whole) return null;
                            return ($"{name}({whole.Text})", whole.Next);
                        }
                        // One operand with its implicit product ("cosine 2 theta" → cos 2θ) — the
                        // SMALLEST reading: "sine of x plus 1" is sin x + 1; say "sine of the
                        // quantity x plus 1" for sin(x + 1).
                        if (TryScriptOperand(j) is not { } argument) return null;
                        // "the natural log of 2" → ln 2 on its own: "natural log" is never English.
                        if (powered || sym.Text == "ln") _activated = true;
                        return (MathScript.ApplyFunction(name, argument.Text), argument.Next);
                    }
                    return null;
                }

                default:
                    return null;
            }
        }

        /// A bracketed group. An unclosed one (the speaker forgot "close paren") is closed at the
        /// end of the run rather than abandoning the whole construct — or, like an event, before
        /// its second relation ("the probability that X is at most 3 equals 0.65" →
        /// "P(X ≤ 3) = 0.65").
        private (string Text, int Next)? Group(int k)
        {
            if (_items[k].Sym?.Text is not { } open) return null;
            int depth = 0, end = -1;
            for (int j = k; j < _items.Count; j++)
            {
                if (_items[j].Kind != ItemKind.Symbol || _items[j].Sym is not { } sym) continue;
                if (sym.Kind == MathKind.Open) depth++;
                else if (sym.Kind == MathKind.Close)
                {
                    depth--;
                    if (depth == 0) { end = j; break; }
                }
            }

            // An unclosed bracket also ends where "all over" takes the whole side (rule 6).
            int innerEnd = end < 0 ? _items.Count : end;
            if (end < 0)
            {
                for (int j = k + 1; j < _items.Count; j++)
                    if (_items[j].Key == Kw.AllOver) { innerEnd = j; break; }
            }
            string close = end < 0 ? Closing(open) : (_items[end].Sym?.Text ?? Closing(open));
            if (innerEnd <= k + 1) return null;

            var inside = new Run(_items.GetRange(k + 1, innerEnd - k - 1), -1, end < 0 ? _ctx.CleanEnd : true);
            var inner = new Parser(inside, limitsRelations: end < 0);
            var (body, innerActivated, used) = inner.RunFrom(0);
            if (used == 0) return null;
            _activated = _activated || innerActivated;

            return (open + body + close, end < 0 ? k + 1 + used : end + 1);
        }

        /// "the quantity …" (rule 6): a spoken open bracket. It closes at a close bracket, else
        /// just before the next relation or "all over", else at the end of the run — and it is
        /// only a group when what it holds is more than one term, so "the quantity x equals 5"
        /// is left as words.
        private (string Text, int Next)? Quantity(int k)
        {
            int depth = 0, end = _items.Count;
            bool closed = false;
            for (int j = k + 1; j < _items.Count; j++)
            {
                var item = _items[j];
                if (item.Kind == ItemKind.Symbol && item.Sym is { } sym)
                {
                    if (sym.Kind == MathKind.Open) depth++;
                    else if (sym.Kind == MathKind.Close)
                    {
                        if (depth == 0) { end = j; closed = true; break; }
                        depth--;
                    }
                    else if (sym.Kind == MathKind.Relation && depth == 0) { end = j; break; }
                }
                else if (depth == 0 && item.Key == Kw.AllOver) { end = j; break; }
            }
            if (end <= k + 1) return null;

            var inside = new Run(_items.GetRange(k + 1, end - k - 1), -1, end == _items.Count ? _ctx.CleanEnd : true);
            var (body, innerActivated, used) = new Parser(inside).RunFrom(0);
            if (used == 0 || (closed && used != end - k - 1)) return null;
            int next = closed ? end + 1 : k + 1 + used;
            _activated = _activated || innerActivated;
            if (MathScript.NeedsGrouping(body, leadingSign: false)) return ("(" + body + ")", next);
            // One term built from several spoken pieces ("the quantity 5 over 6 to the 4" →
            // (5/6)⁴) needs no extra brackets; a lone word after it is no group at all.
            if (used <= 1) return null;
            return (body, next);
        }

        private static string Closing(string open) => open switch
        {
            "[" => "]",
            "{" => "}",
            _ => ")",
        };
    }
}
