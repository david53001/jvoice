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

/// One line of the eval summary.
struct Tally: Equatable, Sendable {
    var total = 0
    /// Passed, graded on what the app would paste.
    var pass = 0
    /// Passed with a real polish pasted — a fallback's local text can pass a case for free.
    var polishedPass = 0
    /// The local text alone passes (what doing nothing scores).
    var baseline = 0
    var fallbacks = 0

    mutating func add(pass ok: Bool, polished: Bool, baseline local: Bool) {
        total += 1
        if ok { pass += 1 }
        if ok && polished { polishedPass += 1 }
        if local { baseline += 1 }
        if !polished { fallbacks += 1 }
    }
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

}

/// Hidden dev mode: `JVoice --polish-eval <cases.json> [--model claude-haiku-5-5] [--thinking off|low]
/// [--out <file.md>]` — runs every case against the REAL API through the app's own
/// `AIPolishRequest` builder/parser and `AIPolishClient`, then prints per-case PASS/FAIL, accuracy
/// overall + per category, p50/p95 latency, tokens and cost, and writes the same report to
/// `docs/ai-polish/eval-results/<date>-<model>-<thinking>.md`.
///
/// The key comes from `ANTHROPIC_API_KEY`, else the saved key file (`APIKeyStore`); it is never printed. Each call
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
        let usage = "usage: JVoice --polish-eval <cases.json> [--model claude-haiku-5-5] [--thinking off|low] [--prompt-file <template.txt>] [--out <file.md>]"
        guard let path = value(after: "--polish-eval", in: arguments), !path.hasPrefix("--") else {
            return fail(usage, code: 64)
        }
        // Anything not understood is refused: an ignored "--thinking low" (zsh passes an unsplit
        // "$args" as ONE word) once made three "different" runs the same config.
        let known: Set<String> = ["--polish-eval", "--model", "--thinking", "--out", "--prompt-file"]
        var index = arguments.firstIndex(of: "--polish-eval") ?? 0
        while index < arguments.count {
            guard known.contains(arguments[index]) else { return fail("unknown argument: \(arguments[index])\n" + usage, code: 64) }
            index += 2
        }
        var options = AIPolishRequest.Options.standard
        if let model = value(after: "--model", in: arguments) { options.model = model }
        if let thinking = value(after: "--thinking", in: arguments) {
            guard let parsed = AIPolishRequest.Thinking(rawValue: thinking) else { return fail(usage, code: 64) }
            options.thinking = parsed
        }
        if let promptPath = value(after: "--prompt-file", in: arguments) {
            guard let template = try? String(contentsOfFile: promptPath, encoding: .utf8), !template.isEmpty else {
                return fail("can't read the prompt file \(promptPath)", code: 66)
            }
            options.promptTemplate = template
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
        /// Per category: graded passes (what the app would paste), passes by a REAL polish (a
        /// fallback's local text can pass a case for free), the do-nothing baseline, fallbacks.
        var tallies: [String: Tally] = [:]
        var holdout = Tally()
        var overall = Tally()
        var latencies: [Int] = []
        var overDeadline = 0
        var inputTokens = 0
        var outputTokens = 0
        let deadlineMs = Int(AppTimings.aiPolishTimeout * 1000)

        print("AI Polish eval — \(cases.count) cases, model \(options.model), thinking \(options.thinking.rawValue)\(options.promptTemplate == nil ? "" : ", prompt from file")\n")
        for testCase in cases {
            let mode = testCase.appMode
            let result: AIPolishResult
            let skipped = !AIPolish.isWorthPolishing(testCase.transcript)
            if !skipped {
                result = await client.polish(testCase.transcript, previous: testCase.previous ?? [],
                                             mode: mode, vocabulary: testCase.customWords ?? [],
                                             options: options, apiKey: { key })
                latencies.append(result.milliseconds)
                inputTokens += result.usage?.inputTokens ?? 0
                outputTokens += result.usage?.outputTokens ?? 0
            } else {
                result = AIPolishResult(text: testCase.transcript, outcome: .fallback(.empty), milliseconds: 0, usage: nil)
            }
            // Grade exactly what the app would paste: past its deadline the local text, else the
            // reply with the tone's formatting re-applied (VoiceCoordinator.finishTranscription).
            let late = result.milliseconds > deadlineMs
            if late { overDeadline += 1 }
            let polished = result.isPolished && !late
            let pasted = polished ? TextProcessor.format(result.text, mode: mode) : testCase.transcript
            let reasons = PolishEval.failures(of: pasted, for: testCase)
            let ok = reasons.isEmpty
            let baseline = PolishEval.failures(of: testCase.transcript, for: testCase).isEmpty
            let outcome = skipped ? "skipped(short)" : late ? "late(\(result.logLabel))" : result.logLabel

            tallies[testCase.category, default: Tally()].add(pass: ok, polished: polished, baseline: baseline)
            overall.add(pass: ok, polished: polished, baseline: baseline)
            if testCase.holdout == true { holdout.add(pass: ok, polished: polished, baseline: baseline) }

            let verdict = ok ? "PASS" : "FAIL"
            let detail = ok ? "" : " — " + reasons.joined(separator: "; ")
            print("\(verdict) \(testCase.id) [\(testCase.category)] \(result.milliseconds) ms \(outcome)\(detail)")
            print("     in:  \(testCase.transcript)")
            print("     out: \(pasted)")
            rows.append("| \(cell(testCase.id)) | \(testCase.category)\(testCase.holdout == true ? " (hold-out)" : "") | \(verdict) | \(result.milliseconds) | \(outcome) | \(cell(testCase.transcript)) | \(cell(pasted)) | \(cell(reasons.joined(separator: "; "))) |")
        }

        func percent(_ a: Int, _ b: Int) -> String { b == 0 ? "—" : String(format: "%.1f%% (%d/%d)", 100 * Double(a) / Double(b), a, b) }
        func line(_ name: String, _ t: Tally) -> String {
            "\(name): \(percent(t.pass, t.total)) — by a real polish \(percent(t.polishedPass, t.total)); do-nothing baseline \(percent(t.baseline, t.total)); fallbacks \(t.fallbacks)"
        }
        var summary: [String] = []
        summary.append("- **" + line("Overall accuracy", overall) + "**")
        for category in tallies.keys.sorted() {
            summary.append("- " + line(category, tallies[category]!))
        }
        summary.append("- " + line("context-fix hold-out (words not in the prompt)", holdout))
        summary.append("- **Latency:** p50 \(PolishEval.percentile(latencies, 50)) ms, p95 \(PolishEval.percentile(latencies, 95)) ms, max \(latencies.max() ?? 0) ms; over the app's \(Int(AppTimings.aiPolishTimeout)) s deadline (graded as the local text): \(overDeadline)")
        var tokens = "- Tokens: \(inputTokens) in / \(outputTokens) out"
        if let price = AIPolishRequest.pricePerMillion(model: options.model) {
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
