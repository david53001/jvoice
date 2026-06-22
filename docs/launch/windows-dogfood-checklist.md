# JVoice for Windows — dogfood checklist

Manual verification that an autonomous/headless session **cannot** perform (it needs an
interactive desktop, a microphone, keypresses, and human eyes). Run through this on the dev
machine after `dotnet build windows/JVoice.sln -c Release` succeeds. Tick each item.

> Automated coverage already green: `dotnet test windows/JVoice.Tests` = 122/122 (the brain +
> pure platform/coordinator helpers); `JVoice.exe --bench <wav>` proves on-device transcription
> end-to-end (Phase 2). This list covers only the GUI + live-input paths.
>
> **Startup is already verified working** — the app launches to the tray and stays alive. Two
> startup crashes were found and fixed when first launching it (`TaskbarIcon.ForceCreate`
> efficiency-mode `COMException`, and a PNG→`System.Drawing.Icon` conversion); see
> `../HANDOFF-WINDOWS.md` §7. So if the app fails to *launch* now, that's a new regression — but the
> items below (live input, visuals, devices, permissions) are the real point of this pass.

## Launch & tray
- [ ] `dotnet run --project windows/JVoice.App` (or run the published `JVoice.exe`).
- [ ] A tray icon (white "J") appears in the system tray.
- [ ] **First run only:** the Settings window opens centered + an info dialog says
      "JVoice is running in your system tray — press Ctrl + Shift + Space to dictate."
      (To re-test: delete `HKCU\Software\JVoice\UiFirstRunShown`.)
- [ ] Subsequent runs start silently to the tray (no window).
- [ ] Right-click tray → menu shows **Start Dictation**, **Settings…**, **Launch at Login** (✓ state), **Quit JVoice**. The dictation item flips to **Stop Dictation** while recording.

## Global hotkey + dictation (the core loop)
- [ ] Focus a text field in another app (Notepad, browser, etc.).
- [ ] Press **Ctrl+Shift+Space** → the HUD pill shows **Recording** (blue, mic glyph, spinning ring, pulsing aura, red stop button). The pill is bottom-center, ~24px above the taskbar.
- [ ] Speak a sentence. Press **Ctrl+Shift+Space** again (or click the stop button).
- [ ] HUD shows **Transcribing** (cyan) briefly, then **Done** (green check), then auto-dismisses (~1s).
- [ ] The transcribed, tone-styled text is **pasted into the previously-focused app**, and your clipboard is restored to its prior contents after ~300ms.
- [ ] Mash the hotkey rapidly → it fires at most once per 150ms (debounce).
- [ ] **Hotkey stays alive across many dictations / heavy GPU use** (the global hook is hardened: high-priority hook thread + a self-healing watchdog that re-installs the hook if Windows ever silently drops it — see HANDOFF-WINDOWS §7 #14). If it *ever* seems unresponsive, relaunch from a terminal with `set JVOICE_HOTKEY_LOG=1` (or `$env:JVOICE_HOTKEY_LOG='1'`) and reproduce — `%TEMP%\jvoice-hotkey.log` will show whether the hook received the key, matched, or re-armed. Send me that file.
- [ ] First dictation after picking a not-yet-downloaded model shows **Downloading Model** (purple, %) then **Preparing Model**, then proceeds.

## HUD visual fidelity (vs docs/demo-video/DESIGN-TOKENS.md)
- [ ] Recording = blue `#4A9EFF`; Transcribing = cyan `#00D4E0`; Preparing/Downloading = purple `#8060FF`; Done = green `#6EE7B7`; Error = orange `#FAA060`. Pill fill near-black `#07070E`.
- [ ] The pill is click-through **except** while recording (click the desktop behind it when idle/transcribing — clicks pass through; the stop button is clickable while recording).
- [ ] The pill never steals focus from your target app (it's a non-activating overlay).
- [ ] Crisp on a high-DPI monitor; positioned correctly on a secondary monitor's primary work area.

## Settings panel (320×520, dark)
- [ ] Header "JVoice" + "Voice dictation controls". 9 sections in order: Last Transcript, Keyboard Shortcut, Language, Voice Style, Processing, Whisper Model, Custom Words, Stats, footer (Restore/Quit).
- [ ] Each section card matches the dark tokens (accent dot + UPPERCASED title + divider).
- [ ] **Keyboard Shortcut:** the recorder shows "Ctrl+Shift+Space"; click it, press a new chord → it updates and the new chord triggers dictation (old one no longer does). Backspace resets to default; Esc cancels.
- [ ] **Language / Voice Style / Whisper Model:** segmented pickers select correctly and persist (close + relaunch → choice retained).
- [ ] **Processing:** the teal switch toggles Remove Filler Words; "um/uh/er" disappear from output when on.
- [ ] **Custom Words:** type a word + Enter (or Add) → it appears in the list and biases transcription; the × removes it.
- [ ] **Last Transcript:** edit the box, **Fix** → new words become custom words; **Revert** undoes the fix + removes those words.
- [ ] **Stats:** total words + avg WPM update after a dictation.
- [ ] **Restore Default Settings** → confirm dialog → settings reset (stats untouched). **Quit JVoice** → tray icon disappears, process exits.

## Audio device routing (Bluetooth A2DP preservation)
- [ ] With a normal mic (built-in/USB) default: dictation records from it (no change).
- [ ] Pair Bluetooth earbuds/headset and make them the **default mic**, play music over them in A2DP, then dictate → JVoice records from a **non-Bluetooth** mic instead, and your music **stays in stereo/A2DP** (doesn't collapse to mono HFP). The system default device is unchanged.

## Permissions & edge cases
- [ ] Turn OFF Settings → Privacy & security → Microphone → "Let desktop apps access your microphone", then dictate → HUD shows a mic-denied error and the Windows microphone Settings page opens (`ms-settings:privacy-microphone`). Turn it back on.
- [ ] A very short tap (< ~1s) → "Recording too short" error, no paste.
- [ ] Dictate into an **elevated (admin)** window → expect an "Can't paste into an elevated window" message (UIPI; JVoice runs non-elevated by design). Pasting into normal windows works.
- [ ] **Launch at Login:** toggle in the tray menu → verify `HKCU\...\Run\JVoice` appears/disappears (auto-enabled once on first run). Untick it if you don't want a dev build auto-launching.
- [ ] **Single instance:** launching a second `JVoice.exe` is a no-op (the first keeps owning the hotkey).
- [ ] **`--bench` still bypasses the UI:** `JVoice.exe --bench <wav>` transcribes and exits with no tray/window.

## Privacy spot-checks
- [ ] After several dictations, `%TEMP%\jvoice-*.wav` has no leftover files (deleted after each + swept on launch).
- [ ] No network traffic at runtime except the first-run model download from huggingface.co.

Record anything that fails (with a screenshot if visual) in `docs/HANDOFF-WINDOWS.md`.
