# App / UI — WPF (native look: Settings, HUD pill, tray)

**The native look (2026-10-02, parity rows 28–30) replaced the 2026-06-23 monochrome redesign.**
Windows 11 Fluent following the Mac's design language: Mica behind the content, surfaces as TINTS of
the text colour (card 4 %, hairline 8 %, input 6 %, row hover 7 %), Segoe UI Variable text styles, no
decorative dots/glows, colour only where it means something (accent, red = destructive, orange =
warning). `Theme.cs` owns System/Light/Dark (follows Windows' app mode live) and the Opacity setting:
every brush is a **DynamicResource** it rewrites (`Text.*`, `Card.*`, `Input.Fill`, `Row.Hover`,
`Button.*`, `Accent`, `Danger`, `Window.Backing`, `Pill.Backing` …) — never hard-code a colour in XAML;
add a key to `Theme.Refresh` + the dark default in `Styles/JVoicePalette.xaml`. `Theme.Attach(window)`
gives a window Mica + rounded corners + a themed title bar. The HUD bars stay a generated wave.

## Key files
- `HudView.xaml` / `.cs`, `HudWindow.cs` — the recording/transcribing pill. Solid bar shapes (not
  AA text) so it stays crisp at non-native gaming resolutions; `DisplayMetrics.HudScale` sizes it
  to the Mac's share of the screen area (HANDOFF §7 #68; 1.074× at 1500×1080). **Fix blur IN-APP — never tell David to change his resolution** (memory
  `dev-monitor-native-1920x1080`).
- `SettingsView.xaml` / `.cs`, `SettingsWindow.cs`, `MasonryPanel.cs` — settings, plus the Windows-only
  Recent Transcripts history (root `CLAUDE.md` §7 #26). **Since WINDOWS-HANDOFF §9 (2026-10-17) the window
  is RESIZABLE** (drag edges/corners; double-click the title bar or Maximize fills the work area and
  restores again — native Win32, so never re-add `SizeToContent` or a `MaxHeight`/`MaxWidth`: they snap the
  window back or cap a maximized one). It opens at `SettingsWindow.DesignedWidth` (1080) × the content's
  height capped to the work area (the old §7 #33 "X never off-screen" guard, now a starting size), minimum
  700 × 420, and keeps its size/maximized state across hide/show. Layout: header · Stats full width ·
  every other card in a **`MasonryPanel`** (`Core/Policy/MasonryLayout`: 2 / 3 / 4 columns at content
  width 560 / 900 / 1360, each card IN ORDER into the currently shortest column — no holes at any width,
  reflows live while dragging) · footer; content capped at 1440 and centred. Card order = the Mac's
  (Whisper Model, Recent Transcripts, Processing, Custom Words, Voice Style, Language, App Modes, Keyboard
  Shortcut, AI Polish, Tours & Tips, Appearance) with Corrections / Microphone / Gaming / Updates slotted
  next to their neighbours. Cards have no margin of their own (the panel owns the 12-DIP spacing). The
  `ScrollViewer` keeps `HorizontalScrollBarVisibility="Disabled"` (finite width for the columns).
  `--settings-render <png> [--size WxH|Wxfull]` renders a client size (viewport) or the full content at a
  width; it still needs **two** measure/arrange passes. The **Whisper Model** card carries a monochrome
  "keep on Large" warning callout (Segoe MDL2 `E7BA` triangle); its extra caution line is bound to
  `IsLarge` via `InverseBoolToVis` (root `CLAUDE.md` §7 #35).
- `TrayIcon.cs` — monochrome status item (idle / recording / transcribing) + Help & Tours ▸.
- `WelcomeView.xaml` / `WelcomeWindow.cs` — the first-run Welcome window (rows 31/32): NEW users only, two pages,
  "Want a quick tour?"; closing it unanswered = No Thanks (quitting is not an answer). Settings carries the ⓘ
  (`settings.help`) and a Tours & Tips card; the Appearance card's anchor is `settings.appearance` (the tour's
  Opacity step), the header picker's is `settings.theme`.
- `Converters.cs`, `SettingsCard.cs`, `Theme.cs`, `HotkeyRecorder.cs`, `TranscriptRow.cs`,
  `Styles/JVoicePalette.xaml` — support + palette.

- **AI Polish (§7 #70):** `ClaudeGlowText.cs` is the ONE "Claude is working" glow (a #D97757 band swept
  through the letters over a breathing orange glow; `Core/Policy/ClaudeGlow` holds the Mac's numbers):
  Full on the HUD's `RefiningPanel` ("AI refining", 1.6 s), Subtle on the AI Polish card title
  (`SettingsCard.GlowHeader`, 3.2 s, fainter). It animates only while visible and holds still when Windows
  animations are off. The AI Polish card is a normal stacked masonry card; the key field is NEVER
  data-bound (code-behind moves it between the PasswordBox/TextBox and the coordinator; reveal resets when
  the window hides) and, with a key saved, its empty placeholder is the hint "••••abcd". Renders:
  `--settings-render <png> aipolish-nokey|zero|on|revealed|usedup [light|dark]`, `--hud-render <png> refining`.

## Trap
The HUD bars are a generated animation, **not** a microphone level meter — David preferred a steady
flow over reactive bars that stuttered on his words (root `CLAUDE.md` §7 #23). Don't wire them to
live mic RMS.

## Verify
`JVoice.exe --hud-preview <state>` · `--hud-render <png>` · `--settings-render <png>` ·
`--welcome-render <png> [allset] [question] [light|dark]` · `--tour-render <png> [light|dark]` to screenshot any UI
state (renders never write a setting or tours.json).
