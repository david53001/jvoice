# Changes — 2026-07-20 dictation-cutoff fixes

Two prompt-induced whisper failures, both David-reported the same evening, both fixed the
same way (unprompted witness re-decode) and both live in the installed app (`1.0.0+abf6bb8`,
branch `fix/sparse-decode-guard`, commits `aa22187` + `abf6bb8`). Not pushed.

## 1. Repetition-loop spam — PhraseLoopGuard (§7 #42, commit `aa22187`)

- **Bug:** a 97 s dictation pasted "You're not a man of Caesar." ×16, overwriting real speech.
- **Fix:** `JVoice.Core/Policy/PhraseLoopGuard.cs` — detects runs of ≥4 consecutive identical
  phrases; the engine re-decodes without the vocabulary prompt and prefers that witness.
  Genuine repeats ("Holy, holy, holy") stay. A looped streaming chunk fails into the lossless
  whole-file fallback.

## 2. Mid-transcript skip — SparseTranscriptGuard (§7 #43, commit `abf6bb8`)

- **Bug:** a 32 s dictation pasted only its head + tail ("Now next, Jesus appears to his
  disciples. not forgiven. Amen.", 61 chars ≈ 1.9 chars/s) — the prompted decode silently
  swallowed the middle ~25 s; every existing guard was blind (no loop, no uncovered tail,
  not near-silent).
- **Fix:** `JVoice.Core/Policy/SparseTranscriptGuard.cs` — a decode emitting < 4 chars/s on
  ≥ 10 s of audio triggers an unprompted witness re-decode; the witness is adopted only when
  it carries ≥ 2× the text. Calibrated on a 30-clip sweep of real captures (legit ≥10 s
  dictation never dips below 8.9 chars/s; witness drift ≤ 1.1×). A sparse streaming chunk
  fails into the whole-file fallback.

## Verification

- `dotnet test` **865/865** (46 new tests across both guards).
- On-device `--bench`: both real failing clips now decode to the full text (whole-file and
  streaming); 6-clip no-harm sweep **byte-identical** to the pre-fix build.

## Deployment

- `%LOCALAPPDATA%\Programs\JVoice` refreshed to `1.0.0+abf6bb8` (GPU publish, robocopy;
  license + uninstaller preserved); app relaunched elevated via the
  "JVoice Elevated Autostart" task. Version stays 1.0.0 (baseline unchanged).

Full detail: `docs/HANDOFF-WINDOWS.md` §7 #42–#43.
