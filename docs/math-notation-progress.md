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

Not started.

## Windows mirror list (changes `windows/JVoice.Core/Math/` + `windows/JVoice.Tests/MathSpeechTests.cs` need)

1. The whole Step 1 package: the grouping rule (`Scope`, `Run`, `Parser.subExpression`, rules 1–5 in the
   `Parser` doc comment), bare "to the" weak + `powerIsUnmistakable`, ordinal exponents (lexer step 1b),
   whisper's "x" between numbers as a weak "·" (lexer step 4b), the article-pair rule ("a plus one"),
   `MathSymbols.weakOperators = ["/"]` ("per" weak), "more than"/"is more than" removed from ">".
