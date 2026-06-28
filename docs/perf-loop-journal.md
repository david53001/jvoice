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
