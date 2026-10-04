# Math notation — the shared format, and what JVoice should change (2026-09-29)

**What this is.** David's apps turn mathematics into text in two ways:

- **JVoice** (this repo) turns *spoken* maths into symbols when **Settings → Processing → Math Notation**
  is on ("x squared equals 4" → `x² = 4`).
- **BetterScreenshot**'s **Capture Text** (a separate repo, `../BetterScreenshot`) turns maths in a
  *screenshot* into symbols.

Both paste into the same places: Google Docs, Word, Notes, AI chats, code editors and IB (International
Baccalaureate) coursework. The same maths should therefore come out **identical** whether David says it or
screenshots it.

This document does four things:
1. Defines that one format, symbol by symbol (§2–§3).
2. Records where JVoice's current output differs, measured on 2026-09-29 (§4).
3. Sets the rule for the Math Notation toggle: switching it off must actually save time (§5).
4. Lists the open decisions (§6) and how to verify changes (§7).

It is written for a session with no context. **Status (2026-09-29):** the macOS engine implements §4 on
branch `feat/math-format` (not merged, not released) — see the Status column in §4 and
`docs/math-notation-progress.md` for what changed, deviations and the Windows mirror list. The Windows
engine (`windows/JVoice.Core/Math/`) does not yet.

**Where the format comes from.** It is the format BetterScreenshot adopted on 2026-09-28 (David's
decision: "readable Unicode, not LaTeX"). Its source of truth is BetterScreenshot's
`docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 8 §8.2 and the expected outputs of its test cases in
`tools/ocr-bench/Sources/ocr-bench/*.swift`.

**Where JVoice's maths code is.**
- macOS: `Sources/JVoice/Services/Transcription/Math/`.
  - `MathSpeech.swift`: grammar, activation rules, emitter.
  - `MathSymbols.swift`: the vocabulary of ~700 spoken forms.
  - `MathScript.swift`: super/subscripts and fractions.
  - `SpokenNumbers.swift`, `MathSymbol.swift`, and `MathProbe.swift` (the `--math-probe` command-line mode).
- It is applied last, in `VoiceCoordinator.finishTranscription` (≈ line 817):
  `mathNotation ? MathSpeech.convert(styled) : styled`.
- The setting is `SettingsState.mathNotation` (schema v4, default on). The Settings row is in
  `UI/SettingsView.swift` (≈ line 241).
- The Mac engine is a 1:1 port of the Windows port's `windows/JVoice.Core/Math/`, whose spec tests are
  `windows/JVoice.Tests/MathSpeechTests.cs`. **Every format change below must be made in both engines.**
- The maths-engine rework that sat uncommitted in `.claude/worktrees/agent-a94ba1b50b2a7c999` (`docs/HANDOFF.md`,
  2026-09-24, "Unfinished — the maths-engine package") landed on branch `feat/math-format` on 2026-09-29,
  together with this format (`docs/math-notation-progress.md`).

---

## 1. Principles

1. **Readable Unicode, not LaTeX.** Write `x² + y² = z²`, never `x^2+y^2=z^2` or `$x^{2}$`.
2. **Fallback only where Unicode has no character.** Use `^(…)` or `_(…)` only when some character in an
   exponent or index has no super/subscript form: `e^(iπ)`, `e^(0.2t)`, `a_b`. A single character needs
   no brackets (`a_b`, `x^π`). Never mix styles in one exponent: `e^(0.2t)`, not `e⁰.²ᵗ`.
3. **Spacing follows typeset maths.**
   - Put one space on each side of relations and binary operators: `F = ma`, `x² - 9`, `a ≤ b`.
   - Unary signs stay tight: `-3`, `(-x)`, `= -1`.
   - Nothing goes inside scripts: `xⁿ⁺¹`.
   - Letters multiply by juxtaposition: `2ab`, `(n - 1)d`.
4. **One character per meaning.**
   - `×` is multiplication between numbers (`6 × 7`, `3.00 × 10⁸`).
   - `·` is the dot product (`a · b`).
   - `/` is division and fractions.
   - `÷` only when the source itself shows `÷` (a primary-school sum), never as the rendering of "over".
5. **Minus is pasted as ASCII `-`.** It works in Excel formulas, calculators and code. BetterScreenshot
   does the same. U+2212 `−` looks nicer but breaks those targets.
6. **Parentheses carry grouping that a stacked layout would have shown.** A fraction's numerator or
   denominator, and a root's radicand, get parentheses when they hold more than one term: `(a + b)/2`,
   `1/(x ln 2)`, `√(b² - 4ac)`.
7. **Don't damage ordinary speech.** This is JVoice's own rule (Transcription `CLAUDE.md`, invariant 4)
   and BetterScreenshot's "no-harm guard": when unsure, leave the words as spoken.
   - JVoice calls this the **no-bleed guarantee**: maths must never "bleed" into ordinary talking.
   - It is structural. A word can only become a symbol inside a **maths run**, meaning consecutive words
     that all read as maths, ended by any ordinary word or punctuation.
   - A run only converts when an *activating* construct (`=`, `+`, "squared", "over", …) finds its
     operands.
   - Weak words (`π`, "percent", number words) render only inside an already-activated run.

## 2. Characters

| Group | Characters | Notes |
|---|---|---|
| Superscripts | `⁰¹²³⁴⁵⁶⁷⁸⁹ ⁺⁻⁼⁽⁾ ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ` | No superscript `q`, no capitals, no Greek → fallback `^(…)`. |
| Subscripts | `₀₁₂₃₄₅₆₇₈₉ ₊₋₌₍₎ ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ` | No subscript `b c d f g q w y z`, no capitals → fallback `_(…)`. |
| Relations | `= ≠ ≈ < > ≤ ≥ → ⇒ ⇔ ∈ ∉ ⊂ ⊆ ≡ ∝` | Spaced. |
| Operators | `+ - × ÷ ± · ∘` | See principles 3–5. |
| Sets and numbers | `∩ ∪ ∅ ℕ ℤ ℚ ℝ ℂ` and complement `A′` | IB uses `A′` for the complement. |
| Logic | `∀ ∃ ¬ ∧ ∨` | |
| Calculus | `∫ ∑ ∏ ∂ ∞ ′ ″` and `lim` | Prime is U+2032 `′`, not an apostrophe. |
| Roots | `√ ∛ ∜` | |
| Geometry | `° ∠ ⊥ ∥ △ ≅ ∼` | |
| Greek | `α β γ δ ε θ λ μ π ρ σ τ φ ω Δ Σ Ω` | Say the name, get the letter. Capitals only when said ("capital delta"). **Exception — "sigma" is the SUM SIGN `∑`** (David, 2026-09-29): "sigma from i equals 1 to n of i" → `∑ᵢ₌₁ⁿ i`, like "sum from …". The letter `σ` is "lowercase sigma" / "small sigma"; `Σ` is "capital sigma". |
| Fractions | `½ ⅓ ⅔ ¼ ¾ ⅕ ⅛` | Only for spoken simple number fractions ("three quarters" of a quantity); algebra uses `/`. |
| Other | `% ‰ ! |x| ⌊x⌋ ⌈x⌉` | |

## 3. Constructs — spoken → pasted

What JVoice should paste. The "today" column in §4 shows where it differs.

| Spoken | Paste |
|---|---|
| x squared plus y squared equals z squared | `x² + y² = z²` |
| x to the n plus 1 | `xⁿ⁺¹` (the exponent runs until the grammar closes it; see §6.1) |
| 10 to the power of minus 3 | `10⁻³` |
| e to the i pi | `e^(iπ)` |
| e to the minus x squared | `e^(-x²)` (nested script → fallback) |
| e to the zero point two t | `e^(0.2t)` |
| x sub 1, a sub n, log base 2 of 8 | `x₁`, `aₙ`, `log₂8` |
| H two O, C O two | `H₂O`, `CO₂` (only if chemistry activates safely — §6.4) |
| Fe three plus | `Fe³⁺` |
| metres per second squared | `m s⁻²` (IB style), or `m/s²` (§6.3) |
| a plus b over 2 / a plus b all over 2 | `a + b/2` / `(a + b)/2` ("all over" closes the numerator) |
| pi over 6 | `π/6` |
| 1 over x squared | `1/x²` |
| x squared minus 9 all over x minus 3 | `(x² - 9)/(x - 3)` |
| d y by d x / d y d x | `dy/dx` |
| f prime of x | `f′(x)` |
| f inverse of x | `f⁻¹(x)` |
| the square root of 14 | `√14` |
| the square root of b squared minus 4 a c | `√(b² - 4ac)` (scope: §6.1) |
| the cube root of 27 | `∛27` |
| the integral from 0 to 1 of x squared d x | `∫₀¹ x² dx` |
| the sum from i equals 1 to n of i | `∑ᵢ₌₁ⁿ i` |
| the limit as x approaches 0 of sine x over x | `lim_(x→0) (sin x)/x` (no subscript arrow → `_(…)`) |
| sine theta, cos 2 theta, sine squared theta | `sin θ`, `cos 2θ`, `sin²θ` |
| sine of x plus 1 | `sin(x + 1)` (parentheses only for multi-term arguments) |
| natural log of 2, log base 3 of x plus 1 | `ln 2`, `log₃(x + 1)` |
| x is less than or equal to 5 | `x ≤ 5` |
| x is approximately 3.47 | `x ≈ 3.47` |
| 3 plus or minus 0.5 | `3 ± 0.5` |
| 6 times 7 divided by 2 | `6 × 7 ÷ 2` ("divided by" between plain numbers may keep `÷`; in algebra, `/`) |
| a dot b, a cross b | `a · b`, `a × b` |
| the absolute value of x, the magnitude of a | `|x|`, `|a|` |
| 5 factorial | `5!` |
| n choose r | `ⁿCᵣ` (IB booklet) or `C(n, r)` (§6.2) |
| x tends to infinity | `x → ∞` |
| x is an element of the reals | `x ∈ ℝ` |
| A intersect B, A union B, A complement | `A ∩ B`, `A ∪ B`, `A′` |
| probability of A given B | `P(A|B)` |
| angle A B C equals 90 degrees | `∠ABC = 90°` |
| 25 degrees Celsius, 20 percent | `25 °C`, `20%` |
| the matrix 1 2 3 4 | `[1 2; 3 4]` (rows by `;`) |

## 4. Where JVoice differs today (measured 2026-09-29)

**How this was measured.** Each line was piped through `.build/release/JVoice --math-probe`, the release
build dated 2026-09-28 19:59 (the branch was `feat/guided-tour`, with HEAD at `987d2f9`). The probe prints
what Math Notation would paste.

| Spoken | JVoice today | Should be | Change | Status on `feat/math-format` (2026-09-29) |
|---|---|---|---|---|
| a plus b over 2 | `a + ᵇ⁄₂` | `a + b/2` | Stop printing stacked super/sub fractions (`ᵇ⁄₂`): many fonts render them badly and they can't be edited. Use `/`. | ✅ `a + b/2` |
| a plus b all over 2 | `a + b all over 2` | `(a + b)/2` | "all over" should close a whole numerator. | ✅ `(a + b)/2` — "all over" is a new weak keyword |
| pi over 6; a over b plus c over d; 1 over x squared | `π ÷ 6`; `a ÷ b + c ÷ d`; `1 ÷ x²` | `π/6`; `a/b + c/d`; `1/x²` | "over" → `/`. | ✅ `π/6`; `a/b + c/d`; `1/x²` |
| the limit … of sine of x over x | `the lim_(x→0) sin(x) ÷ x = 1` | `lim_(x→0) (sin x)/x = 1` | Same `/` rule; the `lim_(…)` form already matches. | ✅ `the lim_(x→0) (sin x)/x = 1` (a spoken leading "the" is kept, as for `the √14`) |
| the square root of x plus 1 | `the √x + 1` | `√(x + 1)` or `√x + 1` | Ambiguous when spoken (§6.1), but multi-term radicands need `√(…)`. | ✅ `√x + 1` by default (§6.1 smallest reading); `√(x + 1)` with "the square root of the quantity x plus 1" |
| the square root of b squared minus 4 a c | `the √b² - 4ac` | `√(b² - 4ac)` | Needs a scope rule. | ⚠️ default stays `√b² - 4ac` (§6.1 smallest reading); "the square root of **the quantity** b squared minus 4 a c" → `√(b² - 4ac)` |
| a sub n equals a sub 1 plus n minus 1 times d | `aₙ = a₁ + n - 1 · d` | `aₙ = a₁ + (n - 1)d` | `·` for "times" between terms reads as a dot product; use juxtaposition or `×`. | ✅ `aₙ = a₁ + (n - 1)d` (a "times" after "… ± 1" takes the difference) |
| 6 times 7 divided by 2 | `6 · 7 ÷ 2` | `6 × 7 ÷ 2` | `×` between numbers. | ✅ `6 × 7 ÷ 2` |
| sine squared theta plus cosine squared theta | `sin²(θ) + cos²(θ) = 1` | `sin²θ + cos²θ = 1` | Parentheses only for multi-term arguments. | ✅ `sin²θ + cos²θ = 1` |
| d y by d x equals … | `d y by dx = 3x² - 4` | `dy/dx = 3x² - 4` | Add the derivative forms. | ✅ `dy/dx = 3x² - 4` (also "d y d x") |
| f prime of x | `f prime of x = 2x + 1` | `f′(x) = 2x + 1` | Add "prime". | ✅ `f′(x) = 2x + 1` |
| f inverse of x | unchanged | `f⁻¹(x)` | Add. | ✅ `f⁻¹(x)` (converts on its own) |
| 10 to the power of minus 3 | unchanged | `10⁻³` | Add "to the power of". | ✅ `10⁻³` |
| e to the minus x squared | `e to the minus x²` | `e^(-x²)` | Nested script → fallback. | ✅ `e^(-x²)` |
| H 2 O | unchanged | `H₂O` | Only with a safe chemistry rule (§6.4). | ⏸ open decision §6.4 — not implemented |
| 5 factorial | unchanged | `5!` | Add. | ✅ `5!` (on its own only when it ends the sentence: "a 2 by 2 factorial design" stays words) |
| the natural log of 2 | unchanged | `ln 2` | Add. | ✅ `the ln 2` (converts on its own; the spoken "the" is kept) |
| x tends to infinity | unchanged | `x → ∞` | Add "tends to". | ✅ `x → ∞` (after a lower-case variable or `f(x)` only) |
| 20 percent of 50 | unchanged | `20% of 50` | Add as a weak word (converts only inside an activated maths run, principle 7). | ✅ weak: alone it stays words; inside an equation `20% of 50 = 10` |
| log base 3 of x plus 1 | `log₃(x) + 1` | `log₃(x + 1)` | Scope (§6.1). | ⚠️ default `log₃x + 1` (§6.1 smallest reading); "log base 3 of the quantity x plus 1" → `log₃(x + 1)` |
| angle A B C | `∠ ABC` | `∠ABC` | No space after `∠`. | ✅ `∠ABC = 90°` (alone, "angle A B C" stays words — weak) |
| n choose r | `C(n, r)` | `ⁿCᵣ` or `C(n, r)` | David's call (§6.2). | ⏸ open decision §6.2 — `C(n, r)` kept |

Status legend: ✅ matches on `feat/math-format` · ⚠️ the default is §6.1's smallest reading; the spoken grouping
word "the quantity" (a new weak open bracket) gives the grouped form · ⏸ an open decision in §6, left as is.
The before/after probe table for every §3/§4 example is in `docs/math-notation-progress.md`.

Already matching the format:
- `x² + y² = z²`, `x₁ + x₂`, `e^(iπ) + 1 = 0`, `∫₀¹ x² dx`, `∑ᵢ₌₁ⁿ i`
- `θ = π`, `α + β = γ`, `x ≤ 5`, `x ≠ y`, `x ≈ 3.47`, `3 ± 0.5`
- `|x|`, `x ∈ ℝ`, `A ∩ B`, `A ∪ B`, `a · b`, `∛27`, `xⁿ + 1`
- Ordinary sentences stay untouched ("I went to the shop and bought 3 apples").

## 5. The Math Notation toggle must actually save time

**Requirement (David, 2026-09-29).** Switching Math Notation **off** must make dictation measurably
faster, not just change the formatting. BetterScreenshot's new Capture Text toggle does this: it skips
every maths-only pass and is ≈ 3× faster with it off (median 413 → 133 ms per capture).

**JVoice today: the toggle saves no measurable time.**
- `MathSpeech.convert` is pure text processing. Measured on 2026-09-29: 4,400 dictations in 0.19 s with the
  release build, including process start — about **0.04 ms per dictation**.
- A whole dictation takes 0.5–1 s, almost all of it Whisper decoding. `docs/HANDOFF.md`, 2026-09-23 entry:
  formatting plus pasting cost 3–10 ms end to end.
- The toggle only gates `convert`, so on and off take the same time.

**What to do.**
1. **Keep "off" free of all maths work**, now and later. Nothing maths-specific may run when the toggle is
   off. One exception: the `RepetitionGuard` / `PhraseLoopGuard` maths exemptions. They exist so that
   dictated numbers are not mistaken for a decoder loop and re-decoded. They *save* time, keep them always on.
2. **Gate decode-side maths features on the toggle.** These are the only things that can make the two
   modes differ in speed, so decide deliberately:
   - **Maths words in the vocabulary prompt** ("squared, cubed, sine, cosine, theta, integral, derivative"):
     this may help Whisper hear maths, but the custom-word prompt already costs ≈ 0.2 s per decode
     (`docs/HANDOFF.md`, 2026-09-23 speed work). Add maths terms only when the toggle is on, and only if a
     measured accuracy gain on real maths dictation justifies the cost.
   - **Any second pass** (a maths-specific re-decode, or a heavier grammar or model for maths) runs only
     when the toggle is on.
3. **Measure both modes.** `BenchRunner` (the `--bench` mode) applies `MathSpeech.convert` unconditionally
   (`BenchRunner.swift` ≈ line 115). Add a `--no-math` flag, run the same clips with and without it, and
   record stop→paste for each. Add the numbers to the Settings help text only if the difference is real.
   *(2026-09-29, `feat/math-format`: `--no-math` exists and the whole-file path prints `postprocess: … ms`;
   the clips have NOT been run yet.)*
4. **Say it honestly in Settings.** Today's subtitle, "Spoken equations become symbols: x squared equals 4
   → x² = 4", is accurate. Don't claim "off is faster" until item 3 shows it.

## 6. Decisions and gaps to settle

1. **Scope when speaking** — where an exponent, root, numerator or function argument ends.
   - Speech has no brackets. Suggested closing words: "all over" (whole numerator), "end root" / "end
     power" / "close bracket", "the quantity … " (opens a group), a spoken "comma".
   - Default when nothing closes a group: the smallest reading (`√x + 1`, `xⁿ + 1`).
   - Grouping words must be ones nobody says in ordinary speech, or the no-bleed guarantee breaks.
2. **Combinations:** the IB formula booklet writes `ⁿCᵣ` (and the binomial coefficient in brackets);
   JVoice prints `C(n, r)`. Choose one; `ⁿCᵣ` matches IB.
3. **Units:** IB uses `m s⁻²` and `kg m⁻³`; everyday text uses `m/s²`. Choose one; BetterScreenshot keeps
   whatever the screenshot shows.
4. **Chemistry** (`H₂O`, `CO₂`, `Fe³⁺`): useful for IB chemistry, but "H 2 O" spoken as letters and digits
   is also ordinary speech ("room H 2"). Only convert inside an activated run, or with an explicit word
   ("formula H two O").
5. **Paste targets that can't take Unicode:** Excel formulas, calculators, code and LaTeX editors
   (Overleaf, Notion equations). A later "Math format: Unicode / ASCII (`x^2`, `*`, `sqrt()`) / LaTeX"
   choice could serve them, in both apps. Not requested yet.
6. **Fonts:** a few characters (`ₐ ᵢ ⱼ ᵥ`, `∛ ∜`) are missing from some fonts and show as boxes. That is a
   reason to keep fallbacks rare and never to invent look-alike characters.
7. **Decimal separator:** IB uses `.` (`3.14`); Romanian writes `3,14`. Keep `.` for spoken "point".
8. **Keep the two apps in sync.** When the format changes, update this document, BetterScreenshot's
   Part 8 §8.2, and both JVoice engines (Mac + Windows) together. BetterScreenshot's test cases
   (`../BetterScreenshot/tools/ocr-bench/Sources/ocr-bench/`) are a ready-made list of canonical outputs
   to borrow.
9. **A Greek name outside an equation** (decided 2026-10-04, branch `feat/math-context`): it becomes its
   letter only through **context promotion** — the rest of the dictation holds an equation with a letter
   in it, or the name sits in a maths slot ("value of λ", "solve for θ", "in terms of π", "let λ be"),
   and no veto applies ("AWS Lambda", "Pi Day", "omega 3"). Otherwise it stays a word. Rules:
   `docs/math-context-design.md`; code: `Sources/JVoice/Services/Transcription/Math/MathContext.swift`.

## 7. How to verify a change

- `.build/release/JVoice --math-probe "<text>"`, or pipe one dictation per line. It prints
  `CHANGED|before|after` or `same|text` and never opens the app's UI. Run the §3/§4 examples through it.
- **No-bleed:** sweep a real corpus (Recent Transcripts in `~/Library/Preferences/com.jvoice.app.plist`,
  key `jvoice.app.transcriptHistory`, and the corpora under `.build/bench-2026-09-23/hunt-math/`). Read
  every CHANGED line.
- Unit tests: `./scripts/run-logic-tests.sh`, `Tests/JVoiceTests/MathSpeechTests.swift`,
  `MathSymbolsTests.swift`, and the Windows `MathSpeechTests.cs`.
- Accuracy on David's real maths dictation: `docs/math-accuracy/README.md`. It is gitignored and holds
  personal transcripts, so never commit it.
- Speed: `--bench` with and without maths (§5, item 3).
