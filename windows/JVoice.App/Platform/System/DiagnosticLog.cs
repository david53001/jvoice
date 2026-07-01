using System.IO;
using System.Text;

namespace JVoice.App.Platform;

/// TEMPORARY diagnostic logger for tracing the "Something went wrong on every
/// dictation" report (2026-06-23). Writes timestamped lines to
/// %APPDATA%\JVoice\diagnostic.log so a single live reproduction reveals exactly
/// which coordinator/recording path fails (the HUD shows only the generic
/// "Something Went Wrong" headline and hides the real message by design).
///
/// Remove this file and its call sites once the root cause is fixed.
public static class DiagnosticLog
{
    private static readonly object Gate = new();

    private static string LogPath =>
        Path.Combine(PlatformPaths.AppDataDirectory, "diagnostic.log");

    public static void Write(string message)
    {
        try
        {
            // [pid/tid] prefix: interleaved instances (e.g. an elevated relaunch beside the
            // outgoing copy) and cross-thread flows are untangleable without it — the 2026-06-26
            // "elevated freeze" hunt had to guess which PID wrote which line.
            string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  [{Environment.ProcessId}/{Environment.CurrentManagedThreadId}]  {message}{Environment.NewLine}";
            lock (Gate) File.AppendAllText(LogPath, line, Encoding.UTF8);
        }
        catch { /* diagnostics must never break the app */ }
    }
}
