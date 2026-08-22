using System.Text;
using System.Text.RegularExpressions;

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
/// Two extra rules close the gaps that the operand requirement alone leaves open:
///   • "a"/"A" are only WEAK operands, and a weak operand is refused when it is the last thing
///     before an ordinary word — which is exactly what makes "two times a day" safe while
///     "a subscript n equals 1 plus 7n" and "a plus b" still work.
///   • "I" is never a variable, and "sum"/"product" only count as ∑/∏ when bounds follow, so
///     "the sum of my fears" and "an integral part of the plan" never activate.
///
/// When nothing activates, <see cref="Convert"/> returns the input string itself — untouched,
/// not re-joined — so the feature is provably invisible outside mathematics.
///
/// ── Escape hatch ───────────────────────────────────────────────────────────────────────
/// Saying "start equation … end equation" forces every run between the markers to convert
/// (and drops the markers), for the rare symbol that is too ordinary a word to auto-activate.
///
/// The vocabulary lives in <see cref="MathSymbols"/>, number words in
/// <see cref="SpokenNumbers"/>, and Unicode script rendering in <see cref="MathScript"/>.
/// This file owns the grammar and the activation rules.
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

            if (toks[it.Start + it.Count - 1].Trail.Length > 0)
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
                ok = string.Equals(cores[i + k], words[k], StringComparison.OrdinalIgnoreCase);
            if (ok) { consumed = words.Length; return true; }
        }
        consumed = 0;
        return false;
    }

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

    /// A structural construct the ENGINE parses (with its operands) rather than the
    /// vocabulary looking it up — see <see cref="MathSymbols.ReservedPhrases"/>.
    private enum Kw
    {
        None, Sub, Sup, Pow2, Pow3, Power, Root, Over, From, To, Of,
        Abs, Deriv, PartialDeriv, Wrt, Limit, As, Approaches, Base, Choose, The,
    }

    private sealed record Item(
        ItemKind Kind, string Text, int Start, int Count,
        MathSymbol? Sym = null, Kw Key = Kw.None, bool Weak = false);

    private static readonly Dictionary<string, (Kw Key, string Payload)> Keywords =
        new(StringComparer.OrdinalIgnoreCase)
        {
            // NOTE: no "the ..." variants — a structural construct never swallows a spoken
            // word. "the derivative of y with respect to x" → "the dy/dx", exactly like
            // "the square root of 16" → "the √16". (Vocabulary NAMES may include an article,
            // e.g. "the reals" → ℝ, because there the article is part of the name.)
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
            // alpha version" and "go to the store" can never take it.
            ["to the"] = (Kw.Power, ""),
            ["base"] = (Kw.Base, ""),          // after a function: "log base 2 of x" → log₂(x)
            // "the" belongs to the maths phrase when it sits in OPERAND position
            // ("x equals the square root of 2" → "x = √2") and to the sentence anywhere else
            // ("the sum from ..." keeps its "the"). Lexing it as a keyword lets the parser
            // make that distinction instead of the run simply ending here.
            ["the"] = (Kw.The, ""),
            ["choose"] = (Kw.Choose, ""),      // "n choose k" -> C(n, k)
            ["square root of"] = (Kw.Root, "2"),
            ["square root"] = (Kw.Root, "2"),
            ["cube root of"] = (Kw.Root, "3"),
            ["cube root"] = (Kw.Root, "3"),
            ["over"] = (Kw.Over, ""),
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
            ["tends to"] = (Kw.Approaches, ""),
            ["goes to"] = (Kw.Approaches, ""),
        };

    private static readonly int MaxKeywordWords =
        Keywords.Keys.Max(k => k.Count(c => c == ' ') + 1);

    /// Big operators whose spoken name is an ordinary English noun: only mathematics when
    /// bounds follow ("sum from n equals 1 to ten"), never on their own.
    private static readonly Dictionary<string, string> BoundedOnly =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["sum"] = "∑",
            ["sums"] = "∑",
            ["product"] = "∏",
            ["products"] = "∏",
        };

    /// "7n", "3x" — whisper writes coefficients glued to the variable.
    private static readonly Regex Coefficient = new(@"^\d+(\.\d+)?[a-zA-Z]$", RegexOptions.Compiled);

    private static List<Item> Lex(List<Tok> toks)
    {
        var cores = toks.Select(t => t.Core).ToList();
        var items = new List<Item>();

        for (int i = 0; i < cores.Count;)
        {
            string core = cores[i];
            if (core.Length == 0) { items.Add(new Item(ItemKind.Word, "", i, 1)); i++; continue; }

            // 1) "<ordinal> root of x" → ⁿ√x
            var ord = SpokenNumbers.TryReadOrdinal(cores, i);
            if (ord is { } o && i + o.Consumed < cores.Count
                && cores[i + o.Consumed].Equals("root", StringComparison.OrdinalIgnoreCase))
            {
                int len = o.Consumed + 1;
                if (i + len < cores.Count && cores[i + len].Equals("of", StringComparison.OrdinalIgnoreCase)) len++;
                items.Add(new Item(ItemKind.Keyword, o.Digits, i, len, Key: Kw.Root));
                i += len;
                continue;
            }

            // 2) "sum"/"product" — only a big operator when bounds follow
            if (BoundedOnly.TryGetValue(core, out string? bigOp)
                && i + 1 < cores.Count && cores[i + 1].Equals("from", StringComparison.OrdinalIgnoreCase))
            {
                items.Add(new Item(ItemKind.Symbol, bigOp, i, 1, new MathSymbol(bigOp, MathKind.Prefix)));
                i++;
                continue;
            }

            // 3) numbers ("twenty five" → 25, "7", "7n")
            if (Coefficient.IsMatch(core))
            {
                items.Add(new Item(ItemKind.Number, core, i, 1));
                i++;
                continue;
            }
            // "one half" / "three quarters" is ONE operand ("1/2", "3/4"). Weak like any number,
            // so "three quarters of the class" never activates and stays words.
            var frac = SpokenNumbers.TryReadFraction(cores, i);
            if (frac is { } f)
            {
                items.Add(new Item(ItemKind.Number, f.Digits, i, f.Consumed));
                i += f.Consumed;
                continue;
            }
            var num = SpokenNumbers.TryRead(cores, i);
            if (num is { } n)
            {
                items.Add(new Item(ItemKind.Number, n.Digits, i, n.Consumed));
                i += n.Consumed;
                continue;
            }

            // 4) structural keywords vs the vocabulary — the LONGER phrase wins, so the
            //    vocabulary name "the reals" (ℝ) beats the bare keyword "the"; a tie goes to
            //    the engine, which owns the reserved forms.
            bool hasKw = TryKeyword(cores, i, out Kw key, out string payload, out int kwLen);
            bool hasSym = MathSymbols.TryMatch(cores, i, out var sym, out int symLen);
            if (hasKw && !(hasSym && symLen > kwLen))
            {
                items.Add(new Item(ItemKind.Keyword, payload, i, kwLen, Key: key));
                i += kwLen;
                continue;
            }
            if (hasSym)
            {
                items.Add(new Item(ItemKind.Symbol, sym.Text, i, symLen, sym));
                i += symLen;
                continue;
            }

            // 5) single-letter variables ("I" is the pronoun, never a variable)
            if (core.Length == 1 && char.IsAsciiLetter(core[0]) && core != "I")
            {
                items.Add(new Item(ItemKind.Variable, core, i, 1, Weak: core is "a" or "A"));
                i++;
                continue;
            }

            items.Add(new Item(ItemKind.Word, core, i, 1));
            i++;
        }
        return items;
    }

    private static bool TryKeyword(
        List<string> cores, int i, out Kw key, out string payload, out int consumed)
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

            int pos = 0;
            while (pos < buf.Count)
            {
                var parser = new Parser(buf, weakCutoff);
                var (text, activated, used) = parser.Run(pos);
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

    // ─────────────────────────────── expression building ───────────────────────────────

    /// The rendered pieces of one run, plus the spacing rules that join them:
    /// relations and operators get air ("1 + 7n"), scripts and postfixes bind tight ("aₙ", "5!"),
    /// and a number followed by a letter is a coefficient ("7n", "2π").
    private sealed class Expr
    {
        private readonly List<(string Text, bool Operand, bool Tight)> _parts = new();
        private bool _tightNext;

        public bool LastIsOperand => _parts.Count > 0 && _parts[^1].Operand;
        public string LastText => _parts[^1].Text;

        public void PushOperand(string text)
        {
            bool tight = _tightNext
                || (_parts.Count > 0 && _parts[^1].Operand && Juxtaposes(_parts[^1].Text, text));
            _parts.Add((text, true, tight));
            _tightNext = false;
        }

        /// A big operator or a "lim" head: the body that follows is separated by a space.
        public void PushHead(string text)
        {
            _parts.Add((text, false, _tightNext));
            _tightNext = false;
        }

        public void PushInfix(string text)
        {
            _parts.Add((text, false, false));
            _tightNext = false;
        }

        public void PushOpen(string text)
        {
            _parts.Add((text, false, _tightNext));
            _tightNext = true;
        }

        public void AttachToLast(string suffix) => ReplaceLast(_parts[^1].Text + suffix);

        public void ReplaceLast(string text) => _parts[^1] = (text, true, _parts[^1].Tight);

        public override string ToString()
        {
            var sb = new StringBuilder();
            for (int i = 0; i < _parts.Count; i++)
            {
                if (i > 0 && !_parts[i].Tight) sb.Append(' ');
                sb.Append(_parts[i].Text);
            }
            return sb.ToString();
        }

        /// Two ATOMIC operands side by side are implicit multiplication and are written closed
        /// up: "7 n" → "7n", "2 π" → "2π", "delta x" → "δx". Anything already composite
        /// ("aₙ", "sin(x)", "1/2") keeps its space, where the product is clearer spaced out.
        private static bool Juxtaposes(string left, string right)
            => IsSingleLetter(right) && (IsSingleLetter(left) || IsPlainNumber(left));

        private static bool IsSingleLetter(string s) => s.Length == 1 && char.IsLetter(s[0]);

        private static bool IsPlainNumber(string s)
            => s.Length > 0 && s.All(c => char.IsAsciiDigit(c) || c == '.');
    }

    // ─────────────────────────────── parsing ───────────────────────────────

    /// Walks one run left to right, folding items into an <see cref="Expr"/>. Stops at the
    /// first item it cannot consume and reports how far it got, so the caller can hand the
    /// leftovers back out as plain words.
    private sealed class Parser(List<Item> items, int weakCutoff)
    {
        private bool _activated;

        public (string Text, bool Activated, int Used) Run(int start)
        {
            var expr = new Expr();
            int i = start;
            while (i < items.Count && Step(expr, ref i)) { }
            return (expr.ToString(), _activated, i - start);
        }

        private bool Step(Expr expr, ref int i)
        {
            var it = items[i];

            if (it.Kind == ItemKind.Keyword) return Keyword(expr, ref i);

            if (it.Kind == ItemKind.Symbol)
            {
                var sym = it.Sym!;
                if (sym.Kind is MathKind.Relation or MathKind.Operator)
                {
                    if (!expr.LastIsOperand) return false;
                    if (!TryOperand(i + 1, out string rhs, out int after)) return false;
                    expr.PushInfix(sym.Text);
                    expr.PushOperand(rhs);
                    _activated = true;
                    i = after;
                    return true;
                }
                if (sym.Kind == MathKind.Postfix)
                {
                    if (!expr.LastIsOperand) return false;
                    expr.AttachToLast(sym.Text);
                    i++;
                    return true;
                }
                // A close bracket is normally swallowed by Group(); a stray one is unbalanced
                // speech, so leave it (and everything after) as plain words.
                if (sym.Kind == MathKind.Close) return false;
                if (sym.IsBigOperator) return BigOperator(expr, ref i);
            }

            if (TryOperand(i, out string operand, out int next))
            {
                expr.PushOperand(operand);
                if (it.Kind == ItemKind.Symbol && it.Sym!.Activates) _activated = true;
                i = next;
                return true;
            }
            return false;
        }

        private bool Keyword(Expr expr, ref int i)
        {
            var it = items[i];
            switch (it.Key)
            {
                case Kw.Sub:
                case Kw.Sup:
                case Kw.Power:
                {
                    if (!expr.LastIsOperand) return false;
                    if (!TryOperand(i + 1, out string script, out int after)) return false;
                    expr.ReplaceLast(MathScript.Attach(expr.LastText, script, it.Key != Kw.Sub));
                    _activated = true;
                    i = after;
                    return true;
                }
                case Kw.Pow2:
                case Kw.Pow3:
                {
                    if (!expr.LastIsOperand) return false;
                    expr.ReplaceLast(MathScript.Attach(expr.LastText, it.Key == Kw.Pow2 ? "2" : "3", true));
                    _activated = true;
                    i++;
                    return true;
                }
                case Kw.Root:
                case Kw.Abs:
                {
                    // Both build a self-contained operand, so TryOperand owns the one
                    // implementation and they also work in operand position ("x equals the
                    // square root of 2", "from 0 to the square root of 2").
                    if (!TryOperand(i, out string built, out int after)) return false;
                    expr.PushOperand(built);
                    _activated = true;
                    i = after;
                    return true;
                }
                case Kw.Over:
                {
                    if (!expr.LastIsOperand) return false;
                    if (!TryOperand(i + 1, out string denominator, out int after)) return false;
                    expr.AttachToLast("/" + denominator);
                    _activated = true;
                    i = after;
                    return true;
                }
                case Kw.Choose:
                {
                    if (!expr.LastIsOperand) return false;
                    if (!TryOperand(i + 1, out string k, out int afterK)) return false;
                    expr.ReplaceLast($"C({expr.LastText}, {k})");
                    _activated = true;
                    i = afterK;
                    return true;
                }
                case Kw.Deriv:
                case Kw.PartialDeriv:
                {
                    if (!TryOperand(i + 1, out string of, out int after)) return false;
                    if (after >= items.Count || items[after].Key != Kw.Wrt) return false;
                    if (!TryOperand(after + 1, out string wrt, out int end)) return false;
                    string d = it.Key == Kw.Deriv ? "d" : "∂";
                    expr.PushOperand($"{d}{of}/{d}{wrt}");
                    _activated = true;
                    i = end;
                    return true;
                }
                case Kw.Limit:
                {
                    int j = i + 1;
                    if (j >= items.Count || items[j].Key != Kw.As) return false;
                    if (!TryOperand(j + 1, out string variable, out int afterVar)) return false;
                    if (afterVar >= items.Count || items[afterVar].Key != Kw.Approaches) return false;
                    if (!TryOperand(afterVar + 1, out string target, out int afterTarget)) return false;
                    if (afterTarget < items.Count && items[afterTarget].Key == Kw.Of) afterTarget++;
                    expr.PushHead(MathScript.Attach("lim", $"{variable}→{target}", superscript: false));
                    _activated = true;
                    i = afterTarget;
                    return true;
                }
                default:
                    return false; // "of" / "from" / "to" / "as" with nothing to attach to
            }
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
            var sym = items[i].Sym!;
            string text = sym.Text;
            int j = i + 1;
            bool bounded = false;

            if (j < items.Count && items[j].Key == Kw.From)
            {
                if (!TryBound(j + 1, out string lower, out int afterLower)) return false;
                // "from 0 to the square root of 2" lexes "to the" as a power keyword; as a
                // bounds separator it means the same "to".
                if (afterLower >= items.Count
                    || items[afterLower].Key is not (Kw.To or Kw.Power)) return false;
                if (!TryBound(afterLower + 1, out string upper, out int afterUpper)) return false;
                text = MathScript.Attach(MathScript.Attach(sym.Text, lower, false), upper, true);
                j = afterUpper;
                bounded = true;
            }

            if (j < items.Count && items[j].Key == Kw.Of) j++;

            // Without bounds a big operator must at least have a body, otherwise "an integral
            // part of the plan" would turn into "an ∫ part of the plan".
            if (!bounded && !TryOperand(j, out _, out _)) return false;

            expr.PushHead(text);
            _activated = true;
            i = j;
            return true;
        }

        /// A summation/integration bound, which may be a small equation: "n equals 1" → "n=1".
        private bool TryBound(int k, out string text, out int next)
        {
            if (!TryOperand(k, out text, out next)) return false;
            while (next < items.Count
                   && items[next].Kind == ItemKind.Symbol
                   && items[next].Sym!.Kind is MathKind.Relation or MathKind.Operator
                   && items[next].Sym!.Text is "=" or "+" or "-"
                   && TryOperand(next + 1, out string rhs, out int after))
            {
                text += items[next].Sym!.Text + rhs;
                next = after;
            }
            return true;
        }

        /// Reads ONE operand: a number (with its coefficient variable), a variable, a symbol
        /// value, a bracketed group, a negated/rooted operand, or a function application.
        private bool TryOperand(int k, out string text, out int next)
        {
            text = "";
            next = k;
            if (k >= items.Count) return false;
            var it = items[k];

            // "the" is part of the maths phrase when the phrase is what we are reading.
            if (it.Kind == ItemKind.Keyword && it.Key == Kw.The)
                return TryOperand(k + 1, out text, out next);

            if (it.Kind == ItemKind.Keyword && it.Key == Kw.Root)
            {
                int j = k + 1;
                if (j < items.Count && items[j].Key == Kw.Of) j++;
                if (!TryOperand(j, out string radicand, out next)) return false;
                text = RootSign(it.Text) + radicand;
                _activated = true;
                return true;
            }
            if (it.Kind == ItemKind.Keyword && it.Key == Kw.Abs)
            {
                if (!TryOperand(k + 1, out string inner, out next)) return false;
                text = "|" + inner + "|";
                _activated = true;
                return true;
            }

            switch (it.Kind)
            {
                case ItemKind.Number:
                    text = it.Text;
                    next = k + 1;
                    // "7 n" → "7n" (a coefficient, but never on the weak "a")
                    if (next < items.Count && items[next].Kind == ItemKind.Variable
                        && !items[next].Weak && next != weakCutoff)
                    {
                        text += items[next].Text;
                        next++;
                    }
                    return true;

                case ItemKind.Variable:
                {
                    if (it.Weak && k == weakCutoff) return false;
                    text = it.Text;
                    next = k + 1;
                    // "f of x" → "f(x)". Only a real (non-weak) variable may be applied like a
                    // function: "5 of 10" and "a of the" must stay words. Never activating on
                    // its own — something else in the run has to be mathematics.
                    if (!it.Weak && next < items.Count && items[next].Key == Kw.Of
                        && TryOperand(next + 1, out string arg, out int afterArg))
                    {
                        text = $"{it.Text}({arg})";
                        next = afterArg;
                    }
                    return true;
                }

                case ItemKind.Symbol:
                {
                    var sym = it.Sym!;
                    if (sym.Kind == MathKind.Operand)
                    {
                        text = sym.Text;
                        next = k + 1;
                        return true;
                    }
                    if (sym.Kind == MathKind.Open) return Group(k, out text, out next);
                    if (sym.Kind == MathKind.Prefix && !sym.IsBigOperator)
                    {
                        if (!TryOperand(k + 1, out string inner, out next)) return false;
                        text = sym.Text + inner;
                        return true;
                    }
                    if (sym.Kind == MathKind.Function)
                    {
                        int j = k + 1;
                        string name = sym.Text;
                        // "log base 2 of x"
                        if (j < items.Count && items[j].Key == Kw.Base
                            && TryOperand(j + 1, out string b, out int afterBase))
                        {
                            name = MathScript.Attach(name, b, superscript: false);
                            j = afterBase;
                        }
                        if (j < items.Count && items[j].Key == Kw.Of) j++;
                        if (!TryOperand(j, out string arg, out next)) return false;
                        text = $"{name}({arg})";
                        return true;
                    }
                    return false;
                }

                default:
                    return false;
            }
        }

        /// A bracketed group. An unclosed one (the speaker forgot "close paren") is closed at
        /// the end of the run rather than abandoning the whole construct.
        private bool Group(int k, out string text, out int next)
        {
            string open = items[k].Sym!.Text;
            int depth = 0, end = -1;
            for (int j = k; j < items.Count; j++)
            {
                if (items[j].Kind != ItemKind.Symbol) continue;
                if (items[j].Sym!.Kind == MathKind.Open) depth++;
                else if (items[j].Sym!.Kind == MathKind.Close && --depth == 0) { end = j; break; }
            }

            int innerEnd = end < 0 ? items.Count : end;
            string close = end < 0 ? Closing(open) : items[end].Sym!.Text;
            if (innerEnd <= k + 1) { text = ""; next = k; return false; }

            var inner = new Parser(items.GetRange(k + 1, innerEnd - k - 1), -1);
            var (body, activated, used) = inner.Run(0);
            if (used == 0) { text = ""; next = k; return false; }
            _activated |= activated;

            text = open + body + close;
            next = (end < 0 ? k + 1 + used : end + 1);
            return true;
        }

        private static string Closing(string open) => open switch
        {
            "[" => "]",
            "{" => "}",
            _ => ")",
        };
    }
}
