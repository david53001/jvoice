using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace JVoice.App.Platform;

/// Reads the exe name of the process owning a window, for the Windows-only "app-aware modes"
/// feature (AppModeResolver decides the tone from it). Deliberately the SAME read-only access
/// class as GameDetector — <c>PROCESS_QUERY_LIMITED_INFORMATION</c> + <c>QueryFullProcessImageName</c>
/// ONLY: no memory reads, no module enumeration, no injection (anti-cheat-safe by construction;
/// root CLAUDE.md §7 #27). Returns null on any failure (e.g. a higher-integrity process we can't
/// open), in which case the caller falls back to the user's global tone.
public static class ForegroundApp
{
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    /// The foreground window's process exe name WITHOUT extension (e.g. "Code", "WindowsTerminal"),
    /// or null if it can't be determined. Case is preserved; AppModeResolver normalizes.
    public static string? ExeName(IntPtr hwnd)
    {
        string? path = ExePath(hwnd);
        return path is null ? null : Path.GetFileNameWithoutExtension(path);
    }

    private static string? ExePath(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        _ = GetWindowThreadProcessId(hwnd, out uint pid);
        if (pid == 0) return null;

        IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (hProc == IntPtr.Zero) return null; // can't open (e.g. higher integrity) — safe fallback
        try
        {
            // Mirrors GameDetector's read exactly (CharSet.Unicode → the ...W entry point,
            // ref uint size, ToString(0, cap)); a non-Unicode marshal would mangle a non-ASCII
            // install path and break the app-mode match.
            var sb = new StringBuilder(1024);
            uint cap = (uint)sb.Capacity;
            return QueryFullProcessImageName(hProc, 0, sb, ref cap) ? sb.ToString(0, (int)cap) : null;
        }
        finally
        {
            CloseHandle(hProc);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);
}
