# Math context — progress log (started 2026-10-04)

**What this is.** A running log for the "context-aware maths words" feature, so a session that starts
from nothing can pick up the work.

**Where the work is.**
- Branch `feat/math-context`. It starts from `feat/math-format` @ `90c6836`, the newest maths engine.
  That branch is installed for dogfooding but is NOT merged into `main`.
- Worktree: `.claude/worktrees/math-context`.
- Nothing has been merged, pushed or installed.

## The ask (David, 2026-10-04, dictated)

1. Make **"lambda" → λ** work when David is speaking mathematics. His screenshot showed `of λ.`, as in
   "find the value of λ".
2. Make the maths engine decide ambiguous words from the **context of the whole dictation**.
   - "lambda … 5 = K … X = 5": the other equations show it is maths, so write λ.
   - "lambda … the pie is really tasty": nothing else is maths, so keep the word "lambda".
   - "λ = 5" on its own must still convert, even with no other maths around it.
3. Run it as a multi-agent workflow, optimised to detect mathematical language as well as possible.

## Starting point (measured 2026-10-04 on the installed build)

- `--math-probe "lambda equals 5"` gives `λ = 5`. The "=" activates the run, so this already works.
- `--math-probe "find the value of lambda"` leaves the text unchanged. Greek letters are WEAK: they
  only convert inside a run that something else has already activated.
- The engine's no-bleed guarantee is structural and works one run at a time. A run is a stretch of
  consecutive maths words. Nothing looks at the rest of the dictation. See
  `Sources/JVoice/Services/Transcription/CLAUDE.md`, the `Math/` bullet and invariant 4.
- The old test corpora in `.build/bench-2026-09-23/hunt-math/` (494 everyday sentences and 367 maths
  dictations) no longer exist; a disk cleanup deleted `.build/`. New corpora go in
  `.build/math-context/` (gitignored).
- Baseline binary for before/after comparison: `.build/math-context/JVoice-baseline`, built from
  `90c6836`.

## Rules that apply here

- NEVER run `swift test` on this Mac. Use `./scripts/run-logic-tests.sh`, `swift build -c release`
  and `.build/release/JVoice --math-probe`.
- Only one build at a time. The Mac has 16 GB of memory.
- The Windows engine (`windows/JVoice.Core/Math/`) has to mirror the change, but there is no .NET on
  this Mac. Record the mirror list here instead.

## Log

- 2026-10-04: created the worktree and branch, and started the baseline build. Next step: the
  workflow (research → design → implement → adversarial verify).
- 2026-10-04: `swift build` is BROKEN on this Mac since the Command Line Tools 26.6 install on 2026-10-02.
  - Symptom 1: `swift-package` fails to start with a dyld error, "Symbol not found … BuildServerProtocol".
  - Symptom 2: the default SDK, `MacOSX27.0.sdk`, was built by a newer compiler (Swift 6.4) than the
    one installed (6.3.3).
  - Workaround for the maths engine: prefix commands with
    `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` (that symlink points to 26.5).
    Then `scripts/build-math-probe.sh [out]` (new; plain `swiftc`, no SwiftPM) builds a standalone
    `--math-probe`, and `./scripts/run-logic-tests.sh` passes (baseline 1123/1123).
  - The full app cannot be built until the Command Line Tools are reinstalled.
- 2026-10-04: launched workflow run `wf_d9d4cfe4-533`: research (engine map, ambiguity lexicon,
  corpora + baseline) → design (`docs/math-context-design.md`) → implement → adversarial verify
  (bleed + recall) → fix.
- 2026-10-04: built the test corpora in `.build/math-context/` (gitignored; `real.txt` and `prose.txt` hold personal
  transcripts, so never commit them). Files:
  - `everyday.txt`: 509 ordinary dictations that must never change.
  - `math.txt`: 318 maths dictations.
  - `context.tsv`: 137 rows of `input<TAB>expected`. `context-tags.txt` gives each row's tag, line for line:
    P = promote (needs context), C = cue-phrase only with no equation, K = already right, S = must stay,
    M = maths elsewhere but the word is not a symbol.
  - `real.txt`: 60 Recent Transcripts. These are stored AFTER conversion, so they already contain `=`.
  - `prose.txt`: 24,169 lines of docs.
  Baseline outputs are in `baseline-<name>.out`, from `probe-baseline` @ 90c6836.
  - CHANGED lines: everyday 2/509, math 247/318, real 0/60, prose 268/24169, context 94/137.
  - The baseline already gets 65/137 `context.tsv` rows right (all S/K/M) and 0 of the 72 P+C rows.
  - The 2 everyday bleeds are "2 plus 1 free months" → `2 + 1` and "stop at n minus 1" → `n - 1` (code chat).
- 2026-10-04: design written to `docs/math-context-design.md`.
  - **What it adds.** Evidence across the whole dictation, plus anchors and vetoes, decides whether a
    curated set of Greek words becomes the symbol.
  - **Evidence.** A converted segment with a letter operand, or an anchor phrase.
  - **Vetoes.** Collocations, casing and per-letter anti-cue words.
  - **Also new.** "lamda" alias; narrow run-only "pie".
  - **Next.** Implement per §4 of the design, then sweep against its §8 acceptance bar.
- 2026-10-04: **implemented** (context promotion; the "pie" rule is the next entry).
  - **Files.**
    - New `Sources/JVoice/Services/Transcription/Math/MathContext.swift`: the word lists (promotable
      names, V2 before-words, V3 after-words, V5 anti-cues per letter) and pure checks (`nameLike`,
      `namesSomething`, `vetoed`, `anchored`, `dictationVetoes`).
    - `MathSpeech.swift`: `convert` computes `contextOn` (any candidate item) and calls
      `Emitter.promote()` at the end; `Emitter.flush` sets `evidence` when a converted segment has a
      letter operand and records unconverted segments holding candidates (`Pending`); `promote()`
      vetoes, checks anchors, then rewrites in reverse (whole segment when it is only numbers +
      candidates — "2 pi," → "2π," — else only each name's own token).
    - `MathSymbols.swift`: "lamda" is a λ alias.
    - Tests: new section "a Greek name is decided by the whole dictation" in
      `scripts/run-logic-tests.sh` (which now also compiles `MathContext.swift`), mirrored as
      `greekNamesAreDecidedByTheWholeDictation` in `Tests/JVoiceTests/MathSpeechTests.swift` (CI-only).
    - Docs: area brief (`Sources/JVoice/Services/Transcription/CLAUDE.md`, `Math/` bullet +
      invariant 4), `docs/math-notation-format.md` §6 item 9.
  - **Deviations from the design** (all make it MORE conservative; each was forced by a sweep line):
    1. A **quoted** name is never promoted (`say "lowercase sigma"` is a mention). Without it 4 prose
       lines (maths docs quoting spoken forms) changed.
    2. **"big X"** is promotable only for the curated lower-case names and goes through every veto
       ("That's a big delta, and x equals 5." became `That's a Δ`). "capital X" / "uppercase X" stay
       promotable for every letter, V1-only, as designed.
    3. **One word, one meaning per dictation:** an occurrence vetoed as a NAME (V1, V2, V3, V4's
       capitalised-next-word and Greek-beside-Greek; not V4's number rule) blocks that letter for the
       whole dictation. Fixes "we had pi on pi day, x equals 3" (was `we had π on pi day`), and it is
       what keeps `real.txt` line 33 (David's own dictated ask, which says "it's not Lambda") unchanged.
  - **Acceptance numbers** (probe `.build/math-probe` vs `.build/math-context/probe-baseline`):
    - `everyday.txt`: CHANGED 2 → 2, **0 lines differ**.
    - `context.tsv`: **137/137 exact** (baseline 65/137); every P, C, K, S and M row passes.
    - `real.txt`: CHANGED 0 → 0, 0 lines differ.
    - `prose.txt`: CHANGED 268 → 268, 1 line differs — a docs table row that was already CHANGED:
      `| sine theta, cos 2 theta, …` now reads `sine θ, cos 2θ, …`. It sits in a line that already
      converts maths, and that is what promotion is for; accepted.
    - `math.txt`: CHANGED 247 → 257, 61 lines differ; a token-level diff confirmed that every changed
      word is a Greek name (or a number merged with one: "9 pi" → `9π`).
    - Logic tests: **1194/1194** (1123 before + 71 new).
    - Timing, 10,000 lines (`math.txt` + `everyday.txt` repeated), 3 runs each: baseline 0.74 / 0.75 /
      0.74 s, new 0.74 / 0.74 / 0.75 s — medians equal.
  - **Known gaps / not done.**
    - Rule 2 (item by item) leaves the neighbours as dictated: "r theta" → `r θ`, "sine theta" →
      `sine θ` (not `rθ` / `sin θ`). Widening rule 1 would touch non-Greek items; left as designed.
    - `real.txt` line 38 ("I forgot really what lambda is") still stays a word — no evidence.
    - Mid-sentence capitalised names are always vetoed (V1), so "…, Lambda is 5, x equals 2" whose
      capital came from whisper stays a word.
    - **Windows mirror pending** (no .NET on this Mac): `windows/JVoice.Core/Math/MathContext.cs`
      (static class mirroring `MathContext.swift`, but do NOT make bare "sigma" promotable — Windows
      still maps it to σ, `MathSymbols.cs:363`); `MathSymbols.cs` λ line →
      `Greek("λ", "Λ", "lambda", "lamda");`; `MathSpeech.cs` `Convert` (contextOn + `Promote()` after
      the last `Flush`), `Emitter` (`Evidence`, pending list, the quoted / big-X / name-propagation
      deviations above), `Flush` records pending entries in the `used == 0` and verbatim branches;
      port the assertions to `windows/JVoice.Tests/MathSpeechTests.cs`; add the invariant-4 exception
      paragraph to `windows/JVoice.Core/Math/CLAUDE.md`.
    - Not merged, not installed, not pushed.
