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
  now **192** after the TextProcessor + PhoneticMatcher audits). As the hunt adds regression tests this
  number only grows; it must never go down or go red.

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
- [ ] **VocabularyPrompt** — `…/Text/VocabularyPrompt.cs` + `VocabularyPromptTests.cs`
      ← `…/Services/VocabularyPrompt.swift` / `VocabularyPromptTests.swift`
- [ ] **RepetitionGuard** — `…/Text/RepetitionGuard.cs` + `RepetitionGuardTests.cs`
      ← `…/Services/RepetitionGuard.swift` / `RepetitionGuardTests.swift` (incl. the 120-case fuzz)
- [ ] **RegurgitationRecovery** — `…/Text/RegurgitationRecovery.cs` + `RegurgitationRecoveryTests.cs`
      ← `…/Services/RegurgitationRecovery.swift` / `RegurgitationRecoveryTests.swift`
- [ ] **WavTail / WavTailReader** — `…/Audio/WavTail.cs` + `WavTailTests.cs`
      ← `…/Services/WavTail.swift` / `WavTailTests.swift` (FLLR padding, stale size, growing WAV)
- [ ] **ChunkPlanner** — `…/Audio/ChunkPlanner.cs` + `ChunkPlannerTests.cs`
      ← `…/Services/ChunkPlanner.swift` / `ChunkPlannerTests.swift` (silence-cut, min/max constants)
- [ ] **StreamingTranscriptionSession** — `…/Audio/StreamingTranscriptionSession.cs` + `StreamingSessionTests.cs`
      ← `…/Services/StreamingTranscriptionSession.swift` / `StreamingTranscriptionSessionTests.swift`
      (the data-loss guarantee: empty non-silent chunk → fallback, NEVER a silent drop; finish-once; cancel-join)
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

---

## Loop control
- **Consecutive iterations with no new bug AND no new coverage:** 0
- **STATUS:** IN PROGRESS
- **Stop when:** every coverage-map row is `[x]` **and** the last 3 iterations added neither a new bug
  nor new coverage → set STATUS to `DONE` and report `DONE — nothing left`.
