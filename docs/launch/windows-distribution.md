# JVoice for Windows — unsigned distribution & SmartScreen

The Windows analog of the macOS Gatekeeper "Open Anyway" findings
(`unsigned-distribution-findings.md`). $0 budget → **no paid code-signing certificate** →
JVoice ships as an **unsigned** download. This documents what users see and how to ship.

## What ships

- A **zipped self-contained folder** (`JVoice-<gpu|cpu>-win-x64.zip`), not a bare `.exe`.
  - **GPU build** (`JVoiceFlavor=gpu`): includes CUDA + Vulkan + CPU native runtimes. Larger.
  - **CPU build** (`JVoiceFlavor=cpu`, folder): small, CPU-only. The reliable "lite" download.
  - **Not** a single-file exe: WPF can't be trimmed and Whisper.net 1.9.1 can't load its native
    runtime from a bundled single-file (`Assembly.Location` is empty there). The folder build is
    verified working; the single-file is not shipped.
- Each zip includes `LICENSE.txt` (GPL-3.0 obligation).
- Self-contained: the .NET 9 runtime is bundled — users need nothing pre-installed.
- The speech model (`ggml-*.bin`, 74–547 MB) is **not** in the zip; it downloads on first use
  from Hugging Face to `%LOCALAPPDATA%\JVoice\models\` (the one allowed runtime network call).

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
