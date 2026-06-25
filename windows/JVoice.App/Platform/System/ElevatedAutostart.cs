using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;

namespace JVoice.App.Platform;

/// Registers a Task Scheduler logon task that starts JVoice with HIGHEST privileges at every
/// logon — WITHOUT a per-boot UAC prompt (the elevation is authorized once, when the task is
/// created). This is the standard, and the only seamless, way for an UNSIGNED app to auto-start
/// elevated; the HKCU Run key (LaunchAtLogin) cannot elevate. Why elevated at all: a non-elevated
/// process's global keyboard hook never fires while an elevated window has focus (UIPI) — see
/// Elevation. Creating/removing a HIGHEST task requires admin, so callers must already be elevated
/// (the enable/disable flow relaunches elevated first — see VoiceCoordinator). All operations shell
/// out to the built-in schtasks.exe (no extra dependency vs. the Task Scheduler COM API).
public static class ElevatedAutostart
{
    /// Task name (root folder). Distinct, stable; mirrors the Run-key value name "JVoice".
    public const string TaskName = "JVoice Elevated Autostart";

    /// True when the logon task is registered. `schtasks /query` exits 0 iff the task exists.
    public static bool IsEnabled
    {
        get
        {
            try { return RunSchtasks($"/query /tn \"{TaskName}\"", out _, out _) == 0; }
            catch { return false; }
        }
    }

    /// Create (or overwrite) the elevated logon task. MUST be called from an elevated process
    /// (registering a HIGHEST-privilege task is itself a privileged operation). Returns true on
    /// success; on failure `error` carries schtasks' message.
    public static bool Enable(out string? error)
    {
        error = null;
        string xmlPath = Path.Combine(Path.GetTempPath(), "jvoice-autostart.xml");
        try
        {
            // schtasks /xml expects UTF-16 (matches the <?xml encoding="UTF-16"?> declaration).
            File.WriteAllText(xmlPath, BuildTaskXml(), Encoding.Unicode);
            int code = RunSchtasks($"/create /tn \"{TaskName}\" /xml \"{xmlPath}\" /f", out _, out string err);
            if (code == 0) return true;
            error = string.IsNullOrWhiteSpace(err) ? $"schtasks exited {code}" : err.Trim();
            return false;
        }
        catch (Exception ex) { error = ex.Message; return false; }
        finally { try { File.Delete(xmlPath); } catch { /* best-effort */ } }
    }

    /// Remove the elevated logon task. Returns true if it is gone afterward (including the
    /// already-absent case). Deleting a HIGHEST task may itself require elevation; on access
    /// failure `error` is set and the caller can retry elevated.
    public static bool Disable(out string? error)
    {
        error = null;
        try
        {
            if (!IsEnabled) return true;
            int code = RunSchtasks($"/delete /tn \"{TaskName}\" /f", out _, out string err);
            if (code == 0) return true;
            error = string.IsNullOrWhiteSpace(err) ? $"schtasks exited {code}" : err.Trim();
            return false;
        }
        catch (Exception ex) { error = ex.Message; return false; }
    }

    /// Build the Task XML by hand (array-joined lines — no raw-string-literal indentation traps).
    /// Bare exe path in &lt;Command&gt; (Task Scheduler resolves spaces itself; quoting it breaks
    /// resolution). LogonType InteractiveToken so it runs in the user's interactive session (the
    /// tray/HUD need a desktop). RunLevel HighestAvailable = elevated.
    private static string BuildTaskXml()
    {
        string u = Escape(WindowsIdentity.GetCurrent().Name); // MACHINE\User (elevation doesn't change the user)
        string c = Escape(LaunchAtLogin.CurrentExecutablePath);
        return string.Join("\r\n",
            "<?xml version=\"1.0\" encoding=\"UTF-16\"?>",
            "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">",
            "  <RegistrationInfo>",
            "    <Description>Starts JVoice with administrator rights at logon so voice dictation works in elevated apps (admin terminals, etc.).</Description>",
            "  </RegistrationInfo>",
            "  <Triggers>",
            "    <LogonTrigger>",
            "      <Enabled>true</Enabled>",
            $"      <UserId>{u}</UserId>",
            "    </LogonTrigger>",
            "  </Triggers>",
            "  <Principals>",
            "    <Principal id=\"Author\">",
            $"      <UserId>{u}</UserId>",
            "      <LogonType>InteractiveToken</LogonType>",
            "      <RunLevel>HighestAvailable</RunLevel>",
            "    </Principal>",
            "  </Principals>",
            "  <Settings>",
            "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>",
            "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>",
            "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>",
            "    <AllowHardTerminate>false</AllowHardTerminate>",
            "    <StartWhenAvailable>true</StartWhenAvailable>",
            "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>",
            "    <IdleSettings>",
            "      <StopOnIdleEnd>false</StopOnIdleEnd>",
            "      <RestartOnIdle>false</RestartOnIdle>",
            "    </IdleSettings>",
            "    <AllowStartOnDemand>true</AllowStartOnDemand>",
            "    <Enabled>true</Enabled>",
            "    <Hidden>false</Hidden>",
            "    <RunOnlyIfIdle>false</RunOnlyIfIdle>",
            "    <WakeToRun>false</WakeToRun>",
            "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>",
            "    <Priority>7</Priority>",
            "  </Settings>",
            "  <Actions Context=\"Author\">",
            "    <Exec>",
            $"      <Command>{c}</Command>",
            "    </Exec>",
            "  </Actions>",
            "</Task>");
    }

    private static string Escape(string s) =>
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    private static int RunSchtasks(string args, out string stdout, out string stderr)
    {
        using var p = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = args,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            },
        };
        p.Start();
        stdout = p.StandardOutput.ReadToEnd();
        stderr = p.StandardError.ReadToEnd();
        p.WaitForExit();
        return p.ExitCode;
    }
}
