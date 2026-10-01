# Core / Math — spoken mathematics → real notation

Windows-only (no macOS counterpart). Turns dictated equations into the symbols:
`"a subscript n equals 1 plus 7n"` → `"aₙ = 1 + 7n"`. One toggle in Settings
(`SettingsState.MathNotation`, schema v6, **default ON**), applied by `VoiceCoordinator` as the
LAST step of post-processing.

## The one hard requirement
It must not bleed into ordinary talking. That is a **structural** rule, not a classifier:

> A word only becomes a symbol inside a **run**, and a run only converts when an **ACTIVATING**
> construct in it found its **OPERANDS**.

- A *run* = consecutive words that all lexed as maths. Any ordinary word or punctuation ends it.
- *Activating* = an infix relation/operator with an operand on BOTH sides, a prefix with one
  after it, or a structural construct (script, power, root, fraction, bounds, derivative,
  limit, absolute value, `choose`).
- *Weak* (never activates, only renders inside an already-activated run) = π, α, %, °, `sin`,
  brackets, number words, and **signs** (`negative`).
- When nothing activates, `Convert` returns the **same string instance** — the guarantee that
  ordinary dictation is untouched.

Three rules close the holes the operand requirement leaves: `"a"`/`"A"` are weak operands and
are refused right before an ordinary word (`"two times a day"`); `"I"` is never a variable;
`"sum"`/`"product"` are only ∑/∏ with bounds (`"the sum of my fears"`).

## How the notation reads — the SHARED format (parity rows 22–25, 2026-10-02)
Since the Mac port (`docs/mac-reference/math-notation-format.md` is the normative spec, the same
format BetterScreenshot's Capture Text pastes) this engine is a 1:1 port of the Mac's
`MathSpeech.swift` / `MathScript.swift` / `MathSymbols.swift`. It REPLACES the §7 #48 rules (`·`
for times, stacked `½`/`÷` for over):
- **"over" is a slash**, bracketed only where needed: `a + b/2`, `(a + b)/2` ("all over"),
  `12/(2T)` (a juxtaposed denominator is bracketed), `1/x²`, `(5/6)⁴` (`MathScript.SlashFraction`,
  `NeedsGrouping`, `PowerBase`). "divided by" keeps `÷` between plain numbers (`6 × 7 ÷ 2`) and is a
  slash in algebra (`x/(2y)`). `MathScript.Fraction` (stacked) is kept but unused.
- **"times"** lexes to the internal marker `*` and is laid out at render time
  (`MathScript.ProductSeparator`): `×` between numbers (`6 × 7`), juxtaposition between letter terms
  (`2y`, `(n - 1)d`, `πr²`), a space before a trig/log function or a differential. `·` is ONLY the dot
  product. Whisper's "3 x 4" is a weak times.
- **Functions**: `sin θ`, `sin²θ`, `log₂8`, `ln 2` — brackets only for a multi-term argument
  (`ApplyFunction`). **Roots**: `√x`, `√(2x)` (`Radical`). Every construct takes the SMALLEST
  reading unless "all over" / "the quantity" widen it (`√x + 1` vs `√(x + 1)`).
- **Grouping rule** (doc comment on `Parser`): choose / factorial / over / "f of" / "P of" / "given"
  reach as far as a student means them — `C(n, n - k)`, `n!/(k!(n - k)!)`, `P(A ∣ B)`, `f(n - 1)`.
- **Leak fixes**: bare "to the" is weak unless the exponent is unmistakable ("I gave 5 to the 3
  kids" stays words); "per" is a weak operator; "more than" is not `>`; "a plus one" never activates;
  "5 factorial" activates only at the clean end of a sentence; "tends to" only after a lower-case
  variable or `f(x)`.
- **David's 2026-09-29 dictation**: bare "root of" is weak (activates only with a powered radicand),
  whisper's glued "Kx" is a weak glued variable, **"sigma" is the sum sign ∑** (the letter σ is
  "lowercase/small sigma"; bare sigma is weak without bounds), a Greek letter + "of" is an application.
- Kept from §7 #48: a log with a named base activates; "u n" is a sequence term `uₙ`; brackets take
  either word order and a comma right after an opening bracket does not end the run.

## Files
- `MathSpeech.cs` — tokenizer, run splitting, parser, renderer. `Convert(string)` is the API.
- `MathSymbols.cs` — the vocabulary (spoken form → symbol + kind). Data only.
- `MathSymbol.cs` — `MathKind` + what `Activates`.
- `MathScript.cs` — Unicode super/subscript (all-or-nothing, `^`/`_` fallback) + the layout helpers of the shared format (slash fractions, radicals, function application, product separator). Scans Runes, not chars.
- `SpokenNumbers.cs` — number words → digits.

## Traps
- **`MathSymbols.ReservedPhrases` are parsed structurally by the engine** — never add them as
  vocabulary keys (`MathSpeechTests` fails if you do).
- Adding a Relation/Operator/Prefix is the only way to create a false positive. Weak kinds are
  free; activating kinds need the "could this sit between two operand-looking words in ordinary
  speech?" audit.
- **A vocabulary key can silently SHADOW a construct** and cost it its activation. `"log base 2"`
  was a key, so longest-match returned a ready-made (weak) `log₂` and the `base` construct never
  ran — `"log base 2 of 8"` stayed words. Never spell out a phrase the engine already parses.
- The engine runs **after** `TextProcessor.Process`, deliberately: tone formatting, filler
  removal and the correction dictionaries all work on English words, so no symbol can be
  mangled by them. (Cosmetic consequence: in Formal tone a sentence-initial variable is
  capitalised, `"X² = 4."`)

## Verify
- `dotnet test windows/JVoice.Tests` — `MathSpeechTests` is the spec (conversions + prose that
  must come back byte-identical), plus `MathSymbolsTests` / `SpokenNumbersTests`.
- `JVoice.exe --math-probe "<text>"` (or piped stdin) — one line per input, `CHANGED|…` / `same|…`.
- Regression corpus: run `--math-probe` over the `raw="…"` lines in
  `%APPDATA%\JVoice\diagnostic.log`, and diff against the same sweep before your change. At the
  time of writing (2026-10-02, the Mac-format port) that is 22 changes in 1,684 real dictations +
  Recent Transcripts, all genuine arithmetic, and the port added **zero** (only re-formatted them).
- Acceptance table: every row of "Final §3/§4 probe table" in
  `docs/mac-reference/math-notation-progress.md` must produce its "After" text (84/84 at the port). **Never commit that corpus — it is personal data.**
