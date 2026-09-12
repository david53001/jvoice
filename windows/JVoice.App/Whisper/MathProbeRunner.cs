using System;
using System.IO;
using System.Linq;
using System.Text;
using JVoice.Core.Text;

namespace JVoice.App.Whisper;

/// Hidden developer CLI for the spoken-mathematics converter:
///
///     JVoice --math-probe "a subscript n equals 1 plus 7n"
///     type transcripts.txt | JVoice --math-probe
///
/// Runs <see cref="MathSpeech.Convert"/> over one argument, or — with no text given — over
/// every line of standard input, so a whole file of real transcripts can be swept for
/// false positives in one pass. One compact, greppable line per input:
///
///     CHANGED | &lt;before&gt; | &lt;after&gt;
///     same | &lt;text&gt;
///
/// Output goes to the console AND to a fixed temp file (mirrors GameProbeRunner): JVoice is
/// a WinExe, so stdout is only visible when the caller redirects it.
///
/// Runs BEFORE any WPF startup (see App.Main). Touches nothing but the pure converter —
/// no settings, no mic, no whisper, no window.
internal static class MathProbeRunner
{
    private const string LogFileName = "jvoice-mathprobe.log";

    /// True when <paramref name="args"/> contains "--math-probe".
    public static bool ShouldRun(string[] args) =>
        Array.Exists(args, a => string.Equals(a, "--math-probe", StringComparison.OrdinalIgnoreCase));

    /// Converts the given text (or stdin) and returns 0; 1 only if the run itself failed.
    public static int RunAndExit(string[] args)
    {
        // ₙ / ² / √ are the whole point of this probe, so don't let the console codepage eat them.
        try { Console.OutputEncoding = Encoding.UTF8; } catch { /* non-fatal */ }

        string logPath = Path.Combine(Path.GetTempPath(), LogFileName);
        try { File.WriteAllText(logPath, string.Empty); }
        catch { /* non-fatal — console output still works */ }

        // Everything after the flag that isn't itself a flag is the text to convert, joined with a
        // single space so an unquoted phrase works too. Nothing after it => read stdin.
        int idx = Array.FindIndex(args,
            a => string.Equals(a, "--math-probe", StringComparison.OrdinalIgnoreCase));
        string inline = string.Join(" ", args.Skip(idx + 1).TakeWhile(a => !a.StartsWith("--", StringComparison.Ordinal)));

        try
        {
            if (!string.IsNullOrWhiteSpace(inline))
            {
                Emit(logPath, inline);
                return 0;
            }

            Report(logPath, $"JVoice --math-probe: reading lines from stdin (also logging to {logPath}).");
            int total = 0, changed = 0;
            string? line;
            while ((line = Console.In.ReadLine()) is not null)
            {
                if (line.Length == 0) continue;
                total++;
                if (Emit(logPath, line)) changed++;
            }
            Report(logPath, $"# {total} line(s), {changed} changed.");
            return 0;
        }
        catch (Exception ex)
        {
            string fatal = $"--math-probe fatal error: {ex.Message}";
            Console.Error.WriteLine(fatal);
            try { AppendToLog(logPath, fatal); } catch { }
            return 1;
        }
    }

    /// Converts one line and prints its verdict. Returns true when the text changed.
    private static bool Emit(string logPath, string text)
    {
        string after = MathSpeech.Convert(text);
        bool changed = !string.Equals(text, after, StringComparison.Ordinal);
        Report(logPath, changed ? $"CHANGED | {text} | {after}" : $"same | {text}");
        return changed;
    }

    private static void Report(string logPath, string line)
    {
        Console.WriteLine(line);
        AppendToLog(logPath, line);
    }

    private static void AppendToLog(string path, string text)
    {
        try { File.AppendAllText(path, text + Environment.NewLine); } catch { }
    }
}
