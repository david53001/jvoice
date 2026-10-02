using System.IO;
using JVoice.Core.Diagnostics;

namespace JVoice.App.Platform;

/// The diagnostic log, %APPDATA%\JVoice\diagnostic.log: timestamped lines that let one live reproduction show which
/// coordinator/recording path failed (the HUD shows only a generic headline by design). Started as a temporary
/// tracer (2026-06-23) and kept, so since review round 3 #1 it is held to the privacy bar:
/// - dictated text is logged as its length only (<see cref="Text"/>); set JVOICE_LOG_TEXT=1 to log the words
///   (David's maths calibration sweeps read them);
/// - capped at 1 MB with one rolled copy (<see cref="RollingLog"/>);
/// - written by a pool thread, never the caller's (the UI thread logs from inside UpdateHud);
/// - deleted by Recent Transcripts "Clear all" and Restore Defaults (<see cref="Clear"/>).
public static class DiagnosticLog
{
    public const string KeepTextVariable = "JVOICE_LOG_TEXT";

    private static readonly Lazy<RollingLog> Log = new(() =>
    {
        var log = new RollingLog(PlatformPaths.AppDataDirectory);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => log.Flush(); // the last lines before a quit
        return log;
    });

    private static bool KeepsText =>
        Environment.GetEnvironmentVariable(KeepTextVariable) is { Length: > 0 } value && value != "0";

    /// Dictated text as it may appear in the log: "&lt;N chars&gt;", or the quoted words when JVOICE_LOG_TEXT is set.
    public static string Text(string? text) => RollingLog.Redact(text, KeepsText);

    public static void Write(string message)
    {
        try
        {
            // [pid/tid] prefix: interleaved instances (e.g. an elevated relaunch beside the
            // outgoing copy) and cross-thread flows are untangleable without it — the 2026-06-26
            // "elevated freeze" hunt had to guess which PID wrote which line.
            Log.Value.Enqueue($"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  [{Environment.ProcessId}/{Environment.CurrentManagedThreadId}]  {message}{Environment.NewLine}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* no profile folder: no log */ }
    }

    /// Deletes the log and its rolled copies — part of clearing the user's transcripts.
    public static void Clear()
    {
        try { Log.Value.Clear(); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
