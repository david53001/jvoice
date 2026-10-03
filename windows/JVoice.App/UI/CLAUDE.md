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
- `SettingsView.xaml` / `.cs`, `SettingsWindow.cs` — settings, plus the Windows-only Recent
  Transcripts history (root `CLAUDE.md` §7 #26). **Since rows 28–30: 1080 wide, ~940 tall, header
  (title + System/Light/Dark) over three columns of `SettingsCard`s (Stats heads the right column so
  the panel fits a 1080-tall desktop); keep every column ending near the same height.** History of
  the old layout: it was a wide three-column "masonry"
  (Width=960, height sized to content ≈ 757: full-width header, 11 cards split across three
  independent vertical-StackPanel columns, full-width footer; root `CLAUDE.md` §7 #33). Went from
  two columns (640×1080) to three because a ~1080-tall window pushed the title-bar close (X) off
  the top of David's non-native 1600×1080 desktop — three columns keep the panel short enough that
  the whole thing (and its X) fits the screen work area. Each column is still ~300px wide (same as
  the old per-card width, so no card is more cramped). The view has **no fixed Height** (sizes to
  content, mirroring the live `SizeToContent` window); `SettingsWindow` also clamps
  `MaxHeight = WorkArea.Height − 16` as a guard so the X can never be pushed off-screen again, and
  the four list cards (Recent Transcripts / Custom Words / Corrections / App Modes) are kept in
  separate columns so no column balloons. The `ScrollViewer` keeps
  `HorizontalScrollBarVisibility="Disabled"` on purpose — that's what gives the body a finite width
  so the `*` columns resolve. **Note:** `--settings-render` needs **two** measure/arrange passes
  before reading `DesiredSize.Height` (the outer ScrollViewer settles its extent only after the
  first layout pass — a single pass under-measures and clips the tallest column). The **Whisper
  Model** card carries a monochrome "keep on Large" warning callout (Segoe MDL2 `E7BA` triangle);
  its extra caution line is bound to `IsLarge` via `InverseBoolToVis` and shows only when a smaller
  model is selected (root `CLAUDE.md` §7 #35).
- `TrayIcon.cs` — monochrome status item (idle / recording / transcribing) + Help & Tours ▸.
- `WelcomeView.xaml` / `WelcomeWindow.cs` — the first-run Welcome window (rows 31/32): NEW users only, two pages,
  "Want a quick tour?"; closing it unanswered = No Thanks (quitting is not an answer). Settings carries the ⓘ
  (`settings.help`) and a Tours & Tips card; the Appearance card's anchor is `settings.appearance` (the tour's
  Opacity step), the header picker's is `settings.theme`.
- `Converters.cs`, `SettingsCard.cs`, `Theme.cs`, `HotkeyRecorder.cs`, `TranscriptRow.cs`,
  `Styles/JVoicePalette.xaml` — support + palette.

## Trap
The HUD bars are a generated animation, **not** a microphone level meter — David preferred a steady
flow over reactive bars that stuttered on his words (root `CLAUDE.md` §7 #23). Don't wire them to
live mic RMS.

## Verify
`JVoice.exe --hud-preview <state>` · `--hud-render <png>` · `--settings-render <png>` ·
`--welcome-render <png> [allset] [question] [light|dark]` · `--tour-render <png> [light|dark]` to screenshot any UI
state (renders never write a setting or tours.json).
