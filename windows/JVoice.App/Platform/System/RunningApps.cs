using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace JVoice.App.Platform;

/// One entry in the "pick an app" list for app-aware mode rules.
/// <see cref="Exe"/> is the exe name WITHOUT extension (what AppModeResolver matches);
/// <see cref="Display"/> is a friendly label (the file description, e.g. "Visual Studio Code",
/// falling back to the exe name).
public sealed record AppChoice(string Display, string Exe);

/// Enumerates the user's currently-open apps (visible, titled top-level windows) so the Settings
/// UI can offer a searchable picker instead of a raw exe-name text box. Read-only, same access
/// class as GameDetector/ForegroundApp — window enumeration + <c>QueryFullProcessImageName</c> (via
/// <see cref="ForegroundApp.ExePath"/>) + reading the exe file's version info off disk. No process
/// memory reads, no module enumeration, no injection (anti-cheat-safe; root CLAUDE.md §7 #27).
public static class RunningApps
{
    private const uint GW_OWNER = 4;
    private const int GWL_EXSTYLE = -20;
    private const long WS_EX_TOOLWINDOW = 0x00000080;

    // Shell/host processes that own visible titled windows but aren't apps a user dictates into.
    private static readonly HashSet<string> Skip = new(StringComparer.OrdinalIgnoreCase)
    {
        "ApplicationFrameHost", "TextInputHost", "ShellExperienceHost", "StartMenuExperienceHost",
        "SearchHost", "SearchApp", "LockApp", "PeopleExperienceHost",
    };

    /// Currently-open apps, de-duplicated by exe and sorted by display name. Best-effort: any window
    /// we can't inspect is simply skipped.
    public static IReadOnlyList<AppChoice> List()
    {
        var byExe = new Dictionary<string, AppChoice>(StringComparer.OrdinalIgnoreCase);
        uint ownPid = (uint)Environment.ProcessId;

        EnumWindows((hwnd, _) =>
        {
            try
            {
                if (!IsWindowVisible(hwnd)) return true;
                if (GetWindow(hwnd, GW_OWNER) != IntPtr.Zero) return true;   // owned (dialog/tooltip)
                if (GetWindowTextLength(hwnd) == 0) return true;             // no title → not an app
                if ((GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64() & WS_EX_TOOLWINDOW) != 0) return true;

                GetWindowThreadProcessId(hwnd, out uint pid); // return (thread id) unused
                if (pid == 0 || pid == ownPid) return true;

                string? path = ForegroundApp.ExePath(hwnd);
                if (path is null) return true;
                string exe = Path.GetFileNameWithoutExtension(path);
                if (exe.Length == 0 || Skip.Contains(exe)) return true;

                if (!byExe.ContainsKey(exe))
                    byExe[exe] = new AppChoice(FriendlyName(path, exe), exe);
            }
            catch { /* skip any window we can't inspect */ }
            return true;
        }, IntPtr.Zero);

        return byExe.Values.OrderBy(a => a.Display, StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// The exe's FileDescription (e.g. "Google Chrome") if present, else the exe name. Reads version
    /// info off the file on disk — not the running process.
    private static string FriendlyName(string path, string exe)
    {
        try
        {
            string? desc = FileVersionInfo.GetVersionInfo(path).FileDescription?.Trim();
            if (!string.IsNullOrEmpty(desc)) return desc;
        }
        catch { /* fall back to the exe name */ }
        return exe;
    }

    // P/Invoke (window enumeration only; the privileged exe read is ForegroundApp.ExePath)

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
