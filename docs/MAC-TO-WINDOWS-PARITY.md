# JVoice — macOS → Windows parity (everything the Mac gained since 2026-09-12)

**Written 2026-09-30 on the Mac, for a fresh Claude Code session on David's Windows PC.** You have no
other context. Read this file top to bottom once, then work through §3 ("Order of work") one item at a
time. Every item says what the Mac does, what the Windows port does today, exactly what to build, and
how to check it.

## 0. Orientation

### 0.1 What JVoice is, and where each version lives
- **JVoice** is David's local push-to-talk dictation app: press a global hotkey, speak, a local
  **Whisper** speech-recognition model transcribes, the text is cleaned up and pasted into the app you
  were typing in. Zero network calls at runtime.
- **macOS app**: Swift, `Sources/JVoice/` at the repo root. Uses **WhisperKit** (Whisper on Apple's
  Neural Engine / Core ML).
- **Windows port**: C# / .NET, WPF, under `windows/` (`windows/JVoice.sln`: `JVoice.Core` = pure logic,
  `JVoice.App` = WPF app + Win32 platform code, `JVoice.Tests` = xUnit, `tools/` = probes). Uses
  **whisper.cpp via Whisper.net**. Its area index is `windows/CLAUDE.md`; its big work log is
  `docs/HANDOFF-WINDOWS.md` (§7 is a numbered list of shipped items, e.g. §7 #48 = Math Notation,
  §7 #49 = zero-latency HUD).
- GitHub: `https://github.com/david53001/jvoice` (public). Branches that matter:

| Branch | What it holds |
|---|---|
| `windows-port` | The Windows port. **You work here.** Tip when this doc was written: `11465a4` ("§7 #49 shipped"), plus this doc's commit. |
| `origin/main` | macOS app through v1.1.4 (native look, guided tour, bug-hunt fixes). Contains `windows/` unchanged from `windows-port`. |
| `origin/feat/tour-opacity` | `main` + the Opacity setting + tour polish + "windows open on the active display" (the newest macOS UI). |
| `origin/feat/math-format` | The new maths engine + shared notation format (pushed 2026-09-30; `git show origin/feat/math-format:<path>`). Its sources are also copied into `docs/mac-reference/src/math-format/`. |

- Read a Mac file without switching branches:
  `git fetch origin && git show origin/feat/tour-opacity:Sources/JVoice/UI/HUDView.swift`.
  List them: `git ls-tree -r --name-only origin/feat/tour-opacity Sources/`.
- Mac → Windows history: the Windows port was ahead in July–September (the Mac copied six dictation
  features, Math Notation and the zero-latency HUD FROM Windows). Since 2026-09-12 the Mac has moved on
  and Windows has not been touched. Everything below is the delta.

### 0.2 Reference material shipped next to this file (`docs/mac-reference/`)
Copies of the Mac's own notes, taken 2026-09-30. They are the Mac's source of truth; this document
summarises them for Windows and adds the Windows comparison.

| File | What it is |
|---|---|
| `CHANGELOG-mac.md` | The Mac CHANGELOG (Unreleased → 1.1.0) — user-facing description of every change. |
| `HANDOFF-mac.md` | The Mac session log (`docs/HANDOFF.md` on `feat/tour-opacity`) — root causes, measurements, decisions. |
| `HANDOFF-mac-math-format.md` | The extra sessions logged on `feat/math-format`. |
| `math-notation-format.md` | **The shared maths output format** (JVoice + BetterScreenshot). Normative. |
| `math-notation-progress.md` | How the Mac implemented it, deviations, and a **"Windows mirror list"** (§7 below repeats it). |
| `opacity-progress.md` | The Opacity setting: numbers, measurements, method. |
| `briefs/*.md` | The Mac area briefs (`CLAUDE.md` files): `mac-root`, `UI`, `Tours`, `Transcription` (math-format version), `Audio`, `Orchestration`. Dense and exact. |
| `src/tour-opacity/…` | Mac Swift sources for the Tours kit, the UI pure-logic files, and the streaming/text/orchestration files referenced below (also readable via `git show origin/feat/tour-opacity:…`). |
| `src/math-format/…` | Mac Swift sources + tests of the maths engine from the unpushed `feat/math-format` branch. |
| `design-language/` | David's cross-app design language (from his MacStats repo, which the PC doesn't have): `README.md` (the native look), `jvoice-native-redesign.md` (how it was applied to JVoice), `opacity-setting.md` (the shared Opacity spec). |

### 0.3 House rules that apply on Windows too
- David's global rules: plan big, do small; verify (build + relevant tests) before saying done; touch
  only what the task needs; keep a progress note updated so the next session can continue (use
  `docs/HANDOFF-WINDOWS.md` §7 — add one numbered entry per item you ship).
- **The Windows HUD must stay crisp at David's non-native, stretched gaming resolution** (1600×1080
  stretched; `DisplayMetrics.HudScale` in the port). Fix blur in-app; never tell David to change his
  resolution. Any translucent/"glass" work below must be checked at that resolution.
- Never suggest undervolting/downclocking the PC.
- Latency contract (both platforms): the pill appears on the hotkey press BEFORE any microphone work.
  Nothing below may add work between the press and the pill.

### 0.4 Terms used below
- **HUD / pill** — the small floating capsule that shows recording / transcribing / pasted / error.
- **Chunk / streaming session** — while you talk, the recording is cut at pauses into chunks that are
  decoded in the background, so little is left to decode after the stop press.
- **Tail** — the audio after the last chunk cut; decoded after the stop press.
- **Speculative tail decode** — decoding the tail early, when the speaker pauses, betting the next
  event is the stop press.
- **Vocabulary prompt** — the custom words fed to Whisper as conditioning text; improves spelling of
  names but can make Whisper recite the list back ("regurgitation").
- **Witness decode** — one extra decode WITHOUT the prompt, used only when a failure mode shows; it
  decides which text to keep.
- **Run / activation (maths)** — see §7.1.
- **Material** (macOS) — a system blur of whatever is behind a window. The Windows analogues are
  **Mica** (blurred desktop wallpaper, for main windows) and **Acrylic** (blur of what's behind, for
  transient surfaces), set with `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)` on Windows 11 22H2+.
- **Backing** — a solid colour layer over the material whose alpha the Opacity slider sets.
- **Continuous corners / squircle** — Apple's smooth rounded rectangle; on Windows use the closest:
  a normal rounded rectangle of the same radius (or DWM rounded corners for whole windows).
- **Contrast N:1** — WCAG 2.x contrast ratio; 4.5:1 is the minimum for normal text.

---

## 1. Summary — every change, and where Windows stands

Status: **MISSING** (Windows has nothing), **PARTIAL** (some of it / different), **DONE** (already
equivalent), **N/A** (Mac-only problem). Priority: **P1** = user-visible / correctness, do first;
**P2** = important; **P3** = polish.

| # | Change (Mac version) | Mac commit(s) | Windows today | Prio | § |
|---|---|---|---|---|---|
| 1 | Zero-latency HUD, faster paste, poll 1 s→250 ms | 5daf1b0 | **DONE** (it was ported *from* Windows §7 #49) | — | 5.1 |
| 2 | Streaming poll 250 → **100 ms** + stat-before-read | ab0b846 | **DONE** 919880b | P2 | 5.2 |
| 3 | **Speculative tail decode** | ab0b846, 2026-09-23 validity fix | **DONE** 919880b | P1 | 5.3 |
| 4 | In-flight chunk decode survives the stop press | ab0b846 | **DONE** 919880b | P1 | 5.4 |
| 5 | Pre-prepared spare recorder | ab0b846, 65b63ae | PARTIAL (Windows prewarms differently) | P3 | 5.5 |
| 6 | **Local recovery** of a failed/empty chunk (no whole-file re-decode) | ffbca8a | **DONE** 919880b | P1 | 5.6 |
| 7 | Soft-audio robustness in chunking | ffbca8a | Check | P2 | 5.6 |
| 8 | **Maths is not a loop** (RepetitionGuard math-token exemption + trailing phrase loop) | ffbca8a | **DONE** 24c336d | P1 | 6.1 |
| 9 | Witness guards (phrase loop anywhere, sparse, silence gate, vocab recital, caption-only) | d6d7a63 | **DONE/origin** (Mac ported them *from* Windows); small deltas in §6.2 | P3 | 6.2 |
| 10 | Custom words: keep neighbour & possessive, no joins across commas, edit distance ≤ 1 | b0bb390 | **DONE** 8d51918 | P1 | 6.3 |
| 11 | Filler removal no longer eats "ER", "err", "Uh-oh", "Mm-hmm" | b0bb390 | **DONE** 8d51918 | P1 | 6.3 |
| 12 | Everyday-English keys removed from Developer Terms | b0bb390 | **DONE** 8d51918 | P2 | 6.3 |
| 13 | ".NET"/".env" custom words keep dots once; Very Casual keeps "$1,000,000"; Formal period rules | b0bb390 | **DONE** 8d51918 | P3 | 6.3 |
| 14 | "J-Voice" → "JVoice"; bare lowercase "you" on <1 s hum dropped | 000a8b0 | **DONE** 8d51918 | P2 | 6.4 |
| 15 | Second press during transcription is ignored (never discards) | 8ea5088 | **DONE** 5c8cf04 | P1 | 6.5 |
| 16 | Refused paste → clipboard + history; per-item clipboard restore, skipped if user copied | 8ea5088 | **DONE** 5c8cf04 | P1 | 6.5 |
| 17 | Mic/device fixes (virtual-device redirect, silent device named, "Recording was interrupted", stop during open, quit deletes audio) | 8ea5088 | Check each | P2 | 6.5 |
| 18 | Shortcut recorder refuses bare / system / app-menu / duplicate chords, with a reason | 22694e2 | DONE 0b88006 | P1 | 6.6 |
| 19 | Rejected custom word / app rule stays in the field with the reason | 22694e2 | MISSING | P2 | 6.6 |
| 20 | Hidden pill stops animating while hidden (2–5 % CPU idle) | 22694e2 | Check (Windows has a generated wave) | P1 | 6.7 |
| 21 | Settings crash (KeyboardShortcuts `Bundle.module`) | 0c46d53 | **N/A** (Mac-only) | — | 6.8 |
| 22 | **Maths engine package** (grouping, "to the", ordinals, "x" for times, article pair, leaks) | 563bf4f | DONE 1cecc0e | P1 | 7.3 |
| 23 | **Shared math-notation format** (Unicode, `/` fractions, `×` vs juxtaposition, `√(…)`, `sin θ`) | 6bcd031 | DONE 1cecc0e | P1 | 7.2 |
| 24 | "root of … Kx … sigma of" dictation fix; glued variables | 382da82 | DONE 1cecc0e | P1 | 7.4 |
| 25 | "sigma" = ∑ (σ is "lowercase sigma") | ede7a2d | DONE 1cecc0e | P1 | 7.5 |
| 26 | Math Notation off must be measurably faster | spec §5 | Check | P3 | 7.6 |
| 27 | Bench: `--repeat N --idle S`, prompt-token count, `--no-math`, `--stream --realtime` | 26bb896, fdacf33 | PARTIAL | P3 | 5.7 |
| 28 | **Native look** (System/Light/Dark, translucent Settings, cards, native controls) | a3bfff0 | MISSING (Windows is pure-black monochrome) | P1 | 8 |
| 29 | **Glass pill that hugs its content and morphs between states** | a3bfff0, 33d8a21 | MISSING | P1 | 8.4 |
| 30 | **Opacity setting** (Settings → Appearance) | d060a72 | MISSING | P1 | 9 |
| 31 | **First-run Welcome window + guided tours** (new users only) | 124c42c…157698d | MISSING | P1 | 10 |
| 32 | ⓘ on every window (Replay Tour, Show Me list), Help & Tours menu, Tours & Tips card | 99abe37, 5069c8c | MISSING | P1 | 10.6 |
| 33 | Tour polish: capsule outline on the pill, animated Opacity step | a45598e | MISSING | P2 | 10.8 |
| 34 | Windows open on the display with the mouse pointer | a45598e | MISSING | P2 | 11 |
| 35 | `--ui-preview` screenshot mode, `--settings-smoke` | b034f9d, 0c46d53 | PARTIAL (`--settings-render` exists) | P3 | 12 |
| 36 | HUD: model download vs compile shown separately; compile wait once per model | 767a1f4, ab8063e | N/A (Neural-Engine compile) — see §6.9 | — | 6.9 |
| 37 | One-line terminal install/update + stable signing | 83c21fb | N/A — Windows has its own installer + updater | — | 6.10 |

---

## 2. What NOT to port (and why) — read before starting
- **KeyboardShortcuts / `Bundle.module` crash (v1.1.1)** — a SwiftPM packaging bug; Windows' `HotkeyRecorder`
  is its own control. Only the *refusal rules* (§6.6) matter on Windows.
- **Neural Engine compile split (767a1f4, ab8063e)** — whisper.cpp has no per-model compile step. Keep
  Windows' existing "downloading / loading model" states.
- **Bluetooth "call mode" from the spare recorder (65b63ae)** — a macOS AVAudioRecorder timing issue.
  On Windows, *opening* a Bluetooth headset's microphone also switches it to the Hands-Free profile
  (music drops to mono/quiet). If you add a spare/prewarmed capture (§5.5), never open the headset mic
  before the user presses the key.
- **Mac install one-liner / signing identity** — Windows already ships installers + `JVoice.App/Update`.
- **Windows-only features the Mac lacks** — `FramePacer`, UI-thread priority boost, `TailCoverageGuard`
  (§7 #39), `HighPassSilence`, game detection, `DisplayMetrics.HudScale`. Keep them.

---

## 3. Order of work (recommended)
Do these as separate, verified, committed steps (one §7 entry each in `docs/HANDOFF-WINDOWS.md`):
1. **Accuracy fixes that lose words today**: §6.1 (maths deleted as a "loop"), §6.3 (custom words eat the
   previous word; filler eats "ER"), §6.5 (second press / failed paste). Small, pure, testable.
2. **Speed**: §5.6 local recovery, §5.3 speculative tail, §5.2 100 ms poll, §5.4 in-flight check.
3. **Maths**: §7 (engine package → format → root/glued fix → sigma). Largest pure-logic job; port the
   Swift engine file by file (`docs/mac-reference/src/math-format/`), then the tests.
4. **Shortcut recorder rules**, entry-policy messages, hidden-pill CPU (§6.6–6.7).
5. **Native look + glass pill + morph** (§8) — the biggest UI job. Decide the backdrop strategy first
   (§8.2) and check the pill at the stretched resolution.
6. **Opacity** (§9) — needs §8's material + backing structure.
7. **Welcome window + tours + ⓘ + Help & Tours** (§10) — needs §8/§9 for the tag's look.
8. **Active display** (§11), dev modes (§12).

---

## 4. Build / test on Windows (reminder)
Exact commands are in `windows/CLAUDE.md` ("Build / test"). In short: `dotnet build windows/JVoice.sln -c Release`,
`dotnet test windows/JVoice.Tests`. Pure logic goes in `JVoice.Core` with xUnit tests; anything WPF/Win32 in
`JVoice.App`. Republish/relaunch the tray app after runtime-visible changes (see `windows/README.md`).

---

## 5. Speed

### 5.1 Zero-latency HUD, faster paste — DONE on Windows
The Mac's 2026-09-12 work (pill shown synchronously on the press, prewarmed HUD window, mic opened
off the UI thread, permission fast path, audio-stack warm-up, paste skips the 80 ms activation wait when
the target is already frontmost, "transcribing" pill before the recorder stops, "done" pill before the
stats writes) is a port of Windows §7 #49 (`a22440f`). Windows already has all of it
(`HudWindow.Prewarm`, `AppTimings.PasteActivationDelay`, `LatencyProbe`). Nothing to do — but keep the
contract when building §8–§10.

### 5.2 Streaming poll 100 ms, stat before read — PARTIAL
- Mac: `AppTimings.streamingPoll = 0.1` s (was 1 s → 250 ms → 100 ms). Each poll first **stats** the WAV
  and skips the read if the file hasn't grown (the Mac recorder flushes in ~320 ms bursts), so 10 Hz
  costs nothing.
- Windows: `windows/JVoice.Core/Policy/AppTimings.cs` → `StreamingPollMs = 250`.
- Do: set 100 ms **only together with** a cheap "has the capture grown?" check (Windows captures into
  memory/WASAPI buffers or a WAV — check `JVoice.Core/Audio/StreamingTranscriptionSession.cs` and the
  capture class; skip the tail read + RMS when no new samples arrived). The speculative tail (§5.3)
  relies on this cadence to notice a pause within ~0.1 s.
- Verify: `LatencyProbe` / log lines show chunk decodes starting ≤ 100 ms after a cut; CPU idle while
  recording unchanged.

### 5.3 Speculative tail decode — MISSING (P1)
**What it fixes.** Every dictation paid ~1 s between the stop press and the paste, because the tail
(everything not yet chunked, up to 25 s) was decoded only after the press. People almost always pause
before pressing stop.

**Mac behaviour** (`Sources/JVoice/Services/Transcription/StreamingTranscriptionSession.swift`,
`ChunkPlanner.swift`; copies in `docs/mac-reference/src/tour-opacity/`):
1. On every poll, compute `trailingSilence = ChunkPlanner.trailingSilenceSamples(pending)`:
   walk backwards from the end of the pending audio in **0.1 s** windows; stop at the first window whose
   RMS ≥ `silenceRMSFloor`; return the number of silent samples at the end.
   ```
   int TrailingSilenceSamples(short[] s, Config c, double probeSeconds = 0.1) {
       int step = Math.Max(1, (int)(probeSeconds * c.SampleRate));
       int end = s.Length;
       while (end > 0) {
           int start = Math.Max(0, end - step);
           if (Rms(s, start, end) >= c.SilenceRmsFloor) break;
           end = start;
       }
       return s.Length - end;
   }
   ```
2. If `trailingSilence ≥ AppTimings.speculativeTailPause` (**0.4 s**) and no speculation is running for this
   audio, start decoding the pending audio *now* (`speculation`), remembering the sample index it
   decoded up to (**decodedEnd**).
3. On the stop press, `finish()`: if a speculation exists and **no speech exists after its decodedEnd**
   (everything after it is below the silence floor), use its text — zero post-stop decode. Log
   `speculative tail HIT`.
4. **Validity is anchored at the decoded end** (2026-09-23 fix): drop the speculation only if there is
   *speech past the audio it decoded*. Do NOT drop it because the measured "speech end" moved — the
   trailing-silence probe jitters on breaths near the floor (live: jumps of up to 1.8 s with nothing new
   said, which restarted the decode up to 5× in a row). Log `speculative tail dropped — speech resumed`.
5. If a normal chunk cut lands inside the same pause, **reuse** the speculation as that chunk's decode,
   but only if everything between its decodedEnd and the cut is silent (the chunk planner cuts at windows
   that are quiet only *relative to the chunk's peak*, so soft speech can sit there).
6. A speculation that decoded **empty** goes straight to local recovery (§5.6) — decoding the same audio
   again alone would say the same.
7. Cancelling a dropped speculation must stop the decode promptly (whisper.cpp: use the abort callback /
   `CancellationToken` that Whisper.net exposes) and decodes must never overlap (one decode at a time).
   Measured on the Mac: ~9 in 10 speculations are dropped (~11 s of accelerator time per dictation-minute)
   but the latency cost is ~0 because a cancelled decode stops at the next token.

**Windows today:** no speculation (grep `Speculat` finds nothing). `StreamingTranscriptionSession.cs`
decodes the tail after `Finish`.
**Build:** add the pure helper to `JVoice.Core/Audio/ChunkPlanner.cs`, add the speculation state to
`JVoice.Core/Audio/StreamingTranscriptionSession.cs`, the constant `SpeculativeTailPauseMs = 400` to
`AppTimings.cs`. Keep Windows' own guarantees (§7 #39 tail coverage, §7 #41 silent-chunk decode) intact:
a speculation is just an early decode of the same tail with the same guards.
**Tests** (mirror the Mac's `scripts/verify-streaming.sh` scenarios 9–12, 17–18 with a mock decoder):
- tail ends in ≥ 0.4 s silence, stop pressed, nothing new → no decode after `Finish`, text = speculation;
- speech resumes after the speculation → speculation dropped, normal tail decode;
- breath/noise that moves the measured speech end but adds no samples above the floor past decodedEnd
  → speculation kept;
- chunk cut inside the pause, silent between decodedEnd and cut → reused (decoder called once);
- soft speech between decodedEnd and the cut → not reused;
- speculation decodes empty → local recovery path.
**Verify live:** `BenchRunner --stream --realtime` (add it if missing, §5.7) on a clip that ends with 1.5 s
of silence → log shows `speculative tail HIT`, post-stop ≈ 0.

### 5.4 An in-flight chunk decode survives the stop press — check
Mac bug: `finish()` cancelled the poll task, WhisperKit threw on cancellation inside the running chunk
decode, the session failed, and the whole 96 s dictation was re-decoded (6.6 s). Fix: chunk decodes run
as their own task that `finish()` **awaits**; only `cancel()` (abandoned recording) cancels them.
Windows: check `StreamingTranscriptionSession.cs` — lines ~217–222 return on `ct.IsCancellationRequested`
("re-cover via finish/fallback"). If `Finish()` cancels the token that a running chunk decode uses, the same
bug exists. Required behaviour: `Finish()` must await the in-flight chunk decode to completion and use
its result; only `Cancel()` (recording discarded) may cancel it. Test: mock decoder that takes 500 ms,
call `Finish()` 100 ms into it → exactly one decode call for that chunk, no whole-file fallback.

### 5.5 Spare recorder — PARTIAL, low priority
Mac: after every stop (and at launch) it creates and prepares the next recorder, so a press only pays
`record()` (~60 ms instead of ~90–130 ms). Preparing binds no device. A press that switches away from a
Bluetooth mic opens a fresh recorder after the switch (65b63ae).
Windows: capture startup is already prewarmed (§7 #49, `Prewarm` in `VoiceCoordinator`/`App.xaml.cs`).
Only do more if `LatencyProbe` shows MicStarted > ~60 ms. Never open the device early (Bluetooth HFP, §2).

### 5.6 Local recovery of a failed chunk — MISSING (P1)
**What it fixes.** One bad chunk (decode error or empty result on non-silent audio) made the whole
dictation re-decode from scratch: 52 s dictation, 9.8 s after stop. After: 0.5 s.
**Mac behaviour** (`StreamingTranscriptionSession.recoverLocally`):
- Keep every piece decoded before the failed chunk.
- Re-decode only from the start of the **last kept piece** (so the failed audio is heard in context; at
  least 15 s of preceding audio) to the end of the recording, with the whole-file decode options, and
  replace that last piece with the result.
- Fall back to the whole-file decode only if: there is no kept piece; the recovery region would exceed
  **70 %** of the recording (`maxRecoveryFraction` — it would cost what the whole file costs); or the
  recovery is also empty.
- Data-loss invariant (unchanged): a non-silent chunk is never dropped.
**Also (soft audio, same commit):** a decode started during a pause is not thrown away when a breath
flickers around the silence threshold; a chunk may not skip soft audio between that decode and the next
cut.
**Windows today:** `StreamingTranscriptionSession.cs` doc comment (lines 12–29) and lines 144–165,
217–236: every failure → `null` → whole-file fallback.
**Build:** add `RecoverLocally(failedIndex)` in `JVoice.Core/Audio/StreamingTranscriptionSession.cs`, fed
by a `recover(samples)` delegate the engine supplies (`WhisperNetTranscriptionEngine` — "decode this
sample array with whole-file options"). Keep Windows' extra guards (tail coverage) on the recovered text.
**Tests** (Mac `verify-streaming.sh` scenarios 13–16, 19–20): failed middle chunk → one recovery decode
covering [start of previous piece, end]; no previous piece → whole-file; region > 70 % → whole-file;
recovery empty → whole-file; empty speculation → recovery.

### 5.7 Bench flags — PARTIAL
Mac `--bench <wav>` gained: `--repeat N [--idle S]` (decode N times, sleep S s between: separates cold
vs warm and prompt vs no-prompt cost), prints `prompt tokens: N` (each custom word costs its tokens + a
comma; ~9 ms per token per decode on an M3), applies the Developer Terms pack like the app,
`--stream --realtime` (replay at 1× with the app's poll cadence + speculation, printing session events),
`--no-math` (skip Math Notation). Windows: `windows/JVoice.App/Whisper/BenchRunner.cs` — add whichever are
missing; `--stream --realtime` is needed to verify §5.3 without a microphone.

---

## 6. Accuracy, text and app behaviour

### 6.1 Spoken maths is not a loop — MISSING (P1, loses text today)
**Symptom (Mac, 2026-09-23):** "26 times 26 times 26 times 10 times 10 times 10", "minus 3 minus 3
minus 3" was judged a decoder loop: cut from the paste AND the audio decoded a second time. When a whole
chunk was maths it came back empty and forced the whole-file fallback. The Mac notes say the Windows
`RepetitionGuard` has **the same rule** ("Windows port: has the same maths-deleting RepetitionGuard rule").
**Mac rule** (`Sources/JVoice/Services/Transcription/RepetitionGuard.swift`, constants):
- `minLoopTokens 8`, `tailWindow 12`, `densityThreshold 0.7`, `minRepeatCount 3`, `nonLoopyTolerance 1`
  (unchanged, as Windows).
- NEW: a **maths token** (`isMathToken`: a number, a single letter, a number word, or a spoken operator
  from `mathWords`) counts as a loop token on repetition alone only if it occurs **≥ 8 times within the last
  24 tokens** (`mathRepeatWindow 24`, `mathMinRepeatCount 8`). A stuck decoder repeats until its token
  budget runs out, so real loops always pass this.
- NEW safety net `trailingPhraseLoop`: a transcript that **ends** in one exact phrase of ≤ 12 tokens
  (`maxLoopPhraseTokens`) repeated ≥ 6 times (`minPhraseRepeats`) is a loop whatever its tokens
  ("page 1 of 10, page 1 of 10, …").
- Windows `PhraseLoopGuard` already exempts pure-maths phrases (needs 12 repeats) — keep that.
**Build:** `windows/JVoice.Core/Text/RepetitionGuard.cs` (`IsDegenerate`, line ~44) — port `IsMathToken`,
the `mathWords` set, the 8-of-24 rule and `TrailingPhraseLoop` from the Mac file
(`docs/mac-reference/src/tour-opacity/Services/Transcription/RepetitionGuard.swift`), plus its tests
(`Tests/JVoiceTests/RepetitionGuardTests.swift` via `git show origin/feat/tour-opacity:…`; the Mac
`scripts/run-logic-tests.sh` has a loop fuzz). Must-pass: the two examples above are kept verbatim;
"page 1 of 10" ×6 at the end is a loop; a real 40× "the the the" is still a loop.

### 6.2 Witness guards — DONE (origin Windows), deltas to check
The Mac 2026-09-24 guards were ported **from** Windows: `PhraseLoopGuard`, `SparseTranscriptGuard`
(≥ 10 s and < 4 chars/s → witness adopted if ≥ 2× the text), `SilenceHallucinationGate`,
`RepetitionGuard.isVocabularyList`, `NonSpeechAnnotation`, one policy `RegurgitationRecovery.decode`
(prompted decode first; on a failure mode, ONE prompt-free witness decode decides; vocab-recital and
quiet cases keep the prompted text only if the witness shares a word with it, after phonetic respelling,
else ""). Differences to be aware of (no action unless a bug shows):
- Mac `SilenceHallucinationGate` trigger is peak 0.3 s-window RMS **< 0.05** (provisional, uncalibrated);
  Windows' is `QuietRmsTrigger = 0.004` (calibrated on David's quiet mic). **Keep Windows' value.**
- Mac logs every witness decision as one line `Guard witness(<reasons>) audio=… peak=… chars prompted=… witness=… → <verdict>`
  (numbers only). Add the same line on Windows if it isn't there — it's the calibration data.
- The Mac drops the bare lowercase token `you` (Whisper's answer to < 1 s of hum) — §6.4.

### 6.3 Custom words, fillers, Developer Terms — MISSING (P1)
From Mac `b0bb390` (`PhoneticMatcher.swift`, `TextProcessor.swift`, `DeveloperTerms.swift`; tests
`Tests/JVoiceTests/PhoneticMatcherTests.swift`, `TextProcessorTests.swift`, `DeveloperTermsTests.swift`):
1. **Never swallow the word before a custom word.** "I deployed 2 Vercel apps" kept "Vercel" but lost "2".
   The sound-alike window must start AT the candidate word, not one word earlier.
2. **Keep possessives:** "vercel's" → "Vercel's" (match the stem, re-append `'s`).
3. **Never join across a comma** (a multi-word match may not span punctuation).
4. **Edit distance ≤ 1** (was 2): "verse"/"vessel" → Vercel and "Obama" → Ollama were false corrections.
   Windows `windows/JVoice.Core/Text/PhoneticMatcher.cs` lines 77–83 still allow `letterDistance <= 2` with
   key distance 1 and `Math.Max(1, len/3)` — port the Mac thresholds exactly (read the Mac file).
5. **The custom word's plain lowercase key is added** to the correction dictionary (Mac bug since
   `5d60aca` — check Windows `UserCorrections.cs`/`TextProcessor.cs` does add it).
6. **Filler removal** must not eat "ER" (emergency room), "err", "Uh-oh", "Mm-hmm". Windows regex
   (`TextProcessor.cs:159`): `\b(um+h?|uh+|er+|a+h+|hmm+)\b[,.]?\s*` with IgnoreCase — it eats all four.
   Port the Mac pattern (case-sensitive handling of "ER", `er` only as a standalone lowercase filler of
   length ≥ 2 "erm/er" per the Mac file, and hyphenated interjections protected).
7. **Developer Terms**: remove the everyday-English keys the Mac removed — "my sql", "no sql", "fast api",
   "restful", "uri", "keyboard shortcuts" (David approved). Windows `JVoice.Core/Text/DeveloperTerms.cs`.
8. ".NET"/".env" custom words no longer gain an extra dot; Very Casual keeps "$1,000,000"; Formal adds no
   period after a closing quote/colon/ellipsis. Check each on Windows with a test; port if different.
**Tests:** copy the Mac cases (input → expected) from the three Mac test files into xUnit.

### 6.4 "J-Voice" and the lone "you" — check (P2)
- `TextProcessor.correctionDictionary` gained `J-Voice → JVoice` (Whisper hyphenates under a cased
  prompt).
- `removeWhisperHallucinations` drops the bare, lowercase, unpunctuated `you` (Whisper's answer to < 1 s of
  hum) — case-sensitive so a real "You." survives. It runs on the **raw** decode in both paths
  (`cleanRawDecode`), so near-silence reads as an empty decode, which triggers the witness/whole-file
  fallback instead of pasting an artifact.
Windows: grep `TextProcessor.cs` for both; add with tests if missing.

### 6.5 Dictation lifecycle, paste and audio fixes — PARTIAL (P1)
From Mac `8ea5088` (`CoordinatorDecisions.swift`, `PasteManager.swift`, `RecordingManager.swift`,
`SilentCaptureDetector.swift`, `VoiceCoordinator.swift`):
1. **A second press between the stop press and the paste never cancels the in-flight transcription.**
   Pure decision `CoordinatorDecisions.pressAction(isRecording:…)` → `.start | .stop | .stopOnceOpened | .ignore`;
   while a transcription is in flight → `.ignore` (logged). Windows §7 #44 (`CoordinatorDecisions.cs:48–54`)
   blocks a *start* within a window after stop (key auto-repeat). Check that *any* press (hotkey, tray menu,
   pill click) while transcribing is ignored, not only auto-repeat; port `PressAction` if not.
   `.stopOnceOpened`: a stop press while the mic is still opening ends the recording as soon as it opens.
2. **Refused paste keeps the text**: no Accessibility on Mac ≈ on Windows `SendInput` blocked (UIPI — target
   runs elevated) or the target rejects Ctrl+V. The text goes to the clipboard AND Recent Transcripts, and
   the pill says so, instead of being lost.
3. **Clipboard restore** is per item, and skipped if the user copied something during the 0.3 s restore
   window (Windows: compare `GetClipboardSequenceNumber()` before/after — `Paster.cs` already snapshots;
   check for the "user copied meanwhile" skip).
4. Clipboard-only mode shows "Copied" (not "Pasted").
5. Audio: the Bluetooth redirect targets only physical inputs (never virtual devices like VB-Cable);
   digital-silence capture names the device in the error; a recorder failing mid-recording shows
   "Recording was interrupted"; quitting mid-transcription deletes that dictation's audio file; settings
   load warnings reach the user.
Tests: `PressAction` table (pure) + paste-failure path with a fake paster.

### 6.6 Shortcut recorder rules + entry messages — MISSING (P1)
Mac (`UI/ShortcutCapturePolicy.swift`, `ShortcutCapturePolicy+AppKit.swift`, `SettingsEntryPolicy.swift`,
`Components/InlineNotice.swift`; copies in `docs/mac-reference/src/tour-opacity/UI/`):
- While recording a chord: Esc or Tab cancels; Delete/Backspace clears; Shift alone is refused; F-keys may
  be bare; **every other key needs at least one real modifier**. Bare arrow / navigation / keypad keys are
  refused (they were being stored as global hotkeys).
- Refused with a stated reason: **system-reserved chords** (Mac: `CopySymbolicHotKeys` — ⌘Space, ⌘⇧3…),
  **app-menu chords** (⌘C, ⌘V, ⌘Q…), and a chord **already used by the other action** (Toggle
  Recording vs Undo Last Paste).
- While the recorder listens, both global hotkeys are unregistered (else the chord is swallowed
  system-wide) and re-registered when the window loses focus/closes.
- Custom Words / App Modes: a rejected entry stays in the text field with the reason shown under it
  (inline notice), instead of silently clearing.
Windows (`windows/JVoice.App/UI/HotkeyRecorder.cs`): accepts any key + modifiers, waits for a
non-modifier. Build a pure `ShortcutCapturePolicy` in `JVoice.Core` with the Windows equivalents:
- reserved (refuse): Win+L, Win+D, Win+E, Win+R, Win+Tab, Win+Space, Win+V, Win+Shift+S, Alt+Tab,
  Alt+F4, Ctrl+Alt+Del, Ctrl+Shift+Esc, Ctrl+Esc, PrintScreen, and any chord `RegisterHotKey` fails on
  (that failure itself = "already used by Windows or another app");
- common app-edit chords (refuse): Ctrl+C/V/X/Z/Y/A/S/F/W/Q/N/O/P/T;
- duplicate of the other action (refuse);
- bare keys refused except F1–F24.
Show the reason in the recorder row (inline, secondary text). Tests: a decision table like the Mac's.

### 6.7 Hidden pill must not animate — check (P1 CPU)
Mac: the prewarmed, hidden pill kept animating at 30 Hz from launch to the first dictation (2.3–5.5 % of
a core idle) — fixed by swapping the hidden pill to an idle view. Windows' pill has a generated wave
animation and a `FramePacer`; check with Task Manager that JVoice is ~0 % CPU while idle after launch
(before the first dictation). If not, stop the storyboard/`CompositionTarget.Rendering` handler when the
HUD is hidden or prewarmed.

### 6.8 Settings crash — N/A
Mac-only packaging bug (see §2).

### 6.9 Model download vs compile — N/A
The Mac separates "Downloading model…" from "Preparing model (one-time)…" because Core ML compiles for the
Neural Engine once per model. Keep Windows' states.

### 6.10 Install / update — N/A
Mac got `curl … install.sh | bash` + stable signing so updates keep permissions. Windows has its own
installer and `JVoice.App/Update` (auto-update). Nothing to port. (The Mac README was simplified and the
licence switched to **PolyForm Strict 1.0.0** on `main` — the Windows installer/README should show the
same licence text if it bundles one; check `windows/README.md`.)

---

## 7. Maths — the new engine and the shared notation format

**Background.** Windows had Math Notation first (§7 #48, `windows/JVoice.Core/Math/`: `MathSymbols.cs`,
`MathSpeech.cs`, `MathScript.cs`, `MathSymbol.cs`, `SpokenNumbers.cs`; 130 test cases in
`windows/JVoice.Tests/MathSpeechTests.cs`). The Mac ported it 1:1 (v1.1.1), then (a) fixed seven bugs
found in a bug hunt (the "package"), (b) adopted a **shared output format** that David wants identical
in JVoice and in BetterScreenshot's Capture Text, (c) fixed a failed real dictation, (d) made "sigma" mean
∑. None of this is on GitHub except via this repo's `docs/mac-reference/`.

**The Swift engine to port**: `docs/mac-reference/src/math-format/Math/` — `MathSymbol.swift` (59 lines),
`MathSymbols.swift` (522), `SpokenNumbers.swift` (429), `MathScript.swift` (380), `MathSpeech.swift`
(1,856), `MathProbe.swift` (44). Tests: `docs/mac-reference/src/math-format/Tests/MathSpeechTests.swift`
(390) and `MathSymbolsTests.swift` (312). The C# files map 1:1 by name. **The recommended way is a
careful file-by-file port of the Swift into the existing C# files** (they were ported 1:1 the other way in
September, so structure and names still line up), then porting the tests, rather than re-implementing
from the prose below.

### 7.1 The model (unchanged, both platforms)
- A word becomes a symbol only inside a **run**: consecutive words that all lex as mathematics, ended by
  any ordinary word or punctuation.
- A run converts only when an **activating** construct found its **operands**: an infix relation/operator
  with an operand on both sides, a prefix (√, ∫, ¬) with one after it, or a structural construct (script,
  power, root, fraction, bounds, derivative, limit, absolute value, "n choose k").
- **Weak** items (π, α, %, °, `sin`, brackets, number words, spoken signs) render only inside an
  already-activated run; otherwise they stay words. No activation → input returned unchanged
  (**no-bleed guarantee** — "two times a day", "100 percent sure", "the square root of all evil" paste
  exactly as spoken).
- "start equation … end equation" forces conversion.
- Applied LAST, after `TextProcessor`, only when Settings → Math Notation is on.

### 7.2 The shared output format — `docs/mac-reference/math-notation-format.md` (normative)
Read that file in full; it is the spec (253 lines: principles, characters, constructs spoken → pasted,
where JVoice differed, the "toggle must save time" rule, decisions, verification). The main changes vs
the current Windows output:
- Fractions are **`/` with brackets only where needed**, not `÷` or stacked `½`/`ˣ⁄ₙ`:
  a side gets brackets when it holds a space or an operator; a denominator also when it is a juxtaposed
  product: `12/(2T)`, `(x² - 9)/(x - 3)`, `(sin x)/x`. (`MathScript.SlashFraction`, `NeedsGrouping`.)
- **Products**: a spoken "times" is `×` between numbers and **juxtaposition** between letter terms:
  `6 × 7`, `(n - 1)d`. `·` is ONLY the dot product ("dot", "dot product", "inner/scalar product").
  "times"/"multiplied by" map to an internal marker `*` that is never printed; layout decides at render
  time (`ProductSeparator`; `×` also after an open radical — `EndsInOpenRadical`).
- **Radicals**: `√x`, `√(2x)` (brackets when the radicand is more than one atom) — `Radical`.
- **Functions**: `sin θ`, `sin²θ`, `log₂8`, `sin(x + 1)` — `ApplyFunction` (spaced-function set).
- **Powers of groups**: `(5/6)⁴` — `PowerBase`. Super/subscripts are Unicode, all-or-nothing, with a
  `^(…)`/`_(…)` fallback when a character has no Unicode script form (there is no subscript "b":
  "a subscript b" → `a_b`).
- **Limits**: `lim_(x→0) (sin x)/x`.
- Default without a grouping word: every construct takes the **smallest** reading (`√x + 1`,
  `sin x + 1`, `log₃x + 1`). Grouping words "all over", "the quantity" widen it (§7.3).
- The §3/§4 tables of the format doc and the "Final §3/§4 probe table" at the end of
  `math-notation-progress.md` are the acceptance tests — every row must produce exactly its "after" text.

### 7.3 The engine package (bug-hunt fixes 1–7) + format work — port list
This is the Mac's own **"Windows mirror list"** (`math-notation-progress.md` §"Windows mirror list"),
repeated here. Files: `windows/JVoice.Core/Math/*.cs`, `windows/JVoice.Tests/MathSpeechTests.cs`,
`MathSymbolsTests.cs`.
1. **Step 1 package**: the grouping rule (`Scope`, `Run`, `Parser.subExpression`, rules 1–5 in the
   `Parser` doc comment); bare "to the" is weak + `powerIsUnmistakable` ("I gave 5 to the 3 kids" stays
   words; "x to the 3", "2 to the power of 10" convert); ordinal exponents, lexer step 1b ("10 to the
   fifth" → `10⁵`, "x to the third power"/"x to the 3rd" → `x³`); Whisper's "x" between numbers as a weak
   times (lexer step 4b: "3 x 4 equals 12" → `3 × 4 = 12`); the article-pair rule ("I'm bringing a plus
   one" stays words); `MathSymbols.weakOperators = ["/"]` ("5 per 100,000" stays words); "more than" /
   "is more than" removed from `>` ("y is 5 more than x" stays words); the auto-closed "the probability
   that" bracket closes before a second relation (`P(X ≤ 3) = 0.65`); "over" takes a following
   choose/factorial; **smart grouping** (David-approved, deliberately differs from the old Windows
   output): choose / factorial / over / "P of" / "f of" / "given" take the whole following expression —
   "n choose n minus k" → `C(n, n - k)`, "n plus k minus 1 choose k" → `C(n + k - 1, k)`, "the probability
   of A given B" → `P(A ∣ B)`, "f of n minus 1" → `f(n - 1)`.
2. `MathScript.cs`: the layout helpers — `NeedsGrouping(operand, leadingSign, slash)`, `IsWrapped`,
   `IsApplication`, `IsNumeric`, `SlashFraction`, `IsJuxtaposedProduct`/`TopLevelFactors`, `Radical`,
   `ApplyFunction` (+ the spaced-function set), `ProductSeparator`, `PowerBase`, `ScriptOperand`.
   **Scan code points, not UTF-16 chars** (superscripts/∑ etc. are outside the BMP in places — use
   `Rune`/`StringInfo`).
3. `MathSymbols.cs`: "times"/"multiplied by" → `*` (the times marker); `·` keeps only dot / dot product /
   inner / scalar product; new `ActivatingPostfixes = {"!", "!!"}`; reserved phrases += "all over",
   "the quantity". `MathSymbol.Activates` += activating postfixes.
4. `MathSpeech.cs`: keywords "all over" (`AllOver`), "the quantity" (`Quantity`), "tends to" → its own
   `TendsTo` (limits accept it too); lexer 1c (derivative ratio "d y by d x" → `dy/dx`: `Differential`,
   `EndsOperand`); "to the" + "quantity" → strong power; lexer 4b emits the times marker; `Expr`:
   `Part.Relation`, `PushInfix(…, relation)`, `SideStart`, `GroupTrailingOne`, render-time times layout,
   ∠/△ tight; `Scope.Side` (`Reaches` = not a relation, `Allows` = all but AllOver/TendsTo, implicit
   products like `.Product`); step(): algebraic "divided by" reads its denominator like "over"
   (`n!/(k!(n - k)!)`), `GroupTrailingOne` before a times, postfix activation only at the clean end of the
   run; keyword(): scripts via `TryExponent` (signed, powered) + `PowerBase` + `ScriptOperand`, "over" →
   one slash-fraction operand, AllOver, Quantity, TendsTo (`CanTend`), "of" after a `%`, DerivRatio;
   `PowerIsUnmistakable` skips a leading minus; tryOperand(): `Radical` for roots and the √ prefix, marked
   function names (`FunctionMarks`: "f prime of x", "f inverse of x"), `ApplyFunction` with a
   script-operand argument and ln/powered-function activation ("natural log of …", "sine squared θ"),
   `Quantity(k)`; `Group` stops an unclosed bracket at "all over".
   New structural activators (2026-09-29), each checked against a bleed list of ordinary sentences using
   its own words: "d y by d x"; "f prime/inverse of x" (single non-weak letter + mark + "of" + operand);
   "natural log of …" and a powered function; a factorial ONLY where it ends the sentence ("a 2 by 2
   factorial design" is English); "tends to" ONLY after a lower-case variable or `f(x)` ("plan B tends to
   5 percent" is English). "all over" and "the quantity" are WEAK.
5. **2026-09-29 dictation fix** (§7.4).
6. **"sigma" = ∑** (§7.5).
7. Tests: take expectations from the Swift test files — the "shared notation format" block and the new
   leave-alone lines in `MathSpeechTests.swift`; the "times"/"dot" lookups and four updated conversions in
   `MathSymbolsTests.swift`. Existing Windows cases whose expected output changes because of the new
   format (÷ → /, · → × or juxtaposition, stacked fractions → slash) must be **updated to the new format,
   not kept** — the format doc is the authority.

### 7.4 "root of … Kx … sigma of" — David's failed dictation (382da82)
Keyword "root of" (lexed weak; a weak root reads a powered radicand and activates only when it took a
power; `keyword()` does not activate a weak root); `Item.Glued` + lexer step 5b (`IsGluedVariables`, the
two-letter word list, `IsInfix`, `StartsScript`) + `GluedBase` suppressing activation in the operator
branch, scripts and "squared"/"cubed" (so Whisper's run-together variables like "Kx" behave as a product
without turning English two-letter words into maths); Greek letter + "of" → function application
(`IsGreekLetter`); the limit target is read with `allowApply: false`; `MathScript.EndsInOpenRadical` →
`×` in `ProductSeparator`. Tests: the "David's failed dictation" block and the root/sigma/two-letter
leave-alone lines in `MathSpeechTests.swift`; the exact dictation and its expected output are in
`math-notation-progress.md` §"Fix — David's failed dictation".

### 7.5 "sigma" is the sum sign (ede7a2d)
`MathSpeech.cs` lexer step 2b + the weak-∑ check in `BigOperator` (bare "sigma" parses like "sum": weak
without "from"); `MathSymbols.cs` removes the bare "sigma" key, adds "lowercase sigma" / "small sigma" /
"lower case sigma" → σ, reserves "sigma". `MathSymbolsTests.cs`: "sigma squared equals the variance of x"
becomes "lowercase sigma squared …".

### 7.6 The toggle must save time (format doc §5)
David's requirement: switching Math Notation **off** must make dictation measurably faster. On the Mac,
`MathSpeech.convert` is pure text processing (~0.04 ms/dictation), so off = no maths code runs at all
(the bench's `--no-math` does the same). On Windows: make sure that with the toggle off, no maths code
runs (check `VoiceCoordinator.cs` gates the call, not just the result). Don't claim "off is faster" in the
UI unless a bench shows it.

### 7.7 Acceptance (from the Mac process)
- All updated `MathSpeechTests`/`MathSymbolsTests` pass; converting twice changes nothing (idempotence).
- **No-bleed sweep**: ordinary sentences must come back byte-identical. The Mac used 494 everyday
  sentences + 55 sentences using the new trigger words; those corpora are gitignored on the Mac and not
  here — build a Windows equivalent from David's Recent Transcripts (Windows keeps them — see
  `docs/HANDOFF-WINDOWS.md` §7 #26 for where) plus the leave-alone lines in the Swift tests, and read every
  changed line. A new ACTIVATING vocabulary entry (relation/operator/prefix) is the only thing that can
  turn a sentence into an equation — everyday words may only be added as weak kinds.
- Linear time on pathological inputs (the Mac `stress.py` timed long runs of operators/numbers).
- `MathProbeRunner.cs` (`--math-probe "<text>"`, one per stdin line → `CHANGED|before|after` or
  `same|text`) — keep it in step so you can sweep a corpus.

---

## 8. Native look (Mac v1.1.4) — MISSING (P1, biggest UI job)

**David's words (Mac):** "it's all black", "little dots on all the different things", "doesn't look like a
Mac native app". The Mac replaced the 2026-06-27 monochrome look (which Windows still has — pure-black
`Settings.PanelBg #000`, `SectionBg #0E0E0E`, dots in `DarkSection` headers, text-free white-on-black pill)
with the native look of David's MacStats app. The same applies to all three of David's apps (MacStats,
JVoice, BetterScreenshot); BetterScreenshot's Windows doc (`docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 9 in
the better-screenshot repo) has the same brief for its port — keep both Windows ports consistent.
On Windows, "native" means **Windows 11 Fluent**: Mica/Acrylic backdrops, Segoe UI Variable, system
light/dark, accent colour, rounded corners, standard controls.

### 8.1 The rules (from `docs/mac-reference/briefs/UI.md` and `docs/mac-reference/design-language/README.md` + `jvoice-native-redesign.md`)
- System materials behind content — **never opaque black/white/grey fills**.
- Surfaces are **tints of the text colour** over the material: card fill = primary text colour at **4 %**,
  card hover 8.5 %, pressed 12 %; input fill 6 %; card hairline = primary at **8 %**, **0.5 pt** wide
  (1 physical px on Windows at 100–150 % scaling); row hover 7 %.
- Radii: card **10**, row 6, small button 6 (height 24). Continuous corners on Mac → plain rounded on WPF.
- Text uses **styles**, not fixed tiny fonts, no letter-spacing: section labels = caption2 semibold
  secondary; row labels = body/callout primary; notes = callout secondary. Windows mapping: Segoe UI
  Variable — Caption 12, Body 14, Body Strong 14 semibold, Subtitle 20 semibold; secondary text =
  `TextFillColorSecondary`.
- Colour only where it means something: red = stop/destructive, green = done, orange = warning,
  blue/accent = model work. **No decorative dots, no glows, at most one soft shadow.**
- **Appearance picker**: segmented **System / Light / Dark** at the top-right of Settings. **System** is the
  default and follows the OS. Migration: a stored old default dark → System; an explicit Light is kept.
  Stored as a NEW settings key `appearance` (schema version unchanged so older builds still read the
  file); the legacy `theme` field is still written (dark/light only) for older builds.
  Windows: read `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`
  (0 = dark) and watch `SystemEvents.UserPreferenceChanged` (category General) or `UISettings.ColorValuesChanged`;
  apply to each window (resource dictionary swap + `DWMWA_USE_IMMERSIVE_DARK_MODE` = 20 for the title bar).
  Add `Appearance` (`System|Light|Dark`) to `windows/JVoice.Core/Models/SettingsState.cs` +
  `SettingsStateJson.cs` with the same migration and tests.

### 8.2 Windows backdrop strategy (decide once, apply to Settings, Welcome, tour tag, pill)
- Windows 11 22H2+: `DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE (38), DWMSBT_MAINWINDOW (2)=Mica
  | DWMSBT_TRANSIENTWINDOW (3)=Acrylic)`, with `WindowStyle=None`/`AllowsTransparency=False`,
  the WPF window background transparent, and `DwmExtendFrameIntoClientArea(-1)`. Settings + Welcome =
  Mica-like ("a softly see-through background, the desktop shows through"); the Mac used `.popover`
  (a lighter blur of what's behind), so **Acrylic (3) matches the Mac more closely** — try both at the
  default opacity and pick the one closer to the Mac screenshots (see §12 for how the Mac makes them).
- Rounded window corners: `DWMWA_WINDOW_CORNER_PREFERENCE (33) = DWMWCP_ROUND (2)`.
- Windows 10 / backdrop unavailable / "Transparency effects" off: fall back to the solid
  `windowBackground` colour (the Opacity backing at alpha 1) — never a see-through window without blur
  (text contrast would collapse).
- The **pill** is a small layered, click-through-free, no-activate topmost window
  (`WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST`). DWM system backdrops apply to layered/borderless
  windows inconsistently; if Acrylic on the pill is unreliable, draw the pill as: a rounded capsule filled
  with the dark window colour at the pill backing alpha (§9) over a **blur you don't have** — i.e. accept
  "tinted glass without blur" only if contrast checks (§9.4) pass; otherwise raise the backing. Test at
  the stretched 1600×1080 resolution with `HudScale`.

### 8.3 Settings window layout (Mac)
- 700 pt wide, **2 columns** of cards; **Stats full-width on top** (MacStats stat pattern: big number +
  caption, three cells — words dictated, speaking speed WPM, time saved).
- Left column (controls): Whisper Model · Processing · Voice Style · Language · App Modes · Keyboard
  Shortcut. Right column (your data): Recent Transcripts · Custom Words · Tours & Tips. Appearance card
  (with Opacity, §9) at the bottom.
- Card: 0.04 fill, 0.5 pt hairline at 0.08, radius 10; section label caption2 semibold secondary, **no dot**.
- Native controls: small switches, segmented pickers sized to content and left-aligned, native sliders,
  bordered buttons; footer **Restore Defaults…** and **Quit** as small red (destructive) buttons.
  Restore Defaults confirms with a native alert (warning icon, "Restore Defaults" destructive + Cancel).
- List rows (transcripts, words, app rules) reveal their actions (copy / remove) on hover over a 0.07
  highlight. Recent Transcripts: read-only list of up to 30; hover → Copy / delete; "Clear All".
- Settings' scrolling content never slides under the title bar.
Windows today: 960-wide, three-column masonry, pure black, sized to fit David's 1080-tall desktop
(`SettingsWindow` clamps `MaxHeight = WorkArea.Height − 16` so the close button can't go off-screen) —
**keep that clamp and the reason**. Recommendation: keep three columns if two would exceed the work area
at David's resolution; restyle the cards/controls/colours to the rules above; drop the header dots
(`DarkSection` → a new `Card` control with a plain caption label); add the Appearance card and the Tours &
Tips card. The Windows-only cards (Corrections, Automatic Updates, Version) stay.

### 8.4 The glass pill that hugs its content and morphs (Mac 33d8a21)
Constants (`UI/HUDLayout.swift`): capsule height **56**, corner **28** (half height); recording/
transcribing capsule min width **240**; status pills hug their text, wrapping (≤ 2 lines) beyond **360**;
transparent margin **22** around the capsule for its shadow; capsule sits **64** above the bottom of the
visible work area (above the Dock → above the taskbar).
- ONE capsule wraps whichever pill is showing; each pill reports its natural size. Recording →
  transcribing → Pasted **resizes the capsule** with a subtle, no-bounce spring (`.snappy(duration: 0.3)` ≈
  WPF: 300 ms `CubicEase EaseOut` on Width) while the contents **cross-fade**. The window first grows to
  fit both capsules for the morph, then shrinks to the new one **0.35 s** later (`morphSettleDelay`);
  content is bottom-anchored and centred so nothing jumps.
- The **first show and the hide never animate** (latency contract): only a visible pill replacing a
  visible pill animates.
- **Recording / transcribing**: the J mark · waveform bars (3 pt wide capsules resting at 2 pt tall = a
  calm flat line; bar opacity from secondary → primary with level) · a **red stop square** (no label).
  Windows keeps its *generated* wave (David prefers a steady flow over mic-reactive bars — Windows §7 #23);
  only restyle it (resting flat line, primary/secondary colours).
- **Downloading / preparing / done ("Pasted") / copied / error / notice**: an icon in the state's accent
  colour + callout text (no badge circle). `notice` = a neutral info pill used for tour confirmations.
- One soft shadow (radius 10, 4 pt down) with the capsule cut out of it, so nothing shadows through the
  translucent body.
- Colours: text = primary label colour of the pill's (dark) appearance; red stop stays red; accent roles:
  done green, warning orange, model work blue, error red.
Windows today: text-free monochrome pill (white bars on black, a successful paste is **silent**, errors
are the only text). The Mac now shows "Pasted" etc. Ask David once whether Windows should keep the silent
paste (it was a deliberate Windows choice) — if unsure, follow the Mac.
Build: `windows/JVoice.App/UI/HudView.xaml(.cs)`, `HudWindow.cs`, a `HudLayout` constants class; keep
`HudScale` (all constants × scale). Verify: frame-by-frame capture of a recording → transcribing →
Pasted sequence; no jump, no animation on first show; crisp at the stretched resolution.

---

## 9. Opacity setting (Mac d060a72, `feat/tour-opacity`) — MISSING (P1)

Identical setting in all three apps (MacStats, JVoice, BetterScreenshot); shared spec: `docs/mac-reference/design-language/opacity-setting.md`.
- **UI**: Settings → **Appearance** card → **Opacity**: a slider labelled *Transparent* (left) … *Opaque*
  (right) + a **Default** button. Live (every window and the pill update while dragging).
- **Storage**: `jvoice.app.uiOpacity` (Double, 0…1, default **0.5**, a separate key — not inside the settings
  blob on the Mac). Windows: add `UiOpacity` (double, default 0.5) to `SettingsState` (clamp to 0…1;
  missing/NaN → 0.5).
- **Mapping** (`UI/UIOpacity.swift`, pure — port 1:1 to `JVoice.Core`): each surface = its backdrop +
  a **backing** of the window background colour (follows light/dark) at `backingAlpha`, piecewise-linear
  0 → 0.5 → 1:

  | Surface | alpha at 0 | at 0.5 (default) | at 1 |
  |---|---|---|---|
  | window (Settings, Welcome, tour tag) | 0 | **0.35** | 1 |
  | pill | **0.45** (readability floor) | **0.62** | 1 |

  ```csharp
  public static double BackingAlpha(double value, Surface s) {
      var (t, m, o) = s == Surface.Window ? (0.0, 0.35, 1.0) : (0.45, 0.62, 1.0);
      double v = double.IsFinite(value) ? Math.Clamp(value, 0, 1) : 0.5;
      return v <= 0.5 ? t + (m - t) * (v / 0.5) : m + (o - m) * ((v - 0.5) / 0.5);
  }
  ```
  Tests: `BackingAlpha(0.25, Window) == 0.175`, `(0.75, Pill) == 0.81`, `(-1, …)` = value at 0,
  `(NaN, …)` = value at 0.5.
- **Readability floor (shared spec)**: at the default, primary text ≥ 4.5:1 (Mac measured: pill 5.1:1 over
  a white page in Dark; Settings 5.8:1); at 0, primary text must stay ≥ 3:1 (pill 3.5:1 — that is why its
  floor is 0.45). Measure on Windows with screenshots over a **white** page, a black page and a bright
  wallpaper at 0 / 0.5 / 1 (method: body colour = most common colour in a box; text = the pixel differing
  most). If the Windows backdrop is more transparent than the Mac's, raise the alpha anchors until the
  same ratios hold — the ratios are the contract, the alphas are Mac-calibrated.
- "Restore Default Settings…" does NOT reset Opacity on the Mac (known follow-up); the card's Default does.
- Implementation shape on the Mac: a single live store (`UIOpacityStore.shared`, observable) that every
  surface subscribes to. Windows: a singleton `INotifyPropertyChanged` or a `DynamicResource` brush whose
  alpha is updated app-wide.

---

## 10. First-run Welcome window + guided tours + ⓘ (Mac v1.1.3 + 2026-09-30 polish) — MISSING (P1)

Full Mac design: `docs/mac-reference/briefs/Tours.md` (read it) and `UI.md` (WelcomeWindow section);
sources `docs/mac-reference/src/tour-opacity/Tours/` (Kit = engine, tag overlay, ⓘ; `TourCatalog.swift` =
every step). JVoice's tours were adapted from BetterScreenshot's TourKit — **the BetterScreenshot Windows
port will build the same kit** (`docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 7 in the better-screenshot repo has
WPF notes for the tag overlay: click-through, no-focus windows). Build it once as clean C# and reuse.

### 10.1 Who gets tours — the "only the first time" guarantee (do not weaken)
- The **audience** (`new` | `existing`) is decided ONCE, at launch, **before anything writes settings**
  (on the Mac `SettingsStore.init` writes the blob on a fresh install, so classifying later would call
  everyone existing), and stored; never recomputed.
- `existing` if ANY of: any non-tour setting already stored; microphone permission already granted
  (Mac also: Accessibility granted); running from a dev build path. **Doubt → existing** (a missed new
  user is harmless, a nagged one isn't).
  Windows equivalents: settings file exists (`%APPDATA%\JVoice\…` — check `Platform/Persistence`), or
  Recent Transcripts/stats exist, or a downloaded model exists, or the Windows microphone privacy consent
  for the app is already "Allow" (`HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged\<path with # for \>` → `Value = Allow`), or running from `bin\Debug`.
  **Upgrading users must be `existing`** — David's own PC must never see the Welcome window.
- New users who haven't answered get the **Welcome window** at launch. Closing it on either page = "No
  Thanks" (JVoice launches at login; an unanswered window would come back every login); quitting with it
  open asks again next launch.
- A tour auto-starts only if `firstUseToursEnabled == true` (absent = off) and its version isn't in
  `toursSeen`. Existing users: no window, no automatic tour, ever (also not after a version bump).
- Everyone can run any tour on purpose: tray menu → Help & Tours, the ⓘ, Settings → Tours & Tips.
- Persisted keys (nothing else): `tourAudience`, `tourQuestionAnswered`, `firstUseToursEnabled`,
  `toursSeen` (tour id → version), `toursPaused` (tour id → step index to resume at).

### 10.2 The Welcome window
Same translucent material as Settings, the real app icon, large native buttons (primary + secondary).
- Page 1 — **permissions**: Microphone + Accessibility with live status (Windows: Microphone privacy
  status + a "Test" affordance; there is no Accessibility permission on Windows — show the paste target
  note instead, or omit the row).
- Page 2 — **"You're all set!"**: a shortcut cheat sheet (aligned grid built from the LIVE bindings) +
  **"Want a quick tour?"** with **Show Me Around** (primary) / **No Thanks**. Answer sets
  `firstUseToursEnabled`, `tourQuestionAnswered = true`.
- Also opened on page 2 without the question by Help & Tours → Take the Welcome Tour.
- While the Welcome window will show, suppress any launch-time permission prompt — the window asks.
- Anchors: `welcome.shortcut` (the shortcut row), `welcome.tryIt` (the try-it area).

### 10.3 The tours (verbatim — `TourCatalog.swift`)
Copy rules (lint-tested on the Mac; port the lint as a unit test): title ≤ 4 words, body ≤ 20 words, Try
steps start with a verb, one idea per step, plain words; step titles unique within a tour (they are menu
items); `{shortcut:toggleRecording}` renders the user's CURRENT chord (e.g. "Alt+Space"), or "(not set)";
bodies must fit **2 lines at 260 pt** with the longest possible shortcut text (Mac: ⌃⌥⇧⌘F12 — Windows:
"Ctrl+Alt+Shift+Win+F12").

**Welcome tour** (`welcome`, surface Welcome window, started by the app / menu / replay):
1. Explain · anchor `menuBar.icon` (Windows: the tray icon — see 10.5) · **"Your menu bar J"** — "JVoice
   lives here. Click it to start dictating, open Settings or quit." (Windows: title "Your tray icon",
   body "JVoice lives here, by the clock. Click it to start dictating, open Settings or quit.")
2. Explain · `welcome.shortcut` · **"Your dictation shortcut"** — "Press {shortcut:toggleRecording} in any
   app to start talking. Press it again to stop."
3. Try (advances on `recording.started`) · `welcome.tryIt` · **"Try it now"** — "Click into any text box,
   then press {shortcut:toggleRecording} and say something."

**Recording tour** (`recordingPill`, surface pill, trigger = first time the pill is shown):
1. Try (advances on `recording.stopped`) · `pill.controls` · **"JVoice is listening"** — "Speak, then press
   {shortcut:toggleRecording} again or click ■. Your words get typed for you."

**Settings tour** (`settings`, trigger = first Settings window; scroll each anchor into view first):
1. `settings.stats` · **"Your stats"** — "Words dictated, your speaking speed and the typing time you saved."
2. `settings.model` · **"Speech model"** — "Bigger models are more accurate but slower. Everything runs on
   this Mac." (Windows: "…runs on this PC.")
3. `settings.processing` · **"Clean-up options"** — "Drop filler words, turn spoken maths into symbols, and more."
4. `settings.voiceStyle` · **"Voice style"** — "Choose how your text comes out, from very casual to formal."
5. `settings.appModes` · **"App modes"** — "Give an app its own style, like Code in your editor."
6. `settings.shortcut` · **"Your shortcut"** — "Click the shortcut, then press new keys to change it. Esc cancels."
7. `settings.transcripts` · **"Recent transcripts"** — "Your last dictations, kept on this Mac. Hover one to
   copy it again." (Windows: "this PC")
8. `settings.customWords` · **"Custom words"** — "Add names and jargon so JVoice always spells them your way."
9. `settings.appearance` · **"Opacity"** — "Sets how see-through JVoice's windows and pill are." (plays the
   Opacity demo, §10.8)
10. `settings.help` · **"Replay any tour"** — "Click ⓘ to replay this tour, or pick one part to see again."
All Settings steps are Explain. Menu titles: "Welcome Tour", "Recording Tour", "Settings Tour".
(Windows-only cards like Corrections/Updates get no step unless you add one following the copy rules.)

### 10.4 Engine (pure — port to `JVoice.Core/Tours/`, with tests)
- Model: `TourID`, surface, trigger (`startedByApp` | `surfaceShown(surface)`), `TourStep(anchor, kind:
  explain | tryIt(advanceOn: event), title, body)`, versions.
- `TourEngine`: pure state machine — start / next / skipStep / skipTour / pause / resume; Try-step
  matching on events; **a step whose anchor isn't on screen is skipped**; progress counter "n of m" counts
  only steps that will be shown.
- `TourRules.shouldAutoStart`, `{shortcut:…}` placeholder rendering.
- `TourAudience` classifier (pure over an injected "facts" record) + keys.
- `TourEvents`: a one-way bus the surfaces post to (`recording.started`, `recording.stopped`,
  `dictation.pasted`, `surfaceShown(x)`, `replay(tour)`, `replayPart(tour, step)`, `resetAll()`).
  Surfaces never call the coordinator directly.
- Events timing: `recording.started` is posted only **after the pill is shown and the mic actually opened**
  (next UI-thread turn — never between the press and the pill/mic); a failed open posts nothing (no tag
  over a permission dialog). `surfaceShown(recordingPill)` only if that same recording is still on screen.
  `recording.stopped` is posted before the pill leaves the recording state.
- Coordinator: owns triggers, hand-overs, pausing (host window closed → pause; resumes next time),
  persistence and the tag. Tour confirmations ("Tours reset", "The recording tour starts at your next
  dictation") show as the neutral `notice` pill — never over a recording/transcription.

### 10.5 The tag overlay (Windows implementation)
- Pieces: a **dim** over the host window with a hole around the control, an **outline box** around the
  control, a **leader** line, and the **tag bubble** (title, 1–2 line body, "n of m", **Next** capsule,
  **Skip Step**, **Skip Tour**). Keys: Return = Next, Esc = Skip Tour — except while a Settings shortcut
  row is recording (the recorder keeps Return/Esc: "claims keys"), and on the pill, which can never take
  focus (its tag buttons are clickable instead).
- Look (native, 2026-09-29): the bubble uses the same material + Opacity backing as the windows, in the
  HOST window's light/dark; system text colours; the outline (1.5 pt line), leader and Next capsule in the
  user's **accent colour** (Windows: `UISettings.GetColorValue(UIColorType.Accent)` or
  `SystemParameters.WindowGlassColor`); continuous corners.
- Outline shape: a control may declare a corner radius; the box radius = that radius + box padding,
  capped at half the box's short side — so around the capsule pill the outline is a **concentric capsule**
  (not a 6-pt rectangle); the dim's hole and the leader's corner clearance use the same radius. Default
  radius for other controls = the tag style's box radius.
- Windows: two borderless, topmost, **no-activate** (`WS_EX_NOACTIVATE`), `ShowActivated=false` windows
  per host: a **click-through** decor window (`WS_EX_TRANSPARENT | WS_EX_LAYERED`) for dim/outline/leader,
  and a clickable (not click-through, still no-activate) window for the bubble. Owned by the host window so
  they move/minimise with it. Anchor ids: `AutomationProperties.AutomationId` on the WPF element (the Mac
  stores them as accessibility identifiers the same way); find the element's screen rect with
  `PointToScreen` + `ActualWidth/Height` (DPI-aware).
- Follow: re-place on host move/resize, and **follow scrolling in the same frame** (Mac 157698d: subscribe
  to the anchor's scroll viewer `ScrollChanged` synchronously; a 0.1 s timer alone lagged up to ~220 pt).
  Cut the box to the viewport; hide the tag while its control is scrolled fully out of view.
- The dim covers only the pill's capsule (not its transparent shadow margin or morph room) — the pill
  reports its capsule rect ("host shaping").
- Tray anchor: a Windows tray icon has no window to outline. Use `Shell_NotifyIconGetRect` to get the
  icon's rect (works when the icon is visible in the tray, not in the overflow flyout); if it's hidden,
  **skip the step** (the Mac skips the menu-bar step when the status item isn't on screen).

### 10.6 ⓘ on every window, Help & Tours, Tours & Tips
- **ⓘ** in the title bar's top-right of Settings and the Welcome window (not the pill — too small). Its
  menu: **Replay Tour** (whole tour) · **Show Me ▸** one item per step title (explains just that part — a
  one-step "part" session that never marks the tour seen, never pauses/resumes, never fires onFinished;
  a part whose control isn't on screen shows a HUD notice) · **Keyboard Shortcuts**.
- Tray menu → **Help & Tours ▸** Welcome Tour · Recording Tour · Settings Tour · Reset All Tours (+ "Take
  the Welcome Tour" opens the Welcome window on page 2).
- Settings → **Tours & Tips** card (bottom of the right column): "Show Me Around" toggle
  (= `firstUseToursEnabled`), Replay Welcome Tour, Reset All Tours.

### 10.7 Verify
Pure tests: engine transitions, rules, audience classifier (every "existing" fact alone → existing; none →
new), placeholder rendering, catalog lint (copy rules, unique titles, body fit at 260 pt with the longest
shortcut — measure with WPF `FormattedText` in Segoe UI Variable Body 13), outline radius maths, Opacity
demo timeline (§10.8). By hand: a clean Windows user profile (or a VM) for the first-run flow — **never
wipe David's real settings to test it**.

### 10.8 Tour polish (2026-09-30, a45598e)
- **Capsule outline on the pill** — §10.5 outline shape; anchor `pill.controls` declares radius 28 (× HudScale).
- **Animated Opacity step** (David: show the bar "slowly going down… decreased and increased"): while step 9
  is on screen, a demo drives the REAL Opacity value along a pure timeline — user's value → 0 → 1 → back,
  eased, looping ~**9.5 s** — so the slider moves and every window follows live; the tag body gets a live
  readout appended: `Watch: 37 % ↓`, `Watch: 0 % Transparent`, `Yours: 50 %`. It **never saves**: saving is
  off while it plays; stopping restores the user's value; if the value changes to something the demo
  didn't set (user dragged the slider or pressed Default), the demo ends and the user's value is kept and
  saved. Started after the tag shows; stopped whenever the step leaves (next step, skip, pause, finish).
  Port `OpacityDemoTimeline.swift` (51 lines, pure) exactly and its tests (readouts must fit the tag's two
  lines).

---

## 11. Windows open on the display you're using (a45598e) — MISSING (P2)
Mac: Settings and the Welcome window centre on **the screen with the mouse pointer** each time they open
from hidden; the pill picks that screen when it appears and keeps it while up (a morph never jumps
monitors). Before, a windowless tray app used the primary display.
Windows: `GetCursorPos` → `MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST)` → `GetMonitorInfo` (work area) →
centre the window in that work area in DIPs for that monitor's DPI (per-monitor DPI aware: convert with
the target monitor's scale, and set the position before `Show()` to avoid a flash on the old monitor).
The HUD: position on the cursor's monitor at show time, bottom-centre, 64 × HudScale above the taskbar
edge of that work area.

## 12. Dev modes — PARTIAL (P3)
- Mac `--ui-preview <dir> [--opacity v] [--backdrop white|black|wallpaper] [--active] [--hud-timeline]`
  opens the real Settings (Light + Dark, + a tour tag), Welcome (both pages), every HUD state (+ a
  mid-morph frame), the tour Opacity demo frames and the pill tour tag, and saves PNGs of the screen region
  under each (backdrop included). Never writes a setting. Windows: extend `--settings-render` into a
  `--ui-preview` that renders the same set with `RenderTargetBitmap` for layout and a real screen capture
  (`Graphics.CopyFromScreen` / Windows.Graphics.Capture) for the translucent look over a known backdrop
  window. This is how you verify §8–§10 and measure §9's contrast.
- Mac `--settings-smoke` (build the real Settings window in a throwaway process and exit 0) — the Windows
  analogue is `--settings-render`; keep it working after the redesign.

---

## 13. Checklist when you finish an item
1. `dotnet build` + `dotnet test` green (never run anything heavy on David's Mac — this is the PC).
2. Republish + relaunch the tray app if the change is runtime-visible; try it for real.
3. Add a §7 entry to `docs/HANDOFF-WINDOWS.md` (what, why, files, tests, verification) and tick the item's
   row in §1 of this document (change its status to DONE with the commit hash).
4. Commit on `windows-port` with a clear message; push when David says so.
