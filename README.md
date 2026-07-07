<div align="center">

<img src="docs/assets/icon.png" alt="JVoice" width="104" height="104">

# JVoice

**Free, open-source voice dictation for macOS &amp; Windows — 100% on-device.**
No subscription, no cloud, no accounts.

Press a hotkey anywhere, talk, and clean, tone-styled text lands at your cursor — in any app.

[Download for macOS](#macos) · [Download for Windows](#windows) · [Why JVoice](#why-jvoice) · [Build from source](#build-from-source)

</div>

---

## Why JVoice

Dictation tools like Wispr Flow and superwhisper charge $8–15/month for something your computer can already do by itself. JVoice runs OpenAI's Whisper **locally** — on macOS via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Silicon), on Windows via [Whisper.net](https://github.com/sandrohanea/whisper.net) (CPU, or NVIDIA GPU acceleration). Your voice never leaves your machine, and it costs nothing, forever.

- 🎙️ **System-wide dictation** — one global hotkey, works in any app: chat, mail, docs, your IDE
- 🧠 **On-device Whisper** — pick a model to match your machine; nothing is ever sent anywhere
- ✍️ **Tone styles** — Casual, Formal, or Very Casual: JVoice rewrites your rambling into the register you want
- 🧹 **Filler-word removal** — "um", "uh", "like" are gone before the text lands
- 📖 **Custom dictionary** — teach it your name, your project names. Words don't just get find-replaced afterwards: they bias Whisper itself at recognition time, and a phonetic matcher catches the mishearings that slip through ("jay voice" → "JVoice")
- 📊 **Stats** — words dictated, time saved, and average WPM (you talk ~3× faster than you type)
- 🌍 **English &amp; Romanian** — Whisper supports ~100 languages, so more are easy to add

## Download

> JVoice is **free and unsigned** — no $99/yr Apple developer account, no paid Windows certificate. Each OS shows a one-time "unverified developer" prompt the first time you open it. The steps below clear it in a few seconds.

### macOS

**[⬇️ Download `JVoice.dmg`](https://github.com/david53001/jvoice/releases/download/v1.0.0/JVoice-1.0.0.dmg)** — macOS 14+ (Apple Silicon recommended)

1. Open the DMG and drag **JVoice** into **Applications**.
2. First launch: macOS says it *"can't verify the developer."* Click **Done** (not "Move to Trash").
3. Open **System Settings → Privacy &amp; Security**, scroll to the bottom, and click **Open Anyway** next to JVoice. Enter your password, open JVoice again, and click **Open**. You'll never see the warning again.

> If you instead see *"JVoice is damaged"*, run this once in Terminal:
> `xattr -dr com.apple.quarantine /Applications/JVoice.app`

On first run JVoice asks for **Microphone** (to hear you) and **Accessibility** (to type text into the frontmost app) permissions, then downloads your chosen Whisper model.

**Default hotkey:** <kbd>⌥ Option</kbd>+<kbd>Space</kbd> — rebind it to whatever you like in Settings.

### Windows

| Download | Get this if… | Size |
| --- | --- | :---: |
| **[⬇️ `JVoice-Setup.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.0.0/JVoice-Setup.exe)** ← **most people** | Any Windows 10/11 (x64) PC. CPU-only. | ~65 MB |
| [`JVoice-Setup-GPU.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.0.0/JVoice-Setup-GPU.exe) | You have an **NVIDIA GPU** and want faster transcription (CUDA/Vulkan). | ~360 MB |

Both produce identical transcripts — the GPU build is just *faster* on supported hardware, and it falls back to CPU anyway. **When in doubt, get `JVoice-Setup.exe`.**

1. Run the installer. It's **unsigned**, so Windows SmartScreen shows *"Windows protected your PC."* Click **More info → Run anyway**. (One-time, per download.)
2. It installs to `%LOCALAPPDATA%\Programs\JVoice`, adds a Start-Menu shortcut, and launches to the system tray. No admin required.
3. Your first dictation downloads the Whisper model once (a few hundred MB), then everything is offline.

**Default hotkey:** <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Space</kbd> — rebind it to whatever you like in Settings.

## Usage

1. Press your hotkey — by default <kbd>⌥Space</kbd> on macOS or <kbd>Ctrl+Shift+Space</kbd> on Windows, and rebindable in Settings — a recording indicator appears.
2. Talk. Press the hotkey again to stop.
3. Transcribed, tone-styled text is pasted at your cursor.

Open **Settings** (menu-bar / tray icon → Settings…) for language, tone style, Whisper model, filler-word removal, custom words, and your dictation stats. Your recent transcripts are kept there too — copy any one back to the clipboard, or clear them. Everything stays on your machine.

## Privacy

- **Zero network calls during use.** The only network access is a one-time Whisper-model download on first run (from Hugging Face) — plus, on Windows, an optional update check you can turn off.
- No telemetry, no analytics, no accounts.
- Open source — read the code, or build it yourself.
- Full details in the [Privacy Policy](PRIVACY.md).

## Build from source

Don't trust an unsigned binary? Good instinct — build it yourself.

**macOS** — macOS 14+, Apple Silicon recommended, Xcode Command Line Tools only (no full Xcode needed):

```bash
git clone https://github.com/david53001/jvoice && cd jvoice
swift build -c release
./scripts/install.sh   # builds, signs locally, installs to /Applications
```

**Windows** — Windows 10/11 x64, [.NET 9 SDK](https://dotnet.microsoft.com/download):

```powershell
git clone https://github.com/david53001/jvoice; cd jvoice
dotnet build windows/JVoice.sln -c Release
dotnet run --project windows/JVoice.App
```

## Support the project

JVoice is free forever. If it saves you a subscription, a ⭐ on this repo is the best way to help others find it.

## License &amp; legal

GPL-3.0 — free to use, build, and modify; derivatives must stay open. Full text in [`LICENSE`](LICENSE).

- **[Terms of Use](TERMS.md)** — JVoice is provided *as-is, with no warranty*; you use it at your own risk.
- **[Privacy Policy](PRIVACY.md)** — everything stays on your device; nothing is collected.
- **[Third-Party Notices](THIRD-PARTY-NOTICES.md)** — attributions for the open-source libraries and Whisper models JVoice builds on.

JVoice is an independent project — not affiliated with, or endorsed by, OpenAI, Apple, or Microsoft.
