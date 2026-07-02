using System.Diagnostics;
using Microsoft.Win32;

namespace JVoice.App.Platform;

/// Launch-at-login via the HKCU Run key. Faithful port of LaunchAtLoginManager.swift:
/// IsEnabled / SetEnabled, plus a one-time first-run auto-enable guarded by an init
/// flag so we never re-enable after the user deliberately turns it off.
/// No elevation required (all HKCU). Errors are swallowed/reported, never thrown to
/// the UI (a dev/unsigned copy may fail to write; the user can flip the toggle later).
public static class LaunchAtLogin
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "JVoice";
    private const string AppKeyPath = @"Software\JVoice";
    private const string InitFlagName = "LaunchAtLoginInitialized";

    /// The exe path written into the Run value. For a published self-contained
    /// single-file build this is the .exe; for `dotnet run` it is the apphost/dll
    /// host — fine for dev (launch-at-login is a release feature).
    public static string CurrentExecutablePath
    {
        get
        {
            // Process.MainModule.FileName is the actual host .exe (e.g. JVoice.exe),
            // not the managed dll — correct for the Run key.
            using var proc = Process.GetCurrentProcess();
            return proc.MainModule?.FileName
                ?? Environment.ProcessPath
                ?? AppContext.BaseDirectory;
        }
    }

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using RegistryKey? run = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
                return run?.GetValue(RunValueName) is string s && s.Length > 0;
            }
            catch { return false; }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using RegistryKey run = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (enabled)
                // The --autostart marker lets App.Main tell a logon launch from a manual one, so a
                // non-elevated logon copy can step aside for the elevated logon task (Elevation/
                // ElevatedAutostart). Harmless to every other code path (it ignores the flag).
                run.SetValue(RunValueName, $"{Quote(CurrentExecutablePath)} {Elevation.AutostartFlag}", RegistryValueKind.String);
            else if (run.GetValue(RunValueName) is not null)
                run.DeleteValue(RunValueName, throwOnMissingValue: false);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Could not update launch-at-login. {ex.Message}");
        }
    }

    /// First launch only: set the init flag and best-effort enable. Silent by design.
    public static void PerformFirstRunEnableIfNeeded()
    {
        try
        {
            using RegistryKey app = Registry.CurrentUser.CreateSubKey(AppKeyPath, writable: true);
            object? flag = app.GetValue(InitFlagName);
            if (flag is int i && i != 0) return; // already initialized
            app.SetValue(InitFlagName, 1, RegistryValueKind.DWord);
        }
        catch
        {
            // If we can't even write the flag, don't risk repeatedly re-enabling; bail.
            return;
        }
        SetEnabled(true); // best-effort; SetEnabled already swallows/reports failures
    }

    /// Wrap the path in quotes so a space in the path (e.g. "C:\Program Files\...")
    /// is treated as a single argument by the shell at logon.
    private static string Quote(string path) => path.StartsWith('"') ? path : $"\"{path}\"";
}
