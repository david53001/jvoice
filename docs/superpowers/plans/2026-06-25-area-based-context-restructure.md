# Area-based Context Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the unused demo-video project and group `Sources/JVoice/Services/` into three area
subfolders (each with an auto-loading `CLAUDE.md` brief) so a developer can `@`-mention one folder in
Claude Code and get focused, accurate context — with zero change to app behavior.

**Architecture:** Pure file moves via `git mv` (no `.swift` content edits) plus new `CLAUDE.md` briefs.
Safe because `Package.swift` compiles by directory glob, so moving files inside `Sources/JVoice/` does
not change the build. The only path-coupled consumers are two local verification scripts, updated in
lockstep.

**Tech Stack:** Swift 5.9, Swift Package Manager (SwiftPM), macOS 14+. Verification via `swift build`,
`./scripts/run-logic-tests.sh`, `./scripts/verify-streaming.sh`.

**Spec:** `docs/superpowers/specs/2026-06-25-area-based-context-restructure-design.md`

**Commit policy:** Per this repo's standing rule, **nothing is committed or pushed without David's
explicit go-ahead.** Execution stages all changes (`git mv` stages moves automatically) and runs every
verification gate, then stops. The `git commit` lines below are the *recommended grouping for David*, not
steps the agent runs.

**Branch:** A dedicated branch `restructure-areas` created off the **current HEAD** (not `main`), so the
two script edits apply against the latest versions of those scripts and this work does not conflict with
the unmerged `overnight-hardening` branch. (Can be rebased onto `main` later if desired.)

---

### Task 0: Create the working branch

**Files:** none (git only)

- [ ] **Step 1: Confirm a clean tree, then branch**

Run:
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Code/JVoice
git status --short            # expect only untracked scripts/__pycache__/
git checkout -b restructure-areas
```
Expected: switched to a new branch `restructure-areas`.

---

### Task 1: Remove the demo-video project (keep the rendered README gif)

**Files:**
- Delete: `docs/demo-video/` (entire directory)
- Modify: `scripts/generate-icon.swift` (remove the secondary demo-icon export)
- Modify: `CLAUDE.md` (remove the "## Demo video (Remotion)" section)
- Untouched: `docs/assets/demo.gif`, `docs/assets/demo.mp4`, `README.md`

- [ ] **Step 1: Delete the Remotion project**

Run:
```bash
git rm -r docs/demo-video
```
Expected: removes 61 tracked files. (Untracked `node_modules/` / `out/` inside it are removed from disk
too; if any remain, `rm -rf docs/demo-video`.)

- [ ] **Step 2: Edit `scripts/generate-icon.swift` — fix the header comment (lines 4–5)**

Replace:
```swift
// on a macOS rounded-square, then assembles Resources/AppIcon.icns and
// exports docs/demo-video/public/app-icon.png (1024px) for the Remotion demo.
```
with:
```swift
// on a macOS rounded-square, then assembles Resources/AppIcon.icns.
```

- [ ] **Step 3: Edit `scripts/generate-icon.swift` — remove the `demoIconURL` declaration (line 22)**

Delete this line:
```swift
let demoIconURL = repoRoot.appendingPathComponent("docs/demo-video/public/app-icon.png")
```

- [ ] **Step 4: Edit `scripts/generate-icon.swift` — remove the demo-icon write block (lines 130–135)**

Delete this block (including its leading blank line so no double blank remains):
```swift

// Demo-video icon asset (1024px).
let demoRep = render(px: 1024)
if let data = demoRep.representation(using: .png, properties: [:]) {
    try data.write(to: demoIconURL)
    print("• demo-video app-icon.png (1024px)")
}
```

- [ ] **Step 5: Edit `CLAUDE.md` — delete the entire "## Demo video (Remotion)" section**

Remove the heading `## Demo video (Remotion)` and all its bullet content, up to (but not including) the
next top-level heading `## Launch material`.

- [ ] **Step 6: Verify the icon script still compiles**

Run:
```bash
swift -frontend -parse scripts/generate-icon.swift 2>/dev/null && echo "parse OK" || swiftc -typecheck scripts/generate-icon.swift
```
Expected: no errors referencing `demoIconURL` or `demoRep` (both removed together).

- [ ] **Step 7: Verify the app still builds**

Run: `swift build`
Expected: `Build complete!` (the demo removal touches no Swift target source).

- [ ] **Step 8 (David): recommended commit**

```bash
git add -A
git commit -m "chore: remove unused demo-video Remotion project"
```

---

### Task 2: Group `Services/` into area folders + fix the two scripts (one unit)

**Files:**
- Create dirs: `Sources/JVoice/Services/Transcription/`, `Sources/JVoice/Services/Audio/`,
  `Sources/JVoice/Services/Orchestration/`
- Move: 22 files (via `git mv`)
- Modify: `scripts/run-logic-tests.sh` (lines 271–276), `scripts/verify-streaming.sh` (lines 152–157)

- [ ] **Step 1: Create the three subfolders**

Run:
```bash
cd /Users/davidghermansteinberg/Desktop/Home/Code/JVoice/Sources/JVoice/Services
mkdir -p Transcription Audio Orchestration
```

- [ ] **Step 2: Move the Transcription files (10)**

Run:
```bash
git mv TranscriptionManager.swift StreamingTranscriptionSession.swift ChunkPlanner.swift \
       WavTail.swift VocabularyPrompt.swift RepetitionGuard.swift RegurgitationRecovery.swift \
       TextProcessor.swift PhoneticMatcher.swift BenchRunner.swift Transcription/
```

- [ ] **Step 3: Move the Audio files (2)**

Run:
```bash
git mv RecordingManager.swift AudioInputRouter.swift Audio/
```

- [ ] **Step 4: Move the Orchestration files (10)**

Run:
```bash
git mv PasteManager.swift HotKeyManager.swift SettingsStore.swift SettingsURLs.swift \
       StatsStore.swift LastTranscriptStore.swift LaunchAtLoginManager.swift SystemActions.swift \
       PermissionError.swift AppTimings.swift Orchestration/
```

- [ ] **Step 5: Confirm `Services/` now has only the three folders**

Run: `ls -1 /Users/davidghermansteinberg/Desktop/Home/Code/JVoice/Sources/JVoice/Services`
Expected: exactly `Audio  Orchestration  Transcription` (no loose `.swift` files).

- [ ] **Step 6: Update `scripts/run-logic-tests.sh` (lines 271–276)**

Change the six `Services/<File>.swift` paths to `Services/Transcription/<File>.swift`. The `Models/AppMode.swift`
line (270) is unchanged. Result:
```bash
    "$REPO_ROOT/Sources/JVoice/Models/AppMode.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/TextProcessor.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/PhoneticMatcher.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RepetitionGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/VocabularyPrompt.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/WavTail.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/ChunkPlanner.swift" \
```

- [ ] **Step 7: Update `scripts/verify-streaming.sh` (lines 152–157)**

Change all six `Services/<File>.swift` paths to `Services/Transcription/<File>.swift`. Result:
```bash
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/WavTail.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/ChunkPlanner.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/StreamingTranscriptionSession.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/PhoneticMatcher.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RepetitionGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RegurgitationRecovery.swift" \
```

- [ ] **Step 8: Verify the app builds after the move**

Run: `swift build`
Expected: `Build complete!` (proves SwiftPM still finds every file — directory glob unaffected).

- [ ] **Step 9: Verify the logic-test script (updated paths + logic intact)**

Run: `./scripts/run-logic-tests.sh`
Expected: `All logic tests passed.`

- [ ] **Step 10: Verify the streaming script (updated paths + guarantees intact)**

Run: `./scripts/verify-streaming.sh`
Expected: `All streaming + recovery verification passed.`

- [ ] **Step 11: Verify the test target still compiles**

Run: `swift build --build-tests`
Expected: `Build complete!` (tests use `@testable import JVoice`, unaffected by moves).

- [ ] **Step 12 (David): recommended commit**

```bash
git add -A
git commit -m "refactor: group Services into Transcription/Audio/Orchestration folders"
```

---

### Task 3: Add the five area briefs

**Files (all Create):**
- `Sources/JVoice/Services/Transcription/CLAUDE.md`
- `Sources/JVoice/Services/Audio/CLAUDE.md`
- `Sources/JVoice/Services/Orchestration/CLAUDE.md`
- `Sources/JVoice/UI/CLAUDE.md`
- `docs/launch/CLAUDE.md`

- [ ] **Step 1: Write `Sources/JVoice/Services/Transcription/CLAUDE.md`** — content as in spec §"Per-area briefs":
  pipeline overview, per-file roles, the regurgitation failure mode + guards, the WhisperKit 1.0.0
  `withoutTimestamps` truncation trap, and the verification tools (`verify-streaming.sh`,
  `run-logic-tests.sh`, `--bench`, `verify-transcription.py`).
- [ ] **Step 2: Write `Sources/JVoice/Services/Audio/CLAUDE.md`** — recording lifecycle, orphan-WAV sweep,
  and the A2DP/built-in-mic routing rule.
- [ ] **Step 3: Write `Sources/JVoice/Services/Orchestration/CLAUDE.md`** — the hotkey→record→transcribe→paste
  flow driven by the top-level `VoiceCoordinator.swift`, plus the persisted stores.
- [ ] **Step 4: Write `Sources/JVoice/UI/CLAUDE.md`** — HUD / Settings / menu-bar structure; note there is
  no automated visual test.
- [ ] **Step 5: Write `docs/launch/CLAUDE.md`** — what the launch material is, the "do not publish without
  David" rule, and the `USER` placeholder convention.

- [ ] **Step 6: Confirm the briefs exist and the build is still green**

Run:
```bash
find Sources docs/launch -name CLAUDE.md
swift build
```
Expected: the five new paths listed; `Build complete!` (Markdown files are not compiled).

- [ ] **Step 7 (David): recommended commit**

```bash
git add -A
git commit -m "docs: add per-area CLAUDE.md briefs for @-mention context"
```

---

### Task 4: Sync the root `CLAUDE.md` architecture section

**Files:** Modify `CLAUDE.md` (the "## Architecture (Sources/JVoice/)" section)

- [ ] **Step 1: Update the `Services/` description to name the new subfolders**

In the Architecture section, update the `Services/` bullet so it states the new layout —
`Services/Transcription/` (engine, streaming, accuracy, `BenchRunner`), `Services/Audio/`
(`RecordingManager`, `AudioInputRouter`), `Services/Orchestration/` (paste/hotkey/stores/system glue) —
and note that the per-area `CLAUDE.md` briefs document each. Preserve all existing technical detail; only
the grouping/paths change.

- [ ] **Step 2: Verify no stale `Services/<File>` path references remain in root CLAUDE.md that imply the old flat layout**

Run:
```bash
grep -nE "demo-video|Demo video" CLAUDE.md || echo "no demo refs (good)"
```
Expected: `no demo refs (good)` (confirms Task 1 Step 5 fully removed the demo section).

- [ ] **Step 3 (David): recommended commit**

```bash
git add CLAUDE.md
git commit -m "docs: update root CLAUDE.md architecture for area folders"
```

---

### Final acceptance gate (all must pass)

- [ ] `swift build` → `Build complete!`
- [ ] `./scripts/run-logic-tests.sh` → `All logic tests passed.`
- [ ] `./scripts/verify-streaming.sh` → `All streaming + recovery verification passed.`
- [ ] `swift build --build-tests` → `Build complete!`
- [ ] `git status` / `git diff --stat` shows only: demo deletions, 22 renames, the two script edits, five
  new `CLAUDE.md` briefs, and the root-`CLAUDE.md` edits — nothing unexpected.
