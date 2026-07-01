# JVoice for Windows — unsigned distribution & SmartScreen

The Windows analog of the macOS Gatekeeper "Open Anyway" findings
(`unsigned-distribution-findings.md`). $0 budget → **no paid code-signing certificate** →
JVoice ships as an **unsigned** download. This documents what users see and how to ship.

## What ships — two installers (CPU default, GPU optional)

The user-facing download is a **one-click installer**: an IExpress self-extractor that wraps a
**self-contained folder build**, unpacks it to `%LOCALAPPDATA%\Programs\JVoice`, creates Start-Menu
+ Desktop shortcuts and an Add/Remove-Programs entry, and launches. No admin needed. Two flavors:

| Download | Flavor | Size | For |
| --- | --- | --- | --- |
| **`JVoice-Setup.exe`** | `JVoiceFlavor=cpu` (folder) | ~66 MB | **Everyone — the default.** CPU-only; runs on any Windows 10/11 x64 PC. |
| `JVoice-Setup-GPU.exe` | `JVoiceFlavor=gpu` (folder) | ~365 MB | **Optional, NVIDIA owners.** Bundles CUDA + Vulkan + CPU runtimes for GPU-accelerated transcription. |

**Which one?** → **Most people: `JVoice-Setup.exe`.** Only grab the GPU build if you have an
**NVIDIA GPU** and want the speed-up — it's ~5× larger and falls back to CPU on machines without a
supported GPU, so there's no benefit to it otherwise. Both transcribe identically; the GPU build is
just faster on capable hardware.

- A plain `JVoice-<gpu|cpu>-win-x64.zip` of the same folder is the no-installer alternative.
- **Not** a single-file exe: WPF can't be trimmed and Whisper.net 1.9.1 can't load its native
  runtime from a bundled single-file (`Assembly.Location` is empty there). The folder build is
  verified working; the single-file is not shipped.
- Self-contained: the .NET 9 runtime is bundled — users need nothing pre-installed.
- Ship `LICENSE.txt` alongside the binary (GPL-3.0 obligation) — add it to the folder before
  zipping/packaging.
- The speech model (`ggml-*.bin`, 74–547 MB) is **not** bundled; it downloads on first use
  from Hugging Face to `%LOCALAPPDATA%\JVoice\models\` (the one allowed runtime network call).

The installers are built with IExpress from `windows/artifacts/` (gitignored): publish each flavor
to a folder, zip the folder as `app.zip` (top-level `JVoice\`), then `iexpress /N /Q JVoice-<flavor>.sed`
packages `app.zip` + `install.ps1` + `uninstall.ps1` into the setup `.exe`. See the `.sed` files and
`install.ps1` in `windows/artifacts/sfx-build/` / `windows/artifacts/JVoice-<gpu|cpu>.sed`.

## What the user sees (SmartScreen)

Because the build is unsigned and has no reputation, **Microsoft Defender SmartScreen** shows a
blue dialog on first launch:

> **Windows protected your PC** — Microsoft Defender SmartScreen prevented an unrecognized app
> from starting. Running this app might put your PC at risk.

The "Run anyway" button is hidden behind **"More info"**:

1. Click **More info**.
2. Confirm the publisher line reads **Unknown publisher** and the app is **JVoice.exe**.
3. Click **Run anyway**.

This is the exact analog of macOS Gatekeeper's "Open Anyway". It is a one-time prompt per
download; once the user runs it, subsequent launches are silent. Document this prominently on
the download page and in the README so users aren't scared off.

### Reducing the prompt (future, optional)
- **Reputation:** SmartScreen relaxes as a binary accrues downloads over time (slow, free).
- **Signing:** an OV/EV code-signing cert removes the prompt but costs money (out of scope at $0).
  An EV cert grants instant reputation; an OV cert still warms up over time.
- **winget / Microsoft Store:** out of scope for the unsigned $0 model (the Store requires
  packaging + an account).

## In-app updates (built; branch `feat/in-app-updates`)

JVoice has a built-in updater (full detail: `windows-in-app-updates.md`; HANDOFF §7 #36). It checks
**GitHub Releases** (not raw `main` commits) and, when a newer version exists, shows an "Update
available" prompt + one-click **Update Now** in **Settings → Updates** (and a tray item). "Update
Now" downloads the matching `JVoice-Setup(-GPU).exe`, launches it, and quits so it can overwrite +
relaunch.

- **Pipeline to wire at publish:** *commit/tag on `main` → CI builds both installers → publishes a
  GitHub Release* — the app polls `releases/latest`. A release-cutting GitHub Actions workflow is a
  follow-up (not built yet).
- **Dormant until public:** the check is an anonymous GitHub API GET; while the repo/releases are
  private it 404s → "no update", so shipping this changes nothing until David publishes. Point
  `UpdateConfig.RepoSlug` at the release repo at publish time (one edit).
- **Privacy:** this is the only runtime network call besides the one-time model download and sends
  **no user data**; it's opt-out in Settings ("Automatic Updates", default on). Note it on the
  download page alongside the SmartScreen step.
- **Installer wait-for-exit:** since the app quits right as it launches the installer, add a
  `Get-Process JVoice` wait at the top of `install.ps1`'s copy step so robocopy never races a still-
  locked file.

## Zipping the build (PowerShell, in-box)

```powershell
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=gpu `
  -p:SelfContained=true -p:PublishTrimmed=false -p:PublishReadyToRun=true -o out/gpu
Copy-Item LICENSE out/gpu/LICENSE.txt
Compress-Archive -Path out/gpu/* -DestinationPath JVoice-gpu-win-x64.zip -Force
```

(Repeat with `-p:JVoiceFlavor=cpu -p:PublishSingleFile=false` for the CPU "lite" zip.)

## ARM64

CUDA is x64-only. An ARM64 build (`-r win-arm64 -p:JVoiceFlavor=cpu`) is CPU-runtime-only.
`Whisper.net.Runtime` ships ARM64 CPU binaries; `Whisper.net.Runtime.Cuda` does not. Build on
demand by swapping the RID; verify `Whisper.net.Runtime` has a `win-arm64` native asset first.

## Do NOT publish without David's go-ahead

Same rule as the macOS side: no `gh release`, no pushing, no posting. This doc is the playbook
for *when* David decides to publish — it is not an instruction to publish now.
