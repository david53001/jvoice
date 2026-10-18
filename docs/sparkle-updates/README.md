# JVoice: Sparkle auto-updates + the one-time "open at login?" prompt

Written 2026-10-18 for a fresh session with no context. JVoice is a SwiftPM macOS menu-bar dictation app
(no Xcode project; Command Line Tools only) in `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice`,
GitHub `david53001/jvoice` (**public** repo; the same repo also holds the Windows port under `windows/`). This
work is on branch **`feat/sparkle-updates`**, worktree
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/sparkle-updates`, based on
`origin/main` at `c0b97b6`. It copies the approach MacStats and BetterScreenshot got first (their
`docs/sparkle-updates/README.md` on their own `feat/sparkle-updates` branches), so all three apps behave alike.

## Glossary

- **Sparkle** (https://sparkle-project.org): the standard open-source auto-update framework for Mac apps outside
  the App Store. Version used: **2.10.0**, exactly.
- **Appcast**: an RSS/XML file listing available versions. Each installed app downloads it from its `SUFeedURL`
  and compares the newest item's `sparkle:version` with its own `CFBundleVersion`.
- **EdDSA signature**: every update zip is signed with a private ed25519 key; the app carries the matching public
  key (`SUPublicEDKey`) and refuses any download whose signature doesn't match. This is what makes updates safe,
  independent of Apple code signing.
- **Code signing identity**: the certificate `codesign` signs the app with. macOS ties JVoice's **Microphone** and
  **Accessibility** permissions (TCC, macOS's privacy-permission database) to it, through the app's *designated
  requirement* `identifier "com.jvoice.app" and certificate leaf = H"1164938af56472957620eeaaca96e33572677860"`.
- **`CFBundleVersion`** (build number, an integer) vs **`CFBundleShortVersionString`** (the "1.2.0" users see).
  Sparkle compares the build number.
- **rpath**: folders baked into the executable where the dynamic loader looks for frameworks.
- **Inside-out signing**: signing nested code first (Sparkle's helpers, then the framework), then the app, so each
  layer's signature covers already-signed contents. `codesign --deep` is not used: it re-signs nested code
  without its own options (here: the hardened runtime Sparkle's helpers ship with).
- **`SMAppService`**: macOS's Login Items API (`SMAppService.mainApp.register()` = open at login).
- **"Latest" release**: the GitHub release marked Latest; `releases/latest/download/<file>` always points at it.

## What was added

### 1. Sparkle auto-updates

| Piece | Where |
|---|---|
| `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")`, linked into the `JVoice` target with rpath `@executable_path/../Frameworks` | `Package.swift`, `Package.resolved` |
| `SUFeedURL` = `https://github.com/david53001/jvoice/releases/latest/download/appcast.xml`, `SUPublicEDKey` = `JrE6EncJErY++AZZXYrrwcNmcVzY/M2wgDWcCkaBf6U=`, `SUEnableAutomaticChecks` = YES (daily check, no "may we check?" dialog). Version **1.2.0**, build **7** (1.1.4 was 6; no branch has a higher one — checked with every local and remote branch's `Resources/Info.plist`) | `Resources/Info.plist` |
| Updater: `SPUStandardUpdaterController`, started at launch, "gentle reminders": a background find opens Sparkle's window *behind* other apps, without taking focus — except when Sparkle chooses "immediate focus" (its default when the app was launched recently, e.g. at login, or the Mac had been idle): then it opens in front, as in most Mac apps. So a window behind others isn't missed, the menu item and the Settings button both read **"Update Available (X)…"** (`Updates.actionTitle`) until the user looks at it. No notification (JVoice never asks for that permission). | `Sources/JVoice/Services/Orchestration/Updates.swift` (started in `AppDelegate`) |
| Menu bar: **Check for Updates…** under Help & Tours (greyed out while a check runs) | `Sources/JVoice/UI/MenuBarController.swift` |
| Settings → **UPDATES** card (right column, under Tours & Tips): **Check Automatically** switch ("Look for a new version once a day."), the same **Check for Updates…** / **Update Available (X)…** button, "You have JVoice X." | `Sources/JVoice/UI/SettingsView.swift` (`updatesSection`) |
| Bundle: copies `Sparkle.framework` into `Contents/Frameworks` (ditto, keeps symlinks), removes its `XPCServices`, `Headers`, `PrivateHeaders`, `Modules`; deletes every rpath except `/usr/lib/swift` and `@executable_path/../Frameworks` (SwiftPM also bakes in `@loader_path` and the CLT's swift-6.2 folder); fails if an `@rpath` library other than Sparkle appears. Env vars `JVOICE_APP` (destination), `JVOICE_SWIFT_FLAGS`, `JVOICE_REQUIRE_IDENTITY=1` | `scripts/build-app.sh` (new — the ONE way a JVoice.app is assembled; `package-release.sh`, `dev-install.sh` and the e2e test all use it) |
| Signing, inside-out, no `--deep`: `Autoupdate`, `Updater.app`, the framework (all `-o runtime`, as Sparkle ships them), then the app with identifier = its bundle id (`com.jvoice.app`), no entitlements, no hardened runtime (as before) | `scripts/sign-app.sh` (new) |
| SDK pin: the CLT's default MacOSX27.0 SDK can't build SwiftUI macros, so the scripts use `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` when present (an `SDKROOT` you set wins). Same file as the sibling apps. | `scripts/sdk-env.sh` (sourced by `build-app.sh`) |
| One-command release | `scripts/package-release.sh` (rewritten) |
| Real end-to-end update test (good update installs, bad signature refused; `E2E_UI=1`: through Sparkle's own windows, the path real users take) | `scripts/sparkle-e2e-test.sh`; `Sources/JVoice/Services/Orchestration/SparkleE2EUI.swift` and the `#if SPARKLE_E2E_TEST` parts of `Updates.swift`, `AppDelegate.swift`, `JVoiceApp.swift` (only in that test build: on the release binary `nm` finds no `SparkleE2EUI` symbol and `strings` no `SPARKLE-E2E`) |
| Privacy policy + README now mention the macOS update check | `PRIVACY.md`, `README.md` |

**Not sandboxed** (checked: JVoice has no entitlements file at all, so no `com.apple.security.app-sandbox`). So
Sparkle installs through its bundled `Autoupdate` / `Updater.app`; the framework's XPC services are only for
sandboxed apps (and only when `SUEnableInstallerLauncherService` / `SUEnableDownloaderService` are set, which they
aren't), and Sparkle's docs say a non-sandboxed app may remove them, so `build-app.sh` does. The end-to-end test
passes without them.

**Why the app has no hardened runtime:** it never had one (not notarized; $0 budget, no Apple Developer account).
Hardened runtime turns on library validation, which would refuse a `Sparkle.framework` signed by a self-signed
certificate (no Team ID).

**Network:** the only network traffic Sparkle adds is the appcast + zip download from GitHub (no system profile:
`SUEnableSystemProfiling` is unset). CLAUDE.md used to say "zero network calls at runtime (only the one-time
Whisper model download)"; `PRIVACY.md` §"The only times JVoice uses the network" item 2 now covers macOS too (and
its Windows endpoint was corrected to the list endpoint the code really uses). **Owner to-do:** bump the
"Effective date" at the top of `PRIVACY.md` when 1.2.0 is published.

**A bare binary no longer launches:** `.build/release/JVoice` now links `@rpath/Sparkle.framework`, so a
hand-assembled bundle without `Contents/Frameworks/Sparkle.framework` dies at launch (dyld). The Settings smoke
recipe in `Sources/JVoice/UI/CLAUDE.md` was changed to use `scripts/build-app.sh`; `dev-install.sh` now uses it too.
(`--bench`, `--math-probe` straight from `.build/release/JVoice` still work: in the build folder Sparkle sits next
to the binary and `@loader_path` finds it.)

### 2. "Open JVoice at login?" after 5 dictations

Before: up to 1.1.4, the first launch turned launch at login on silently
(`LaunchAtLoginManager.performFirstRunEnableIfNeeded()`, called from `VoiceCoordinator.bootstrapLaunchAtLogin()`,
flag `jvoice.app.launchAtLogin.didInitialize`). That is **removed**. Now:

- A **use** = one dictation whose text reached the user: pasted, or copied in clipboard-only mode
  (`VoiceCoordinator.onDictationCompleted`, called at the very end of `finishTranscription`, right after the
  `dictationPasted` tour event). A cancelled recording, "No speech detected", a too-short recording, a
  transcription error, or a refused paste (no Accessibility / target rejected / clipboard busy) isn't one.
- After the **5th** use, the app checks once a second (for up to 120 s; the next dictation tries again) for a **calm
  moment**: ≥ 3 s since that dictation, no key pressed for ≥ 2 s (`CGEventSource.secondsSinceLastEventType`, needs no
  permission), no mouse button down, the menu-bar menu closed (`MenuBarController.isMenuOpen`), **no dictation
  activity at all** (`VoiceCoordinator.isDictationActive`: recording, mic opening, stopping, transcribing,
  pasting, or any HUD pill — incl. "Pasted" and errors — on screen), none of JVoice's windows in front
  (`NSApp.isActive` false: not while in Settings or Welcome), no guided-tour tag on screen, and **nothing
  full-screen in front** (the frontmost app has no window exactly the size of a screen, menu bar included; from
  `CGWindowListCopyWindowInfo`, bounds and owners need no permission). Then it shows the card.
- **The card** (`Sources/JVoice/UI/LaunchAtLoginCard.swift`): a notification-style card in the **top-right** corner of
  the screen under the pointer, 12 pt below the menu bar (the HUD lives at the bottom centre, so they never overlap).
  The app icon, **"Open JVoice at login?"**, "Your dictation shortcut keeps working after a restart. You can change
  this any time in Settings or the JVoice menu." (since 1.3.0; 1.2.0 said "in the JVoice menu"), **No Thanks** (secondary) and **Open at Login** (primary).
  - Never takes focus: a borderless `.nonactivatingPanel` that can't become key; its buttons take the first click
    (`FirstClickHostingView`). So no keyboard shortcuts on it (there's no focus to receive them) — by design. VoiceOver
    announces the title and line when it appears and can reach its buttons; the full keyboard alternative is the
    menu's **Launch at Login** item, which answers the question too.
  - **Unanswered, it goes away by itself** after **25 s** (not while the pointer is on it), like a macOS banner, so it
    never sits over a presentation or a shared screen. It stays due. **Only a showing the user could have seen
    counts** (`LaunchAtLoginPrompt.Showing`): ≥ 5 s during which the card's window was visible
    (`occlusionState.contains(.visible)` and `isOnActiveSpace`) **and** the user had used the mouse or keyboard since
    it appeared. A counted showing brings it back after a dictation **≥ 24 h later or after a relaunch**; after the
    **3rd** counted one it counts as answered "no". An uncounted one comes back after a dictation ≥ 10 min later.
  - Joins every Space but not full-screen ones (no `.fullScreenAuxiliary`).
  - **Design** (MacStats `docs/design-language/README.md`, JVoice `Sources/JVoice/UI/CLAUDE.md`): system light/dark
    (follows JVoice's System / Light / Dark choice), the `.popover` behind-window material under a **0.8**
    `windowBackgroundColor` tint — slightly transparent — continuous 16 pt corners, a 0.5 pt hairline at 0.08, one
    system shadow, text styles (title `.body` semibold, line `.callout`, buttons `.callout`), all text `.primary`.
    **Contrast ≥ 4.5:1 is computed for the worst desktop** (pure black behind the light card, pure white behind the
    dark one; `LaunchAtLoginCardColors`), on the card and on the secondary button in all three of its states
    (resting / under the pointer / pressed = fills 0.08 / 0.12 / 0.16, checked to equal `Design`'s small-button
    fills): light 9.02:1 (button 7.81 / 7.24 / 6.69), dark 6.86:1 (button 5.59 / 5.05 / 4.57) — printed and checked
    by `scripts/run-logic-tests.sh`. (Round 1 used a 0.75 tint, which left the dark card's button at 4.41:1 under
    the pointer and 4.03:1 pressed.) The material's own blur/tint only
    moves the backdrop towards the tint, so real contrast is at least that. Secondary button = the design
    language's `SubtleButtonStyle`; primary = a label-colour fill with window-background text (≈ 14:1), same
    geometry — not `.borderedProminent`, which AppKit draws as an inactive grey button in a window that is never key.
    Rendered and looked at in light + dark from the real app's `--ui-preview` (2026-10-18, drawn from the views
    because the terminal has no Screen Recording, so the blur is flat): `docs/sparkle-updates/previews/login-card-*.png`.
- **No Thanks** → card goes, never asked again. **Open at Login** → `SMAppService.mainApp.register()`, then: enabled →
  "JVoice will open at login." for 1.6 s; `.requiresApproval` → "One more step / Allow JVoice in Login Items to
  finish." + **Done** / **Open Login Items** (`SMAppService.openSystemSettingsLoginItems()`); error (e.g. an unsigned
  dev copy) → "Couldn't turn it on. / You can try again with Launch at Login in Settings or the JVoice menu." + **Done**. Those
  two also go away by themselves after 25 s.
- **Controls in sync:** in 1.2.0 the menu bar's **Launch at Login** item was the only control; since **1.3.0**
  Settings → **Startup → Launch at Login** is a second one (same `VoiceCoordinator.setLaunchAtLogin` path, so
  everything below applies to it too; `.requiresApproval` shows an **Open Login Items** button there). `LaunchAtLoginManager.setEnabled` posts `LaunchAtLoginManager.didChangeNotification`;
  `VoiceCoordinator.launchAtLogin` (which the menu item's checkmark reads) re-reads `SMAppService` on it. Any choice
  made with the menu item counts as answered (`setEnabled` marks it asked) and closes the card if it's up.
- **Answered at most once ever. Never asked if launch at login is already on** (checked when it becomes due and again
  right before showing; found on → marked asked, so later dictations don't make the XPC status call again).
- **Existing users**: if `jvoice.app.launchAtLogin.didInitialize` is set, ≤ 1.1.4 tried to turn it on for them: it
  wrote that flag *before* a silent `try? setEnabled(true)`. They are never asked and their uses aren't counted. Most
  of them still have it or turned it off on purpose, but the call could also have failed silently (e.g.
  `.requiresApproval`, or an unregistered copy), and the flag can't tell "turned off" from "never succeeded". So a
  few existing users who never had it won't be asked either. **This is a deliberate trade-off**: better to miss a
  few than to ask someone who already said no. In practice that is every existing user; the card is for new
  installs from 1.2.0 on.
- Same rules and wording as BetterScreenshot (5 uses, once, legacy flag, a choice elsewhere counts as an answer,
  25 s auto-hide, ≤ 3 seen showings) and MacStats (titles, "No Thanks" / "Open at Login" / "One more step" /
  "Couldn't turn it on."). Differences: a use is a dictation; the "change it later" pointer names the JVoice menu.

**UserDefaults keys** (domain `com.jvoice.app`, all `jvoice.app.*` like the rest of JVoice):

| Key | Type | Meaning |
|---|---|---|
| `jvoice.app.launchAtLoginPrompt.uses` | Int | Completed dictations counted so far (stops at 5) |
| `jvoice.app.launchAtLoginPrompt.asked` | Bool | Answered on the card, chosen with the menu item, ignored 3 times, or launch at login found on: never ask again |
| `jvoice.app.launchAtLoginPrompt.unansweredShowings` | Int | Times the card hid itself unanswered after the user could see it (3 → asked) |
| `jvoice.app.launchAtLoginPrompt.lastShownAt` | Double | When the last such showing ended, seconds since 1970 (0 = never) |
| `jvoice.app.launchAtLogin.didInitialize` | Bool | Legacy, **read only**: ≤ 1.1.4 auto-enabled launch at login |

Code: rules + flow steps (`afterUse`, `waitStep`, `isCalmMoment`, `fullScreenInFront`, `shouldHideUnanswered`,
`Showing`, `cardHidUnanswered`, `mayShowAgain`) and the contrast math in
`Sources/JVoice/Services/Orchestration/LaunchAtLoginPrompt.swift` (pure Foundation + CoreGraphics, behind a small
storage protocol so tests use an in-memory store and never write a plist); flow
`Sources/JVoice/UI/LaunchAtLoginPromptController.swift`; card `Sources/JVoice/UI/LaunchAtLoginCard.swift`; wiring
`Sources/JVoice/AppDelegate.swift` (`installLoginPrompt`); `Sources/JVoice/Services/Orchestration/LaunchAtLoginManager.swift`.
Tests: section 5 of `scripts/run-logic-tests.sh` (90 assertions, runs on this Mac) and
`Tests/JVoiceTests/LaunchAtLoginPromptTests.swift` (swift-testing, CI only — never run the suite on this Mac, see
CLAUDE.md; it was type-checked locally only).

To see the card on a dev build without 5 dictations (only on a copy whose settings you're happy to change, NOT the
owner's running app — use a bundle with a different `CFBundleIdentifier`): `defaults write <id>
jvoice.app.launchAtLoginPrompt.uses -int 5`, make sure `jvoice.app.launchAtLoginPrompt.asked` and
`jvoice.app.launchAtLogin.didInitialize` are unset, launch at login off, dictate once, then don't type for a few
seconds. Or just look at it: `--ui-preview <dir>` from an assembled bundle saves `login-card-{light,dark}.png`
(`login-card-{light,dark}-views.png` when the terminal has no Screen Recording permission).

**Related branch, now ported:** `feat/launch-at-login` (worktree `.claude/worktrees/launch-at-login`, `2aa00cc`, never
merged) built a Settings switch + a tour step. Release 1.3.0 re-did its switch and tour step on top of this work
(`release/1.3.0`): the switch calls `VoiceCoordinator.setLaunchAtLogin` → `LaunchAtLoginManager.setEnabled` (a choice
there counts as the answer and closes the card), the coordinator re-reads `SMAppService` on `didChangeNotification`,
and that branch's first-launch auto-enable was NOT brought back. Don't merge the old branch.

## Where the keys live (and their backups)

- **Sparkle EdDSA private key**: login Keychain, item "Private key for signing Sparkle updates", account `ed25519`.
  Sparkle's tools read it from there (`sign_update` worked without a prompt on 2026-10-18). Off-Keychain backup:
  `~/Backups/sparkle-signing-key/` (its `README.md` explains the files and how to restore with
  `~/Developer/Sparkle/2.10.0/bin/generate_keys -f ~/Backups/sparkle-signing-key/sparkle-ed25519-private-key.txt`).
  Same key for all three apps. **Never commit, print or upload the private key.** If it's lost, installed copies
  can't be updated any more (they'd need a manual reinstall with a new key).
- **Code signing identity "JVoice Self-Signed"**: login keychain (`security find-identity -p codesigning login.keychain`
  shows `1164938AF56472957620EEAACA96E33572677860 "JVoice Self-Signed"`), created by `scripts/setup-signing.sh`. It is
  the **same certificate** as every published macOS release (checked 2026-10-18: the v1.1.4 `JVoice.app.zip` and the
  copy in `/Applications` both have `certificate leaf = H"1164938a…"`), so an update keeps users' Microphone and
  Accessibility permissions. `package-release.sh` refuses any other certificate (`RELEASE_CERT`). Losing it means every
  user re-grants both permissions once; **back it up** (Keychain Access → export "JVoice Self-Signed" with its private
  key as a .p12 into `~/Backups/`, password in your password manager) — not done by this session.
- Sparkle CLI tools: `/Users/davidghermansteinberg/Developer/Sparkle/2.10.0/bin` (`sign_update`, `generate_appcast`,
  `generate_keys`). The same tools come with the SwiftPM artifact in `.build/artifacts/sparkle/Sparkle/bin`.

## How to cut a release (step by step)

From the main checkout `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice` on `main`, with this branch
merged (JVoice's CLAUDE.md: **no pushing or publishing without David's explicit go-ahead**):

```sh
# 0. (first time only) merge: git checkout main && git merge --no-ff feat/sparkle-updates
# 1. Bump the version in Resources/Info.plist:
#    CFBundleShortVersionString (e.g. 1.2.0 -> 1.2.1) AND CFBundleVersion (+1, e.g. 7 -> 8; never reuse one).
#    For 1.2.0 itself, skip the plist bump: this branch already set 1.2.0 / build 7.
#    Every release (1.2.0 too): update the versioned DMG link in README.md ("Prefer a manual download?",
#    still JVoice-1.1.4.dmg on this branch) and date the CHANGELOG.md entry.
# 2. Tests (local; the swift-testing suite runs in CI on push):
./scripts/run-logic-tests.sh && ./scripts/verify-streaming.sh
# 3. Commit the bump and push it (package-release.sh refuses a dirty tree or HEAD != origin/main):
git commit -am "Release 1.2.1" && git push origin main
# 4. Release notes (Markdown, outside the repo so the tree stays clean); they become the GitHub notes and
#    Sparkle's update text. Then build + sign + zip + DMG + EdDSA-sign + appcast:
scripts/package-release.sh ~/Desktop/jvoice-1.2.1-notes.md
# 5. Run the gh command the script printed, which looks like (--target = the packaged commit):
gh release create v1.2.1 "…/dist/JVoice.app.zip" "…/dist/JVoice-1.2.1.dmg" "…/dist/appcast.xml" \
   --repo david53001/jvoice --target <sha> --latest --title "JVoice 1.2.1" --notes-file "…/dist/release-notes.md"
# 6. Check the feed every installed copy reads:
curl -fsSL https://github.com/david53001/jvoice/releases/latest/download/appcast.xml | grep sparkle:version
```

Dry run (anything uncommitted, not on main, …): `ALLOW_DIRTY=1 ALLOW_NOT_MAIN=1 scripts/package-release.sh` — writes
`dist/dry-run/*-DRYRUN*` files (appcast with `edSignature="DRYRUN-not-signed"`), prints no gh command. Never upload them.

The first Sparkle-capable release (1.2.0) is still installed by hand or with the `install.sh` one-liner: users on
≤ 1.1.4 have no updater. From 1.2.0 on, updates arrive by themselves.

### The `--latest` rule

Every installed Mac copy reads `https://github.com/david53001/jvoice/releases/latest/download/appcast.xml`. So:

- **Every macOS release must be created with `--latest`** (the printed command has it).
- **Every Windows release must be created with `--latest=false`** (`gh release create windows-vX.Y.Z … --latest=false`),
  or all Macs stop seeing updates until the next Mac release. Windows releases are made by hand (no workflow publishes
  them: `.github/workflows/windows.yml` only builds and tests, `permissions: contents: read`); the rule is in
  `docs/launch/windows-distribution.md` and `CLAUDE.md`. `windows-v1.1.0` was published that way (2026-10-03); `v1.1.4`
  is Latest today. Fix a mistake with `gh release edit <newest mac tag> --repo david53001/jvoice --latest`.
- The Windows in-app updater lists releases (`api.github.com/repos/david53001/jvoice/releases`) and picks the newest
  Windows one, and `scripts/install.sh` picks the newest release carrying `JVoice.app.zip`, so neither depends on Latest.

## How to re-run the end-to-end test

```sh
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/sparkle-updates   # or main once merged
scripts/sparkle-e2e-test.sh                                          # ~4 min the first time (debug WhisperKit build)
E2E_BUILD_DIR=$PWD/.build/sparkle-e2e scripts/sparkle-e2e-test.sh    # keeps the build for quicker re-runs (delete after)
KEEP=1 scripts/sparkle-e2e-test.sh /tmp/jv-e2e                       # keep the work dir (logs, bundles, feed)
E2E_UI=1 KEEP=1 scripts/sparkle-e2e-test.sh /tmp/jv-e2e-ui            # Sparkle's real windows (see "UI mode" below)
```

What it does: builds once with `-DSPARKLE_E2E_TEST` (the app then starts ONLY the updater, logs each Sparkle step as
`SPARKLE-E2E …`, and installs right away instead of on quit), makes OLD (build 100, "90.0") and NEW (build 101,
"90.1") copies with bundle id `com.jvoice.app.sparkletest`, `SUFeedURL=http://127.0.0.1:8767/appcast.xml`,
`NSAllowsLocalNetworking`, `SUAutomaticallyUpdate`, signed inside-out with the real identity; zips NEW, EdDSA-signs
it with the real key; serves the feed with `python3 -m http.server --bind 127.0.0.1`; GOOD = real signature, BAD =
the right length but the signature of the good zip with one byte appended (so it can never match). It never
touches `/Applications/JVoice.app`, the `com.jvoice.app` defaults or a running JVoice; it quits what it started and
deletes the test id's defaults, caches, Launch Services entries (the copies and the `Updater.app` inside each one's
`Sparkle.framework`, which Sparkle launches and Launch Services registers too) and (unless `KEEP=1`) the work
dir. `PORT=` changes the port.

Result on 2026-10-18 (this branch, `3b5775b`; re-run after the round-1 fixes with the same result, GOOD PASS +
BAD PASS, and no `jv-e2e` / `sparkletest` record left in `lsregister -dump` afterwards):

```
==> GOOD: signed update 100 -> 101
OLD pid 43418 loads Sparkle from: /var/folders/…/install/JVoice.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle
after 1s: installed build 101
SPARKLE-E2E found 90.1 (build 101)
SPARKLE-E2E downloaded 101
SPARKLE-E2E ready to install 101; installing now
SPARKLE-E2E installing 101
installed copy: codesign --verify --deep --strict OK
Identifier=com.jvoice.app.sparkletest
Authority=JVoice Self-Signed
installed copy: version 90.1 (build 101)
running after relaunch: 43499 /private/var/folders/…/install/JVoice.app/Contents/MacOS/JVoice
==> BAD: zip whose EdDSA signature doesn't match
SPARKLE-E2E found 90.1 (build 101)
SPARKLE-E2E downloaded 101
SPARKLE-E2E aborted: … Code=3002 "EdDSA signature does not match. …"
==> RESULT
GOOD update installed (build 101): PASS
BAD signature refused (still build 100): PASS
```

### UI mode (`E2E_UI=1`): the path real users take

The default run installs at once (`SUAutomaticallyUpdate` + the `immediateInstallationBlock` hook), so it never shows
Sparkle's windows. `E2E_UI=1` runs one scenario instead of GOOD/BAD: OLD has **no** `SUAutomaticallyUpdate` and runs
with `SPARKLE_E2E_UI=1`, which turns on `Sources/JVoice/Services/Orchestration/SparkleE2EUI.swift` and makes the
immediate-install hook step aside (`return false`, only the logging delegate stays), exactly like a real install. It
logs `pendingVersion` when the scheduled find sets it; waits for Sparkle's update window and logs whether it came up
key, the frontmost app and the menu title (`Updates.actionTitle`); does what the menu item does
(`Updates.showSparkleWindow`, minus activating the app); clicks **Install Update**; when **Install and Relaunch**
appears logs `pendingVersion` again (must be cleared by then) and clicks it. Sparkle's `Updater.app` installs and
relaunches; the script checks the copy is build 101, passes `codesign --verify --deep --strict` and is running again.
Every window of the test app is transparent the moment it appears; after its first snapshot the app hands focus back
to the app that was in front (the script prints "Don't type for about 30 s"). Snapshots (`cacheDisplay`) go to
`<work-dir>/ui/` and show layout and buttons but drop most label text. Ported from BetterScreenshot's mode of the
same name.

Result 2026-10-18 (round-1 fixes; the Mac was locked, idle 11 098 s, so the frontmost app was
`com.apple.loginwindow`):

```
SPARKLE-E2E found 90.1 (build 101)
SPARKLE-E2E UI scheduled update 90.1, immediate focus 1
SPARKLE-E2E UI will show 90.1: handled by Sparkle 1, user-initiated 0
SPARKLE-E2E UI pending set by the scheduled find: 90.1
SPARKLE-E2E UI update window shown: key 0, app active 0, frontmost app com.apple.loginwindow
SPARKLE-E2E UI menu title: Update Available (90.1)…
SPARKLE-E2E UI after the menu action: pending 90.1, menu title: Update Available (90.1)…
SPARKLE-E2E UI focus now: app active 0
SPARKLE-E2E UI clicking Install Update
SPARKLE-E2E UI user attention for 90.1
SPARKLE-E2E downloaded 101
SPARKLE-E2E UI at Install and Relaunch: pending none, menu title: Check for Updates…
SPARKLE-E2E UI clicking Install and Relaunch
SPARKLE-E2E installing 101
installed copy: codesign --verify --deep --strict OK
Identifier=com.jvoice.app.sparkletest
Authority=JVoice Self-Signed
==> RESULT (UI mode)
the scheduled find set pendingVersion (90.1): PASS
update window shown by the scheduled check: PASS
(SPARKLE-E2E UI scheduled update 90.1, immediate focus 1; Mac idle 11098 s)
(the update window came up without focus: frontmost app com.apple.loginwindow)
without focus: no keyboard taken (not key, app not active): PASS
without focus: the menu reads Update Available (90.1)…: PASS
Sparkle reports the user's attention: PASS
pendingVersion cleared once the user acted (menu back to Check for Updates…): PASS
the test app doesn't keep the keyboard (not active a second later): PASS
Install and Relaunch was offered and clicked: PASS
installed as build 101: PASS
relaunched after the install (pid 60527): PASS
```

What this showed: Sparkle asked for immediate focus (the Mac was idle) but couldn't take it from the lock screen,
so the window waited without focus and the gentle-reminder label **"Update Available (90.1)…"** was up, as
designed. The no-activation menu action didn't clear it (Sparkle reports attention when the window is seen; the
real menu item activates JVoice first, which this test deliberately skips); clicking Install Update did, and the
label went back to "Check for Updates…". The other branch, the window coming up **key** (immediate focus on an
unlocked Mac: attention reported at once, the label never shows), is checked by the script when it happens; it
did not happen on this run. BetterScreenshot's identical code verified it there.

Not covered: installing on quit (an update that was downloaded but deferred and is installed when the app quits;
the script can't quit the app gracefully without an Apple-event permission prompt). A cross-certificate update was tested on BetterScreenshot (Sparkle
accepts it on the EdDSA signature); JVoice keeps its certificate, so it doesn't need it. Manual check for the first
real update (1.2.0 → 1.2.1): install 1.2.0, publish 1.2.1, then menu → Check for Updates… → Install Update →
Install and Relaunch; afterwards dictate once (Microphone + Accessibility must still work without a prompt).

## STATUS / NEXT STEPS

### Release 1.3.0 (prepared 2026-10-18, NOT pushed / tagged / published / installed)

1.2.0 (build 7) is published as GitHub release `v1.2.0` (Latest). Branch **`release/1.3.0`**, worktree
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/release-1.3.0`, made from local
`main` = `origin/main` = `42612be` ("Release 1.2.0"). Commits: `9f7296d` = `git merge feat/ai-polish` (no rebase/squash;
`feat/ai-polish` already contains `feat/math-context` and `feat/math-format` — `git merge` of those two says "Already up
to date"), then the 1.3.0 commit (Launch at Login switch, version 1.3.0 / build 8, docs), then a docs commit with these
results.

What 1.3.0 is (CHANGELOG `[1.3.0]`): opt-in AI Polish (Claude, user's own Anthropic key in
`~/Library/Application Support/JVoice/anthropic-api-key` — NOT the Keychain since 2026-10-17 —, prepaid local balance,
prompt v2), context-aware Greek letters + the shared maths notation, Opacity setting + its tour step, resizable masonry
Settings, no blank Settings window, and the new **Settings → Startup → Launch at Login** switch.

How the conflicts were resolved (both sides kept): Settings = AI Polish's masonry list + main's **Updates** card (+ the
new **Startup** card); AppDelegate = main's login card + ai-polish's reopen handler (a no-op in the `SPARKLE_E2E_TEST`
build); `run-logic-tests.sh` = both new sections (6 now); UIPreviewRunner = ai-polish's in-process capture + main's
Updates/login-card shots + a new invisible `--offscreen` mode; CI's Settings-smoke step now uses `build-app.sh` (a
hand-made bundle without Sparkle.framework can't launch since 1.2.0). The 5-use login prompt still counts at the very end
of `finishTranscription` (`onDictationCompleted`), after AI Polish, so a polished and an unpolished dictation count the
same, and failed/cancelled ones (incl. one cancelled during the polish) don't. `isDictationActive` covers the new
`.refining` pill. "Check Automatically" stays default ON (`SUEnableAutomaticChecks` = YES, unchanged).

Launch at Login switch: `SMAppService.mainApp.status` is the source of truth (`VoiceCoordinator.refreshLaunchAtLogin()` →
`launchAtLogin` + `launchAtLoginNeedsApproval`, on launch, on `LaunchAtLoginManager.didChangeNotification`, on menu open,
on the card's appear / any window becoming key, after every change). Switch, menu item and card all end in
`LaunchAtLoginManager.setEnabled` (marks the card answered, closes it if it is up, posts the notification). Only
`.requiresApproval` shows **Open Login Items**. No first-launch auto-enable. The card's text now says "in Settings or
the JVoice menu".

Verified 2026-10-18 on this Mac (background only, nothing shown on screen; real output in the release session's report):
- [x] `swift build -c release` (SDK 26.5 via `scripts/sdk-env.sh`): Build complete, no new warnings in changed files.
- [x] `./scripts/run-logic-tests.sh`: **2716 assertions in 6 sections, 0 failures** (incl. "Settings tour: Opacity →
      Launch at login (Startup switch) → ⓘ" and "settings/Launch at login fits").
- [x] `./scripts/verify-streaming.sh`: "All streaming + recovery verification passed." `./scripts/verify-tour-scroll.sh`: PASS.
- [x] `--settings-smoke` from a `build-app.sh` copy re-identified `com.jvoice.app.previewtest` (scratch dir):
      "OK — Settings built, laid out and drawn (700×588)". Its defaults domain + Launch Services record removed after.
- [x] `--ui-preview <dir> --offscreen` from the same copy: 16 drawings (Settings at designed/wide/fill/small/bottom size,
      fill with a forced "Update Available (1.2.1)…", the login card + its "done" line, Light + Dark). Looked at: the
      Updates, Startup and AI Polish cards fit both the 2- and 3-column layouts with nothing clipped. Not committed:
      the AI Polish card shows the last 4 characters of the real saved key (`••••xxxx`, read from the key file).
      *(Fixed in review round 1: `--ui-preview` and `--settings-smoke` now use a temp key folder with a dummy key,
      so renders show `••••0000`.)*
- [x] `scripts/sparkle-e2e-test.sh` (non-UI mode) on the merged code: **GOOD update installed (build 101): PASS**,
      **BAD signature refused (still build 100): PASS**, codesign strict OK, Authority=JVoice Self-Signed; no leftover
      process, Launch Services record or work dir; `/Applications/JVoice.app` (pid 4073) untouched.
- [x] `scripts/package-release.sh` refuses without overrides ("HEAD is not origin/main"); dry run
      `ALLOW_NOT_MAIN=1 scripts/package-release.sh` (tree clean): JVoice 1.3.0 (build 8), codesign OK, Authority=JVoice
      Self-Signed, zip 3.46 MB, DMG 3.86 MB, appcast `sparkle:version` 8 with `DRYRUN-not-signed`; no gh command
      printed. Dry-run files deleted afterwards.

Not verified here (owner-only checks):
- [ ] The swift-testing suite (incl. the new `TourCatalogTests.settingsTourShowsLaunchAtLoginAfterOpacity` and the AI
      Polish tests) — CI only; never on this Mac. Check the `test.yml` run after pushing (also the reworked smoke step).
- [ ] Flipping the switch on a real, signed install (registers a real login item — not done by design); the
      `.requiresApproval` caption/button (can't force that state); the card ↔ switch sync live with Settings open.
- [ ] Looking at Settings, the tour's new "Launch at login" step (`tour-login-*`) and the HUD with real translucency:
      `--ui-preview <dir>` without `--offscreen` (windows appear behind everything for ~1 s each).
- [ ] AI Polish live with a key (dogfood steps: `docs/ai-polish/PROGRESS.md` → "David: manual test steps").

#### Independent review round 1 (8/10, `docs/release-1.3.0/REVIEW-round1.md`), fixed 2026-10-18

- [ ] **M1 (Medium) swift-testing suite never run on the merged code + the unexplained intermittent signal-6
      abort at suite start** (3 sightings on `feat/ai-polish`, `docs/ai-polish/PROGRESS.md` → CI). Can't be fixed
      on this branch: the suite runs only in CI (never on this Mac, root CLAUDE.md) and the branch may not be pushed
      by a session. Turned into a hard **release gate** in the steps below: after `git push origin main`, the
      `test.yml` run on that exact commit must be green **3 times in a row** before `package-release.sh`. I read
      the log of the 3rd abort (run 39035152148): the line is only `error: Exited with unexpected signal code 6`
      at 0.5 s, interleaved with ~560 parallel test starts, no message and no test name — so no root cause can be
      found from it; the "Print test-process crash reports" step (added after it, `441e4a2`) is what will name it.
      Record the run ids in "CI gate for 1.3.0" below.
- [x] **L1 AI Polish switch subtitle** now names everything sent: "Sends the text of each dictation (never the
      audio), with your custom words and your last few dictations in that app, to Anthropic's Claude to fix
      mistakes. Off until you turn it on." (`SettingsView.swift`). Off-screen renders checked: 3 lines in the
      3-column fill layout, 4 lines in the 2-column bottom layout, nothing clipped.
- [x] **L2 "balance used up" notice can't be lost:** `VoiceCoordinator.pendingBalanceNotice` (stored, was a local)
      is set when `record` returns true and shown + cleared on the next dictation that reaches the user (the same
      one, or the next one if a paste failure / cancel ended it early); skipped if money was added meanwhile.
      Closes fix #4 of `docs/ai-polish/REVIEW.md`. Not exercised live (needs a real billed polish that empties the
      balance); compiled + logic harness green.
- [x] **L3 balance wording:** CHANGELOG now says "You set a budget (approximate)" and explains that late replies
      and Test Key aren't deducted; hard cap = the key's spend limit in the Anthropic console (as PRIVACY.md says).
- [x] **L4 previews never read the real key:** `APIKeyStore.useScratchDirectory(fakeKey:)` points the store at a
      fresh temp folder (removed at exit); `--ui-preview` saves a dummy (`••••0000` in the renders), `--settings-smoke`
      none. Checked: renders show `••••0000`; the temp folder is gone after the run.
- [x] **L5 stale "Keychain" wording** fixed in `SettingsState.swift`, `run-logic-tests.sh`, `PROGRESS.md` (State
      table, decisions 2/3/7 marked superseded 2026-10-17, the eval how-to) and the AI Polish card's doc comment.
      Left as is: historical log lines (eval results / CI run 100) and the swift-testing case name
      `theDeadlineAlsoCoversABlockingKeychainRead` (renaming a test that can only run in CI isn't worth it).
- [x] **L6 release notes:** `docs/release-1.3.0/release-notes.md` (committed, plain language, leads with "AI Polish
      is new, optional and off"). It is what every 1.2.0 user reads in Sparkle's update window and on GitHub.
- [x] **L7 `.requiresApproval`:** caption changed to "Waiting for your OK in Login Items, where you can also turn it
      off." Behaviour unchanged on purpose (the switch reads OFF and re-registers): a different behaviour can't be
      tested here because the state can't be produced. Owner-only check: if you ever see that state, confirm the
      caption + **Open Login Items** button.
- Nit (not mine to delete): `~/Library/Preferences/com.jvoice.app.previewtest.plist` (42 bytes, empty) is still there;
  `rm ~/Library/Preferences/com.jvoice.app.previewtest.plist` if you like.
- Verification after the fixes (2026-10-18, background only, nothing shown on screen): `swift build -c release`
  (SDK 26.5) Build complete, only the existing `WelcomeWindow.swift:153` warning; `./scripts/run-logic-tests.sh`
  **2716 assertions, 6 sections, 0 failures**; `./scripts/verify-streaming.sh` passed; a `build-app.sh` copy in the
  scratchpad re-identified `com.jvoice.app.fixtest` (ad-hoc): `--settings-smoke` "OK — Settings built, laid out and
  drawn (700×588)", `--ui-preview --offscreen` 16 drawings (looked at fill-light and bottom-dark). Afterwards its
  defaults domain, Launch Services record and the copy's prefs were gone (no new plist in `~/Library/Preferences`).
  Sparkle code/scripts unchanged in this round, so the E2E was not re-run.

Review round 2 (2026-10-18): **8.5 / 10**. Reports are not in the repo (round 1 quotes the last 4 characters
of the owner's API key): `~/Backups/2026-10-18-release-1.3.0-reviews/JVoice/` on the owner's Mac. Round-2 Lows
fixed after it: L-A (`Updates.swift` comment names AI Polish), L-C (TERMS.md §5 paragraph on AI Polish +
effective date), L-D (re-date step moved before the push below). **L-B skipped:** `run-logic-tests.sh` leaves
small `jvoice.test.*` / `jvoice.logic.*` plists in `~/Library/Preferences`. Removing them in the script was
tried and doesn't hold: cfprefsd rewrites the empty domain files after the test process (and an exit trap)
has deleted them. They're 42-byte test-only files; clear them any time with
`rm ~/Library/Preferences/jvoice.test.*.plist ~/Library/Preferences/jvoice.logic.*.plist`.

#### CI gate for 1.3.0 (fill in after the push)

| Attempt | Run id | Commit | Result |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Owner's release steps (from the main checkout, after review; `--latest` rule above):

```sh
# `main` is checked out in the sparkle-updates worktree (the main checkout is on feat/guided-tour), so work there:
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/JVoice/.claude/worktrees/sparkle-updates
git merge --ff-only release/1.3.0                           # main has not moved since 42612be, so this fast-forwards
./scripts/run-logic-tests.sh && ./scripts/verify-streaming.sh
# (publishing on another day than CHANGELOG [1.3.0] says? re-date it + PRIVACY.md/TERMS.md now, BEFORE the push,
#  so the commit the CI gate tests is the one that gets packaged)
git push origin main                                         # CI runs test.yml on this commit
# CI GATE (review M1): 3 greens in a row on this exact commit before packaging.
gh run list --repo david53001/jvoice --workflow test.yml --commit "$(git rev-parse HEAD)"   # note the run id
gh run watch <id> --repo david53001/jvoice                   # attempt 1
gh run rerun <id> --repo david53001/jvoice && gh run watch <id> --repo david53001/jvoice   # attempt 2
gh run rerun <id> --repo david53001/jvoice && gh run watch <id> --repo david53001/jvoice   # attempt 3
# Any red: open the failed attempt's "Print test-process crash reports" step, fix the faulting test or
# initializer, commit, push, and start the 3 greens again. Write the run ids in "CI gate for 1.3.0" above.
scripts/package-release.sh docs/release-1.3.0/release-notes.md   # then run the printed `gh release create v1.3.0 … --latest`
curl -fsSL https://github.com/david53001/jvoice/releases/latest/download/appcast.xml | grep sparkle:version   # → 8
```

Then: the first real Sparkle update (1.2.0 → 1.3.0) on an installed 1.2.0: menu → Check for Updates… → Install Update
→ Install and Relaunch; dictate once (Microphone + Accessibility must still work without a prompt).

### 1.2.0 work (feat/sparkle-updates, released 2026-10-18 as v1.2.0)

Done on `feat/sparkle-updates` (2026-10-18), commits `31987d4` (app code + tests), `3b5775b` (scripts) and the docs
commit after it:

- [x] Sparkle 2.10.0 via SwiftPM, rpath, embedded + inside-out signed, XPC services removed (not sandboxed)
- [x] Info.plist feed/key/automatic checks; 1.1.4 (6) → **1.2.0 (7)**
- [x] Check for Updates… in the menu; Settings → Updates card (switch + button)
- [x] `package-release.sh`: one command → zip + DMG + EdDSA signature + appcast + printed `gh … --latest` command.
      Dry run passed (`ALLOW_DIRTY=1 ALLOW_NOT_MAIN=1`: zip 3.1 MB, DMG 3.5 MB, valid appcast, `codesign` OK,
      Authority=JVoice Self-Signed); refusals checked (dirty tree, HEAD ≠ origin/main). The non-dry path (real names +
      printed gh command) only runs on `main` = `origin/main`, so it was not executed.
- [x] `--latest` rule documented (Windows releases are made by hand; no workflow to fix)
- [x] Launch-at-login prompt after 5 dictations; silent first-launch enable removed
- [x] Tests: `./scripts/run-logic-tests.sh` → 1077 assertions in 5 sections, all pass (section 5 = the prompt, 90);
      swift-testing file type-checked against the CLT Testing framework (not run: never on this Mac)
- [x] `swift build -c release` clean (no new warnings); `--settings-smoke` OK from an assembled bundle (700×588)
- [x] End-to-end update test: GOOD installs (build 101, codesign strict OK), BAD refused — output above
- [x] Card rendered in light + dark and looked at (probe; folder icon there only because the probe isn't a bundle)

Round 1 of the independent review (8.2/10; report `docs/sparkle-updates/REVIEW-round1.md`, not committed), fixed
2026-10-18 in the commit after `a74c611`:

- [x] **M1 real update path**: `E2E_UI=1` mode ported (`SparkleE2EUI.swift`, script, `Updates.showSparkleWindow`);
      run: 10/10 PASS (output in "UI mode" above): pendingVersion set by the scheduled find, "Update Available
      (90.1)…" while the window waited without focus, cleared once the user acted, Install Update → Install and
      Relaunch through `Updater.app`, build 101 installed, codesign strict OK, relaunched.
- [x] **M2 Settings → Updates card looked at**: `--ui-preview` now falls back to drawing windows from their views
      (`NSView.cacheDisplay`) without Screen Recording, and also saves Settings scrolled to the Updates card, once
      with a forced "Update Available (1.2.1)…" (`Updates.showPendingVersionForPreview`). Looked at in light + dark
      (`docs/sparkle-updates/previews/settings-update-available-*.png`): switch row, button and "You have JVoice
      1.2.0." fit on one line with room to spare, the caption isn't shrunk, the card lines up with the column.
      32 PNGs saved; `UI/CLAUDE.md`'s "offscreen rendering comes back blank" corrected (true only of
      `ImageRenderer` / `CALayer.render`). Limits of the fallback: flat materials, no tour-tag panel, and the HUD
      pill comes out as a light capsule even in Dark (Liquid Glass) — judge the HUD with Screen Recording.
- [x] **L1 contrast**: hover and pressed fills checked too; the tint went 0.75 → 0.8 so every state is ≥ 4.5:1
      (dark pressed 4.57:1); the fills are asserted equal to `Design`'s (the logic test now compiles `Theme.swift`);
      doc comment fixed (`.popover`, not `.hudWindow`).
- [x] **L2 Launch Services**: cleanup also unregisters each copy's `Updater.app`; the stale
      `tmp.iy67ovZvEq/…/Updater.app` record was removed (`lsregister -u`). After both runs `lsregister -dump` lists
      no `jv-e2e` / `sparkletest` path. (Older `Updater.app` records from MacStats' and BetterScreenshot's e2e runs
      are still listed: dead paths, harmless, out of this branch's scope; their scripts have the same gap.)
- [x] **L3 `docs/launch/windows-distribution.md`**: restored from `origin/main` with CRLF endings, the paragraph
      re-applied with CRLF (diff: 6 insertions, 2 deletions), and `` `JVoice\runtimes\` `` written correctly.
- [x] **L4 root `CLAUDE.md` line 3**: now names the optional daily update check (Sparkle; `PRIVACY.md`).
- [x] **L5 legacy-user rule**: reworded here and in `LaunchAtLoginPrompt.swift` as a deliberate trade-off.
- [x] **L6 BAD case**: signature of the good zip + one appended byte (deterministic); comment fixed.
- [ ] **L7 CI**: still open — can't be done without pushing (not allowed on this branch yet). After the push,
      check the `test.yml` run on macos-15 / Xcode 16 executes the `LaunchAtLoginPromptTests` cases.
- [x] **N1 menu item while open**: the update item now also follows `pendingVersion` / `canCheck` while the menu
      is open (Combine on the main queue, which runs during menu tracking). Not exercised by hand. The card's lack
      of a keyboard path and the possible overlap with a notification banner are by design / shared with the
      sibling apps, unchanged.
- Verification after the fixes: `swift build -c release` clean (only the warnings already on main);
  `./scripts/run-logic-tests.sh` 1082 assertions, 0 failures; `./scripts/verify-streaming.sh` passed;
  `--settings-smoke` OK (700×588) on a copy re-identified as `com.jvoice.app.previewtest` (its defaults domain and
  Launch Services record removed afterwards); `scripts/sparkle-e2e-test.sh` GOOD PASS + BAD PASS;
  `E2E_UI=1` 10/10 PASS; `/Applications/JVoice.app` (pid 4073) kept running, untouched.

Not done / owner decisions:

- [ ] **Not merged, pushed, tagged or released** (CLAUDE.md: needs David's go-ahead). Release steps above.
- [ ] The Settings → Updates card and the login card were looked at drawn from their views (flat materials); a
      look with real translucency needs `--ui-preview` from a terminal with Screen Recording.
- [ ] The swift-testing suite (incl. the new `LaunchAtLoginPromptTests`) runs only in CI — check the CI run after pushing.
- [ ] Not tried on a real install: the card after 5 real dictations, `.requiresApproval`. Sparkle's own windows were
      driven on the test copy (`E2E_UI=1`), but only the "window without focus" branch ran; the "comes up key" branch
      and installing on quit were not seen on JVoice.
- [ ] Back up the "JVoice Self-Signed" identity (see "Where the keys live").
- [ ] Bump `PRIVACY.md`'s effective date when 1.2.0 ships.
- [ ] Unmerged `feat/launch-at-login`, `feat/ai-polish`, `feat/math-context`, `feat/guided-tour`… branches were not
      touched; whichever merges second resolves trivial conflicts in `Resources/Info.plist` (version),
      `MenuBarController.swift`, `SettingsView.swift`, `AppDelegate.swift`, `CHANGELOG.md`.
