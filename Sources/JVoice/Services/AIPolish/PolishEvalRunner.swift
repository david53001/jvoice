import Foundation

/// One eval case (`scripts/ai-polish-eval/cases.json`). Checks are case-sensitive substrings on the
/// text the user would get, kept minimal so the model is free in its wording.
struct PolishEvalCase: Decodable, Sendable {
    var id: String
    var category: String
    var previous: [String]?
    var transcript: String
    var mode: String?
    var mustContain: [String]?
    var mustNotContain: [String]?
    /// A `context-fix` case whose word is NOT one of the system prompt's examples.
    var holdout: Bool?
    var customWords: [String]?
    /// `preserve`: the output's length must stay within ±this fraction of the transcript's.
    var lengthTolerance: Double?

    var appMode: AppMode { mode.flatMap(AppMode.init(rawValue:)) ?? .casual }
}

/// The pure half of the eval: grading and the summary numbers (unit-tested; no network).
enum PolishEval {
    /// Why `output` fails `testCase`; empty = PASS.
    static func failures(of output: String, for testCase: PolishEvalCase) -> [String] {
        var reasons: [String] = []
        for needle in testCase.mustContain ?? [] where !output.contains(needle) {
            reasons.append("missing “\(needle)”")
        }
        for needle in testCase.mustNotContain ?? [] where output.contains(needle) {
            reasons.append("contains “\(needle)”")
        }
        if let tolerance = testCase.lengthTolerance, !testCase.transcript.isEmpty {
            let ratio = Double(output.count) / Double(testCase.transcript.count)
            if abs(ratio - 1) > tolerance {
                reasons.append(String(format: "length %.0f%% of the transcript", ratio * 100))
            }
        }
        return reasons
    }

    /// Nearest-rank percentile (p in 0…100) of `values`; 0 for none.
    static func percentile(_ values: [Int], _ p: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    /// USD per million input / output tokens, for the models the eval compares.
    static func pricePerMillion(model: String) -> (input: Double, output: Double)? {
        switch model {
        case "claude-haiku-5-5": return (0.10, 0.50)
        case "claude-sonnet-5-5": return (2.00, 10.00)
        default: return nil
        }
    }
}

/// Hidden dev mode: `JVoice --polish-eval <cases.json> [--model claude-haiku-5-5] [--thinking off|low]
/// [--out <file.md>]` — runs every case against the REAL API through the app's own
/// `AIPolishRequest` builder/parser and `AIPolishClient`, then prints per-case PASS/FAIL, accuracy
/// overall + per category, p50/p95 latency, tokens and cost, and writes the same report to
/// `docs/ai-polish/eval-results/<date>-<model>-<thinking>.md`.
///
/// The key comes from `ANTHROPIC_API_KEY`, else the Keychain item; it is never printed. Each call
/// gets a 30 s deadline (not the app's 3 s) so the real latency is measured; the report counts how
/// many calls the app would have abandoned.
enum PolishEvalRunner {
    static let evalDeadline: TimeInterval = 30

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--polish-eval")
    }

    static func runAndExit(arguments: [String]) -> Never {
        var exitCode: Int32 = 0
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            exitCode = await run(arguments: arguments)
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func fail(_ message: String, code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return code
    }

    private static func run(arguments: [String]) async -> Int32 {
        let usage = "usage: JVoice --polish-eval <cases.json> [--model claude-haiku-5-5] [--thinking off|low] [--out <file.md>]"
        guard let path = value(after: "--polish-eval", in: arguments), !path.hasPrefix("--") else {
            return fail(usage, code: 64)
        }
        var options = AIPolishRequest.Options.standard
        if let model = value(after: "--model", in: arguments) { options.model = model }
        if let thinking = value(after: "--thinking", in: arguments) {
            guard let parsed = AIPolishRequest.Thinking(rawValue: thinking) else { return fail(usage, code: 64) }
            options.thinking = parsed
        }
        if options.model.hasPrefix("claude-sonnet-5-5"), options.thinking == .off {
            return fail("claude-sonnet-5-5 rejects disabled thinking (HTTP 400) — run it with --thinking low.", code: 64)
        }

        let cases: [PolishEvalCase]
        do {
            cases = try JSONDecoder().decode([PolishEvalCase].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            return fail("can't read \(path): \(error)", code: 66)
        }

        let environmentKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = (environmentKey?.isEmpty == false ? environmentKey : nil) ?? APIKeyStore.read() else {
            return fail("No API key: export ANTHROPIC_API_KEY (read -s, never inline) or save one in JVoice Settings → AI Polish.", code: 77)
        }

        let client = AIPolishClient(transport: EphemeralTransport.shared, deadline: evalDeadline)
        var rows: [String] = []
        var passed: [String: (pass: Int, total: Int)] = [:]
        var holdout = (pass: 0, total: 0)
        var fallbacks = 0
        var latencies: [Int] = []
        var overDeadline = 0
        var inputTokens = 0
        var outputTokens = 0

        print("AI Polish eval — \(cases.count) cases, model \(options.model), thinking \(options.thinking.rawValue)\n")
        for testCase in cases {
            let result = await client.polish(testCase.transcript, previous: testCase.previous ?? [],
                                             mode: testCase.appMode, vocabulary: testCase.customWords ?? [],
                                             options: options, apiKey: { key })
            let reasons = PolishEval.failures(of: result.text, for: testCase)
            let ok = reasons.isEmpty
            var tally = passed[testCase.category] ?? (pass: 0, total: 0)
            tally.total += 1
            if ok { tally.pass += 1 }
            passed[testCase.category] = tally
            if testCase.holdout == true {
                holdout.total += 1
                if ok { holdout.pass += 1 }
            }
            if !result.isPolished { fallbacks += 1 }
            latencies.append(result.milliseconds)
            if Double(result.milliseconds) > AppTimings.aiPolishTimeout * 1000 { overDeadline += 1 }
            inputTokens += result.usage?.inputTokens ?? 0
            outputTokens += result.usage?.outputTokens ?? 0

            let verdict = ok ? "PASS" : "FAIL"
            let detail = ok ? "" : " — " + reasons.joined(separator: "; ")
            print("\(verdict) \(testCase.id) [\(testCase.category)] \(result.milliseconds) ms \(result.logLabel)\(detail)")
            print("     in:  \(testCase.transcript)")
            print("     out: \(result.text)")
            rows.append("| \(cell(testCase.id)) | \(testCase.category)\(testCase.holdout == true ? " (hold-out)" : "") | \(verdict) | \(result.milliseconds) | \(result.logLabel) | \(cell(testCase.transcript)) | \(cell(result.text)) | \(cell(reasons.joined(separator: "; "))) |")
        }

        let total = passed.values.reduce(0) { $0 + $1.total }
        let pass = passed.values.reduce(0) { $0 + $1.pass }
        func percent(_ a: Int, _ b: Int) -> String { b == 0 ? "—" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b) }
        var summary: [String] = []
        summary.append("- **Overall accuracy:** \(percent(pass, total))")
        for category in passed.keys.sorted() {
            let t = passed[category]!
            summary.append("- \(category): \(percent(t.pass, t.total))")
        }
        summary.append("- context-fix hold-out (words not in the prompt): \(percent(holdout.pass, holdout.total))")
        summary.append("- Fallbacks (local text returned): \(fallbacks) of \(cases.count)")
        summary.append("- **Latency:** p50 \(PolishEval.percentile(latencies, 50)) ms, p95 \(PolishEval.percentile(latencies, 95)) ms, max \(latencies.max() ?? 0) ms; over the app's \(Int(AppTimings.aiPolishTimeout)) s deadline: \(overDeadline)")
        var tokens = "- Tokens: \(inputTokens) in / \(outputTokens) out"
        if let price = PolishEval.pricePerMillion(model: options.model) {
            let cost = Double(inputTokens) * price.input / 1_000_000 + Double(outputTokens) * price.output / 1_000_000
            tokens += String(format: " — estimated cost $%.4f ($%.6f per dictation)", cost, cases.isEmpty ? 0 : cost / Double(cases.count))
        }
        summary.append(tokens)

        print("\n" + summary.joined(separator: "\n"))

        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let outPath = value(after: "--out", in: arguments)
            ?? "docs/ai-polish/eval-results/\(date)-\(options.model)-\(options.thinking.rawValue).md"
        let report = """
        # AI Polish eval — \(date), \(options.model), thinking \(options.thinking.rawValue)

        Cases: `\(path)` (\(cases.count)). Per-call deadline \(Int(evalDeadline)) s (the app uses \(Int(AppTimings.aiPolishTimeout)) s).

        ## Summary

        \(summary.joined(separator: "\n"))

        ## Cases

        | id | category | verdict | ms | outcome | transcript | output | why |
        |---|---|---|---|---|---|---|---|
        \(rows.joined(separator: "\n"))

        """
        let outURL = URL(fileURLWithPath: outPath)
        do {
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.write(to: outURL, atomically: true, encoding: .utf8)
            print("\nwrote \(outPath)")
        } catch {
            return fail("couldn't write \(outPath): \(error)", code: 73)
        }
        return 0
    }

    /// A Markdown table cell: pipes escaped, newlines flattened.
    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
