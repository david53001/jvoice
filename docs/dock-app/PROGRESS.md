# JVoice → Dock app — progress (branch `feat/dock-app`)

Worktree: `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/dock-app`,
branch `feat/dock-app`, based on `main` 4d786e6 (released v1.3.1). Approved plan (owner, 2026-10-25): JVoice
stops being a menu-bar agent (`LSUIElement` + `NSStatusItem`) and becomes a normal Dock app.

Terms: **HUD** = JVoice's floating "pill" at the bottom of the screen showing recording / transcribing / Pasted.
**`LSUIElement`** = Info.plist key that hides an app from the Dock (menu-bar-only apps). **Dock menu** = the menu
when you right-click an app's Dock icon. **Launch Apple Event** = the "open application" (`'oapp'`) event macOS sends
an app when it starts; its `keyAEPropData` parameter is `keyAELaunchedAsLogInItem` (`'lgit'`) when the app was
started as a login item. **Logic tests** = `scripts/run-logic-tests.sh` (the swift-testing suite must never run
on this Mac — see the repo `CLAUDE.md`). Every build/test here was wrapped in the shared lock
`lockf -k <scratchpad>/build.lock …` because another agent built BetterScreenshot in parallel.

## STATUS
Code + docs DONE and committed (2026-10-25). Not installed, not pushed, not released (version 1.4.0 build 10 is
local). Waiting for: the owner's live check on the installed app (list below), then install / merge / release.

## What changed (for a fresh session)
- `Resources/Info.plist`: no `LSUIElement`; 1.4.0 (build 10). Signing, bundle id, Sparkle keys untouched.
- `Sources/JVoice/JVoiceApp.swift`: plain AppKit entry (`NSApplication.shared`, `AppDelegate`, `run()`); the SwiftUI
  `App` with its never-inserted `MenuBarExtra` + `.commands` is gone (no SwiftUI scene can open a blank window or
  build its own menu any more).
- `Sources/JVoice/UI/AppMenus.swift` (new; replaces the deleted `UI/MenuBarController.swift`): main menu
  (JVoice · Edit · Window · Help) + Dock menu (`applicationDockMenu`). No key equivalent on Start Dictation.
- `Sources/JVoice/AppDelegate.swift`: `.regular` policy, installs the main menu in `applicationWillFinishLaunching`,
  reads the launch Apple Event, opens what `LaunchWindowPolicy` says; Dock click → Settings (Welcome forward on first
  run); `applicationDockMenu`.
- `Sources/JVoice/Services/Orchestration/LaunchWindowPolicy.swift` (new, pure): launch → Settings / none (at login) /
  Welcome (first run); reopen → Settings / Welcome; `isLoginItemLaunch` (`'oapp'` + `keyAEPropData` = `'lgit'`).
  A non-default launch (`NSApplication.launchIsDefaultUserInfoKey` = false in the did-finish-launching notification,
  e.g. macOS's "Reopen windows when logging back in" session restore, which may not carry `'lgit'`) also opens no
  window. The launch logs `Launch atLogin=<bool> isDefault=<bool> window=<…>` (subsystem `com.jvoice.app`, category
  `launch`).
- `VoiceCoordinator`: status-item wiring removed. Paste-target logic unchanged from `main`: when JVoice is frontmost
  at the stop, the target is the last OTHER app activated since JVoice started; none yet → "No text field focused"
  (a launch-time seed was tried and dropped after review — it pasted into Finder after a Finder launch).
- `refreshLaunchAtLogin(onlyChanges: true)` from the JVoice menu's `menuNeedsUpdate` (AppKit runs it on every
  key-equivalent search, e.g. each ⌘V in Settings): publishes only a real change, so Settings isn't redrawn.
- HUD + login card: `canHide = false`, excluded from the Window menu; tour tag panels copy the host's `canHide`.
- Welcome page line "JVoice lives in your Dock." carries anchor `welcome.dock` = Welcome tour step 1
  ("Your Dock icon"); `menuBar.icon` is gone from the catalog and the lint's extra anchors.
- `--settings-smoke` also builds + validates both menus. `LaunchAtLoginPromptController.isMenuOpen` is left
  unwired (documented in place).
- Tests: `MenuBarIconTests.swift` deleted (its code is gone); `LaunchWindowPolicyTests.swift` added (CI);
  `run-logic-tests.sh` section 5 covers the policy + checks the four-char codes against the SDK constants.

## DONE
- `82cda96` code (all of the above) + `be0fbde` docs (CLAUDE briefs, README, CHANGELOG 1.4.0 Unreleased,
  install.sh message, sparkle README notes).
- Verified on this Mac 2026-10-25, all under the shared build lock:
  - `swift build -c release`: Build complete, no new warnings in changed files.
  - `swift build --build-tests` (compile only, NOT run): Build complete.
  - assembled `.app` (`scripts/build-app.sh`) `--settings-smoke`: "Settings built, laid out and drawn (700×588)" +
    "main menu (39 items) and Dock menu (12 items) built".
  - `./scripts/run-logic-tests.sh`: 2738 assertions, 6 sections, 0 failures (incl. "welcome/Your Dock icon fits").
  - `./scripts/verify-tour-scroll.sh`: PASS (12 ✓). `./scripts/verify-streaming.sh`: passed (62 ✓).
  - `--ui-preview` (windows behind everything): Welcome all-set page shows "JVoice lives in your Dock." correctly.

- Review fixes (2026-10-25, after an independent review): session-restore launch → no window
  (`launchIsDefaultUserInfoKey`), launch-time paste-target seed dropped, `onlyChanges` refresh in the JVoice menu,
  `Window.none` → `.noWindow`. Re-verified: release build OK; `--settings-smoke` OK (39 / 12 menu items);
  logic tests 2741 ✓ 0 failures; test target compiles (not run). Tour-scroll / streaming code untouched.

## NEXT STEPS (owner / main session)
1. Install (`./scripts/dev-install.sh` from this worktree) and do the live checks below.
2. Merge `feat/dock-app` → `main`; at release time follow `docs/sparkle-updates/README.md` (date the CHANGELOG
   entry, README DMG link, notes).

## LIVE CHECKS (could not be done without showing UI / dictating / logging out)
- Dock icon appears; no "J" in the menu bar; Dock click opens Settings (also with the pill on screen); Dock
  click while Settings is open just brings it forward.
- Right-click Dock menu: Start/Stop Dictation (title flips while recording), Settings…, Launch at Login ✓,
  Help & Tours ▸, Check for Updates… / Update Available (X)…, plus the Dock's own Quit.
- Start dictation from the Dock menu while typing in another app → text lands in that app; JVoice never comes
  to the front during dictation/paste. Same from JVoice's own menu bar (text goes to the previous app).
- JVoice main menu: About; Settings… ⌘,; Hide ⌘H then dictate → pill still shows; Quit ⌘Q. Edit menu: ⌘V/⌘C/
  ⌘A/⌘Z in the API-key and Custom Words fields. Window: ⌘W hides Settings (app keeps running), Minimize greyed
  for Settings. Apple's own "Start Dictation…" should NOT be in the Edit menu.
- ⌥Space while Settings is frontmost → pastes into the previous app (unchanged behaviour), never into JVoice.
- Launch at login: log out/in with Launch at Login on → JVoice in the Dock, no window. Confirm with
  `/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jvoice.app" && category == "launch"'`
  → `Launch atLogin=true isDefault=… window=noWindow`. A Finder/Spotlight launch → `atLogin=false isDefault=true
  window=settings`.
- Restart (or log out) with "Reopen windows when logging back in" TICKED, Launch at Login on or off → JVoice comes
  back with no Settings window (log: `isDefault=false window=noWindow`, or `atLogin=true`).
- Right after opening JVoice from Finder (Settings in front, no other app clicked yet), ⌥Space → "No text field
  focused" (same as 1.3.1), not a paste into Finder.
- Whether a login launch leaves JVoice frontmost with only its menu bar (cosmetic; see RISKS).
- First-run flow (only on a test account / wiped domain): Welcome → "Show Me Around" → step 1 outlines the
  "JVoice lives in your Dock" line; Return keys / buttons on Welcome still work.
- Sparkle "Install and Relaunch" → the relaunch opens Settings (counts as a user launch; decided acceptable).

## RISKS / DECISIONS
- Login detection = `keyAELaunchedAsLogInItem` in the launch Apple Event. Widely used with `SMAppService.mainApp`
  (it can't pass launch arguments), but Apple doesn't document it for SMAppService and it's unverified on this
  macOS. If it fails, a login launch would open Settings (harmless, visible) — the log line above tells.
- A relaunch by Sparkle after an update, `open`, Finder, Spotlight all count as user launches → Settings opens.
- Dock tile shows no recording state (decided: the HUD already shows it; kept minimal).
- The Sparkle e2e throwaway build (`-DSPARKLE_E2E_TEST`) stays `.accessory` (no second JVoice in the Dock); not re-run.
- `TourCoordinator.extraAnchorWindows`, the Kit's menu-bar-host code in `TagOverlayController`, and
  `LaunchAtLoginPromptController.isMenuOpen` are now unused (left in place, documented — dead code not deleted).

## 2026-10-25 23:58 — merged + installed
- Local `main` fast-forwarded to `4a20d65` (not pushed, no release). `main` is checked out in worktree `.claude/worktrees/sparkle-updates`.
- Installed to `/Applications/JVoice.app` with `JVOICE_REQUIRE_IDENTITY=1 scripts/dev-install.sh`: 1.4.0 (build 10), signing certificate leaf `1164938a…` unchanged, so Microphone + Accessibility permissions carry over. Launch log: `Launch atLogin=false isDefault=true window=settings`. System Events shows a single menu bar (no status item) and the main menu JVoice · Edit · Window · Help.
- Previous install (1.3.0 build 8) backed up at `~/Backups/2026-10-25-pre-dock-app/JVoice-1.3.0-build8.app`.
- NEXT: the owner runs the live checks above; to ship publicly, set the CHANGELOG date, point the README DMG link at 1.4.0, push, and follow `docs/sparkle-updates/README.md` "How to cut a release".
