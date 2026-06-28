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

_To be filled by the first iteration: record `swift build` result, `run-logic-tests.sh` pass
count, `verify-streaming.sh` result, and any timing numbers captured._

## Iteration log

<!-- newest first; one entry per iteration -->
<!--
### YYYY-MM-DD HH:MM — <target area>
- **Target:** ...
- **Change:** ...
- **Measured:** baseline -> after ...
- **Verifiers:** build ✓ / run-logic-tests ✓ (N cases) / verify-streaming ✓
- **Decision:** KEPT (commit <sha>) | REVERTED (<why>)
-->
