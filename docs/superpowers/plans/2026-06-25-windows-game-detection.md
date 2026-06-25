# Windows game-detection hotkey suppression (2026-06-25)

Zero-context design note for a new Windows-port feature: **suppress the JVoice hotkey
while the user is playing a video game**, so an accidental `Ctrl+Shift+Space` in
Minecraft / GTA / Fortnite / Valorant doesn't start a recording or paste text into the
game. Read this before touching the code; it records the goal, the **anti-cheat-safety
stance (non-negotiable)**, the signals, the pure decision policy, the exact integration
points in the existing code, the UX, the test/verify plan, and the deliberate
omissions and rejected alternatives.

> **Provenance / scope.** This is a **Windows-only** feature (`windows/`). It has **no
> macOS equivalent** — do not touch `Sources/`, `Tests/`, `Package.swift`, `Resources/`.
> The macOS app is read-only reference. Author: design agreed with David 2026-06-25.

---

## 0. TL;DR

When the **foreground app at the moment of the keypress** is a game, JVoice goes
**silent and fully transparent**: it does not record, and it **stops swallowing** the
chord so `Ctrl+Shift+Space` passes straight through to the game (it may be an in-game
bind). Detection is a bundle of cheap, **read-only** OS signals fed to a pure decision
function; the strongest single signal is Microsoft's own "a game is running fullscreen"
query (`SHQueryUserNotificationState`), the same one that drives Windows Focus Assist.

Default behaviour: **Balanced**, on by default. The user can turn it Off or make it
Aggressive, and (v2) maintain per-app allow/deny lists.

---

## 1. The problem (David, Windows port)

The global hotkey (default `Ctrl+Shift+Space`, a `WH_KEYBOARD_LL` hook in
`windows/JVoice.App/Platform/GlobalHotkey.cs`) fires anywhere, including inside a
fullscreen game. An accidental press:

- pops the recording HUD over the game and starts capturing the mic, and/or
- on a second press, pastes transcribed text into whatever has focus (e.g. game chat).

The hook also currently **swallows** the chord's main key on every match
(`GlobalHotkey.cs` `HookCallback` returns `(IntPtr)1`), so even an in-game
`Ctrl+Shift+Space` bind would be eaten. We want JVoice to disappear entirely while
gaming.

---

## 2. NON-NEGOTIABLE: anti-cheat safety (no false bans)

David's hard requirement: **this must never risk an anti-cheat ban** (Riot Vanguard,
Easy Anti-Cheat, BattlEye). The design guarantees this **by never interacting with the
game process at all**:

- **Only read public OS state.** The signals are: the foreground window handle
  (`GetForegroundWindow`), its rectangle vs the monitor (`GetWindowRect` /
  `GetMonitorInfo`), the system notification state (`SHQueryUserNotificationState`), the
  foreground process's image path via a **least-privilege** handle
  (`OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageName`), and a
  **registry read** of the list Windows itself maintains of recognized games
  (`HKCU\System\GameConfigStore\Children`).
- **Never do what anti-cheats actually ban for:** no reading the game's memory, no
  `PROCESS_VM_READ`, no DLL injection, no overlay drawing into the game, no synthesized
  input/keystrokes into the game. These are passive OS queries — the same category used
  by OBS, screenshot tools, and Windows' own "don't notify while gaming" feature.
- **If even the limited-info handle is denied** (some hardened processes), the
  process-based signals simply evaluate to `false` and we fall back to the
  process-untouching signals (`SHQueryUserNotificationState`, window-rect fullscreen).
  Denial is never treated as a positive signal and never retried with more privilege.
- **Deliberately omit the one signal that would open the process:** scanning the game's
  loaded graphics DLLs (Toolhelp module enumeration) is **excluded from v1** precisely to
  keep the process-interaction surface at exactly zero. The remaining signals already
  cover the named titles.

Net effect during a game: JVoice does *less*, not more — it stops swallowing the chord
and stops recording. There is no new game-process interaction anywhere in this feature.

---

## 3. The signals (ranked by reliability)

Gathered in `windows/JVoice.App/Platform/GameDetector.cs` (new, App layer — Win32 lives
here, never in Core). All are cheap; the heavy ones are computed off the hotkey thread
(see §6).

| # | Signal | Source | Strength | Catches |
|---|--------|--------|----------|---------|
| 1 | **D3D exclusive fullscreen** | `SHQueryUserNotificationState() == QUNS_RUNNING_D3D_FULL_SCREEN (3)` | **Decisive** — MS's own game signal (Focus Assist) | Most fullscreen games |
| 2 | **Windows-registered game** | `HKCU\System\GameConfigStore\Children\*` value `MatchedExeFullPath` equals the foreground exe path | **Strong**, zero-maintenance, per-user | Anything Windows recognized, incl. windowed Minecraft |
| 3 | **Known game install path** | foreground exe path contains a known game root (`\steamapps\common\`, `\Epic Games\`, `\Riot Games\`, `\GOG Galaxy\Games\`, `\Ubisoft\`, `\Battle.net\`, …) or matches a small curated exe-name set (`VALORANT-Win64-Shipping.exe`, `FortniteClient-Win64-Shipping.exe`, `GTA5.exe`, …) | **Strong**, works windowed | Store-installed titles |
| 4 | **Foreground is true-fullscreen** | window rect == monitor rect (small tolerance), excluding the shell (`Progman`/`WorkerW`) and our own windows | **Medium** (also trips on fullscreen video) | Borderless-windowed games |

The exe path for #2–#4 comes from `GetWindowThreadProcessId` → `OpenProcess(
PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageName`. `javaw.exe`
(Minecraft) is intentionally **not** in the curated name list (too ambiguous — many Java
apps use it); Minecraft is caught by signal #2 (GameConfigStore) or Aggressive mode.

`QUNS_PRESENTATION_MODE (4)` and `QUNS_BUSY (2)` are available but deliberately **not**
used in Balanced (presenting / a generic fullscreen app is not necessarily a game and we
don't want to surprise the user).

---

## 4. The decision policy (pure, in Core, unit-tested)

Mirrors the established pattern: pure logic in `JVoice.Core`, unit-tested from
`JVoice.Tests` (net9.0, cannot reference the net9.0-windows app) — exactly like
`HotkeyGate` / `CoordinatorDecisions`. Win32 signal-gathering stays in the App layer.

```csharp
// windows/JVoice.Core/GameDetectionPolicy.cs
public enum GameDetectionMode { Off, Balanced, Aggressive }

public readonly record struct GameSignals(
    bool D3DFullscreen,          // QUNS_RUNNING_D3D_FULL_SCREEN
    bool RegisteredGame,         // GameConfigStore matched the foreground exe
    bool KnownGamePath,          // exe under a known game root / curated name
    bool ForegroundIsFullscreen, // window covers the monitor, not shell, not self
    bool UserForceGame,          // (v2) user's per-exe "always pause here"
    bool UserForceNotGame);      // (v2) user's per-exe allowlist (never pause)

public static class GameDetectionPolicy
{
    public static bool ShouldSuppress(in GameSignals s, GameDetectionMode mode)
    {
        if (s.UserForceNotGame) return false;          // explicit allow wins
        if (s.UserForceGame)    return true;           // explicit deny wins
        if (mode == GameDetectionMode.Off) return false;

        // Balanced (default): high-confidence only; NO bare-fullscreen, so fullscreen
        // video / browsers never false-positive.
        if (s.D3DFullscreen || s.RegisteredGame || s.KnownGamePath) return true;

        // Aggressive (opt-in): also any borderless/exclusive fullscreen app — catches
        // obscure windowed games, but WILL also trip on fullscreen YouTube/Netflix.
        if (mode == GameDetectionMode.Aggressive && s.ForegroundIsFullscreen) return true;

        return false;
    }
}
```

Keeping bare fullscreen out of Balanced is the key false-positive guardrail. The function
unit-tests as a truth table (à la `HotkeyGateTests`).

---

## 5. Behaviour: suppress = silent AND transparent

When suppressing, JVoice must (a) **not** start/stop recording and (b) **not** swallow
the chord, so the keystroke reaches the game unmodified. This is the important subtlety:
the hook today *always* swallows on a chord match.

---

## 6. Integration points (exact, in existing code)

1. **`windows/JVoice.Core/GameDetectionPolicy.cs`** *(new)* — §4. Pure. + tests in
   `windows/JVoice.Tests/GameDetectionPolicyTests.cs` (truth table).

2. **`windows/JVoice.App/Platform/ForegroundWindowTracker.cs`** *(edit)* — already a
   `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)` on the UI thread. Add
   `public event Action<IntPtr>? ForegroundChanged;` and raise it at the end of
   `OnForegroundChanged` (after the self-window guard). Reuse this hook; do **not** add a
   second WinEvent hook.

3. **`windows/JVoice.App/Platform/GameDetector.cs`** *(new)* — owns
   `private volatile bool _suppress;` exposed as `public bool ShouldSuppress => _suppress;`.
   Recomputes signals → `GameDetectionPolicy.ShouldSuppress` on:
   - `ForegroundWindowTracker.ForegroundChanged`, and
   - a low-frequency `DispatcherTimer` (~1.5 s) backstop for a game going fullscreen
     *without* a foreground change (alt-enter).
   Caches the `GameConfigStore` exe-path set, refreshed infrequently (changes rarely).
   Holds the current `GameDetectionMode` (updated when the setting changes). All P/Invoke
   for §3 lives here.

4. **`windows/JVoice.App/Platform/GlobalHotkey.cs`** *(edit)* — add
   `public Func<bool>? SuppressPredicate { get; set; }`. In `HookCallback`, when
   `MatchesChord` is true but `SuppressPredicate?.Invoke() == true`: do **not** raise
   `Triggered`, do **not** debounce, and `return CallNextHookEx(...)` (passthrough)
   instead of `(IntPtr)1`. The predicate reads a `volatile bool` → O(1) → safe inside the
   `LowLevelHooksTimeout` budget (the heavy work is on the UI thread in `GameDetector`).
   Cross-thread: hook thread reads, UI thread writes a `volatile bool` — no lock needed.

5. **`windows/JVoice.App/VoiceCoordinator.cs`** *(edit)* — create `GameDetector`, start it
   in `Start()` next to `_foreground.Start()` (around line 196), set
   `_hotkey.SuppressPredicate = () => _gameDetector.ShouldSuppress;` **before**
   `_hotkey.Register(_hotkeyChord)` (line 202). Belt-and-suspenders: early-return in
   `ToggleRecording()` (line 524) when suppressing, so the tray "Start dictation" item is
   covered too. Push the mode into `_gameDetector` from the setter that owns it.

6. **`windows/JVoice.Core/Models/SettingsState.cs` + `SettingsStateJson.cs`** *(edit)* —
   add `GameDetectionMode GameMode` (default `Balanced`); v2 adds
   `IReadOnlyList<string> GameAllowList` / `GameDenyList`. **Bump
   `CurrentSchemaVersion` 1 → 2** and make deserialize tolerant of a missing field
   (default it) so existing `settings.json` still loads. `SettingsStore` already handles
   the forward-version case (`ForwardVersionException`); confirm a v1 file upgrades
   cleanly to v2 with `GameMode = Balanced`. Add a `SettingsStateTests` case for the
   missing-field migration.

7. **Settings UI** (`windows/JVoice.App/UI/SettingsView*` / `SettingsWindow.cs`) *(edit)* —
   a monochrome "Gaming" row: a toggle **"Pause hotkey while gaming"** (Off ↔ Balanced)
   plus an advanced **"…in any fullscreen app"** (Aggressive). Match the black-&-white
   redesign. Wire to a `VoiceCoordinator.GameMode` bindable property that persists via
   `PersistSettings()` and updates `GameDetector`.

8. **`windows/JVoice.App/App.xaml.cs`** *(edit)* — add a hidden `--game-probe` CLI next to
   `--hud-preview` (same dispatch shape in `Main`/`OnStartup`, bypassing the
   single-instance lock). It prints, on a loop, the live signals + final decision for the
   current foreground window: QUNS state name, fullscreen y/n, exe path, KnownGamePath,
   RegisteredGame, and `ShouldSuppress`. This is the **real** verification path (Win32
   fullscreen/QUNS can't be unit-tested) — David alt-tabs into each game and reads it.

---

## 7. Test & verify

- **Unit (CI + local `dotnet test windows/JVoice.Tests`):** `GameDetectionPolicyTests`
  truth table over every `GameSignals` × `GameDetectionMode` combination, incl.
  allow/deny precedence and the Balanced-excludes-bare-fullscreen guarantee.
  `SettingsStateTests` v1→v2 migration. Must keep the suite green (currently 434/434).
- **On-device (David, dogfood):** with `--game-probe` running, alt-tab into **Valorant,
  Fortnite, GTA V, Minecraft, a Steam game**, and confirm `ShouldSuppress=true`; press the
  hotkey in-game and confirm **no HUD / no recording** and that the chord reaches the
  game. Then alt-tab to a normal app (and to **fullscreen YouTube**) and confirm
  `ShouldSuppress=false` and the hotkey works again. Add these steps to
  `docs/launch/windows-dogfood-checklist.md`.
- **Build:** `dotnet build windows/JVoice.sln -c Release` = 0 errors.

---

## 8. Edge cases & decisions (the "why")

- **Foreground-keyed, not "any game running."** A backgrounded / alt-tabbed game does not
  suppress; dictating into an app on monitor 2 while a game sits on monitor 1 keeps
  working. This is the correct behaviour and falls out of evaluating the foreground
  window.
- **Borderless-windowed games** (modern Valorant/Fortnite default) may not trip
  `QUNS_RUNNING_D3D_FULL_SCREEN`; caught by GameConfigStore (#2) + known path (#3), or
  Aggressive's fullscreen heuristic (#4).
- **Fullscreen video** (YouTube/Netflix) stays dictatable in Balanced (no game path, no
  D3D-fullscreen). Aggressive intentionally suppresses it — the user opts in knowing that.
- **`javaw.exe` ambiguity** → not curated by name; rely on GameConfigStore or Aggressive.
- **Already-recording when a game takes focus** is out of scope for v1 (we gate the
  *trigger*); revisit if it bites in dogfood.

## 9. Rejected / deferred

- **Toolhelp graphics-DLL module scan** — *deferred indefinitely.* It would open the game
  process; dropping it keeps anti-cheat surface at zero (§2) and avoids the fullscreen-
  browser false positive (browsers load `d3d11.dll` too). Balanced doesn't need it.
- **Hard-coded master game list** — rejected as sole mechanism (unmaintainable);
  GameConfigStore + install-path roots are the zero-maintenance substitute, with a small
  curated name set only as a convenience.
- **Suppress on any fullscreen by default** — rejected (fullscreen-video false positives);
  it's the explicit Aggressive opt-in instead.

## 10. Phasing

- **v1 (this plan):** `GameDetectionPolicy` (+ tests) · `GameDetector` (signals #1–#4) ·
  `GlobalHotkey` passthrough · `ForegroundWindowTracker.ForegroundChanged` ·
  `VoiceCoordinator` wiring · `GameMode` setting (schema v2) + UI toggle · `--game-probe`
  · dogfood-checklist entries.
- **v2 (later):** per-exe allow/deny lists in Settings · first-suppression explainer ·
  complementary **manual "Pause JVoice"** tray toggle and/or **push-to-talk** (hold to
  record) so a stray tap can't latch a recording regardless of detection.

## 11. Decision-log note

On completion, add a numbered entry to `docs/HANDOFF-WINDOWS.md` §7 (next free number)
summarising: the feature, the **anti-cheat-safe (read-only, no game-process interaction)**
stance, the Balanced default, and the deliberate omission of the module-scan signal.
