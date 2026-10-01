# Core / Tours — the first-run guided tours (parity rows 31/32, `docs/MAC-TO-WINDOWS-PARITY.md` §10)

Pure, UI-free port of the Mac's TourKit + `TourCoordinator.swift` (`docs/mac-reference/src/tour-opacity/Tours/`).
The engine and tag layout are the same C# as BetterScreenshot's Windows port (`BetterScreenshot.Tours`).
Namespace `JVoice.Core.Tours`. Locked by `TourTests` + `TourCoordinatorTests`.

## The guarantee (do not weaken)
Tours are for NEW users only, asked first. The audience is classified ONCE, in `App.Main` before anything writes
`%APPDATA%\JVoice` (SettingsStore writes settings.json on construction; DiagnosticLog appends there), and stored in
`tours.json`; never recomputed. `existing` if ANY signal: a data-folder entry other than tours.json, a downloaded
model, mic consent "Allow" for this exe, `HKCU\Software\JVoice` exists, or a bin\ build path. Doubt → existing.
David's PC is existing on every signal. A tour starts by itself only with `firstUseToursEnabled == true`.

## Files
- `TourModel.cs` — ids (persisted raw values: welcome / recordingPill / settings), surfaces, events, steps, triggers.
- `TourEngine.cs` — the state machine (missing anchors skipped, Try steps, progress counted over shown steps).
- `TourRules.cs` — `TourAudience` (classifier), `TourRules` (ask / auto-start), `TourText` (`{shortcut:…}`).
- `TourPrefs.cs` — the five persisted keys + lenient JSON (tours.json is its own file on purpose).
- `TourCatalog.cs` — every step's copy (Mac verbatim + Windows wording). The pill step drops "again"/"for you" so it
  fits 2 lines with "Ctrl+Alt+Shift+Win+F12" (the lint measures with WPF FormattedText — that's why the test project
  is `net9.0-windows` + UseWPF).
- `TagLayout.cs` — where the tag goes, `TagKeys` (Enter/Esc), `TagStyle` (look numbers, concentric outline radius).
- `OpacityDemoTimeline.cs` — the Opacity step's ~9.5 s demo motion (exact port).
- `TourCoordinator.cs` — triggers, hand-overs, pause/resume, Show Me parts, Reset All, persistence; drives an
  `ITourTagPresenter` over `ITourHost`s with an `ITourClock` (all faked in tests).

The WPF side (overlay, hosts, ⓘ, Welcome window, demo player) is `JVoice.App/Tours/` + `UI/WelcomeWindow.cs`.
