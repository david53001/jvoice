# HANDOFF — state as of 2026-06-09 (custom-words hallucination + dropped-speech fix)

Audience: the next Claude session (opened in this directory) and David. Read `CLAUDE.md` first for the rules; this file is the mutable status.

## 2026-06-09 session — Custom-words hallucination loop + dropped speech on long dictations — FULL FIX (UNCOMMITTED, autonomous)

Two reports, one root cause. (1) Mid-dictation the transcript stopped following speech and recited Custom Words in a comma-separated loop — `"…from a country that is sub agents, claude, li-fraumeni, vs code, sub agents, …"`, words never said; a first-pass `RepetitionGuard` (strip the trailing loop) helped. (2) David then: longer dictations still (a) scatter custom words where not spoken, and (b) **cut out big spans** ("I talk for two minutes and it cuts out a big chunk"). Deep multi-agent investigation found the shared root cause + two new mechanisms.

**Root cause (all symptoms):** the vocabulary `promptTokens` (built by `VocabularyPrompt.text` as a comma-separated list) is the decoder's `<|startofprev|>` attractor, re-applied identically to every 30 s window — in low-confidence regions (pauses/breaths/window boundaries) the most probable continuation is *more of the list*, so the model recites the prompt instead of transcribing. WhisperKit 1.0.0 can't suppress it: `noSpeechProb` hardcoded `0` (`TextDecoder.swift:802`, silence gate dead); the only repetition defense (compression-ratio fallback) emits the degenerate window anyway — never drops it (`TranscribeTask.swift:407-410`); `temperatureFallbackCount = 2` gives 3 attempts; `withoutTimestamps=true` on streaming chunks removes even the TimestampRulesFilter loop guard. The first-pass guard only stripped *trailing* loops.

**New mechanisms found:**
1. **Silent data loss** — `StreamingTranscriptionSession.pollOnce`/`finish` advanced `consumedSamples` past any chunk that decoded EMPTY. Round-1's guard stripping a regurgitating chunk to "" made it empty → up to 25 s of real speech deleted. (I had traded garbage for drops.) The whole-file fallback never fired because a partly-streamed session still returns a non-nil lossy transcript.
2. **Long-cycle guard miss** — the guard's tail gate required a token repeated ≥3× in a 12-token window; David's real 4-phrase vocab is a 6-token cycle → only 2 repeats in the window → the loop was NOT flagged at all (found by a 120-case fuzz).

**The fix (keep accuracy, kill the failure modes):**
- **Decoder prompt STAYS ON** (default `useVocabularyPrompt: true`) — proven necessary: prompt-off degrades "Li-Fraumeni"→"Leif or Meany", "VS Code"→"Versus Code" (PhoneticMatcher can't recover those). New `Services/RegurgitationRecovery.swift`: decode WITH prompt; if `RepetitionGuard.scrub` reports `removedRegurgitation` OR empty, **re-decode the same audio WITHOUT the prompt** and use that. Clean re-decode runs only on the rare bad decode → accuracy + latency kept in the common case; recovers the speech a loop replaced AND eliminates scattered insertions. Wired into both `transcribe` (whole-file) and `transcribeChunkSamples` (streaming) via `decodeRecoveringFromRegurgitation`.
- **Streaming never silently drops** — a non-silent chunk that decodes "" now FAILS the session → `finish()` nil → lossless whole-file fallback (`pollOnce` + `finish` drain).
- **Guard long-cycle fix** — tail gate is density-only; the ≥3-repeat requirement moved to the final validation over the *whole* loop run (sees every cycle). `RepetitionGuard.scrub` now also returns `removedRegurgitation` (the re-decode trigger).
- **`TextProcessor.stripDecoderArtifacts`** removes leaked `[BLANK_AUDIO]`/`[MUSIC]` sentinels (found via the harness on pause-heavy clips), wired into both decode paths.

**Verification (all green; David asked to "verify hundreds of scenarios" — this is the evidence base):**
- `scripts/run-logic-tests.sh` — **120-case loop fuzz** (every generated coherent-prefix + vocab-loop stripped) + 120 single-mention controls untouched + scrub-flag + `stripDecoderArtifacts` cases. EXECUTES locally.
- `scripts/verify-streaming.sh` (NEW) — compiles + EXECUTES the streaming actor and `RegurgitationRecovery` with mock decoders: empty non-silent chunk → fallback (no silent drop), silent region dropped safely, recovery re-decodes WITHOUT prompt on regurgitation/empty, clean decode kept (one decode, vocab accuracy preserved).
- `scripts/verify-transcription.py` (NEW) — 34 real `say` clips (varied length 18 s–2.5 min, pause density, 2 voices, vocab spoken/not) × whole-file + streaming, scoring word-retention (drops) + spurious-vocab (hallucination) + vocab accuracy. **base: 65/68, `spur=0` on ALL 68 runs** (the 3 fails are base-model whole-file mis-transcription — streaming passed those same clips 0.95–0.98). **large (David's model): 68/68 ALL PASS, `spur=0` everywhere, retention ≥0.96** (the clips that failed on base all pass on Large). Spoken-vocab clip: "VS Code/Claude/JVoice/Li-Fraumeni/sub agents" all spelled correctly (prompt accuracy intact).
- `swift build` (debug+release), `swift test` (compile) green. New tests: `RegurgitationRecoveryTests.swift` (4), streaming data-loss cases (3), `RepetitionGuard` scrub + long-cycle + artifact cases.

Files: NEW `Services/{RepetitionGuard,RegurgitationRecovery}.swift`, `scripts/{verify-streaming.sh,verify-transcription.py}`, `Tests/JVoiceTests/{RepetitionGuard,RegurgitationRecovery}Tests.swift`; CHANGED `Services/{TranscriptionManager,StreamingTranscriptionSession,TextProcessor,BenchRunner}.swift`, `Tests/JVoiceTests/StreamingTranscriptionSessionTests.swift`, `scripts/run-logic-tests.sh`. Bench gained `--no-prompt` to A/B the decoder prompt. Limitation: the *live* regurgitation is stochastic and not reproducible on clean `say` TTS, so its recovery is proven deterministically (scrub fuzz + RegurgitationRecovery exec tests) rather than by a captured live failure — real-mic dogfood of a long pause-heavy dictation with Custom Words is the final human check. Deferred probability-reducers (NOT done — need `--bench`, trade the tuned latency): soften the comma-list prompt, raise `temperatureFallbackCount`, populate `suppressTokens`.

## 2026-06-09 session — Large → quantized turbo build (UNCOMMITTED, autonomous at David's instruction)

Goal: "make Large transcribe faster, safely (ro+en only)." One shipped change, bench-gated.

**Large now uses Argmax's turbo-optimized quantized build `openai_whisper-large-v3-v20240930_turbo_632MB`** (was the full ~1.5 GB `…-v20240930`). Same 4-layer-decoder architecture, so accuracy holds, but ~624 MB download and **~21–36% faster warm decode**. Implemented via "Option Y": `WhisperModelOption.largeTurbo`'s `rawValue` STAYS `"large-v3-v20240930"` (stable Codable identity → no new migration shim, persisted settings untouched); only `whisperKitModelName`/`whisperKitFolderName` were repointed at the `_turbo_632MB` folder. UI unchanged ("Large"); Settings picker guidance updated 1.6 GB → ~630 MB.

Bench evidence (this machine, warm transcribe, full → turbo_632MB): en-short 1.01→0.65 s · en-long (31 s) 2.47→1.77 s · ro-short 1.13→0.77 s · ro-long (36 s) 3.24→2.56 s · en-vocab 0.87→0.56 s. Accuracy: English words byte-identical; **Romanian equal-or-BETTER** — the turbo build restores diacritics the full build dropped ("intenționat / dacă / aceleași / frumoasă"). **Vocab path re-verified**: "JVoice" still spelled correctly → the `SuppressBlankFilter` promptTokens shim survives the quantization. No multi-window truncation on the 31 s/36 s clips. The bench harness gained `--lang en|ro` (Romanian couldn't be tested before — it silently defaulted to English).

Caveat: accuracy was verified on macOS `say` TTS clips (voice "Ioana" for ro), not David's real voice — strong evidence, but the real-voice Romanian verdict is still his call. Revert = repoint the two strings in `WhisperModelOption` back to `large-v3-v20240930`. Also: this is a NEW ~624 MB first-use download + ANE compile; the full 1.5 GB build, the 606 MB `_626MB` test build (benched, equivalent but ~same warm speed as full — turbo won), and the old 3.0 GB `large-v3_turbo` are all still cached in `~/Documents/huggingface/…` — reclaim manually. Files touched: `Models/WhisperModelOption.swift` (+ its test), `VoiceCoordinator` guidance string, `Services/BenchRunner.swift` (`--lang`). Verified: `swift build` (debug+release), `swift test` (compile), `scripts/run-logic-tests.sh` all green.

## 2026-06-07 session — Large-model speedup (ALL UNCOMMITTED, autonomous session at David's instruction)

Goal: "make the Large model faster, same accuracy." Spec: `docs/superpowers/specs/2026-06-07-large-model-speedup-design.md`; plan: `docs/superpowers/plans/2026-06-07-large-model-speedup.md`. Two shipped changes, both bench-gated:

1. **Model swap — "Large" now = OpenAI's real large-v3-turbo** (`openai_whisper-large-v3-v20240930`, 4-layer decoder). The old `large-v3_turbo` was WhisperKit's *compression* of original large-v3 — still a 32-layer decoder; decode dominated latency. rawValue changed; legacy `"large-v3_turbo"` settings decode to `.largeTurbo` via a shim (downgrade caveat: an OLD binary reading the NEW rawValue falls back to .tiny — irrelevant pre-release). Measured (47.7 s long clip / 8.6 s short clip, warm, this machine): short **2.56→1.16 s**, long **11.6→3.68 s**, vocab **1.81→0.94 s**; transcripts byte-identical; no multi-window truncation; warm load 1.1→0.49 s.
2. **Streaming-while-recording**: a read-only overlay (`WavTail` growing-WAV parser tolerating Apple's FLLR padding + stale size fields; pure `ChunkPlanner` silence-cut policy, 15 s min / 25 s cap chunks; `StreamingTranscriptionSession` actor) polls the WAV AVAudioRecorder is still writing and transcribes completed chunks during recording. On hotkey release only the tail decodes. **Any failure → `finish()` returns nil → the unchanged whole-file path runs (worst case = pre-session behavior; capture pipeline untouched).** Bench (`--bench --stream`, simulates a live recording at 10× growth): streamed transcript **byte-identical** to whole-file; post-stop wait **~1.2 s** (vs 3.68 s whole-file, vs 11.6 s old model). Verified E2E without a mic; sessions cancel/finish on every termination path (incl. quit-mid-recording, rapid hotkey toggling via a recordingGeneration guard).

**Critical discovery (do not lose this):** vocabulary `promptTokens` initially produced EMPTY transcripts on the new model. Root cause: large-v3-v20240930 confidently predicts `<|endoftext|>` as the FIRST content token under a `<|startofprev|>` prompt; the empty decode passes every WhisperKit quality gate (no fallback; `noSpeechProb` is hardcoded 0 in 1.0.0). Reference Whisper prevents exactly this with SuppressBlank at sample_begin; WhisperKit 1.0.0 ships that filter off-by-default AND wired to the wrong index. Fix: `WhisperKitTranscriptionEngine` installs its own correctly-indexed `SuppressBlankFilter` (sampleBegin = promptTokenCount + 5; multilingual-model assumption documented) whenever a prompt is used — shared between file and chunk paths via `applyVocabularyBiasing`. Post-fix, vocab biasing is BETTER than before: raw output now spells "JVoice" directly (old model needed the phonetic post-pass). **After ANY WhisperKit version bump, re-run `--bench --vocab` and `--bench --stream` — the fix reaches into WhisperKit's filter wiring (createLogitsFilters appends built-ins to `textDecoder.logitsFilters`) and a 1.x change could silently undo it.** Candidate upstream fixes are documented on `installPromptCompatibilityFilter`.

New files: `Services/{WavTail,ChunkPlanner,StreamingTranscriptionSession}.swift`, tests for all three (+prefill-count and finish-idempotence tests) — suite now ~120 swift-testing cases; `run-logic-tests.sh` extended (WavTail+ChunkPlanner assertions execute locally). `--bench` gained `--stream`. Process: spec → plan → subagent implementation with two-stage reviews per task → 7-angle code review; all confirmed findings fixed (finish-once contract, start-after-finish guard, async cancel join, generation guard, decode-options dedup).

**First app use after this change**: the app downloads ~1.5 GB (`large-v3-v20240930`) and pays a fresh ANE compile (CLI bench's cache does NOT carry over — per-bundle-ID). The `.preparingModel` HUD covers it. The old `openai_whisper-large-v3_turbo` folder (~2 GB) is still in `~/Documents/huggingface/...` — reclaim manually if wanted.

**Dogfood checklist (can't be verified without a human + mic):** long dictation (>30 s) with natural pauses → text should appear ~1 s after release; dictation with Bluetooth headphones connected (A2DP redirect + streaming reader together); cancel/quit mid-recording; rapid hotkey double-press; custom words on Large. Known acceptable behaviors: switching model mid-recording silently degrades that dictation to the whole-file path; a stop landing mid-first-chunk-decode falls back to whole-file (both by design).

## Where this came from

David surveyed his ~14 projects looking for a new helpful-then-monetizable project. Decision: ship his existing work **free first** to build a portfolio and user base. JVoice (this repo) is app #1, extracted from `../MacOSUtils`. **BetterScreenshot (`../BetterScreenshot`) is planned as app #2.**

## Decisions locked

- Free-first releases; monetize later (VoiceInk model: free source, paid prebuilt binary, one-time price, never subscription).
- $0 budget: no Apple Dev account → unsigned ad-hoc-signed DMG via GitHub Releases; no Homebrew (banned for unsigned, Sept 2026); GitHub Pages for the site.
- License: GPL-3.0 (LICENSE committed). All deps verified GPL-compatible (MIT/Apache-2.0).
- Demo media: Remotion, must match the real product UI exactly.
- **Publishing is ON HOLD** — David explicitly said don't post to GitHub yet. gh CLI authenticated (david53001 active, da97d). No remotes configured anywhere.

## 2026-06-06 evening session — what changed (ALL UNCOMMITTED, by David's instruction)

The whole session's work sits in the working tree, deliberately not committed. Spec plans for everything live in `docs/superpowers/plans/2026-06-06-*.md`; the full scan report is `CODEBASE-SCAN.md`.

1. **App identity — "J"**: `Resources/AppIcon.icns` regenerated as a black-squircle "J" (was a leftover copy of MacOSUtils' "M") via new `scripts/generate-icon.swift`. Menu bar status item is now a bold "J" **template image** (native light/dark adaptation; the forced-darkAqua hack is gone), red `mic.fill` while recording, cyan `waveform` while transcribing. Installed to /Applications via `install.sh` and running.
2. **Vocabulary v2** (the "custom words don't work" fix): custom words now (a) bias Whisper's decoder via `promptTokens` (`VocabularyPrompt` + engine cache; survives engine swaps), and (b) get a phonetic fuzzy post-pass (`PhoneticMatcher`: simplified-Metaphone key + Levenshtein windows) catching "jay voice"/"g voice" → "JVoice". Also fixed: Very Casual no longer destroys correction casing (deliberate policy change — `veryCasualPreservesDictionaryCorrectionCasing` test documents it). Verified end-to-end on real TTS audio with `--bench`: without vocab Whisper writes "JVoy"; with vocab the output is "JVoice".
3. **Large-model speed**: duration-gated `withoutTimestamps` (≤25 s clips, provably single-window → ~10% faster: 1.34s→1.21s measured on large-v3_turbo). **Unconditional `withoutTimestamps` is a trap**: WhisperKit 1.0.0 truncates multi-window transcripts without timestamps (measured; documented in the plan + code comment). Long clips keep the timestamped path (~41 s for 53 s audio — inherent to WhisperKit 1.0.0; streaming is the long-term fix). New hidden `--bench` CLI (`JVoice --bench <wav> [--model …] [--vocab …]`) is how to measure.
4. **Demo video — native Apple UI**: all Apple chrome now uses real OS artifacts extracted by `docs/demo-video/scripts/extract-assets.swift` (real app icons via NSWorkspace, real SF Symbols, real NSCursor arrow, real "Mac Purple" wallpaper). Notes window rebuilt with correct dark chrome (the wrong yellow title bar is gone). Outputs re-rendered: `docs/assets/demo.{mp4,gif}` + `../Portfolio/assets/jvoice-demo.gif` (gif 1.38 MB). DESIGN-TOKENS.md updated (incl. post-rebuild deltas).
5. **Improvements from an 8-agent codebase scan** (see `CODEBASE-SCAN.md`): CI fixed (macos-15 + Xcode 16 — **the old Xcode 15.4 pin silently skipped 78/96 swift-testing cases**; the workflow now asserts ≥90 cases executed); `Package.resolved` un-gitignored (commit it!); temp-WAV privacy leaks fixed (quit-while-recording, recorder-failure teardown, launch sweep); vocabulary re-pushed on pending-engine promotion; `WhisperModelLocator` now also requires MelSpectrogram weights + config.json (NOT tokenizer.json — it lives outside the model folder); HUD `.preparingModel` state ("first use can take a few minutes") shown when dictation waits on a model load; model-picker guidance caption in Settings; PhoneticMatcher multi-token exact early-out.
6. **New tests**: PhoneticMatcher (13), VocabularyPrompt (3), MenuBarIcon (2), locator config case, TextProcessor vocabulary/casing cases — ~100 swift-testing cases total. Local verification = `scripts/run-logic-tests.sh` (actually executes; `swift test` still compiles-only on this CLT machine).

## Verification (all green at session end)

- `swift build` / `swift build -c release` / `swift test` (compile) → Build complete!
- `scripts/run-logic-tests.sh` → all pass.
- `.build/release/JVoice --bench /tmp/jv-vocab.wav --model base --vocab "JVoice"` → processed output contains "JVoice".
- `cd docs/demo-video && npx tsc --noEmit` → clean. `open ../assets/demo.mp4` → 20 s demo with native UI.
- `/Applications/JVoice.app` installed (stable self-signed identity), running, J in menu bar.

## Deferred / open questions

- **Commit the session's work** — David must review the diff and commit (nothing was committed per his instruction). `Package.resolved` should be included.
- **Release workflow not built** (tag → build → sign → DMG → Release) — still the next engineering task.
- **Dogfooding now possible** — the app is installed; David should dictate daily and watch for PhoneticMatcher false positives (tightening lever: the length gate in `PhoneticMatcher.matches`).
- Scan leftovers (deliberate non-changes): dead convenience API across services (prune before open-sourcing?), `ToneMode`/`WhisperModelChoice` bridge-enum collapse, `DictationSession` extraction, settings single-source-of-truth, push-to-talk, transcript history, sound feedback, CONTRIBUTING/BUILDING.md. All catalogued in `CODEBASE-SCAN.md`.
- License confirmation (GPL-3.0 vs MIT) — soft-confirmed GPL by silence.
- David has not yet watched the rebuilt demo video — verdict pending.

## Pick up here

1. David reviews + commits the working tree. 2. Dogfood. 3. Build the release-DMG workflow. Do NOT publish anything without his explicit instruction.
