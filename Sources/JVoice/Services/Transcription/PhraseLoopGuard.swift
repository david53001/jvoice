import Foundation

/// Detects and collapses a decoder repetition loop ANYWHERE in a transcript —
/// the complement of `RepetitionGuard`, which only strips a TRAILING loop.
///
/// Port of the Windows port's `windows/JVoice.Core/Policy/PhraseLoopGuard.cs`
/// (`docs/HANDOFF-WINDOWS.md` §7 #42 and #45). There, the vocabulary-prompted
/// decode locked into one sentence ×16 in the MIDDLE of a 97 s dictation, and a
/// 21-token clause ×6 inside a streaming chunk: the loop overwrote real speech,
/// normal text resumed after it, so a trailing-only guard never saw it. The
/// unprompted decode of the same audio was clean both times.
///
/// Same algorithm as Windows (runs of consecutive identical phrases of ≤
/// `maxPhraseTokens` tokens, matched on `RepetitionGuard.core`, collapsed to
/// their first occurrence), but stricter thresholds, because on the Mac
/// repetition is also dictated MATHS and emphasis ("minus 3 minus 3 minus 3
/// minus 3", "no, no, no, no"), and deleting dictated maths is exactly the bug
/// the 2026-09-23 `RepetitionGuard` fix removed:
/// - a run needs ≥ `minRepeats` repeats AND ≥ `minLoopTokens` tokens in total
///   (so short-period repeats need more cycles: 1 token ×16, 2 ×8, 3 ×6, 4+ ×4);
/// - a phrase made only of maths tokens (`RepetitionGuard.isMathToken`) needs
///   ≥ `mathMinRepeats` repeats — a whole 24-token window for "26 times".
/// The observed loops covered 96 and 126 tokens, far above both.
public enum PhraseLoopGuard {

    /// Consecutive repeats of one phrase that can count as a loop (Windows: 4).
    static let minRepeats = 4
    /// Longest phrase considered as a loop unit (Windows: 32 since §7 #45 — a
    /// 21-token clause looped). A longer period is never detected.
    static let maxPhraseTokens = 32
    /// Tokens a run must cover (phrase length × repeats). Legit emphasis and
    /// chants stay short ("no no no no" 4, "come on" ×4 = 8, "I love you" ×4
    /// = 12); decoder loops fill a big share of a 224-token window.
    static let minLoopTokens = 16
    /// Repeats required when every word of the phrase is a maths token.
    static let mathMinRepeats = 12

    public struct CollapseResult: Equatable {
        public let text: String
        public let foundLoop: Bool
    }

    /// True when `text` contains a qualifying run anywhere.
    public static func hasLoop(_ text: String) -> Bool {
        collapse(text).foundLoop
    }

    /// Every qualifying run collapsed to its FIRST occurrence (verbatim tokens,
    /// re-joined with single spaces). A trailing PARTIAL repeat is left in
    /// place: absorbing it could eat a genuine sentence that starts with the
    /// phrase's first words. No loop ⇒ the original string, unchanged.
    public static func collapse(_ text: String) -> CollapseResult {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let n = tokens.count
        guard n >= minLoopTokens else { return CollapseResult(text: text, foundLoop: false) }
        let cores = tokens.map(RepetitionGuard.core)

        var kept: [String] = []
        kept.reserveCapacity(n)
        var found = false
        var idx = 0
        while idx < n {
            if let run = bestRun(at: idx, cores: cores) {
                found = true
                kept.append(contentsOf: tokens[idx..<(idx + run.length)])
                idx += run.length * run.count
            } else {
                kept.append(tokens[idx])
                idx += 1
            }
        }
        return found
            ? CollapseResult(text: kept.joined(separator: " "), foundLoop: true)
            : CollapseResult(text: text, foundLoop: false)
    }

    /// The healed transcript after `looped` (the prompted decode) was found to
    /// loop: the unprompted `witness` decode of the same audio when it has
    /// text — it carries the speech the loop overwrote — else `looped`
    /// collapsed. Either way collapsed, so a loop can never be returned.
    public static func resolve(looped: String, witness: String) -> String {
        if witness.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return collapse(looped).text
        }
        return collapse(witness).text
    }

    // MARK: - Internals

    /// The qualifying run starting exactly at `start` that covers the most
    /// tokens, ties to the smallest period; nil when none qualifies.
    private static func bestRun(at start: Int, cores: [String]) -> (length: Int, count: Int)? {
        let n = cores.count
        var best: (length: Int, count: Int)?
        var bestCoverage = 0
        let maxLength = min(maxPhraseTokens, (n - start) / minRepeats)
        guard maxLength >= 1 else { return nil }
        for length in 1...maxLength {
            let phrase = cores[start..<(start + length)].filter { !$0.isEmpty }
            guard !phrase.isEmpty else { continue }   // punctuation only: not a phrase

            var count = 1
            while start + (count + 1) * length <= n,
                  cores[start..<(start + length)] == cores[(start + count * length)..<(start + (count + 1) * length)] {
                count += 1
            }
            let coverage = length * count
            let needed = phrase.allSatisfy(RepetitionGuard.isMathToken) ? mathMinRepeats : minRepeats
            if count >= needed, coverage >= minLoopTokens, coverage > bestCoverage {
                best = (length, count)
                bestCoverage = coverage
            }
        }
        return best
    }
}
