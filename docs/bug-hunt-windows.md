# Windows Port — Autonomous Bug-Hunt Ledger

**Purpose:** tracking doc for the autonomous `/loop` bug-hunt of the JVoice **Windows** port
(`windows/` .NET solution). Each loop iteration re-reads this file, picks the next unaudited
component, hunts for bugs/edge cases in the machine-verifiable layers, fixes any real bug at the
root, adds a regression test, and records the result here. **This file is the memory of the loop —
never start from a blank slate; never redo a `DONE` row.**

> **Scope reminder:** an autonomous/headless session **cannot** dogfood the live GUI / mic / paste /
> visual paths — those need a human at the desktop (`docs/launch/windows-dogfood-checklist.md`). This
> hunt targets only what a machine can verify: the **pure brain** (`JVoice.Core`, fidelity vs the
> read-only Swift reference under `Sources/JVoice/` + fuzzing), the **engine** (adversarial WAVs via
> `whisper-smoke` / `--bench`), and the **headless-verifiable platform** code (persistence corruption,
> orphan sweep, `hotkey-probe`, struct/marshalling review).

---

## Baseline (must hold at the start AND end of every iteration)

- `dotnet build windows/JVoice.sln -c Release` → **0 errors** (2 benign CS4014 warnings on
  `VoiceCoordinator.cs:267` are expected — not a finding).
- `dotnet test windows/JVoice.Tests/JVoice.Tests.csproj` → **Passed! Failed: 0** (started at **122**;
  now **247** after the TextProcessor + PhoneticMatcher + VocabularyPrompt + RepetitionGuard +
  RegurgitationRecovery + WavTail + ChunkPlanner + StreamingTranscriptionSession audits). As the hunt
  adds regression tests this number only grows; it must never go down or go red.

---

## NOT bugs — documented intentional deviations (do NOT "fix" these)

Before flagging any C#↔Swift divergence as a bug, confirm it is **not** one of these deliberate
choices (sources: `docs/HANDOFF-WINDOWS.md` §7, `docs/superpowers/plans/2026-06-22-windows-port-00-overview.md` §6.3/§10):

- The two WhisperKit-1.0.0 workarounds are **deliberately dropped** — `SuppressBlankFilter` /
  `installPromptCompatibilityFilter`, and the single-window `withoutTimestamps` 25 s truncation trap.
  whisper.cpp doesn't have those bugs. Their **absence is correct**, not a missing port.
- `HudState` has a **new** `DownloadingModel` kind (macOS folded download into "preparing").
- Rebound hotkey is **session-only** — `SettingsState` has no hotkey field by design; reset to
  `HotkeyChord.Default` (Ctrl+Shift+Space) on relaunch is intended.
- Pure helpers (`HotkeyChord`, `SettingsStateJson`, `BluetoothDevicePolicy`, `StatsMath`,
  `CoordinatorDecisions`) live in `JVoice.Core` (not `JVoice.App.Platform`) so tests can reach them.
- `AppTimings.PasteRestoreDelayFailureMs = 50` exists in Core by design.
- One Phase-2 constructor-default deviation (behaviorally identical) noted in the Phase 2 plan.

---

## Coverage map — audit status per component

Legend: `[ ]` not started · `[~]` in progress · `[x]` audited (status line: date · #tests added · #bugs).
Each row: **C# under test** ← **Swift reference** / **Swift test** (the fidelity oracle).

### Tier 1 — pure brain (highest value; fully unit-testable on `JVoice.Core`)
- [x] **TextProcessor** — `JVoice.Core/Text/TextProcessor.cs` + `JVoice.Tests/TextProcessorTests.cs`
      ← `Sources/JVoice/Services/TextProcessor.swift` / `Tests/JVoiceTests/TextProcessorTests.swift`
      — 2026-06-23 · +46 tests · **1 bug** (#1 ExtractCorrections newline tokenization). Line-by-line
      fidelity confirmed for the whole file; ported every missing Swift vector (extractCorrections ×5,
      regex-template literal-escape ×3, disfluencies ×9, very-casual ×7, hallucinations, dictionary
      variants, phonetic-in-process) + empty/whitespace edges + a 400-case never-throw/idempotent fuzz.
- [x] **PhoneticMatcher** — `…/Text/PhoneticMatcher.cs` + `PhoneticMatcherTests.cs`
      ← `…/Services/PhoneticMatcher.swift` / `PhoneticMatcherTests.swift`
      — 2026-06-23 · +24 tests · **0 bugs**. Line-by-line fidelity confirmed (Metaphone digraph table,
      prefix rules, bounded Levenshtein DP + early-exit, smallest-window-first probing, initial-sound
      guard, maxWindow camelCase estimate). Ported every missing Swift vector (phoneticKey ×6,
      levenshtein ×3, the "whisper cat"→WhisperKit compound, all false-positive guards incl. the
      "JVoice is"→swallow regression, short-word ignore) + empty-text/idempotency edges + a 400-case
      Levenshtein symmetry/bounded invariant + a 400-case Correct/PhoneticKey never-throw fuzz.
- [x] **VocabularyPrompt** — `…/Text/VocabularyPrompt.cs` + `VocabularyPromptTests.cs`
      ← `…/Services/VocabularyPrompt.swift` / `VocabularyPromptTests.swift`
      — 2026-06-23 · +10 tests · **0 bugs**. Line-by-line fidelity confirmed (MaxWords=40,
      MaxPromptTokens=96, leading-space, `", "` join, empty→null). Verified C# `Trim()` and Swift
      `.whitespacesAndNewlines` resolve to the **same** char set (so trimming is identical). Added the
      precise Swift cap vector (word39 kept / word40 dropped / not ending word99), the 39/40/41 boundary,
      duplicate-not-deduped, order-preserved, comma-in-entry-not-escaped, tab/newline trim, + a 300-case
      never-throw/well-formed fuzz (null iff no non-blank entry, else starts with a single space).
- [x] **RepetitionGuard** — `…/Text/RepetitionGuard.cs` + `RepetitionGuardTests.cs`
      ← `…/Services/RepetitionGuard.swift` / `RepetitionGuardTests.swift` (incl. the 120-case fuzz)
      — 2026-06-23 · +13 tests · **1 bug** (#2 Core alphanumerics). Line-by-line fidelity confirmed
      (all 5 constants, the 3-step strip pipeline, IsDegenerate, the loopy() predicate, stopwords list
      verbatim, VocabularyCores camelCase split, trailing-sep trim). Added `InternalsVisibleTo` so Core
      internals are white-box testable; ported the reported-bug case, generic loop, whole-loop→empty,
      empty/whitespace, scrub flags, VocabularyCores parity + a 400-case never-throw/never-lengthen fuzz.
      NOTE: the Swift `vocabularyCoresSplitsSpokenParts` test asserts `contains("vs")`, but the Swift
      *algorithm* (faithfully ported) does NOT yield "vs" for "VS Code" (camelCase splits "VS"→V/S, each
      <2 chars; only whole "vscode" survives) — C# matches the algorithm; that lone Swift assertion is
      inconsistent with its own code (a non-aborting `#expect`). We lock the real behaviour + the
      lowercase "vs code"→"vs" contrast.
- [x] **RegurgitationRecovery** — `…/Text/RegurgitationRecovery.cs` + `RegurgitationRecoveryTests.cs`
      ← `…/Services/RegurgitationRecovery.swift` / `RegurgitationRecoveryTests.swift`
      — 2026-06-23 · +7 tests · **0 bugs**. Line-by-line fidelity confirmed: the guard is De Morgan-
      equivalent to Swift's (`guard A, B else return` ↔ `if (!A || !B) return`), `isEmpty`↔`Length==0`,
      decode is called with `useVocabularyPrompt` then `false`, and decode errors propagate (rethrows ↔
      async throw). Added edges: prompt-off result is still scrubbed, first call is prompted, recovery's
      second decode is prompt-free, recovery output is itself scrubbed, all-loop recovery → "" (no silent
      loop fallback), and decode-throws propagates on both the first and the recovery decode.
- [x] **WavTail / WavTailReader** — `…/Audio/WavTail.cs` + `WavTailTests.cs`
      ← `…/Services/WavTail.swift` / `WavTailTests.swift` (FLLR padding, stale size, growing WAV)
      — 2026-06-23 · +11 tests · **1 bug** (#3 chunk-size Int32 overflow → throw). Line-by-line fidelity
      confirmed (RIFF/WAVE gate, chunk-walk, fmt/data validation 16k/mono/16-bit, word-alignment, the
      [dataOffset,EOF) payload model, FloatSamples /32768, the reader's odd-trailing-byte + past-EOF
      handling). Added the high-bit/max-uint size regression, a 600-case ParseHeader never-throw fuzz,
      truncated/empty/data-before-fmt/odd-size-word-aligned header edges + reader odd-byte/past-EOF.
- [x] **ChunkPlanner** — `…/Audio/ChunkPlanner.cs` + `ChunkPlannerTests.cs`
      ← `…/Services/ChunkPlanner.swift` / `ChunkPlannerTests.swift` (silence-cut, min/max constants)
      — 2026-06-23 · +9 tests · **0 bugs**. Line-by-line fidelity confirmed (all 6 Config constants;
      minSamples/maxSamples/window int-truncation; the candidate filter; `min(by:)` first-minimum
      tie-break == the C# strict-`<` loop; silence-vs-forced cut branches; `windowRMS` partial-final
      window). Relaxed `WindowRms`/`WindowEnergy` to `internal` (matching Swift's testable access) to
      port the partial-window vector. Added empty→wait, continuous-speech→wait, cut-not-silent,
      forced-cut-range, all-silence→silent-cut, isSilent([]) , quiet-speech-not-silence + a 300-case
      Plan never-throw / cut-in-bounds fuzz.
- [x] **StreamingTranscriptionSession** — `…/Audio/StreamingTranscriptionSession.cs` + `StreamingSessionTests.cs`
      ← `…/Services/StreamingTranscriptionSession.swift` / `StreamingTranscriptionSessionTests.swift`
      (the data-loss guarantee: empty non-silent chunk → fallback, NEVER a silent drop; finish-once; cancel-join)
      — 2026-06-23 · +5 tests · **0 bugs**. Line-by-line fidelity confirmed: the Start guard, the
      finish-once gate, the join-before-read pattern (C# `await _pollTask` after `_cts.Cancel()` gives
      the same happens-before as Swift's actor + `await pollTask?.value`), the drain loop (terminates —
      every cut shrinks tail), consumed-samples advancement (no gap/overlap), empty-non-silent→fail,
      silent→drop, cancelled-mid-decode→don't-consume, transcriber-throw→fail. Ported the Swift
      fast-config vectors (in-order chunks+tail with **sum == total, no loss/dup**; transcriber-throws;
      one-empty-chunk-anywhere→fallback; silent-region-dropped; vanished-file→null). Verified non-flaky
      (3× clean full runs).
- [ ] **SettingsState (+migration)** — `…/Models/SettingsState.cs` + `SettingsStateTests.cs`
      ← `…/Models/SettingsState.swift` / `SettingsStateMigrationTests.swift`
- [ ] **SettingsStateJson** — `…/Models/SettingsStateJson.cs` + `SettingsStoreJsonTests.cs`
      ← `…/Services/SettingsStore.swift` / `SettingsStoreCorruptionTests.swift` (forward-version refusal, per-field fallback)
- [ ] **WhisperModelOption (+GGML map)** — `…/Models/WhisperModelOption.cs` + `ModelTests.cs`
      ← `…/Models/WhisperModelOption.swift` / `WhisperModelOptionTests.swift`
- [ ] **HudState** — `…/Models/HudState.cs` ← `…/Models/HUDState.swift` (+ `DownloadingModel` is new)
- [ ] **HotkeyChord** — `…/Models/HotkeyChord.cs` + `HotkeyChordTests.cs` (Windows-only; parse/format/Default)
- [ ] **StatsMath** — `…/StatsMath.cs` + `StatsMathTests.cs` ← WPM math in `…/Services/StatsStore.swift`
      (edge cases: 0 seconds, 0 words, overflow)
- [ ] **CoordinatorDecisions** — `…/CoordinatorDecisions.cs` + `CoordinatorDecisionsTests.cs`
      ← decision logic in `…/VoiceCoordinator.swift` (target-window resolution, HUD→tray map, reset-delay map)
- [ ] **BluetoothDevicePolicy** — `…/Audio/BluetoothDevicePolicy.cs` + `BluetoothDevicePolicyTests.cs`
      ← `…/Services/AudioInputRouter.swift` / `AudioInputRouterTests.swift` (pure non-BT pick policy)
- [ ] **FileBackedTranscriptionEngine** — `…/Transcription/FileBackedTranscriptionEngine.cs` + `FileBackedEngineTests.cs`
      ← `FileBackedTranscriptionEngine` in `…/Services/TranscriptionManager.swift`
- [ ] **Swift-test parity sweep** — enumerate EVERY case in each `Tests/JVoiceTests/*.swift` brain test
      and confirm a C# equivalent assertion exists. Any Swift vector with no C# counterpart = a coverage
      gap → add the C# test; if it fails, that's a port-fidelity bug → fix `JVoice.Core` to match Swift.

### Tier 2 — engine + streaming on real audio (machine-verifiable via bench/smoke; needs Tiny model)
- [ ] **WhisperNetTranscriptionEngine — adversarial WAVs** — `JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`.
      Run crafted 16 kHz/mono/16-bit WAVs through `whisper-smoke` and `JVoice.exe --bench` (+`--stream`):
      empty/near-empty, pure silence, < 1 s, very long (>120 s), full-scale clipping, DC offset, all-noise,
      and a non-16 kHz file (expect a clean rejection, not a crash). Invariants: never crashes, never a
      silent drop (streaming falls back to whole-file), correct exit codes (64/65/66/70/1/0).
- [ ] **WhisperModelStore** — `JVoice.App/Whisper/WhisperModelStore.cs`. Verify size+SHA gate, atomic
      `.part`→final rename, no re-download when present, no `.part` leftovers, corrupt-file re-fetch.
- [ ] **Bench/smoke CLI** — arg parsing edge cases (missing args, bad flags, `--vocab` quoting, `--lang`,
      `--no-prompt`, unknown model) → documented exit codes, never an unhandled exception.

### Tier 3 — headless-verifiable platform (review + throwaway-console harnesses; NO GUI/mic/paste E2E)
- [ ] **NAudioRecorder** — `JVoice.App/Platform/NAudioRecorder.cs`. Orphan-WAV sweep correctness,
      `BufferedWaveProvider.ReadFully=false` (no infinite flush loop), `IsUsableRecording` thresholds,
      growing-WAV header contract (16000/1/2) readable by `WavTailReader`. (Verify with a small console
      that drives the recorder logic where a mic isn't required; review the parts that need a device.)
- [ ] **SettingsStore / StatsStore / LastTranscriptStore** — `JVoice.App/Platform/*Store.cs`. Corruption→
      backup+reset, forward-version refusal, UTF-8 round-trip, debounced-write coalescing, concurrent-write safety.
- [ ] **Paster** — `JVoice.App/Platform/Paster.cs`. Review the `INPUT`/`InputUnion` struct (sizeof==40 on
      x64), `FocusTarget` already-foreground early-return, clipboard save/restore (300 ms / 50 ms-failure).
      Add a unit test for any pure logic (outcome mapping); E2E paste needs the dogfood checklist.
- [ ] **GlobalHotkey** — `JVoice.App/Platform/GlobalHotkey.cs` via `windows/tools/hotkey-probe`
      (chord-match, 150 ms debounce, watchdog re-arm, recovery modes). Drive its `chord`/`watchdog`/`recovery` paths.
- [ ] **AudioInputRouter / ForegroundWindowTracker / LaunchAtLogin / SingleInstance / PermissionError /
      SettingsUris** — `JVoice.App/Platform/*.cs`. Review for races/leaks; verify registry round-trips
      **revert cleanly** (never leave `HKCU\…\Run\JVoice` set), cross-process mutex actually blocks.

---

## Bugs found & fixed
*(append; newest last. Format: `#N [component] symptom → root cause → fix → regression test → commit`)*

**#1 [TextProcessor.ExtractCorrections] multiline input tokenized differently from the Swift oracle.**
- *Symptom:* `ExtractCorrections("the\nMacOS thing", "the\nmacOS thing")` returned `["macOS"]` in C# but
  the Swift reference returns `["the\nmacOS"]` — a newline was wrongly treated as a word boundary.
- *Root cause:* the port split words with `original.Split((char[]?)null, …)`, i.e. `char.IsWhiteSpace`,
  which splits on newlines, `\r`, U+0085 (NEL), U+2028/U+2029. Swift uses
  `original.components(separatedBy: .whitespaces)` — `CharacterSet.whitespaces` = tab (U+0009) + Unicode
  **Space_Separator (Zs)** only, deliberately **excluding** newlines (Swift's `.whitespacesAndNewlines`
  is the broader set, not used here). This is the one place in the brain that uses `.whitespaces`, and
  it is **not** on the intentional-deviations list.
- *Fix:* added `SplitOnWhitespacesOnly` + `IsSwiftWhitespace` (`c == '\t' || GetUnicodeCategory(c) ==
  SpaceSeparator`) in `TextProcessor.cs` and tokenized both word lists with it. Matches Swift verbatim;
  tab stays a boundary, newlines/line-separators do not.
- *Regression test:* `ExtractCorrections_NewlineIsNotAWordBoundary` (red before → `["macOS"]`; green
  after → `["the\nmacOS"]`), plus `ExtractCorrections_TabIsAWordBoundary` pins the kept behaviour.
- *Commit:* see this firing's `test(win-bughunt): TextProcessor …` commit.

**#2 [RepetitionGuard.Core] dropped Unicode marks + Nl/No numbers (CharacterSet.alphanumerics mismatch).**
- *Symptom:* `Core("a½́b")` returned `"ab"` (Swift: `"a½́b"`). Consequence through the public API: a
  repeated `No`/`Nl`/combining-mark token forms a regurgitation loop under Swift (its core is non-empty)
  but C# silently dropped it, so `Scrub` returned the text unchanged where Swift stripped the loop —
  a (rare) silent miss of the regurgitation guard.
- *Root cause:* C# `Core` filtered with `char.IsLetterOrDigit` (Unicode **L\* + Nd** only). Swift `core()`
  uses `CharacterSet.alphanumerics` = **L\* + M\* + N\*** — it keeps combining marks (Mn/Mc/Me) and the
  Nl/No number categories. Not on the intentional-deviations list.
- *Fix:* `Core` now enumerates Unicode scalars (`string.EnumerateRunes()`, mirroring Swift's
  `unicodeScalars`) and keeps a rune iff `Rune.GetUnicodeCategory` is in L\*/M\*/N\* (new
  `IsAlphanumericScalar`). ASCII behaviour is unchanged (the change only *adds* M\*/Nl/No), so no
  regression. Also added `<InternalsVisibleTo Include="JVoice.Tests" />` to `JVoice.Core.csproj` to
  white-box-test the internal `Core`/`VocabularyCores` (mirrors Swift `@testable`).
- *Regression tests:* `Core_KeepsMarksAndNumberSymbols_LikeSwiftAlphanumerics` (red `"ab"` → green
  `"a½́b"`) and `Scrub_NumberSymbolLoop_StrippedLikeSwift` (a 12× `½` loop: red not-stripped → green
  stripped to the coherent prefix).
- *Commit:* see this firing's `test(win-bughunt): RepetitionGuard …` commit.

**#3 [WavTail.ParseHeader] a chunk size with the high bit set overflowed Int32 → uncaught throw.**
- *Symptom:* `ParseHeader` of a header containing a chunk whose 32-bit size field is `>= 0x80000000`
  (e.g. a stale/garbage byte run in the probed header of a file being written) threw
  `ArgumentOutOfRangeException` from `FourCC`/`Slice`. `WavTailReader.Open` only catches
  `IOException`/`UnauthorizedAccessException`, so it would crash the caller instead of falling back.
- *Root cause:* C# read the size as `(int)BinaryPrimitives.ReadUInt32LittleEndian(...)` and used `int`
  for `offset`. A size with the high bit set became a negative `Int32`, driving `offset` hugely
  negative; the `while (offset + 8 <= bytes.Length)` check passes for negatives, so the next slice
  indexed out of range. Swift reads the size as a 64-bit `Int`, so a huge size jumps `offset` FORWARD
  past EOF and the loop simply exits → `nil`.
- *Fix:* `offset` and `size` are now `long` (matching Swift's `Int`); `size` is the widened `uint32`
  (no sign wrap), and the in-bounds `int off = (int)offset` cast is only taken when `offset + 8 <=
  bytes.Length` (so it is always in range). Huge sizes now jump past EOF → `null`, never a throw.
- *Regression tests:* `ParseHeader_HighBitChunkSize_ReturnsNull_DoesNotThrow` (red: threw → green:
  null), `ParseHeader_MaxUintChunkSize_…`, and a 600-case `Fuzz_ParseHeader_NeverThrows`.
- *Commit:* see this firing's `test(win-bughunt): WavTail …` commit.

## Open bugs needing David (could not be safely auto-fixed)
*(HIGH PRIORITY — these are surfaced here AND the failing test is `[Fact(Skip="BUG: see #N")]` so the
suite stays green+committed while the bug stays visible. Empty = good.)*

_(none yet)_

## Invariants proven (no bug; recorded for confidence)
*(append; e.g. "WavTail tolerates a truncated FLLR chunk — fuzzed 500 cases, never throws")*

- **TextProcessor pure transforms never throw** on adversarial input (control chars, brackets, regex
  metacharacters `$`/`\`, exotic whitespace incl. U+00A0/U+2028, non-ASCII letters) — `Process` (all 3
  tones), `RemoveDisfluencies`, `RemoveWhisperHallucinations`, `ExtractCorrections`, `SpokenVariants`:
  400-case seeded fuzz (`Fuzz_PureTransforms_NeverThrow_AndStripIsIdempotent`).
- **`StripDecoderArtifacts` is idempotent** on every input (proven over the same 400-case fuzz + an
  explicit case).
- **Custom-word replacements are inserted literally** — `$`, `\`, and `$1`-style group references in a
  replacement value never trigger .NET regex substitution (parity with the three Swift backreference
  tests).
- TextProcessor C#↔Swift fidelity confirmed line-by-line (constants, branch order, tone formatting,
  filler regex, hallucination sentinel list, phrase-pattern `\b…\s+…\b`, terminal-punctuation rules).
- **PhoneticMatcher C#↔Swift fidelity confirmed line-by-line** — Metaphone digraph map, prefix
  simplifications (kn/wr/ps/wh), g↔j merge, bounded Levenshtein DP with row-min early-exit, the
  smallest-window-first token probing + exact-spelling short-circuit, the initial-sound guard, and the
  camelCase-aware `maxWindow`. All Swift correctness vectors reproduce identically in C#.
- **Bounded Levenshtein is symmetric, non-negative, and ≤ limit+1** — 400-case seeded fuzz.
- **`PhoneticMatcher.Correct` / `PhoneticKey` never throw** on adversarial input (empty/punctuation-only
  tokens, digits, over-long windows, unicode, 0–3 random vocab entries) — 400-case seeded fuzz; `Correct`
  is idempotent on the common exact-spelling case.
- **VocabularyPrompt C#↔Swift fidelity confirmed** — MaxWords=40, MaxPromptTokens=96, leading-space +
  `", "` join, the 40-word cap (word39 kept, word40+ dropped), order preserved, duplicates not deduped,
  commas in entries not escaped, and trimming identical to Swift's `.whitespacesAndNewlines`.
- **`VocabularyPrompt.Text` never throws and is well-formed** — null iff every entry trims to empty,
  else starts with exactly one leading space — 300-case seeded fuzz.
- **RepetitionGuard C#↔Swift fidelity confirmed** — all 5 constants (MinLoopTokens=8, TailWindow=12,
  DensityThreshold=0.7, MinRepeatCount=3, NonLoopyTolerance=1), the 3-step strip pipeline, `IsDegenerate`,
  the `loopy()` predicate, the 68-word stopwords list (verbatim), `VocabularyCores` camelCase splitting,
  and the trailing-separator trim. The reported-bug regurgitation case + generic non-vocab loops strip
  correctly; legitimate single/dense mentions are preserved.
- **`RepetitionGuard.Scrub` never throws and never lengthens the text** (null/empty/punctuation-only/
  loop-soup inputs across 3 vocab sets) — 400-case seeded fuzz; clean text is returned byte-identical.
- **RegurgitationRecovery decode-and-recover policy C#↔Swift fidelity confirmed** — recovery fires iff
  `useVocabularyPrompt && (removedRegurgitation || empty)`; the recovery decode is always prompt-free
  and is itself scrubbed (no silent fallback to a loop — all-loop recovery → ""); the prompt-off path
  still scrubs; decode exceptions propagate on both the first and recovery decode.
- **WavTail.ParseHeader never throws on arbitrary header bytes** (600-case seeded fuzz, half with a
  valid RIFF/WAVE prefix to exercise the chunk-walk) and C#↔Swift fidelity confirmed: RIFF/WAVE gate,
  chunk-walk with word-alignment, fmt/data format validation (PCM/16k/mono/16-bit), the deliberately-
  ignored stale RIFF/data sizes ([dataOffset,EOF) payload model), FLLR tolerance, `FloatSamples` /32768,
  and the reader's odd-trailing-byte drop + past-EOF → empty.
- **ChunkPlanner C#↔Swift fidelity confirmed** — all 6 Config constants, the silence-only cut policy
  (cut at the quietest sub-threshold window past minChunk, else wait, else force at the maxChunk cap),
  the first-minimum tie-break, the absolute+relative silence thresholds, and the partial-final-window
  RMS. `Plan` never throws and any Cut lands in (0, length] — 300-case seeded fuzz.
- **StreamingTranscriptionSession data-loss guarantee holds and C#↔Swift fidelity confirmed** — chunks
  + tail transcribed in order with **sum-of-samples == total (no loss, no duplication)**; an
  empty-but-non-silent chunk anywhere fails the session → whole-file fallback (never a silent drop); a
  transcriber throw fails safely; a genuinely silent region is dropped without failing; a vanished file
  fails to null; finish-once (a 2nd finish returns null, no backlog re-drain); cancel discards
  everything. The C# join-before-read (`await _pollTask` after cancel) replicates Swift's actor
  serialization. Verified non-flaky (3× clean full runs).

---

## Loop control
- **Consecutive iterations with no new bug AND no new coverage:** 0
- **STATUS:** IN PROGRESS
- **Stop when:** every coverage-map row is `[x]` **and** the last 3 iterations added neither a new bug
  nor new coverage → set STATUS to `DONE` and report `DONE — nothing left`.
