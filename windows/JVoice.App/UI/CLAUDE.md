# App / UI — WPF (monochrome HUD, Settings, tray)

The black-&-white redesign (2026-06-23). Text-free HUD; a **continuous voice-activity wave** while
recording (mic-independent — a generated wave, NOT a mic meter), indeterminate shimmer while
transcribing; a successful paste is **silent**; errors are the only text. Settings + tray are fully
monochrome.

## Key files
- `HudView.xaml` / `.cs`, `HudWindow.cs` — the recording/transcribing pill. Solid bar shapes (not
  AA text) so it stays crisp at non-native gaming resolutions; `DisplayMetrics.HudScale` enlarges
  by the stretch ratio. **Fix blur IN-APP — never tell David to change his resolution** (memory
  `dev-monitor-native-1920x1080`).
- `SettingsView.xaml` / `.cs`, `SettingsWindow.cs` — settings, plus the Windows-only Recent
  Transcripts history (root `CLAUDE.md` §7 #26). **Layout is a wide three-column "masonry"**
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
- `TrayIcon.cs` — monochrome status item (idle / recording / transcribing).
- `Converters.cs`, `DarkSection.cs`, `HotkeyRecorder.cs`, `TranscriptRow.cs`,
  `Styles/JVoicePalette.xaml` — support + palette.

## Trap
The HUD bars are a generated animation, **not** a microphone level meter — David preferred a steady
flow over reactive bars that stuttered on his words (root `CLAUDE.md` §7 #23). Don't wire them to
live mic RMS.

## Verify
`JVoice.exe --hud-preview <state>` · `--hud-render <png>` · `--settings-render <png>` to screenshot
any UI state.
