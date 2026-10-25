# JVoice → Dock app — progress (branch `feat/dock-app`)

Worktree: `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/dock-app`,
branch `feat/dock-app`, based on `main` 4d786e6 (released v1.3.1). Approved plan (owner, 2026-10-25): JVoice
stops being a menu-bar agent (`LSUIElement` + `NSStatusItem`) and becomes a normal Dock app.

## STATUS
In progress (started 2026-10-25, overnight autonomous session).

## DONE
- `82cda96` code: pure AppKit entry, `.regular`, no `LSUIElement`, `UI/AppMenus.swift` (main + Dock menu),
  `LaunchWindowPolicy` (+ logic tests + `Tests/JVoiceTests/LaunchWindowPolicyTests.swift`), Welcome tour step 1
  → `welcome.dock`, HUD/card `canHide = false`, paste-target seeding, smoke builds menus, 1.4.0 (build 10).
  Verified: release build OK; `--settings-smoke` OK (main menu 39 items, Dock menu 12); logic tests 2738 ✓;
  tour-scroll 12 ✓; streaming 62 ✓; test target compiles (`swift build --build-tests`, NOT run).

## NEXT STEPS
1. `--ui-preview` look at Welcome / Settings.
2. Docs (CLAUDE.md files, README, PRIVACY, install.sh message, sparkle README), CHANGELOG.
3. Final diff review + report.

## RISKS
- Login-item detection relies on `keyAELaunchedAsLogInItem` in the open-application Apple Event; needs a real
  logout/login check on the installed app.
