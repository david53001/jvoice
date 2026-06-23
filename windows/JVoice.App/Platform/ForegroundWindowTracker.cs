using System.Runtime.InteropServices;

namespace JVoice.App.Platform;

/// Remembers the last foreground window that is NOT owned by this process, so the
/// paste target is the app the user was in before JVoice's HUD/tray took focus.
/// Windows analog of the macOS lastNonSelfFrontmostPID. Uses a SetWinEventHook for
/// EVENT_SYSTEM_FOREGROUND; must be created/Started on a thread that pumps Win32
/// messages (the WPF UI thread in Phase 4).
public sealed class ForegroundWindowTracker : IDisposable
{
    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;

    private WinEventDelegate? _callback; // keep the delegate alive (GC would collect it)
    private IntPtr _hook = IntPtr.Zero;

    public IntPtr LastForegroundWindow { get; private set; } = IntPtr.Zero;

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        // Seed with the current foreground window if it isn't ours.
        IntPtr current = GetForegroundWindow();
        if (current != IntPtr.Zero && !IsOwnWindow(current))
            LastForegroundWindow = current;

        _callback = OnForegroundChanged;
        _hook = SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, _callback, 0, 0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    public void Stop()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWinEvent(_hook);
            _hook = IntPtr.Zero;
        }
        _callback = null;
    }

    public void Dispose() => Stop();

    public static IntPtr GetForegroundWindowNow() => GetForegroundWindow();

    /// True when `hwnd` belongs to this (JVoice) process — i.e. it is our own
    /// HUD/Settings window, never a paste target. Process-ownership check (the
    /// Windows analog of the macOS `processIdentifier != ownPID` test), so it is
    /// correct for *every* one of our windows and never goes stale — unlike a single
    /// HWND captured at launch. Used by VoiceCoordinator to decide whether the live
    /// foreground is "self" when resolving the paste target.
    public static bool IsOwnedByCurrentProcess(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        _ = GetWindowThreadProcessId(hwnd, out uint pid);
        return pid == (uint)Environment.ProcessId;
    }

    private void OnForegroundChanged(
        IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero) return;
        if (IsOwnWindow(hwnd)) return; // never target our own HUD/tray/settings window
        LastForegroundWindow = hwnd;
    }

    private bool IsOwnWindow(IntPtr hwnd) => IsOwnedByCurrentProcess(hwnd);

    // P/Invoke

    private delegate void WinEventDelegate(
        IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWinEventHook(
        uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
