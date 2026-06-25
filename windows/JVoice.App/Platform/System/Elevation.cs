using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;

namespace JVoice.App.Platform;

/// Elevation (UAC) helpers. JVoice ships non-elevated (app.manifest `asInvoker`) because it
/// never needs admin for its own work. BUT a non-elevated process's low-level keyboard hook
/// (GlobalHotkey) is, by Windows UIPI design, NOT called while a HIGHER-integrity ("Run as
/// administrator") window has focus — so the hotkey is dead in e.g. an admin terminal, and a
/// non-elevated process also cannot SendInput/paste there (see Paster). The only fix available
/// to an UNSIGNED app — the `uiAccess="true"` bypass needs a signing cert + a Program Files
/// install, both ruled out by the $0/unsigned posture — is to run JVoice itself elevated.
/// These helpers relaunch the app elevated on demand; ElevatedAutostart makes it stick at logon.
public static class Elevation
{
    /// CLI flags carried across an elevated relaunch. All three mean "I am the relaunched copy —
    /// wait for the previous instance's single-instance mutex to release before taking over".
    public const string RelaunchFlag         = "--admin-relaunch";          // one-off elevate, no persistence
    public const string EnableAutostartFlag  = "--enable-admin-autostart";  // elevate + register the logon task
    public const string DisableAutostartFlag = "--disable-admin-autostart"; // elevate just to remove the logon task

    /// Arg the Run-key launch-at-login entry carries, so a logon launch can be told apart from a
    /// manual double-click and "step aside" for the elevated logon task (see App.Main).
    public const string AutostartFlag = "--autostart";

    public enum RelaunchResult { Started, UserCancelled, Failed }

    /// True when the current process token is elevated (full administrator).
    public static bool IsElevated
    {
        get
        {
            try
            {
                using var id = WindowsIdentity.GetCurrent();
                return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }

    /// Did this process get launched as one of the elevated-relaunch copies? (Main then waits
    /// for the outgoing instance to release the single-instance mutex before taking the slot.)
    public static bool IsRelaunch(string[] args) => MatchedFlag(args) is not null;

    /// The relaunch flag this process was started with, if any (drives the follow-up action).
    public static string? MatchedFlag(string[] args)
    {
        foreach (var f in new[] { RelaunchFlag, EnableAutostartFlag, DisableAutostartFlag })
            if (Array.Exists(args, a => string.Equals(a, f, StringComparison.OrdinalIgnoreCase)))
                return f;
        return null;
    }

    /// Relaunch THIS executable elevated (shows the UAC prompt). `flag` is one of the *Flag
    /// constants and is passed to the new instance so it both waits for the singleton handoff and
    /// performs any follow-up (task register/unregister). Returns Started (a new elevated process
    /// was spawned — the caller should now quit so the mutex frees), UserCancelled (UAC declined —
    /// keep running unchanged), or Failed.
    public static RelaunchResult RelaunchElevated(string flag)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = LaunchAtLogin.CurrentExecutablePath,
                UseShellExecute = true, // required for the "runas" verb
                Verb = "runas",         // triggers the UAC elevation prompt
                Arguments = flag,
            };
            using var p = Process.Start(psi);
            return p is not null ? RelaunchResult.Started : RelaunchResult.Failed;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) // ERROR_CANCELLED — user declined UAC
        {
            return RelaunchResult.UserCancelled;
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Couldn't relaunch as administrator. {ex.Message}");
            return RelaunchResult.Failed;
        }
    }
}
