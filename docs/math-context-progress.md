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
    - `real.txt` line 38 (a casual remark that mentions lambda) still stays a word — no evidence.
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
- 2026-10-04: **"pie" rule** (separate commit, so it can be reverted alone).
  - `MathSpeech.lex` step 5c: "pie" lexes as the same weak π as "pi" only when a number item of one
    token (digits or one number word) comes right before it, a single ASCII letter other than
    a/A/I comes right after it, and no punctuation sits in between. "C equals 2 pie r" → `C = 2πr`;
    "2 pie r" alone, "I ate 2 pie r slices", "a pie chart", "x equals 2 pie a" stay as dictated.
    Never a context candidate.
  - Sweeps: identical to the previous entry (everyday 0 lines differ; `everyday.txt` has 39 lines
    containing "pie"). Logic tests **1204/1204** (+10). Timing on the 10,000-line file: baseline
    0.74 / 0.73 / 0.72 s, new 0.74 / 0.74 / 0.73 s (medians 0.73 vs 0.74 s, within 5 %).
  - Windows mirror: add the same lexer step to `windows/JVoice.Core/Math/MathSpeech.cs` (pending,
    with the list above).
  - **Next:** David dogfoods it (needs `swift build`, which is broken until the Command Line Tools are
    reinstalled — see the 2026-10-04 toolchain entry), then merge `feat/math-context` into
    `feat/math-format`, then the Windows mirror.
- 2026-10-04: **adversarial verify + fixes** (revision; design `docs/math-context-design.md` §9 is now
  the current design).
  - **Findings.** Verifiers reproduced 12 bleed patterns and 13 recall gaps against `761c3ee`.
    - Bleeds: an anchor alone ("In terms of beta access", "Let beta be honest", "value of theta
      healing") promoted, and counted as evidence for the WHOLE dictation; "capital X" swallowed
      "venture capital beta" (→ Latin-looking `Β`); "big X" ("big alpha energy"); old run bleeds with
      a letter ("T minus 10", "press X plus Y", "n plus 1 tickets") counted as evidence; one real
      equation promoted everyday nouns in later sentences ("alpha team", "still in beta", "lambda
      sensor", "tau is a protein"); finance greeks; "capital omega 99" → `Ω₉₉`; commas/brackets/dashes
      /colons hid a mention; "The cow says mu".
    - Recall: "Find alpha beta" blocked by Greek-beside-Greek; half-typeset products "2 π r", "ρ g
      h"; V5 cues that are IB words ("testing", "released", "version", "males", "watch", "rays");
      a comma-capital "Lambda" blocked every lambda; half-converted broken equations; `x̄`/`dy/dx`
      not evidence; "pie" only after a number; IB command stems ("Find λ.", "Let λ equal 3"); indexed
      "lambda 1 and lambda 2"; sigma.
  - **Fixes** (all in `Math/MathContext.swift` + `MathSpeech.Emitter`, details in design §9):
    evidence needs a letter operand AND a real construct (§9.1); anchors are local — own letter +
    own sentence — and stricter (§9.2), with new IB stems (command clause, cue nouns, trig, let …
    equal N, express … in terms of); V3 is an allowlist of words that may follow a name; V2 gains
    the/in/absolute/closed/… and "room 1"-style labels; V5 loses the IB words and gains finance,
    gaming, climbing, "call sign" and per-letter cues; mentions include brackets, dashes and a colon;
    deliberate capitals pass every veto plus a word-before allowlist; "big X" removed; two lower-case
    names are a product (αβ); indexed families (indices 0–2) render `λ₁`; a comma-capital no longer
    blocks its letter; a stretch with a relation left as words is never promoted; promoted stretches
    are written as one product ("2πr", "ρgh", "μmg", "sin θ"); "pie" widened (after a relation, before
    "over"/"root").
  - **Corpora** (gitignored, `.build/math-context/`): new `everyday-adversarial.txt` (103 lines: every
    verifier bleed input + 25 of my own probes of the new rules, e.g. "Let beta be 2 hours late",
    "Room 1 alpha and room 2 alpha are booked, x equals 4") and `math-adversarial.txt` (60 lines: every
    recall input, split one per line). Baselines `baseline-everyday-adversarial.out` /
    `baseline-math-adversarial.out` from `probe-baseline` (90c6836).
  - **Acceptance numbers** (new probe vs `probe-baseline` @ 90c6836):
    - `everyday.txt`: CHANGED 2 → 2, **0 lines differ**. `everyday-adversarial.txt`: CHANGED 77 → 77,
      **0 lines differ** (the verifiers' build differed on 78 of 103).
    - `real.txt`: 0 → 0, 0 differ. `prose.txt`: 268 → 268, 1 line differs (the same already-converted
      docs table row as before, now `sin θ, cos 2θ, sin²θ`).
    - `context.tsv`: **137/137**.
    - `math.txt`: CHANGED 247 → 270, 74 lines differ; a token diff shows only Greek names becoming
      letters, a number/letter/function joining one ("2π", "rθ", "Δx", "sin θ"), and indexed names.
      Versus `761c3ee`: 24 lines differ — 22 gains, 2 losses: "For part b, use the value of lambda
      from part a, which was 2." (no command word, no equation) and "…, lambda equals minus 1." (a
      broken equation is now left as words, not half-converted).
    - `math-adversarial.txt`: CHANGED 42 → 57.
    - Logic tests **1287/1287** (1204 + 83 new: 24 promote cases ×2, 32 no-bleed cases, 3 "big X"
      checks), mirrored as `greekNamesSurviveTheAdversarialVerify` in
      `Tests/JVoiceTests/MathSpeechTests.swift` (parse-checked; CI-only).
    - Timing, 10,000 lines (`math.txt` + `everyday.txt`), 3 runs: baseline 0.73 / 0.73 / 0.72 s, new
      0.74 / 0.74 / 0.74 s (medians 0.73 vs 0.74 s, +1.4 %, within 5 %).
  - **Known limitations** (design §9.6): bare "sigma" stays ∑ (David's 2026-09-29 decision); a
    mid-sentence capital is always a name ("value of Lambda", "4 Pi"); "our/your/a theta" vetoed even
    in maths; a single index ("So lambda 1 is 2"); "lambda's"/"lambda-max"; Whisper-written symbols
    ("x=2") are not evidence; "I" never a variable; "lambda 5 equals K" → `λ₅` (engine); residual risk
    "My favourite is alpha, x equals 2." → `α` (allowed slot + real evidence).
  - **Windows mirror (pending, no .NET here)** — on top of the earlier list: port `MathContext.cs`
    from the revised `MathContext.swift` (continuation allowlist, capitalBefore, labelWords, cue/command
    lists, two-word anti-cues, the trimmed V5); in `MathSpeech.cs` `Emitter`: E1 strong-construct
    check, verbatim-relation broken ranges, local + sentence anchors, comma-capital rule, indexed
    families, mention marks, `Juxtapose` rendering; the widened "pie" lexer step; port the 83 new
    assertions.
- 2026-10-04, the lead's own check after workflow `wf_d9d4cfe4-533` finished (HEAD `9119cb9`):
  - Rebuilt the probe; `./scripts/run-logic-tests.sh` passes 1287/1287.
  - everyday.txt, everyday-adversarial.txt and real.txt are byte-identical to the baseline.
  - David's examples behave as asked:
    - "Lambda is the unknown here, and we know that 5 equals K and X equals 5." →
      `λ is the unknown here, and we know that 5 = K and X = 5.`
    - "Lambda, I don't know, the pie is really tasty." → unchanged.
    - "lambda equals 5" → `λ = 5`.
  - Bugs that exist on the baseline too (not caused by this branch) and remain open:
    1. "given that" becomes the conditional bar: "find theta given that sine theta equals 0.5" →
       `find θ ∣ sin θ = 0.5`.
    2. The identity matrix "I" ends a run: "det of A minus lambda I equals 0" →
       `det of A - λ I equals 0` (half converted).
    3. "pie r squared" with no number before it stays `pie r²`.
  - Not done: building the full app (`swift build` is broken, see above), installing,
    dogfooding, and the Windows mirror.
- 2026-10-04 (later), David's first real dictation on the installed build:
  - Whisper wrote "Where's the lambda in this equation for x = 5?" and it pasted UNCHANGED. Two causes:
    1. The V2 veto: "the" right before a name blocks it.
    2. Equations Whisper already wrote as symbols ("x = 5", "5x + 7z = 5") are NOT counted as evidence.
       Whisper large-v3-turbo writes symbols itself most of the time, so this kills recall in practice.
  - David: "this probably goes for recognizing other wordings as well" → workflow #2 (recall on
    real wordings plus Whisper-written notation, without new bleeds).
  - Workflow #2 launched: run `wf_bb02298c-3ca` (measure: Whisper-style wordings corpus, everyday-whisper bleed corpus, rule ablation → implement → bleed/recall verify → fix → final SHIP/NOT-SHIP check). Snapshot of the installed engine for comparison: `.build/math-context/probe-v1`.
- 2026-10-04 (evening), workflow #2 implement stage — **recall rework** (design §10):
  - **What changed** (`Math/MathContext.swift`, `MathSpeech.swift` lexer + `Emitter`, one line in
    `MathScript.swift`):
    - Equations Whisper wrote as symbols are evidence (`MathContext.writtenEquations`: a window of
      notation tokens with a relation and a letter term — "x = 5", "5x + 7z = 5", "F = ma", "tan x =
      √3", "y=mx+c"; numbers-only "0 = 0" only beside maths words or a "value of ⟨name⟩" slot).
    - V2 per letter: the/this/our/in veto only alpha/beta/gamma/pi; a/an/my also lambda/omega;
      his/her/their all; lifted by evidence in the same stretch, evidence + a maths word in the same
      sentence, or the letter written by Whisper. V1 lifted for a non-everyday capital with an equation
      in its stretch. V3 allowlist widened (verbs, Whisper operators). V4 number rule only for
      alpha/beta/gamma/pi/omega; a lone index before is/if/… renders `λ₁`. Hyphen-minus is no dash.
      Broken-equation rule only for a spoken relation that is not dangling before when/if/….
    - New forms: glued names ("lambda's", "lambda²", "lambda=3"); "delta ⟨letter⟩" → `Δx` engine-wide
      (`Δx/Δt` as one factor); "pi r²" → `πr²`; "Is there a lambda such that" no longer `aλ`; "Pixel 9
      beta"-style product labels no longer `9β`.
    - Performance: sentence/stretch indices are precomputed (was quadratic), regexes compiled once,
      fast paths for plain words/numbers.
  - **Numbers** (final probe `.build/math-context/probe-v2`; references `probe-baseline` 90c6836,
    `probe-v1` cf22587):
    - `wordings.tsv` exact 460/467 (98.5 %): P 319/326 (97.9 %), S 141/141 (100 %). probe-v1: 239/467.
    - `everyday.txt` 0, `everyday-adversarial.txt` 0, `everyday-whisper.txt` 0 lines differ from
      probe-baseline (and from probe-v1).
    - `context.tsv` 137/137. `prose.txt` 0 lines differ from probe-v1. `real.txt` 0 differ.
    - `math.txt` 6 lines differ from probe-v1, all δ → Δ for a change ("Δx = 3", "Q = mcΔT", "v =
      Δx/Δt"). `math-adversarial.txt` 9 differ, all gains (57 → 60 changed).
    - David's 2026-10-04 dictations: 6 of 30 now promote (was 0); a word diff shows only Greek names
      becoming letters (and one "three lambda" → `3λ`), including the dictation that started this.
    - STRESS set (everyday lines with "x = 2." before / ", and x = 2." after): 108 lines differ from
      probe-baseline (probe-v1: 132; the ablation's recommendation: 136).
    - Logic tests 1387/1387 (+58: 21 promote cases ×2 incl. David's exact sentence in both written and
      spoken form, 16 no-bleed cases), mirrored as `greekNamesFollowRealWordingsAndWrittenNotation` in
      `Tests/JVoiceTests/MathSpeechTests.swift` (parse-checked; CI-only).
    - Timing, 10,000 lines (math.txt + everyday.txt), 5 runs: probe-v1 0.72–0.73 s, new 0.75 s (+3.4 %).
  - **Open**: "equals to" is still not a relation (own change); the 7 missed P rows and the risks are
    in design §10.5–10.6; Windows mirror not done; not installed.
- 2026-10-04 (night), workflow #2 fix stage — **fix round** after the verify of `28bcad5` (design §10.7):
  - **Why**: the verify reproduced 9 bleed families (e.g. "Set x = 5 in the config. The lambda is still
    timing out." → `The λ …`; "Plan B = 20 euros, and the omega is too expensive." → `ω`; "x = 2 and
    his lambda is broken." → `his λ`) and 17 recall families (e.g. "So lambda = -3.", "So lambda² = 4.",
    "sin(theta)", "lambda N" → `λ_N`, "equals to", "Where's the lambda coming from if x = 5?").
  - **What changed** (`Math/MathContext.swift`, `MathSpeech.swift`, `MathSymbols.swift`):
    - V2 rewritten: a determiner/possessive vetoes EVERY letter unless the name's own neighbourhood is
      maths (written letter, value statement, in/of an equation or maths noun, a question/command, a
      condition "when x = 5", a maths word); a status word after the name ("down", "fine", "best", …)
      cancels the lift. Everyday letters without a determiner need maths around them.
    - Whisper-written evidence: names count as letter terms in Whisper's windows (so "lambda = -3" is
      its own evidence); degrees, slash/power numbers, letter products, "2(x", "det(A"; labels ("Plan B
      = 20"), rankings ("S > A > B"), config keys ("lr=0.01"), "1x"/"100m" and the μ of units are never
      evidence.
    - New anchors (for which λ, "What's the value of λ?", "The value of λ is 3.", "λ in this equation",
      IB quantity nouns), new vetoes (naming nouns, slang adjectives, code/crypto/brand/game words).
    - New forms: "-lambda", "-omega²", "sin(theta", "N(mu", "e^(-lambda" (with the letter after inside
      the bracket: `sin(ωt + φ)`, `e^(-λt)`, `det(A - λI)`), "-2 lambda" → `-2λ`, "A = pie r²" → `πr²`.
    - Engine-wide: "equals to" → "="; Δ before a Greek name (`Δθ/Δt`); "pie r squared" after any word;
      a capital indexes only n/k (`λN`, `GMm`); "4 over 3 pi r cubed" → `(4/3)πr³`; ε₀/μ₀; unit
      letters ending an equation keep their space (`F = 12 N`, `10 N m`); a relation after only keywords
      ("has to equal to 3") or before unreadable notation is no broken equation.
  - **Numbers** (final probe `.build/math-context/probe-v3`; eval script recreated in the session
    scratchpad — the checks are the same as the recall-rework entry's):
    - Verify inputs: 0 of 81 bleed inputs change (v2: 81); 115 of 130 recall rows exact (v2: 1).
    - `everyday.txt` 0, `everyday-adversarial.txt` 0, `everyday-whisper.txt` (now 511 lines, the 81
      bleed inputs appended) 0 lines differ from probe-baseline. `prose.txt` 0 differ from probe-v2.
    - `wordings.tsv` (now 597 rows: two families appended) 573/597; P 431/455; S 142/142. On the
      original 467 rows 456 (P 315/326, S 141/141; v2 had 460) — 6 more P misses, each a determiner
      with only distant/other-stretch evidence, the price of the B1–B5 fixes (listed in design §10.7).
    - `context.tsv` 137/137. `math.txt` 7 lines differ from probe-v2, all fixes. `math-adversarial.txt` 0.
    - David's real dictations (2026-10-04 set + real.txt): vs v2 only "equals to" → "=" (8 lines) and
      the half-promoted α/β dictation now fully converted (the §10.6 doubt is closed).
    - STRESS: 29 lines differ from baseline (v2: 108).
    - Logic tests 1538/1538 (+151: 59 promote cases × 2, 33 no-bleed), mirrored as
      `greekNamesFixRoundRecallWithoutBleeds` in `Tests/JVoiceTests/MathSpeechTests.swift` (parse-checked).
    - Timing, 10,000 lines, 5 runs: v1 0.69–0.72 s, v2 0.73–0.75 s, v3 0.76–0.77 s.
  - **Open**: accepted risks and the not-fixed list are in design §10.7; Windows mirror not done
    (now also the §10.7 rules); not installed.
- 2026-10-04: workflow #2 (`wf_bb02298c-3ca`) finished with the final check's verdict SHIP (HEAD `3ce0edd`).
  - Installed with `SDKROOT=…/MacOSX26.5.sdk ./scripts/dev-install.sh`, and the branch pushed.
  - The installed app now converts David's sentence.
  - Snapshot of the installed engine: `.build/math-context/probe-v3-installed`.
  - Remaining recall gaps P1–P7 (from the final check) → workflow #3.
  - Workflow #3 launched: run `wf_c532e914-58a` (P1–P7 families: units, maths verbs, written notation such as pi/4 or (x + λ)², the colon / "the same as" half conversions; then bleed/recall verify → fix → SHIP check). Fresh corpora from round 2's check are saved as `everyday-fresh.txt` / `math-fresh.txt`.
- 2026-10-04 (late night), workflow #3 implement stage — **round 3** (design §11):
  - **What changed** (`Math/MathContext.swift` section "round 3", `MathSpeech.Emitter`): a name in an everyday
    place is a thing (P1); one meaning per dictation — a colon and an everyday letter's article are lifted for a
    letter converted elsewhere, with a second decision pass (P2); "the same as"/"such that"/"given that" before
    English is no broken equation (P3); definitions with filler (P4); whisper bars/brackets/arc functions/
    powered brackets/"pi/4"/window-only δ (P5); letter-specific quantity units and "we got" clauses (P6);
    strong maths vocabulary at sentence scope, maths-verb operands, definition anchors, "γ factor" (P7).
    Engine-wide: none (the rendering of runs is unchanged).
  - **Corpus**: `.build/math-context/round3.tsv` (259 rows, P1–P7, P and S per family; gitignored).
  - **Numbers** (probe `.build/math-context/probe-r3`, eval script recreated in the session scratchpad as
    `ev3.py`): round3.tsv 259/259 (v3 110); wordings.tsv 576/597, P 435/456, S 141/141 after relabelling the
    one row round 3 reverses ("Theta is 45 degrees." S → P; v3 on the new labels 572); context.tsv 137/137;
    everyday, everyday-adversarial, everyday-whisper, everyday-fresh 0 lines differ from baseline;
    verify2-bleed 43 differ from baseline (v3 44 — the one change removes the bleed "… by the way the omega
    is in the shop"); maths corpora 0 losses vs v3 (gains: math 8, math-fresh 19, verify2-recall 15; others 0);
    STRESS 14/15 (unchanged); a held-out set written after the rules: promote 40/40 (v3 9/40), 99 everyday
    lines 0 changed (one bleed found and fixed before: "Phi is the angle of my bed").
  - Logic tests 1662/1662 (+124: 42 promote cases ×2, 40 no-bleed; the "delta is run-only" assertion now
    says window-only), mirrored as `greekNamesRoundThreeQuantitiesVocabularyAndPlaces` in
    `Tests/JVoiceTests/MathSpeechTests.swift` (parse-checked; CI-only).
  - Timing, 10,000 lines, 5 runs: v3-installed 0.71–0.73 s, round 3 0.74–0.76 s (median +3.2 %).
  - **Open**: design §11.3; Windows mirror; not installed; verify/fix/SHIP stages of workflow #3 pending.
- 2026-10-05: workflow #3 was interrupted while its verify agents ran (the Mac went to sleep). The implement stage had already committed `27e5760`. Resumed the same run (`wf_c532e914-58a`, resumeFromRunId), which reuses the implement result and re-runs verify → fix → final check. Nothing from round 3 is pushed or installed yet.
- 2026-10-05: **PAUSED by David** (he had to close the machine). Workflow #3 was stopped during verify.
  - State: round 3 is committed as `27e5760`. It is pushed with this note, but it has NOT been
    adversarially verified and is NOT installed.
  - The installed app is round 2 (`3ce0edd`).
  - Resume from a Claude Code session in this worktree:
    `Workflow({scriptPath: "~/.claude/projects/-Users-davidghermansteinberg-Desktop-Home-Projects-Code-JVoice--claude-worktrees-math-context/a8ef1c78-bcf4-4895-a8b4-fe5408133bf2/workflows/scripts/jvoice-math-context-round3-wf_c532e914-58a.js", resumeFromRunId: "wf_c532e914-58a"})`.
    The implement stage is cached; verify → fix → final check re-run.
  - If that resume is not available (it only works in the same session), run the script's
    Verify/Fix/final-check stages by hand.
  - Then follow the usual ship steps:
    1. `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./scripts/run-logic-tests.sh`
    2. `SDKROOT=… ./scripts/dev-install.sh` (this quits and relaunches JVoice)
    3. `git push`
- 2026-10-05, correction: commit `243e166` ("pause note") accidentally also swept in the fix agent's
  PARTIAL, unverified round-3b edits. Those were uncommitted in the tree when the run was stopped.
  - The edits are kept on branch `wip/math-context-round3b-partial` (pushed).
  - The next commit restores the four source/test files to `27e5760` (verified round 3).
  - The branch tip is round 3 (`27e5760`) plus docs.
  - Resuming the workflow re-runs the fix stage from scratch. The verify findings are already cached
    in the run.
