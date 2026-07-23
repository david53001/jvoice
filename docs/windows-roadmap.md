# JVoice Windows — Roadmap (future work)

> **Context for a zero-context reader.** JVoice is a free, privacy-first voice-dictation app
> (global hotkey → record → on-device Whisper transcription → text pasted into the focused app).
> This file is the forward-looking work list for the **Windows port** (`windows/`, C#/.NET 9/WPF,
> Whisper.net). The authoritative *as-built* state, build commands, and every gotcha live in
> `docs/HANDOFF-WINDOWS.md` (start there); hard rules (no publishing without David, $0 budget,
> read-only macOS `Sources/`) are in the root `CLAUDE.md`. Items here are **not commitments** —
> they are the agreed-upon or recommended next steps, ordered by value. Written 2026-07-02.

## 1. Fix first (quality of the core loop)

- **~~The 2026-07-23 "`*referred*`" incident~~ — ROOT-CAUSED + FIXED 2026-07-23** (HANDOFF
  §7 #44, branch `fix/asterisk-annotations-and-inflight-guard`). The log disproved the
  guard-failure hypothesis: the ~165 s dictation was never decoded at all — a hotkey re-fire
  **313 ms** after the stop press hit `ToggleRecording`'s start branch, which **cancelled the
  in-flight transcription** (a guard Swift has — `!transcriptionManager.isTranscribing` — that
  the port had dropped) and started an accidental 3.7 s near-silent recording that decoded to
  `*referred*` (the `*…*` annotation form the regex didn't strip). Three fixes, all
  test-locked (880/880): `NonSpeechAnnotation` now strips `\*[^*]*\*`;
  `CoordinatorDecisions.CanStartRecording` + `_isTranscribing` make a pending transcript
  outrank a new start request; `GlobalHotkey` fires only on the chord key's down transition
  (auto-repeat swallowed without triggering). Bench-verified on the real clips: `*referred*`
  → no-speech, the 165 s WAV → the full ~1,900-char dictation. Installed locally 2026-07-23
  (David-requested) and pushed to `origin/fix/asterisk-annotations-and-inflight-guard`; the
  installers/release assets do NOT have it yet.
1. **~~Silence-hallucination gate~~ — DONE 2026-07-02** (HANDOFF §7 #38). Calibrated on David's
   real clips; discriminator = prompt-vs-no-prompt agreement (confidence measured inverted);
   shipped as `Core/Policy/SilenceHallucinationGate` + a witness decode in the engine. 17/17
   clips verdict-correct; quiet real speech unharmed (§7 #21 balance held). Re-calibrate any
   time via `JVOICE_KEEP_WAV` capture → `nospeech-probe --analyze`.
2. **~~Elevated-run first-recording freeze~~ — FIXED 2026-07-02** (HANDOFF §7 #37). Root cause
   was a capture-teardown deadlock in `NAudioRecorder`, not elevation; elevation was a
   coincidental first-observation. Kept here so nobody re-opens the stale §8 warning.
3. **David's interactive dogfood** (`docs/launch/windows-dogfood-checklist.md`) — the live-mic
   loop, BT routing, game suppression with real games, elevated-window dictation, and everything
   added since §7 #32 (translate, undo hotkey, Code mode, updater) which is render-verified but
   not yet lived-with.

## 2. Ship-readiness (before/at first public release)

4. **Inno Setup installer** (Phase 5 Task 3, `windows/installer/JVoice.iss` — not yet written).
   The IExpress one-click installers work but give no uninstall entry or upgrade-in-place; the
   in-app updater (§7 #36) would hand off to Inno more cleanly. Needs Inno Setup installed.
5. **winget submission — after the repo is public.** The winget community repo accepts
   **unsigned** installers and is free — the Windows answer to Homebrew's unsigned-cask ban, and
   it sidesteps the SmartScreen "More info → Run anyway" friction for technical users. One-time
   manifest PR; outward-facing, so **David's go-ahead required**.
6. **Port `scripts/verify-transcription.py`** (Phase 5 Task 6) to
   `windows/tools/verify-transcription`: corpus-level word-retention / spurious-vocab scoring
   over generated TTS clips, so accuracy regressions are caught mechanically. `whisper-smoke` +
   `--bench` already prove the engine end-to-end; this adds breadth.

## 3. Feature additions (rough value order)

7. **Spoken punctuation / editing commands** — "new line", "period", "scratch that". Every
   serious competitor (Wispr Flow, SuperWhisper) has this. Fits as a new pure stage in
   `windows/JVoice.Core/Text/` on the post-processing channel (same pattern as
   `DeveloperTerms`), so it's unit-testable and gated by a Settings toggle.
8. **Hold-to-talk mode** — press-and-hold the chord to record, release to stop, alongside the
   current toggle. `GlobalHotkey` already sees key-down/up (`WH_KEYBOARD_LL`); the hook comment
   even anticipates push-to-talk. Big ergonomic win for short dictations.
9. **"Learn from my fixes" suggester** (HANDOFF §8 item 6) — reuse
   `TextProcessor.ExtractCorrections` to notice repeated manual fixes and offer them as
   correction rules; turns the Corrections list into a flywheel.
10. **Per-app Whisper-model override** — the future field explicitly left open in the §7 #32
    `AppModeResolver` design (e.g. Tiny for game chat, LargeTurbo elsewhere). Schema bump +
    engine swap on app switch; weigh model-reload latency first.
11. **Search/filter box for Recent Transcripts** — the 30-entry history (§7 #26) exists; a
    filter makes it actually retrievable.
12. **Language auto-detect** — whisper.cpp supports it natively; today the language is fixed
    en/ro in Settings. David is bilingual; auto-detect removes a manual toggle. Check accuracy
    cost on short clips before defaulting it on.
13. **Developer-terms follow-ups** (§7 #28/#34): categorized packs (Web / Python / DevOps…) and
    porting `JVoice.Core/Text/DeveloperTerms.cs` 1:1 back to the macOS app. Respect the
    exclusion audit (`cursor`, `bolt`, `render`… stay excluded — they collide with everyday
    English; see the #34 test-locked list).

## 4. Non-goals / guard rails (do NOT do these)

- **No digital gain on transcription audio** to "fix accuracy" (§7 #22; memory
  `win-mic-low-capture-level`): whisper normalizes log-mel energy; gain scales noise equally
  and risks clipping. Real levers: mic SNR, diction, the `Core/Text` pipeline.
- **No RMS/spectral no-speech pre-gate** — retired by §7 #21; the model decides. The #24 gate
  above must be model-driven (agreement/compression), not level-driven.
- **No live streaming-preview-as-you-speak** — conflicts with the regurgitation-recovery
  re-decode policy and adds a lot of UI complexity for marginal value.
- **Game detection stays read-only** (anti-cheat safety, §7 #27): no memory reads, module
  enumeration, or injection — ever. `ForegroundApp`/`GameDetector` stay at
  `PROCESS_QUERY_LIMITED_INFORMATION`.
- **Elevation stays opt-in** (§7 #25); the manifest stays `asInvoker`.
- **Don't ship the single-file exe** — Whisper.net can't find its native runtimes there
  (§7 #4); ship the folder build / installers.
- **No publishing, pushing, or outward-facing action without David's explicit go-ahead.**
