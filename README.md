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

Needs Windows 10 or 11 (64-bit). Download and run the installer:

- [`JVoice-Setup.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.0.0/JVoice-Setup.exe) (about 70 MB) for most PCs.
- [`JVoice-Setup-GPU.exe`](https://github.com/david53001/jvoice/releases/download/windows-v1.0.0/JVoice-Setup-GPU.exe) (about 380 MB) only if you have an NVIDIA graphics card and want faster transcription. The text is the same either way.

It installs for your user only (no admin needed) and starts in the system tray. To update, open Settings, go to Updates and click Check Now, then Update Now (JVoice also checks once a day unless you turn that off). Running a newer installer over the old one works too. Your settings are kept.

## Uninstall

On macOS, paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/jvoice/main/scripts/uninstall.sh | bash
```

It quits JVoice and removes the app, its settings (including custom words, stats and recent transcripts), the downloaded Whisper model, its caches, and its Microphone and Accessibility permissions. You can read the script first: [`scripts/uninstall.sh`](scripts/uninstall.sh).

## First launch

JVoice is free and not signed with a paid developer certificate, so your system warns you once:

- **macOS** (only if you used the DMG): click Done, then go to System Settings > Privacy & Security and click Open Anyway. If macOS says the app is damaged, run `xattr -dr com.apple.quarantine /Applications/JVoice.app`.
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
