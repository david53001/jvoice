using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using JVoice.Core;

namespace JVoice.App.Platform;

/// <summary>
/// The monitor the user is on: the one with the mouse pointer (parity row 34; Mac <c>ActiveScreen</c>). Before this a
/// windowless tray app put Settings and the pill on the primary display. All lookups are microseconds (safe on the
/// press → pill path, §7 #49).
/// </summary>
public static class ActiveScreen
{
    /// <summary>The pointer's monitor: its work area in physical pixels and its DPI scale (1.0 = 96 dpi).</summary>
    public static (PxRect Work, double Scale)? UnderPointer()
    {
        try
        {
            if (!GetCursorPos(out var pt)) return null;
            var mon = MonitorFromPoint(pt, MonitorDefaultToNearest);
            if (mon == IntPtr.Zero) return null;
            var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
            if (!GetMonitorInfo(mon, ref info)) return null;
            double scale = GetDpiForMonitor(mon, 0 /* MDT_EFFECTIVE_DPI */, out uint dpiX, out _) == 0 && dpiX > 0 ? dpiX / 96.0 : 1.0;
            var r = info.rcWork;
            return (new PxRect(r.Left, r.Top, r.Right, r.Bottom), scale);
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) { return null; }
    }

    /// <summary>Centres a not-yet-visible window on the pointer's monitor BEFORE it shows (no flash on the old one).
    /// <paramref name="sizeDip"/> is the window's outer size in DIPs. Returns false (caller keeps its own placement)
    /// when anything is unavailable.</summary>
    public static bool CenterBeforeShow(Window window, Size sizeDip)
    {
        if (UnderPointer() is not { } screen || sizeDip.Width <= 0 || sizeDip.Height <= 0) return false;
        var hwnd = new WindowInteropHelper(window).EnsureHandle();
        var (x, y) = ScreenPlacement.Center(screen.Work, sizeDip.Width, sizeDip.Height, screen.Scale);
        window.WindowStartupLocation = WindowStartupLocation.Manual;
        return SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SwpNoSize | SwpNoZOrder | SwpNoActivate);
    }

    /// <summary>Moves a window's top-left to (x, y) physical pixels without resizing or activating it.</summary>
    public static void MoveTo(IntPtr hwnd, int x, int y) =>
        SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SwpNoSize | SwpNoZOrder | SwpNoActivate);

    private const uint MonitorDefaultToNearest = 2;
    private const uint SwpNoSize = 0x0001, SwpNoZOrder = 0x0004, SwpNoActivate = 0x0010;

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
