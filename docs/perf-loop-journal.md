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
