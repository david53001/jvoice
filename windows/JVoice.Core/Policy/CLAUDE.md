# Core / Policy — pure decision logic

Cross-cutting, side-effect-free decisions the orchestrator and platform layers consult. No I/O,
fully unit-tested. (These files moved here from the Core root during the 2026-06-26 reorg; they
keep `namespace JVoice.Core`.)

## Key files
- `CoordinatorDecisions.cs` — pure helpers that decide the next coordinator action (what
  `VoiceCoordinator` should do for a given state) without touching the OS.
- `HotkeyGate.cs` — decides whether a hotkey press is honored or swallowed (the game-suppression
  gate). Pairs with `GameDetectionPolicy`.
- `GameDetectionPolicy.cs` — turns the raw game signals (gathered by
  `JVoice.App/Platform/System/GameDetector`) into an Off/Balanced/Aggressive verdict.
  **Anti-cheat-safe by construction: read-only OS signals only.** Balanced (default) excludes
  bare fullscreen so fullscreen video doesn't false-positive (root `CLAUDE.md` §7 #27).
- `StatsMath.cs` — pure arithmetic for usage stats (words/time aggregations).
- `SilenceHallucinationGate.cs` — the §7 #38 witness-decode policy: near-silence (rawRms < 0.004,
  a verify TRIGGER only — never a rejector, §7 #21) means the prompted transcript must be vouched
  for by an unprompted decode; an empty reduced witness ⇒ no-speech. Calibrated on David's real
  clips (whisper confidence is INVERTED — don't threshold it).
- `PhraseLoopGuard.cs` — the §7 #42 repetition-loop policy: detects/collapses runs of ≥4
  consecutive identical phrases (≤32 tokens since §7 #45 — a real 21-token loop escaped the
  original 12-token window; case/punctuation-insensitive) — whisper's
  prompt-induced decode loop ("You're not a man of Caesar." ×16), which sits MID-transcript with
  full timestamp coverage, so RepetitionGuard and TailCoverageGuard are blind to it. The engine
  answers a detected loop with an unprompted witness re-decode (`Resolve` prefers the witness —
  the loop overwrote real speech); genuine "Crucify him, crucify him" (2×) / "Holy, holy, holy"
  (3×) stay below the threshold, test-locked.
- `SparseTranscriptGuard.cs` — the §7 #43 mid-transcript-skip policy: a PROMPTED whole-file decode
  that emits conspicuously little text for the audio (< 4 chars/s on ≥ 10 s audio — real dictation
  measured 8.9–17.8 chars/s across the 2026-07-20 30-clip sweep) triggers an unprompted witness
  re-decode; the witness is adopted only when it carries ≥ 2× the characters (the real skip's
  witness was 9.3×, legit drift ≤ 1.1×). Catches whisper silently swallowing the MIDDLE of a
  dictation (head + tail kept, last segment near the audio end), which the loop/repetition/tail/
  silence guards are all structurally blind to. Density is only the TRIGGER — the replace decision
  is the model's own unprompted decode, so §7 #21 (no arithmetic rejection) holds.
- `TailCoverageGuard.cs` — the §7 #39 tail-recovery policy: when a decode's last segment ends
  ≥1.5 s before the end of the audio (early-EOT truncation fingerprint; the trigger is timestamp
  coverage, never RMS), the uncovered tail is re-decoded and merged with normalized-containment
  dedupe. A trailing pause decodes empty and merges to nothing.
- `AppTimings.cs` — shared timing constants.

## Invariant
The split is **policy-here / probing-there**: this folder must stay pure. The privileged OS reads
live in `JVoice.App/Platform/System` (`GameDetector`, `ForegroundWindowTracker`). Keep it that way
so the decision logic stays testable.

## Verify
`dotnet test windows/JVoice.Tests` — CoordinatorDecisionsTests, HotkeyGateTests,
GameDetectionPolicyTests, StatsMathTests.
