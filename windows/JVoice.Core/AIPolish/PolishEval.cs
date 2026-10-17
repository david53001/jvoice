using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using JVoice.Core.Models;
using JVoice.Core.Text;

namespace JVoice.Core.AIPolish;

/// <summary>One eval case (<c>scripts/ai-polish-eval/cases*.json</c>, shared with the Mac). Checks are
/// case-sensitive substrings on the text the user would get, kept minimal so the model is free in its
/// wording.</summary>
public sealed class PolishEvalCase
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("category")] public string Category { get; set; } = "";
    [JsonPropertyName("previous")] public List<string>? Previous { get; set; }
    [JsonPropertyName("transcript")] public string Transcript { get; set; } = "";
    [JsonPropertyName("mode")] public string? Mode { get; set; }
    [JsonPropertyName("mustContain")] public List<string>? MustContain { get; set; }
    [JsonPropertyName("mustNotContain")] public List<string>? MustNotContain { get; set; }
    /// <summary>A <c>context-fix</c> case whose word is NOT one of the system prompt's examples.</summary>
    [JsonPropertyName("holdout")] public bool? Holdout { get; set; }
    [JsonPropertyName("customWords")] public List<string>? CustomWords { get; set; }
    /// <summary><c>preserve</c>: the output's length must stay within ±this fraction of the transcript's.</summary>
    [JsonPropertyName("lengthTolerance")] public double? LengthTolerance { get; set; }

    public ToneStyle AppMode => AIPolishRequest.ParseMode(Mode);

    public static List<PolishEvalCase> Parse(string json) =>
        JsonSerializer.Deserialize<List<PolishEvalCase>>(json) ?? [];
}

/// <summary>One line of the eval summary.</summary>
public sealed class PolishTally
{
    public int Total { get; private set; }
    /// <summary>Passed, graded on what the app would paste.</summary>
    public int Pass { get; private set; }
    /// <summary>Passed with a real polish pasted — a fallback's local text can pass a case for free.</summary>
    public int PolishedPass { get; private set; }
    /// <summary>The local text alone passes (what doing nothing scores).</summary>
    public int Baseline { get; private set; }
    public int Fallbacks { get; private set; }

    public void Add(bool pass, bool polished, bool baseline)
    {
        Total++;
        if (pass) Pass++;
        if (pass && polished) PolishedPass++;
        if (baseline) Baseline++;
        if (!polished) Fallbacks++;
    }
}

/// <summary>Parsed <c>--polish-eval</c> arguments.</summary>
public sealed record PolishEvalArgs(string CasesPath, AIPolishOptions Options, string? PromptFile, string? OutPath);

/// <summary>
/// The pure half of the eval (port of the Mac's <c>PolishEval</c> + <c>PolishEvalRunner</c>): grading,
/// the summary numbers, argument parsing and the run itself — through the SAME request builder,
/// validator and <see cref="AIPolishClient"/> as the app, with a transport and key supplied by the
/// caller (the real HTTP transport in <c>JVoice.exe --polish-eval</c>, a fake in tests).
/// </summary>
public static class PolishEval
{
    public const string Usage =
        "usage: JVoice.exe --polish-eval <cases.json> [--model claude-haiku-5-5] [--thinking off|low] [--prompt-file <template.txt>] [--out <file.md>]";

    /// <summary>Each call gets 30 s (not the app's 3 s) so real latency is measured; a call past the
    /// app's deadline is graded as the local text.</summary>
    public static readonly TimeSpan EvalDeadline = TimeSpan.FromSeconds(30);

    private static readonly string[] KnownFlags = ["--polish-eval", "--model", "--thinking", "--out", "--prompt-file"];

    /// <summary>Why <paramref name="output"/> fails <paramref name="testCase"/>; empty = PASS.</summary>
    public static List<string> Failures(string output, PolishEvalCase testCase)
    {
        var reasons = new List<string>();
        foreach (var needle in testCase.MustContain ?? [])
            if (!output.Contains(needle, StringComparison.Ordinal)) reasons.Add($"missing “{needle}”");
        foreach (var needle in testCase.MustNotContain ?? [])
            if (output.Contains(needle, StringComparison.Ordinal)) reasons.Add($"contains “{needle}”");
        if (testCase.LengthTolerance is { } tolerance && testCase.Transcript.Length > 0)
        {
            double ratio = (double)AIPolishRequest.Length(output) / AIPolishRequest.Length(testCase.Transcript);
            if (Math.Abs(ratio - 1) > tolerance)
                reasons.Add($"length {(ratio * 100).ToString("0", CultureInfo.InvariantCulture)}% of the transcript");
        }
        return reasons;
    }

    /// <summary>Nearest-rank percentile (p in 0…100) of <paramref name="values"/>; 0 for none.</summary>
    public static int Percentile(IReadOnlyList<int> values, double p)
    {
        if (values.Count == 0) return 0;
        var sorted = values.OrderBy(v => v).ToList();
        int rank = (int)Math.Ceiling(p / 100 * sorted.Count);
        return sorted[Math.Min(Math.Max(rank, 1), sorted.Count) - 1];
    }

    /// <summary>Parses the CLI. Anything not understood is refused (an ignored "--thinking low" once made
    /// three "different" Mac runs the same config). Returns null with <paramref name="error"/> set.</summary>
    public static PolishEvalArgs? ParseArgs(IReadOnlyList<string> args, out string? error)
    {
        error = null;
        int start = -1;
        for (int i = 0; i < args.Count; i++)
            if (args[i] == "--polish-eval") { start = i; break; }
        if (start < 0 || start + 1 >= args.Count || args[start + 1].StartsWith("--", StringComparison.Ordinal))
        {
            error = Usage;
            return null;
        }
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        for (int i = start; i < args.Count; i += 2)
        {
            if (!KnownFlags.Contains(args[i]))
            {
                error = $"unknown argument: {args[i]}\n{Usage}";
                return null;
            }
            if (i + 1 >= args.Count || args[i + 1].StartsWith("--", StringComparison.Ordinal))
            {
                error = $"missing value for {args[i]}\n{Usage}";
                return null;
            }
            if (values.ContainsKey(args[i]))
            {
                error = $"{args[i]} given twice\n{Usage}";
                return null;
            }
            values[args[i]] = args[i + 1];
        }
        // Arguments before --polish-eval are not ours either.
        if (start > 0)
        {
            error = $"unknown argument: {args[0]}\n{Usage}";
            return null;
        }
        var options = AIPolishOptions.Standard;
        if (values.TryGetValue("--model", out var model)) options = options with { Model = model };
        if (values.TryGetValue("--thinking", out var thinking))
        {
            if (thinking == "off") options = options with { Thinking = PolishThinking.Off };
            else if (thinking == "low") options = options with { Thinking = PolishThinking.Low };
            else { error = Usage; return null; }
        }
        if (options.Model.StartsWith("claude-sonnet-5-5", StringComparison.Ordinal) && options.Thinking == PolishThinking.Off)
        {
            error = "claude-sonnet-5-5 rejects disabled thinking (HTTP 400) — run it with --thinking low.";
            return null;
        }
        values.TryGetValue("--prompt-file", out var promptFile);
        values.TryGetValue("--out", out var outPath);
        return new PolishEvalArgs(values["--polish-eval"], options, promptFile, outPath);
    }

    /// <summary>The default report path: <c>docs/ai-polish/eval-results/&lt;date&gt;-windows-&lt;model&gt;-&lt;thinking&gt;.md</c>.</summary>
    public static string DefaultOutPath(AIPolishOptions options, DateTime now) =>
        Path.Combine("docs", "ai-polish", "eval-results",
            $"{now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)}-windows-{options.Model}-{(options.Thinking == PolishThinking.Off ? "off" : "low")}.md");

    /// <summary>Runs every case and returns the Markdown report; each case's lines go to
    /// <paramref name="print"/> as it finishes.</summary>
    public static async Task<string> RunAsync(
        IReadOnlyList<PolishEvalCase> cases, string casesPath, AIPolishOptions options, string key,
        IPolishTransport transport, Action<string> print, TimeSpan? appDeadline = null, DateTime? now = null)
    {
        var deadline = appDeadline ?? AIPolishGate.Timeout;
        var client = new AIPolishClient(transport, EvalDeadline);
        var rows = new List<string>();
        var tallies = new SortedDictionary<string, PolishTally>(StringComparer.Ordinal);
        var holdout = new PolishTally();
        var overall = new PolishTally();
        var latencies = new List<int>();
        int overDeadline = 0, inputTokens = 0, outputTokens = 0;
        int deadlineMs = (int)deadline.TotalMilliseconds;
        string thinkingLabel = options.Thinking == PolishThinking.Off ? "off" : "low";

        print($"AI Polish eval (Windows) — {cases.Count} cases, model {options.Model}, thinking {thinkingLabel}{(options.PromptTemplate is null ? "" : ", prompt from file")}\n");
        foreach (var testCase in cases)
        {
            var mode = testCase.AppMode;
            bool skipped = !AIPolishGate.IsWorthPolishing(testCase.Transcript);
            AIPolishResult result;
            if (!skipped)
            {
                result = await client.PolishAsync(testCase.Transcript, testCase.Previous ?? [], mode,
                    testCase.CustomWords ?? [], () => key, options).ConfigureAwait(false);
                latencies.Add(result.Milliseconds);
                inputTokens += result.Usage?.InputTokens ?? 0;
                outputTokens += result.Usage?.OutputTokens ?? 0;
            }
            else
            {
                result = new AIPolishResult(testCase.Transcript, AIPolishOutcome.Fail(FallbackKind.Empty), 0, null);
            }
            // Grade exactly what the app would paste: past its deadline the local text, else the reply
            // with the tone's formatting re-applied (VoiceCoordinator.FinishTranscriptionAsync).
            bool late = result.Milliseconds > deadlineMs;
            if (late) overDeadline++;
            bool polished = result.IsPolished && !late;
            string pasted = testCase.Transcript;
            if (polished)
            {
                string formatted = TextProcessor.Format(result.Text, mode);
                if (formatted.Length > 0) pasted = formatted; else polished = false;
            }
            var reasons = Failures(pasted, testCase);
            bool ok = reasons.Count == 0;
            bool baseline = Failures(testCase.Transcript, testCase).Count == 0;
            string outcome = skipped ? "skipped(short)" : late ? $"late({result.LogLabel})" : result.LogLabel;

            if (!tallies.TryGetValue(testCase.Category, out var tally)) tallies[testCase.Category] = tally = new PolishTally();
            tally.Add(ok, polished, baseline);
            overall.Add(ok, polished, baseline);
            if (testCase.Holdout == true) holdout.Add(ok, polished, baseline);

            string verdict = ok ? "PASS" : "FAIL";
            string detail = ok ? "" : " — " + string.Join("; ", reasons);
            print($"{verdict} {testCase.Id} [{testCase.Category}] {result.Milliseconds} ms {outcome}{detail}");
            print($"     in:  {testCase.Transcript}");
            print($"     out: {pasted}");
            rows.Add($"| {Cell(testCase.Id)} | {testCase.Category}{(testCase.Holdout == true ? " (hold-out)" : "")} | {verdict} | {result.Milliseconds} | {outcome} | {Cell(testCase.Transcript)} | {Cell(pasted)} | {Cell(string.Join("; ", reasons))} |");
        }

        var summary = new List<string> { "- **" + Line("Overall accuracy", overall) + "**" };
        foreach (var (category, tally) in tallies) summary.Add("- " + Line(category, tally));
        summary.Add("- " + Line("context-fix hold-out (words not in the prompt)", holdout));
        summary.Add($"- **Latency:** p50 {Percentile(latencies, 50)} ms, p95 {Percentile(latencies, 95)} ms, max {(latencies.Count == 0 ? 0 : latencies.Max())} ms; over the app's {deadline.TotalSeconds.ToString("0.#", CultureInfo.InvariantCulture)} s deadline (graded as the local text): {overDeadline}");
        string tokens = $"- Tokens: {inputTokens} in / {outputTokens} out";
        if (AIPolishRequest.PricePerMillion(options.Model) is { } price)
        {
            double cost = inputTokens * price.Input / 1_000_000 + outputTokens * price.Output / 1_000_000;
            tokens += $" — estimated cost ${cost.ToString("0.0000", CultureInfo.InvariantCulture)} (${(cases.Count == 0 ? 0 : cost / cases.Count).ToString("0.000000", CultureInfo.InvariantCulture)} per dictation)";
        }
        summary.Add(tokens);
        print("\n" + string.Join("\n", summary));

        string date = (now ?? DateTime.Now).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var report = new StringBuilder();
        report.Append($"# AI Polish eval (Windows) — {date}, {options.Model}, thinking {thinkingLabel}\n\n");
        report.Append($"Cases: `{casesPath}` ({cases.Count}). Per-call deadline {EvalDeadline.TotalSeconds:0} s (the app uses {deadline.TotalSeconds.ToString("0.#", CultureInfo.InvariantCulture)} s).{(options.PromptTemplate is null ? "" : " System prompt from `--prompt-file`.")}\n\n");
        report.Append("## Summary\n\n");
        report.Append(string.Join("\n", summary)).Append("\n\n");
        report.Append("## Cases\n\n");
        report.Append("| id | category | verdict | ms | outcome | transcript | output | why |\n");
        report.Append("|---|---|---|---|---|---|---|---|\n");
        report.Append(string.Join("\n", rows)).Append('\n');
        return report.ToString();
    }

    private static string Percent(int a, int b) =>
        b == 0 ? "—" : $"{(100.0 * a / b).ToString("0.0", CultureInfo.InvariantCulture)}% ({a}/{b})";

    private static string Line(string name, PolishTally t) =>
        $"{name}: {Percent(t.Pass, t.Total)} — by a real polish {Percent(t.PolishedPass, t.Total)}; do-nothing baseline {Percent(t.Baseline, t.Total)}; fallbacks {t.Fallbacks}";

    /// <summary>A Markdown table cell: pipes escaped, newlines flattened.</summary>
    private static string Cell(string text) => text.Replace("|", "\\|", StringComparison.Ordinal).Replace("\n", " ", StringComparison.Ordinal);
}
