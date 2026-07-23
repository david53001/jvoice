using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure decision helpers extracted from GlobalHotkey (the App-layer low-level keyboard hook) so the
/// timing/matching logic is unit-testable without injecting system-wide input. Behaviour-preserving:
/// each method is the exact predicate GlobalHotkey used inline.
public static class HotkeyGate
{
    /// Debounce gate (GlobalHotkey.TryDebounce): a fire is allowed only once the debounce window has
    /// fully elapsed since the last fire. `>=` so a press exactly `windowMs` later is allowed; the
    /// first-ever press (lastFiredTicks == 0, nowTicks large) is always allowed.
    public static bool DebounceAllows(long nowTicks, long lastFiredTicks, int windowMs)
        => nowTicks - lastFiredTicks >= windowMs;

    /// Hook-staleness signal (GlobalHotkey.WatchdogTick): the low-level hook looks evicted when the
    /// system has registered input materially newer than our hook's last callback. `unchecked` makes
    /// the subtraction wrap-safe across the 32-bit GetTickCount domain (both args share it).
    public static bool HookIsStale(int systemLastInputTick, int lastCallbackTick, int thresholdMs)
        => unchecked(systemLastInputTick - lastCallbackTick) > thresholdMs;

    /// Exact modifier match (GlobalHotkey.MatchesChord): the live modifier state must equal the chord's
    /// required set EXACTLY — extra held modifiers (e.g. an extra Alt) reject the match.
    public static bool ModifiersMatch(bool ctrl, bool alt, bool shift, bool win, HotkeyModifiers want)
        => ctrl == want.HasFlag(HotkeyModifiers.Control)
        && alt == want.HasFlag(HotkeyModifiers.Alt)
        && shift == want.HasFlag(HotkeyModifiers.Shift)
        && win == want.HasFlag(HotkeyModifiers.Win);

    /// §7 #44 auto-repeat gate: a toggle hotkey fires only on the chord key's down TRANSITION.
    /// The low-level hook receives a fresh WM_KEYDOWN for every keyboard auto-repeat of a held
    /// key, and the 150 ms debounce does NOT absorb those — Windows' shortest repeat delay is
    /// 250 ms, so a slightly-long hold of the stop chord re-fired the toggle 313 ms later on
    /// 2026-07-23 (restarting recording while the previous dictation was still transcribing).
    /// `mainKeyAlreadyDown` is the hook's tracked key state (down seen, no key-up yet).
    public static bool AllowsKeyDownFire(bool mainKeyAlreadyDown) => !mainKeyAlreadyDown;
}
