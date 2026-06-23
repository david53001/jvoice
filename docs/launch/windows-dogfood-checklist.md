# JVoice for Windows — dogfood checklist

Manual verification that an autonomous/headless session **cannot** perform (it needs an
interactive desktop, a microphone, keypresses, and human eyes). Run through this on the dev
machine after `dotnet build windows/JVoice.sln -c Release` succeeds. Tick each item.

> Automated coverage already green: `dotnet test windows/JVoice.Tests` = 402/402 (the brain +
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
- [ ] Press **Ctrl+Shift+Space** → the HUD pill appears bottom-center (~24px above the taskbar): a **pure-black pill with a row of white voice-activity bars** that rise and fall with your voice. **No text, no spinning ring, no stop button** (the 2026-06-23 black-&-white redesign — see HANDOFF-WINDOWS §7 #18).
- [ ] Speak — the bars react to your volume (taller/livelier when you talk, settling when quiet). Press **Ctrl+Shift+Space** again to stop (there is no on-pill stop button anymore — use the hotkey or the tray menu).
- [ ] The bars switch to a gentle left-right **shimmer while transcribing**, then the HUD **just disappears** — there is **no "Pasted"/Done confirmation** (silent success, by design).
- [ ] The transcribed, tone-styled text is **pasted into the previously-focused app**, and your clipboard is restored to its prior contents after ~300ms.
- [ ] **Click directly into a terminal (Windows Terminal / PowerShell / cmd), then dictate → text lands in that terminal.** Crucially, also test the terminal JVoice was *launched from* — the paste target is now resolved by process ownership of the live foreground (HANDOFF-WINDOWS §7), not a stale launch-time window handle, so dictating into the launching terminal no longer mis-fires.
- [ ] **Quiet / short utterances register** (no-speech gate RETIRED — the MODEL decides now, HANDOFF §7 #21): say a short, fairly quiet word or sentence → it transcribes. This is the fix for the bug where your real short/quiet sentences kept showing "No speech detected." (the old RMS/spectral gates were tuned on synthetic clips and couldn't tell your quiet speech from your room hum; whisper itself can, so the gate is gone). Pressing the hotkey and saying *nothing* still shows "No speech detected." — and a noisy room/fan no longer pastes a stray `(birds chirping)`/`you`. If a genuinely-spoken phrase is *still* rejected, relaunch from a terminal and send `%APPDATA%\JVoice\diagnostic.log` (it now logs `no-speech (model empty/annotation) hpRms=… rawRms=… ratio=…`).
- [ ] **Sentence endings are not cut off** (streaming tail fix, HANDOFF §7 #21): dictate a longer multi-sentence passage that *trails off quietly at the end* (let your voice drop on the last few words, as people naturally do) → the **last words still appear**. Previously the quiet trailing clause was dropped as "silence" and only the earlier (louder) part pasted. Try a few; if any ending is still clipped, send the `diagnostic.log`.
- [ ] Mash the hotkey rapidly → it fires at most once per 150ms (debounce).
- [ ] **Hotkey stays alive across many dictations / heavy GPU use** (the global hook is hardened: high-priority hook thread + a self-healing watchdog that re-installs the hook if Windows ever silently drops it — see HANDOFF-WINDOWS §7 #14). If it *ever* seems unresponsive, relaunch from a terminal with `set JVOICE_HOTKEY_LOG=1` (or `$env:JVOICE_HOTKEY_LOG='1'`) and reproduce — `%TEMP%\jvoice-hotkey.log` will show whether the hook received the key, matched, or re-armed. Send me that file.
- [ ] First dictation after picking a not-yet-downloaded model shows the same **bar shimmer** while it downloads/prepares the model (no text/percentage — the redesign is text-free except errors), then proceeds.

## HUD visual fidelity (black & white redesign — 2026-06-23)
> The HUD no longer follows `docs/demo-video/DESIGN-TOKENS.md` (that's the macOS color design).
> The Windows HUD is intentionally a minimal **black & white** pill. Screenshot any state without a
> mic via `JVoice.exe --hud-preview recording|transcribing|preparing|downloading|error`.
- [ ] **Recording / transcribing / preparing / downloading:** a pure-black rounded pill with white bars, no text. Bars are crisp (solid shapes, not the old glowy text) — **not blurry**, even at the non-native 1600×1080 desktop (the bars sidestep the layered-window text softness, and `DisplayMetrics.HudScale` enlarges the pill by the resolution stretch ratio).
- [ ] **Error only:** a white ⚠ glyph + white message (e.g. "No speech detected.", "Something went wrong") on the same black pill — the one state that shows text. Auto-dismisses after ~3s.
- [ ] **Success is silent:** a normal paste shows **no** confirmation pill — the HUD just vanishes.
- [ ] The pill is **always click-through** (click the desktop behind it any time — clicks pass through; there's no interactive affordance on it now) and never steals focus from your target app (non-activating overlay).
- [ ] Positioned correctly on a secondary monitor's primary work area.

## Settings panel (320×520, black & white)
- [ ] Header "JVoice" + "Voice dictation controls". 10 sections in order: Last Transcript, Keyboard Shortcut, Language, Voice Style, Processing, Whisper Model, Custom Words, Corrections, Stats, footer (Restore/Quit). (Screenshot headlessly via `JVoice.exe --settings-render out.png`, or show it with `--settings-preview`.)
- [ ] **All monochrome:** pure-black background, dark cards with gray hairline borders, **white** section accent dots (the keyboard section's dot is a subtle gray), gray UPPERCASED titles. No blue/cyan/purple/teal/orange/pink/green anywhere.
- [ ] **Keyboard Shortcut:** the recorder shows "Ctrl+Shift+Space"; click it, press a new chord → it updates and the new chord triggers dictation (old one no longer does). Backspace resets to default; Esc cancels.
- [ ] **Language / Voice Style / Whisper Model:** segmented pickers select correctly (selected segment = white-tint fill, white text) and persist (close + relaunch → choice retained).
- [ ] **Processing:** the switch (white-when-on, black knob) toggles Remove Filler Words; "um/uh/er" disappear from output when on.
- [ ] **Custom Words:** type a word + Enter (or Add) → it appears in the list and biases transcription; the × removes it.
- [ ] **Corrections:** add a rule From `web api` → To `web app` (Enter in either box or Add) → it appears as "web api → web app" (the "To" text in white); the × removes it; choice persists across relaunch. Then dictate so the recognizer produces "web api" → the pasted text reads "web app", while a separate "REST API" dictation stays "REST API" (the phrase rule doesn't touch standalone API). Blank/duplicate input is ignored (no row added).
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
