# HANDOFF — state as of 2026-06-06

Audience: the next Claude session (opened in this directory) and David. Read `CLAUDE.md` first for the rules; this file is the mutable status.

## Where this came from

David surveyed his ~14 projects looking for a new helpful-then-monetizable project. Decision: ship his existing work **free first** to build a portfolio and user base. JVoice (this repo) is app #1, extracted from `../MacOSUtils`. **BetterScreenshot (`../BetterScreenshot`) is planned as app #2** — strong demand at his school, including non-technical classmates; same launch pipeline applies.

## Decisions locked

- Free-first releases; monetize later (VoiceInk model is the researched blueprint: free source, paid prebuilt binary, one-time price, never subscription).
- $0 budget: no Apple Dev account yet → unsigned ad-hoc-signed DMG via GitHub Releases; no Homebrew (banned for unsigned, Sept 2026); GitHub Pages for the site.
- License: GPL-3.0 (LICENSE committed). David was told he can swap to MIT — he has not objected, but hasn't explicitly confirmed either.
- Demo media is generated programmatically with **Remotion** (David's explicit tool choice) and must match the real product UI exactly. He rejected a generic 10fps mockup.
- **Publishing is ON HOLD** — David explicitly said don't post to GitHub yet. gh CLI is authenticated (accounts: david53001 active, da97d). He confused local merge with publishing once; was reassured nothing leaves the machine (no remotes configured).

## What exists / shipped (all local, all committed on `main`)

- This repo: extracted app (builds: `swift build` → Build complete), 13 test files (execute in CI only), install/signing scripts, CI test workflow, README (+ `USER` placeholders), LICENSE, launch docs (`docs/launch/`), Remotion demo project (`docs/demo-video/`) and rendered assets (`docs/assets/demo.{gif,mp4}`).
- `../Portfolio` (separate git repo): static GitHub Pages-ready download site — landing + JVoice page with illustrated "Open Anyway" install guide; mobile-verified; demo gif wired in at `assets/jvoice-demo.gif`. BetterScreenshot listed as "coming soon".
- Memory files (note: stored under the `Code/` directory's project memory, NOT visible to sessions opened here — that's why this file exists): builder profile + launch plan.

## Verification

- `swift build` → "Build complete!"
- `open docs/assets/demo.mp4` → 20s demo: Notes opens → recording pill → transcription types in → menu bar → settings panel.
- Site: `open ../Portfolio/index.html` (or `python3 -m http.server` in that dir).

## Deferred / open questions

- **David has not yet confirmed watching the demo video** — get his verdict before treating Task "demo" as truly done; all timing/copy is parameterized in `docs/demo-video/src/`.
- **Release workflow not built**: GitHub Action for tag → release build → ad-hoc sign → `create-dmg` → GitHub Release. This is the next engineering task; without it the Download buttons point at nothing.
- **Dogfooding not done**: David should run `./scripts/install.sh` and use JVoice daily before launch.
- Publish steps when David says go: pick gh account → create public repos (this + Portfolio) → replace `USER` placeholders everywhere → push → enable Pages → repo topics + social preview → then the launch sequence in `docs/launch/distribution-plan.md`.
- License confirmation (GPL-3.0 vs MIT) — soft-confirmed GPL by silence.

## Pick up here

Most likely next action: build the release-DMG GitHub Actions workflow, then have David dogfood the app. Do NOT publish anything without his explicit instruction.
