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
  now **363** after the full Tier 1 sweep (TextProcessor, PhoneticMatcher, VocabularyPrompt,
  RepetitionGuard, RegurgitationRecovery, WavTail, ChunkPlanner, StreamingTranscriptionSession,
  SettingsState, SettingsStateJson, WhisperModelOption, HudState, HotkeyChord, StatsMath,
  CoordinatorDecisions, BluetoothDevicePolicy, FileBackedTranscriptionEngine, + the Swift-test parity
  sweep) plus Tier 3 (StatsMath.ShouldRecord — bug #6). As the hunt adds regression tests this number
  only grows; it must never go down or go red.

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
- **SettingsStateJson per-field/wrong-type leniency** (documented in the source + locked by tests):
  Swift's `SettingsState.init(from:)` uses `try?` only for `mode`/`model` but `try`+`decodeIfPresent`
  for `schemaVersion`/`language`/`customWords`/`removeFillerWords`, so a field with the WRONG JSON TYPE
  (e.g. `"schemaVersion":"x"`, `"language":5`, a mixed `customWords` array, `"removeFillerWords":"no"`)
  makes the whole Swift decode THROW → the store treats it as corruption (reset + backup). The C# port
  deliberately falls back **every** field to its default instead (no throw, valid fields preserved, no
  backup) — see the `SettingsStateJson` doc comment + `Deserialize_UnknownEnumValues_FallBackPerField`.
  Both end at defaults for the bad field; only corruption-backup differs. Low severity, deliberate.
- **`SettingsState` record uses reference equality for `CustomWords`** (Swift's `Equatable` struct is
  value-equal). Immaterial: `SettingsStore.Update` always saves/notifies on every call and never compares
  `SettingsState` for equality, so record equality is never used for a correctness decision.
- **HudState Windows UI presentation differs from macOS HUDState** (intentional): the per-kind
  `Subtitle` copy is shorter Windows wording (e.g. Recording "Listening…" vs Swift "Capturing audio for
  transcription."), and Swift's `systemImageName` (SF Symbols) + `accentRole` + `displayText` are
  dropped — the Windows HUD renders MDL2 glyphs in `HudView` (handoff §7 #10). All behavioral semantics
  (Headline / IsVisible / IsBusy / IsTerminal / Payload) match Swift; `DownloadingModel` is the
  documented new kind. The exact subtitle copy is now test-locked so it can't silently drift.
- **WhisperModelOption Windows UI text differs from macOS** (test-locked, intentional): `LargeTurbo`
  `DisplayName` is `"Large"` (vs Swift's `"Large v3 Turbo"`) and the `Guidance` strings cite Windows GGML
  download sizes. The whole `whisperKitModelName`/`whisperKitFolderName` (CoreML) concept is replaced by
  `GgmlFileName` (whisper.cpp) — the documented platform swap (overview §2.5). The no-raw-id-in-UI
  invariant from Swift still holds.

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
- [x] **SettingsState (+migration)** — `…/Models/SettingsState.cs` + `SettingsStateTests.cs`
      ← `…/Models/SettingsState.swift` / `SettingsStateMigrationTests.swift`
      — 2026-06-23 · +7 tests · **0 bugs**. Record fields/defaults/CurrentSchemaVersion=1 match Swift;
      all 7 Swift migration vectors are already locked (legacy-no-version→normalize, forward-version→
      throw, unknown-enum→default, encode-has-version, legacy-model names, missing-fields, invalid-JSON).
      Added macOS-lowercase rawValue decoding, customWords mixed-array leniency, wrong-type schemaVersion,
      the schema==current boundary, the `with` pattern, + a 400-case decode fuzz (only ForwardVersion
      throws; valid blobs always normalize the version forward). See new intentional-deviation note re:
      per-field/wrong-type leniency + record equality.
- [x] **SettingsStateJson** — `…/Models/SettingsStateJson.cs` + `SettingsStoreJsonTests.cs`
      ← `…/Services/SettingsStore.swift` / `SettingsStoreCorruptionTests.swift` (forward-version refusal, per-field fallback)
      — 2026-06-23 · +4 tests · **0 bugs**. Decode side already exhaustively covered (firing #9). This
      firing audited the Serialize side: emits exactly the 6 Swift CodingKeys (schemaVersion/mode/model/
      language/customWords/removeFillerWords), writes enum names, JSON-special chars (`"` `\` tab newline
      unicode) survive a round-trip, + a 400-case Serialize→Deserialize identity fuzz. NOTE: the store-
      level corruption→backup+reset / debounce coalescing (SettingsStoreCorruptionTests.swift) lives in
      `JVoice.App/Platform/SettingsStore.cs` — JVoice.Tests (net9.0) can't reference JVoice.App
      (net9.0-windows), so it's deferred to the Tier 3 "SettingsStore/StatsStore/LastTranscriptStore"
      row (verify via throwaway console).
- [x] **WhisperModelOption (+GGML map)** — `…/Models/WhisperModelOption.cs` + `ModelTests.cs`
      ← `…/Models/WhisperModelOption.swift` / `WhisperModelOptionTests.swift`
      — 2026-06-23 · +11 tests · **0 bugs**. 4 cases (Tiny/Base/Small/LargeTurbo) match Swift; GGML map
      (the Windows swap for macOS CoreML folders) verified distinct + well-formed (ggml-*.bin); display
      names never leak a raw id; legacy decode (`large-v3_turbo`/`large-v3-v20240930`→LargeTurbo) + the
      LargeTurbo JSON round-trip covered. Swift largeTurbo.displayName "Large v3 Turbo" → C# "Large" and
      the Guidance strings are deliberate, test-locked Windows UI wording (see deviation note).
- [x] **HudState** — `…/Models/HudState.cs` ← `…/Models/HUDState.swift` (+ `DownloadingModel` is new)
      — 2026-06-23 · +38 tests (theories) · **0 bugs**. Behavioral semantics match Swift exactly:
      Headline (6 Swift kinds + new DownloadingModel), IsVisible/IsBusy/IsTerminal per kind, Payload
      (only Done/Error), Error empty-subtitle fallback. Locked structural invariants (every kind has a
      headline; busy∩terminal=∅; visible ⟺ busy∨terminal). Subtitle copy + the dropped systemImageName/
      accentRole/displayText are intentional Windows UI deviations (see note).
- [x] **HotkeyChord** — `…/Models/HotkeyChord.cs` + `HotkeyChordTests.cs` (Windows-only; parse/format/Default)
      — 2026-06-23 · +23 tests · **0 bugs**. Windows-only value type (no Swift ref — macOS uses the
      KeyboardShortcuts lib). Verified Default=Ctrl+Shift+Space, alias canonicalization (Ctrl/Control,
      Win/Windows/Cmd, Esc/Escape, Enter/Return, Del/Delete, PgUp/PgDn), digit + function-key (F1=0x70..
      F24=0x87; F0/F25 rejected), modifier ordering (Ctrl+Alt+Shift+Win), whitespace trimming, two-main-
      keys + modifiers-only rejection, no-modifier validity, a 400-case round-trip identity fuzz
      (TryParse(c.Format())==c), and a 400-case TryParse-never-throws-on-garbage fuzz.
- [x] **StatsMath** — `…/StatsMath.cs` + `StatsMathTests.cs` ← WPM math in `…/Services/StatsStore.swift`
      (edge cases: 0 seconds, 0 words, overflow)
      — 2026-06-23 · +7 tests · **1 bug** (#4 NaN guard). Computation matches Swift 1:1. Fixed the guard
      to faithfully negate Swift's `guard totalSeconds > 0` (NaN → 0). Added 0-words, tiny-seconds,
      int.MaxValue no-overflow, ±Infinity edges.
- [x] **CoordinatorDecisions** — `…/CoordinatorDecisions.cs` + `CoordinatorDecisionsTests.cs`
      ← decision logic in `…/VoiceCoordinator.swift` (target-window resolution, HUD→tray map, reset-delay map)
      — 2026-06-23 · +10 tests · **0 bugs**. All 3 extractions match Swift: ResolveTargetWindow
      (frontmost-if-not-self else lastNonSelf, no re-check), HudToTray (recording→Recording;
      preparing/downloading/transcribing→Transcribing; idle/done/error→Idle), HudResetDelayMs
      (Error=3000 via showError's 3 s, else 1000 default). Added all-kinds reset-delay, both-maps-
      defined-for-every-kind completeness, and the no-re-check / foreground==lastNonSelf resolve edges.
- [x] **BluetoothDevicePolicy** — `…/Audio/BluetoothDevicePolicy.cs` + `BluetoothDevicePolicyTests.cs`
      ← `…/Services/AudioInputRouter.swift` / `AudioInputRouterTests.swift` (pure non-BT pick policy)
      — 2026-06-23 · +5 tests · **0 bugs**. Matches Swift `redirectTarget` 1:1 (default-not-BT→null,
      filter non-BT, prefer built-in else first non-BT, empty→null). The `Id is {Length>0}` guard is the
      idiomatic struct-`FirstOrDefault` "no built-in found" check (only differs from Swift for an empty
      device id, which is unreachable). Added default-not-BT short-circuit edges, multiple-built-ins→
      first, single-built-in, and a 400-case fuzz (a non-null pick is always a non-BT endpoint in the
      list, only when default is BT, built-in preferred when present).
- [x] **FileBackedTranscriptionEngine** — `…/Transcription/FileBackedTranscriptionEngine.cs` + `FileBackedEngineTests.cs`
      ← `FileBackedTranscriptionEngine` in `…/Services/TranscriptionManager.swift`
      — 2026-06-23 · +2 tests · **1 bug** (#5 lenient vs strict UTF-8). Now reads bytes + strict-UTF-8
      decodes (matches Swift's `String(data:encoding:.utf8)` → unsupportedAudioFile on invalid bytes).
      file-missing / empty-transcript paths match; non-ASCII valid UTF-8 round-trips. (Minor remaining
      divergence: a read IO error is wrapped as UnsupportedAudioFile, where Swift propagates the raw
      error — kept as the safer fallback-engine behaviour; noted.)
- [x] **Swift-test parity sweep** — enumerate EVERY case in each `Tests/JVoiceTests/*.swift` brain test
      and confirm a C# equivalent assertion exists. Any Swift vector with no C# counterpart = a coverage
      gap → add the C# test; if it fails, that's a port-fidelity bug → fix `JVoice.Core` to match Swift.
      — 2026-06-23 · +1 test · **0 bugs (this firing)**. Brain (Core-testable) Swift test files all
      confirmed covered: TextProcessorTests, PhoneticMatcherTests, VocabularyPromptTests,
      RepetitionGuardTests, RegurgitationRecoveryTests (closed the last vector this firing — prompt-off
      single decode receives `false`), WavTailTests, ChunkPlannerTests, StreamingTranscriptionSessionTests,
      SettingsStateMigrationTests, WhisperModelOptionTests, LastTranscriptTests (extractCorrections part),
      AudioInputRouterTests (pure non-BT pick = BluetoothDevicePolicy). The remaining Swift test files are
      **App-bound** (JVoice.Tests net9.0 can't reference JVoice.App net9.0-windows) and map to later rows:
      TranscriptionManagerTests + WhisperModelLocatorTests → Tier 2 (engine); MenuBarIconTests,
      PasteManagerTests, PermissionErrorTests, RecordingManagerDelegate/Interruption,
      VoiceCoordinatorHotkeyRaceTests, SettingsStoreCorruptionTests (store level),
      LastTranscriptTests (store level) → Tier 3 (platform, throwaway-console verification).

### Tier 2 — engine + streaming on real audio (machine-verifiable via bench/smoke; needs Tiny model)
- [x] **WhisperNetTranscriptionEngine — adversarial WAVs** — `JVoice.App/Whisper/WhisperNetTranscriptionEngine.cs`.
      Run crafted 16 kHz/mono/16-bit WAVs through `whisper-smoke` and `JVoice.exe --bench` (+`--stream`):
      empty/near-empty, pure silence, < 1 s, very long (>120 s), full-scale clipping, DC offset, all-noise,
      and a non-16 kHz file (expect a clean rejection, not a crash). Invariants: never crashes, never a
      silent drop (streaming falls back to whole-file), correct exit codes (64/65/66/70/1/0).
      — 2026-06-23 · 0 new xUnit (engine harness) · **0 bugs**. Ran Tiny through whisper-smoke on 8
      crafted WAVs: baseline→`"Testing J voice on Windows 1 2 3"`; silence/0.3 s/clipping/DC →
      clean **"No transcript was produced"** (exit 1, no garbage); white-noise → a benign Whisper
      hallucination `"(engine revving)"` (raw engine output — the brain's hallucination-stripping handles
      this downstream); 125 s clip → exit 0 in ~2 s (no truncation/crash); **non-16 kHz (44.1 kHz) →
      clean "Unsupported audio file"** (exit 1). NEVER crashed on any input. `JVoice.exe --bench` (x64
      build) bad-arg exit codes verified: no-wav→64, missing-file→66, bad-model→64 (short-circuit before
      model/WPF; 65/70 confirmed by code-review of BenchRunner). HARNESS GOTCHA logged below.
- [x] **WhisperModelStore** — `JVoice.App/Whisper/WhisperModelStore.cs`. Verify size+SHA gate, atomic
      `.part`→final rename, no re-download when present, no `.part` leftovers, corrupt-file re-fetch.
      — 2026-06-23 · throwaway probe (11 checks, all PASS) · **0 bugs**. Verified with a temp-dir probe
      that compiled the real store + a mock HttpClient (no network): CompleteModelPath size gate
      (missing/wrong-size→null, exact-size→path); EnsureAsync short-circuits when present (HTTP never
      called); DownloadAsync wrong-size→throws + `.part` deleted + no final; a stale `.part` is never
      resumed; a corrupt (wrong-size) existing file → re-fetch attempted, throws (broken path never
      returned); and the SUCCESS path streaming the **real** tiny model → size+SHA verified → atomic
      rename, no `.part` leftover. Probe deleted after the run (tree clean).
- [x] **Bench/smoke CLI** — arg parsing edge cases (missing args, bad flags, `--vocab` quoting, `--lang`,
      `--no-prompt`, unknown model) → documented exit codes, never an unhandled exception.
      — 2026-06-23 · engine-harness runs + code-review · **0 bugs**. whisper-smoke: no-args→64,
      no-file→66, valid+`--vocab "VS Code,JVoice"`→0 (comma-split/quoting), `--no-prompt`→0, `--lang ro`→0,
      empty `--vocab ""`→0 — no unhandled exceptions. x64 `--bench`: unknown `--model`→64, unknown
      `--lang`→64, `--bench --model tiny` (no wav, flag taken as the missing path)→66; no-wav→64,
      missing-file→66 (firing #19). Every parse uses Array.IndexOf + Split + switch-with-default, so a
      malformed/partial arg can only yield a defined exit code (64/65/66/70/1/0), never a throw. No GUI
      spawned for any bad-arg run (process count unchanged).

### Tier 3 — headless-verifiable platform (review + throwaway-console harnesses; NO GUI/mic/paste E2E)
- [x] **NAudioRecorder** — `JVoice.App/Platform/NAudioRecorder.cs`. Orphan-WAV sweep correctness,
      `BufferedWaveProvider.ReadFully=false` (no infinite flush loop), `IsUsableRecording` thresholds,
      growing-WAV header contract (16000/1/2) readable by `WavTailReader`. (Verify with a small console
      that drives the recorder logic where a mic isn't required; review the parts that need a device.)
      — 2026-06-23 · throwaway sweep-probe (11 checks, all PASS) · **0 bugs**. The orphan-sweep glob
      (`jvoice-*.wav`) is correctly scoped: matches `jvoice-<guid>.wav` (incl. the recorder's own
      prefix+ext) and NEVER over-matches — `foo.wav`, `notjvoice-*.wav`, `jvoice-*.txt`, `settings.json`,
      and crucially `jvoice-x.wavbak` / `jvoice-x.wav.old` are all excluded (.NET 9 has no legacy 8.3
      `*.wav`→`*.wavXYZ` quirk). Code-review confirmed: `ReadFully=false` (the documented infinite-loop
      fix), every failure path calls `TearDownLocked(deleteFile:true)` (a broken recording never orphans
      a WAV), `IsUsableRecording` = Exists && Length>=1024 (try/catch→false), and the 16k/mono/16-bit
      WaveFileWriter header (already proven readable by WavTailReader in Tier 1 + handoff §6). Mic
      capture / permission probe need a device (David's dogfood); probe deleted (tree clean).
- [x] **SettingsStore / StatsStore / LastTranscriptStore** — `JVoice.App/Platform/*Store.cs`. Corruption→
      backup+reset, forward-version refusal, UTF-8 round-trip, debounced-write coalescing, concurrent-write safety.
      — 2026-06-23 · +8 xUnit (StatsMath.ShouldRecord) + throwaway store-probe (17 checks, all PASS) ·
      **1 bug (#6, fixed)**. Found & fixed bug #6 (StatsStore.Record NaN guard — see below). Verified via a
      temp-dir probe driving the real stores: SettingsStore corrupt JSON → Default + corrupt blob backed up;
      forward-version (`schemaVersion:999`) → Default + backup; missing → Default + default written to disk;
      Update+Flush round-trip (RemoveFillerWords + CustomWords); StatsStore Record guard (0/neg/NaN rejected,
      positive recorded), synchronous persistence, corrupt→fresh, Reset; LastTranscriptStore UTF-8 round-trip
      (é/CJK/em-dash) + missing→"" + no BOM. NOTE (intentional, see deviations): on corruption the Windows
      store leaves the bad settings.json in place (backed up) and normalizes it on the next Flush/Dispose/Update
      rather than rewriting defaults immediately like Swift's UserDefaults — the contract (user gets defaults,
      corrupt blob preserved) holds. Probe deleted (tree clean).
- [x] **Paster** — `JVoice.App/Platform/Paster.cs`. Review the `INPUT`/`InputUnion` struct (sizeof==40 on
      x64), `FocusTarget` already-foreground early-return, clipboard save/restore (300 ms / 50 ms-failure).
      Add a unit test for any pure logic (outcome mapping); E2E paste needs the dogfood checklist.
      — 2026-06-23 · reflection probe (6 checks, all PASS) + code-review vs PasteManager.swift · **0 bugs**.
      Reflection probe confirmed the P/Invoke marshalling: INPUT=40, InputUnion=32, MOUSEINPUT=32,
      KEYBDINPUT=24, HARDWAREINPUT=8 — so SendInput's `cbSize=40` is correct (the union carries MOUSEINPUT,
      the largest member; the prior 32-byte bug is gone). Code-review vs Swift: outcome flow matches
      (empty→TargetRejected; elevated-target→AccessDenied is the documented Windows analog of macOS
      `accessibilityDenied`; focus-fail/send-fail→TargetRejected; ok→Ok); restore delays match
      (success→300 ms = Swift `pasteRestoreDelay`; failure→50 ms = Swift hardcoded `0.05`); empty/locked
      clipboard→null→no restore matches Swift's `!snapshot.isEmpty` guard; `_restoreCts` cancel+dispose
      matches `restoreTask?.cancel()` (two pastes in-window don't clobber each other); `FocusTarget`
      already-foreground early-return + AttachThreadInput foreground workaround reviewed. E2E paste is
      David's dogfood (commit 434adef "make dictation paste actually work" already fixed it live). Probe
      deleted (tree clean).
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

**#4 [StatsMath.AverageWpm] NaN totalSeconds returned NaN instead of 0 (guard not the exact Swift negation).**
- *Symptom:* `AverageWpm(100, double.NaN)` returned `NaN`; Swift's `averageWPM` returns `0`.
- *Root cause:* Swift guards with `guard totalSeconds > 0 else return 0` (so `NaN > 0 == false` → 0),
  but the C# port guarded with `if (totalSeconds <= 0) return 0` — and `NaN <= 0 == false`, so NaN fell
  through to `words / NaN * 60 = NaN`. `<= 0` is not the exact negation of Swift's `> 0` for NaN.
- *Fix:* guard is now `if (!(totalSeconds > 0)) return 0;` — the literal negation of the Swift guard,
  returning 0 for `<= 0` AND NaN. Finite/±Infinity behaviour is unchanged. (Low severity — totalSeconds
  is an accumulated real duration, never NaN in practice — but it's a clear fidelity divergence.)
- *Regression test:* `NaN_Seconds_ReturnsZero` (red `NaN` → green `0`).
- *Commit:* see this firing's `test(win-bughunt): StatsMath …` commit.

**#5 [FileBackedTranscriptionEngine] read leniently as UTF-8 → the unsupportedAudioFile path was dead.**
- *Symptom:* a non-UTF-8 "audio" file (e.g. a real WAV fed to the fallback engine) was read with U+FFFD
  replacement chars and returned as a garbage transcript, instead of throwing `UnsupportedAudioFile`.
- *Root cause:* C# used `File.ReadAllTextAsync` (lenient UTF-8 — never throws on bad bytes, replaces
  them), so the `UnsupportedAudioFile` branch only ever fired on IO errors, never on its intended
  "not decodable text" case. Swift uses strict `String(data:encoding:.utf8)` (returns nil → throws
  `unsupportedAudioFile`).
- *Fix:* read raw bytes (`File.ReadAllBytesAsync`) then decode with `UTF8Encoding(throwOnInvalidBytes:
  true)`; a `DecoderFallbackException` → `UnsupportedAudioFile`. Valid UTF-8 (incl. non-ASCII) is
  unchanged; file-missing/empty paths unchanged. (This also keeps a leading BOM as U+FEFF like Swift,
  vs the old StreamReader BOM-strip.)
- *Regression test:* `InvalidUtf8File_ThrowsUnsupportedAudioFile` (bytes `41 FF 42`; red: no throw →
  green: `UnsupportedAudioFile`) + `ValidUtf8_NonAscii_Decodes`.
- *Commit:* see this firing's `test(win-bughunt): FileBackedTranscriptionEngine …` commit.

**#6 [StatsStore.Record] NaN-duration guard let NaN through (sibling of bug #4).**
- *Symptom:* `StatsStore.Record(words, NaN)` added `NaN` to `totalSeconds` instead of ignoring the
  sample. That poisons lifetime stats (every later AverageWpm depends on it — masked to 0 only because
  bug #4 was fixed) and breaks persistence (System.Text.Json refuses to serialize `NaN` → the save
  throws → stats silently not written).
- *Root cause:* the port wrote the guard as `if (words <= 0 || durationSeconds <= 0) return;`. `NaN <= 0`
  is **false**, so a NaN duration slipped past. Swift's guard is `guard words > 0, durationSeconds > 0`
  and `NaN > 0` is **false**, so Swift rejects it. Exact same negation flaw as bug #4 (StatsMath), in a
  second location. Not on the intentional-deviations list.
- *Fix:* added the pure, testable `StatsMath.ShouldRecord(words, durationSeconds) => words > 0 &&
  durationSeconds > 0` in `JVoice.Core` (mirrors Swift's guard; rejects NaN) and rewired
  `StatsStore.Record` to `if (!StatsMath.ShouldRecord(words, durationSeconds)) return;`. Relocating the
  guard to Core follows the established "Core-located pure helpers" pattern so it gets permanent xUnit
  coverage (JVoice.Tests can't reference the App-layer StatsStore).
- *Regression test:* `StatsMathTests.ShouldRecord_NaNDuration_IsFalse` (+ a `ShouldRecord_PositiveOnly`
  Theory for 0/neg/positive edges + `…PositiveInfinityDuration_IsTrue`). Red on the old inline guard
  (`NaN <= 0` == false → not rejected); green now. Also empirically confirmed at the StatsStore level via
  the throwaway store-probe (`Record(10, NaN)` → totalSeconds stays 0, not NaN).
- *Commit:* see this firing's `test(win-bughunt): Settings/Stats/LastTranscript stores …` commit.

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
- **SettingsStateJson Serialize↔Deserialize is a faithful round-trip** — emits exactly the 6 Swift
  CodingKeys, writes enum names, JSON-special chars (`"`/`\`/tab/newline/unicode/empty) survive intact,
  and Serialize→Deserialize is an identity on all fields for any valid SettingsState — 400-case fuzz.
- **HudState behavioral semantics match Swift** (Headline/IsVisible/IsBusy/IsTerminal/Payload per kind);
  structural invariants hold for every kind (busy∩terminal=∅; visible ⟺ busy∨terminal).
- **HotkeyChord parse/format round-trip is an identity** (`TryParse(c.Format()) == c`), alias/case/
  ordering canonicalize, and `TryParse` never throws on arbitrary input — two 400-case seeded fuzzes.
- **Paster's SendInput marshalling is correct** — `sizeof(INPUT)==40` on x64 (union carries the largest
  member, MOUSEINPUT=32; type+pad=8), confirmed by reflecting the real private structs; and the
  outcome/restore-delay flow (success 300 ms / failure 50 ms, restore-cancellation, empty-clipboard→no-restore)
  matches PasteManager.swift. The 40-byte cbSize is what made paste work (commit 434adef).
- **The three platform stores honor their recovery contracts** — SettingsStore: corrupt JSON and
  forward-version (`schemaVersion`>current) both → defaults with the original blob preserved in
  `settings.corrupt.bak`; missing → defaults written to disk; Update+Flush round-trips fields; atomic
  temp-file→move write. StatsStore: Record rejects non-positive AND NaN (bug #6 fixed), persists
  synchronously, corrupt→fresh, Reset clears. LastTranscriptStore: UTF-8 round-trip (é/CJK/em-dash),
  missing→"", no BOM. Verified by a 17-check temp-dir probe + the StatsMath.ShouldRecord unit tests.
- **NAudioRecorder orphan-sweep is correctly scoped** — `jvoice-*.wav` matches the recorder's own
  files and never over-matches unrelated temp files (incl. the legacy `*.wav`→`*.wavXYZ` 8.3 quirk,
  which .NET 9 doesn't exhibit); failure paths always delete the partial WAV (no orphan); `IsUsableRecording`
  = Exists && Length>=1024. Verified by an 11-check temp-dir probe + code-review.
- **MILESTONE — Tier 2 (engine) is fully audited (2026-06-23).** All 3 Tier-2 rows are `[x]`: the
  WhisperNet engine never crashes on adversarial audio, WhisperModelStore only ever exposes a complete
  (size+SHA-verified) model, and the bench/smoke CLI maps every arg edge to a defined exit code with no
  unhandled exception. **0 bugs in Tier 2.** Next: Tier 3 (headless-verifiable platform code).
- **Bench/smoke CLI never throws on malformed args** — every flag is parsed via Array.IndexOf + Split +
  switch-with-default, so missing/bad/partial flags resolve to a documented exit code (64/65/66/70/1/0);
  verified across whisper-smoke (no-args/no-file/vocab/no-prompt/lang/empty-vocab) and x64 `--bench`
  (unknown model/lang, flag-as-path). No bad-arg run launches the GUI.
- **WhisperModelStore only ever exposes a complete model** — size+SHA gate, no-redownload-when-present,
  stale-`.part` never resumed, wrong-size/corrupt → throw + `.part` cleaned (never a broken final), and
  the real-tiny success path passes size+SHA before the atomic rename — 11-check temp-dir probe (no network).
- **WhisperNetTranscriptionEngine never crashes on adversarial audio** — verified on-device (Tiny, via
  whisper-smoke) over silence, <1 s, full-scale clipping, DC offset, white noise, a 125 s clip, and a
  non-16 kHz file: no crash, no hang, no silent drop; empty results surface as a clean "No transcript"
  (exit 1) and a wrong-format file as "Unsupported audio file" (exit 1). White-noise can yield a benign
  Whisper hallucination at the raw-engine layer (handled downstream by the brain's hallucination strip).
- **HARNESS GOTCHA (for future Tier-2/3 firings):** run the app exe from
  `windows/JVoice.App/bin/**x64**/Release/net9.0-windows/JVoice.exe`. A stale non-bench-aware exe at
  `bin/Release/net9.0-windows/` (predates the App.xaml→Page/bench-Main fix) launches the **GUI** for
  every arg incl. `--bench` — running it spawns a tray instance. The x64 exe correctly short-circuits
  `--bench` (no-wav→64, missing→66) before WPF. Always cap exe runs with a timeout and check the JVoice
  process count before/after; never kill David's running instance (identify by StartTime).
- **MILESTONE — Tier 1 (the pure brain) is fully audited (2026-06-23).** All 18 Tier-1 rows are `[x]`.
  Every `JVoice.Core` component was compared line-by-line against its read-only Swift reference and the
  Swift brain test vectors were ported; **5 real port-fidelity bugs were found and fixed** (#1
  ExtractCorrections newline tokenization, #2 RepetitionGuard.Core alphanumerics, #3 WavTail chunk-size
  Int32 overflow→throw, #4 StatsMath NaN guard, #5 FileBacked strict-UTF-8). The brain is byte-faithful
  to Swift modulo the documented intentional deviations above. Next: Tier 2 (engine adversarial WAVs).
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
