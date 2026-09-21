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
  chunk, falls back to a whole-file decode — it never silently drops speech. Polled every
  `AppTimings.streamingPoll` (100 ms since 2026-09-12; was 1 s) so a finished chunk's decode starts
  sooner and less backlog remains at the stop press. A silent-classified FINAL tail is dropped
  without a decode and the streamed pieces are kept (deliberately faster than the Windows port,
  which decodes that tail to confirm it is empty). **Latency layer (2026-09-12):** a chunk decode
  in flight at the stop press is an unstructured task that `finish()` awaits — never cancel it
  (WhisperKit throws on cancellation → session failed → whole-file re-decode, 6.6 s live); and the
  **speculative tail decode**: pending audio ending in ≥ `AppTimings.speculativeTailPause` of
  silence (`ChunkPlanner.trailingSilenceSamples`) is decoded immediately, so `finish()` returns it
  with no post-stop decode when the user then presses stop (`speculative tail HIT`), drops it if
  speech resumes, and a chunk cut inside the same pause reuses it. Verified by
  `scripts/verify-streaming.sh` scenarios 9–12 and `--bench --stream --realtime`.
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
  corrections, `stripDecoderArtifacts` (drops `[BLANK_AUDIO]`-style hallucination sentinels) and
  `removeWhisperHallucinations` (whole-text stock phrases like "Thank you.", all-symbol output, and
  the bare lowercase `you` that Whisper emits for < 1 s of hum). Both engine decode paths run these
  two on the RAW decode (`WhisperKitTranscriptionEngine.cleanRawDecode`), so near-silent audio reads
  as an empty decode — the trigger for `RegurgitationRecovery` / the whole-file fallback.
- `PhoneticMatcher.swift` — fuzzy sound-alike correction (e.g. "jay voice" → "JVoice").
- `Math/` — **spoken mathematics → real notation** (ported 1:1 from the Windows port's
  `windows/JVoice.Core/Math/`, 2026-09-21). "x squared plus y squared equals z squared" becomes
  "x² + y² = z²"; "the limit as x approaches 0 of sine of x over x equals 1" becomes
  "the lim_(x→0) sin(x) ÷ x = 1". Applied LAST in `VoiceCoordinator.finishTranscription`, after
  `TextProcessor.process`, and gated on the opt-out `SettingsState.mathNotation` (default ON).
  - `MathSymbols.swift` — the ~700-form vocabulary ("how it is said" → "what to print"), data only.
  - `MathSpeech.swift` — the grammar, the activation rules and the emitter. **The no-bleed
    guarantee is STRUCTURAL, not a classifier**: a word only becomes a symbol inside a RUN
    (consecutive maths-lexing words, ended by any ordinary word or punctuation), and a run only
    converts when an ACTIVATING construct found its OPERANDS (an infix relation/operator with an
    operand on both sides, a prefix with one after it, or a structural construct — script, power,
    root, fraction, bounds, derivative, limit, absolute value, choose). π, α, %, °, `sin`,
    brackets, number words and signs are WEAK: they render inside an already-activated run and
    stay plain words otherwise. When nothing activates, `convert` returns the input unchanged.
  - `SpokenNumbers.swift` — "twenty five" → "25", "three point one four" → "3.14", "three
    quarters" → "¾". Greedy on purpose (it only ever runs inside a recognised run) but it never
    over-consumes: "and", "point" and "a" are each settled by lookahead.
  - `MathScript.swift` — Unicode super/subscripts and stacked fractions, all-or-nothing with a
    `^`/`_` fallback (there is no subscript "b", so "a subscript b" prints `a_b`).
  - `MathSymbol.swift` — `MathKind` + the one record type; `activates` is the whole rule.
  - `MathProbe.swift` — the hidden `--math-probe` command-line mode; see the verification section.
- `BenchRunner.swift` — the hidden `--bench` command-line harness that measures transcription
  speed and verifies vocabulary biasing / streaming on this machine. Not part of the running app's
  user flow; it is a dev tool, co-located here because it exercises this pipeline.

## Invariants — do not break these
1. A non-silent chunk is never dropped; on any doubt, fall back to a whole-file decode.
2. Keep the vocabulary prompt ON; rely on RepetitionGuard + RegurgitationRecovery for the
   regurgitation failure mode rather than disabling the prompt.
3. Long clips keep timestamps (the WhisperKit 1.0.0 truncation trap above).
4. Mathematics must never bleed into ordinary talking. Before changing anything under `Math/`,
   re-run the no-bleed half of the suite (`./scripts/run-logic-tests.sh`) AND sweep a real corpus
   through `--math-probe`; a new vocabulary entry of an ACTIVATING kind (Relation / Operator /
   Prefix) is the only thing that can turn a sentence into an equation, so everyday English words
   may only ever be added as weak kinds.

## How to verify changes here
- `./scripts/verify-streaming.sh` — compiles and EXECUTES the streaming data-loss + recovery
  guarantees using mock decoders (no WhisperKit or microphone needed).
- `./scripts/run-logic-tests.sh` — runs the pure-logic checks (TextProcessor, PhoneticMatcher,
  RepetitionGuard including a loop fuzz, VocabularyPrompt, WavTail, ChunkPlanner).
- `.build/release/JVoice --bench <wav> [--model tiny|base|small|large] [--vocab "A,B"] [--stream [--realtime]]`
  — end-to-end speed + accuracy on a real clip. `--stream` replays at 10× (stress: decodes fall
  behind, exercises the in-flight-at-stop path); `--stream --realtime` replays at 1× with the app's
  poll cadence + speculation and prints the session's events (make the clip end in a pause with
  `say … "[[slnc 1500]]"` to see a `speculative tail HIT`).
- `.build/release/JVoice --math-probe "<text>"` (or piped stdin, one dictation per line) prints
  `CHANGED|before|after` for a line the mathematics engine rewrote and `same|text` for one it left
  alone. This is how the no-bleed guarantee is MEASURED: sweep a real corpus (e.g. the recent
  transcripts in `~/Library/Preferences/com.jvoice.app.plist`, key `jvoice.app.transcriptHistory`)
  and read every CHANGED line.
- `python3 scripts/verify-transcription.py --model tiny|base|small|large [--quick]` — full
  word-retention / spurious-vocab harness (requires the model downloaded).
