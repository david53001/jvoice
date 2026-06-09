# Audit 04 — Transcription Pipeline (read-only, deep)

**Scope:** `TranscriptionManager` / `WhisperModelLocator`, `VocabularyPrompt`, `RepetitionGuard`,
`RegurgitationRecovery`, `StreamingTranscriptionSession`, `WavTail`, `ChunkPlanner`, `TextProcessor`,
`PhoneticMatcher`, `WhisperModelOption`, `TranscriptionLanguage`, plus the matching tests and the two
local verification scripts (`run-logic-tests.sh`, `verify-streaming.sh`).

**Summary.** The pipeline is in good shape and the delicate accuracy layer (prompt → RepetitionGuard →
RegurgitationRecovery → duration-gated timestamps) is internally consistent and well-tested. The
streaming "never silently drop audio" invariant holds end-to-end: every non-silent chunk that decodes
empty or errors fails the session and triggers the lossless whole-file fallback, and the `finish()`
drain loop is provably terminating (every `.cut` strictly shrinks the tail; `plan` never cuts at 0).
`WavTail` correctly handles FLLR padding, odd-aligned chunk padding, larger `fmt ` sizes, stale/zero size
fields, trailing odd bytes, vanished files, and past-EOF offsets. `ChunkPlanner` forced cuts are
correctly bounded. The one genuinely incorrect *output* I found is a **double/triple substitution bug in
`TextProcessor.applyCorrections`** that mangles certain custom words (`.NET` → `..NET`/`...NET`). The
remaining findings are smaller robustness/edge issues. Most output-affecting fixes are Tier 2 because
they live in the correction path; the pure deterministic ones (`stripDecoderArtifacts` regex,
`isSilent([])` documentation, NaN/inf handling) are Tier-1 script-verifiable.

| Severity | Count | IDs |
|---|---|---|
| Critical | 0 | — |
| High | 1 | TRX-01 |
| Medium | 4 | TRX-02, TRX-03, TRX-04, TRX-05 |
| Low | 4 | TRX-06, TRX-07, TRX-08, TRX-09 |
| **Total** | **9** | |

Tier split: T1 (pure-logic, script-verifiable, no accuracy change): TRX-06, TRX-08, TRX-09 — and the
*test-only* additions in TRX-02/TRX-05. T2 (touches correction/accuracy/decode behavior → propose only):
TRX-01, TRX-03, TRX-04, TRX-07. (TRX-01 is mechanically a deterministic string bug, but it lives in the
correction pipeline and changes user-visible corrected text, so it is flagged T2 and should be validated
with `verify-transcription.py` in addition to a new logic-test case.)

---

### [TRX-01] `applyCorrections` double-applies overlapping spoken variants → corrupted custom words (`.NET` → `..NET`)
- **Severity:** High
- **Tier:** T2 (correction-path / accuracy — propose only; mechanically deterministic so also gets a new logic-test)
- **Location:** `Sources/JVoice/Services/TextProcessor.swift:44-51` (`applyCorrections` loop) + `:85-105` (`spokenVariants`) + `:194-199` (`phrasePattern`)
- **What:** `applyCorrections` iterates every (needle → replacement) pair sequentially over the *same*
  growing `result` string. When a custom word produces several spoken variants that overlap *after* one
  substitution, a later variant's `\b…\b` pattern matches a substring of the already-inserted
  replacement and substitutes again.
- **Evidence:** `buildUserDictionary(from: [".NET"])` yields variants including `net`→`.NET` and
  ` net`→`.NET` (and `.net`→`.NET`). On input `"use dot net daily"`:
  - first matching variant: `net` → `.NET` ⇒ `"use dot .NET daily"`
  - second variant (`\bnet\b`, case-insensitive) matches the `NET` inside `.NET` (a `\b` sits between
    `.` and `N`) ⇒ `"use dot ..NET daily"`.
  Verified directly:
  ```
  applyCorrections("use dot net daily", extraDictionary: buildUserDictionary([".NET"])) == "use dot ..NET daily"
  ```
  End-to-end it is worse — the phonetic pass adds a third application:
  ```
  TextProcessor.process("use dot net daily", mode:.casual, extraDictionary: dict, vocabulary:[".NET"]) == "use dot ...NET daily"
  ```
- **Impact:** Any custom word whose canonical spelling contains a substring equal to one of its own
  shorter spoken variants gets corrupted. `.NET` is the clearest real-world trigger; the class is
  general (leading/trailing punctuation glued to a letter-run that is itself a variant). Built-in dict
  entries happen to be idempotent (`whisperkit`→`WhisperKit` re-matches but replacement == match), so the
  blast radius is *user vocabulary with punctuation*, exactly the kind of word the feature exists to fix.
- **Fix (sketch):** Make `applyCorrections` non-re-entrant. Two clean options:
  1. Single combined alternation regex (longest-first) over the original text in one pass, so no
     replacement is ever re-scanned; or
  2. Build a protected-span set as you substitute and skip matches that fall inside an already-inserted
     replacement.
  Minimal-change option: in `spokenVariants`, drop variants that are a substring of the canonical
  `word` (so `.NET` never registers the bare `net` variant). This is the smallest surgical fix and
  removes the self-overlap class, at the cost of not auto-correcting someone saying "net" → ".NET"
  (acceptable; "net" is far too ambiguous to expand anyway).
- **Verification:** Add a logic-test case to `run-logic-tests.sh` asserting
  `applyCorrections("use dot net daily", extraDictionary: buildUserDictionary([".NET"])) == "use dot .NET daily"`
  and a control that built-in dict idempotence still holds. Re-run `verify-transcription.py` with a
  punctuated custom word to confirm no spurious-vocab regression.

---

### [TRX-02] `WavTail.parseHeader` rejects a valid WAV when `data` precedes `fmt ` (chunk-order assumption)
- **Severity:** Medium
- **Tier:** T2 (changes what audio can stream; only manifests on non-AVAudioRecorder WAVs) — test addition is T1
- **Location:** `Sources/JVoice/Services/WavTail.swift:33-57`
- **What:** The parser only validates format when it *reaches* the `data` chunk, requiring `fmt ` to have
  been seen first. If a (legal) RIFF file places `data` before `fmt `, parsing returns `nil`.
- **Evidence:** Probe with `data` chunk emitted before `fmt ` → `parseHeader(...) == nil`.
- **Impact:** Low in practice — AVAudioRecorder (the only producer the streaming path consumes) always
  writes `fmt ` before `data`, and a `nil` here merely refuses to stream and falls back to whole-file
  transcription (no data loss, no crash). It is a correctness *gap* (a valid file is refused), not a
  user-facing defect today. Worth recording because the file's own doc-comment frames it as a general
  RIFF tail parser.
- **Fix:** Either (a) document explicitly that `fmt`-before-`data` ordering is assumed (matches the only
  producer), or (b) defer the format check: record the `data` payload offset, keep walking for `fmt `,
  and validate at end. Given the simplicity-first rule and the single known producer, (a) is the
  proportionate choice unless a non-AVAudioRecorder source is ever added.
- **Verification:** Add a `run-logic-tests.sh` assertion documenting the current behavior
  (`parseHeader(dataBeforeFmt) == nil`) so a future "improvement" can't silently regress whichever
  decision is made.

---

### [TRX-03] `RegurgitationRecovery` uses the prompt-free re-decode unconditionally, even if it is also degenerate or empty
- **Severity:** Medium
- **Tier:** T2 (decode/accuracy policy — propose only)
- **Location:** `Sources/JVoice/Services/RegurgitationRecovery.swift:23-30`
- **What:** On a regurgitated/empty prompted decode, the policy returns
  `RepetitionGuard.scrub(decode(false)).text` *unconditionally*. If the prompt-free re-decode is itself a
  generic Whisper loop (RepetitionGuard scrubs it to `""`) or comes back empty, the recovered value is
  `""`.
- **Evidence:** Code path: `return RepetitionGuard.scrub(try await decode(false), …).text`. There is no
  comparison against the prompted result and no guard for an empty recovery.
- **Impact:** For the **whole-file path** this is safe-ish: an empty final transcript surfaces
  "No speech detected." But for the **streaming chunk path** (`transcribeChunkSamples`), an empty return
  is interpreted by the session as a chunk failure → whole-file fallback re-runs the *whole* recording
  with the prompt again and can hit the same empty/regurgitation on the same span, producing an empty
  final result on audio that *did* contain speech. The common case (real speech recovers) is fine; this
  is the rare double-failure tail. Not a regression vs. today's non-streaming behavior, but the policy
  could be slightly more defensive.
- **Fix (sketch):** If the prompt-free re-decode is empty, fall back to the prompted result *before*
  scrub (the loop-contaminated text still contains the real prefix) rather than returning `""`:
  ```swift
  let clean = RepetitionGuard.scrub(try await decode(false), vocabulary: vocabulary).text
  return clean.isEmpty ? primary.text : clean   // never discard speech for a worse empty re-decode
  ```
  Note `primary.text` is the *scrubbed* prompted text (loop already removed), so this keeps the coherent
  prefix instead of nothing. Validate carefully — it slightly changes the empty-recovery contract the
  streaming session relies on (an empty chunk currently *intentionally* fails the session).
- **Verification:** Extend `verify-streaming.sh` recovery scenarios with a mock where both `decode(true)`
  and `decode(false)` return empty/loop, and assert the chosen output; pair with `verify-transcription.py`.

---

### [TRX-04] `ChunkPlanner` relative-silence threshold can mis-cut after a loud transient
- **Severity:** Medium
- **Tier:** T2 (affects where chunks are cut → decode quality)
- **Location:** `Sources/JVoice/Services/ChunkPlanner.swift:44-53`
- **What:** `threshold = max(silenceRMSFloor, peak * relativeSilenceFraction)`. A single very loud
  transient inside the search window (door slam, clap, mic bump) inflates `peak`, so the relative
  threshold (10% of peak) can rise above the level of *normal speech*, classifying ordinary speech
  windows as "pauses" and cutting there — potentially mid-word.
- **Evidence:** With a 0.99-amplitude transient amid 0.3-amplitude speech, 0.3 is ~30% of peak — still
  above the 10% threshold, so the probe correctly returned `.wait` (no mis-cut). The risk materializes
  when the transient is ≥10× the speech amplitude (e.g. clipping clap at 0.99 vs whispered 0.05 speech →
  5% of peak < 10% threshold → speech treated as silence). The current absolute floor protects the
  *isSilent* drop decision but not the *cut-point selection*.
- **Impact:** Edge case; produces a sub-optimal (mid-word) cut, not data loss — the cut still streams
  both halves and the worst case is a slightly degraded chunk transcription that the whole-file fallback
  does not even see (streaming only falls back on empty/error). Low real-world frequency.
- **Fix:** Consider clamping `peak` used for the relative threshold to a robust statistic (e.g. a high
  percentile rather than the max), or cap the relative threshold at a fraction that can't exceed a
  speech-plausible RMS. This is a tuning change — only with `verify-transcription.py` + real clips.
- **Verification:** New `verify-transcription.py` clip variant with an injected loud transient; assert
  word-retention unchanged.

---

### [TRX-05] No coverage / explicit handling for NaN or ±inf samples reaching RMS / scaling
- **Severity:** Medium
- **Tier:** T1 for the guard+test (pure logic); behavior is currently "propagate"
- **Location:** `Sources/JVoice/Services/ChunkPlanner.swift:79-95` (`windowRMS`), `Sources/JVoice/Services/WavTail.swift:60-62` (`floatSamples`)
- **What:** Samples enter as `Int16`, so NaN/inf cannot originate from `WavTail` (Int16→Float is always
  finite, range `[-1.0, 0.99997]`). However `ChunkPlanner.plan` / `isSilent` are *public* and accept any
  `[Int16]`, and `windowRMS` does `Double(samples[i]) / 32768.0` then `sqrt(sum/n)` — fine for Int16, but
  the *sample-array* streaming entry point (`transcribe(audioArray:)`) and the `[Float]` chunk passed to
  WhisperKit are never sanity-checked. If a future caller (or a corrupted decode) produced non-finite
  floats they would reach the model.
- **Evidence:** `floatSamples` is closed over Int16 (safe). `ChunkPlanner` only sees Int16 (safe). The
  gap is purely that the `[Float]` boundary into WhisperKit has no `isFinite` assertion; today nothing
  generates non-finite values, so this is a *defensive-coverage* note, not a live bug.
- **Impact:** None today (Int16 source guarantees finiteness). Flagged so the invariant is explicit.
- **Fix:** None required given the Int16 source. If desired, a one-line `assert(samples.allSatisfy(\.isFinite))`
  in DEBUG at the `transcribeChunkSamples` boundary documents the contract at zero release cost.
- **Verification:** A `run-logic-tests.sh` assertion that `windowRMS` of an all-`Int16.min`/`Int16.max`
  buffer is finite and ≤ 1.0 documents the bound.

---

### [TRX-06] `stripDecoderArtifacts` removes legitimate single-/multi-letter bracketed tokens (`[A]`, `[I]`, `[X]`)
- **Severity:** Low
- **Tier:** T1 (pure-logic, script-verifiable, no model interaction)
- **Location:** `Sources/JVoice/Services/TextProcessor.swift:148-153` (regex `#"\[[A-Z_][A-Z_ ]*\]"#`)
- **What:** The artifact regex matches any bracketed run of uppercase letters/underscores/spaces,
  including single letters and short tokens a user could plausibly dictate.
- **Evidence:**
  ```
  stripDecoderArtifacts("see figure [A] here")   == "see figure here"
  stripDecoderArtifacts("reference [I] and [II]") == "reference and"
  stripDecoderArtifacts("the answer is [X]")      == "the answer is"
  ```
- **Impact:** Low frequency in dictation, but a real false positive: option labels, citation markers, and
  Roman numerals get silently deleted. The comment claims "the all-caps/underscore bracket shape never
  occurs in natural dictation" — `[A]`/`[I]`/`[X]` are counterexamples.
- **Fix (sketch):** Require the bracket content to look like a real decoder sentinel — e.g. length ≥ 2
  AND contain an underscore OR be a known word from a small allow-list
  (`BLANK_AUDIO|BLANK_TEXT|MUSIC|APPLAUSE|NOISE|SILENCE|…`). Tightening to
  `#"\[[A-Z][A-Z_ ]*[A-Z_]\][ ]*"#` plus an underscore/keyword requirement removes the single-letter
  case while still catching `[BLANK_AUDIO]`, `[MUSIC]`, `[APPLAUSE]`. (Note: `[MUSIC]` has no underscore,
  so a keyword allow-list is the cleaner discriminator than "must contain `_`".)
- **Verification:** Add `run-logic-tests.sh` assertions: `[A]`/`[I]`/`[X]` preserved, `[BLANK_AUDIO]`/
  `[MUSIC]`/`[APPLAUSE]`/`[NOISE_1]` still stripped.

---

### [TRX-07] `WhisperModelLocator.completeModelFolder` doesn't validate the turbo build's *physical* folder vs. weight presence beyond three components
- **Severity:** Low
- **Tier:** T2 (model-load behavior)
- **Location:** `Sources/JVoice/Services/TranscriptionManager.swift:89-108`
- **What:** The completeness check verifies `MelSpectrogram`, `AudioEncoder`, `TextDecoder` weight files
  plus `config.json`. Some WhisperKit builds also ship a `TextDecoderContextPrefill.mlmodelc` (the
  context-prefill component referenced in the `installPromptCompatibilityFilter` comment). If a turbo
  snapshot includes a prefill component that is itself half-downloaded while the three checked components
  are complete, `completeModelFolder` returns the path with `download:false` and WhisperKit may again
  hang loading a weightless sub-model — the exact failure mode this guard exists to prevent.
- **Evidence:** `requiredWeightPaths` is a fixed 4-entry list; it does not enumerate all `.mlmodelc`
  dirs present in the folder. The risk is conditional on which components the specific 632 MB turbo build
  ships (not verifiable here without the download).
- **Impact:** Low and conditional — only on a *partially* interrupted download where the unchecked
  component is the incomplete one. The common interrupted-download case (any of the big three missing)
  is caught.
- **Fix:** Generalize the check: for every `*.mlmodelc` directory present in the folder, require its
  `weights/weight.bin`. That makes the guard robust to whatever component set a future build ships,
  matching the stated intent ("incomplete download → re-download").
- **Verification:** Extend `WhisperModelLocatorTests` (CI) with a fixture folder containing a complete
  big-three set but a weightless extra `.mlmodelc`, asserting `completeModelFolder == nil`.

---

### [TRX-08] `ChunkPlanner.plan` returns `.wait` for an exactly-`minSamples` non-silent buffer with no candidate window (documentation gap)
- **Severity:** Low
- **Tier:** T1 (pure-logic, script-verifiable)
- **Location:** `Sources/JVoice/Services/ChunkPlanner.swift:40-58`
- **What:** When `unconsumed.count == minSamples`, `searchEnd == minSamples`, and the candidate filter
  (`start >= minSamples && start + window <= searchEnd`) admits *no* window, so `quietest == nil` and
  the function returns `.wait` (it waits until `maxSamples`). This is correct and termination-safe, but
  it is an implicit boundary worth a regression test, because a future tweak to the candidate filter or
  `searchEnd` could turn it into a `.cut(at: small)` that breaks the `finish()` drain-loop's "every cut
  strictly shrinks the tail" guarantee.
- **Evidence:** Probe: 15.0 s (= exactly minSamples) of audio → `.wait` (iters=0 in a drain loop).
- **Impact:** None today; this is a latent-invariant note. The drain loop's termination correctness
  depends on `plan` never returning `.cut(at: 0)` and on `.cut` strictly advancing — currently true
  because the smallest possible `at` is `minSamples + window/2 > 0`.
- **Fix:** No code change. Add a documenting test.
- **Verification:** `run-logic-tests.sh` assertions: `plan(exactly-minSamples tone) == .wait`; and a
  drain-loop fuzz asserting every `.cut`'s `at` is in `(0, count]` and strictly shrinks the tail across
  pure-silence, all-speech, and mixed inputs (guards TRX-08's invariant directly).

---

### [TRX-09] `samples(from:)` returns `[]` (not `nil`) for an offset past EOF — masks a would-be over-consume
- **Severity:** Low
- **Tier:** T1 (pure-logic, script-verifiable)
- **Location:** `Sources/JVoice/Services/WavTail.swift:100-120`
- **What:** Seeking past EOF clamps and `readToEnd()` returns empty → the method returns `[]` ("no new
  data yet") rather than `nil` ("file unreadable"). If `consumedSamples` ever exceeded the true sample
  count (it shouldn't under current flow, since `atSample` is always bounded by available samples), the
  session would silently spin returning `.wait` instead of failing into the lossless fallback.
- **Evidence:** Probe: `samples(from: 1_000_000_000) == []` and `samples(from: pastEOF) == []`.
- **Impact:** None today (`consumedSamples` only advances by realized `atSample`). Latent-invariant note:
  the empty-vs-nil distinction is load-bearing for the data-loss guarantee, so an over-consume bug
  introduced elsewhere would be masked here rather than caught.
- **Fix:** No change required; optionally assert `sampleOffset <= currentSampleCount` in DEBUG. Mainly a
  documentation/test item.
- **Verification:** `run-logic-tests.sh`/`WavTailTests`: assert `samples(from: hugeOffset) == []` and that
  a normal `consumedSamples` advance never exceeds the produced sample count.

---

## Proposed new test cases

**For `scripts/run-logic-tests.sh` (pure logic, executes locally):**

1. **TRX-01 regression** — `applyCorrections("use dot net daily", extraDictionary: buildUserDictionary([".NET"]))` must equal `"use dot .NET daily"` (no `..NET`/`...NET`). Add controls: built-in dict idempotence (`applyCorrections("use whisperkit now") == "use WhisperKit now"`), and a punctuated user word like `"C#"` not corrupting `"i code in c sharp"`.
2. **TRX-06** — `stripDecoderArtifacts` preserves `[A]`, `[I]`, `[II]`, `[X]`; still strips `[BLANK_AUDIO]`, `[MUSIC]`, `[APPLAUSE]`, `[NOISE_1]`. (Currently fails for the single-letter cases — encodes the bug, then the fix.)
3. **TRX-08 invariant fuzz** — for pure-silence, all-speech, and mixed `[Int16]` buffers of varied lengths, run the `finish()`-style drain (`while case .cut`) and assert every `at ∈ (0, count]` and `Array(tail[at...]).count < tail.count` (strict shrink) — directly guards drain-loop termination.
4. **TRX-08 boundary** — `plan(tone(seconds: 15.0))` (exactly minSamples) `== .wait`.
5. **TRX-02 documentation** — `parseHeader(dataBeforeFmt) == nil` (locks whichever decision is taken).
6. **TRX-05 bound** — `windowRMS` of all-`Int16.min` and all-`Int16.max` buffers yields finite RMS `≤ 1.0`.
7. **TRX-09** — `samples(from: hugeOffset) == []` (already partially covered by `readerStreamsGrowingFile` for the at-EOF case; add the past-EOF case).
8. **RepetitionGuard Unicode** — `core("Café,") == "café"`, and a diacritic vocabulary entry (`["café"]`) loop strips correctly (confirms `CharacterSet.alphanumerics` keeps Unicode letters — currently passes; lock it in).

**For `scripts/verify-streaming.sh` (executes the real actor + recovery policy locally):**

9. **TRX-03 double-empty** — `RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: …)` where both `decode(true)` and `decode(false)` return empty/loop: assert the chosen output matches the agreed policy (today `""`; after the proposed fix, the scrubbed prompted prefix). Pin the streaming-session consequence too: a chunk whose both decodes are empty must still fail the session (nil) so the whole-file fallback runs.
10. **Streaming silent-then-speech ordering** — a WAV of `[silence, speech, silence, speech]` segments: assert the two speech pieces appear in order and no silent span is transcribed (extends scenario 3 to multiple alternations, guarding the `consumedSamples += atSample` advance on silent drops).
11. **Backlog drain in `finish()`** — a recording grown faster than the poll cadence can consume (large file, slow mock decode) so `finish()` must drain ≥2 backlog chunks; assert total samples transcribed exactly once and pieces ordered (extends scenario 4 with a multi-chunk backlog).

**For `scripts/verify-transcription.py` (model-backed, CI / on-demand):**

12. A custom word with internal punctuation (`.NET`, `Node.js`) spoken in a sentence — assert it is rendered exactly once, correctly (catches TRX-01 end-to-end through the phonetic pass).
13. A clip with an injected loud transient amid normal speech — assert word-retention unchanged (TRX-04).
