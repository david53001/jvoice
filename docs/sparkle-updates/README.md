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
| Real end-to-end update test (good update installs, bad signature refused) | `scripts/sparkle-e2e-test.sh`; the `#if SPARKLE_E2E_TEST` parts of `Updates.swift`, `AppDelegate.swift`, `JVoiceApp.swift` (only in that test build) |
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
  this any time in the JVoice menu.", **No Thanks** (secondary) and **Open at Login** (primary).
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
    (follows JVoice's System / Light / Dark choice), the `.popover` behind-window material under a **0.75**
    `windowBackgroundColor` tint — slightly transparent — continuous 16 pt corners, a 0.5 pt hairline at 0.08, one
    system shadow, text styles (title `.body` semibold, line `.callout`, buttons `.callout`), all text `.primary`.
    **Contrast ≥ 4.5:1 is computed for the worst desktop** (pure black behind the light card, pure white behind the
    dark one; `LaunchAtLoginCardColors`): light 8.07:1 (7.00:1 on the secondary button), dark 5.84:1 (4.84:1 on the
    secondary button) — printed and checked by `scripts/run-logic-tests.sh`. The material's own blur/tint only
    moves the backdrop towards the tint, so real contrast is at least that. Secondary button = the design
    language's `SubtleButtonStyle`; primary = a label-colour fill with window-background text (≈ 14:1), same
    geometry — not `.borderedProminent`, which AppKit draws as an inactive grey button in a window that is never key.
    Rendered and looked at in light + dark (2026-10-18, own-window capture from a probe; the real-app
    `--ui-preview` could not save screenshots in this session, see STATUS).
- **No Thanks** → card goes, never asked again. **Open at Login** → `SMAppService.mainApp.register()`, then: enabled →
  "JVoice will open at login." for 1.6 s; `.requiresApproval` → "One more step / Allow JVoice in Login Items to
  finish." + **Done** / **Open Login Items** (`SMAppService.openSystemSettingsLoginItems()`); error (e.g. an unsigned
  dev copy) → "Couldn't turn it on. / You can try again with Launch at Login in the JVoice menu." + **Done**. Those
  two also go away by themselves after 25 s.
- **Menu item in sync:** JVoice has no Settings switch for this on `main` — the menu bar's **Launch at Login** item is
  the control. `LaunchAtLoginManager.setEnabled` posts `LaunchAtLoginManager.didChangeNotification`;
  `VoiceCoordinator.launchAtLogin` (which the menu item's checkmark reads) re-reads `SMAppService` on it. Any choice
  made with the menu item counts as answered (`setEnabled` marks it asked) and closes the card if it's up.
- **Answered at most once ever. Never asked if launch at login is already on** (checked when it becomes due and again
  right before showing; found on → marked asked, so later dictations don't make the XPC status call again).
- **Existing users**: if `jvoice.app.launchAtLogin.didInitialize` is set, ≤ 1.1.4 already turned it on for them; they
  either still have it (nothing to do) or turned it off on purpose (respected): never asked, uses not counted. In
  practice that is every existing user; the card is for new installs from 1.2.0 on.
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
seconds. Or just look at it: `--ui-preview <dir>` from an assembled bundle saves `login-card-{light,dark}.png`.

**Unmerged related branch:** `feat/launch-at-login` (worktree `.claude/worktrees/launch-at-login`, `2aa00cc`) adds a
Settings switch + a tour step. If it's merged after this branch, its switch must call `LaunchAtLoginManager.setEnabled`
(so a choice there counts as the answer and the card closes), observe `didChangeNotification`, and any tour text
claiming new users "have it on already" is wrong now.

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
```

What it does: builds once with `-DSPARKLE_E2E_TEST` (the app then starts ONLY the updater, logs each Sparkle step as
`SPARKLE-E2E …`, and installs right away instead of on quit), makes OLD (build 100, "90.0") and NEW (build 101,
"90.1") copies with bundle id `com.jvoice.app.sparkletest`, `SUFeedURL=http://127.0.0.1:8767/appcast.xml`,
`NSAllowsLocalNetworking`, `SUAutomaticallyUpdate`, signed inside-out with the real identity; zips NEW, EdDSA-signs
it with the real key; serves the feed with `python3 -m http.server --bind 127.0.0.1`; GOOD = real signature, BAD =
the signature of different bytes with the right length. It never touches `/Applications/JVoice.app`, the
`com.jvoice.app` defaults or a running JVoice; it quits what it started and deletes the test id's defaults, caches,
Launch Services entries and (unless `KEEP=1`) the work dir. `PORT=` changes the port.

Result on 2026-10-18 (this branch, `3b5775b`):

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

Not covered by the script: Sparkle's own windows (the path real users take — "Install Update" / "Install and
Relaunch"); BetterScreenshot's `E2E_UI=1` mode does that for its app and was not ported. A cross-certificate update
was tested on BetterScreenshot (Sparkle accepts it on the EdDSA signature); JVoice keeps its certificate, so it
doesn't need it. Manual check for the first real update (1.2.0 → 1.2.1): install 1.2.0, publish 1.2.1, then menu →
Check for Updates… → Install Update → Install and Relaunch; afterwards dictate once (Microphone + Accessibility must
still work without a prompt).

## STATUS / NEXT STEPS

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

Not done / owner decisions:

- [ ] **Not merged, pushed, tagged or released** (CLAUDE.md: needs David's go-ahead). Release steps above.
- [ ] `--ui-preview` couldn't save screenshots in this session (`could not create image from rect`: the terminal has
      no Screen Recording permission), so the **Settings → Updates card was not looked at**; only `--settings-smoke`
      proved it builds and draws. Run `--ui-preview` from a terminal with Screen Recording and check
      `settings-light.png` / `settings-dark.png` (right column, bottom) and `login-card-*.png`.
- [ ] The swift-testing suite (incl. the new `LaunchAtLoginPromptTests`) runs only in CI — check the CI run after pushing.
- [ ] Not tried on a real install: the card after 5 real dictations, `.requiresApproval`, Sparkle's own update windows.
- [ ] Back up the "JVoice Self-Signed" identity (see "Where the keys live").
- [ ] Bump `PRIVACY.md`'s effective date when 1.2.0 ships.
- [ ] Unmerged `feat/launch-at-login`, `feat/ai-polish`, `feat/math-context`, `feat/guided-tour`… branches were not
      touched; whichever merges second resolves trivial conflicts in `Resources/Info.plist` (version),
      `MenuBarController.swift`, `SettingsView.swift`, `AppDelegate.swift`, `CHANGELOG.md`.
