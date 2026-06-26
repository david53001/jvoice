# JVoice for Windows — release notes (DRAFT)

> **Staging only — not published.** This is the ready-to-use body for a GitHub Release on
> `david53001/jvoice` (currently **private**). Publishing it = making the repo/release public,
> which is on hold until David's explicit go-ahead. When that happens: attach the two installers
> from `~/Downloads` as release assets and paste the section below as the release description.
> Built from commit `6f8ffc2` (two-column Settings). Tag suggestion: `win-v1.0.0`.

---

## JVoice for Windows — v1.0.0

Free, private, on-device voice dictation. Press **Ctrl + Shift + Space** anywhere → speak → JVoice
transcribes locally with Whisper and pastes the text into whatever app you're in. No accounts, no
telemetry, no cloud — the only network call is a one-time speech-model download on first use.

### ⬇️ Which download do I need?

| Download | Pick this if… | Size |
| --- | --- | --- |
| **`JVoice-Setup.exe`** ← **most people** | You just want it to work on any Windows 10/11 PC. CPU-only. | ~65 MB |
| `JVoice-Setup-GPU.exe` | You have an **NVIDIA GPU** and want faster transcription (CUDA/Vulkan). | ~360 MB |

Both produce identical transcripts — the GPU build is only *faster* on supported hardware, and it
falls back to CPU anyway, so there's no reason to grab the larger file unless you have an NVIDIA
GPU. **When in doubt, get `JVoice-Setup.exe`.**

### Install

1. Download the installer above and run it.
2. It's **unsigned** ($0 project, no paid certificate), so Windows SmartScreen will show
   *"Windows protected your PC."* Click **More info → Run anyway**. (One-time, per download.)
3. It installs to `%LOCALAPPDATA%\Programs\JVoice`, adds a Start-Menu shortcut, and launches to the
   system tray. No admin required.
4. First dictation downloads the speech model (~74 MB Tiny by default) once, then everything is
   offline.

### Use

- **Ctrl + Shift + Space** to start/stop recording (rebindable in Settings).
- Lives in the system tray — right-click for Settings, Start/Stop, Launch at Login, Quit.
- Settings is a two-column panel: model, processing, voice style, language, custom words,
  corrections, recent transcripts, gaming mode, and the hotkey.

### Requirements

- Windows 10 / 11, 64-bit (x64).
- A microphone.
- ~200 MB disk for the app + ~74–550 MB for the speech model you choose.
- Optional: an NVIDIA GPU (for the GPU build's acceleration).

### Notes

- **Private & offline:** no telemetry, no accounts; recordings are deleted right after
  transcription. The only network access is the one-time model download from Hugging Face.
- **License:** GPL-3.0. Source is in this repo.
- **Don't run it elevated** unless you specifically need the hotkey inside admin windows — the
  normal (non-elevated) mode is the supported path.
