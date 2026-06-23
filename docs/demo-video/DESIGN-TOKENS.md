# JVoice Design Tokens

Extracted verbatim from the JVoice **macOS** Swift sources. Every visual in the demo video
traces to a value here. Source files are cited per section. SwiftUI `Color(red:green:blue:)`
uses 0–1 sRGB components; CSS equivalents are `round(component * 255)`.

> **macOS only.** This is the colored macOS UI (orbital ring, accents, text states). The **Windows**
> port has a *separate, intentionally different* HUD — a text-free black pill of white voice-activity
> bars, fully monochrome Settings/tray — which does NOT follow these tokens. For the Windows look see
> `docs/HANDOFF-WINDOWS.md` §7 #18 (redesign), #22 (the no-transcription-gain guard) and #23 (the
> continuous-wave recording bars + final pill geometry).

---

## 1. HUD Pill (Source: `Sources/JVoice/UI/HUDView.swift`, `HUDLayout.swift`, `HUDWindow.swift`)

### Layout
- Pill min size: **220 × 50 pt** (`HUDLayout.hudPillSize`).
- Corner radius: **22** (`.continuous` / squircle — approximate in CSS with a large radius; visually near-pill).
- Inner content padding: horizontal **10**, vertical **7**.
- HStack spacing between orbital ring and text block: **10**.
- Pill sits at **bottom center** of screen, 24 pt above the bottom of the visible frame (`positionAtBottomCenter`). Outer `.padding(32)` around the pill body (so a glow margin exists).

### Shared pill background (`pillBackground(borderColor:)`)
- Fill: `Color(red: 0.027, green: 0.027, blue: 0.055)` → **rgb(7, 7, 14)** (near-black navy).
- Border: `borderColor.opacity(0.22)`, lineWidth 1.
- Top-leading gradient overlay: `borderColor.opacity(0.06)` → clear (topLeading → center).
- Glow shadows: `borderColor.opacity(0.18)` radius 16, plus `borderColor.opacity(0.07)` radius 32.
- Drop shadow (per pill): `black.opacity(0.35)`, radius 12, y +6.

### Orbital Ring (the animated icon disc, 36×36)
- Pulsing aura: RadialGradient `ringColor.opacity(0.18)` → clear, endRadius 18, on a 36×36 circle; pulse scale 0.9→1.05 easeInOut 1.8s repeatForever autoreverse.
- Spinning arc: a 28×28 circle, `trim(from: 0, to: 0.28)`, stroke lineWidth 1.5, round cap, rotates full 360° every **4.0s**; glow `ringColor.opacity(0.85)` r3 + `0.4` r6.
- Center icon: SF Symbol, size 11, semibold, color = ringColor, glow `0.6` r4 + `0.25` r10.

### Recording Pill (`RecordingPill`) — HUDState `.recording`
- accent = `Color(red: 0.290, green: 0.620, blue: 1.000)` → **rgb(74, 158, 255)** (blue).
- textColor = `Color(red: 0.820, green: 0.910, blue: 1.000)` → **rgb(209, 232, 255)**.
- subColor = accent.opacity(0.55).
- Ring icon: **`mic.fill`**.
- Title text: **"Recording"** (size 12, semibold), glow accent .55 r6 + .20 r18.
- Subtitle: **"Listening…"** (size 10, medium), color subColor.
- Stop button on right (only in `.recording`): 22×22, RoundedRect r6 fill stopRed.opacity(0.12),
  border stopRed.opacity(0.30); inner 7×7 RoundedRect r2 fill stopRed. stopRed = `rgb(255, 96, 96)`.

### Transcribing Pill (`TranscribingPill`) — HUDState `.transcribing`
- accent = `Color(red: 0.000, green: 0.831, blue: 0.878)` → **rgb(0, 212, 224)** (cyan).
- textColor = `Color(red: 0.627, green: 0.941, blue: 0.969)` → **rgb(160, 240, 247)**.
- Ring icon: **`waveform.path`**.
- Title: **"Transcribing"** (12 semibold). Subtitle: **"Processing…"** (10 medium).
- No stop button.

### Status Pill (`StatusPill`) — HUDState `.done` / `.error`
- Disc is a static 28×28 Circle (no spinning arc): fill accent.opacity(0.12), border accent.opacity(0.30), glow accent.opacity(0.22) r6.
- `.done`: accent = `Color(red: 0.431, green: 0.906, blue: 0.718)` → **rgb(110, 231, 183)** (green);
  textColor = `Color(red: 0.694, green: 0.988, blue: 0.718)` → **rgb(177, 252, 183)**;
  icon **`checkmark.circle.fill`**; headline = **"Pasted"** (from `HUDState.headline`).
- `.error`: accent = rgb(250, 160, 96) orange; icon `exclamationmark.triangle.fill`; headline "Something Went Wrong".
- Headline font size 12 semibold, single line.

### HUD State machine / labels (`HUDState.swift`)
- `.recording`  → headline "Listening", systemImage `mic.fill`, accent role red (but RecordingPill uses BLUE accent above — pill view overrides the role color).
- `.transcribing` → headline "Transcribing".
- `.done(text)` → headline **"Pasted"**, displayText "Pasted".
- Transition order in the app: idle → recording → transcribing → done → (fades to idle).

---

## 2. Settings Panel (Source: `Sources/JVoice/UI/SettingsView.swift`)

### Window / frame
- SettingsView content frame: **320 × 520** (`.frame(width: 320, height: 520)`), `.preferredColorScheme(.dark)`, scrollable.
- Native window title bar text: **"Settings"** (`SettingsWindow.title`), traffic-light buttons (close/min/zoom).
- Outer content padding: **16**. Vertical spacing between sections: **10**.

### Palette (`SettingsPalette`)
- panelBg    = rgb(13, 13, 22)   `Color(0.051, 0.051, 0.086)`
- sectionBg  = rgb(15, 15, 26)   `Color(0.059, 0.059, 0.102)`
- border     = rgb(30, 30, 44)   `Color(0.118, 0.118, 0.173)`
- headerText = rgb(74, 128, 204) `Color(0.290, 0.502, 0.800)`
- inputBg    = rgb(10, 10, 20)   `Color(0.039, 0.039, 0.078)`
- blue   = rgb(74, 158, 255)
- gray   = white 0.53 → rgb(135,135,135)
- indigo = rgb(96, 160, 255)
- purple = rgb(128, 96, 255)
- cyan   = rgb(32, 216, 255)
- orange = rgb(240, 160, 48)
- green  = rgb(74, 222, 160)
- teal   = rgb(32, 192, 160)
- red    = rgb(255, 96, 96)

### Section chrome (`DarkSection`)
- Card: RoundedRect r10, fill sectionBg, border 1px border color.
- Header row: 5×5 accent dot (with glow accentColor.opacity(0.55) r3) + title text.
- Title text: **UPPERCASED**, size 9.5, bold, kerning 0.7, color headerText.
- Header padding: h12, top 9, bottom 7. Then 0.5px divider (border color). Content padding 12.

### Header block (top of panel)
- Title **"JVoice"** size 17 bold white.
- Subtitle **"Menu bar transcription controls"** size 11, color white 0.45.

### Sections IN ORDER (exact titles + controls + labels)
1. **LAST TRANSCRIPT** (accent blue) — empty state text "No transcript yet."; otherwise a
   TextEditor (size 11) + buttons "Fix" / "Revert".
2. **KEYBOARD SHORTCUT** (accent gray) — KeyboardShortcuts.Recorder labelled "Toggle Recording:";
   helper line **"Default: ⌥ Space"** (size 10, white 0.35).
3. **LANGUAGE** (accent indigo) — segmented Picker, labelsHidden. Options: **English**, **Romanian**
   (`TranscriptionLanguage`). Default English.
4. **VOICE STYLE** (accent purple) — segmented Picker. Options: **Casual**, **Formal**, **Very Casual**
   (`ToneMode`). Default Casual.
5. **PROCESSING** (accent teal) — row: title **"Remove Filler Words"** (size 12 medium, white 0.85) +
   subtitle **"Strip um, uh, er, ah, hmm from output"** (size 10, white 0.38) + a `.switch` Toggle
   tinted teal. Default ON.
6. **WHISPER MODEL** (accent cyan) — segmented Picker, labelsHidden. Options: **Tiny**, **Base**,
   **Small**, **Large** (`WhisperModelChoice.displayName`; note largeTurbo → "Large"). Default Tiny.
7. **CUSTOM WORDS** (accent orange) — list of word rows w/ red `minus.circle.fill` remove buttons,
   empty state "No custom words added."; input field placeholder **"Add word (e.g. VS Code)"** + "Add" button.
8. **STATS** (accent green) — two columns split by 0.5px divider:
   - Left: big number (size 26 bold white, monospaced, blue glow) + label **"total words"** (size 10, white 0.38).
   - Right: big number (green glow) + label **"avg WPM"**.
9. Footer row: **"Restore Default Settings"** (destructive red button) on left, **"Quit JVoice"** (destructive red) on right.

---

## 3. Menu Bar (Source: `Sources/JVoice/UI/MenuBarController.swift`)

### Status item icon
- A bold 15pt **"J"** mark when idle (the product changed 2026-06-06; mirrors
  `MenuBarController.makeStatusIcon()`); **`mic.fill`** tinted `.systemRed` when recording.
- Appearance forced `.darkAqua`. imagePosition imageOnly. toolTip "JVoice".
- In the demo, the menu bar height is **MENUBAR_H = 25** (macOS 14 at 1×; was 28).

### NSMenu items IN ORDER (exact titles)
1. **"Start Dictation"** (becomes **"Stop Dictation"** while recording).
2. — separator —
3. **"Settings…"**  (note: trailing ellipsis character …)
4. **"Launch at Login"** (checkmark state on/off).
5. — separator —
6. **"Quit JVoice"**

---

## 4. App Icon (Source: `Resources/AppIcon.icns`)
- Black rounded-square (squircle) app icon with a centered white/off-white **"J"** glyph
  (the product changed from "M" to "J" on 2026-06-06), subtle inner shadow/gradient.
  Extracted to `public/app-icon.png`.

---

## 5. Demo-specific content (the scripted dictation)
- Raw spoken (caption builds up): **"hey um can we move practice to thursday at five"**
- Cleaned/typed result in Notes: **"Hey! Can we move practice to Thursday at 5?"**
- End caption (optional): **"100% on-device · free"**

---

## 6. Motion / fidelity rules
- All entrances use spring()/interpolate — nothing pops.
- Cursor uses the real macOS arrow pointer (extracted PNG), spring/bezier easing.
- Typing is per-character with slight raggedness (variable delay), not linear.
- Orbital ring arc: one full rotation every 4.0s; pulse aura 1.8s autoreverse.
- Caret blink ~1.06s period (standard macOS).

---

## 7. System environment assets (2026-06-06)
The Apple UI in the demo is no longer hand-drawn — every Apple-owned artifact is
extracted from the OS itself by `scripts/extract-assets.swift` into
`public/system/`, so the recreation is pixel-true:

- **Dock app icons** — `NSWorkspace.shared.icon(forFile:)` for Finder, Safari,
  Messages, Notes, System Settings; Trash from `CoreTypes.bundle`
  (`TrashIcon.icns`). Files: `app-*.png` (256×256). Each PNG already contains its
  own squircle + margins — no CSS `borderRadius`.
- **Menu-bar & Notes-toolbar glyphs** — real SF Symbols via
  `NSImage(systemSymbolName:)`, recolored with `.sourceIn` and rendered @4×.
  Files: `mb-*.png` (Apple logo, battery.100, wifi, magnifyingglass, switch.2,
  mic.fill) and `nt-*.png` (sidebar.left, list.bullet, square.grid.2x2, trash,
  square.and.pencil, textformat, checklist, tablecells, photo, lock.open.fill,
  square.and.arrow.up, link).
- **Cursor** — `NSCursor.arrow.image` (`cursor-arrow.png`) with hotspot/size in
  `cursor-meta.json` (hotspot 5,5; native 28×40). Extraction requires a GUI app
  context: the script calls `NSApplication.shared.setActivationPolicy(.accessory)`
  first, otherwise the cursor image resolves to 0×0 and the bitmap rep fails.
- **Wallpaper** — system desktop picture converted to `wallpaper.jpg` via
  `sips`. The video uses **`Mac Purple.heic`** (purple/lavender abstract) because
  its tone flatters the dark JVoice UI under blur; `Sonoma.heic` was an option but
  its green lower half clashed with the dark window and colored overlays.
- The JVoice status item is a bold 15px **"J"** drawn in React (mirrors
  `MenuBarController.makeStatusIcon()`); it swaps to `mb-mic-recording.png`
  (mic.fill, systemRed) while recording.

**Before rendering on a new machine, re-run** `swift scripts/extract-assets.swift`
then `sips -s format jpeg -Z 3200 "/System/Library/Desktop Pictures/Mac Purple.heic" --out public/system/wallpaper.jpg`
to repopulate `public/system/` (assets are machine-specific OS artifacts).

## Post-rebuild product deltas (2026-06-06, later same day)

- **Menu bar transcribing state**: the status item now has three states —
  idle bold "J" (template), recording `mic.fill` (systemRed), transcribing
  `waveform` tinted rgb(0,212,224) (the HUD transcribing accent). Mirrored in
  `Desktop.tsx` via `recording`/`transcribing` props and the
  `mb-waveform-transcribing.png` asset.
- **Whisper Model guidance caption**: `SettingsView` shows a 10pt gray
  (white 0.38) caption under the model picker (`WhisperModelChoice.guidance`).
  The panel mirror shows the Tiny caption ("Fastest · smallest download ·
  least accurate") since Tiny is the selected segment.
- **HUD `.preparingModel` state** (purple accent rgb(128,96,255), gearshape.2,
  "Preparing Model / First use can take a few minutes…") exists in the app but
  is deliberately NOT depicted in the demo (transient first-use state).
