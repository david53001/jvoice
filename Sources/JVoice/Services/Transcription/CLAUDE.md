# Services/Transcription — JVoice's speech-to-text pipeline

This folder turns a recorded WAV file into clean, styled text. JVoice transcribes on-device
using WhisperKit (an open-source Swift wrapper around OpenAI's Whisper speech-to-text models,
pinned to version 1.0.0). To work in this area, read the files below.

## Files
- `TranscriptionManager.swift` — owns the WhisperKit engine and is the whole-file transcription
  entry point. Also hosts `WhisperModelLocator` (finds downloaded model bundles on disk).
  **Trap:** it duration-gates the `withoutTimestamps` decode option — long clips MUST keep
  timestamps, or WhisperKit 1.0.0 truncates the output.
- `StreamingTranscriptionSession.swift` — decodes completed audio chunks *while* recording is
  still in progress. Data-loss guarantee: any decode failure, or an empty result on a non-silent
  chunk, falls back to a whole-file decode — it never silently drops speech.
- `ChunkPlanner.swift` — pure (no I/O) policy deciding where to cut the growing recording into
  chunks at silence boundaries.
- `WavTail.swift` — safely parses a WAV file that is still being written (the "tail" that has
  grown since the last read).
- `VocabularyPrompt.swift` — builds the decoder-conditioning `promptTokens` from the user's
  custom words. This is the main custom-word accuracy lever (e.g. it gets "Li-Fraumeni" and
  "VS Code" right). Kept ON by default.
- `RepetitionGuard.swift` — detects "prompt regurgitation" (the decoder reciting the vocab list
  back on pauses/silence) and flags it via a `scrub` result.
- `RegurgitationRecovery.swift` — re-decodes the same audio *without* the prompt, but **only when**
  a decode regurgitated or returned empty. This keeps prompt accuracy in the common case while
  making the failure mode (loops, scattered insertions, dropped speech) unreachable.
- `TextProcessor.swift` — post-processing: tone styling, filler-word removal, exact custom-word
  corrections, and `stripDecoderArtifacts` (drops `[BLANK_AUDIO]`-style hallucination sentinels).
- `PhoneticMatcher.swift` — fuzzy sound-alike correction (e.g. "jay voice" → "JVoice").
- `BenchRunner.swift` — the hidden `--bench` command-line harness that measures transcription
  speed and verifies vocabulary biasing / streaming on this machine. Not part of the running app's
  user flow; it is a dev tool, co-located here because it exercises this pipeline.

## Invariants — do not break these
1. A non-silent chunk is never dropped; on any doubt, fall back to a whole-file decode.
2. Keep the vocabulary prompt ON; rely on RepetitionGuard + RegurgitationRecovery for the
   regurgitation failure mode rather than disabling the prompt.
3. Long clips keep timestamps (the WhisperKit 1.0.0 truncation trap above).

## How to verify changes here
- `./scripts/verify-streaming.sh` — compiles and EXECUTES the streaming data-loss + recovery
  guarantees using mock decoders (no WhisperKit or microphone needed).
- `./scripts/run-logic-tests.sh` — runs the pure-logic checks (TextProcessor, PhoneticMatcher,
  RepetitionGuard including a loop fuzz, VocabularyPrompt, WavTail, ChunkPlanner).
- `.build/release/JVoice --bench <wav> [--model tiny|base|small|large] [--vocab "A,B"] [--stream]`
  — end-to-end speed + accuracy on a real clip.
- `python3 scripts/verify-transcription.py --model tiny|base|small|large [--quick]` — full
  word-retention / spurious-vocab harness (requires the model downloaded).
