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

## Files
- `MathSpeech.cs` — tokenizer, run splitting, parser, renderer. `Convert(string)` is the API.
- `MathSymbols.cs` — the vocabulary (spoken form → symbol + kind). Data only.
- `MathSymbol.cs` — `MathKind` + what `Activates`.
- `MathScript.cs` — Unicode super/subscript, all-or-nothing, `^`/`_` fallback.
- `SpokenNumbers.cs` — number words → digits.

## Traps
- **`MathSymbols.ReservedPhrases` are parsed structurally by the engine** — never add them as
  vocabulary keys (`MathSpeechTests` fails if you do).
- Adding a Relation/Operator/Prefix is the only way to create a false positive. Weak kinds are
  free; activating kinds need the "could this sit between two operand-looking words in ordinary
  speech?" audit.
- The engine runs **after** `TextProcessor.Process`, deliberately: tone formatting, filler
  removal and the correction dictionaries all work on English words, so no symbol can be
  mangled by them. (Cosmetic consequence: in Formal tone a sentence-initial variable is
  capitalised, `"X² = 4."`)

## Verify
- `dotnet test windows/JVoice.Tests` — `MathSpeechTests` is the spec (conversions + prose that
  must come back byte-identical), plus `MathSymbolsTests` / `SpokenNumbersTests`.
- `JVoice.exe --math-probe "<text>"` (or piped stdin) — one line per input, `CHANGED|…` / `same|…`.
- Regression corpus: run `--math-probe` over the `raw="…"` lines in
  `%APPDATA%\JVoice\diagnostic.log`. At the time of writing that is 4 changes in 1,174 real
  dictations, all of them genuine arithmetic. **Never commit that corpus — it is personal data.**
