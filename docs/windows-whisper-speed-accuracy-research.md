# Whisper Speed & Accuracy — Full Research Findings (2026-07-24)

Eight parallel research agents (two per area: one codebase deep-dive, one external research) investigated every avenue for making JVoice-Windows' Whisper transcription **faster** and **more accurate**. All investigations were read-only — no code changed, no mic used, no GPU benchmarks run (recommendations name the experiments to run instead). Stack under study: Whisper.net 1.9.1 (whisper.cpp 1.8.5), GGML large-v3-turbo (**q5_0** — see Area 2), Vulkan on RTX 3060 Ti, CPU fallback i5-12400, flash attention ON (GPU), threads = physical cores.

> Executive synthesis is at the end (§9). Raw agent reports follow, verbatim, in §1–§8.

---

## Area 1 — Decode parameters

### §1. Codebase analysis (what the engine sets today)

# Decode-Parameter Surface Analysis (Whisper.net 1.9.1 / whisper.cpp 1.8.5)

Sources: the engine sources, reflection of the NuGet DLL `whisper.net\1.9.1\lib\netstandard2.0\Whisper.net.dll`, Whisper.net v1.9.1 `WhisperProcessor.cs` (GitHub), and whisper.cpp **v1.8.5** source (the bundled version) read line-by-line.

## 1. Current state — what the app sets

All decode configuration happens in `DecodeSamplesAsync` (`WhisperNetTranscriptionEngine.cs:369-427`) plus one factory-level option (`PerformLoadAsync`, 139-144).

| Option | Value | Notes |
|---|---|---|
| Flash attention (`WhisperFactoryOptions.UseFlashAttention`) | ON (GPU), OFF under `JVOICE_CPU` | Factory-level, §7 #31 |
| `.WithLanguage(...)` | fixed `"en"` or `"ro"` | Never auto-detect |
| `.WithTranslate()` | only when `_translate` | Toggle rebuilds engine |
| `.WithTemperature(0.0f)` | 0.0 | **Identical to native default — behavioral no-op** |
| `.WithTemperatureInc(0.2f)` | 0.2 | **Identical to native default — behavioral no-op** |
| `.WithThreads(n)` | physical cores (6), clamp [1,16] | §7 #31 |
| `.WithAudioContextSize(ctx)` | both tuning flags off in `EngineTuning.Default` | Rejected as non-monotonic §7 #31 |
| `.WithPrompt(promptText)` | vocab prompt when `usePrompt` && non-empty | Witness decodes pass `usePrompt: false` |

Everything else is left at whisper.cpp defaults — verified: Whisper.net applies each option **only when non-null**, so unset = `whisper_full_default_params(GREEDY)`.

## 2. The effective inherited decode config (whisper.cpp 1.8.5 defaults, `src/whisper.cpp:5915-6021`)

| Native param | Inherited value | Meaning for JVoice |
|---|---|---|
| strategy | GREEDY, `best_of = 5` | best_of only applies at temperature > 0 (fallback rungs run 5 parallel decoders) |
| `no_context` | **true** | see §4.1 — near-irrelevant here |
| `n_max_text_ctx` | effectively ≈ **224 tokens** | conditioning window per 30-s segment |
| `temperature` / `temperature_inc` | 0.0 / 0.2 → ladder **{0, 0.2, 0.4, 0.6, 0.8, 1.0}** (6 rungs) | NOT the "~2 fallbacks" the in-file comment claims |
| `entropy_thold` | 2.4 | loop detector over **last 32 tokens only** (§4.3) |
| `logprob_thold` | -1.0 | fallback + no-speech coupling (§4.4) |
| `no_speech_thold` | 0.6 | only skips a window when **also** avg_logprobs < -1.0 |
| `suppress_blank` | true | deliberate (documented in-file) |
| `suppress_nst` | false | non-speech tokens NOT suppressed — **load-bearing for the app** (§4.5) |
| `carry_initial_prompt` | false | prompt seeds rolling context once, then washes out |
| `max_len`/`split_on_word`/`max_tokens`/token timestamps/VAD | 0/false/0/off/off | unused |

## 3. Full Whisper.net 1.9.1 builder surface (reflected from the DLL)

`WithLanguage`, `WithLanguageDetection`, `WithTranslate`, `WithPrompt`, `WithCarryInitialPrompt(bool)`, `WithTemperature`, `WithTemperatureInc`, `WithEntropyThreshold`, `WithLogProbThreshold`, `WithNoSpeechThreshold`, `WithNoContext()`, `WithMaxLastTextTokens(int)`, `WithGreedySamplingStrategy` (→ `WithBestOf`), `WithBeamSearchSamplingStrategy` (→ `WithBeamSize`, `WithPatience`), `WithLengthPenalty`, `WithMaxInitialTs`, `WithAudioContextSize`, `WithThreads`, `WithMaxSegmentLength`, `WithMaxTokensPerSegment`, `SplitOnWord`, `WithSingleSegment`, `WithTokenTimestamps` (+ thresholds), `WithoutSuppressBlank`, `WithSuppressRegex`, `WithDuration`, `WithOffset`, `WithProbabilities`, `WithOpenVinoEncoder`.

Notable: there is **no `WithSuppressNonSpeechTokens`** (native `suppress_nst` unreachable — good), no `WithoutTimestamps`, and native `whisper_full_params.vad` is **not exposed** on this builder — VAD exists only as the standalone `WhisperVadFactory`/`WhisperVadProcessorBuilder` (Silero) returning speech segments you cut yourself. `SegmentData` exposes `NoSpeechProbability`, `Probability` (needs `WithProbabilities()`), and `Tokens` — currently unused by the engine (it reads only `.Text`/`.End`).

## 4. Key mechanics findings (from whisper.cpp 1.8.5 source — these change several assumptions)

### 4.1 `WithNoContext()` is a no-op here, and "condition_on_previous_text=False" does not exist in whisper.cpp
`no_context` **already defaults to true** and only clears `prompt_past` **at the start of a `whisper_full` call** — i.e., it stops carry-over between successive calls on a reused state. Since the engine builds a fresh processor per decode, it does nothing. Crucially, **within one call, cross-window conditioning is unconditional**: after every window, `prompt_past` is refilled with the previous conditioning prompt + newly decoded tokens (lines 7597-7608, no `no_context` check), and the next window conditions on the last ≤224 of them whenever the current temperature < 0.5. The OpenAI-Python anti-loop lever "don't condition on previous text" is therefore **not reachable via `WithNoContext`**. The only in-call off-switches are `WithMaxLastTextTokens(0)` — which also kills the vocab prompt (same budget path) — or temperature ≥ 0.5 (fallback rungs ≥3 auto-drop all conditioning, including the prompt: whisper's own built-in "unprompted witness").

### 4.2 The vocab prompt washes out after ~1 window
Without `carry_initial_prompt`, prompt tokens are pushed into the rolling context once. Window 2 conditions on `[prompt tokens + window-1 text]` truncated **from the front** to 224; by window 3-4 of a long dictation the prompt is gone. This explains why custom-word accuracy is strongest early in long dictations, and it bounds the blast radius of the prompt — relevant to why loops tend to appear mid-transcript. `WithCarryInitialPrompt(true)` re-injects the prompt into **every** window — a custom-word accuracy lever for long clips, but it multiplies exposure to the exact prompt-induced failure class of #42/#43/#45.

### 4.3 whisper's own loop detector has the same structural blindness PhraseLoopGuard #45 fixed
The entropy gate computes entropy over **only the last 32 tokens** and fires when `result_len > 32 && entropy < 2.4`. For a pure loop of a phrase with *d* distinct tokens, entropy ≈ ln(*d*): threshold 2.4 catches *d* ≤ ~11 — an 8-token "You're not a man of Caesar." loop (ln 8 ≈ 2.08) *should* trip it and escalate temperature, but the 21-token loneliness loop (ln 21 ≈ 3.04) **passes** whisper's own gate for exactly the reason it passed the old 12-token PhraseLoopGuard. Consequences: (a) raising `WithEntropyThreshold` to ~2.8-3.0 makes whisper heal *short-period* loops itself at a fallback rung (cheaper than the app's witness re-decode, and rung ≥ 0.5 drops the offending prompt), but (b) **no entropy value can catch long-period loops** — PhraseLoopGuard stays necessary regardless. Also: when the ladder is exhausted, the *last* rung's output is accepted even if failed — looped text can still emerge, so the guards remain the backstop.

### 4.4 The native no-speech skip is effectively disabled at defaults
A window is skipped as no-speech only when `no_speech_prob > 0.6` **AND** `avg_logprobs < logprob_thold`, and with `logprob_thold = -1.0` the second condition almost never holds (hallucinations here score confidently — "whisper confidence is INVERTED"). That is *why* silence produces annotations/hallucinated sentences that `NonSpeechAnnotation` + SilenceHallucinationGate must handle. Raising `WithLogProbThreshold` would arm the native skip — but it gates *fallback retries* too, changing two behaviors at once. Low-value, high-entanglement; the app's model-driven gates already cover this with real-clip calibration.

### 4.5 Do NOT suppress non-speech tokens or blanks — the architecture depends on them
The app's no-speech design (§7 #21/#38) **relies on** whisper emitting `[BLANK_AUDIO]`/`(birds chirping)`/`*…*` annotations so `NonSpeechAnnotation.Reduce` can map them to empty. Suppressing those token classes would force plausible words on silence — regressing #38 at the source. Same logic forbids `WithSuppressRegex` patterns targeting annotations.

### 4.6 Language: fixed is correct; auto-detect costs a full extra encoder pass
If language were auto, `whisper_full` runs a full encoder pass + decoder pass on the first window whose output is NOT reused — on short clips roughly doubling encode cost. Keep fixed. Trap: `WithLanguageDetection()` sets `detect_language=true`, and `whisper_full` then **returns after detection with no transcript** — never use it on the transcription path.

## 5. Option-by-option assessment (unset options only)

| Option | Verdict |
|---|---|
| `WithEntropyThreshold(2.8f)` | **High value.** Heals short-period loops at source (rung ≥0.5 drops the prompt automatically); reduces PhraseLoopGuard/witness firings. Long-period loops still need the guard. Best experiment candidate. A/B 2.6/2.8/3.0 |
| `WithMaxLastTextTokens(128)` | **Medium-high value.** Limits how far degenerate text propagates across windows; vocab prompt (≈50-70 tokens) still fits. At 64 the *front* of the prompt could truncate — use 128, not 64. Never 0 (kills the prompt) |
| Beam search beam 5 | **Worth one measured A/B.** Decode ~2-5× slower at t=0; on GPU turbo decode is a modest share — measure. Literature-consistent WER win, more robust to greedy's degenerate loops. Transcripts differ → full no-harm sweep required |
| `WithCarryInitialPrompt(true)` | **High reward, high risk** — custom-word accuracy on long dictations (prompt currently washes out) vs re-exposing every window to the loop/sparse class. Only behind the full failure-clip regression set |
| `WithTemperatureInc(0.4f)` | Low value unless logs show multi-rung decodes are common. The in-file "≈2 fallbacks like WhisperKit" comment is inaccurate — actual behavior is a 6-rung ladder, which is richer and includes the prompt-dropping rungs; keep |
| Greedy `WithBestOf(1)` | Not recommended (weakens the rescue path) |
| `WithLogProbThreshold`/`WithNoSpeechThreshold` | Leave — entangled with fallback triggering; #38/#21 gates already cover this |
| `WithNoContext()` | **No-op** (§4.1) — don't bother |
| Silero VAD pre-pass | Philosophically adjacent to the retired RMS gate — a learned VAD, but it *would* pre-reject audio. Streaming chunker already silence-cuts. Defer (see Areas 3-4 for the classification-only use) |
| `WithProbabilities()` + `SegmentData.NoSpeechProbability`/`Tokens` | **Diagnostics-only value:** log per-segment `NoSpeechProbability` for free guard-calibration data. Never threshold token `Probability` (inverted confidence) |
| `WithMaxSegmentLength`/`SplitOnWord`/`WithMaxTokensPerSegment`/token timestamps/`WithSingleSegment` | Skip (single_segment truncates — documented in-file) |
| `WithMaxInitialTs`/`WithLengthPenalty`/`WithDuration`/`WithOffset`/OpenVINO | No use case |

## 6. Does the #42 "don't touch decode params" caution still hold?
Partially. It was right while root-causing. But the guard architecture is now mature and **byte-level regression-testable against a library of real failure captures** — exactly the safety harness a decode-param experiment needs. `entropy_thold` and `max_last_text_tokens` *reduce* the frequency of the failure class the guards catch, bypass no guard, and are trivially revertable one-liners. The witness/fallback economics even improve speed: every avoided guard firing saves a full re-decode or whole-file streaming fallback.

## 7. Ranked experiments (with the required harness)

**Step 0: extend `EngineTuning` with nullable `EntropyThreshold`, `MaxLastTextTokens`, `BeamSize`, `CarryInitialPrompt` fields (defaults null = today's behavior), thread through `DecodeSamplesAsync`, add matching `--bench` flags** — keeps `EngineTuning.Default` shipping-identical until a lever is adopted.

Standard verification set (archived `JVOICE_KEEP_WAV` captures): loop clips `capture-20260720-225708-670.wav` (#42) and `capture-20260724-020028-378.wav` (#45, `--stream`), sparse clip `capture-20260720-231246-541.wav` (#43), the #44 clips, the 10 silent + 7 quiet #38 clips, plus a ~6-clip no-harm sweep expecting byte-identical output.

1. **`--entropy 2.8`** — expect #42 clip decodes clean *without* the guard firing; #45 clip likely still needs the guard (21 distinct tokens); no-harm sweep byte-identical. Adopt if zero no-harm diffs + fewer guard firings + time not worse than +10%.
2. **`--max-text-ctx 128`** — expect identical no-harm transcripts, reduced cross-window loop propagation; check `--vocab` still corrects custom words.
3. **`--beam 5`** — measure decode-time delta; adopt only if <~30% end-to-end cost *and* demonstrably fewer guard firings.
4. **Diagnostics (no behavior change): log per-segment `NoSpeechProbability` + segment count per temperature rung.** Zero risk; answers "how often do we hit fallback rungs today."
5. **`--carry-prompt`** — only after 1-2 land; judged on the failure-clip set (any loop/sparse reappearance = reject). Reward: custom words recognized past window 1 in minute-long dictations.
6. **Do not do:** `WithNoContext` (no-op), `WithoutSuppressBlank`, annotation suppression, `WithLanguageDetection`, `WithSingleSegment`, auto-detect language, re-defaulting `audio_ctx`.

## 8. Risks
- Any decode-param change invalidates the "byte-identical" baseline — every adoption needs the full clip sweep re-run and HANDOFF updated.
- Entropy 3.0+ risks false-failing legitimate repetitive dictation (prayers/poetry — "Holy, holy, holy"); that content is usually < 32 result tokens per window, so likely safe — but it's the one no-harm case to watch specifically.
- Beam search changes hallucination *texture*; SilenceHallucinationGate/SparseTranscriptGuard thresholds were calibrated on greedy output and may need recalibration.
- Whisper.net 1.9.0 notes mention carry-initial-prompt memory-reuse issues that were fixed — pin behavior with the bench before trusting it in long sessions.

**Bottom line:** the speed surface is already near-optimal for this stack (flash ON, threads set, fixed language, audio_ctx correctly rejected); the remaining value is in *robustness* knobs that make whisper fail less at the source — `WithEntropyThreshold` (best ratio), `WithMaxLastTextTokens(128)`, optionally beam search — with `WithCarryInitialPrompt` as the one genuine accuracy upside held behind the failure-clip regression wall.

### §2. External research (upstream best practice)

# Decode-Parameter Research: whisper.cpp / Whisper.net 1.9.1 on large-v3-turbo

**Scope:** upstream/community best practice for sampling, fallback thresholds, context/prompt handling, suppression flags, language, and post-2025 speed features — evaluated against this app's specific failure history (prompt-induced loops #42/#45, sparse prompted decodes #43, silence hallucinations #38, tail cutoffs #39/#41). No repo files touched; no benchmarks run.

## 1. Sampling strategy: greedy vs beam search

**The single highest-EV change is switching from greedy to beam search, beam_size = 5.**

- The app currently runs whisper.cpp *library* defaults via Whisper.net, and the library default strategy is **greedy** (`WHISPER_SAMPLING_GREEDY`, `best_of = 5` — best_of only matters at temperature > 0 during fallback, it is irrelevant at t=0). OpenAI's reference implementation and the whisper.cpp **CLI** both use **beam search with 5 beams** — whisper.cpp deliberately made beam search the CLI default in [v1.5.0](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.5.0) "to match the OG implementation of OpenAI Whisper," alongside a batched-KV-cache beam implementation. So every whisper.cpp quality number people quote is a beam-5 number; a library embedder using defaults silently gets the weaker greedy decoder.
- OpenAI's own model card documents that Whisper's seq2seq decoder "is prone to generating repetitive texts, which can be mitigated to some degree by beam search and temperature scheduling" ([whisper-large-v3-turbo model card](https://huggingface.co/openai/whisper-large-v3-turbo)). Beam search maintains multiple hypotheses, so a single token step into a loop attractor doesn't commit the whole transcript — this is exactly the failure class behind #42/#45 and, plausibly, the sparse prompted decodes of #43 (a greedy early-EOT has no competing hypothesis to rescue it).
- **Cost on this hardware is near zero.** ggerganov's v1.5.0 notes state that with the batched decoder "on modern NVIDIA hardware, the performance with 5 beams is the same as 1 beam" (Metal is slightly slower). On an RTX 3060 Ti with a 4-decoder-layer turbo model, decode is a small fraction of total time; expect low-single-digit-% latency cost, possibly unmeasurable. A CPU-fallback build will feel it more (roughly the 80–150 ms vs <50 ms per 5 s clip class of numbers quoted in [benchmark posts](https://www.spheron.network/blog/voice-ai-gpu-infrastructure/)) — consider beam on GPU flavor, greedy or beam-2 on the CPU flavor.
- **Whisper.net 1.9.1 exposes it**: `WithBeamSearchSamplingStrategy()` on `WhisperProcessorBuilder` (with a `BeamSearchSamplingStrategyBuilder` for beam size); greedy is `WithGreedySamplingStrategy()`. Note `patience` is still "TODO: not implemented" in whisper.h — beam 5, default patience is the only real option, which matches the reference anyway.
- Caveat for the guard stack: beam search changes decode outputs deterministically-but-differently; the byte-identical no-harm sweeps will not be byte-identical across this change. Re-run the real-capture corpus (`--bench` sweep of the #38/#42/#43/#45 clips) as the acceptance test instead.

## 2. Temperature fallback ladder + thresholds (what defaults you're actually running)

whisper.cpp library defaults (mirroring OpenAI's reference where noted):

| Param | whisper.cpp default | OpenAI reference | Notes |
|---|---|---|---|
| temperature | 0.0 | 0.0 | |
| temperature_inc | 0.2 | 0.2 (ladder 0→1.0) | fallback ladder is **already active** by default |
| entropy_thold | 2.4 | (analog: compression_ratio_threshold 2.4) | whisper.cpp computes entropy over the **last 32 tokens** — a repeated-token detector, not softmax entropy ([discussion #620](https://github.com/ggml-org/whisper.cpp/discussions/620)) |
| logprob_thold | -1.0 | -1.0 | avg logprob below ⇒ retry at higher temperature |
| no_speech_thold | 0.6 | 0.6 | implemented upstream since the v1.7.4 era |

- **Fallback mechanics:** if the segment's last-32-token entropy falls below `entropy_thold` (repetition) or avg logprob falls below `logprob_thold`, the decode is retried with temperature + 0.2, up to 1.0 ([discussion #1087](https://github.com/ggml-org/whisper.cpp/discussions/1087), [#620](https://github.com/ggml-org/whisper.cpp/discussions/620)). Known weakness: the final rung just accepts the t=1.0 output, which is where "less likely to loop but less likely to be correct" garbage comes from — the app's witness/fallback guards remain the right backstop for that.
- **Community-recommended tightening for loop suppression** (the long "[Improving hallucinations and repetitions](https://github.com/ggml-org/whisper.cpp/discussions/2286)" thread): **`entropy_thold 2.4 → 2.6`** (fires the repetition-retry earlier — directly relevant to the #42/#45 loop class, and cheap: it only costs extra decodes on clips that were already degenerate), and adjusting `logprob_thold` (that thread uses -1.25; note direction: *raising* toward -0.8 triggers more retries, *lowering* to -1.25 fewer — their intent was accepting less junk at the final rung, so treat logprob changes as experiment-only). Whisper.net exposes all of these: `WithEntropyThreshold`, `WithLogProbThreshold`, `WithTemperature`, `WithTemperatureInc`, `WithNoSpeechThreshold`.
- **no_speech:** long "not implemented" in whisper.cpp, this landed via [PR #2654](https://github.com/ggml-org/whisper.cpp/pull/2654) (segment-level `no_speech_prob` + `whisper_full_get_segment_no_speech_prob`, threshold default 0.6, v1.7.4 era) and [PR #2663](https://github.com/ggml-org/whisper.cpp/pull/2663) (CLI flag). The OpenAI rule is *no_speech_prob > 0.6 AND avg_logprob < -1.0 ⇒ treat segment as silence*. **App relevance:** reading per-segment `no_speech_prob` is a nearly free extra signal for the SilenceHallucinationGate — e.g., skip the witness decode when no_speech_prob is decisive, or use it as an additional trigger alongside `rawRms < 0.004`. Remember the app's own calibration found whisper *confidence* inverted on hallucinations; `no_speech_prob` is a different head (the `<|nospeech|>` token probability at the window start) and is precisely the signal the upstream community uses for this, so it's worth calibrating on the 17-clip corpus before trusting it.

## 3. no_context / condition_on_previous_text

- Terminology mapping: whisper.cpp `no_context = true` ⇔ OpenAI `condition_on_previous_text = False`. The whisper.cpp **library default is `no_context = true`** — but verify what Whisper.net actually passes (`WithNoContext()` exists on the builder; check `WhisperProcessorOptions` mapping in the app's engine, because this only matters for **multi-window (>30 s) whole-file decodes**, where prior-window text is fed as prompt to the next window).
- The evidence that context-carry is the loop amplifier is strong and current: [issue #3744](https://github.com/ggml-org/whisper.cpp/issues/3744) (Apr 2026) diagnoses long-form repetition as *"one chunk produces a bad short phrase … fed back as prompt history … later chunks repeat it again"* and proposes `retry_on_repeat` (retry the chunk **without** previous-text context — which is literally the app's PhraseLoopGuard witness-re-decode policy, independently reinvented upstream; good external validation). [Issue #2510](https://github.com/ggml-org/whisper.cpp/issues/2510) documents `no_context=false` streaming repeating old data after minutes. The production-consensus in the faster-whisper world is `condition_on_previous_text=False` + VAD as the two flags that "eliminate the majority of Whisper's notorious hallucination cases … with negligible quality cost" ([survey](https://www.spheron.network/blog/whisper-v4-asr-gpu-cloud-production-guide/), [openai/whisper #679](https://github.com/openai/whisper/discussions/679)).
- **For the streaming path** the app already decodes each chunk in a separate `whisper_full` call with no carried text — cross-chunk conditioning is structurally off; keep it that way (upstream confirms carrying text across chunks is the main loop vector). **For 30–120 s whole-file decodes**, explicitly setting `WithNoContext()` is the recommended, evidence-backed configuration for a dictation app: coherence benefit of context-carry is minimal for dictation, and it removes the within-call self-reinforcement channel. One interaction to check: with context off, windows after the first may lose the vocabulary prompt's influence entirely (see §4) — for this app that's arguably a *feature* (prompt-induced pathologies are all first-order harms here; exact-match correction packs recover the vocab downstream).

## 4. Initial-prompt best practice

- **Token budget: 224 tokens hard cap; only the *last* 224 are kept, silently** ([OpenAI prompting guide](https://cookbook.openai.com/examples/whisper_prompting_guide), [openai/whisper #1386](https://github.com/openai/whisper/discussions/1386), [#1824](https://github.com/openai/whisper/discussions/1824)). Later tokens exert more influence. Keep the vocab prompt well under the cap (the guide's own vocab examples are one short line); a long comma-separated list is exactly the "unnatural text the decoder wants to continue" shape that produces regurgitation — the failure the app's RepetitionGuard/RegurgitationRecovery already fight. Community advice consistent with the app's design: prompts of *natural prose containing* the custom words condition better and regurgitate less than bare comma lists.
- **Prefix vs prompt:** OpenAI's API distinguishes `prompt` (previous-context conditioning, `<|startofprev|>`) from `prefix` (forced beginning of the current segment). **whisper.cpp has no prefix parameter** — only `initial_prompt` / `prompt_tokens` (prev-context semantics). So nothing to change there; the app's `promptTokens` path is the only mechanism and has the right semantics for vocabulary biasing.
- **carry_initial_prompt:** upstream OpenAI added it ([openai/whisper PR #2343](https://github.com/openai/whisper/pull/2343)) to keep vocab influence after the first window; whisper.cpp grew the field later (after [issue #2564](https://github.com/ggml-org/whisper.cpp/issues/2564)), and Whisper.net exposes `WithCarryInitialPrompt(bool)`. **Recommend OFF for this app**: it re-injects the vocab list at every 30 s window of a long decode — multiplying the exact prompt-regurgitation/loop surface the guards exist for — and there is a reported correctness issue in the whisper.cpp implementation (PR #2684 "Wrong implementation of carry_initial_prompt").
- Structural upstream validation of the app's whole architecture: the community's standard remedies for prompt-induced failure are (a) decode without prompt history ([#2286](https://github.com/ggml-org/whisper.cpp/discussions/2286)), (b) retry-without-context on repetition ([#3744](https://github.com/ggml-org/whisper.cpp/issues/3744)) — i.e., the witness-re-decode pattern. No upstream parameter *prevents* prompt-induced loops outright; beam search + entropy retry reduce frequency, guards remain necessary.

## 5. Suppression flags, max_len, single_segment

- **`suppress_blank` (default true):** keep. It only suppresses blank outputs at segment start; disabling it is what `WithoutSuppressBlank()` is for, and there's no evidence it helps dictation.
- **`suppress_nst` / non-speech-token suppression (default FALSE):** **keep OFF — this one would actively break the app.** whisper.cpp deliberately disabled non-speech suppression by default ([commit for #473](https://git.sr.ht/~fitzsim/whisper.cpp/commit/a94897bcde6436698bcd09e88e581edd591a7985)); the server got an opt-in flag later ([PR #2649](https://github.com/ggml-org/whisper.cpp/pull/2649)). Two reasons to leave it: (1) the app's `NonSpeechAnnotation` no-speech detector *depends on* `[BLANK_AUDIO]`/`(birds chirping)`-style annotations being emitted; (2) [discussion #1258](https://github.com/ggml-org/whisper.cpp/discussions/1258) reports that suppressing these tokens on silence makes whisper output *arbitrary hallucinated speech instead* — the model needs an escape hatch on silence, and the annotations are it. Whisper.net doesn't even expose `suppress_nst` on the builder (only `WithSuppressRegex`), so there's no accidental foot-gun.
- **`max_len` / `max_tokens` (defaults 0 = unlimited):** leave at 0. Capping tokens per segment can truncate; capping length forces artificial segment splits that distort the timestamp geometry TailCoverageGuard/SparseTranscriptGuard read. No community evidence of accuracy benefit.
- **`single_segment`:** used by the upstream `stream` example for sub-30 s realtime chunks; it forces one segment and skips the sliding-window seek loop. Marginal speed win for ≤30 s clips, **but it collapses per-segment timestamps to one span — which blinds TailCoverageGuard's `lastEnd` early-EOT fingerprint and degrades the diagnostics the app's whole guard calibration is built on. Not recommended.**

## 6. Language forcing vs auto-detect

Auto-detect costs an extra encoder pass over the first 30 s window before decoding begins — a real, fixed per-clip latency hit (the [openHAB whisper.cpp integration docs](https://www.openhab.org/addons/voice/whisperstt/) call it out: "specifying a language can speed up recognition by avoiding auto-detection"; whisper.cpp calls it an expensive operation, [issue #826](https://github.com/ggml-org/whisper.cpp/issues/826)). On a 2–10 s dictation clip this is proportionally large. The app already forces `--lang en|ro`; the actionable check is that `detect_language` is false and `WithLanguage("en")` (not `WithLanguageDetection()`) is on every decode path including witness decodes — and note [issue #1831](https://github.com/ggml-org/whisper.cpp/issues/1831) (params ignored in some paths) as a reason to verify from the diagnostic log rather than assume.

## 7. Post-mid-2025 speed features & Whisper.net exposure

- **Native VAD (Silero) landed in whisper.cpp v1.7.5** (`--vad`, [issue #3003](https://github.com/ggml-org/whisper.cpp/issues/3003)): the VAD model finds speech segments, and only those are passed to whisper. Defaults: threshold 0.5, min_speech 250 ms, min_silence 100 ms, pad 30 ms, overlap 0.1 s ([vad-speech-segments example](https://fossies.org/linux/whisper.cpp/examples/vad-speech-segments/speech.cpp)). Community and literature agree this is the single most effective anti-silence-hallucination and long-file speed lever ("enable VAD" is the near-universal tip; a Silero-class VAD "yields a significant reduction in WER … as well as the incidence of hallucinations" — [arxiv 2501.11378](https://arxiv.org/pdf/2501.11378), [backend comparison](https://builderai.tools/blog/whisper-cpp-vs-faster-whisper-speed-and-accuracy)). whisper.cpp v1.8.5 further improved *streaming* VAD.
- **Whisper.net 1.9.1 ships this**: standalone `WhisperVadFactory` / `WhisperVadProcessor` / `WhisperVadProcessorBuilder` (+ Silero model via `WhisperGgmlDownloader`, `ggml-silero-v6.2.0.bin`) — confirmed present in the [repo source tree](https://github.com/sandrohanea/whisper.net/tree/main/Whisper.net). Note it is exposed as a **separate VAD processor** (you get `VadSegmentData` speech spans), not a `WithVad()` flag on the transcription builder — which is actually the better fit here: **Silero segment boundaries could replace or arbitrate the RMS `SilenceRmsFloor = 0.005` classifier inside ChunkPlanner**, the exact misclassifier behind the #39/#41 dropped-chunk saga (David's speech reads below the RMS floor; Silero is model-driven, so it's doctrinally consistent with the "whisper decides, never RMS-gate" rule — used as a *chunk-cut/classification* signal, not a rejector). This is the second-highest-EV item after beam search.
- Whisper.net 1.9.1 bundles whisper.cpp ~1.8.5 per its release listing (the repo README says to verify via the whisper.cpp submodule commit on the release tag — worth pinning exactly, since 1.8.3+ brought large ggml perf syncs: [1.8.3 iGPU 12x](https://www.phoronix.com/news/Whisper-cpp-1.8.3-12x-Perf), [1.8.4 broad perf + `--gpu-device`](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.8.4), [1.8.6 ffmpeg decode](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.8.6)). No single-stream batching flag exists — batched decoding is what powers beam search internally (free win when you enable beams).
- **DTW token timestamps:** opt-in, needs per-model alignment heads, adds memory + compute, and word-level timestamps are dramatically slower in practice (benchmarkers exclude them for fairness — [backend bench](https://medium.com/@vici0549/whisper-transcription-i-benched-every-major-backend-so-you-dont-have-to-8eff4a68d2a0)). The app only needs segment-end times for TailCoverageGuard; keep `token_timestamps`/DTW off.
- **Whisper.net.Runtime.Cuda12** (new in 1.9.1, Windows/Linux with runtime-loader support): potentially a real speed jump over Vulkan on the RTX 3060 Ti (cuBLAS beats Vulkan on NVIDIA in most whisper.cpp benches) and would revisit the earlier "CUDA needs the toolkit" finding. Flag for a future measured evaluation only; also mind installer size and the CPU-default/GPU-optional distribution decision in §30.

## Ranked recommendations (EV for this app: loops/truncation first, then latency)

1. **Beam search, beam_size 5, GPU flavor** (`WithBeamSearchSamplingStrategy`) — reference-implementation parity, directly attacks the loop/sparse-decode class at the source, ~free on this GPU. Acceptance: re-run the real-capture `--bench` corpus (#38/#42/#43/#45 clips + no-harm set); expect fewer guard firings, not byte-identical output.
2. **Silero VAD (via `WhisperVadProcessor`) as the chunk/silence classifier feeding ChunkPlanner** — replaces the RMS floor that caused the #39/#41 drop class, and is the community's #1 anti-silence-hallucination lever. Keep whisper as the final arbiter (doctrine-compatible).
3. **`WithNoContext()` explicitly on multi-window (>30 s) whole-file decodes** — removes within-call self-reinforcement (the #3744 mechanism); verify what Whisper.net currently passes, since the library default (true) may already cover it.
4. **`WithEntropyThreshold(2.6)`** (from 2.4) — earlier repetition-retry, cheap; community-endorsed in #2286. Leave `logprob_thold` at -1.0 unless calibrated on the clip corpus.
5. **Consume per-segment `no_speech_prob` (+ `WithNoSpeechThreshold`)** — free extra signal to cheapen/strengthen SilenceHallucinationGate (calibrate first; it's a different head than the inverted confidence).
6. **Prompt hygiene:** keep the vocab prompt short (≪224 tokens; last-tokens-win), prefer natural-prose embedding of custom words over bare lists; keep `carry_initial_prompt` OFF.
7. **Confirm forced language + `detect_language=false` on every decode path** (incl. witness decodes) — pure latency win, already mostly in place.
8. **Do-NOT list (protects the guard stack):** `suppress_nst` stays off (NonSpeechAnnotation depends on annotations; suppression worsens silence output), `single_segment` off (blinds TailCoverageGuard), `max_len`/`max_tokens` at 0, DTW/token timestamps off.
9. **Future measured experiments:** Whisper.net.Runtime.Cuda12 vs Vulkan; CPU-flavor beam-2 vs greedy.

*(Full source list preserved in the agent transcript; key ones inline above.)*

---

## Area 2 — Backend / runtime / models

### §3. Codebase analysis

# JVoice-Windows Backend/Runtime/Model Layer — Findings

## 1. Current architecture (as built)

### Runtime backend selection
- `windows\JVoice.App\Whisper\WhisperRuntime.cs`: JVoice does **not** choose a backend explicitly. Whisper.net auto-probes its default order (CUDA → Vulkan → CPU) lazily on the first `WhisperFactory.FromPath`. `WhisperRuntime.EnsureLoaded()` is a no-op marker (no public preload API in 1.9.1); `Describe()` reads `RuntimeOptions.LoadedLibrary` after the fact for logs/bench.
- `--bench --runtime auto|cuda|cuda12|cuda-any|vulkan|cpu` (`BenchRunner.cs` lines 123–138) calls `WhisperRuntime.ForceRuntimeOrder(...)`, which sets `RuntimeOptions.RuntimeLibraryOrder` **before** first factory creation — forcing a single library makes a missing backend a hard `FileNotFoundException` instead of a silent fallback. `--log-runtime` streams whisper.cpp debug logs.
- Package flavors (`windows\JVoice.App\JVoice.App.csproj`): always `Whisper.net` 1.9.1 + `Whisper.net.Runtime` 1.9.1 (CPU, universal fallback). `Whisper.net.Runtime.Cuda` + `.Vulkan` 1.9.1 are referenced **only when `JVoiceFlavor != 'cpu'`** (keeps ~418 MB of GPU natives out of the CPU build). The `cpu` flavor also defines `JVOICE_CPU`, which forces flash attention off in two places (`EngineTuning.Default` and a guard in `PerformLoadAsync`).
- No `Whisper.net.Runtime.NoAvx` and no `Whisper.net.Runtime.Cuda12` are referenced. On the dev box CUDA fails (no toolkit) → Vulkan loads.

### Model selection/download
- `WhisperModelStore.cs`: manifest of 4 GGML files from `huggingface.co/ggerganov/whisper.cpp` — `ggml-tiny.bin`, `ggml-base.bin`, `ggml-small.bin`, and **`ggml-large-v3-turbo-q5_0.bin` (574 MB)**. Important: **the default LargeTurbo model is already the q5_0 quantization** — not the f16 `ggml-large-v3-turbo.bin` (~1.6 GB). Tiny/Base/Small are the f16 files. Download → `.part` → size check (+ SHA-256 for tiny only) → atomic rename. This is the app's only runtime network call.
- Default model is `LargeTurbo` for all users (both flavors), per §7 #35.

### Engine lifecycle (`WhisperNetTranscriptionEngine.cs`)
- **Factory (model weights) is loaded once and kept warm**: `LoadFactoryAsync` dedupes concurrent loads under `_gate`; `_factory` lives for the engine's lifetime. `VoiceCoordinator` calls `PrewarmAsync()` at startup (line 407), so weights persist between dictations.
- **A fresh `WhisperProcessor` is built per decode** (`DecodeSamplesAsync` lines 374–401: `factory.CreateBuilder()...Build()` then `await using` disposes it). Every decode pays `whisper_init_state` (KV caches, compute buffers, Vulkan allocations) again.
- **Prewarm loads the factory but never decodes.** The first real dictation pays the lazy-init cost (Vulkan pipeline/shader warm-up, first compute-buffer allocation). Evidence: `BenchRunner` deliberately runs one warm-up decode "excluded so steady-state timing isn't polluted by lazy init" (lines 183–184).
- **Engine is fully rebuilt (new object → new factory → full model reload) on**: model change, **language change**, **Translate-to-English toggle**, Restore Defaults (`VoiceCoordinator.cs` lines 123–126, 137–140, 272–275, 653). But `_language` and `_translate` are used only in the per-decode **builder** (`WithLanguage` / `WithTranslate`), never in factory creation — the factory depends only on (model path, flash flag). So language/translate swaps reload ~574 MB of weights for nothing. Vocabulary changes correctly do NOT rebuild (in-place `UpdateVocabularyAsync` + prompt-string cache).
- **The old factory is never disposed.** `SwapEngine` just replaces `_engine`; `WhisperNetTranscriptionEngine` has no `Dispose`, and `_factory` (IDisposable, native + GPU memory) is dropped to the GC. Repeated toggling of translate/language can hold multiple model copies in native/VRAM until finalization.

### Tuning (§7 #31, confirmed in code)
`EngineTuning.Default`: flash attention ON (GPU builds; ~30–37% faster on Vulkan large-v3-turbo, byte-identical transcripts) / OFF under `JVOICE_CPU`; `WithThreads` = physical cores via `CpuInfo` (`WhisperTuning.DecodeThreads`, clamp [1,16]; ~21% CPU win); adaptive `audio_ctx` implemented (`WhisperTuning.AudioContextFor`, whisper.cpp issue #1855 formula, floor 768) but **not adopted** — measured non-monotonic (768 regressed ~9 s clips 2–3×). Temperature fallback: `WithTemperature(0)` + `WithTemperatureInc(0.2)`.

### Witness/guard decode multiplication
On the whole-file path (`TranscribeAsync`), a single dictation can run up to **4–5 full decodes** of overlapping audio, sequentially: 1. prompted decode (always), 2. RegurgitationRecovery unprompted re-decode (on regurgitation/empty), 3. SilenceHallucinationGate witness (near-silent + non-empty), 4. PhraseLoopGuard witness, 5. SparseTranscriptGuard witness, 6. TailCoverageGuard tail decode (tail-only audio). Mutually mostly exclusive in practice, but loop+sparse+tail can chain. Streaming chunks that trip loop/sparse guards throw `DegenerateDecode` → session fails → a **whole-file** decode of the entire recording re-runs (plus its own guards) — correct-by-doctrine (#41) but the worst-case latency path. Each witness re-runs the **encoder** too; Whisper.net 1.9.1 exposes no encoder-state reuse — upstream API limit, not a local bug.

### Whisper.net version currency
- Repo pins 1.9.1 everywhere (only 1.9.1 in local NuGet cache). HANDOFF §7 #31 (2026-06-27) records "1.9.1 is already latest" at that date.
- Upgrade-friction surface (APIs used): `WhisperFactory.FromPath(+WhisperFactoryOptions.UseFlashAttention)`, `CreateBuilder().WithLanguage/WithTranslate/WithTemperature/WithTemperatureInc/WithThreads/WithAudioContextSize/WithPrompt`, `ProcessAsync(float[])` segment streaming, `RuntimeOptions.RuntimeLibraryOrder/LoadedLibrary`, `LogProvider.AddConsoleLogging`. Most version-fragile: `RuntimeOptions` statics and `WhisperFactoryOptions`.

## 2. Ranked improvement candidates

1. **Stop reloading the model on language/translate toggles** (speed, UX). Make `_language`/`_translate` mutable per-decode settings (like vocabulary) or pass the loaded factory into the new engine. Saves a full 574 MB reload + GPU re-upload per toggle and fixes the undisposed-factory leak in `SwapEngine`. Effort: small; risk: low — factory provably depends only on (model, flash). Also add `IDisposable` to the engine and dispose the old factory on real model swaps.
2. **Startup warm-up decode** (perceived speed of first dictation). After `PrewarmAsync`, decode ~1 s of zero samples in the background. Hides Vulkan pipeline compile/buffer-pool warm-up from the first hotkey press. Effort: tiny; risk: minimal (discard output; never touch guards/stats).
3. **Reuse `WhisperProcessor` across decodes** (per-decode latency, esp. streaming's chunk decodes). Cache one processor per configuration (prompted / unprompted), invalidate on vocab/language/translate change. Eliminates per-call `whisper_init_state`. Effort: moderate; risk: moderate — must verify whisper.cpp carries nothing across `whisper_full` calls; measure before adopting.
4. **CPU-flavor default model review**. `SettingsState.Default.Model = LargeTurbo` applies to CPU-only users too; large-v3-turbo q5_0 on typical AVX2 CPU plausibly slower than real-time; witness decodes double it. Options: flavor-aware default (e.g. Small on `JVOICE_CPU`) or soften the "Keep this on Large" advisory in the CPU build. Effort: small; risk: product decision (David's) — #35 advisory was calibrated on his GPU.
5. **Quantized variants for the smaller models** (download size + CPU speed). Large is already q5_0; Tiny/Base/Small are f16. Adding q5_1/q8_0 rows is trivial (manifest entry + `GgmlFileName` case + expected bytes). q8_0 Small ≈ half download, ~equal accuracy. Flip side: **higher-precision large-turbo q8_0 (~874 MB) is the available *accuracy* lever upward** from today's q5_0 on the 8 GB GPU — VRAM headroom ample. Effort: small; risk: low.
6. **CUDA as a shipped opt-in for the GPU flavor** (speed). CUDA documented faster than Vulkan for whisper.cpp on NVIDIA; today silently fails without the toolkit (`Runtime.Cuda` needs CUDA 13 runtime; `Cuda12` package not referenced). Candidate: also reference `Cuda12` so users with CUDA 12 runtime get it. Effort: tiny (one PackageReference); risk: bigger GPU installer.
7. **Bound the guard-decode chain** (worst-case latency). Carry a "witness already run" flag so loop→sparse don't each re-decode unprompted (they request the identical unprompted whole-file decode — compute once and share). Effort: small; risk: low; preserves guard semantics.

## 3. Notable risks / inconsistencies spotted
- `SwapEngine` leaks the previous native model (no dispose) — worse now that translate/language toggles rebuild.
- csproj `cpu` flavor still sets `PublishSingleFile=true`, but single-file publishes fail ("Native Library not found") and the rule is "ship the folder build". Latent trap for `JVoiceFlavor=cpu` publishes.
- CPU runtime ships a single AVX-enabled `ggml-cpu-whisper.dll`; pre-AVX CPUs would need the unreferenced `Whisper.net.Runtime.NoAvx` — doc note.
- Adaptive `audio_ctx` stays correctly off (measured non-monotonic) — don't revisit without new measurements.

### §4. External research

# Whisper Backend / Runtime / Model Landscape

## 1. Whisper.net release history after 1.9.1

**Headline: 1.9.1 (released 2026-06-01) is the latest stable — the app is already on the newest Whisper.net.** NuGet history: 1.8.0/1.8.1 (Mar 2025) → 1.9.0 (2025-11-16) → 1.9.1-preview1 (2026-01-18) → 1.9.1 (2026-06-01).

- **1.9.1 bundles whisper.cpp 1.8.5.** Upstream whisper.cpp is now at **v1.9.1** (June 2026), but the delta 1.8.5→1.9.1 is small: 1.8.7 was maintenance/CI, **1.9.0's headline was NVIDIA Parakeet model support in whisper.cpp itself** (see §4 below — a significant watch item), 1.9.1 was CI fixes.
- Relevant 1.9.x-line features already available in the API you're on: **Silero VAD integration via `WhisperVadFactory`**, CUDA 12 + CUDA 13 runtime packages with automatic probing, improved cancellation/error propagation, `carry-initial-prompt` handling fixes.
- whisper.cpp **1.8.0 turned flash attention ON by default**; the §31 tuning is already aligned with upstream's direction.
- **Upgrade risk assessment: nothing to upgrade today.** Watch: when Whisper.net 1.10/2.0 lands with whisper.cpp ≥1.9.0, it potentially brings Parakeet support into the exact stack already shipped.
- **Unused lever already in 1.9.1: native Silero VAD.** Caution: project doctrine is "whisper decides, never an RMS gate" (§7 #21) — Silero is a *neural* VAD; if trialed, position it as a chunk-boundary/trigger improvement (replacing the failure-prone `SilenceRmsFloor` classifier from §39/§41) with the same "model decides" fallbacks, validated against the quiet-mic clips.

## 2. Vulkan vs CUDA on NVIDIA consumer GPUs

- **Measured gap:** Vulkan delivers roughly **70–90% of CUDA throughput** for the same whisper.cpp workload on a discrete RTX card. The Vulkan backend matured rapidly through 2025–2026 (whisper.cpp 1.8.3 shipped a "12× performance boost" for integrated GPUs via Vulkan work).
- **CUDA packaging: the toolkit requirement stands.** Whisper.net README requires **CUDA Toolkit ≥ 13.0.1** for `Whisper.net.Runtime.Cuda` (or CUDA 12 toolkit for `.Cuda12`); the 136 MB `Cuda.Windows` package contains the ggml-CUDA whisper library but **not** cudart/cublas. Workaround possible at $0: NVIDIA's EULA permits redistributing cudart + cuBLAS DLLs (whisper.cpp's own official `cublas` release zips do this) — but that adds roughly **600–800 MB** to the installer for a ~10–40% decode speedup on clips that already finish in <1 s. Bad trade for this app.
- **Vulkan correctness:** known issues concentrate on **AMD/Intel** GPUs; on NVIDIA, Vulkan is considered stable, and the app's own byte-identical no-harm sweeps are evidence of correctness on this exact GPU.
- **Verdict: keep Vulkan as the shipped GPU backend.**

## 3. Quantized GGML variants of large-v3-turbo

Key context: **the installed default (~574 MB GGML) is already the q5_0 quantization** (f16 turbo is ~1.6 GB). The interesting move may be *up*, not down:

- **Accuracy:** quantization loss is small but real — Q8_0 is essentially transparent; **q5_0 is the most degraded of the common choices** (q5_1 > q5_0 in quality) ([arXiv 2511.08093](https://arxiv.org/pdf/2511.08093), [whisper.cpp discussion #3752](https://github.com/ggml-org/whisper.cpp/discussions/3752)).
- **Speed on GPU: quantized can be *slower* than f16.** GPU backends must dequantize per-op; whisper.cpp has a confirmed report of quantized models taking *more* time on Metal, and the Vulkan dequant path has the same structural overhead ([issue #2241](https://github.com/ggml-org/whisper.cpp/issues/2241)). Bandwidth savings can win on some cards, but the gain is not guaranteed the way it is on CPU.
- **CPU:** q5_0/q5_1 are notoriously slow kernels (3–5.5× slower than q4_0 in one systematic CPU benchmark); q8_0 and q4_0 have the fast paths. Relevant to the CPU-flavor installer.
- **VRAM:** irrelevant on 8 GB — f16 turbo needs ~1.6 GB weights + ~0.5 GB working.

**Verdict: the single cheapest accuracy experiment available is swapping the model file — bench q8_0 (~874 MB) and f16 (~1.6 GB) turbo against the current q5_0 on the real capture corpus.** Zero code change (model-store path only), likely a small accuracy gain, and plausibly *faster* on Vulkan, not slower. Given the §42–§45 saga is prompt-induced decode degeneracy, a less-quantized decoder is also marginally less likely to fall into degenerate modes.

## 4. Alternative models

- **distil-large-v3 / v3.5:** ~1.5× faster than turbo, short-form OOD WER slightly *better* than turbo. **⚠ ENGLISH-ONLY — disqualified as the default model for JVoice (Romanian required).** Skip.
- **large-v3 full:** the accuracy ceiling for Romanian — turbo ≈ large-v2 level multilingual. But **large-v3 is itself notorious for repetition loops** — switching would NOT escape the §42/§45 loop class and costs ~4× decoder compute. Only bench if Romanian accuracy specifically disappoints.
- **NVIDIA Parakeet-tdt-0.6b-v3 — the most interesting alternative.** 600 M params, **25 European languages including Romanian**, tops English leaderboards at RTFx far beyond Whisper (blazing speed even on CPU), permissive CC-BY-4.0. Two $0 .NET paths exist **today**: (1) **sherpa-onnx** ships an official C# NuGet (`org.k2fsa.sherpa.onnx`) with offline-recognizer support for parakeet-tdt-0.6b-v3 (int8 ONNX ~640 MB), CPU + CUDA + DirectML; (2) **whisper.cpp v1.9.0 added native Parakeet support** — the *next* Whisper.net bump may run Parakeet GGML through the engine already shipped. Strategic note: TDT/transducer decoding is **structurally immune to the prompt-induced degenerate-loop / sparse-decode class** (#42–#45) — no autoregressive LM decoder to spiral, no decoder prompt. Trade: loses `VocabularyPrompt` biasing (custom words rely purely on post-processing correction). Moonshine (English-only) and Kyutai STT (EN+FR) fail the Romanian requirement — dismissed.

## 5. Alternative .NET-usable runtimes

- **faster-whisper / CTranslate2:** fastest Whisper on NVIDIA (often ~2× whisper.cpp CUDA), but **no C# bindings**; only path is a Python sidecar or HTTP server — heavy, fragile, violates the single-process tray-app shape. **Not viable.**
- **whisper.cpp server mode:** same whisper.cpp already in-process — zero gain, added complexity. No reason.
- **ONNX Runtime DirectML Whisper:** second-class turbo exports, custom-op maintenance, no evidence it beats whisper.cpp Vulkan on NVIDIA. The sensible ONNX play is sherpa-onnx + Parakeet, not ONNX-Whisper.

## 6. OS-level factors on Windows

- **HAGS:** measured effect −2% to +3%, gaming-centric — not worth touching (and David games on this machine).
- **GPU clock ramp is the one real OS-level latency source:** NVIDIA GPUs idle at low clocks; the first submission after idle pays a ramp penalty — exactly the JVoice pattern (idle tray → sudden decode). Options: NVIDIA Control Panel per-program "Prefer maximum performance" for JVoice.exe only, or **in-app: a tiny GPU warm-up submission when recording *starts*** so clocks are up before the decode lands (the recording gives a multi-second ramp window).

## Ranked recommendations

| # | Action | Expected gain | Feasibility/cost |
|---|--------|---------------|------------------|
| 1 | **Bench q8_0 and f16 turbo vs the current q5_0 default** on the real capture corpus | Small accuracy gain + possibly *faster* on Vulkan; marginally fewer degenerate decodes | Trivial — model file swap, zero code |
| 2 | **In-app GPU warm-up at record-start** (or per-app "Prefer maximum performance") | Shaves idle→first-decode clock-ramp latency | Small, in-app, reversible |
| 3 | **Trial whisper.cpp Silero VAD** as replacement for the RMS `SilenceRmsFloor` chunk classifier | Faster long dictations + attacks the §39/§41 silent-chunk misclassification at the source | Medium; validate on quiet-mic clips |
| 4 | **Prototype Parakeet-tdt-0.6b-v3 via sherpa-onnx C#** (Romanian ✓, CC-BY, structurally loop-immune) | Potentially eliminates the entire prompt-loop bug class + big speed headroom | Large: new engine; watch whisper.cpp ≥1.9.0 delivering it in-stack |
| 5 | Bench **full large-v3** for Romanian specifically | Romanian ceiling; English ~nil; does NOT fix loops | Trivial to bench |
| 6 | CUDA backend (toolkit or ~700 MB DLL redistribution) | ~10–30% on decodes already <1 s — imperceptible | Poor trade; keep Vulkan |
| 7 | distil / Moonshine / Kyutai | — | **Disqualified: no Romanian** |
| 8 | faster-whisper interop / server mode / ONNX-DirectML | — | Not viable / no gain / unproven |

---

## Area 3 — Audio & streaming pipeline

### §5. Codebase analysis (with real log mining)

# Audio Capture + Streaming Pipeline: Speed & Accuracy Headroom

All numbers come from code inspection plus mining the real on-device log `%APPDATA%\JVoice\diagnostic.log` (2.7 MB, 39,696 lines, through 2026-07-24 18:00).

## 1. Capture pipeline as-built

**Files:** `windows\JVoice.App\Platform\Capture\NAudioRecorder.cs`, `windows\JVoice.Core\Audio\WavTail.cs`

- **Capture:** `WasapiCapture(device, useEventSync: true)` shared mode → device mix format (typically 48 kHz / 32-bit float / 1–2 ch).
- **Conversion chain (`TryStart`, lines 85–94):** `BufferedWaveProvider` (5 s ring) → `StereoToMonoSampleProvider` (0.5/0.5 mix) → `WdlResamplingSampleProvider` to **16 kHz** → `SampleToWaveProvider16` → `WaveFileWriter` (16 kHz mono 16-bit).
- **Write cadence:** timer pumps every **250 ms**, flushing so `WavTailReader` sees fresh bytes.
- **Resampler quality:** WDL (Cockos) sinc resampler — the best NAudio ships fully managed; proper anti-aliasing. No quality concern for whisper input.
- **Stop path:** all cheap — single-digit ms.

**End-to-end critical path after the stop press** (`VoiceCoordinator.StopRecordingAndTranscribe` → `FinishTranscriptionAsync`, `VoiceCoordinator.cs:878–1081`):
1. UI thread: `_recorder.Stop()` → foreground-target resolve → HUD "Transcribing".
2. Background: `IsUsableRecording` → engine-ready check → `session.Finish()` → if null, `_engine.TranscribeAsync(wholeFile)` + guard cascade (each triggered guard = a full extra decode).
3. Post-process (ms) → `ActivateWindow(target)` → **`await Task.Delay(80 ms)`** (`AppTimings.PasteActivationDelay`) → `Paster.Paste`: clipboard set (retry loop) → `FocusTarget` → **a second `Thread.Sleep(80 ms)`** inside `Paster.Paste` → `SendInput` Ctrl+V. Clipboard restore is async — off the critical path.

Note the **double settle delay**: ~160 ms of fixed sleep on every paste.

## 2. ChunkPlanner policy and the tail at stop

**File:** `windows\JVoice.Core\Audio\ChunkPlanner.cs`. Constants: `SampleRate` 16 000, `MinChunkSeconds` **15**, `MaxChunkSeconds` **25**, `SilenceWindowSeconds` **0.3**, `SilenceRmsFloor` **0.005** (absolute), `RelativeSilenceFraction` **0.1**. `IsSilent` (chunk classification) uses the **absolute 0.005 floor only**.

**Undecoded tail at stop:** ~0–25 s, expectation ~8–12 s for continuous speech. Recordings **< 15 s never stream at all** (log confirms: 0 of 205 sub-15 s stops streamed).

**Wasted work in `Finish()` (`StreamingTranscriptionSession.cs:85–116`):** the backlog drain *decodes* remaining cuts first, and only *then* checks whether the final tail is silent-classified → returns null → every backlog decode it just paid is thrown away and the whole file is re-decoded anyway. `ChunkPlanner.Plan` is pure/fast — the tail verdict could be taken *first* and the drain skipped on that path.

## 3. How often streaming actually pays off (real log numbers, since 2026-07-13)

| Cohort | n | stream | whole-file | stream success |
|---|---|---|---|---|
| < 15 s | 205 | 0 | 205 | n/a (never eligible) |
| ≥ 15 s | 198 | 76 | 122 | **38%** |
| ≥ 30 s | 118 | 47 | 71 | 40% |

**Why streaming fails:** **59× "silent final tail"** + **53× "silent-classified but decoded N chars → whole-file fallback"** — i.e. **112 of ~122 fallbacks (~92%) are the absolute 0.005 `SilenceRmsFloor` misclassifying David's quiet speech (window-RMS 0.0005–0.004) as silence**. Only 4 hard failures and 4 degenerate-decode fallbacks. "Silent-classified, model confirmed empty → skipped" fired **0 times** — on this mic the silent classification is essentially *never* right, yet it torpedoes the session every time it fires.

**Measured stop→transcribed latency** (log timestamp deltas, since 07-13):

| Cohort | median | mean | p90 |
|---|---|---|---|
| < 15 s (whole-file) | 371 ms | 541 ms | 943 ms |
| ≥ 15 s, streamed | **369 ms** | 433 ms | 575 ms |
| ≥ 15 s, whole-file fallback | 751 ms | 1 052 ms | 2 137 ms |
| ≥ 60 s, streamed | 431 ms | 473 ms | 1 182 ms |
| ≥ 60 s, whole-file fallback | **1 676 ms** | 1 804 ms | 2 745 ms |

Streaming, when it works, makes stop→paste ~duration-independent (~0.4 s); the fallback costs ~1.3 s extra at 60 s+, ~2.3 s at p90.

## 4. Whole-file fallback: reuse and early start

- **The streamed partial result is discarded entirely** — deliberate and, per #41/#43 evidence, correct (isolated chunk decodes of quiet audio were observed silently partial while claiming full timestamp coverage). Reuse would reintroduce exactly the failure class the doctrine prevents.
- Starting the fallback during recording isn't possible in the strict sense (needs the complete file). `Finish()` on a failed session already returns null fast; the big waste is the non-failed silent-tail path in §2.

## 5. Accuracy of the 16-bit / 16 kHz conversion for quiet audio

- **No clipping risk**; dual-mono capture sums back to original level via the 0.5/0.5 mix; WDL resampler and `SampleToWaveProvider16` clamp properly.
- **No dither** (plain scale-and-truncate) — at ~0.004 peak (~131 LSB) quantization noise is ~42 dB below signal; not a practical factor. Not worth adding.
- **`HighPassSilence` feeds nothing decode-relevant** — confirmed metrics-only; `rawRms` additionally serves as the `SilenceHallucinationGate.ShouldVerify` trigger. The spectral `IsSilent` gate is unwired, as documented.

## 6. Ranked proposals

### (b) Streaming success rate — the structural lever

1. **Replace the absolute silent-classification with the spectral classifier that already exists** — the single highest-leverage change in the whole pipeline. `ChunkPlanner.IsSilent`'s bare `peak < 0.005` floor causes ~92% of fallbacks and was *never once correct* in the current log era. `HighPassSilence.IsSilent(hpRms, rawRms)` was built and calibrated on this exact mic (test-locked anchors) to separate quiet speech (broadband, ratio ≥ 0.2) from hum (ratio ≤ 0.12) — and currently sits unwired. Wire it into `StreamingTranscriptionSession` (both `PollOnce` and `Finish`) instead of (or ANDed with) the absolute floor. Doctrine check: this is *not* an RMS no-speech gate — classification only routes **trust**, never rejects speech; the model still decides no-speech. Failure modes: (i) quiet speech now classifies non-silent → decodes and appends → streaming succeeds (the win); (ii) true silence misclassified non-silent → decodes empty → session fails → lossless whole-file fallback (costs latency, never text); (iii) residual: a quiet chunk whose trusted decode is silently partial (the #41 fingerprint) — the chunk-level SparseTranscriptGuard check from #43 (<4 chars/s on ≥10 s) catches the observed case (16.35 s → 40 chars ≈ 2.4 chars/s); a partial decode *above* that density could still slip — state in the commit, optionally tighten the chunk-level density threshold for spectrally-quiet chunks. Expected effect: ≥15 s stream success 38% → plausibly 80–90%; median stop→paste on 60 s+ dictations 1.7 s → ~0.45 s.
2. **Apply the same spectral test to the final-tail check** (`Finish()`, line 109) — kills the 59 "silent final tail" fallbacks. A genuinely silent tail then decodes empty → session fails → whole-file (unchanged outcome, one wasted small decode).
3. **Optionally cut more eagerly** — `MinChunkSeconds` 15 → ~10 shrinks the expected undecoded tail to ~5–7 s and lets sub-15 s dictations (52% of all stops, currently never streamed) partially stream. Second-order; do only after 1–2 land and re-measure.

### (a) Stop→paste latency

4. **Reorder `StreamingTranscriptionSession.Finish()`: plan first, decode later.** Take the tail verdict *first*; today the 59-case silent-tail path pays backlog chunk decodes guaranteed to be discarded. (Largely mooted if proposal 2 lands, but correct regardless.)
5. **Collapse the double settle delay.** The coordinator waits 80 ms after `ActivateWindow`, then `Paster.Paste` re-focuses and sleeps another 80 ms. One focus + one delay suffices. ~80 ms off every paste; re-verify paste reliability in slow-focusing apps.
6. **Scope the `SilenceHallucinationGate` witness by clip length.** Since 07-13: 88 witness decodes, **73 "kept"** — 83% of the time a real quiet dictation paid a full second decode purely to vouch for itself. The hallucination class was only ever observed on short presses (calibration set 3.7–22 s). Add an audio-duration ceiling to `ShouldVerify` (e.g. only verify clips < ~30 s, or gate on transcript length). Policy-constant change in `SilenceHallucinationGate.cs`; needs a mini-calibration pass against kept captures.
7. **True prewarm.** `PrewarmAsync` only loads the factory; first dictation pays `builder.Build()` state init + Vulkan pipeline warm. Decode ~0.5 s of zeros once at load. Measure cold-vs-warm with `--bench` before claiming the size.
8. **Measure `WhisperProcessor` reuse.** Two cached processors (prompted / unprompted), rebuilt on vocabulary change, would amortize `whisper_init_state`. Unknown magnitude on Vulkan — bench first.
9. **CUDA as an opt-in measured experiment** — engine already auto-probes CUDA when the toolkit is present (free download for the dev box). Worth one bench session; not a code change.

**Explicitly not proposed** (documented dead ends respected): digital gain on transcription audio (§7 #22), any RMS floor that *rejects* speech (§7 #21), reusing streamed pieces in the fallback (#41 evidence), adaptive `audio_ctx` (§31).

**Priority order:** 1 & 2 (spectral chunk/tail classification) → 5 (single settle delay) → 6 (witness scope) → 4 (Finish reorder) → 7/8 (prewarm + processor reuse, measure first) → 3 (eager cuts) → 9 (CUDA bench).

### §6. External research

# Audio-Pipeline Techniques (external evidence)

## 1. VAD for chunking

- **Whisper.net 1.9.1 itself ships VAD support** — `WhisperVadFactory`/`WhisperVadProcessor`, an `examples/Vad` sample, and Silero model download (`ggml-silero-v6.2.0.bin`). whisper.cpp 1.8.5 includes the native VAD path. No separate ONNX Runtime dependency required. If the reference ONNX model is ever wanted instead: [VadSharp](https://github.com/ZygoteCode/VadSharp) (Silero v5, DirectML) or [ManySpeech.SileroVad](https://www.nuget.org/packages/ManySpeech.SileroVad/) — both maintained .NET options.
- **Measured effects:** VAD pre-segmentation is the best-documented anti-hallucination lever: WER 0.675 → 0.419 in one long-form pipeline ([WhisperAlign, arXiv 2603.04809](https://arxiv.org/html/2603.04809v1)); WhisperX's VAD Cut & Merge reports the lowest hallucination/insertion rate among compared systems ([arXiv 2303.00747](https://arxiv.org/pdf/2303.00747)). Trimming *leading* silence to ~0.3 s alone cut WER 30.47% → 27.34% ([arXiv 2501.11378](https://arxiv.org/pdf/2501.11378)).
- Caveat: naive silence *removal* destroys pause structure whisper uses for punctuation; padding around cuts "primarily serves to suppress hallucinations" ([NPUsper, arXiv 2607.01108](https://arxiv.org/pdf/2607.01108)).
- **Quiet-speech risk (critical here):** stock Silero threshold 0.5 misses quiet speech; for soft speakers go below 0.5. Given David's mic reads below the 0.005 RMS floor, any VAD adoption should start at **threshold ≈ 0.25–0.35**, be validated against the kept real captures, and follow the doctrine: **VAD as a trigger/segmenter, never a rejector**. `speech_pad_ms` at the generous end (~100–200 ms) + `samples_overlap` ≈ 100 ms; `min_silence_duration_ms` ≥ 300–500 ms so intra-sentence pauses don't fragment segments. Silero v5 vs v6: near-equal frame accuracy; v6 better on noise false-positives.
- **Assessment:** the strongest use here is replacing the **RMS cut-point/classification decision** in ChunkPlanner — the exact component that misclassified quiet speech in §39/§41 — while keeping "decode everything, model decides, fallback on disagreement."

## 2. Chunking best practices for streaming Whisper

- **Prompt/context carry is the documented loop factory** — `condition_on_previous_text=False` "drastically reduces hallucination" ([openai/whisper #679](https://github.com/openai/whisper/discussions/679)); never carry the previous chunk's transcript as prompt on top of the vocab prompt (stacks two loop inducers).
- **Chunk length sweet spot:** aim for **8–20 s** segments cut at ≥300 ms pauses. The streaming literature's LocalAgreement-2 (two consecutive decodes agree on a prefix) insight — **agreement between two decodes is the reliability signal** — is precisely what the witness-decode guards already exploit ([Whisper-Streaming, arXiv 2307.14743](https://arxiv.org/pdf/2307.14743)).
- **Mid-speech cuts are formally harmful** (Simul-Whisper, [arXiv 2406.10052](https://arxiv.org/abs/2406.10052)): truncating mid-word produces unreliable last words. Cutting only at VAD-confirmed silence with 100–200 ms pad is the correct policy — ChunkPlanner's design is right; its silence detector was the weak link.
- The "16 s chunk → last 40 chars" failure (#41) matches a known whisper long-form failure class; upstream implementations detect-and-retry (WhisperX decodes VAD-merged segments *without* cross-segment conditioning). The density/coverage guards + fallback are the state of the art; nothing found supersedes them.

## 3. Audio conditioning that helps whisper (beyond gain)

Measured evidence is **against** generic denoising in front of whisper:
- **DeepFilterNet before whisper measurably hurt**: ~20% WER *degradation* on Fleurs across Whisper v1/v2/v3 ([DeepFilterNet issue #483](https://github.com/Rikorose/DeepFilterNet/issues/483)).
- Enhancement-for-ASR literature is mixed ("no single method helps all files"); whisper trained on 680k h of raw noisy audio already carries noise robustness ([DENOASR, arXiv 2410.16712](https://arxiv.org/pdf/2410.16712)).
- **High-pass filtering**: no credible measured WER win for close-mic dictation. `HighPassSilence` being metrics-only is the right call.
- The one conditioning intervention with measured benefit is **silence topology management** (trim long leading silence, keep natural pauses, pad cuts) — that's VAD, not DSP.
- **Do not put RNNoise/DFN in the default path** (at most a hidden opt-in "noisy environment" toggle someday).

## 4. Resampling quality (WASAPI 48 k → 16 k)

- whisper.cpp does **no internal resampling**; reference pipelines use bandlimited sinc. No controlled "linear vs sinc → ΔWER" study found, but aliasing folds 8–24 kHz content into the speech band — the effect is small on clean speech but *non-zero on quiet speech*, where artifact energy competes with low signal energy.
- NAudio guidance: `MediaFoundationResampler` quality 60 is most transparent; `WdlResamplingSampleProvider` usable but observed to "dull" results in Mark Heath's comparison ([NAudio Resampling.md](https://github.com/naudio/NAudio/blob/master/Docs/Resampling.md)). *(Codebase agent confirms WDL sinc is in use — adequate; an MF-quality-60 A/B is a cheap hedge.)*

## 5. Latency architecture used by other local dictation apps

- **Keep the model resident + pre-warm**: universal. One dictation-app builder cut lag 20 s → 2 s largely by warm-loading the model with a dummy prompt at startup. For Vulkan the first inference also compiles/warms pipelines — a **one-time ~0.5–1 s dummy decode of silence at startup** (and after every engine rebuild) moves that cost off the first hotkey press. JVoice keeps the engine resident; the startup dummy-decode is the missing 20%.
- **Decode during recording**: JVoice's streaming-chunks design is exactly what the fastest apps do; [Handy](https://github.com/cjpais/Handy) still decodes whole-clip on hotkey-release — JVoice is *ahead* on this axis.
- **Partial-hypothesis display**: conflicts with the "silent success" UX; low value. Optional middle: provisional text in the HUD only.
- **CPU-flavor direction:** Handy ships **Parakeet V3** as its CPU model at ~5× real-time on an i5.
- **Tail latency trick**: ensure the final chunk decode starts the instant stop is pressed (not after WAV finalization completes).

## 6. Real-time-factor expectations (sanity ceiling)

| Platform | Figure | Implied RTF |
|---|---|---|
| RTX 3060, faster-whisper CUDA, turbo | ~4 s per 30 s chunk | **~0.13** |
| RTX 3060, faster-whisper, large-v3 | ~8 s per 30 s | ~0.27 |
| CPU (modern desktop), turbo | — | ≈1× RT on i5-class |

Treat **RTF ≈ 0.15–0.35 as the healthy band for a 3060 Ti + Vulkan + flash-attention**. If the app measures materially worse than ~3× real-time on GPU for whole-file decodes, something is off (CPU fallback engaged, flash off, or per-decode model reload).

## Ranked recommendations

1. **Replace the RMS silence-cut decision with Silero VAD probabilities** (built into Whisper.net 1.9.1), threshold ~0.25–0.35, 100–200 ms padding, ≥300 ms min-silence — attacks the proven root cause; VAD chooses cut points, never discards audio; validate on the real-capture corpus.
2. **Startup/rebuild warm-up decode** (~1 s silence) — trivial, pure perceived-latency win.
3. **Audit the 48 k→16 k resample path** — WDL sinc is in use (fine); MF quality-60 A/B is a free hedge.
4. **Keep streaming chunk decodes strictly context-free; cut only at VAD-confirmed pauses ≥300 ms with padding** — codifies existing policy.
5. **LocalAgreement-style two-decode agreement as the general reliability signal** — conceptual reinforcement of the witness-decode guards; never scalar-confidence thresholds.
6. **Do NOT add denoising or HPF to the transcription path** — measured evidence against.
7. **(Watchlist)** Parakeet-class models for the CPU flavor; Silero v6 over v5 if choosing an ONNX model.

---

## Area 4 — Prompt & guard layer

### §7. Codebase analysis

# Prompt / Guard / Post-Processing Layer: Accuracy Headroom & Latency Audit

Sources: `windows\JVoice.Core\Text\*`, `windows\JVoice.Core\Policy\*`, the engine + `VoiceCoordinator`, `StreamingTranscriptionSession`/`ChunkPlanner`, David's live `%APPDATA%\JVoice\settings.json` and `diagnostic.log` (39,696 lines), and reflection of the shipped `Whisper.net.dll`.

## 1. Prompt construction & the full re-decode decision tree

### 1.1 Prompt construction (`windows\JVoice.Core\Text\VocabularyPrompt.cs`)
- Format: `" " + string.Join(", ", cleanedWords.Take(40))` — a leading space (BPE merges it into word tokens) + a **comma-separated flat list**, no carrier sentence, no terminal punctuation.
- Caps: `MaxWords = 40`; `MaxPromptTokens = 96` exists as a constant but is **NOT enforced on Windows** — Swift trimmed post-tokenization; Whisper.net's `WithPrompt(string)` tokenizes internally with no trim hook, so only the 40-word cap holds. 40 multi-word entries could exceed 96 tokens.
- Empty list: returns `null`; the engine only calls `WithPrompt` when non-empty — **the prompt is already dropped when the custom-word list is empty**. All four witness guards check the prompt is non-empty before firing. One exception: `RegurgitationRecovery` keys off the `_useVocabularyPrompt` **flag** (hardcoded `true`), not the actual prompt — see §2.4.
- Language: no interplay — a Romanian decode still gets the raw English-ish word list.
- **David's actual prompt** (from settings.json, 7 custom words): `" claude, vs code, claude code, mcp, app, vercel, prod"` — ~15–18 BPE tokens. Notable: `"claude"` is a substring-duplicate of `"claude code"`; `"app"` and `"prod"` are common English words needing no decoder bias — and **`"app"` is literally one of the measured §38 silence-hallucination outputs**. Even this tiny prompt produced every failure class — important calibration: shortening alone won't fix it.

### 1.2 The decision tree — when decode #2..#6 fires (whole-file `TranscribeAsync`, engine 191-343)
1. **Decode #1** — prompted. Output → `RepetitionGuard.Scrub`.
2. **Decode #2 — RegurgitationRecovery**: flag on AND (scrub removed a regurgitation OR scrubbed text empty) → full unprompted re-decode, replaces primary. Then `NonSpeechAnnotation.Reduce`.
3. **Decode #3 — SilenceHallucinationGate §38**: text non-empty AND prompt active AND `rawRms < 0.004` → full unprompted witness; empty witness ⇒ no-speech, non-empty ⇒ keep prompted.
4. **Decode #4 — PhraseLoopGuard §42/§45**: `HasLoop` → full unprompted witness; prefer collapsed witness wholesale, else deterministic collapse.
5. **Decode #5 — SparseTranscriptGuard §43**: prompt active AND ≥10 s AND <4 chars/s → witness, adopted at ≥2× chars; **adoption updates `lastOutcome`** so the tail guard sees witness coverage.
6. **Decode #6 — TailCoverageGuard §39**: last segment ends ≥1.5 s early → decodes **only the tail slice** (cheap), containment-dedupe merge.

**Worst case: 6 decode invocations for one dictation** (5 full + 1 tail). Realistic worst chain for David: quiet long dictation → #1, #3, #5, #6.

**Chunk path**: decode (+ possible recovery decode), reduce; a loop/sparse chunk **throws `DegenerateDecode` → session fails → the entire whole-file tree runs from scratch** (all chunk text discarded). A failing streaming dictation costs N chunk decodes + the full whole-file cascade.

## 2. Latency audit — what the diagnostic.log actually shows

(Counts include `--bench` sweep pollution; treat as upper bounds on absolutes but reliable ratios.)

| Event | Count | Outcome split |
|---|---|---|
| Whole-file primaries (prompt=on) | 752 | 3 with chars=0 |
| Unprompted decodes | 152 | 43 paired recovery re-decodes; rest bench |
| **Silence-witness (§38)** | **138** | **121 "kept" (87.7% wasted) / 17 "no-speech"** |
| Tail guard (§39) | 56 | 27 RECOVERED / 29 unchanged (tail-only = cheap) |
| Phrase-loop whole-file / chunk | 16 / 1 | all → witness / fallback |
| Sparse whole-file / chunk | 6 / 3 | 5 adopted, 1 kept (excellent precision) / fallback |
| `source=wholefile` vs `source=stream` | 982 vs 159 | **86% of dictations end whole-file despite streaming** |
| Stream finish → null (silent final tail / failed) | 86 / 56 | |
| Stream finish → pieces | 115 | |
| Silent-classified chunk decoded **non-empty** → fallback | **74** | |
| Silent-classified chunk confirmed empty → skipped | **0** | |

### 2.1 Worst offender: the §38 silence witness — 88% of its decodes are pure waste
David's mic captures real speech at rawRms 0.0005–0.004 — exactly the `QuietRmsTrigger < 0.004` band. 121/138 witnesses confirmed real speech (log shows witnesses vouching for 208–309-char primaries — nobody hallucinates a 300-char essay from silence; the measured §38 hallucinations were all short stock phrases). **The trigger is missing a second dimension: transcript length** (§5-L1).

### 2.2 Streaming is structurally defeated on David's mic — and pays decodes for the privilege
`ChunkPlanner.IsSilent` uses an **absolute** floor (0.005) while David's speech peaks below it: **74/74 silent-classified chunks decoded non-empty** — the model *never once* confirmed a silent classification; every such cut cost a chunk decode then aborted streaming to whole-file. **86 sessions died at `Finish()`** on a "silent" final tail (his last clause). Note `ChunkPlanner.Plan` already computes a **relative** threshold (`peak * 0.1`) for choosing *where* to cut — only the `IsSilent` *classification* is absolute (§5-L3).

### 2.3 Witness decodes are identical but never shared
§38/§42/§43 each independently call `DecodeSamplesAsync(samples, factory, usePrompt: false)` on the **same full buffer** — and RegurgitationRecovery's `decode(false)` is the same call again. If two guards fire on one clip, the identical unprompted decode runs twice. A single memoized `Task<DecodeOutcome>` per `TranscribeAsync` invocation is a zero-behavior-change dedupe (§5-L2).

### 2.4 The flag-vs-prompt mismatch in RegurgitationRecovery
With an **empty custom-word list**, the primary decode is already unprompted, yet an empty result (every silent press) still triggers a second, *bit-identical* decode — the default experience for any fresh user with no custom words: every "No speech detected." costs 2× (§5-L4).

### 2.5 Concurrency
All 2nd–6th decodes run serially. Uniquely, the §38 trigger (`rawRms`) is known **before decode #1** — the witness could launch concurrently and be awaited only if needed. Cost is GPU contention on Vulkan — a measured experiment, not a free win (§5-L5).

## 3. Root-cause leverage: de-risking VocabularyPrompt itself

### 3.1 Prompt vs prefix — there is no prefix
`WithPrompt` maps to whisper.cpp `initial_prompt` (previous-context slot of the first window). whisper.cpp implements no OpenAI-style `prefix`; moot.

### 3.2 The propagation mechanism — the two-knob experiment
The prompt seeds window 1; cross-window conditioning propagates whatever degeneracy it induces. All three catastrophic failure classes occurred on **long** (multi-window) dictations. Candidate combo: `WithNoContext(true)` + `WithCarryInitialPrompt(true)` — per-window vocab biasing without cross-window feedback. *(Reconcile with Area 1 §4.1: the whisper.cpp source read shows `WithNoContext` does NOT stop within-call cross-window conditioning — the real in-call levers are `WithMaxLastTextTokens` and the temp ≥ 0.5 rungs. `WithCarryInitialPrompt` remains valid as the long-dictation vocab-accuracy lever.)* Cheap to A/B on the real-clip corpus via `--bench`: known-bad clips must still heal; no-harm sweep must stay byte-identical after post-processing.

### 3.3 Prompt content curation (cheap, surgical)
- **Dedupe subsumed entries**: `"claude"` adds nothing next to `"claude code"`; duplicates raise regurgitation propensity.
- **Exclude common dictionary words from the *prompt*** (keep them in post-processing): `"app"`, `"prod"` need no decoder bias — and `"app"` is a *measured* hallucination output. Users add such words for *casing* — casing belongs to the corrections channel anyway.
- **Format experiment**: the bare comma list is the most regurgitation-shaped format possible (it *is* a list; whisper recites lists on silence). A carrier form ("Vocabulary: X, Y, Z.") is a known community mitigation — worth one `--bench` A/B, not a blind change.
- **Enforce the token cap**: add a character budget (~380 chars ≈ 96 tokens) to `VocabularyPrompt.Text` so `MaxPromptTokens` isn't a dead constant on Windows.

## 4. Post-processing: precedence, coverage, cheap wins

### 4.1 Correction precedence (who actually wins)
Effective precedence, highest first: **built-in macOS dictionary (9 entries: jvoice/appkit/…) > user correction rules > user custom-word variants > DeveloperTerms > BiblicalTerms.** Quirk worth fixing: a user rule can never override the 9 built-ins (`"jvoice" → "J-Voice"` silently loses) — "user rules outrank everything" is the defensible contract; flipping the overlay order in `TextProcessor.ApplyCorrections` is a deliberate macOS divergence needing its test update. Application order within `ApplyCorrections` is longest-key-first (good).

### 4.2 PhoneticMatcher coverage & limits
- Only entries with **≥3 letters** participate — 2-letter custom words ("Go", "AI") never fuzzy-match.
- **Initial-sound guard**: a mishearing that changes the first sound is permanently uncorrectable ("veercell"→Vercel works; "hercel" doesn't). Deliberate anti-false-positive design; know the ceiling.
- DeveloperTerms/BiblicalTerms get **no** fuzzy matching (exact `\b…\b` only) — why the packs spell out every heard-form.

### 4.3 Cheap wins visible in TextProcessor
- `ApplyCorrections` runs ~230+ fresh `Regex.Replace` constructions per dictation — exceeds .NET's default `Regex.CacheSize` (15), so every pattern re-parses each time. A one-time compiled alternation per pack is a trivial cleanup — relevant mostly to the CPU flavor.
- `Format(Formal)` capitalizes only the first character of the whole transcript — no sentence-boundary capitalization after filler-removal seams. Low priority.
- `RemoveDisfluencies` will also delete the legitimate word "err" ("to err is human"). Edge case; note only.
- `RemoveWhisperHallucinations` is an exact-string blocklist — `"Thank you!"` (bang variant) isn't in it. The §38 witness is the real defense now; fine as-is.

### 4.4 A small correctness gap in guard wiring (engine 274-285 vs 296-310)
When **PhraseLoopGuard adopts the witness**, `lastOutcome` is *not* updated (unlike the sparse guard). TailCoverageGuard then evaluates the **prompted decode's** segment coverage against text from the **witness** — it can fire a tail decode for audio the witness already covered (wasted decode + theoretical double-append with rephrased-tail drift). Mirror the sparse guard's adoption line to close it.

## 5. Ranked improvements

### (a) Accuracy — fewer prompt-induced failures at the source
| # | Change | Where |
|---|---|---|
| A1 | **A/B `WithCarryInitialPrompt(true)` (+ context-cap per Area 1)** — give every window the vocab bias; stop degeneracy propagation via `WithMaxLastTextTokens(128)` | Engine builder via new `EngineTuning` fields + `--bench` flags |
| A2 | **Prompt curation**: dedupe subsumed entries; exclude common English words (stay in corrections/PhoneticMatcher) | `VocabularyPrompt.Text` |
| A3 | **Enforce the token budget** (~380-char cap) | `VocabularyPrompt.Text` |
| A4 | **Fix `lastOutcome` after phrase-loop witness adoption** | `WhisperNetTranscriptionEngine.cs:274-285` |
| A5 | **User rules outrank built-ins**: flip overlay order | `TextProcessor.ApplyCorrections` |
| A6 | **Prompt format experiment** (carrier sentence vs comma list) — measure | bench flag |
| A7 | Optional **beam search on GPU** | `EngineTuning` + builder |

### (b) Latency — fewer/cheaper redundant decodes
| # | Change | Evidence |
|---|---|---|
| L1 | **Length ceiling on the §38 trigger** (`ShouldVerify` also requires a short prompted transcript, ~60–80 chars calibrated on the 17-clip corpus) | 121/138 witnesses (88%) wasted, many on 200–309-char primaries |
| L2 | **Memoize the unprompted witness per `TranscribeAsync`** (shared by §38/§42/§43, seeded by RegurgitationRecovery) | Pure dedupe, zero behavior change |
| L3 | **Fix the streaming silent-misclassification** — make `ChunkPlanner.IsSilent` relative (peak-scaled, like `Plan`'s cut threshold already is) or use the spectral classifier | 74/74 wrong classifications; 86 dead sessions on "silent" final tails |
| L4 | **Gate RegurgitationRecovery on the actual prompt, not the flag** | empty-vocab users pay 2× on every silent press |
| L5 | **Concurrent §38 witness** (rawRms known pre-decode) — measure GPU contention first | behind an `EngineTuning` flag |
| L6 | Leave the tail guard alone — 27/56 fires recovered real speech; tail-only decode is cheap | — |

**Suggested ordering**: L1 + L2 + A4 are small, test-lockable, remove most measured waste. A1 is the highest-leverage *experiment*. L3 is the structural fix that makes streaming worth its decodes. A5/A2/A3 cheap hygiene; A6/A7/L5 measured experiments.

Cross-cutting: `JVoice.Core` constants are macOS-verbatim and test-locked by doctrine — L3/A5 are deliberate divergences needing matching test updates in the same commit; L1/L2/A4 touch Windows-only code with no parity constraint.

### §8. External research

# Whisper Custom-Vocabulary Accuracy & Prompt-Induced Failure Avoidance (external evidence)

## 1. Initial-prompt engineering (the 224-token window)

- **Prompts steer style, not instructions** ([OpenAI Whisper prompting guide](https://developers.openai.com/cookbook/examples/whisper_prompting_guide)): Whisper follows the *style* of the prompt (fake "previous transcript context"), ignores commands.
- **Hard 224-token cap, last-tokens-win** — later tokens exert more influence; put the highest-value custom words **at the end** ([arXiv 2602.18966](https://arxiv.org/html/2602.18966v1), [whisper #1824](https://github.com/openai/whisper/discussions/1824)).
- **Format: natural sentence ≥ glossary list.** The cookbook's worked example found a fluent sentence embedding the terms more effective than "Glossary: …". A **dictation-framing preamble helps** ("Voice dictation transcript.") — steers away from YouTube-subtitle-style completions ("Thanks for watching") on trailing silence ([OpenWhispr #462](https://github.com/OpenWhispr/openwhispr/issues/462)). A bare comma list is the exact shape that gets regurgitated.
- **Prompt length ↔ loops:** regurgitation/loop failure well corroborated ([whisper #1992](https://github.com/openai/whisper/discussions/1992)); no published quantitative loop-rate-vs-length curve — the app's own 30-clip calibration (#43) is ahead of the public literature. Practitioner optimum: short-to-medium prompt of words the user actually says, not a max-length dump. Worth stealing cheaply from arXiv 2602.18966's "JargonPromptDecider": only include vocab entries phonetically plausible for the audio at hand.

## 2. whisper.cpp specifics

- **`prompt`** = fake previous-window context (soft biasing); **`prefix`** = forced literal output start — wrong tool for vocab. whisper.cpp has only `initial_prompt`/`prompt_tokens` — the right semantics; nothing to change.
- **Window carry:** initial prompt conditions only the *first* 30 s window by default; after that it's displaced by rolling transcript ([whisper #1189](https://github.com/openai/whisper/discussions/1189)). `carry_initial_prompt` re-prepends per window (whisper.cpp ≥1.8.1; Whisper.net `WithCarryInitialPrompt(bool)`). Relevance: >30 s whole-file decodes currently lose vocab biasing after the first window; conversely carrying raises loop exposure — a real tuning axis for the #43 sparse-middle failure (the swallowed middle is where the prompt has been displaced). Note reported correctness issue in the whisper.cpp implementation (PR #2684).
- **`no_context` / `n_max_text_ctx`:** `no_context=true` is the most-cited repetition mitigation; capping `WithMaxLastTextTokens` to ~64 is the community middle ground ([#1017](https://github.com/ggml-org/whisper.cpp/issues/1017), [#2286](https://github.com/ggml-org/whisper.cpp/discussions/2286)).
- **faster-whisper's `hotwords`** is the cleanest articulation of what a dictation app wants (vocab injected per-window without competing with rolling context); `carry_initial_prompt` + short `max_last_text_tokens` approximates it in whisper.cpp.
- **[Issue #3744](https://github.com/ggml-org/whisper.cpp/issues/3744)'s proposed `retry_on_repeat` is literally the PhraseLoopGuard witness-re-decode doctrine proposed upstream** — validation, and a watch item (native implementation could let the app delete code).
- [Issue #2445](https://github.com/ggml-org/whisper.cpp/issues/2445): state bleed across runs without model reload — relevant if processor reuse is adopted.
- GBNF grammars: command-mode tool, flaky, not exposed by Whisper.net — not a fit.

## 3. Alternatives to prompt biasing

### 3a. Post-ASR phonetic correction (strengthening PhoneticMatcher) — best gain-per-effort
- **Phoneme-space matching beats grapheme fuzzy matching**: G2P both the ASR output and custom-word list, match with **weighted phoneme edit distance** (substitutions weighted below insertions/deletions; costs graded by phonetic feature similarity) ([arXiv 1203.5255](https://arxiv.org/pdf/1203.5255)).
- **Context-conditioned correction probability** (only replace when surrounding words make the term plausible) measurably cuts false corrections ([arXiv 2102.11480](https://arxiv.org/pdf/2102.11480)).
- **Microsoft's Contextual Spelling Correction** ([arXiv 2203.00888](https://arxiv.org/pdf/2203.00888)) and **PMF-CEC** ([arXiv 2506.11064](https://arxiv.org/pdf/2506.11064) — rewrites only detected error spans, the anti-overcorrection property dictation needs) are the canonical designs.
- Feasibility: pure-C# G2P is very doable (CMUdict + rules for en; Romanian orthography is near-phonemic — rule G2P easy). Slots into `PhoneticMatcher`, zero decode-time cost. **Highest-leverage path to eventually *shrinking* the decoder prompt** (fewer words in prompt → fewer prompt-induced failures → fewer witness re-decodes).

### 3b. Logit-level contextual biasing — highest ceiling, worst feasibility
- Trie-guided logit boosts: ~50% relative WER reduction on biasing words ([arXiv 2407.10303](https://arxiv.org/pdf/2407.10303)); TCPGen for Whisper ([arXiv 2306.01942](https://arxiv.org/pdf/2306.01942)). But whisper.cpp exposes **no logit-bias API** and Whisper.net no logits callback — would mean forking whisper.cpp's decoder loop. Long-term watch, not a 2026 move.

### 3c. LLM post-correction (local) — not recommended now
- Real field with big numbers on *hard* audio (up to 53.9% WER reduction — [HyPoradise, arXiv 2309.15701](https://arxiv.org/abs/2309.15701)), **but** zero-shot LLM correction is "generally ineffective, often *increasing* error rates due to over-correction" on already-accurate transcripts — large-v3-turbo dictation from a cooperative speaker is exactly the danger zone. Plus VRAM contention with whisper on the 3060 Ti and added latency per paste.

### 3d. Fine-tuning-free adapters — skip (all need training passes or decoder-loop access).

## 4. Hallucination suppression / detection

- **The "confidence is inverted" finding is corroborated**: "Hallucinated outputs are often generated with high confidence … while no_speech_prob remains unexpectedly low" ([arXiv 2606.07473](https://arxiv.org/html/2606.07473)); classifiers on avg_logprob/compression-ratio/no_speech_prob achieved **F1 = 23.6%** — essentially useless ([arXiv 2606.23060](https://arxiv.org/pdf/2606.23060)). The prompt-vs-no-prompt agreement discriminator (#38) is legitimately better than anything scalar the decoder emits.
- Scale/shape corroboration: ~1% of clips carry whole hallucinated sentences, concentrated around **longer pauses and silences** (Koenecke et al., FAccT 2024, [arXiv 2402.08021](https://arxiv.org/abs/2402.08021)). Only 3 of 20 decoder attention heads cause >75% of non-speech hallucination (Calm-Whisper: −80% hallucination via fine-tuning those heads — only relevant if GGML weights get published, [arXiv 2505.12969](https://arxiv.org/pdf/2505.12969)).
- **Better signals available:** token-level timestamps + per-token probabilities (`WithTokenTimestamps`, `WithProbabilities`) → *token-timestamp density per segment* — hallucinated segments show abnormal token spacing; would let guards flag *which segment* is fabricated instead of witnessing the whole clip.
- **Silence-compression trick**: don't *remove* pauses, *shorten* them — gaps >~1.5 s trimmed to 0.3–0.5 s keeps punctuation-relevant pause cues while denying the decoder the long-silence windows that trigger hallucination and loops (consistent with the FAccT pause finding). Attacks the *cause* in pause-heavy Bible-study dictations. VAD false positives are their own risk — keep the whole-file fallback.

## 5. large-v3-turbo vs large-v3

- Turbo = large-v3 pruned 32→4 decoder layers; across languages performs ≈ large-v2, not large-v3; **no translation training** — ⚠ the "Translate to English" feature (#32) rides on a model documented as degraded for translation; worth an in-app caveat or auto-suggesting large-v3 when translate is on.
- **Romanian:** no published turbo-vs-v3 numbers; expect "≈large-v2" — real but modest regression vs large-v3. Only an own A/B (`--bench --lang ro`) settles it.
- **Hallucination propensity:** turbo "emits repetition loops and phrases memorized from subtitle-heavy training data on silence and trailing pauses"; with only 4 decoder layers it has less depth to self-correct a forming loop — consistent with the app's loop incidents clustering on this model. Mitigation: decode params + silence handling; or offer large-v3 (non-turbo) as an "accuracy" option for loop-prone long dictations.

## Ranked recommendations

1. **Move most vocabulary from the decoder prompt to post-ASR phonetic correction** (G2P + weighted phoneme edit distance + context gating), keeping only genuinely unspellable terms in a *short* prompt. Directly shrinks the prompt-induced failure surface the four guards exist for. Pure C#.
2. **Restructure the prompt**: short natural dictation preamble + terms embedded in transcript-like prose, highest-value terms last, well under 224 tokens; drop bare comma-list format.
3. **Silence compression pre-pass** using the bundled Silero VAD: shrink >1.5 s pauses to ~0.4 s before decode (whisper still decides speech-vs-not — doctrine-compatible). Attacks the pause-triggered loop/sparse/hallucination cause.
4. **Decode-param hardening for long decodes**: `WithEntropyThreshold(2.6–2.8)`, `WithMaxLastTextTokens(64)`, verify beam search + fallback ladder active; consider `WithCarryInitialPrompt(true)` A/B for >30 s clips (fixes vocab loss after the first window; watch loop rate).
5. **Segment-level fabrication signals**: token timestamps + per-token probabilities for per-segment density evidence; never scalar-confidence thresholds.
6. **Watch, don't build**: whisper.cpp #3744 (`retry_on_repeat` going native), logit biasing if ever exposed, Calm-Whisper GGML weights.
7. **Not recommended now**: local-LLM post-correction; TCPGen/prefix-tree decoder integration; GBNF grammars.

Cross-cutting: for the translate feature and future Romanian dictation, benchmark large-v3 (non-turbo) — turbo's known weak spots (translation untrained, mid-resource languages ≈ large-v2, higher loop propensity) are exactly those two paths.

---

## §9. Executive synthesis

All eight agents converged on a small set of high-confidence conclusions. Where agents disagreed, the disagreement is stated and resolved below.

### The single biggest measured finding (two agents independently, from the real diagnostic.log)

**Streaming is structurally defeated on David's mic, and it's the dominant latency AND robustness problem.** `ChunkPlanner.IsSilent`'s absolute `SilenceRmsFloor = 0.005` classifies his quiet speech (window-RMS 0.0005–0.004) as silence. In the current log era: **the silent classification was never once correct** (74/74 "silent" chunks decoded non-empty → fallback; 0 confirmed-empty skips), ~92% of all streaming fallbacks trace to this floor, and only 38% of ≥15 s dictations actually stream. The cost: a whole-file fallback adds ~1.3 s at 60 s+ (p90 ~2.3 s) versus ~0.4 s duration-independent stop→paste when streaming works. **Fix candidates, in order:** (1) wire in the already-built, already-calibrated-on-this-mic spectral classifier `HighPassSilence.IsSilent` (currently metrics-only/unwired); (2) make `IsSilent` relative (peak-scaled — `Plan`'s cut threshold already is); (3) Silero VAD (bundled in Whisper.net 1.9.1, threshold ~0.25–0.35, generous padding) as the cut/classification signal. All three are doctrine-safe: classification only routes *trust*; the model still decides no-speech; misclassification the other way just costs a fallback, never text. Expected: stream success 38% → ~80-90%, long-dictation stop→paste ~1.7 s → ~0.45 s.

### Top measured latency wastes (quick, low-risk)

1. **§38 silence-witness waste:** 121 of 138 witness decodes (88%) confirmed real speech — a full doubled decode to vouch for 200–300-char transcripts that were obviously not hallucinations. Add a transcript-length ceiling to `SilenceHallucinationGate.ShouldVerify` (calibrate ~60–80 chars on the 17-clip corpus).
2. **Identical witness decodes never shared:** §38/§42/§43/RegurgitationRecovery each independently run the *same* unprompted whole-file decode. Memoize one `Task<DecodeOutcome>` per `TranscribeAsync` call — zero behavior change.
3. **`Finish()` decodes the backlog before checking the tail verdict** — on the 59-86 silent-final-tail sessions every backlog decode was thrown away. Plan first, decode later.
4. **Double 80 ms paste settle delay** (coordinator + `Paster.Paste`) — collapse to one; ~80 ms off every paste.
5. **True prewarm:** `PrewarmAsync` loads weights but never decodes; the first dictation pays Vulkan pipeline/state lazy-init. One ~0.5-1 s dummy decode at startup/engine-rebuild (industry-standard among dictation apps). Related: an in-app GPU warm submission at *record start* beats the NVIDIA idle-clock ramp.
6. **Language/translate toggles reload the full 574 MB model for nothing** (factory depends only on model+flash) and **leak the old factory** (no dispose in `SwapEngine`). Make them per-decode settings; add `IDisposable`.

### Accuracy levers, ranked by evidence × cost

1. **Model file swap experiment (zero code):** the shipped default is **q5_0** — the *most degraded* common quantization — on a GPU where f16 (~1.6 GB) fits trivially. Bench q8_0 (~874 MB) and f16 turbo vs q5_0 on the real corpus: likely small accuracy gain, plausibly *faster* on Vulkan (GPU dequant overhead is real), and marginally fewer degenerate decodes.
2. **`WithEntropyThreshold(2.8)`:** makes whisper heal *short-period* loops itself at a fallback rung (which also auto-drops the prompt at temp ≥ 0.5). Cannot catch long-period loops (entropy is over the last 32 tokens — same structural blindness #45 fixed), so PhraseLoopGuard stays. Best ratio of all decode-param changes.
3. **`WithMaxLastTextTokens(128)`:** bounds cross-window degeneracy propagation; the vocab prompt still fits (128, not 64 — the budget truncates from the front).
4. **Prompt hygiene (cheap, surgical):** dedupe subsumed entries ("claude" ⊂ "claude code"); exclude common English words from the *prompt* (`"app"` is a measured hallucination output — such words belong in the corrections channel, which handles casing anyway); enforce the dead `MaxPromptTokens=96` cap (~380-char budget); A/B a carrier-sentence format (the bare comma list is the most regurgitation-shaped format possible). External best practice: highest-value terms *last* (224-token window keeps the tail), short natural preamble ("Voice dictation transcript.").
5. **`WithCarryInitialPrompt(true)` A/B:** today the vocab prompt washes out after ~1 window — custom words spoken after ~30 s get *no* biasing. Carry fixes that but multiplies the loop-exposure surface; judged strictly on the failure-clip regression set.
6. **Beam search (beam 5) A/B:** reference-implementation parity (whisper.cpp CLI defaults to beam 5; the library default the app inherits is greedy). Agents disagreed on cost — external research says ~free on modern NVIDIA (batched KV), the source-level read says decode 2-5× slower at t=0. Resolution: it's a measured experiment; adopt only if <~30% end-to-end and fewer guard firings. Note beam changes output texture → guard thresholds calibrated on greedy may need recalibration.
7. **Long-term, highest-leverage architectural direction:** move most vocabulary from the decoder prompt to **post-ASR phonetic correction** (G2P + weighted phoneme edit distance + context gating — the Microsoft CSC / PMF-CEC design), keeping only genuinely unspellable terms in a short prompt. Pure C#, zero decode-time cost, directly shrinks the failure surface all five guards defend. Romanian's near-phonemic orthography makes a rule G2P easy.
8. **Fix the `lastOutcome` gap after PhraseLoopGuard witness adoption** (real bug: TailCoverageGuard evaluates the prompted decode's coverage against witness text) and consider flipping correction precedence so user rules outrank the 9 built-ins.

### Conflicts resolved

- **`WithNoContext()`:** recommended by the external agent, but the source-level read of whisper.cpp 1.8.5 shows it's a **no-op** for this app (fresh processor per decode; within-call cross-window conditioning is unconditional — no `no_context` check on the `prompt_past` refill). The real in-call levers are `WithMaxLastTextTokens` and the temp ≥ 0.5 fallback rungs. **Verdict: skip `WithNoContext`.**
- **Silero VAD:** external agents rank it #1-3; the decode-params source agent flags it as philosophically adjacent to the retired RMS gate. **Verdict: use it (or the spectral classifier) only for chunk-cut placement and silent-*classification* — never as a rejector — and validate on the quiet-mic captures first.** The simplest doctrine-safe fix (spectral `HighPassSilence`) doesn't need VAD at all.
- **CUDA:** documented 10-30% faster than Vulkan, but requires the CUDA toolkit or ~600-800 MB of redistributed DLLs for decodes that already finish in <1 s. **Verdict: keep Vulkan shipped; CUDA stays a dev-box bench experiment.**

### Do-NOT list (evidence-backed dead ends, preserved)

No digital gain / RMS rejection gates (§21/§22 doctrine, re-confirmed). No denoising (DeepFilterNet measurably *hurts* whisper ~20% WER) or high-pass in the transcription path. No `suppress_nst`/annotation suppression (NonSpeechAnnotation depends on the annotations; suppression makes silence hallucinate *words*). No `WithSingleSegment` (blinds TailCoverageGuard) or `max_len` caps. No `WithLanguageDetection` (returns no transcript!). No scalar-confidence thresholds ever (inverted-confidence finding corroborated by literature: F1 = 23.6% for logprob-based detectors). `audio_ctx` stays rejected. No LLM post-correction (over-corrects low-WER dictation). distil/Moonshine/Kyutai models disqualified (no Romanian). faster-whisper/server-mode/ONNX-DirectML not viable for this stack. Single-file publish still broken (csproj `cpu` flavor's `PublishSingleFile=true` is a latent trap).

### Watch list

- **Parakeet-tdt-0.6b-v3**: 25 languages **incl. Romanian**, CC-BY, dramatically faster than whisper even on CPU, and **structurally immune to the entire prompt-induced loop/sparse failure class** (no autoregressive decoder prompt). Available today via sherpa-onnx C#; whisper.cpp v1.9.0 added native Parakeet support, so a future Whisper.net bump may deliver it in the existing engine. The trade: no decoder-prompt vocab biasing (post-processing carries it — which #7 above moves toward anyway).
- Whisper.net is current (1.9.1, June 2026, bundles whisper.cpp 1.8.5); next release likely brings whisper.cpp ≥1.9.0.
- whisper.cpp issue #3744's proposed `retry_on_repeat` is the PhraseLoopGuard witness doctrine going native — could eventually delete app code.
- Turbo has **no translation training** — the "Translate to English" feature rides a documented-degraded path; consider suggesting large-v3 when translate is on. For Romanian accuracy, bench large-v3 vs turbo when it matters.

### Suggested execution order (if/when acted on)

1. Streaming silent-classification fix (spectral/relative) — biggest measured win, both speed and robustness.
2. §38 length ceiling + witness memoization + phrase-loop `lastOutcome` fix — small, test-lockable, removes most decode waste.
3. Prewarm dummy decode + single paste settle delay + `Finish()` reorder — pure latency polish.
4. Model-file bench (q8_0/f16 vs q5_0) — zero code, possible free accuracy.
5. `EngineTuning`/`--bench` extension, then entropy 2.8 → max-text-ctx 128 → beam 5 → carry-prompt, each gated on the failure-clip + no-harm corpus.
6. Prompt curation + token-cap enforcement; longer-term, the phonetic-correction (G2P) vocabulary channel.
7. Engine lifecycle: no reload on language/translate toggles + factory dispose.
