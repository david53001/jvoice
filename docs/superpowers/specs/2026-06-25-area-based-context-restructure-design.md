# Design: Area-based context structure for JVoice (+ demo-video removal)

**Date:** 2026-06-25
**Status:** Proposed — awaiting David's review before an implementation plan is written
**Suggested branch:** `restructure-areas` (off `main`)

## What JVoice is (context for a fresh reader)

JVoice is a standalone macOS menu-bar voice-dictation app. The user presses ⌥Space
anywhere, speaks, and on-device WhisperKit (an open-source Swift wrapper around OpenAI's
Whisper speech-to-text models) transcribes the audio; the result is tone-styled and pasted
into the frontmost app. It is a single Swift Package Manager (SwiftPM) executable target
named `JVoice`, Swift 5.9, macOS 14+. All source lives under `Sources/JVoice/`.

## Why we are doing this

David wants a workflow (inspired by how some creators lay out their projects) where he can
`@`-mention a *part* of the app in a Claude Code prompt and the agent gets focused,
accurate context for just that part — instead of re-reading the whole repo. In Claude Code
the `@` file/folder reference already exists; what's missing is (a) clean folder boundaries
so `@`-ing a folder yields exactly one coherent area, and (b) a short per-area brief the
agent reads to orient itself.

We chose the **"Group Services"** approach: physically group the relevant source files into
area folders, and drop an auto-loading `CLAUDE.md` brief into each. (Claude Code automatically
loads a `CLAUDE.md` found in the directory of files it is working on, and `@`-ing a folder
includes that `CLAUDE.md`.) We rejected the lighter "briefs-only" approach because David
prefers the cleaner ergonomics of `@`-ing a real folder, and because folder boundaries can't
drift out of date the way a hand-maintained file list can.

A separate, unrelated cleanup is bundled in because David asked for it in the same breath:
**removing the now-unused demo-video project.**

## The six areas

| Area | Physical home | `@` target |
|------|---------------|-----------|
| Transcription pipeline | `Sources/JVoice/Services/Transcription/` | the folder |
| Audio capture | `Sources/JVoice/Services/Audio/` | the folder |
| App orchestration | `Sources/JVoice/Services/Orchestration/` + top-level `VoiceCoordinator.swift` | the folder (brief points up to the coordinator) |
| UI | `Sources/JVoice/UI/` (already a folder) | the folder |
| Demo video | *being removed* | n/a |
| Launch & docs | `docs/launch/`, `README.md` (already exist) | `docs/launch/` |

Only the first three require any file movement. UI and launch/docs are already their own
folders and just receive a brief. Demo video is deleted, not briefed.

## Part A — Remove the demo video (scope: project only)

Decision: remove the heavyweight Remotion project, but **keep the rendered demo** that the
README depends on.

- **Delete** `docs/demo-video/` (the Remotion project: 61 git-tracked files plus ~515 MB of
  untracked `node_modules/` and `out/`).
- **Keep** `docs/assets/demo.gif` and `docs/assets/demo.mp4` — these are the rendered outputs,
  and `README.md` line 8 embeds `docs/assets/demo.gif` as its hero image. README is unchanged.
- **Edit** `scripts/generate-icon.swift`: remove the lines that also export
  `docs/demo-video/public/app-icon.png` (the comment on line 5 and the write block around
  lines 22 / 131–134). The script's primary job — regenerating `Resources/AppIcon.icns` — is
  left fully intact.
- **Edit** `CLAUDE.md` (project root): delete the "## Demo video (Remotion)" section, since
  the workflow it documents no longer exists.
- Out of scope / untouched: `../Portfolio/assets/jvoice-demo.gif` (a separate git repo we must
  never modify). Historical mentions in `docs/HANDOFF.md`, `CODEBASE-SCAN.md`, and
  `docs/superpowers/plans/*` are point-in-time snapshots and are left as-is.

## Part B — Group `Services/` into area folders

The 22 files currently flat in `Sources/JVoice/Services/` are grouped as follows. **Every move
is a pure `git mv` with no edit to file contents.**

**`Services/Transcription/` (10 files)** — the whisper engine, streaming, and the custom-word
accuracy layer:
`TranscriptionManager.swift`, `StreamingTranscriptionSession.swift`, `ChunkPlanner.swift`,
`WavTail.swift`, `VocabularyPrompt.swift`, `RepetitionGuard.swift`, `RegurgitationRecovery.swift`,
`TextProcessor.swift`, `PhoneticMatcher.swift`, `BenchRunner.swift`.

**`Services/Audio/` (2 files)** — audio capture:
`RecordingManager.swift`, `AudioInputRouter.swift`.

**`Services/Orchestration/` (10 files)** — system glue and persisted state:
`PasteManager.swift`, `HotKeyManager.swift`, `SettingsStore.swift`, `SettingsURLs.swift`,
`StatsStore.swift`, `LastTranscriptStore.swift`, `LaunchAtLoginManager.swift`,
`SystemActions.swift`, `PermissionError.swift`, `AppTimings.swift`.

**Resolved judgment calls:**
- `VoiceCoordinator.swift` **stays at the top level** (`Sources/JVoice/`) alongside
  `JVoiceApp.swift` and `AppDelegate.swift`. It is the app's spine/composition root, not peer
  glue. The `Orchestration/CLAUDE.md` brief cross-references it.
- `BenchRunner.swift` **goes in `Transcription/`** — it is the hidden `--bench` CLI harness that
  measures the transcription pipeline, so co-locating it serves the focused-context goal.

## Why this is safe (the core analysis)

1. **SwiftPM compiles by directory glob, not by file list.** `Package.swift` declares
   `.executableTarget(name: "JVoice", …)` with **no** `path:`, `sources:`, or `exclude:`. SwiftPM
   therefore recursively compiles *every* `.swift` file under `Sources/JVoice/`. Moving files into
   subfolders under that root does not change which files compile.
2. **Swift imports are module-level, not path-level.** Every file in the target shares the one
   `JVoice` module namespace; there are no per-file import paths to update. Tests use
   `@testable import JVoice`, which is likewise path-independent.
3. **The only path-coupled consumers are two local scripts**, which must be updated in the *same
   commit* as the move so the tree is never internally inconsistent:
   - `scripts/run-logic-tests.sh` (lines 270–276) hard-codes 7 source paths.
   - `scripts/verify-streaming.sh` (lines 152–157) hard-codes 6 source paths.
   The CI (continuous integration) workflows under `.github/` hard-code none — they run
   `swift build` / `swift test` plus those scripts, so fixing the scripts keeps CI green.
4. **Moves use `git mv`** → history preserved as renames, fully reversible.
5. **The new `CLAUDE.md` briefs are new files** → pure additions, cannot break anything.

## Per-area briefs

Each brief is a short `CLAUDE.md` (a few hundred words) that orients an agent working in that
area: what the area does, the key files and how they relate, the invariants/traps to respect,
and how to verify changes. Content is distilled from the existing root `CLAUDE.md` architecture
section and the team's memory notes. Briefs to create:

- `Sources/JVoice/Services/Transcription/CLAUDE.md` — the pipeline, the prompt-regurgitation
  failure mode and its guards (`RepetitionGuard` / `RegurgitationRecovery`), the WhisperKit 1.0.0
  `withoutTimestamps` truncation trap, and `--bench` / `verify-streaming.sh` / `verify-transcription.py`
  as the verification tools.
- `Sources/JVoice/Services/Audio/CLAUDE.md` — recording lifecycle, orphan-WAV sweep, and the
  routing rule that keeps Bluetooth headsets on the A2DP high-quality output profile by recording
  from the built-in mic instead of switching them to a low-quality headset profile.
- `Sources/JVoice/Services/Orchestration/CLAUDE.md` — the hotkey → record → transcribe → paste
  flow driven by the top-level `VoiceCoordinator.swift`, plus settings/stats persistence.
- `Sources/JVoice/UI/CLAUDE.md` — the structure of the HUD (the heads-up recording/transcribing
  pill overlay), the Settings window, and the menu-bar status item.
- `docs/launch/CLAUDE.md` — what the launch material is, the "do not publish without David" rule,
  and the `USER` placeholder convention.

## Execution phases (each ends green before the next)

- **Phase 0 — Branch.** Create `restructure-areas` off `main`.
- **Phase 1 — Demo removal.** `git rm -r docs/demo-video/`; edit `scripts/generate-icon.swift`;
  remove the demo section from root `CLAUDE.md`. Verify `swift build` still passes.
- **Phase 2 — Reorg.** `mkdir` the three subfolders; `git mv` all files; update the two scripts'
  hard-coded paths — **all in one commit.**
- **Phase 3 — Briefs.** Add the five `CLAUDE.md` briefs.
- **Phase 4 — Root doc sync.** Update the root `CLAUDE.md` "Architecture" section to reflect the
  new folders.

## Acceptance criteria (all must pass)

1. `swift build` succeeds.
2. `./scripts/run-logic-tests.sh` passes.
3. `./scripts/verify-streaming.sh` passes.
4. `swift test` compiles.
5. `git diff --stat` (vs. branch point) shows only: demo deletions, file renames, the two script
   edits, the new brief files, and the root-`CLAUDE.md` doc edits — nothing unexpected.

## Non-goals

- No custom subagents (deferred; this is the "focused context" path, not "specialized experts").
- No changes to app behavior, UI, or any `.swift` file's contents.
- No new SwiftPM targets/packages; the app stays one `JVoice` executable target.
- No README content change; the demo gif stays.

## Commit policy

Per David's standing rule for this repo, **nothing is committed without his explicit go-ahead**,
and there is no pushing/publishing. This spec is written but will not be committed until David says so.
