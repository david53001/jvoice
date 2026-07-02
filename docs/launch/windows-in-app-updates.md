# JVoice for Windows — in-app updates (feature handoff)

Windows-only. Branch **`feat/in-app-updates`** (worktree, branched from `feat/dictation-modes`
@ `c9ca6ad`). **NOT merged, NOT pushed.** David asked for an in-app "there's an update available"
prompt with a one-click Update button and a "marketing" progress bar (eased, no exact percentage,
fast-start / slow-finish). This is that feature. Recorded as `HANDOFF-WINDOWS.md §7 #36`.

> **Concurrency note:** a second Claude session is working `feat/dictation-modes` at the same time
> (its in-flight §7 **#34** = developer-terms AI expansion, **#35** = default model → Large). This
> branch took **#36** to avoid a numbering collision; at merge David gets #34/#35/#36 in sequence.
> This dedicated doc exists so my write didn't race the other session's live edits to the HANDOFF.

## What it does

- On startup **and then every 24 h while it runs** (opt-out), plus on demand from **Settings →
  Updates → "Check Now"**, JVoice asks GitHub for the latest release and compares it to the running
  build's version. The periodic re-check (added 2026-07-02) means a release published while JVoice is
  sitting in the tray still gets noticed without a restart — `UpdateCoordinator.StartAutoCheck()`
  fires the first check and schedules the daily one; the toggle starts/stops it live, and it stops
  hitting the network once an update is already surfaced.
- When a newer version exists: the **tray** shows a bold "**Update Available — Open Settings…**"
  item at the top, and the **Updates card** shows "Update available — vX.Y.Z" + an **"Update Now"**
  button.
- Clicking **Update Now** downloads the matching installer with an **eased progress bar** (a plain
  white fill, **no percentage text**), then launches the installer and quits so it can overwrite the
  install and relaunch JVoice.
- **Reframe David should know:** the app updates from a published **GitHub Release**, not from raw
  commits to `main`. The intended pipeline is *commit/tag on `main` → CI builds installers → creates
  a GitHub Release → the app sees the release*. Auto-updating on every commit is deliberately not the
  design (main isn't always release-ready, and each release is a 66–365 MB download).

## Gating reality (why it's dormant today)

- The repo/releases are **private**, so the anonymous GitHub API returns **404**, which the service
  treats as "no update" — the feature is **silently inert until David publishes** (repo or its
  Releases made public). Verified live: `JVoice.exe --update-check` prints `available: False`,
  `error: <none>` against `david53001/jvoice`.
- Edit **`UpdateConfig.RepoSlug`** at publish time (one place). If the two-account decision changes
  the target, that's the only edit needed.

## Privacy

The update check is the **second and only other network call** in the app besides the one-time GGML
model download. It is an anonymous `GET https://api.github.com/repos/<slug>/releases/latest` that
sends **no user data** (no telemetry, no identifiers) — only a `User-Agent: JVoice-Updater` header
GitHub requires. It runs only when **"Automatic Updates"** is on (default) or the user clicks "Check
Now". The Settings card discloses this: *"Check GitHub for a new version. No data is sent."*
**Assumption logged:** default is **ON** so the prompt David asked for actually appears; a user can
turn it off in Settings. This is a documented, disclosed exception to the "zero runtime network"
line — flag for David if he'd prefer it default-off.

## Architecture

**Pure Core (`JVoice.Core/Policy/`, unit-locked by `JVoice.Tests`, no I/O):**
- `ReleaseVersion.cs` — tolerant version parse/compare (v-prefix, 2–4 components, SemVer
  `-rc`/`+build` metadata ignored; unparseable → fails so a weird tag never prompts).
- `UpdateProgressCurve.cs` — the "marketing" curve. `FromFraction` = ease-out (ahead of real early,
  decelerates late, capped at `Ceiling = 0.95` so the bar sits just short of full until done);
  `FromElapsed` = time-based crawl when the server sends no Content-Length; `Display(...)` picks
  between them and returns 1.0 only when `done`.
- `UpdateCheck.cs` — `GitHubReleaseParser` (lenient JSON→`ReleaseInfo`), `UpdateAssetSelector`
  (picks `JVoice-Setup.exe` vs `JVoice-Setup-GPU.exe` by flavor, with fallbacks),
  `UpdateDecision.IsUpdateAvailable` (fail-safe: same/older/unparseable → no prompt).

**App (`JVoice.App/Update/`):**
- `UpdateConfig.cs` — repo slug, `Enabled` gate, `PreferCpuInstaller` (`#if JVOICE_CPU`), current
  version. **The one place to edit at publish.**
- `UpdateService.cs` — the only I/O: HTTP check (never throws; 404 → "no update", other failures →
  soft error shown only for user-initiated checks), streamed download with `(received, total?)`
  progress, `LaunchInstaller` (ShellExecute detached).
- `UpdateCoordinator.cs` — the state machine (`Idle/Checking/UpToDate/Available/Downloading/
  ReadyToRestart/Error`) + bindable surface. A ~30 ms `DispatcherTimer` eases a shown value toward
  the pure curve's target (monotonic, up-only) so the fill glides; on completion it fills to full,
  launches the installer, and quits after ~900 ms so file locks release.
- `UpdateProbeRunner.cs` — hidden `--update-check` CLI (runs the real query once, prints the result).

**Wiring:**
- `VoiceCoordinator` exposes `public UpdateCoordinator Updates { get; }`; `Start()` fires a silent
  startup check when `CheckForUpdatesAutomatically` is on; a `CheckForUpdatesAutomatically` bindable
  persists like the other toggles.
- `SettingsView.xaml` — new **"Updates" card** (Column 3, green accent): auto-check toggle, current
  version + "Check Now", status line, "Update Now", and the eased bar (a `Border` fill whose width =
  `FractionToWidthConverter(Updates.Progress, track.ActualWidth)`; converter added to
  `Converters.cs` + registered in `JVoicePalette.xaml`).
- `TrayIcon.cs` — bold "Update Available — Open Settings…" item when `Updates.UpdateAvailable`.
- `App.xaml.cs` — `--update-preview <state>` (live window) and `--settings-render <path> <state>`
  (headless screenshot) force a card state (`available|downloading|checking|uptodate|error`) with no
  network, for visual verification.

## Settings schema

Bumped **v3 → v4**: new `checkForUpdates` (bool, default **true**), Windows-only, per-field fallback
(absent → true). `SettingsState` / `SettingsStateJson` updated; `SettingsStateTests` /
`SettingsStoreJsonTests` updated (version asserts → 4, forward-version test → 5, key count 15 → 16,
new default + round-trip tests, fuzz range widened).

## The installer-apply step (packaging note)

On "Update Now" the app downloads `JVoice-Setup.exe` (matching flavor) to
`%TEMP%\JVoice-Update\`, launches it, and quits after ~900 ms so its files unlock. The **IExpress
`install.ps1`** (in the gitignored `windows/artifacts/`, not in the repo) **should wait for the old
JVoice process to exit before it robocopies** into `%LOCALAPPDATA%\Programs\JVoice` — add a
`Get-Process JVoice` poll (or a short `Start-Sleep`) at the top of the copy step as belt-and-braces.
The installer already relaunches JVoice when it finishes.

## Verification (done)

- `dotnet build windows/JVoice.sln -c Release` → **0 errors**.
- `dotnet test windows/JVoice.Tests` → **651/651** standalone (608 baseline + 43 new:
  `ReleaseVersionTests`, `UpdateProgressCurveTests`, `UpdateCheckTests`, + settings v4 cases);
  **693/693 after consolidation** with `feat/dictation-modes` #34/#35 (merge `0190e72`).
- Live HTTP seam: `JVoice.exe --update-check` → graceful "no update" (404) against the private repo.
- Visuals: `--settings-render <png> available|downloading|error` — the card renders in the
  three-column layout; the downloading state shows the eased white fill with **no % text**.

## How to turn updates ON — release runbook (2026-07-02)

The feature is code-complete and detection is ongoing (startup + 24 h re-check). It is **dormant
end-to-end** only because nothing is published for it to find. To make updates actually work, in
order:

**A. Prerequisite for CI automation — commit the packaging scripts.** The IExpress installer scripts
(`windows/artifacts/*.sed`, `install.ps1`, `uninstall.ps1`) are **gitignored → they live only on
David's machine**, so no GitHub Actions job can build the installers without them. To automate
releases, un-ignore + commit them (they hold no secrets). While there, add a `Get-Process JVoice`
wait-for-exit at the top of `install.ps1`'s copy step (the app quits *as* it launches the installer,
so robocopy must not race a still-locked file).

**B. Build the release-cutting workflow** (`.github/workflows/windows-release.yml`, ~follow-up, not
built): trigger on `push: tags: ['v*']`; `permissions: contents: write`; on `windows-latest` (which
has `iexpress.exe`): for each flavor {cpu, gpu} `dotnet publish -p:JVoiceFlavor=<f>` → zip the folder
→ `iexpress /N /Q windows/artifacts/JVoice-<f>.sed` → attach `JVoice-Setup.exe` +
`JVoice-Setup-GPU.exe` (+ `LICENSE.txt`) to a GitHub Release via `softprops/action-gh-release` with
`tag_name` = the pushed tag. **Pass `-p:Version=${TAG#v}` so the build version is derived from the
tag** — this kills the "forgot to bump `<Version>` → updates silently never detect" footgun.

**C. Version discipline.** The installed build is `1.0.0.0` (`JVoice.App.csproj <Version>`). A release
is only *detected* when its tag parses **higher** than the running build. So the first release
existing installs upgrade to must be e.g. **`v1.0.1`**.

**D. Prove the loop BEFORE trusting it.** The risky half — download → the installer overwrites JVoice
*while it runs* → relaunch — has **never been tested live**. Point `UpdateConfig.RepoSlug` at a
throwaway **public** test repo, cut a dummy `v1.0.1` release with a real installer asset, and watch
the app detect → download (eased bar) → install → reopen. Only then flip the real repo public.

**E. Ship a build that HAS the ongoing-detection change.** The periodic re-check (commit `a5f7f5c`)
currently sits on branch `docs/cross-platform-landing`; make sure the first public installer is built
from a branch that includes it (reconcile onto `windows-port`).

**F. Go live (David's call).** Make repo/Releases public → push a `v1.0.1` tag → CI cuts the Release →
running apps detect it within a day (or on next launch). Confirm anytime with
`JVoice.exe --update-check` (expect `available: True`).

## Still to do (David)

1. **Dogfood** the live flow once there's a real public release to point at (or temporarily aim
   `UpdateConfig.RepoSlug` at a public test repo): check → download bar → installer relaunch.
2. **CI release workflow** (the "commit/tag → release" half) is not built here — a GitHub Actions
   job on a `v*` tag that builds both flavors and publishes a Release. Left as a follow-up so this
   branch stays focused on the in-app UX; happy to add it next.
3. Add the `install.ps1` wait-for-exit line at the next installer rebuild (above).
4. ~~Slot the canonical HANDOFF §7 #36 + `CLAUDE.md` pointer.~~ **DONE** — consolidated into
   `feat/dictation-modes` (merge `0190e72`); HANDOFF §7 #34/#35/#36 + the CLAUDE.md pointer are all
   present and the schema note reads v4.
