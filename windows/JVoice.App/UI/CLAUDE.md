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
  Transcripts history (root `CLAUDE.md` §7 #26). **Layout is a wide two-column "masonry"** (640×846:
  full-width header, 10 cards split across two independent vertical-StackPanel columns, full-width
  footer; root `CLAUDE.md` §7 #29). The `ScrollViewer` keeps `HorizontalScrollBarVisibility="Disabled"`
  on purpose — that's what gives the body a finite width so the `*` columns resolve.
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
