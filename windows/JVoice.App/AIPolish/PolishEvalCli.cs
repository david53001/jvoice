using System.IO;
using System.Text;
using JVoice.Core.AIPolish;

namespace JVoice.App.AIPolish;

/// <summary>
/// Hidden dev mode: <c>JVoice.exe --polish-eval &lt;cases.json&gt; [--model claude-haiku-5-5] [--thinking off|low]
/// [--prompt-file &lt;template.txt&gt;] [--out &lt;file.md&gt;]</c> — runs every case against the REAL API through
/// the app's own request builder, validator and <see cref="AIPolishClient"/> (<see cref="PolishEval.RunAsync"/>),
/// prints per-case PASS/FAIL + the summary, and writes the Markdown report (default
/// <c>docs/ai-polish/eval-results/&lt;date&gt;-windows-&lt;model&gt;-&lt;thinking&gt;.md</c>, relative to the current folder).
///
/// JVoice.exe is a GUI-subsystem app, so pipe it to see the output and make PowerShell wait:
/// <c>.\JVoice.exe --polish-eval … | Out-Host</c>. The key comes from <c>ANTHROPIC_API_KEY</c>, else the
/// key saved in Settings (DPAPI); it is never printed. Unknown arguments are refused. Exit codes: 0 ok,
/// 64 usage, 66 unreadable input, 73 report not written, 77 no key.
/// </summary>
internal static class PolishEvalCli
{
    public static bool ShouldRun(string[] args) => Array.Exists(args, a => a == "--polish-eval");

    public static int RunAndExit(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { /* non-fatal */ }
        try
        {
            return RunAsync(args).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"polish-eval failed: {ex.GetType().Name}: {ex.Message}");
            return 1;
        }
    }

    private static async Task<int> RunAsync(string[] args)
    {
        if (PolishEval.ParseArgs(args, out var error) is not { } parsed)
        {
            Console.Error.WriteLine(error);
            return 64;
        }
        var options = parsed.Options;
        if (parsed.PromptFile is { } promptPath)
        {
            string template;
            try { template = File.ReadAllText(promptPath); }
            catch (Exception) { Console.Error.WriteLine($"can't read the prompt file {promptPath}"); return 66; }
            if (template.Length == 0) { Console.Error.WriteLine($"the prompt file {promptPath} is empty"); return 66; }
            options = options with { PromptTemplate = template };
        }

        List<PolishEvalCase> cases;
        try { cases = PolishEvalCase.Parse(File.ReadAllText(parsed.CasesPath)); }
        catch (Exception ex) { Console.Error.WriteLine($"can't read {parsed.CasesPath}: {ex.Message}"); return 66; }

        string? key = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY")?.Trim();
        if (string.IsNullOrEmpty(key)) key = DpapiKeyProtector.CreateStore().Read();
        if (string.IsNullOrEmpty(key))
        {
            Console.Error.WriteLine("No API key: set ANTHROPIC_API_KEY (Read-Host -AsSecureString, never typed inline) or save one in JVoice Settings → AI Polish.");
            return 77;
        }

        string report = await PolishEval.RunAsync(cases, parsed.CasesPath, options, key, HttpPolishTransport.Shared,
            line => Console.WriteLine(line));

        string outPath = parsed.OutPath ?? PolishEval.DefaultOutPath(options, DateTime.Now);
        try
        {
            string full = Path.GetFullPath(outPath);
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, report, new UTF8Encoding(false));
            Console.WriteLine($"\nwrote {full}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"couldn't write {outPath}: {ex.Message}");
            return 73;
        }
        return 0;
    }
}
