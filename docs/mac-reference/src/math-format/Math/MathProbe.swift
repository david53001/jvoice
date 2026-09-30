import Foundation

/// Hidden dev mode: `JVoice --math-probe "<text>"`, or piped stdin (one line per
/// dictation). Prints `CHANGED|before|after` for a line the mathematics engine rewrote
/// and `same|text` for one it left alone, then exits 0.
///
/// This is the tool the no-bleed guarantee is measured with: feeding a corpus of real
/// dictations through it is how the Windows port found its one false positive (a spoken
/// *sign* activating — "between 60 and negative 50") out of 1,174 transcripts.
/// Mirrors the Windows port's `JVoice.exe --math-probe`.
enum MathProbe {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains("--math-probe")
    }

    static func runAndExit(arguments: [String]) -> Never {
        guard let flag = arguments.firstIndex(of: "--math-probe") else { exit(2) }
        let inline = arguments.dropFirst(flag + 1).filter { !$0.hasPrefix("--") }

        let lines: [String]
        if inline.isEmpty {
            var piped: [String] = []
            while let line = readLine(strippingNewline: true) { piped.append(line) }
            lines = piped
        } else {
            lines = Array(inline)
        }

        var changed = 0
        for line in lines where !line.isEmpty {
            let converted = MathSpeech.convert(line)
            if converted == line {
                print("same|\(line)")
            } else {
                changed += 1
                print("CHANGED|\(line)|\(converted)")
            }
        }
        if lines.count > 1 {
            print("— \(changed) of \(lines.count) line(s) converted")
        }
        exit(0)
    }
}
