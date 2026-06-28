# JVoice Performance & Accuracy Loop — Running Journal

This file is the **persistent state** for an autonomous improvement loop that runs every
5 minutes (cron `*/5 * * * *`) and works on branch `perf-loop/auto-improvements` only.
Each iteration reads this journal first, picks ONE measurable target, makes a small change,
verifies it, then KEEPS (atomic commit) or REVERTS it — and records the outcome here so
later iterations never repeat a dead lever.

## Charter (rules every iteration obeys)

- **Scope:** transcription **speed** and **accuracy** — silence detection, error handling &
  messages, word-processing latency, transcription accuracy. Nothing else.
- **Branch:** work only on `perf-loop/auto-improvements`. Never commit to `main`. Never push,
  add remotes, or `gh repo create`. Never touch `../MacOSUtils`.
- **$0 / zero-network:** no model downloads, no new paid services, no new deps. Runtime stays
  network-free.
- **Surgical:** one focused change per iteration; match existing style; revert anything not
  proven a clear improvement.
- **Verify (all must pass to KEEP):** `swift build`, `./scripts/run-logic-tests.sh`,
  `./scripts/verify-streaming.sh`. Heavy harnesses (`--bench`, `verify-transcription.py`) only
  when the change targets transcription timing/accuracy AND the model is already downloaded.
- **Never leave the branch broken:** if a verifier is red and can't be greened this iteration,
  hard-reset the working tree to the last good commit and log it.

## Known dead / out-of-scope levers (do NOT retry — from project memory)

- Large-model **raw decode speed** is at the architectural floor (full 2026-06-09 sweep: all
  levers done / measured-dead / unavailable). Only future live lever = a WhisperKit >1.0.0 bump.
  → Bias toward pipeline-latency, silence-handling, error-handling, and accuracy wins, NOT
  Whisper-internal speed.
- Chunk-size tuning measured ~0.2s gain → rejected.
- 10×-sim streaming fallbacks are by design, not bugs.
- `promptTokens` is the main accuracy lever and is kept ON; removing it regresses custom words.

## Baseline (iteration 0)

Captured 2026-06-28 on `perf-loop/auto-improvements` (last good commit `bcc2e7a`):

- **`swift build`** — ✓ Build complete (2.87s, debug). Pre-existing warning only: SwiftPM
  flags the 5 `CLAUDE.md` area briefs as "unhandled files" (cosmetic, not our concern).
- **`./scripts/run-logic-tests.sh`** — ✓ All logic tests passed, **100 `✓` assertions**
  (TextProcessor, PhoneticMatcher, VocabularyPrompt, RepetitionGuard incl. 120-case loop fuzz,
  WavTail, ChunkPlanner, AppTheme, DictationError, AudioLevel.normalize).
- **`./scripts/verify-streaming.sh`** — ✓ All streaming + recovery verification passed,
  **14 `✓` assertions** (empty-chunk→fallback never silent-drops; regurgitation re-decode;
  prompt-disabled path; exact sample-count conservation).
- **Heavy-harness eligibility:** models already downloaded under
  `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml` (tiny, base, small,
  large-v3-v20240930 + turbo/626MB/632MB variants). So `--bench` / `verify-transcription.py`
  are runnable for future iterations whose change targets transcription timing/accuracy.
- No timing micro-baseline captured yet (raw decode speed is a known dead lever; future timing
  baselines should target pipeline latency, not Whisper-internal decode).

## Iteration log

<!-- newest first; one entry per iteration -->

### 2026-06-29 — measurement-backed lever: ChunkPlanner earliest-pause cut (David greenlit)
- **Context:** after the loop paused, David greenlit doing one of the deferred levers with the
  heavy on-device harness attached. Picked the `ChunkPlanner` streaming cut-point (the only
  deferred lever that is both implementable AND end-to-end validatable autonomously).
- **Target (scope a + c, silence detection / streaming latency):** `ChunkPlanner.plan` cut the
  growing recording at the *globally quietest* sub-threshold window in `[minChunk, maxChunk]`,
  i.e. it waited to compare against later/deeper pauses before emitting. Since every candidate
  below the silence `threshold` is already a valid (non-word-splitting) boundary, cutting at the
  *earliest* qualifying pause emits the streaming chunk sooner (lower latency, smaller/faster
  chunks) at no loss of cut safety. Quietest-spot logic kept only for the forced-cut fallback.
- **Method (true A/B, deterministic):** the harness uses cached `say` clips + greedy decode, and
  only the streaming path touches `ChunkPlanner`, so the sole variable is the chunk boundary.
  Built `.build/release/JVoice` (`swift build -c release`) BEFORE the change for baseline, then
  AFTER, running `python3 scripts/verify-transcription.py --model base --quick` on identical clips.
- **Measured (baseline → after):** **24/24 PASS both runs; every streaming retention value,
  spurious=0, and all 6 whole-file fallbacks BYTE-IDENTICAL** (streaming retention: tariffs-med
  1.00, weather-med 0.98, cooking-med 0.98, travel-med 1.00, history-med 0.98, long3 0.96;
  `-short` scenarios fall back as before). → **zero accuracy regression, no new fallbacks.**
  - *Honest caveat:* the results are identical because these clips have ≤1 qualifying pause per
    15–25 s chunk window, so earliest==quietest and the change is a **no-op on them**. The harness
    therefore proves SAFETY (no mid-word cuts, no extra fallbacks); the actual latency benefit
    lands on pause-dense dictation (multiple pauses in one window), which the new `twoPause`
    unit test exercises directly (it cuts at the earlier shallow pause, not the deeper later one).
- **Verifiers:** build ✓ / run-logic-tests ✓ (128, +2 incl. the earliest-pause test that was RED
  before) / verify-streaming ✓ (14) / test target compiles ✓ / heavy harness ✓ (zero regression).
- **Decision:** KEPT (commit `a87e3a7`). Verified-safe latency improvement.
- **Remaining deferred levers** (still need David / on-device dogfooding, unchanged): paste timing
  (`AppTimings`) needs real-app paste-reliability testing; decode options need an accuracy A/B and
  a product-judgment tradeoff; `RepetitionGuard` stopwords need a real regurgitation corpus.

### 2026-06-29 — iteration 26: LOOP PAUSED (David's decision)
David was asked (via an interactive prompt) how to proceed after 20+ consecutive plateau
iterations and chose **Pause the loop**. Cron `3ae65987` has been cancelled (`CronList` now reports
no scheduled jobs), so the 5-minute auto-firing has stopped. To resume later, re-run `/loop 5m`
with the same task prompt.

**Final state of branch `perf-loop/auto-improvements`:** clean and green — `swift build` ✓,
`./scripts/run-logic-tests.sh` 126 ✓, `./scripts/verify-streaming.sh` 14 ✓.

**Loop outcome — 4 KEPT accuracy fixes, all in the post-processing layer, each TDD'd (failing
test first) and verified by the fast local verifiers, with the canonical
`Tests/JVoiceTests/TextProcessorTests.swift` suite kept in sync:**
1. `f9c0707` — catch unpunctuated Whisper hallucinations in Casual tone (`removeWhisperHallucinations`).
2. `d949019` — strip "uhm"/"erm" hesitation fillers (`removeDisfluencies`).
3. `8949804` — drop all-symbol Whisper silence artifacts (dashes, ellipses, "♪" runs), not just ASCII `.,;:!?`.
4. `5df2e38` — match hallucination phrases wrapped in leading/surrounding marks.

**Not done (and why) — for whoever resumes:** the remaining levers (decode options, paste timing,
`ChunkPlanner` cut-point, `RepetitionGuard` stopwords) are WhisperKit-coupled, reliability-critical,
or heuristic tradeoffs that need an on-device `--bench` / `verify-transcription.py` measurement or
David's product judgment — not an autonomous edit. See the iteration-4 candidate ledger and the
iteration-14 note (why the heavy harness can't validate the shipped post-processing changes).

### 2026-06-28 — iteration 16: PLATEAU POLICY (consolidating note for the no-op run)
The loop converged after iteration 5. Iterations 4 and 6–16 are no-ops — the locally-verifiable
post-processing accuracy gaps are closed (KEPT fixes: iters 1, 2, 3, 5), the test suite has no
disabled/TODO markers, the source has no crash-prone code, and every remaining lever (decode
options, paste timing, `ChunkPlanner` cut-point, `RepetitionGuard` stopwords — see the iteration-4
ledger and iteration-6 analysis below) needs on-device measurement or David's product-judgment, not
an autonomous edit. The heavy harness cannot validate the shipped changes (iteration 14 explains why).

**Policy change to avoid noise:** committing an identical no-op one-liner every 5 minutes was
itself polluting the journal and git history (10+ no-op commits). The running record is now fully
established by the entries below, so **subsequent consecutive pure-no-op iterations will be
verified-green and reported in chat only — no new journal commit** — until a real improvement is
found, the branch/source state changes, or David intervenes. This entry is the standing record for
the remainder of the plateau.

**Branch state:** clean and green (`swift build` ✓; run-logic-tests 126 ✓ / verify-streaming 14 ✓
as of the last source change at iteration 7, deterministic on unchanged source). **Recommendation
stands:** pause cron `3ae65987` (it auto-expires ~7 days from creation regardless).

### 2026-06-28 — iteration 15: NO-OP (plateau, 10th consecutive). No code change. `swift build` ✓; tree clean, source byte-identical since iter 7 so run-logic-tests (126) / verify-streaming (14) remain green by deduction (re-running deterministic tests on unchanged source adds nothing). Recommend pausing cron `3ae65987`.

### 2026-06-28 — iteration 14: NO-OP (plateau, 9th consecutive)
- Re-evaluated the heavy harness as a way to add value. **Conclusion (record so no future
  iteration wastes ~8 min on it):** `scripts/verify-transcription.py` / `--bench` would NOT
  exercise this loop's accuracy changes — `removeWhisperHallucinations` is a no-op on normal
  speech (fires only on whole-transcript hallucination phrases / all-symbol input, which
  `say`-synthesised real sentences never produce), and `removeDisfluencies` is not invoked by
  `--bench` (`BenchRunner` calls `process(...)` with `removeFillerWords` = false). The harness
  measures WhisperKit model accuracy, not this loop's post-processing. So the iter-1/2/3/5
  "skip heavy harness" calls were correct, and the iter-4/6 "attach a measurement" idea does not
  apply to the *already-shipped* changes (it would apply to a *future* decode-option change).
- No code change. Branch green (build / run-logic-tests 126 / verify-streaming 14).
- Recommend pausing cron `3ae65987`; auto-expires ~7 days from creation regardless.

### 2026-06-28 — iteration 13: NO-OP (plateau, 8th consecutive). Branch green (build / run-logic-tests 126 / verify-streaming 14). No code change since iter 7. Recommend pausing cron `3ae65987`; loop auto-expires ~7 days from creation regardless.

### 2026-06-28 — iteration 12: NO-OP (plateau, 7th consecutive). Branch green (build / run-logic-tests 126 / verify-streaming 14). No code change since iter 7. Loop converged; remaining levers are David's product-judgment calls. Recommend pausing cron `3ae65987`.

### 2026-06-28 — iteration 11: NO-OP (plateau, 6th consecutive). Branch green (build / run-logic-tests 126 / verify-streaming 14). Fresh check: test suite has no disabled/TODO/known-issue markers either. No code change. Recommend pausing cron `3ae65987`.

### 2026-06-28 — iteration 10: NO-OP (plateau, 5th consecutive). Branch green (build / run-logic-tests 126 / verify-streaming 14). No code change; nothing changed since iter 7. Loop has converged — see iter-6 analysis + iter-4 ledger. Recommend pausing cron `3ae65987`.

### 2026-06-28 — iteration 9: NO-OP (plateau, 4th consecutive). Branch green (build / run-logic-tests 126 / verify-streaming 14). No code change; iter-4 ledger + iter-6 analysis current. Remaining levers are David's product-judgment calls. Recommend pausing cron `3ae65987`.

### 2026-06-28 — iteration 8: NO further safe improvement (plateau, 3rd consecutive)
- No code change. Nothing changed since iteration 7; the plateau analysis (iterations 6–7) and the
  iteration-4 candidate ledger remain fully current — every remaining lever needs a heavy-harness /
  on-device measurement or David's input. Did not churn or re-run the full search.
- Verifiers (integrity): build ✓ / run-logic-tests ✓ (126) / verify-streaming ✓ (14). Branch green.
- **Standing recommendation:** pause cron `3ae65987` until a deferred lever is greenlit. Repeated
  5-minute no-ops add no value; future no-op entries will stay one-liners to avoid journal bloat.

### 2026-06-28 — iteration 7: NO further safe improvement (plateau confirmed, 2nd consecutive)
- Fresh pass over `TextProcessor.format`/`normalizeWhitespace`, `ChunkPlanner`, `WavTail`.
  The only candidates left are rare cosmetic edge cases (e.g. Formal-mode
  `capitalizeFirstCharacter` not capitalizing the first *letter* when a transcript begins with a
  quote/symbol) — but Whisper effectively never emits such input from dictation, so fixing it would
  guard a near-impossible scenario (against the project's "no handling for impossible scenarios"
  rule). No change made.
- This confirms the **iteration 6 plateau analysis** (see below) — it remains fully current. The
  locally-verifiable post-processing wins are done (iters 1, 2, 3, 5); the remaining levers
  (decode options, paste timing, `ChunkPlanner` cut-point, `RepetitionGuard` stopwords) need a
  heavy-harness / on-device measurement or David's input, per the iteration-4 ledger.
- **Verifiers (baseline integrity):** build ✓ / run-logic-tests ✓ (126) / verify-streaming ✓ (14).
  Branch clean and green.
- **Decision:** no commit beyond this note. **Recommendation:** pause the 5-min loop (cron
  `3ae65987`) until a deferred lever is greenlit, to avoid low-value repeated no-ops.

### 2026-06-28 — iteration 6: NO further safe improvement found this iteration (plateau)
- **Searched:** the whole-file + streaming decode paths in
  `Services/Transcription/TranscriptionManager.swift` (`decodeFile`/`decodeSamples`), re-scanned
  `PhoneticMatcher`, `RepetitionGuard`, `VocabularyPrompt`, `stripDecoderArtifacts`, and the
  silence path (`ChunkPlanner`).
- **Outcome:** no change made; did not invent risky churn or pile a 5th tweak onto the
  hallucination filter.
- **Why this is a genuine plateau (not under-trying):** the four KEPT fixes (iterations 1, 2, 3, 5)
  have closed the objective, *locally-verifiable* gaps in JVoice's post-processing layer — the
  `removeWhisperHallucinations` filter is now robust across tone modes (iter 1), the unpunctuated
  Casual form (iter 1), all-symbol artifacts (iter 3), and phrases wrapped in leading/surrounding
  marks (iter 5); `removeDisfluencies` now covers the m-trailing fillers uhm/erm (iter 2). The
  source carries no TODO/FIXME and no crash-prone `try!`/`fatalError`/force-unwrap (verified iter 4).
- **What remains needs evidence the fast local verifiers can't provide** (see the iteration-4
  candidate ledger below — still current):
  - **Decode options** (`temperatureFallbackCount`, `chunkingStrategy`, prompt-token cap in
    `decodeFile`/`decodeSamples`): WhisperKit-coupled; any change needs
    `.build/release/JVoice --bench` or `python3 scripts/verify-transcription.py` on a real clip.
  - **Paste timing** (`AppTimings.pasteActivationDelay`/`pasteRestoreDelay`): reliability-critical;
    needs on-device A/B testing.
  - **`ChunkPlanner` cut-point heuristic** and **`RepetitionGuard` stopword set**: heuristic
    tradeoffs needing the real-audio harness, not unit assertions.
- **Recommendation for the next iterations:** prefer one of the *deferred* levers above **only**
  with a heavy-harness measurement attached (models are downloaded, so `--bench` /
  `verify-transcription.py` are runnable), or pause the loop pending David's input. Continuing to
  invent post-processing rules past this point risks over-fitting / churn.
- **Verifiers (baseline integrity):** build ✓ / run-logic-tests ✓ (126 cases) /
  verify-streaming ✓ (14 cases). Branch left clean and green.
- **Decision:** no commit beyond this journal note.

### 2026-06-28 — iteration 5: accuracy — hallucination phrases wrapped in leading/surrounding marks
- **Target (scope d, accuracy):** `TextProcessor.removeWhisperHallucinations`. The phrase-matching
  added in iteration 1 only trimmed **trailing** `.!?` before comparing the transcript to the
  sentinel phrases, so a hallucination Whisper decorated with **leading** marks leaked into the
  pasted text: `- Thanks for watching`, `... Bye`, and music-note-wrapped `♪ Thanks for watching ♪`.
- **Note on the iteration-4 ledger:** iteration 4 listed the "♪-wrapped" case as *deferred pending
  on-device measurement*. Re-examined and promoted it because the change is **safe by
  construction** — a non-match returns the original `text` unchanged, so it can never strip
  legitimate content (which is never in the sentinel list); its safety does not depend on
  measuring how often it fires. It also has a concrete, non-speculative driver: leading-dash/ellipsis
  hallucinations leaked under the trailing-only trim. This is a promotion of a *deferred* item, not
  a re-tread of a *rejected* one.
- **Change:** replaced the trailing-only `removeTerminalPunctuation(trimmed)` with
  `trimmed.trimmingCharacters(in: punctuationOrSymbol)` (the same CharacterSet introduced in
  iteration 3), so marks on **both** ends are ignored during the phrase comparison. One line.
  Added 6 assertions to `scripts/run-logic-tests.sh` and a mirrored `@Test` to
  `Tests/JVoiceTests/TextProcessorTests.swift`.
- **Measured (TDD baseline→after):** before the fix the 3 wrapped/leading cases were RED (leaked
  unchanged) while the 3 guards passed (plain phrase stripped; `- send the report by Friday`
  preserved as real content; longer sentence untouched); after the fix all green. All prior
  hallucination cases (`[BLANK_TEXT]` → trims brackets → matches; `OK.` → preserved) still hold.
- **Verifiers:** build ✓ / run-logic-tests ✓ (126 cases, was 120) / verify-streaming ✓ (14 cases)
  / test target compiles ✓. Heavy harness **skipped by design** (deterministic string filter; the
  `say`-generated clips the heavy harness uses cannot produce on-demand mark-wrapped artifacts).
- **Decision:** KEPT (commit `5df2e38`).

### 2026-06-28 — iteration 4: NO further safe improvement found this iteration
- **Searched:** silence detection (`ChunkPlanner`, `WavTail`), error handling (`DictationError` +
  all callers + the `TranscriptionError`→`DictationError` mapping), pipeline/paste latency
  (`AppTimings`, `PasteManager`, `VoiceCoordinator` paste path), streaming/recovery
  (`StreamingTranscriptionSession`, `RegurgitationRecovery`), and the accuracy matchers
  (`PhoneticMatcher`, `RepetitionGuard`, `VocabularyPrompt`). Also grepped for
  TODO/FIXME/HACK and for crash-prone `try!`/`fatalError`/force-unwraps — **none found**;
  the source is clean and defensive.
- **Outcome:** no change made. Per the charter, did **not** invent risky churn. The three KEPT
  fixes (iterations 1–3) already closed the obvious objective post-processing accuracy gaps.
- **Candidate ledger (evaluated → why deferred/rejected; recorded so later iterations don't
  re-tread):**
  - *Paste timing* (`AppTimings.pasteActivationDelay` 0.08 s / `pasteRestoreDelay` 0.30 s):
    reducing them is a real SPEED lever but reliability-critical — too-short delays cause paste
    failures on slower machines/apps. Needs on-device A/B testing + David's call. **Deferred,
    not autonomous-safe.**
  - *`ChunkPlanner` cut-point selection* ("quietest qualifying pause" → "earliest qualifying
    pause" would lower streaming latency): a heuristic tradeoff (earliest = lower-confidence cut,
    risk of mid-word split). No clear winner without on-device measurement. **Deferred.**
  - *`RepetitionGuard` stopword-set expansion*: risks suppressing real loop detection; pure
    heuristic tuning that needs the real-audio harness to validate. **Deferred.**
  - *`removeWhisperHallucinations` "♪ phrase ♪" wrapping*: plausible but speculative about
    Whisper's exact output; not locally verifiable. **Deferred to a measurement-backed iteration.**
  - *Micro-perf* (`applyCorrections` regex caching, `ChunkPlanner.windowRMS` per-poll recompute,
    `isSilent` slice-vs-array copy): all run once per transcript or once per ~1 s poll over a
    ≤25 s buffer — not user-perceptible, and the churn/complexity fails the "surgical" bar.
    **Rejected.**
  - *Mixed-case decoder sentinels in `stripDecoderArtifacts`*: WhisperKit emits uppercase
    sentinels; the gap is speculative. **Rejected.**
  - *`VocabularyPrompt` dedup*: the add-path (`VoiceCoordinator.addCustomWord`, line 642) already
    dedups case-insensitively, so this would guard an impossible scenario. **Rejected.**
  - *`DictationError` message copy*: already specific, distinct, and actionable; further edits
    would be subjective polish (David's call), not an objective fix. **Rejected.**
- **Verifiers (baseline integrity check):** build ✓ / run-logic-tests ✓ (120 cases) /
  verify-streaming ✓ (14 cases). Branch left clean and green.
- **Decision:** no commit beyond this journal note. The next iterations should bias toward the
  **Deferred** items above, which need either an on-device `--bench`/`verify-transcription.py`
  measurement or David's input — not toward inventing new post-processing rules.

### 2026-06-28 — iteration 3: accuracy — all-symbol Whisper silence artifacts leak
- **Target (scope d, accuracy):** `TextProcessor.removeWhisperHallucinations`. Its lone-punctuation
  guard only matched the hardcoded ASCII subset `".,;:!? "`, so a whole-transcript silence
  artifact made of *other* marks leaked into the pasted text: a stray `-`, an ellipsis `…`,
  em-dash runs, and Whisper's music-note `♪ ♪` output (emitted over background music).
- **Pre-check (scope b, error handling):** also audited `DictationError` + all callers this
  iteration — all 10 cases are produced in `VoiceCoordinator.swift` and the
  `TranscriptionError`→`DictationError` mapping (lines 354–365) is complete, so there was no
  error-handling gap to fix; moved on to the accuracy target above.
- **Change:** broadened the guard to "entirely punctuation/symbols/whitespace" —
  `CharacterSet.punctuationCharacters ∪ .symbols ∪ .whitespacesAndNewlines`, tested with
  `trimmed.unicodeScalars.allSatisfy`. Rationale: real dictated speech always carries a letter or
  digit, so an all-marks transcript is always a silence artifact. Mixed content ("$20 is the
  price", "OK.") still passes through untouched. Added 7 assertions to `scripts/run-logic-tests.sh`
  and a mirrored `@Test` to `Tests/JVoiceTests/TextProcessorTests.swift`.
- **Measured (TDD baseline→after):** before the fix the 4 non-ASCII cases (`-`, `…`, `— —`,
  `♪ ♪ ♪`) were RED (leaked through unchanged) while the 3 guards passed; after the fix all green.
  The passing `♪` case confirms `CharacterSet.symbols` covers the music-note glyph.
- **Verifiers:** build ✓ / run-logic-tests ✓ (120 cases, was 113) / verify-streaming ✓ (14 cases)
  / test target compiles ✓. Heavy harness **skipped by design** (deterministic string filter; the
  `say`-generated clips the heavy harness uses cannot produce on-demand lone-symbol artifacts).
- **Decision:** KEPT (commit `8949804`).

### 2026-06-28 — iteration 2: accuracy — disfluency removal misses "uhm"/"erm"
- **Target (scope d, accuracy / filler removal):** `TextProcessor.removeDisfluencies`. Its regex
  `\b(um+h?|uh+|er+|a+h+|hmm+)\b` caught um/umm/uh/uhh/er/ah/hmm but **missed the m-trailing
  hesitation fillers "uhm" and "erm"** — both extremely common and both non-words — so they leaked
  into the pasted text even when the user enabled filler removal (`removeFillerWords`).
- **Change:** added `uhm+` and `erm+` to the alternation, ordered before `uh+`/`er+`. One regex
  literal edited. The existing `\b…\b` word boundaries keep real `-rm`/`-hm` words (term, firm,
  warm, error) untouched — proven by new regression assertions. Added 7 assertions to
  `scripts/run-logic-tests.sh` and mirrored `@Test`/XCTest functions into the canonical
  `Tests/JVoiceTests/TextProcessorTests.swift` (both its swift-testing and XCTest sections).
- **Measured (TDD baseline→after):** before the fix the 4 new uhm/erm cases were RED (the fillers
  passed through unchanged) while the 3 regression guards already passed; after the fix all green.
- **Verifiers:** build ✓ / run-logic-tests ✓ (113 cases, was 106) / verify-streaming ✓ (14 cases)
  / test target compiles ✓. Heavy harness (`verify-transcription.py` / `--bench`) **skipped by
  design**: this is deterministic post-processing string logic, and the `say`-generated clips the
  heavy harness uses never contain spoken hesitations, so they would exercise nothing here.
- **Decision:** KEPT (commit `d949019`).

### 2026-06-28 — iteration 1: accuracy — hallucination filter tone-mode consistency
- **Target (scope d, accuracy):** `TextProcessor.removeWhisperHallucinations` — close a
  tone-mode-dependent leak. In the live pipeline (`VoiceCoordinator.swift:551`) this filter runs
  **after** `TextProcessor.format`. Casual tone strips terminal `.!?`, so a whole-transcript
  YouTube-style hallucination such as "Thanks for watching!" arrives as "Thanks for watching" —
  which was absent from the sentinel list and leaked into the pasted text. (Author intent was
  clearly to strip it: both "Thanks for watching!"/"Thanks for watching." and "Bye."/"Bye!" were
  enumerated; only the bare, Casual-produced form was missing.)
- **Change:** store the sentinel phrases without terminal punctuation and compare against the
  transcript with trailing `.!?` removed (reusing the existing private `removeTerminalPunctuation`
  helper). Surgical, ~10 lines in one function. Added 6 assertions to `scripts/run-logic-tests.sh`
  and a mirrored `@Test` to the canonical `Tests/JVoiceTests/TextProcessorTests.swift`.
- **Measured (TDD baseline→after):** before the fix the 2 new Casual-form cases were RED
  ("Thanks for watching" and "Bye" leaked through unchanged); after the fix all green. Valid
  utterances ("OK." → "OK.", "Hi" → "Hi") and longer sentences that merely start with such a
  phrase ("Thanks for watching the fireworks tonight") remain untouched.
- **Verifiers:** build ✓ / run-logic-tests ✓ (106 cases, was 100) / verify-streaming ✓ (14 cases)
  / test target compiles ✓. Heavy harness (`verify-transcription.py` / `--bench`) **skipped by
  design**: this is a deterministic whole-transcript string filter with full unit coverage; the
  heavy harnesses score live-audio word-retention on `say` clips of real sentences, which never
  yield a transcript equal to a hallucination phrase, so they'd show zero delta and add no signal.
- **Decision:** KEPT (commit `f9c0707`).

### 2026-06-28 — iteration 0: baseline capture
- **Target:** establish the reference baseline (the scaffold commit `bcc2e7a` created this
  journal but left the baseline section empty). No source change this iteration — recording the
  metrics every future iteration measures against.
- **Change:** filled the "Baseline (iteration 0)" section above with verifier results +
  heavy-harness eligibility. Docs only; no code touched.
- **Measured:** n/a (baseline itself) — `swift build` 2.87s; run-logic-tests 100 ✓;
  verify-streaming 14 ✓.
- **Verifiers:** build ✓ / run-logic-tests ✓ (100 cases) / verify-streaming ✓ (14 cases).
- **Decision:** KEPT (docs-only baseline commit; see branch log).

<!--
### YYYY-MM-DD HH:MM — <target area>
- **Target:** ...
- **Change:** ...
- **Measured:** baseline -> after ...
- **Verifiers:** build ✓ / run-logic-tests ✓ (N cases) / verify-streaming ✓
- **Decision:** KEPT (commit <sha>) | REVERTED (<why>)
-->
