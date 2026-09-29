# Math notation — implementation progress (branch `feat/math-format`)

**What this is.** A running log for implementing `docs/math-notation-format.md` (the shared maths output
format) in JVoice's macOS maths engine, `Sources/JVoice/Services/Transcription/Math/`. It is written so a
fresh session can pick up where the last one stopped. Branch `feat/math-format` starts at `0877330`
(`feat/guided-tour`). Nothing is pushed.

**Terms.**
- *Maths engine*: `MathSpeech.convert(text)` — turns spoken maths into symbols; applied last in
  `VoiceCoordinator.finishTranscription` when Settings → Math Notation is on.
- *No-bleed guarantee*: ordinary speech must come back byte-identical (see the spec, principle 7).
- *Everyday corpus*: 494 ordinary sentences that must not change — `prose.txt` (384) + `bleedrisk.txt` (62)
  + `bleedrisk2.txt` (48) in `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.build/bench-2026-09-23/hunt-math/`
  (gitignored). `prose_formal.txt` / `prose_lower.txt` are capitalised/lower-case variants of an older copy.
- *Maths corpus*: 367 maths dictations — `domain1.txt`–`domain4.txt` in the same folder.
- *Windows spec*: `winspec.tsv` in the same folder — the 130 cases of `windows/JVoice.Tests/MathSpeechTests.cs`
  as `C|U <tab> input <tab> expected`.

## How to verify (no `swift test` — it crashed this Mac; CI only)

- `./scripts/run-logic-tests.sh` — compiles + executes the logic assertions (Math section included).
- `swift build -c release` then `.build/release/JVoice --math-probe "<text>"` (or pipe lines).
- Fast standalone probe (≈5 s compile, no WhisperKit): compile the five Math sources
  (`MathSymbol MathScript MathSymbols SpokenNumbers MathSpeech`) with a `main.swift` that loops
  `readLine()` → `MathSpeech.convert` and prints `same|…` / `CHANGED|in|out`. The session's scratchpad
  copies of the helper scripts (`mkprobe.sh`, `sweep.py`, `winspec.py`) are not in the repo; they are
  ~30 lines each and easy to recreate from this description.

## Step 1 — land the unfinished maths package (from worktree `agent-a94ba1b50b2a7c999`)

Status: **DONE — committed on `feat/math-format`.** Logic tests 1005/1005 (+20 package assertions);
`Tests/JVoiceTests/MathSpeechTests.swift` gained 18 conversions + 9 leave-alone cases (checked through the
probe, not `swift test`: every case in `MathSpeechTests` + `MathSymbolsTests` passes, and converting twice
changes nothing); `swift build -c release` OK; `.build/release/JVoice --math-probe` output is byte-identical
to the standalone probe on all 861 corpus lines.
- The uncommitted diff (MathSpeech.swift +600 lines, MathSymbol.swift, MathSymbols.swift) applied cleanly;
  the Math sources were identical at both bases (`74d9b03` there, `0877330` here). It compiles.
- Everyday corpus: 21 lines differ from the pre-package engine, and **all 21 are the listed leaks being
  fixed** ("a plus one", "5 to the 3 kids" and 10 other "to the" sentences, 4 "per" sentences, 5 "more
  than" sentences). 15 everyday lines still convert, all of them already converted before the package
  (e.g. "7 times 70" → `7 · 70`, "he ran 5 over 3 days" → `he ran ⁵⁄₃ days`) — pre-existing, not new bleed.
- Maths corpus: 80 of 367 lines changed; all reviewed — every one is a fix (grouped factorials/choose,
  `P(A ∣ B)`, ordinal powers, whisper's "x" for times), except the deliberate trade-off of fix 1:
  "10 to the 5" / "10 to the 5 possible codes" now stay words (two plain numbers around a bare "to the").
  "…n factorial divided by k factorial times n minus k factorial" still reads `n! ÷ k! · (n - k)!` —
  smart grouping (fix 5) covers "over", not "divided by".
- Windows spec: 130/130 pass (before and after).
- Stress (`stress.py`): linear; the only crash is a stack overflow at ≥ 20,000 levels of nesting
  ("open paren" ×20,000, "negative" ×200,000) — identical in the pre-package engine, and `convert` runs on
  the main actor (8 MB stack). Not realistic; not changed.
- Pre-existing quirk noticed (not changed): a line that converts is re-joined with single spaces, so
  newlines / double spaces inside a converted dictation collapse ("x equals 5\nand then…" → one line).
- `./scripts/run-logic-tests.sh`: 985/985 with the package applied (before new assertions).

## Step 2 — the spec's §4 table

Status: **engine + tests committed** (commit "feat(math): the shared notation format"). Still to do:
`--no-math` in `BenchRunner` (spec §5 item 3), the docs (spec §4 marks, `HANDOFF.md`, the Transcription
`CLAUDE.md`), and the final §3/§4 probe table below.

What changed (all in `Sources/JVoice/Services/Transcription/Math/`):
- **"over" → `/`** (`MathScript.slashFraction`). A side gets parentheses when it holds a space or an operator;
  a DENOMINATOR also when it is a juxtaposed product (`12/(2T)`, `/(2a)` — see "Deviations"). No more stacked
  `ᵇ⁄₂` (`MathScript.fraction` is now unused on macOS — kept, not deleted, the Windows engine still uses it).
  A numerator that is itself a fraction is not re-bracketed (`a/b/c`). A power on a fraction brackets it:
  "5 over 6 to the fourth" → `(5/6)⁴` (`MathScript.powerBase`).
- **"all over"** (new keyword, WEAK): numerator = the whole side back to the last relation, denominator = the
  rest of the side up to the next relation (new `Scope.side`): `(x² - 9)/(x - 3)`.
- **"the quantity"** (new keyword, weak like every bracket): a spoken open bracket that closes at "close
  bracket", else before the next relation or "all over", else at the run's end; it is only a group when its
  body is more than one term, or a single term built from several spoken items (`1 - (5/6)⁴`). An unclosed
  "open paren" also stops at "all over" now.
- **"times"** (and whisper's "3 x 4") → internal marker `*` (`Parser.timesMarker`), laid out at render time by
  `MathScript.productSeparator`: `×` before a number/sign, after a fraction/percent/degree, and next to a
  bracketed application (`C(26, 4) × C(10, 3)`, `P(B ∣ A) × P(A)`); a space before a trig/log function or a
  differential (`2 sin x cos x`); juxtaposition otherwise (`2y`, `ab`, `(n - 1)d`, `(x - 2)(x - 3)`).
  "dot"/"dot product" keep `·`. **"n minus 1 times d" → `(n - 1)d`** (`Expr.groupTrailingOne`: a "times"
  right after "<lettered term> ± 1" takes that difference — nobody multiplies by a spoken 1).
- **"divided by"** keeps `÷` when both sides contain no letter (`6 × 7 ÷ 2`, `400 ÷ 6`), else it is a slash
  fraction whose denominator is read like one after "over" (`x/(2y)`, `x/y²`, `n!/(k!(n - k)!)`).
- **Functions** (`MathScript.applyFunction`): trig/hyperbolic/log/ln take a one-token argument after a space
  (`sin θ`, `cos 2θ`, `ln 2`), tight after a script (`sin²θ`, `log₂8`), brackets for multi-term or bracketed
  arguments (`sin(x + 1)`, `log₃(x + 1)`), and `log_b(x)` when the base fell back. Others keep brackets
  (`f(x)`, `det(A)`). The argument is now one operand WITH its implicit product ("cosine 2 theta" → `cos 2θ`;
  it was `cos(2) θ`). **Activation:** "natural log of …" and a powered function ("sine squared …") now convert
  on their own; other functions stay weak.
- **Roots** (`MathScript.radical`): bracketed when the radicand is more than one number/letter (`√(2x)`,
  `√(b² - 4ac)`); `√x²`, `√-1`, `√14` stay bare. Default scope is the smallest reading (`√x + 1`).
- **Powers**: a spoken "minus" exponent (`10⁻³`); the exponent takes a following "squared"/"cubed" (`e^(-x²)`,
  `e^(x²)` — was the mixed `eˣ²`); a grouped script loses its brackets and spaces (`xⁿ⁺¹`, `aₙ₊₁`,
  `MathScript.scriptOperand`); "to the quantity" is an unmistakable power.
- **Calculus & the rest**: "d y by d x" / "dy by dx" / spoken "d y d x" → `dy/dx` (activating; the no-"by"
  form only when both differentials were spoken letter by letter and nothing they could belong to stands
  before them — `the ∬ f dy dx` stays two differentials); "f prime/double prime/inverse of x" → `f′(x)`,
  `f″(x)`, `f⁻¹(x)` (activating); "5 factorial" → `5!` (activating ONLY when the factorial ends the
  dictation/sentence — "a 2 by 2 factorial design" and "5 factorial ways" stay words); "x tends to infinity"
  → `x → ∞` (only after a lower-case variable or an application — "plan B tends to 5 percent", "type 2 tends
  to 3 times more" stay words); "20 percent of 50" is one operand inside an activated run (`20% of 50 = 10`;
  alone it stays words); "angle A B C" → `∠ABC` (also `△ABC`).
- Minus was already ASCII `-` everywhere; verified no U+2212 in any output.

Verification (all with the standalone probe = same five sources the app compiles; the release app's
`--math-probe` was byte-identical on all 1,036 lines checked):
- Everyday corpus 494: **479 byte-identical; the same 15 lines as before Step 2 convert** (all pre-existing,
  only their symbols changed: `7 × 70`, `2/3 hours`, …). No new bleed.
- A new 55-sentence bleed list aimed at the new words (factorial design, the quantity of water, tends to,
  all over the news, natural log cabin, prime minister, 100 percent of the way, dx dy dance, …): only the 2
  pre-existing conversions ("we have 3 times 2 weeks left", "5 divided by 2"). It caught two bleeds that
  were fixed before commit (factorial in "factorial design", "plan B tends to").
- Repo prose (18,397 unique lines of every `.md`): 2 newly converted — both lines that literally quote spoken
  maths — and 1 no longer converted (typed `ln 8` is already in the format).
- Maths corpus 367: 153 lines changed vs Step 1, all reviewed; all are the format change or improvements
  (`n!/(k!(n - k)!)` now also from "divided by", `(5/6)⁴`, `e^(-x²)`, `f′(x)`, `3!`), plus the known
  literal-precedence limits below.
- Windows spec 130: 106 identical; the 24 differences are all deliberate symbol changes (÷/stacked → `/`,
  `·` → `×`/juxtaposition, one-token function arguments without brackets); every leave-alone case passes.
- Swift tests (checked through the probe, never `swift test`): 174 conversions + 114 leave-alone, 0 failures,
  all idempotent. Logic tests: 1090/1090.
- Stress: flat 200,000-word inputs unchanged (≈1.7–1.9 s incl. process start). Deeply NESTED chains of one
  construct are now quadratic in the nesting depth (each level re-tests a growing operand): 1,000-deep
  ("log base 2 of" ×1,000 = 4,000 words) ≤ 0.1 s, 5,000-deep ≤ 1.8 s, "x squared" ×50,000 28 s. Real
  dictation never nests past a handful; noted, not optimised further.

## Windows mirror list (changes `windows/JVoice.Core/Math/` + `windows/JVoice.Tests/MathSpeechTests.cs` need)

1. The whole Step 1 package: the grouping rule (`Scope`, `Run`, `Parser.subExpression`, rules 1–5 in the
   `Parser` doc comment), bare "to the" weak + `powerIsUnmistakable`, ordinal exponents (lexer step 1b),
   whisper's "x" between numbers as a weak "·" (lexer step 4b), the article-pair rule ("a plus one"),
   `MathSymbols.weakOperators = ["/"]` ("per" weak), "more than"/"is more than" removed from ">".
2. `MathScript.cs`: the layout helpers — `NeedsGrouping(operand, leadingSign, slash)`, `IsWrapped`,
   `IsApplication`, `IsNumeric`, `SlashFraction`, `IsJuxtaposedProduct`/`TopLevelFactors`, `Radical`,
   `ApplyFunction` (+ the spaced-function set), `ProductSeparator`, `PowerBase`, `ScriptOperand`. Scan code
   points, not text elements.
3. `MathSymbols.cs`: "times"/"multiplied by" → `*` (the times marker); `·` keeps only dot/dot product/inner/
   scalar product; new `ActivatingPostfixes = {"!", "!!"}`; reserved phrases += "all over", "the quantity".
   `MathSymbol.Activates` += activating postfixes.
4. `MathSpeech.cs`: keywords "all over" (`AllOver`), "the quantity" (`Quantity`), "tends to" → own `TendsTo`
   (limits accept it too); lexer 1c (derivative ratio: `Differential`, `EndsOperand`); "to the" +
   "quantity" → strong power; lexer 4b emits the times marker; `Expr`: `Part.Relation`, `PushInfix(…,
   relation)`, `SideStart`, `GroupTrailingOne`, render-time times layout, ∠/△ tight; `Scope.Side`
   (`Reaches` = not a relation, `Allows` = all but AllOver/TendsTo, implicit products like `.Product`);
   step(): algebraic "divided by", `GroupTrailingOne` before a times, postfix activation only at the clean
   end of the run; keyword(): scripts via `TryExponent` (signed, powered) + `PowerBase` + `ScriptOperand`,
   "over" → one slash-fraction operand, AllOver, Quantity, TendsTo (`CanTend`), "of" after a `%`,
   DerivRatio; `PowerIsUnmistakable` skips a leading minus; tryOperand(): `Radical` for roots and the √
   prefix, marked function names (`FunctionMarks`), `ApplyFunction` with a script-operand argument and
   ln/powered-function activation, `Quantity(k)`; `Group` stops an unclosed bracket at "all over".
5. `MathSpeechTests.cs` / `MathSymbolsTests.cs`: take the expectations from the Swift files
   (`Tests/JVoiceTests/MathSpeechTests.swift` — the "shared notation format" block and the new leave-alone
   lines; `MathSymbolsTests.swift` — the "times"/"dot" lookups and the four updated conversions).
