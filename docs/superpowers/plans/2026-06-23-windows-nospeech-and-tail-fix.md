# Windows no-speech & sentence-tail fix (2026-06-23)

Zero-context design note for the two David-reported Windows bugs. Read this before
touching the code; it records the root cause, the on-device evidence, the chosen fix,
the alternatives rejected, and how to verify.

## The two bugs (David, Windows port)

1. **Short/quiet sentences are rejected as "No speech detected."** Real utterances —
   including a 3.3-second sentence — never reach the decoder.
2. **The last part of sentences is sometimes cut off.** Earlier words paste; the
   trailing clause is dropped.

Multiple prior Claude sessions tried and failed (commits `66a9e79`, `c3c849a` —
the high-pass and spectral-ratio no-speech gates).

## Root cause (ONE cause, both bugs)

David's microphone captures speech ~10–20× quieter than every threshold in the code
assumes. From his real `%APPDATA%\JVoice\diagnostic.log` (2026-06-23):

| recSecs | hpRMS  | rawRMS | ratio | outcome                         |
|--------:|-------:|-------:|------:|---------------------------------|
| 3.32    | 0.0004 | 0.0041 | 0.10  | **rejected** (real sentence!)   |
| 1.78    | 0.0004 | 0.0049 | 0.08  | **rejected**                    |
| 1.32    | 0.0001 | 0.0004 | 0.12  | rejected                        |
| 19.46   | —      | —      | —     | streamed OK                     |
| 31.13   | —      | —      | —     | whole-file OK (verbatim, exact) |

`HighPassSilence`'s own doc claims "normal speech 0.02–0.08" and "real quiet dictation
ratio 0.43–0.53". David's real speech is hpRMS≈0.0004 / ratio≈0.08–0.12 — far below.
**The previous fixes were tuned on synthesized SAPI clips that don't reproduce his
real low-level, low-SNR mic.** His quiet speech and his room hum overlap in both level
and spectral ratio, so NO absolute level/ratio threshold can separate them.

- **Bug #1** = the whole-file `HighPassSilence.IsSilent` pre-gate rejecting his speech
  before whisper sees it (`WhisperNetTranscriptionEngine.TranscribeAsync`).
- **Bug #2** = the streaming `ChunkPlanner.IsSilent` (absolute `SilenceRmsFloor=0.005`)
  dropping his quiet trailing clause in `StreamingTranscriptionSession.Finish()`
  (the `SilentRegion_IsDropped` path), so earlier chunks paste but the tail is lost.

## On-device evidence (`windows/tools/nospeech-probe`)

Ran silence / 60 Hz hum / low-freq rumble / white noise / SAPI speech scaled to peak
0.10→0.008 through Whisper.net 1.9.1 (tiny), with and without a vocab prompt:

- **whisper decodes quiet speech correctly at EVERY level** — even peak 0.008
  (rawRMS 0.0011, below David's real level). The decoder was never the problem.
- **whisper returns a NON-SPEECH ANNOTATION on no-speech, never a plausible sentence:**
  silence/hum/rumble → `[BLANK_AUDIO]`; with a prompt → `[Music]` / `[Sigh]`; white
  noise → `(birds chirping)`. `TextProcessor.StripDecoderArtifacts` only strips
  ALL-CAPS bracket tokens, so `[Music]`, `[Sigh]`, `(birds chirping)` survive today.
- `WithNoSpeechThreshold` (Whisper.net `[EXPERIMENTAL]`) made no difference; not used.

Conclusion: **the model is the reliable no-speech authority at any level.** The RMS
pre-gate is pure harm. The original "silence pastes a hallucination" fix (#15) was a
misdiagnosis — `StripDecoderArtifacts` already neutralizes whisper's silence output;
the gate was never needed for silence/hum.

## The fix

### Bug #1 — whole-file (`WhisperNetTranscriptionEngine.TranscribeAsync`)
- **Remove the `HighPassSilence.IsSilent` rejection.** Keep `PeakHighPassRms` /
  `PeakWindowRms` ONLY for the diagnostic-log metrics (so David's log still shows the
  spectrum). `HighPassSilence` becomes metrics-only; update its doc.
- After `RegurgitationRecovery` (which already runs `StripDecoderArtifacts`), apply a
  new **`NonSpeechAnnotation.IsAnnotationOnly(text)`** check: if the WHOLE transcript is
  nothing but `[...]`/`(...)` annotation groups (any case) → treat as empty → the
  existing `EmptyTranscript` throw → "No speech detected." A real sentence that merely
  *contains* a parenthetical is never touched (text outside the groups ⇒ kept).
- Net: his quiet/short speech now decodes and pastes; true silence/hum → annotation →
  empty → "No speech detected." — level-independent, model-driven.

### Bug #2 — streaming (`StreamingTranscriptionSession.Finish()`)
- The final tail must not be dropped on the strength of an absolute RMS floor. Change
  the silent-tail branch: a non-empty tail judged `IsSilent` → **return null (lossless
  whole-file fallback)** instead of dropping it and returning the earlier pieces.
  - Loud/normal tail → decoded as before (streaming benefit preserved; normal users
    unaffected — only a *quiet* tail triggers the fallback).
  - Genuine trailing silence → whole-file fallback re-decodes everything; whisper emits
    annotation→empty for the silence and the full correct transcript for the speech.
  - **Invariant preserved:** speech is never silently dropped (the whole-file path is
    lossless). The mid-recording `PollOnce` silent-drop is unchanged (a 15–25 s chunk is
    only ever flagged silent if the user said nothing loud for 15–25 s — impossible
    during real dictation).
- `NonSpeechAnnotation.IsAnnotationOnly` is also applied to chunk decodes, so an
  annotation-only chunk → "" → existing empty-chunk → fallback (lossless).

### Bug #2 hardening — recorder tail (`NAudioRecorder.Stop()`)
- `WasapiCapture.StopRecording()` returns before the capture thread delivers its final
  buffer; today `Stop()` pumps+finalizes immediately and can lose the last ~one buffer
  period. Wait (bounded) for `RecordingStopped` so all delivered `DataAvailable` are
  pumped before finalizing — no lost final fraction of audio. Bounded timeout ⇒ no hang.

## Rejected alternatives
- **Re-tune the RMS/ratio thresholds** (what every prior session did): his speech and
  hum overlap; no threshold separates them. Fragile by construction.
- **Gain-normalize the capture:** linear gain scales speech and hum equally — it cannot
  separate them at his SNR, and whisper already decodes his level fine, so it adds
  clipping risk for zero benefit on the no-speech decision.
- **`WithNoSpeechThreshold`:** no observable effect on-device; `[EXPERIMENTAL]`.
- **Blocklist "you":** "you" is real dictation; can't be blocklisted. The annotation
  check is the right discriminator (whisper never emits a bare sentence on silence).

## Verify
- `dotnet test windows/JVoice.Tests` — all green (new `NonSpeechAnnotationTests`;
  updated `StreamingSessionTests`).
- `dotnet run --project windows/tools/nospeech-probe` — quiet speech → words; silence/
  hum/noise → `<empty>` after the annotation check.
- David dogfood: short sentences transcribe; sentence tails are not cut.
