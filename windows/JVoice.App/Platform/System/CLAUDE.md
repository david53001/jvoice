# Platform / System — OS hooks, input, elevation, game detection

The most OS-privileged corner of the app: the global keyboard hook, synthetic paste, UAC
elevation, autostart, and the read-only game-detection signals. Touch with care — these are the
files most able to affect (or be flagged by) the rest of the system. **Behavior here is
contract-locked by the root `CLAUDE.md`; preserve the invariants below.**

## Key files
- `GlobalHotkey.cs` — the low-level global keyboard hook (`WH_KEYBOARD_LL`). It **swallows the
  chord key** so no stray space leaks into the focused app (root `CLAUDE.md` §7 #25).
- `Paster.cs` — pastes transcribed text into the foreground app (clipboard + synthetic input);
  `PasteOutcome` reports success/failure.
- `Elevation.cs` / `ElevatedAutostart.cs` — opt-in "run elevated" so the hotkey works in admin
  windows (UIPI). Elevation is **opt-in**; don't make it default.
- `LaunchAtLogin.cs` — autostart registration.
- `GameDetector.cs` — gathers game signals. **Anti-cheat-safe by construction (root `CLAUDE.md`
  §7 #27): read-only OS signals only** — `SHQueryUserNotificationState` D3D-fullscreen,
  `GameConfigStore`, install-path/exe-name match, window-rect-vs-monitor. The ONLY process access
  is `PROCESS_QUERY_LIMITED_INFORMATION` to read the exe path: **no memory reads, no module
  enumeration, no injection.** Never add any of those. The verdict logic is pure and lives in
  `Core/Policy/GameDetectionPolicy`.
- `GameProbeRunner.cs` — the `--game-probe` CLI that logs live signals to
  `%TEMP%\jvoice-gameprobe.log` for dogfood.
- `ForegroundWindowTracker.cs` — which window is frontmost (paste target + game detection).
- `DisplayMetrics.cs` — DPI/resolution; `HudScale` for the non-native-res blur fix (IN-APP only —
  memory `dev-monitor-native-1920x1080`).
- `SingleInstance.cs`, `SystemActions.cs`, `SettingsUris.cs`, `PermissionError.cs`,
  `DiagnosticLog.cs` — single-instance mutex, open-Windows-settings deep links, permission-error
  surface, diagnostics.

## Invariants (do not weaken)
1. Game detection stays **read-only** — no memory reads / module scans / injection, ever
   (anti-cheat safety).
2. When a game owns the foreground, the hotkey goes **silent and passes the chord through** — it
   must not pop the HUD or paste into game chat (§7 #27; the gate is `Core/Policy/HotkeyGate`).
3. Elevation is **opt-in**.
4. The hook **swallows the chord key** (no stray space leak).

## Verify
Pure halves: `dotnet test windows/JVoice.Tests` — HotkeyGateTests, GameDetectionPolicyTests,
HotkeyChordTests. OS behavior: dogfood + `JVoice.exe --game-probe`.
