using System;
using System.IO;
using System.Threading;

namespace JVoice.App.Platform;

/// Hidden developer CLI for live game-detection diagnostics:
///
///     JVoice --game-probe [seconds]
///
/// Loops once per second, printing each foreground-window snapshot to the console
/// AND to a fixed temp-file so the developer can alt-tab into a real game and read
/// the results without keeping a terminal focused (WinExe stdout is only visible
/// when the caller redirects it).
///
/// Runs BEFORE any WPF startup (see App.Main). Does NOT call GameDetector.Start()
/// — Inspect() reads the live foreground directly each iteration without requiring
/// the DispatcherTimer or foreground-change subscription.
internal static class GameProbeRunner
{
    private const string LogFileName = "jvoice-gameprobe.log";

    /// True when <paramref name="args"/> contains "--game-probe".
    public static bool ShouldRun(string[] args) =>
        Array.Exists(args, a => string.Equals(a, "--game-probe", StringComparison.OrdinalIgnoreCase));

    /// Runs the probe loop and returns 0 on normal completion.
    public static int RunAndExit(string[] args)
    {
        // Optional duration: the token immediately after --game-probe, if it parses as int.
        int durationSeconds = 60;
        int idx = Array.FindIndex(args,
            a => string.Equals(a, "--game-probe", StringComparison.OrdinalIgnoreCase));
        if (idx >= 0 && idx + 1 < args.Length &&
            int.TryParse(args[idx + 1], out int parsed) && parsed > 0)
        {
            durationSeconds = parsed;
        }

        string logPath = Path.Combine(Path.GetTempPath(), LogFileName);

        // Truncate (or create) the log file before the first snapshot.
        try { File.WriteAllText(logPath, string.Empty); }
        catch { /* non-fatal — console output still works */ }

        string header = $"JVoice --game-probe: writing snapshots to {logPath} for {durationSeconds}s. Alt-tab into a game; read that file.";
        Console.WriteLine(header);
        WriteToLog(logPath, header);

        try
        {
            var detector = new GameDetector(new ForegroundWindowTracker());

            var deadline = DateTime.UtcNow.AddSeconds(durationSeconds);
            while (DateTime.UtcNow < deadline)
            {
                try
                {
                    var result = detector.Inspect();
                    string snapshot = $"{DateTime.Now:HH:mm:ss}\n{result}\n";
                    Console.WriteLine(snapshot);
                    AppendToLog(logPath, snapshot);
                }
                catch (Exception ex)
                {
                    string err = $"{DateTime.Now:HH:mm:ss} <Inspect error: {ex.Message}>\n";
                    Console.Error.WriteLine(err);
                    AppendToLog(logPath, err);
                }

                Thread.Sleep(1000);
            }

            string done = $"--game-probe complete ({durationSeconds}s).";
            Console.WriteLine(done);
            AppendToLog(logPath, done);
        }
        catch (Exception ex)
        {
            string fatal = $"--game-probe fatal error: {ex.Message}";
            Console.Error.WriteLine(fatal);
            try { AppendToLog(logPath, fatal); } catch { }
        }

        return 0;
    }

    private static void WriteToLog(string path, string text)
    {
        try { File.WriteAllText(path, text + "\n"); } catch { }
    }

    private static void AppendToLog(string path, string text)
    {
        try { File.AppendAllText(path, text + "\n"); } catch { }
    }
}
