using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

// Pure decision logic extracted from GlobalHotkey (App-layer hook) so it's unit-testable without
// injecting system-wide input. The live hook lifecycle (install / gap-free re-arm / message pump /
// eviction-recovery) is verified by code-review + windows/tools/hotkey-probe at dogfood time.
public class HotkeyGateTests
{
    // ---- DebounceAllows (window = AppTimings.HotkeyDebounceMs = 150) ----
    [Theory]
    [InlineData(1000, 800, 150, true)]   // 200ms since last >= 150 -> allowed
    [InlineData(1000, 900, 150, false)]  // 100ms < 150 -> suppressed
    [InlineData(1000, 850, 150, true)]   // exactly 150 -> allowed (>=)
    [InlineData(1000, 851, 150, false)]  // 149 -> suppressed
    public void DebounceAllows_Window(long now, long last, int win, bool expected)
        => Assert.Equal(expected, HotkeyGate.DebounceAllows(now, last, win));

    [Fact]
    public void DebounceAllows_FirstFire_LastZero_IsAllowed()
        => Assert.True(HotkeyGate.DebounceAllows(Environment.TickCount64, 0, 150));

    // ---- HookIsStale (watchdog threshold = 3000) ----
    [Theory]
    [InlineData(10000, 6000, 3000, true)]   // gap 4000 > 3000 -> stale
    [InlineData(10000, 8000, 3000, false)]  // gap 2000 -> healthy
    [InlineData(10000, 7000, 3000, false)]  // gap exactly 3000 -> not > -> healthy
    [InlineData(10000, 6999, 3000, true)]   // gap 3001 -> stale
    public void HookIsStale_Threshold(int sysLast, int lastCb, int threshold, bool expected)
        => Assert.Equal(expected, HotkeyGate.HookIsStale(sysLast, lastCb, threshold));

    // Wrap-safe across the 32-bit GetTickCount rollover: a small REAL gap straddling int overflow
    // must NOT register as stale; a large real gap must.
    [Fact]
    public void HookIsStale_WrapAround_SmallRealGap_NotStale()
    {
        int lastCb = int.MaxValue - 100;
        int sysLast = unchecked(lastCb + 200); // wrapped; real elapsed = 200ms
        Assert.False(HotkeyGate.HookIsStale(sysLast, lastCb, 3000));
    }

    [Fact]
    public void HookIsStale_WrapAround_LargeRealGap_IsStale()
    {
        int lastCb = int.MaxValue - 100;
        int sysLast = unchecked(lastCb + 5000); // wrapped; real elapsed = 5000ms
        Assert.True(HotkeyGate.HookIsStale(sysLast, lastCb, 3000));
    }

    // ---- ModifiersMatch (EXACT set; any extra/missing modifier rejects) ----
    [Fact]
    public void ModifiersMatch_ExactCtrlShift_True()
        => Assert.True(HotkeyGate.ModifiersMatch(ctrl: true, alt: false, shift: true, win: false,
            HotkeyModifiers.Control | HotkeyModifiers.Shift));

    [Fact]
    public void ModifiersMatch_ExtraAltHeld_False()
        => Assert.False(HotkeyGate.ModifiersMatch(ctrl: true, alt: true, shift: true, win: false,
            HotkeyModifiers.Control | HotkeyModifiers.Shift));

    [Fact]
    public void ModifiersMatch_MissingShift_False()
        => Assert.False(HotkeyGate.ModifiersMatch(ctrl: true, alt: false, shift: false, win: false,
            HotkeyModifiers.Control | HotkeyModifiers.Shift));

    [Fact]
    public void ModifiersMatch_NoneWanted_NoneHeld_True()
        => Assert.True(HotkeyGate.ModifiersMatch(false, false, false, false, HotkeyModifiers.None));

    [Fact]
    public void ModifiersMatch_NoneWanted_CtrlHeld_False()
        => Assert.False(HotkeyGate.ModifiersMatch(true, false, false, false, HotkeyModifiers.None));

    [Fact]
    public void ModifiersMatch_AllFour_True()
        => Assert.True(HotkeyGate.ModifiersMatch(true, true, true, true,
            HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift | HotkeyModifiers.Win));

    // ---- AllowsKeyDownFire (auto-repeat gate, §7 #44) ----
    // A chord-key WM_KEYDOWN that arrives while the key is still physically held is keyboard
    // AUTO-REPEAT, not a new press — a toggle hotkey must fire once per press (down TRANSITION
    // only). The 150 ms debounce alone does NOT cover this: Windows' shortest repeat delay is
    // 250 ms, so a slightly-long hold re-fired the toggle 313 ms after the stop press on
    // 2026-07-23 and restarted recording mid-transcription.
    [Fact]
    public void AllowsKeyDownFire_DownTransition_True()
        => Assert.True(HotkeyGate.AllowsKeyDownFire(mainKeyAlreadyDown: false));

    [Fact]
    public void AllowsKeyDownFire_AutoRepeat_False()
        => Assert.False(HotkeyGate.AllowsKeyDownFire(mainKeyAlreadyDown: true));
}
