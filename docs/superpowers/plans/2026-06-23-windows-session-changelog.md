# Windows port — session changelog (2026-06-23, evening) 

Zero-context record of "the past few hours" of work on the JVoice **Windows** port, branch
`windows-port`. Scope: every commit **after `ae322b7`** (the "bug-hunt DONE" commit at 07:26)
through **`f59bc0d`** (23:48) — 19 commits, ~12:41→23:48 Jun 23. The macOS Swift app
(`Sources/`, `Tests/`, `Package.swift`, `Resources/`) was **not touched**; all work is under
`windows/` + `docs/`.

> **Working tree is clean** — everything below is committed. There is nothing uncommitted.
> The deep per-change detail lives in `docs/HANDOFF-WINDOWS.md` §7 (entries #15–#23); this file
> is the linear, grouped narrative. As-built state: `dotnet build windows/JVoice.sln -c Release`
> = 0 errors; `dotnet test windows/JVoice.Tests` = **434/434**; on-device transcription verified.

---

## The five things that changed (one-line each)

1. **No-speech is now decided by the whisper model, not an RMS/spectral gate** — every signal-level
   gate was retired (it kept rejecting David's real quiet/short speech, which overlaps his room hum
   at every level David's mic produces).
2. **The recording HUD bars are a continuous synthetic wave, NOT mic-reactive** (David preferred a
   steady flow; mic-reactive bars stuttered on his words). Final pill: **152×38, 21 round-capped bars**.
3. **A user-editable "Corrections" list** (`heard phrase → replacement`) was added for systematic
   mishearings (e.g. "web api" → "web app").
4. **Paste now lands where you clicked**, including the terminal JVoice was launched from (target is
   resolved by live process-ownership, not a stale launch-time window handle).
5. **The streaming path no longer drops a quiet sentence tail** (it falls back to the lossless
   whole-file decode instead).

---

## Theme 1 — No-speech / silence handling (the session's central thread)

One bug — "my short/quiet sentences are rejected as *No speech detected.*" and "the last part of my
sentences is cut off" — chased through **four** designs before the right one. **Root cause (final):**
David's mic captures speech ~10–20× quieter than every threshold assumed; his quiet speech and his
room hum sit at the *same* raw RMS (~0.004) **and** the same spectral ratio (0.08–0.12), so **no
absolute level or ratio threshold can separate them.** Every gate was tuned on synthesized SAPI
clips that don't reproduce his real low-SNR mic.

| Commit | Time | What | Verdict |
|---|---|---|---|
| `7030e3a` | 12:41 | RMS gate #1: gate whole-file decode on `ChunkPlanner.IsSilent` (0.005 floor) so silence stops pasting a whisper hallucination ("you", "(birds chirping)"). | superseded |
| `66a9e79` | 20:09 | RMS gate #2: `HighPassSilence` — gate on **high-passed** RMS (crush hum, keep broadband speech). | superseded |
| `c3c849a` | 21:20 | RMS gate #3: dual-criterion **spectral-ratio** gate (`hpRMS/rawRMS ≥ 0.20`). | superseded |
| `71b9057` | 22:43 | **RETIRE all gates → the model decides.** + streaming sentence-tail fix (Theme 5). | **final** |

**Final mechanism (`71b9057`):** the engine decodes first, then `JVoice.Core/Text/NonSpeechAnnotation.Reduce`
maps a whole-transcript that is nothing but annotation groups (`[BLANK_AUDIO]`, `[Music]`, `[Sigh]`,
`(birds chirping)` — any case) to `""` → the existing `EmptyTranscript` → "No speech detected." On-device
probing (the new `nospeech-probe` tool) proved whisper decodes quiet speech correctly at *every* level
(down to peak 0.008) and emits an annotation — never a plausible sentence — on true silence. So "did the
user speak?" is answered by whisper's **text output**, level-independently. **No RMS/spectral gate remains
in the live path.** `HighPassSilence` is now **metrics-only** (its `PeakHighPassRms`/`PeakWindowRms` still
feed the diagnostic log; `IsSilent` is unwired but kept as a tested dead-end). Full design + evidence:
`docs/superpowers/plans/2026-06-23-windows-nospeech-and-tail-fix.md`; HANDOFF §7 #15/#19/#20 (the dead
gates, kept for history) → **#21** (the resolution).

## Theme 2 — Black-&-white HUD redesign + bar geometry, ending in the continuous wave

- **`1af6627` (18:59) — the redesign.** The HUD became a **text-free black pill of white voice-activity
  bars**; **silent paste** (no "Pasted" pill); **errors are the only text**; Settings + tray went fully
  **monochrome**. Rationale: solid bars sidestep the layered-window grayscale-AA blur that softened the old
  glowy text at David's non-native 1600×1080 (the in-app blur fix — never tell him to change resolution).
  New: `DisplayMetrics.HudScale` (enlarge the pill by the native/current stretch ratio), `DiagnosticLog`.
- **Seven same-day shape iterations** (David tuning by eye): `1af6627` → `8ebf441` → `2ef1587` → `bb6721e`
  → `77c93ff` (the pivot: bars became true vertical capsules — `Height` animated directly with a fixed
  `BarWidth/2` corner radius, **not** a `ScaleTransform`, which had flattened the round caps at low levels)
  → `510e108` → **`f59bc0d` (final)**.
- **`990ba76` (20:55) — monochrome scrollbar** so Settings lists match the B&W theme.
- **The mic-reactive → continuous-wave reversal (`b39733f` → `c8f4a8d` → `526e395`):** the bars started
  mic-reactive with a *visual* meter gain (boosted to `LevelGain=20`, then `=38` for David's quiet mic),
  but the mic-driven bars **stuttered on his words** — he wanted a constant up-and-down flow. **`526e395`
  removed the live-mic drive entirely** and replaced it with a generated `LiveBar` wave (summed sines +
  per-bar phase gradient so the motion travels across the row + centre-weighted bell). The mic-level wiring
  (`InputLevelProvider`, `CurrentInputLevel`, `IAudioRecorder.CurrentLevel`) is **kept but dead** so a
  mic-reactive mode can be re-enabled later.

**Final HUD (verbatim from `HudView.xaml`/`.cs`):** PillBody **152×38**, **CornerRadius 19**, black, hairline
white border @0.10, black drop shadow. Bars: **BarCount 21**, **BarWidth 3**, **BarGap 3**, **MaxBarHeight 32**,
**MinBarHeight 3** (round dot at rest), fully round caps. Transcribing/preparing/downloading = an
`IndeterminateBar` Gaussian "bump" shimmer; error = the only text state; idle/done = hidden. `HudBaseScale`
trimmed 1.1→1.0. See HANDOFF §7 **#18** (redesign + iteration history) and **#23** (the continuous wave +
final geometry — the as-built record).

## Theme 3 — User-editable Corrections list (`4e3d5c9`, 13:03)

A Windows-only post-processing safety net for systematic *mishearings* where the misheard word is a
*different real word* the vocabulary/decoder-prompt path can't fix (David's case: "web app" → "web api").
`CorrectionRule(From, To)` rules are stored in `SettingsState.Corrections` + a `corrections` JSON key
(schema stays v1, back-compat), edited in a new "Corrections" Settings section. `UserCorrections.Merge`
folds them into the **existing** `extraDictionary` that `TextProcessor.Process` already accepts — **the
brain (`TextProcessor`) is untouched / still 1:1 with Swift.** Phrase-capable on purpose (the recommended
rule is the phrase `web api → web app`, so standalone "API" stays intact). Post-processing only — no engine
reload. HANDOFF §7 **#17**.

## Theme 4 — Paste lands where you clicked (`b2e2170`, 12:56)

JVoice is a tray app with no window at startup, so the old self-check compared the live foreground against
a **single HWND snapshotted at launch** — usually the launching terminal — making it mis-reject the real
paste target when you later dictated into that same terminal. Fixed: `CoordinatorDecisions.ResolveTargetWindow`
now decides "is this window ours?" by **process ownership** (`Environment.ProcessId`, the analog of macOS
`processIdentifier != ownPID`), via `ForegroundWindowTracker.IsOwnedByCurrentProcess`. HANDOFF §7 **#16**.

## Theme 5 — Streaming sentence-tail fix (part of `71b9057`)

`StreamingTranscriptionSession.Finish()` was dropping David's quiet **trailing clause** because, at his low
level, it read as "silent" against the absolute `ChunkPlanner.IsSilent` (0.005) floor — earlier chunks
pasted, the tail was lost. Now a non-empty tail judged silent **returns null → lossless whole-file fallback**
(which re-decodes everything with the gate gone) instead of being dropped. Normal-level users (loud tail) are
unaffected; the never-silently-drop invariant holds. A **Windows divergence from Swift** (the mac mic is
normal-level, so its silent-tail drop never misfires). HANDOFF §7 **#21** (bug #2).

## Theme 6 — Tooling: nospeech-probe (`71b9057`, `dd77505`)

`windows/tools/nospeech-probe` — an on-device harness (kept in the solution) that feeds silence / 60 Hz hum /
rumble / white noise / SAPI speech scaled peak 0.10→0.008 through the real Whisper.net decode (± vocab prompt)
and prints the `NonSpeechAnnotation` result. This is the experiment that proved the model is the reliable
no-speech authority. `dd77505` added `--muffle` (a one-pole low-pass) so the probe reproduces David's real
muffled low-pitched-male mic (ratio ~0.1) instead of SAPI's clean ~0.76.

---

## New files this session

| File | Role |
|---|---|
| `JVoice.Core/Text/NonSpeechAnnotation.cs` | Model-driven no-speech detector (annotation-only transcript → ""). The discriminator that replaced the RMS gate. |
| `JVoice.Core/Audio/HighPassSilence.cs` | High-pass/spectral silence logic — now **metrics-only** (gate retired, kept as documented dead-end). |
| `JVoice.Core/Text/UserCorrections.cs` | `Merge` — folds user `CorrectionRule`s into TextProcessor's extra dictionary. |
| `JVoice.Core/Models/CorrectionRule.cs` | `record CorrectionRule(From, To)`. |
| `JVoice.App/Platform/DisplayMetrics.cs` | `HudScale` = base × native/current stretch ratio (clamp 1.8) — keeps the pill crisp below native res. |
| `JVoice.App/Platform/DiagnosticLog.cs` | Temporary timestamped tracing to `%APPDATA%\JVoice\diagnostic.log` (remove once the mic path is root-caused). |
| `windows/tools/nospeech-probe/` | On-device no-speech harness (`--muffle`, `--dump`). |
| `docs/superpowers/plans/2026-06-23-windows-nospeech-and-tail-fix.md` | Zero-context design note for the no-speech + tail fix. |

New tests: `NonSpeechAnnotationTests`, `UserCorrectionsTests`, `HighPassSilenceTests` (+ updates to
`StreamingSessionTests`, `ChunkPlannerTests`, `CoordinatorDecisionsTests`, `SettingsStoreJsonTests`,
`SettingsStateTests`). Test count grew 381 → **434** across the session.

---

## Still needs a human (David's interactive dogfood)

Live-mic accuracy and the HUD/Settings *look* can only be judged at the desktop — walk
`docs/launch/windows-dogfood-checklist.md` (it was updated this pass to expect the **continuous-wave**
bars, not mic-reactive ones). The no-speech + tail fixes and the visuals are screenshot/engine-verified
for everything an autonomous session can check.
