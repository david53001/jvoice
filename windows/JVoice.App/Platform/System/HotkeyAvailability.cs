using System.Runtime.InteropServices;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// Asks Windows whether a chord is free (parity row 18): JVoice's own hotkeys are a low-level
/// hook, not RegisterHotKey, so a RegisterHotKey probe that fails with
/// ERROR_HOTKEY_ALREADY_REGISTERED means Windows or ANOTHER app already owns the chord. The probe
/// is registered and released at once on the calling thread; no WM_HOTKEY can arrive in between.
public static class HotkeyAvailability
{
    private const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
    private const int ERROR_HOTKEY_ALREADY_REGISTERED = 1409;
    private const int ProbeId = 0x4A56; // "JV"

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    /// True only when Windows reports the chord as already registered by someone else; any other
    /// failure (or success) is "not known to be taken".
    public static bool IsTaken(HotkeyChord chord)
    {
        uint mods = MOD_NOREPEAT;
        if (chord.Modifiers.HasFlag(HotkeyModifiers.Alt)) mods |= MOD_ALT;
        if (chord.Modifiers.HasFlag(HotkeyModifiers.Control)) mods |= MOD_CONTROL;
        if (chord.Modifiers.HasFlag(HotkeyModifiers.Shift)) mods |= MOD_SHIFT;
        if (chord.Modifiers.HasFlag(HotkeyModifiers.Win)) mods |= MOD_WIN;
        if (RegisterHotKey(IntPtr.Zero, ProbeId, mods, (uint)chord.VirtualKey))
        {
            UnregisterHotKey(IntPtr.Zero, ProbeId);
            return false;
        }
        return Marshal.GetLastWin32Error() == ERROR_HOTKEY_ALREADY_REGISTERED;
    }
}
