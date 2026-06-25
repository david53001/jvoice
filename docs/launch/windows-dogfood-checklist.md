# JVoice for Windows — dogfood checklist

Manual verification that an autonomous/headless session **cannot** perform (it needs an
interactive desktop, a microphone, keypresses, and human eyes). Run through this on the dev
machine after `dotnet build windows/JVoice.sln -c Release` succeeds. Tick each item.

> Automated coverage already green: `dotnet test windows/JVoice.Tests` = 490/490 (the brain +
> pure platform/coordinator helpers); `JVoice.exe --bench <wav>` and `tools/nospeech-probe` prove
> on-device transcription + no-speech behaviour end-to-end. This list covers only the GUI + live-input paths.
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
- [ ] Right-click tray → menu shows **Start Dictation**, **Settings…**, **Launch at Login** (✓ state), **Restart as Administrator** (or a disabled **Running as Administrator ✓** when already elevated), **Run as Administrator at Login** (✓ state), **Quit JVoice**. The dictation item flips to **Stop Dictation** while recording.

## Global hotkey + dictation (the core loop)
- [ ] Focus a text field in another app (Notepad, browser, etc.).
- [ ] Press **Ctrl+Shift+Space** → the HUD pill appears bottom-center (~24px above the taskbar): a **pure-black pill with a row of white voice-activity bars** — a **continuous wave** that animates on its own (the bars are **not** mic-reactive; that was removed in §7 #23 because mic-reactivity stuttered on your words). **No text, no spinning ring, no stop button** (the 2026-06-23 black-&-white redesign — see HANDOFF-WINDOWS §7 #18, #23).
- [ ] Speak — the bars keep flowing as a steady, lively wave; they do **not** track your volume (deliberate — mic-reactive bars stuttered on your words, §7 #23). Press **Ctrl+Shift+Space** again to stop (there is no on-pill stop button anymore — use the hotkey or the tray menu).
- [ ] The bars switch to a gentle left-right **shimmer while transcribing**, then the HUD **just disappears** — there is **no "Pasted"/Done confirmation** (silent success, by design).
- [ ] The transcribed, tone-styled text is **pasted into the previously-focused app**, and your clipboard is restored to its prior contents after ~300ms.
- [ ] **No stray space leaks from the hotkey** (§7 #25): pressing Ctrl+Shift+Space inserts **no** space character into the focused field — the hook now **swallows** the chord's main key (it used to fall through, typing a space on every trigger). Plain Space typing is unaffected.
- [ ] **Click directly into a terminal (Windows Terminal / PowerShell / cmd), then dictate → text lands in that terminal.** Crucially, also test the terminal JVoice was *launched from* — the paste target is now resolved by process ownership of the live foreground (HANDOFF-WINDOWS §7), not a stale launch-time window handle, so dictating into the launching terminal no longer mis-fires.
- [ ] **Quiet / short utterances register** (no-speech gate RETIRED — the MODEL decides now, HANDOFF §7 #21): say a short, fairly quiet word or sentence → it transcribes. This is the fix for the bug where your real short/quiet sentences kept showing "No speech detected." (the old RMS/spectral gates were tuned on synthetic clips and couldn't tell your quiet speech from your room hum; whisper itself can, so the gate is gone). Pressing the hotkey and saying *nothing* still shows "No speech detected." — and a noisy room/fan no longer pastes a stray `(birds chirping)`/`you`. If a genuinely-spoken phrase is *still* rejected, relaunch from a terminal and send `%APPDATA%\JVoice\diagnostic.log` (it now logs `no-speech (model empty/annotation) hpRms=… rawRms=… ratio=…`).
- [ ] **Sentence endings are not cut off** (streaming tail fix, HANDOFF §7 #21): dictate a longer multi-sentence passage that *trails off quietly at the end* (let your voice drop on the last few words, as people naturally do) → the **last words still appear**. Previously the quiet trailing clause was dropped as "silence" and only the earlier (louder) part pasted. Try a few; if any ending is still clipped, send the `diagnostic.log`.
- [ ] Mash the hotkey rapidly → it fires at most once per 150ms (debounce). Holding the chord down (auto-repeat) likewise fires once and leaks no spaces (every match is swallowed, §7 #25).
- [ ] **Hotkey stays alive across many dictations / heavy GPU use** (the global hook is hardened: high-priority hook thread + a self-healing watchdog that re-installs the hook if Windows ever silently drops it — see HANDOFF-WINDOWS §7 #14). If it *ever* seems unresponsive, relaunch from a terminal with `set JVOICE_HOTKEY_LOG=1` (or `$env:JVOICE_HOTKEY_LOG='1'`) and reproduce — `%TEMP%\jvoice-hotkey.log` will show whether the hook received the key, matched, or re-armed. Send me that file.
- [ ] First dictation after picking a not-yet-downloaded model shows the same **bar shimmer** while it downloads/prepares the model (no text/percentage — the redesign is text-free except errors), then proceeds.

## Game-detection hotkey suppression (HANDOFF-WINDOWS §7 #27)
> The hotkey goes **silent and fully transparent** while a video game is in focus, so an accidental
> Ctrl+Shift+Space in a game doesn't pop the HUD or paste into game chat. **Anti-cheat safe:** detection is
> read-only OS queries — JVoice never reads the game's memory, never injects, never enumerates its modules
> (the only process access is `PROCESS_QUERY_LIMITED_INFORMATION` for the exe path). Default mode is **Balanced**.
> Diagnostic tool: run `JVoice.exe --game-probe` (writes live signal snapshots to `%TEMP%\jvoice-gameprobe.log`
> for 60s), then alt-tab into a game and read that file — each snapshot shows the QUNS state, exe path, the four
> signals, and the final `ShouldSuppress` decision.
- [ ] **In each real game** (try **Valorant, Fortnite, GTA V, Minecraft, and a Steam game**): with the game in focus, press **Ctrl+Shift+Space** → **no HUD, no recording**, and the chord **passes through to the game** (JVoice does nothing). Use `--game-probe` to confirm `ShouldSuppress: True` for that game first.
- [ ] **Minecraft (windowed `javaw.exe`)** specifically: it's caught via Windows' GameConfigStore, not the exe name. If `--game-probe` shows `RegisteredGame: True`, suppression works; if not (Windows never registered it), it only suppresses fullscreen (Balanced) or needs Aggressive — note which.
- [ ] **Alt-tab out of the game** to a normal app (Notepad/browser) → the hotkey **works again** (dictation normal). A backgrounded game must NOT keep suppressing.
- [ ] **Fullscreen video is NOT a false positive (Balanced):** play a **fullscreen** YouTube/Netflix video → the hotkey **still works** (Balanced deliberately ignores bare fullscreen). 
- [ ] **Settings → Gaming** segmented picker (Off / Balanced / Aggressive): selects, persists across relaunch. Switch to **Aggressive** → now fullscreen video **does** suppress (any fullscreen app). Switch to **Off** → suppression is fully disabled (hotkey fires even inside a game). Return to **Balanced**.
- [ ] **No false ban / no anti-cheat warning:** after sessions in kernel-anti-cheat games (Vanguard/EAC/BattlEye) with JVoice running, there is **no anti-cheat flag or ban** — expected, since detection never touches the game process. (If anything ever looks off, the only game-related access is the read-only `--game-probe`/detector path lookup; send `%TEMP%\jvoice-gameprobe.log`.)

## HUD visual fidelity (black & white redesign — 2026-06-23)
> The HUD no longer follows `docs/demo-video/DESIGN-TOKENS.md` (that's the macOS color design).
> The Windows HUD is intentionally a minimal **black & white** pill. Screenshot any state without a
> mic via `JVoice.exe --hud-preview recording|transcribing|preparing|downloading|error`.
- [ ] **Recording / transcribing / preparing / downloading:** a pure-black rounded pill (152×38) with 21 white round-capped bars, no text. Bars are crisp (solid shapes, not the old glowy text) — **not blurry**, even at the non-native 1600×1080 desktop (the bars sidestep the layered-window text softness, and `DisplayMetrics.HudScale` enlarges the pill by the resolution stretch ratio).
- [ ] **Bars are a lively continuous wave while recording** — tall and constantly moving (a wave that travels across the row), **independent of your voice** (mic-reactivity was removed in §7 #23 because it stuttered on your words). The bars never change what whisper hears. The mic-reactive wiring is kept but unused (`InputLevelProvider` in `HudView.xaml.cs`); the wave constants are at the top of that file if you want to retune the motion.
- [ ] **Error only:** a white ⚠ glyph + white message (e.g. "No speech detected.", "Something went wrong") on the same black pill — the one state that shows text. Auto-dismisses after ~3s.
- [ ] **Success is silent:** a normal paste shows **no** confirmation pill — the HUD just vanishes.
- [ ] The pill is **always click-through** (click the desktop behind it any time — clicks pass through; there's no interactive affordance on it now) and never steals focus from your target app (non-activating overlay).
- [ ] Positioned correctly on a secondary monitor's primary work area.

## Settings panel (320×520, black & white)
- [ ] Header "JVoice" + "Voice dictation controls". Sections in order: **Stats, Recent Transcripts, Whisper Model, Processing, Voice Style, Language, Custom Words, Corrections, Keyboard Shortcut**, footer (Restore/Quit). (Reordered 2026-06-25 to mirror the macOS Settings; the old editable **Last Transcript** box was removed — see HANDOFF-WINDOWS §7 #26. Screenshot headlessly via `JVoice.exe --settings-render out.png`, or show it with `--settings-preview`.)
- [ ] **All monochrome:** pure-black background, dark cards with gray hairline borders, **white** section accent dots (the keyboard section's dot is a subtle gray), gray UPPERCASED titles. No blue/cyan/purple/teal/orange/pink/green anywhere.
- [ ] **Keyboard Shortcut:** the recorder shows "Ctrl+Shift+Space"; click it, press a new chord → it updates and the new chord triggers dictation (old one no longer does). Backspace resets to default; Esc cancels.
- [ ] **Language / Voice Style / Whisper Model:** segmented pickers select correctly (selected segment = white-tint fill, white text) and persist (close + relaunch → choice retained).
- [ ] **Processing:** the switch (white-when-on, black knob) toggles Remove Filler Words; "um/uh/er" disappear from output when on.
- [ ] **Custom Words:** type a word + Enter (or Add) → it appears in the list and biases transcription; the × removes it.
- [ ] **Corrections:** add a rule From `web api` → To `web app` (Enter in either box or Add) → it appears as "web api → web app" (the "To" text in white); the × removes it; choice persists across relaunch. Then dictate so the recognizer produces "web api" → the pasted text reads "web app", while a separate "REST API" dictation stays "REST API" (the phrase rule doesn't touch standalone API). Blank/duplicate input is ignored (no row added).
- [ ] **Recent Transcripts** (read-only history, last 30, newest first — replaces the old editable Last Transcript box, §7 #26): after dictating, the new transcript appears at the **top**; empty state shows muted "No transcripts yet." Each row is **single-line, ellipsis-truncated** (no wrap). **Hover a row** → it highlights and reveals **Copy** + **Delete** icons on the right. **Copy** puts that transcript on the clipboard and flips to a **checkmark for ~1.2s**. **Delete** removes just that row. **Clear all** empties the whole list. The list **survives relaunch** (persisted to `%APPDATA%\JVoice\transcript-history.json`); deleting/corrupting that file → loads empty, no crash. Do ~31 dictations → the list caps at **30** (oldest drops off).
- [ ] **Stats:** total words + avg WPM update after a dictation.
- [ ] **Restore Default Settings** → confirm dialog (now also says **recent transcripts will be cleared**; statistics are not affected) → settings reset, **Recent Transcripts emptied**, stats untouched. **Quit JVoice** → tray icon disappears, process exits.

## Audio device routing (Bluetooth A2DP preservation)
- [ ] With a normal mic (built-in/USB) default: dictation records from it (no change).
- [ ] Pair Bluetooth earbuds/headset and make them the **default mic**, play music over them in A2DP, then dictate → JVoice records from a **non-Bluetooth** mic instead, and your music **stays in stereo/A2DP** (doesn't collapse to mono HFP). The system default device is unchanged.

## Permissions & edge cases
- [ ] Turn OFF Settings → Privacy & security → Microphone → "Let desktop apps access your microphone", then dictate → HUD shows a mic-denied error and the Windows microphone Settings page opens (`ms-settings:privacy-microphone`). Turn it back on.
- [ ] A very short tap (< ~1s) → "Recording too short" error, no paste.
- [ ] **Elevated-window dictation (the UIPI fix — HANDOFF-WINDOWS §7 #24).** While JVoice runs **non-elevated** (the default), the hotkey does **nothing** when an **elevated (admin) terminal/app has focus** — a non-elevated global keyboard hook never sees keys destined for a higher-integrity window (UIPI), and it can't paste there either. To fix, run JVoice elevated:
  - [ ] Tray → **Restart as Administrator** → accept the UAC prompt → JVoice relaunches (tray reappears; the menu now shows a disabled **Running as Administrator ✓**). Focus an **admin** terminal and press **Ctrl+Shift+Space** → the HUD appears and dictation pastes into the admin terminal. (If UAC is declined, the app keeps running non-elevated, unchanged.)
  - [ ] Tray → **Run as Administrator at Login** → UAC → it registers a Task Scheduler logon task (`schtasks /query /tn "JVoice Elevated Autostart"` shows it). **Log out and back in (or reboot)** → JVoice **auto-starts elevated with NO UAC prompt**, and the hotkey works in admin windows from the start. Untick it to remove the task (`schtasks` no longer lists it).
  - [ ] With **both** "Launch at Login" and "Run as Administrator at Login" on, logging in starts **one** elevated instance (the non-elevated Run-key copy steps aside) — not two.
  - [ ] Non-elevated still works as before: with JVoice non-elevated, pasting into **normal** windows works; only elevated targets need the above.
- [ ] **Launch at Login:** toggle in the tray menu → verify `HKCU\...\Run\JVoice` appears/disappears (auto-enabled once on first run). The value now ends in ` --autostart` (the marker that lets a logon copy step aside for the elevated task — §7 #24); a plain manual launch has no such flag and never steps aside. Untick it if you don't want a dev build auto-launching.
- [ ] **Single instance:** launching a second `JVoice.exe` is a no-op (the first keeps owning the hotkey).
- [ ] **`--bench` still bypasses the UI:** `JVoice.exe --bench <wav>` transcribes and exits with no tray/window.

## Privacy spot-checks
- [ ] After several dictations, `%TEMP%\jvoice-*.wav` has no leftover files (deleted after each + swept on launch).
- [ ] No network traffic at runtime except the first-run model download from huggingface.co.

Record anything that fails (with a screenshot if visual) in `docs/HANDOFF-WINDOWS.md`.
