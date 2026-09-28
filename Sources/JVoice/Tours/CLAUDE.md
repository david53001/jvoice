# Tours — the first-run guided tour (added 2026-09-28)

Ported from BetterScreenshot's guided tours (`../BetterScreenshot/Packages/TourKit` +
`App/Tours/TourCoordinator.swift` + its Welcome window's tour question; design there:
`docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md` §14 / §14.9).
David's ask: a tutorial that covers the whole app and teaches how to use it, but **only the first time** —
people who already use JVoice must never get it by itself.

## Terms
- **Tour** — an ordered list of **steps** for one **surface** (a window: the Welcome window, the
  recording pill, Settings).
- **Step** — one real control outlined with a box + a short **tag** (title, 1–2 line body, "n of m",
  Next / Skip Tour). **Explain** steps advance on Next (Return); **Try** steps advance by themselves when
  the user does the thing (the app posts a **tour event**); Skip Step / Skip Tour (Esc) always work.
- **Anchor** — a stable id ("<surface>.<name>") on a real control: `.tourAnchor("settings.model")` in
  SwiftUI, `view.tourAnchor = "menuBar.icon"` in AppKit (stored as the accessibility identifier). A
  step whose anchor isn't on screen is skipped.
- **Audience** — `new` or `existing`, decided ONCE and stored (`tourAudience`); never recomputed.

## Who gets what (the "only the first time" guarantee)
1. `JVoiceMain.main()` (`Sources/JVoice/JVoiceApp.swift`) calls `TourCoordinator.classifyAudienceIfNeeded`
   **before** `AppDelegate`/`VoiceCoordinator`/`SettingsStore` exist — `SettingsStore.init` writes
   `jvoice.app.settings.state` on a fresh install, so classifying later would call everyone "existing".
   `existing` if ANY of: a non-tour key in the `com.jvoice.app` preferences domain; Microphone or
   Accessibility already granted (macOS's privacy database, TCC, keeps grants across reinstalls); bundle id isn't `com.jvoice.app`
   (e.g. running from `.build/`). Doubt → existing: a missed new user is harmless, a nagged one isn't.
2. New users who haven't answered get the **Welcome window** at launch (`UI/WelcomeWindow.swift`):
   permissions page → "You're all set!" page asking **"Want a quick tour?"** (Show Me Around / No
   Thanks). Closing the window on EITHER page counts as No Thanks — JVoice launches at login, so an
   unanswered window would otherwise come back every login; quitting with it open asks again next launch. The answer sets `firstUseToursEnabled`; `tourQuestionAnswered` = true,
   so it's asked once. While that window will show, the launch-time Accessibility system prompt is
   suppressed (`VoiceCoordinator.suppressLaunchAccessibilityPrompt`) — the window asks instead.
3. A tour starts **by itself** only when `firstUseToursEnabled == true` (absent = off) and its version
   isn't in `toursSeen` (`TourRules.shouldAutoStart`). Existing users: no window, no automatic tour, ever
   (also not after a version bump). Everyone can run any tour on purpose: menu bar → Help & Tours,
   Settings' ⓘ, Settings → Tours & Tips (which also has the opt-in toggle and Reset All Tours).

Persisted UserDefaults keys (`TourPreferenceKey`, nothing else): `tourAudience`, `tourQuestionAnswered`,
`firstUseToursEnabled`, `toursSeen` (tour id → version), `toursPaused` (tour id → step to resume at).

## The tours (`TourCatalog.swift` — the contract; copy rules are lint-tested)
E = Explain step, T = Try step.

| Tour | Starts | Steps |
|---|---|---|
| Welcome | Show Me Around / menu / replay | E menu-bar J (`menuBar.icon`) · E dictation shortcut (`welcome.shortcut`) · T "Try it now" (`welcome.tryIt`, advances on `recording.started`) |
| Recording | first recording pill (`surfaceShown(.recordingPill)`) | T "JVoice is listening" (`pill.controls`, advances on `recording.stopped`) |
| Settings | first Settings window | E stats · model · processing · voice style · app modes · shortcut · recent transcripts · custom words · ⓘ (`settings.*`) |

Events (`TourEventName`, posted by `VoiceCoordinator`): `recording.started` (after the pill is shown,
on the next main-queue turn — never between the press and the pill/mic, see the latency contract in the
root `CLAUDE.md`), `recording.stopped` (before the pill leaves the recording state), `dictation.pasted`.

## Behaviour notes (decided while building, 2026-09-28)
- Tour confirmations ("Tours reset", "The recording tour starts at your next dictation") show as a
  neutral `HUDState.notice` pill via `VoiceCoordinator.showTourNotice` (`VoiceCoordinator+Tours.swift`),
  never over a recording/transcription.
- `recording.started` is posted only after the mic actually opened (a failed open posts nothing, so no
  tag appears over a permission dialog); `surfaceShown(.recordingPill)` only if that same recording is
  still on screen.
- The tag is **monochrome** (BetterScreenshot's is red): near-black bubble on light windows, white on
  dark, text contrast 19:1 (`Kit/TagStyle.swift`). Return = Next, Esc = Skip Tour — except while a
  Settings shortcut row is recording (`SettingsWindow` adopts `TourKeysClaiming`), and on the pill,
  which can never become key (its tag buttons are clickable instead).
- Tag bodies must fit 2 lines at 260 pt with the longest shortcut (⌃⌥⇧⌘F12); the fit check in the
  logic tests fails otherwise.

## Files
- `Kit/` — the ported engine, unchanged in behaviour: `TourModel` (ids, surfaces, events, steps),
  `TourEngine` (pure state machine: start/next/skip/pause/resume, Try-step matching, missing anchors
  skipped), `TourRules` (auto-start / ask rules, `{shortcut:…}` placeholders), `TourAudience` (the pure
  classifier + keys), `TourEvents` (the one-way bus surfaces post to; also `resetAll()` and
  `TourSettings`), `TourAnchor`, `TourTagPresenting` + `TagOverlayController`/`TagViews`/`TagLayout`/
  `TagStyle`/`TagKeys`/`TourHostShaping` (the on-screen tag: click-through dim, outline, leader, bubble;
  monochrome to match JVoice's theme), `InfoButton` (the ⓘ).
- `TourCoordinator.swift` — owns triggers, hand-overs, pausing (host window closed → pause; resumes
  next time), persistence and the tag. Surfaces never call it — they post through `TourEvents`.
- `TourCatalog.swift` — every tour + the menu titles.
- Wiring: `AppDelegate.swift` (creates + installs the coordinator, Welcome window at launch,
  `openSurface`, `notify`), `UI/WelcomeWindow.swift`, `UI/MenuBarController.swift` (Help & Tours submenu, `menuBar.icon`),
  `UI/HUDView.swift` (`pill.controls`), `UI/SettingsView.swift` + `SettingsWindow.swift` (anchors,
  Tours & Tips card, ⓘ, `surfaceShown(.settings)`), `VoiceCoordinator.swift` (events).

## Verify
- `swift build`; `./scripts/run-logic-tests.sh` (has a Tours section: engine, rules, audience, layout,
  catalog lint); `Tests/JVoiceTests/Tour*Tests.swift` run in CI only (**never** `swift test` locally).
- Any Settings change: `--settings-smoke` from an assembled `.app` (recipe in `UI/CLAUDE.md`).
- Never test against the real `com.jvoice.app` domain — use `UserDefaults(suiteName:)`. To see the
  first-run flow yourself on a machine that already ran JVoice you'd have to wipe the domain, which
  deletes the user's settings: don't, unless David asks.
