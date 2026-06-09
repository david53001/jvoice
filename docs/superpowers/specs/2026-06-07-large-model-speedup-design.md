# Large-Model Speedup — Design Spec

**Date:** 2026-06-07
**Status:** Approved direction by David (interactive); detailed execution delegated to Claude to run autonomously. Interactive review gates waived for this session — David: "do this all autonomously … do this very carefully."
**Goal:** Cut hotkey-release → text-pasted latency on the Large model while keeping accuracy. Two phases:

- **Phase 1 — Model swap:** point the "Large" option at OpenAI's real large-v3-turbo (`openai_whisper-large-v3-v20240930`), bench-verified.
- **Phase 2 — Streaming-while-recording:** transcribe completed speech chunks in the background *during* recording so only the tail remains on hotkey release.

**Hard constraints (unchanged):** no commits/pushes/publishing this session (working tree only); $0 budget; `swift build` must pass; local verification = `./scripts/run-logic-tests.sh` + `--bench` CLI; never touch `../MacOSUtils`.

---

## Measured baseline (docs/HANDOFF.md, large-v3_turbo)

| Clip | Today |
|---|---|
| Short (≤25 s, single window, `withoutTimestamps` fast path) | ~1.2 s |
| Long (53 s, multi-window timestamped path) | ~41 s |

David's complaint: **every dictation feels slow.** Phase 1 attacks the per-token decode cost (helps all clips); Phase 2 attacks the long-clip wait by overlapping transcription with speaking.

---

## Phase 1 — Swap "Large" to `large-v3-v20240930`

### Why

JVoice's current `openai_whisper-large-v3_turbo` is WhisperKit's *compression pipeline* applied to original large-v3 — still a **32-layer decoder**. Decoding is autoregressive (full decoder pass per token) and dominates latency. `openai_whisper-large-v3-v20240930` is **OpenAI's large-v3-turbo**: identical encoder, decoder pruned 32 → 4 layers and fine-tuned. English WER is essentially on par with large-v3; decode is ~4–6× faster. The pinned WhisperKit 1.0.0 checkout lists it in its model registry and uses it as the *recommended default* for modern Macs (`.build/checkouts/WhisperKit/Sources/WhisperKit/Core/Models.swift:1582,1602`).

### Changes

1. `Sources/JVoice/Models/WhisperModelOption.swift`
   - `case largeTurbo = "large-v3-v20240930"` (rawValue change; case name stays `largeTurbo`).
   - `displayName` stays "Large v3 Turbo" (now literally true). `approximateRelativeSize` stays "Most capable".
   - `whisperKitFolderName` (`openai_whisper-<rawValue>`) then resolves to `openai_whisper-large-v3-v20240930` — matches the upstream HF folder, same pattern as today.
   - Custom `init(from:)`: map legacy rawValue `"large-v3_turbo"` → `.largeTurbo` before the `.tiny` fallback, so existing settings survive the rename.
2. `Sources/JVoice/Services/BenchRunner.swift`
   - `--model` parser: `"large"`, `"large-v3_turbo"`, `"largeTurbo"`, and new `"large-v3-v20240930"` all map to `.largeTurbo`.
3. Tests
   - New swift-testing cases: legacy-rawValue decode mapping; folder-name derivation for the new rawValue. Audit existing tests for `"large-v3_turbo"` literals and update.

**Explicitly unchanged:** DecodingOptions (language pin, `temperatureFallbackCount = 2`, `.vad` chunking, duration-gated `withoutTimestamps` with the 25 s threshold), vocabulary `promptTokens` biasing, prewarm flow, `.preparingModel` HUD state, model-folder completeness validation (`WhisperModelLocator` — required weight paths are identical across WhisperKit models).

### Verification protocol (the gate — bench output decides, not benchmark folklore)

Test clips generated with `say` + `afconvert` (16 kHz mono WAV), per repo convention:
- `short.wav` (~8 s), `long.wav` (~53 s, multi-window), `vocab.wav` (speech containing "jay voice").

For **each** of old model (`large-v3_turbo`) and new model (`large-v3-v20240930`), via `.build/release/JVoice --bench`:
1. Run each clip **twice**; record the second (warm) run's `transcribe:` time. First run of the new model pays its one-time ANE specialization in the CLI cache — excluded from timing.
2. `--vocab "JVoice"` on `vocab.wav`: processed output must contain "JVoice" on the new model (promptTokens biasing works on the 4-layer decoder).
3. `long.wav`: transcripts complete end-to-end on the new model — re-verifies the WhisperKit 1.0.0 multi-window truncation trap doesn't manifest differently. The duration gate stays regardless.

**Acceptance:** new model is materially faster on both clips AND transcripts are word-for-word comparable (minor punctuation/casing drift OK; missing/wrong words NOT OK; vocab biasing must work). **If accuracy fails, revert Phase 1** (keep old rawValue) and note findings in HANDOFF.

### Cost / expectations to document

- One-time ~1.5 GB model download on next app use + fresh ANE compile (~2¼ min, `.preparingModel` HUD covers it; CLI bench's ANE cache is per-bundle-ID and does NOT warm the app's — set expectation in HANDOFF).
- Old `openai_whisper-large-v3_turbo` folder stays on disk under `~/Documents/huggingface/...` (reclaimable manually; not auto-deleted — out of scope).
- Quantized variants (`_626MB`, `_turbo_632MB`) deliberately NOT used: accuracy-first mandate. Future option if David wants a smaller download.

---

## Phase 2 — Streaming-while-recording

### Design principle: zero-risk overlay on the proven pipeline

The capture pipeline is **untouched**: `AVAudioRecorder` keeps writing the same 16 kHz/16-bit/mono PCM `jvoice-*.wav` (Whisper's native format), `AudioInputRouter`'s Bluetooth/A2DP redirect, failure teardown, orphan sweep, and `isUsableRecording` all stay exactly as they are. Streaming is a **read-only observer** of the growing WAV file. Every failure mode degrades to today's behavior: transcribe the final file whole. Worst case = current latency, never worse, never lost audio.

This was chosen over WhisperKit's `AudioStreamTranscriber` (rejected: owns the microphone via its own AVAudioEngine — conflicts with `AudioInputRouter`; continuously *re*-transcribes the unconfirmed buffer — heavy compute and its confirm-heuristic final text can differ from a batch pass, violating the accuracy bar) and over replacing AVAudioRecorder with an AVAudioEngine tap (rejected: rewires live capture, the one thing that can't be end-to-end verified autonomously).

### Accuracy parity argument

Today's long-clip path is WhisperKit's `.vad` chunking: cut the audio at silence, decode each chunk as an independent window. Phase 2 performs the *same* silence-cut chunking, just earlier in time (while the user is still speaking), with the same model and per-window options. Cross-chunk decoder context is not carried — exactly like the current `.vad` path. The bench compares streamed vs. whole-file transcripts on the same audio to confirm parity empirically.

### Components (new files in `Sources/JVoice/Services/`)

**1. `WavTail.swift` — robust growing-WAV reader (pure parsing + thin I/O)**
- `WavTail.parseHeader(_ bytes: [UInt8]) -> WavInfo?` (pure): walks RIFF chunks to locate the `data` chunk payload offset and validate format (PCM, 16-bit, mono, 16 kHz). MUST tolerate Apple's `FLLR` filler chunk (CoreAudio pads headers up to ~4 KB) and a stale/zero `data` size field (AVAudioRecorder patches sizes only on stop) — the payload is treated as `[dataOffset, EOF)`.
- `WavTailReader` (struct, FileHandle-based): `samples(from sampleOffset: Int) -> [Int16]` reads only bytes beyond what's been consumed. Truncates a trailing odd byte (mid-sample write). Returns `[]` on any read problem.
- Failure semantics: unparseable header or vanished file → reader reports failure once → session aborts (fallback engages).

**2. `ChunkPlanner.swift` — pure chunking + silence policy (fully unit-testable)**
- Input: `[Int16]` unconsumed samples, sample rate, config. Output: `.wait` | `.cut(atSample: Int, isSilent: Bool)`.
- Config (internal constants, no user settings — YAGNI):
  - `minChunkSeconds = 15` — don't bother chunking short dictations (post-Phase-1 they're already fast).
  - `maxChunkSeconds = 25` — matches the proven single-window `withoutTimestamps` threshold; every chunk is provably single-window.
  - `silenceWindowSeconds = 0.3`, energy = windowed RMS; silence threshold relative to the running peak (mirrors WhisperKit's relative-energy approach).
- Policy: once ≥ `minChunkSeconds` of unconsumed audio exists, search `[minChunkSeconds, min(available, maxChunkSeconds)]` for a 0.3 s window whose energy is **below the silence threshold**; if found, cut at its midpoint. No sufficiently quiet window → keep waiting (`.wait`) until `maxChunkSeconds` of audio has accumulated, then force the cut at the quietest window found (same compromise WhisperKit's VAD makes). Never cut mid-speech before `maxChunkSeconds`. A chunk whose energy never exceeds the voice threshold is marked `isSilent` and **dropped without transcription** (Whisper hallucinates on silence; `TextProcessor.removeWhisperHallucinations` remains the second line of defense).
- Pure functions → added to `./scripts/run-logic-tests.sh` AND swift-testing suite (synthetic silence/sine-burst signals).

**3. `StreamingTranscriptionSession.swift` — orchestrator (actor)**
- Lifecycle: `start(url:)` → polling Task (every ~1 s): read new samples via `WavTailReader` → `ChunkPlanner` → on `.cut`: convert Int16→Float (/32768), `await engine.transcribeSamples(chunk)` **serially** (one in flight; the engine actor serializes anyway), append result to ordered transcript list, advance consumed offset.
- `finish() async -> String?`: stop polling; recorder has already stopped and finalized the file; read the remaining tail `[consumed, EOF)`, transcribe it (skip if silent/empty), join all piece transcripts with `" "`, return the raw combined transcript. Returns `nil` if the session ever failed or was cancelled → caller falls back.
- `cancel()`: stop polling, discard results (user abandoned the recording).
- Tolerates mid-recording reads seeing a lagging EOF (AVAudioRecorder buffers; chunks just cut later). Correctness is anchored at the *final* file, which is always complete and is read after `recorder.stop()` flushes.
- Any thrown error anywhere → session marks itself failed; never crashes the dictation flow.

**4. Engine addition — `Sources/JVoice/Services/TranscriptionManager.swift`**
- `TranscriptionEngine` protocol gains one member: `func makeStreamingSession() async -> StreamingTranscriptionSession?`, protocol-extension default `nil` — streaming is strictly opt-in per engine, and the factory shape keeps the engine reference inside the session's `@Sendable` transcriber closure without forcing `Sendable` onto the whole protocol (`FileBackedTranscriptionEngine` and test mocks compile untouched).
- `WhisperKitTranscriptionEngine.makeStreamingSession()` returns nil unless the model is already loaded (never trigger a load from the polling path); otherwise builds a session whose transcriber calls a private `transcribeChunkSamples(_:)`: same DecodingOptions as the file path except `withoutTimestamps = true` always (chunks are ≤ 25 s by construction) and no chunking strategy (already a single window). `promptTokens` vocabulary biasing applied per chunk (parity-or-better vs. today). Uses `kit.transcribe(audioArray:decodeOptions:)`. A parameterized `makeStreamingSession(pollNanoseconds:)` variant lets the bench harness poll faster than the app's 1 s cadence.
- `TranscriptionManager.makeStreamingSession()` forwards to the active engine.

**5. Coordinator wiring — `Sources/JVoice/VoiceCoordinator.swift` (minimal diff)**
- `startRecordingFlow`: after `recordingManager.startRecording()` succeeds, if `recordedURL` exists and a streaming session is available, `session.start(url:)`. HUD unchanged (`.recording`).
- `stopRecordingAndTranscribe`: unchanged through `recordingManager.stopRecording()`; passes the session (if any) into the transcription task.
- `finishTranscription`: after the existing `isUsableRecording` guard, if a session exists → `await session.finish()`. Non-nil → use that raw transcript (skip `transcriptionManager.transcribe(audioURL:)`); nil → **fall back to the existing full-file call unchanged**. Everything downstream (TextProcessor, hallucination strip, paste, stats, HUD `.done`) is untouched and shared by both paths. The `defer { removeItem(audioURL) }` already runs after `finish()` completes, so the file outlives all reads.
- Cancel/abandon path (`currentTranscriptionTask?.cancel()` + abandoned-audio cleanup): also `session.cancel()`.
- Recording-failure teardown deletes the WAV mid-recording → session's next poll sees the file gone → fails → no behavior change vs. today (coordinator already reports "No recording was captured").

### Latency model (post-Phase-1 numbers will recalibrate)

For a 53 s dictation: chunks at ~ 15–25 s boundaries are transcribed while the user speaks; on release only the final ≲ 25 s tail (typically ~5–15 s of audio) is decoded → perceived wait ≈ one short-clip transcription instead of the whole clip. Short dictations (< 15 s): streaming never engages; Phase 1 carries them.

### Verification

1. **Pure logic:** ChunkPlanner + WAV header parsing get standalone assertions in `./scripts/run-logic-tests.sh` (this machine's only real test runner) AND swift-testing cases for CI (synthetic WAV bytes incl. FLLR-padded and zero-size-data headers; synthetic energy profiles).
2. **E2E streaming without a microphone:** new `--bench --stream` mode in BenchRunner — simulates a live recording by appending the source WAV's PCM payload progressively (faster than real-time; the planner works on sample counts, not wall time) while a real `StreamingTranscriptionSession` consumes it, then calls `finish()` and prints timing + transcript. Run on `long.wav`:
   - **Acceptance:** streamed transcript ≈ whole-file transcript on the same model (word-for-word comparable; boundary punctuation drift OK), and post-stop (`finish`) time ≪ whole-file transcribe time.
3. **Regression:** non-streamed `--bench` on all clips unchanged; `swift build` clean; full test suite compiles; logic script passes.
4. **What cannot be verified autonomously (flagged for David):** live-mic behavior with real pauses, Bluetooth input redirect interplay, app-bundle ANE warm-up. Dogfood checklist goes in HANDOFF.

### Risks & mitigations

| Risk | Mitigation |
|---|---|
| Growing-WAV header oddities (FLLR, stale sizes) | Robust chunk-walking parser, unit-tested against synthetic variants; parse failure → silent fallback to today's path |
| Chunk cut mid-word (no silence found) | Quietest-window search first; forced cut only at 25 s (same compromise as WhisperKit VAD); bench transcript diff is the gate |
| Whisper hallucination on silent chunks | Silent chunks dropped pre-transcription + existing `removeWhisperHallucinations` |
| Session/coordinator race on rapid toggle | Session owned by the per-recording flow; `cancel()` on abandon; serial engine actor; rapid-toggle already debounced in coordinator |
| Decode-while-recording CPU contention | Chunks are sporadic (≥ 15 s apart), decode is ~1 s post-Phase-1; recorder is an independent OS-level pipeline |
| Anything else | Fallback: full-file transcription, byte-for-byte today's behavior |

### Out of scope (explicitly)

- Live partial-text HUD during recording (not requested; YAGNI).
- Carrying previous-chunk text as decoder context (today's `.vad` path doesn't either; future idea).
- Quantized model variants; user-facing streaming settings; deleting the old model folder; touching `../MacOSUtils`.

---

## Execution order & decision rules (autonomous session)

1. Phase 1 implement → build → logic tests → bench gate. **Fail → revert Phase 1, still attempt Phase 2** (it's independent), note in HANDOFF.
2. Phase 2 via TDD on pure parts, subagent implementation per plan → build → logic tests → `--bench --stream` gate. **Fail → leave Phase 2 code out of the working set (revert its files), keep Phase 1**, note findings.
3. Code review pass (code-review skill) on the full diff; fix findings.
4. Update `docs/HANDOFF.md` (results, expectations, dogfood checklist) and auto-memory. **No commits** — everything stays in the working tree for David's review, per the no-commits-without-ask rule (overrides the brainstorming skill's commit step).
