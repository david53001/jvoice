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
  chunk, is re-covered — it never silently drops speech. **Local recovery (2026-09-23):** the
  pieces decoded before the failed chunk are kept and only the audio from the start of the LAST
  kept piece (≥ 15 s of preceding audio, so the failed audio is heard in context) to the end is
  decoded again through the engine's `recover` closure (`transcribeRegionSamples` — the whole-file
  decode options on a sample array), replacing that piece; only when there is no kept piece, the
  region would exceed `maxRecoveryFraction` (70 %) of the recording (it would cost what the
  whole-file decode costs), or that recovery is also empty, does `finish()` return nil for the
  caller's whole-file decode. Scenarios 13–16 and 19–20 of `scripts/verify-streaming.sh` lock it.
  Measured: a 52 s dictation whose final chunk decoded empty went from ~9.8 s after stop (tail
  retries + whole-file re-decode) to 4.5 s from this alone. A speculative tail that decoded EMPTY
  goes straight to local recovery (re-decoding the same audio alone would say the same). Polled every
  `AppTimings.streamingPoll` (100 ms since 2026-09-12; was 1 s) so a finished chunk's decode starts
  sooner and less backlog remains at the stop press. A silent-classified FINAL tail is dropped
  without a decode and the streamed pieces are kept (deliberately faster than the Windows port,
  which decodes that tail to confirm it is empty). **Latency layer (2026-09-12):** a chunk decode
  in flight at the stop press is an unstructured task that `finish()` awaits — never cancel it
  (WhisperKit throws on cancellation → session failed → whole-file re-decode, 6.6 s live); and the
  **speculative tail decode**: pending audio ending in ≥ `AppTimings.speculativeTailPause` of
  silence (`ChunkPlanner.trailingSilenceSamples`) is decoded immediately, so `finish()` returns it
  with no post-stop decode when the user then presses stop (`speculative tail HIT`), drops it if
  speech resumes, and a chunk cut inside the same pause reuses it. **Validity is anchored at the
  speculation's DECODED END (2026-09-23):** it is dropped only for speech past the audio it
  decoded — the measured speech end jitters on breaths near the silence floor
  (`ChunkPlanner.Config.silenceRMSFloor`) because `trailingSilenceSamples` probes in 0.1 s steps
  anchored at the growing file's end (live: jumps of up to ~1.8 s with nothing new said, which
  restarted the decode up to 5× in a row) — and a chunk cut reuses it only if everything between
  its decoded end and the cut is silent (`ChunkPlanner.plan` cuts at a window quiet only RELATIVE
  to the chunk's peak, so reusing across soft audio there skipped that audio). Roughly 9 in 10 speculations are dropped anyway
  (~11 s of Neural Engine time per dictation-minute, measured 2026-09-23), but a cancelled decode
  stops at the next decoder token (only an encoder pass already running, ≤ ~0.4 s, finishes), and
  decodes never overlap otherwise, so the waste costs almost no latency. Verified by
  `scripts/verify-streaming.sh` scenarios 9–12 and 17–18 and `--bench --stream --realtime`.
- `ChunkPlanner.swift` — pure (no I/O) policy deciding where to cut the growing recording into
  chunks at silence boundaries.
- `WavTail.swift` — safely parses a WAV file that is still being written (the "tail" that has
  grown since the last read).
- `VocabularyPrompt.swift` — builds the decoder-conditioning `promptTokens` from the user's
  custom words. This is the main custom-word accuracy lever (e.g. it gets "Li-Fraumeni" and
  "VS Code" right). Kept ON by default.
- `RepetitionGuard.swift` — detects "prompt regurgitation" (the decoder reciting the vocab list
  back on pauses/silence) and flags it via a `scrub` result. **Spoken maths is not a loop
  (2026-09-23):** numbers, single letters, number words and spoken operators (`isMathToken`) repeat
  legitimately ("26 x 26 x 26 x 10 x 10 x 10"), so on repetition alone they are loop tokens only at
  ≥ 8 occurrences within the last 24 tokens (a stuck decoder repeats until its token budget runs
  out); the net under that exemption: a transcript ENDING in one exact phrase (≤ 12 tokens)
  repeated ≥ 6 times is a loop whatever its tokens (`trailingPhraseLoop` — catches long-cycle loops
  like "page 1 of 10, page 1 of 10, …" that the count cannot see). Before, such maths was DELETED from the paste and cost a second, unprompted decode — the
  "JVoice is slow on numbers" report; when a whole chunk was maths it came back empty and forced the
  whole-file fallback.
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
1. A non-silent chunk is never dropped; on any doubt, re-decode it in context — locally from the
   last kept piece (`StreamingTranscriptionSession.recoverLocally`), else a whole-file decode.
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
