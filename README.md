<img src="docs/assets/icon.png" alt="JVoice" width="96" height="96">

# JVoice

Free voice dictation for macOS and Windows. Press a hotkey, talk, and the text is typed where your cursor is. Speech recognition runs on your computer (OpenAI's Whisper model), so nothing is sent anywhere.

## Install and update

### macOS

Needs macOS 14 or newer (Apple Silicon recommended). Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/jvoice/main/scripts/install.sh | bash
```

The same command installs JVoice and updates it to the newest version. Updating keeps your settings, custom words, stats, downloaded model and permissions. You can read the script first: [`scripts/install.sh`](scripts/install.sh).

Prefer a manual download? Get [`JVoice-1.1.4.dmg`](https://github.com/david53001/jvoice/releases/download/v1.1.4/JVoice-1.1.4.dmg) and drag JVoice into Applications.

### Windows

Needs Windows 10 or 11 (64-bit). Paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/david53001/jvoice/main/scripts/install.ps1 | iex
```

The same command installs JVoice and updates it to the newest version. It picks the faster GPU build if your PC has an NVIDIA graphics card, needs no admin rights, and starts JVoice in the system tray. Updating keeps your settings, custom words, stats and downloaded model. You can read the script first: [`scripts/install.ps1`](scripts/install.ps1). JVoice can also update itself from Settings > Updates.

Prefer a manual download? Get [`JVoice-Setup.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.1.0/JVoice-Setup.exe) (70 MB), or [`JVoice-Setup-GPU.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.1.0/JVoice-Setup-GPU.exe) (380 MB) for NVIDIA graphics cards, and run it.

## Uninstall

On macOS, paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/jvoice/main/scripts/uninstall.sh | bash
```

On Windows, paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/david53001/jvoice/main/scripts/uninstall.ps1 | iex
```

Each quits JVoice and removes the app, its settings (including custom words, stats and recent transcripts), the downloaded Whisper model and its caches; on macOS also its Microphone and Accessibility permissions, on Windows also its shortcuts and launch at login. You can read the scripts first: [`scripts/uninstall.sh`](scripts/uninstall.sh), [`scripts/uninstall.ps1`](scripts/uninstall.ps1).

## First launch

JVoice is free and not signed with a paid developer certificate. The install commands above handle this for you. If you downloaded it by hand, your system warns you once:

- **macOS**: click Done, then go to System Settings > Privacy & Security and click Open Anyway. If macOS says the app is damaged, run `xattr -dr com.apple.quarantine /Applications/JVoice.app`.
- **Windows**: on "Windows protected your PC", click More info > Run anyway.

On macOS, JVoice asks for Microphone access (to hear you) and Accessibility access (to type the text into other apps). On both systems, the speech model downloads once on first use.

## Hotkeys

- macOS: Option+Space to start and stop recording.
- Windows: Ctrl+Shift+Space.

You can change them in Settings.

## Features

- Works in any app: chat, email, documents, code editors.
- Choose the Whisper model size to match your computer.
- Tone styles (Casual, Formal, Very Casual) and filler-word removal ("um", "uh").
- Custom words, so names and project terms come out right.
- Stats: words dictated, time saved, speaking speed.
- English and Romanian.

## Privacy

Your voice never leaves your computer. The only network use is the one-time model download (and, on Windows, the update check, which you can turn off). No accounts, no tracking. Details: [PRIVACY.md](PRIVACY.md).

## Build from source

macOS (Command Line Tools are enough, no Xcode needed):

```sh
git clone https://github.com/david53001/jvoice && cd jvoice
./scripts/dev-install.sh   # builds and installs to /Applications
```

Windows ([.NET 9 SDK](https://dotnet.microsoft.com/download)):

```powershell
git clone https://github.com/david53001/jvoice; cd jvoice
dotnet run --project windows/JVoice.App -c Release
```

## License

[PolyForm Strict 1.0.0](LICENSE): you may view the code and use JVoice for free for noncommercial purposes, but not redistribute, modify or sell it. See also the [Terms of Use](TERMS.md) and [Third-Party Notices](THIRD-PARTY-NOTICES.md).
