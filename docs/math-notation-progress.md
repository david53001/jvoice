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
  `readLine()` → `MathSpeech.convert` and prints `same|…` / `CHANGED|in|out`.
- The helper scripts used this session are saved (gitignored) in
  `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.build/bench-2026-09-23/hunt-math/format-2026-09-29/`
  — edit the path constants at the top of each before use (they pointed at this session's worktree and
  scratchpad):
  - `mkprobe.sh <math-dir> <out> [main.swift]` builds a probe (`probe_main.swift` is the main).
  - `sweep.py <probeA> <probeB> --everyday|--maths|--extra|--file F` diffs two engines over the corpora.
  - `winspec.py <probe>` runs the 130 Windows-spec cases.
  - `checktests.py <probe>` extracts every conversion / leave-alone case from `Tests/JVoiceTests/
    MathSpeechTests.swift` + `MathSymbolsTests.swift` and checks them (plus idempotence) through the probe —
    the SAFE stand-in for `swift test`.
  - `stress.py kind:n …` (env `PROBE=`) times pathological inputs; `linediff.py` shows the changed spans.
  - `bleed_new.txt` — 55 ordinary sentences using this session's new trigger words (must stay unchanged
    except "we have 3 times 2 weeks left" and "I'll divide it 5 divided by 2", which already converted).
  - `spec_rows.tsv` + `probe_table.md` — every §3/§4 example and the before/after table below.

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
  "…n factorial divided by k factorial times n minus k factorial" still read `n! ÷ k! · (n - k)!` after
  Step 1 — smart grouping (fix 5) covers "over", not "divided by". (Step 2 changed that: an algebraic
  "divided by" now reads its denominator like "over" does, giving `n!/(k!(n - k)!)`.)
- Windows spec: 130/130 pass (before and after).
- Stress (`stress.py`): linear; the only crash is a stack overflow at ≥ 20,000 levels of nesting
  ("open paren" ×20,000, "negative" ×200,000) — identical in the pre-package engine, and `convert` runs on
  the main actor (8 MB stack). Not realistic; not changed.
- Pre-existing quirk noticed (not changed): a line that converts is re-joined with single spaces, so
  newlines / double spaces inside a converted dictation collapse ("x equals 5\nand then…" → one line).
- `./scripts/run-logic-tests.sh`: 985/985 with the package applied (before new assertions).

## Step 2 — the spec's §4 table

Status: **DONE — committed on `feat/math-format`** (engine + tests; `BenchRunner --no-math`; docs: spec §4
Status column, `docs/HANDOFF.md` entry, the Transcription `CLAUDE.md`). Not merged, not installed, not
pushed; CI has not run the new swift-testing cases. What is left is under "Next steps".

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

## Fix — David's failed dictation on the installed build (2026-09-29, after Step 2)

**Symptom.** "K squared plus the root of K cubed times Kx squared sigma of 3." pasted as
`K² plus the root of K³ times Kx squared sigma of 3.` — only the two scripts converted.
**Now:** `K² + √K³ × Kx² ∑ 3.` (it was `… σ(3).` until David said "sigma" means the sum sign — see
"sigma = ∑" below). Four causes, each reproduced first:
1. **Bare "root of" was not a keyword**, so "root" was an ordinary word that ended the run and stranded
   "plus". New keyword `"root of"` = square root, lexed WEAK: it renders inside a run something else
   activated ("x plus the root of 2" → `x + √2`), and activates on its own only when its radicand takes a
   power ("the root of K cubed" → `the √K³`; the weak root reads its radicand with `tryPoweredOperand`).
   "the root of the problem", "the root of 3 problems", "root of all evil", "root for the team" stay words.
2. **Whisper glued two variables into "Kx".** New lexer step 5b: a two-letter token, not all capitals
   (acronyms: TV, PC, AI, UK), not in a list of ~130 English/unit/interjection two-letter words (ok, is,
   an, at, my, so, to, us, if, of, or, it, as, be, by, go, he, me, no, up, we, am, do, hi, oh, ox, ax, cm,
   kg, …), is a variable ONLY right after an infix operator or right before a script keyword
   ("squared", "cubed", "sub", "super", "to the power"). It is marked `glued` + weak: an operator or
   script next to it never activates because of it (`Parser.gluedBase`), so it renders only in an already
   activated run. Three-letter tokens were NOT included (the brief allowed 2–3): "x equals 5 plus tax"
   would become `x = 5 + tax`. Consequence: "x equals xy squared" alone stays words (conservative).
3. **"the" mid-run** needed no new code: `tryOperand` already skips a "the" in operand position (that is
   how "plus the square root of" worked); it only failed because "root" was a word (cause 1).
4. **"sigma of 3"** → first `σ(3)`, now `∑ 3` (next section). The rule added here still holds for the other
   Greek letters and for "lowercase sigma of 3" → `σ(3)`: a Greek letter followed by "of" is applied like "f of x" (weak, `Parser.
   isGreekLetter`). "sigma" is NOT turned into ∑ — **David hasn't said what he meant; flag for him.**
   Side fix: a limit's target is read with `allowApply: false`, so "the limit as x approaches pi of sine x"
   stays `lim_(x→π) sin x` rather than `π(sin x)`.
- **Layout choice:** "times" after an UNBRACKETED root is `×` (`√K³ × Kx²`; also `√k³ × kx²` for the old
  "square root" sentence, which pasted `√k³kx²`). Juxtaposition is the spec's rule for letter terms, but
  `√K³Kx²` reads as one radicand √(K³Kx²); `×` keeps the letters and the root's extent unambiguous
  (`MathScript.endsInOpenRadical`). `Kx²` and `σ(3)` were spoken with no "times", so they stay spaced.
- **Verified:** logic tests 1114/1114 (+24); Swift cases through the probe 181 conversions + 129
  leave-alone, 0 failures; everyday corpus 494, variants, maths corpus 367, repo prose (18,398 lines):
  **0 lines differ** from the engine before this fix; the 55-sentence bleed list unchanged; a new
  42-sentence list for root/sigma/two-letter words (`bleed_kx.txt` in the helpers folder) unchanged except
  the two lines that already converted ("x equals 5 plus ok" → `x = 5 plus ok`, "x equals 5 so it works");
  Windows spec 106/130 as before; release `--math-probe` identical to the probe on 1,078 lines.

## "sigma" = ∑ (David, 2026-09-29, same day)

David: by "sigma" he means the SUM SIGN `∑`, not `σ`.
- **Bounded** — exactly like "sum": "sigma from i equals 1 to n of i" → `∑ᵢ₌₁ⁿ i`, "Sigma from k equals 0 to
  infinity of x to the k" → `∑ₖ₌₀^∞ xᵏ` (activating). "sum i equals 1 to n" (no "from") is not supported
  for "sum" either, so not for "sigma".
- **Unbounded** ("sigma of 3"): "sum of 3" stays words even inside an equation, on purpose — "the sum of my
  fears" is everyday English. "sigma" is rarely English next to "of", so the safest consistent option is a
  WEAK `∑`: it renders only inside a run something else made mathematics, and it is laid out like the
  other unbounded big operator (`∫ 3` for "integral of 3") — a space before its body: `… Kx² ∑ 3.` On its
  own ("sigma of 3", "six sigma of 3 teams", "Six Sigma", "sigma male", "that's so sigma") it stays words.
- As for "sum"/"integral", a big operator cannot be the right side of "equals": "x equals sigma of 3" and
  "x equals the sum from i equals 1 to n of i" leave the "equals" as a word (pre-existing, not changed).
- **The letter σ** is only "lowercase sigma" / "small sigma" ("small sigma equals 2" → `σ = 2`); `Σ` stays
  "capital/big/uppercase sigma"; "sigma squared" follows the ∑ rules (so on its own it stays words).
- **Cost, for David:** statistics dictation that says "sigma" for the standard deviation no longer gets `σ`.
  7 of the 367 maths-corpus lines changed, all this kind, e.g. "sigma squared equals 2.5" (was `σ² = 2.5`,
  now words), "z equals x minus mu over sigma" (was `z = x - μ/σ`, now `z = x - μ over sigma`), "x bar plus
  or minus 1.96 times sigma over the square root of n". No line got a wrong `∑`. Say "lowercase sigma".
- Code: lexer step 2b in `MathSpeech.swift` (bare "sigma" → `∑` prefix, weak unless "from" follows);
  `bigOperator` activates for a weak ∑ only when bounded; `MathSymbols` drops the bare "sigma" key, adds
  "lowercase/small/lower case sigma" → σ, and reserves "sigma".
- Verified: everyday 494, variants, repo prose 18,398: 0 lines differ; bleed lists unchanged (6 sigma
  sentences added to `bleed_kx.txt`); maths corpus: the 7 lines above; logic tests 1123/1123; Swift cases
  through the probe 184 + 135, 0 failures; release `--math-probe` identical to the probe.

## Deviations from the spec (and why)

1. **A spoken leading "the" is kept**: "the square root of 14" → `the √14`, "the natural log of 2" →
   `the ln 2`, "the limit …" → `the lim_(x→0) …`. The spec's §3 column omits it, but §4 lists `∫₀¹ x² dx` /
   `|x|` (which print `the ∫…` / `the |x|`) as already matching, so it is not treated as a required change;
   and the engine's rule is that a construct never swallows a spoken word. One-line change if David wants
   the article dropped.
2. **§6.1 smallest reading by default** (per the task brief): "the square root of b squared minus 4 a c" →
   `√b² - 4ac`, "sine of x plus 1" → `sin x + 1`, "log base 3 of x plus 1" → `log₃x + 1`, "x to the n plus
   1" → `xⁿ + 1`. §3 shows the grouped forms; they need the new grouping word "the quantity" (or "open
   paren … close paren"). §3's `xⁿ⁺¹` for "x to the n plus 1" contradicts §4's own "already matching
   `xⁿ + 1`"; the §4/§6.1 reading was kept.
3. **Juxtaposed denominators get brackets**: `12/(2T)`, `(-b ± …)/(2a)`, `1/(2π)`. BetterScreenshot §8.2's
   rule ("parentheses when it holds a space or an operator") would paste `/2a`, which reads as (x/2)·a in
   every calculator/spreadsheet; spec principle 6 (brackets carry what a stacked layout showed) favours
   `/(2a)`. **Needs David's call** — and whichever way, BetterScreenshot and JVoice should agree.
4. **"n minus 1 times d" → `(n - 1)d`** is a targeted grouping rule (a "times" after "<lettered term> ± 1"),
   not general precedence: "x plus 2 times y" stays `x + 2y`. Justification: nobody multiplies by a spoken
   1 on purpose. It also fires on "p to the k minus 1 times p" → `1 - (pᵏ - 1)p` (the speaker meant
   `(1 - p)ᵏ⁻¹p`; the old output `1 - pᵏ - 1 · p` was no closer).
5. **× vs juxtaposition details beyond the spec** (`MathScript.productSeparator`): `×` also before a number
   (`x × 2`), after a fraction/percent (`V/2 × T`), and next to a bracketed function application
   (`C(26, 4) × C(10, 3)`, `P(B ∣ A) × P(A)` — IB also writes `P(A)P(B)`); a space before sin/cos/log
   (`2 sin x cos x`). Two identical letters juxtapose literally: "n times n plus 1 over 2" → `nn + 1/2`.
6. **Activation widened, narrowly**: "5 factorial" converts alone only when the factorial ENDS the sentence
   (not "5 factorial ways"); "tends to" only after a lower-case variable or `f(x)`; "20 percent of 50" alone
   stays words (the spec's own "weak word" instruction); "angle A B C" alone stays words (∠ is weak).
7. **§3 rows outside §4, not changed** (not requested, or excluded): "sine theta" / "cos 2 theta" alone stay
   words (functions are weak; they render as `sin θ` / `cos 2θ` inside an equation); "the magnitude of a" →
   still the weak `norm(a)` function, not `|a|`; "A complement" → weak `Aᶜ`, not IB's `A′`; "a cross b" → words
   ("cross" is excluded as everyday English); "probability of A given B" → `P(A ∣ B)` (spaced U+2223), not
   `P(A|B)`; "25 degrees Celsius" → `25°C` inside an equation, not `25 °C` (unit spacing — excluded); "the
   matrix 1 2 3 4" → words (no matrix grammar). Superscript capitals (`ᴬ ᴮ …`) are still used although §2
   says "no capitals" — unchanged.

## Decisions for David

- Denominator brackets for juxtaposed products: `12/(2T)` (JVoice now) vs `12/2T` (BetterScreenshot's
  wording). Deviation 3.
- Keep or drop a spoken leading "the" before a construct (`the √14` vs `√14`). Deviation 1.
- Still open from the spec: §6.2 `ⁿCᵣ` vs `C(n, r)`, §6.3 units, §6.4 chemistry, §6.5 an ASCII/LaTeX setting.
- His real maths style needs the grouping word: in the 2026-09-28 sample (`docs/math-accuracy/`, gitignored)
  he says "k plus 1 times k plus 2 times 2k plus 9" meaning (k + 1)(k + 2)(2k + 9); the engine now pastes
  `(k + 1)k + 2 × 2k + 9`. Only "the quantity k plus 1 times the quantity k plus 2 …" or explicit brackets
  give the product. Worth telling him before the maths-accuracy review.

## Known limitations (not changed)

- Literal precedence everywhere else: "n times n plus 1 over 2" → `nn + 1/2`, "x to the n plus 1 over n plus
  1" → `xⁿ + 1/n + 1`, "n p times 1 minus p" → `np × 1 - p`.
- Nesting depth cost (see Stress above) and the pre-existing ≥ 20,000-deep stack overflow.
- A converted line is re-joined with single spaces (newlines inside it collapse) — pre-existing.
- `Expr.lastIsDivisor` and `MathScript.fraction` are now unused on macOS (dead code, left in place).

## Next steps

1. David's decisions above (denominator brackets, leading "the").
2. Mirror everything in the Windows engine (list below) — needs the .NET toolchain (not on this Mac).
3. Push the branch only with David's go-ahead; CI then runs the updated swift-testing cases
   (`MathSpeechTests`, `MathSymbolsTests`), which were checked here only through the probe.
4. Spec §5 item 3: run `--bench <clip> [--no-math]` on a few maths clips and record `postprocess: … ms`;
   expected ≈ 0.04 ms/dictation for maths (spec §5), i.e. no measurable difference — don't claim "off is
   faster" in Settings unless it shows.
5. Install/dogfood only when David asks (`./scripts/dev-install.sh`).

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
5. The 2026-09-29 dictation fix: keyword "root of" (lexed weak; weak root reads a powered radicand and
   activates only when it took a power; `keyword()` does not activate a weak root); `Item.Glued` + lexer
   step 5b (`IsGluedVariables`, the two-letter word list, `IsInfix`, `StartsScript`) + `GluedBase`
   suppressing activation in the operator branch, scripts and "squared"/"cubed"; Greek letter + "of" →
   application (`IsGreekLetter`); limit target read with `allowApply: false`; `MathScript.
   EndsInOpenRadical` → `×` in `ProductSeparator`. Tests: the "David's failed dictation" block and the
   root/sigma/two-letter leave-alone lines in `MathSpeechTests.swift`.
6. "sigma" = ∑: `MathSpeech.cs` lexer step 2b + the weak-∑ check in `BigOperator`; `MathSymbols.cs` removes the
   bare "sigma" key, adds "lowercase sigma"/"small sigma"/"lower case sigma" → σ, reserves "sigma".
   `MathSymbolsTests.cs`: "sigma squared equals the variance of x" becomes "lowercase sigma squared …".
7. `MathSpeechTests.cs` / `MathSymbolsTests.cs`: take the expectations from the Swift files
   (`Tests/JVoiceTests/MathSpeechTests.swift` — the "shared notation format" block and the new leave-alone
   lines; `MathSymbolsTests.swift` — the "times"/"dot" lookups and the four updated conversions).

## Final §3/§4 probe table (2026-09-29)

Every spoken example of the spec's §3 and §4 (plus the new grouping-word forms, marked `+`), through the
engine at `0877330` ("Before", i.e. `feat/guided-tour`) and at the tip of `feat/math-format` ("After"),
using the standalone probe (byte-identical to `.build/release/JVoice --math-probe`). "(words)" = left
unchanged. A "Spec wants" cell with a § reference is an open decision or a scope note in spec §6.

| § | Spoken | Spec wants | Before (`0877330`) | After (`feat/math-format`) |
|---|---|---|---|---|
| §3 | x squared plus y squared equals z squared | `x² + y² = z²` | `x² + y² = z²` | `x² + y² = z²` |
| §3 | x to the n plus 1 | `xⁿ⁺¹ (§6.1)` | `xⁿ + 1` | `xⁿ + 1` |
| §3 | 10 to the power of minus 3 | `10⁻³` | (words) | `10⁻³` |
| §3 | e to the i pi | `e^(iπ)` | `e^(iπ)` | `e^(iπ)` |
| §3 | e to the minus x squared | `e^(-x²)` | `e to the minus x²` | `e^(-x²)` |
| §3 | e to the zero point two t | `e^(0.2t)` | `e^(0.2t)` | `e^(0.2t)` |
| §3 | x sub 1 | `x₁` | `x₁` | `x₁` |
| §3 | a sub n | `aₙ` | `aₙ` | `aₙ` |
| §3 | log base 2 of 8 | `log₂8` | `log₂(8)` | `log₂8` |
| §3 | H two O | `H₂O (§6.4)` | (words) | (words) |
| §3 | C O two | `CO₂ (§6.4)` | (words) | (words) |
| §3 | Fe three plus | `Fe³⁺ (§6.4)` | (words) | (words) |
| §3 | metres per second squared | `m s⁻² or m/s² (§6.3)` | (words) | (words) |
| §3 | a plus b over 2 | `a + b/2` | `a + ᵇ⁄₂` | `a + b/2` |
| §3 | a plus b all over 2 | `(a + b)/2` | `a + b all over 2` | `(a + b)/2` |
| §3 | pi over 6 | `π/6` | `π ÷ 6` | `π/6` |
| §3 | 1 over x squared | `1/x²` | `1 ÷ x²` | `1/x²` |
| §3 | x squared minus 9 all over x minus 3 | `(x² - 9)/(x - 3)` | `x² - 9 all over x - 3` | `(x² - 9)/(x - 3)` |
| §3 | d y by d x | `dy/dx` | (words) | `dy/dx` |
| §3 | d y d x | `dy/dx` | (words) | `dy/dx` |
| §3 | f prime of x | `f′(x)` | (words) | `f′(x)` |
| §3 | f inverse of x | `f⁻¹(x)` | (words) | `f⁻¹(x)` |
| §3 | the square root of 14 | `√14` | `the √14` | `the √14` |
| §3 | the square root of b squared minus 4 a c | `√(b² - 4ac) (§6.1)` | `the √b² - 4ac` | `the √b² - 4ac` |
| §3 | the cube root of 27 | `∛27` | `the ∛27` | `the ∛27` |
| §3 | the integral from 0 to 1 of x squared d x | `∫₀¹ x² dx` | `the ∫₀¹ x² dx` | `the ∫₀¹ x² dx` |
| §3 | the sum from i equals 1 to n of i | `∑ᵢ₌₁ⁿ i` | `the ∑ᵢ₌₁ⁿ i` | `the ∑ᵢ₌₁ⁿ i` |
| §3 | the limit as x approaches 0 of sine x over x | `lim_(x→0) (sin x)/x` | `the lim_(x→0) sin(x) ÷ x` | `the lim_(x→0) (sin x)/x` |
| §3 | sine theta | `sin θ` | (words) | (words) |
| §3 | cos 2 theta | `cos 2θ` | (words) | (words) |
| §3 | sine squared theta | `sin²θ` | (words) | `sin²θ` |
| §3 | sine of x plus 1 | `sin(x + 1)` | `sin(x) + 1` | `sin x + 1` |
| §3 | natural log of 2 | `ln 2` | (words) | `ln 2` |
| §3 | log base 3 of x plus 1 | `log₃(x + 1)` | `log₃(x) + 1` | `log₃x + 1` |
| §3 | x is less than or equal to 5 | `x ≤ 5` | `x ≤ 5` | `x ≤ 5` |
| §3 | x is approximately 3.47 | `x ≈ 3.47` | `x ≈ 3.47` | `x ≈ 3.47` |
| §3 | 3 plus or minus 0.5 | `3 ± 0.5` | `3 ± 0.5` | `3 ± 0.5` |
| §3 | 6 times 7 divided by 2 | `6 × 7 ÷ 2` | `6 · 7 ÷ 2` | `6 × 7 ÷ 2` |
| §3 | a dot b | `a · b` | `a · b` | `a · b` |
| §3 | a cross b | `a × b` | (words) | (words) |
| §3 | the absolute value of x | `\|x\|` | `the \|x\|` | `the \|x\|` |
| §3 | the magnitude of a | `\|a\|` | (words) | (words) |
| §3 | 5 factorial | `5!` | (words) | `5!` |
| §3 | n choose r | `ⁿCᵣ or C(n, r) (§6.2)` | `C(n, r)` | `C(n, r)` |
| §3 | x tends to infinity | `x → ∞` | (words) | `x → ∞` |
| §3 | x is an element of the reals | `x ∈ ℝ` | `x ∈ ℝ` | `x ∈ ℝ` |
| §3 | A intersect B | `A ∩ B` | `A ∩ B` | `A ∩ B` |
| §3 | A union B | `A ∪ B` | `A ∪ B` | `A ∪ B` |
| §3 | A complement | `A′` | (words) | (words) |
| §3 | probability of A given B | `P(A\|B)` | `P(A) ∣ B` | `P(A ∣ B)` |
| §3 | angle A B C equals 90 degrees | `∠ABC = 90°` | `∠ ABC = 90°` | `∠ABC = 90°` |
| §3 | 25 degrees Celsius | `25 °C` | (words) | (words) |
| §3 | 20 percent | `20%` | (words) | (words) |
| §3 | the matrix 1 2 3 4 | `[1 2; 3 4]` | (words) | (words) |
| §4 | a plus b over 2 | `a + b/2` | `a + ᵇ⁄₂` | `a + b/2` |
| §4 | a plus b all over 2 | `(a + b)/2` | `a + b all over 2` | `(a + b)/2` |
| §4 | pi over 6 | `π/6` | `π ÷ 6` | `π/6` |
| §4 | a over b plus c over d | `a/b + c/d` | `a ÷ b + c ÷ d` | `a/b + c/d` |
| §4 | 1 over x squared | `1/x²` | `1 ÷ x²` | `1/x²` |
| §4 | the limit as x approaches 0 of sine of x over x equals 1 | `lim_(x→0) (sin x)/x = 1` | `the lim_(x→0) sin(x) ÷ x = 1` | `the lim_(x→0) (sin x)/x = 1` |
| §4 | the square root of x plus 1 | `√(x + 1) or √x + 1` | `the √x + 1` | `the √x + 1` |
| §4 | the square root of b squared minus 4 a c | `√(b² - 4ac)` | `the √b² - 4ac` | `the √b² - 4ac` |
| §4 | a sub n equals a sub 1 plus n minus 1 times d | `aₙ = a₁ + (n - 1)d` | `aₙ = a₁ + n - 1 · d` | `aₙ = a₁ + (n - 1)d` |
| §4 | 6 times 7 divided by 2 | `6 × 7 ÷ 2` | `6 · 7 ÷ 2` | `6 × 7 ÷ 2` |
| §4 | sine squared theta plus cosine squared theta equals 1 | `sin²θ + cos²θ = 1` | `sin²(θ) + cos²(θ) = 1` | `sin²θ + cos²θ = 1` |
| §4 | d y by d x equals 3 x squared minus 4 | `dy/dx = 3x² - 4` | `d y by dx = 3x² - 4` | `dy/dx = 3x² - 4` |
| §4 | f prime of x equals 2 x plus 1 | `f′(x) = 2x + 1` | `f prime of x = 2x + 1` | `f′(x) = 2x + 1` |
| §4 | f inverse of x | `f⁻¹(x)` | (words) | `f⁻¹(x)` |
| §4 | 10 to the power of minus 3 | `10⁻³` | (words) | `10⁻³` |
| §4 | e to the minus x squared | `e^(-x²)` | `e to the minus x²` | `e^(-x²)` |
| §4 | H 2 O | `H₂O (§6.4)` | (words) | (words) |
| §4 | 5 factorial | `5!` | (words) | `5!` |
| §4 | the natural log of 2 | `ln 2` | (words) | `the ln 2` |
| §4 | x tends to infinity | `x → ∞` | (words) | `x → ∞` |
| §4 | 20 percent of 50 | `20% of 50` | (words) | (words) |
| §4 | log base 3 of x plus 1 | `log₃(x + 1)` | `log₃(x) + 1` | `log₃x + 1` |
| §4 | angle A B C | `∠ABC` | (words) | (words) |
| §4 | n choose r | `ⁿCᵣ or C(n, r) (§6.2)` | `C(n, r)` | `C(n, r)` |
| + | the square root of the quantity b squared minus 4 a c | `√(b² - 4ac)` | `the square root of the quantity b² - 4ac` | `the √(b² - 4ac)` |
| + | sine of the quantity x plus 1 | `sin(x + 1)` | `sine of the quantity x + 1` | `sin(x + 1)` |
| + | log base 3 of the quantity x plus 1 | `log₃(x + 1)` | `log base 3 of the quantity x + 1` | `log₃(x + 1)` |
| + | x to the quantity n plus 1 | `xⁿ⁺¹` | `x to the quantity n + 1` | `xⁿ⁺¹` |
| + | 20 percent of 50 equals 10 | `20% of 50 = 10` | `20 percent of 50 = 10` | `20% of 50 = 10` |
| + | x equals negative b plus or minus the square root of the quantity b squared minus 4 a c all over 2 a | `(-b ± √(b² - 4ac))/(2a)` | `x = -b plus or minus the square root of the quantity b² - 4ac all over 2 a` | `x = (-b ± √(b² - 4ac))/(2a)` |
