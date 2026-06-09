import Foundation

/// Removes Whisper "prompt regurgitation" / repetition-loop output.
///
/// When the decoder is conditioned with the custom-vocabulary `promptTokens`
/// (OpenAI's `initial_prompt` technique) and hits a low-confidence region — a
/// pause, a breath, a hesitation, or a window boundary — the most probable
/// continuation of its `<|startofprev|> sub agents, claude, li-fraumeni, …`
/// context is *more of the list*, not the user's speech. The decoder starts
/// reciting the vocabulary prompt back, comma by comma, and loops:
///
///     "…buy an item from a country that is sub agents, claude, li-fraumeni,
///      sub agents, claude, vs code, li-fraumeni, sub agents, li-fraumeni, …"
///
/// WhisperKit 1.0.0 cannot stop this itself: `noSpeechProb` is hardcoded to 0
/// (the silence gate is dead) and a window that fails the compression-ratio
/// gate is still emitted (no window is ever dropped). So we detect the
/// degenerate trailing run in post and remove it, keeping the coherent speech
/// that preceded it.
///
/// Conservative by construction: it only strips a *sustained, repetitive,
/// vocabulary/loop-dominated* trailing run, so ordinary speech that merely
/// mentions a custom word once or twice is never touched.
public enum RepetitionGuard {

    /// A trailing loop shorter than this is never stripped (too risky to tell
    /// from a legitimate vocabulary mention).
    static let minLoopTokens = 8
    /// Window over the end of the transcript used to decide "does this even end
    /// in a loop?" before any stripping. Kept tight so a short coherent prefix
    /// can't dilute a genuine trailing loop below the density threshold.
    static let tailWindow = 12
    /// Fraction of the tail (and stripped run) that must be loop tokens.
    static let densityThreshold = 0.7
    /// Some single token must repeat at least this many times for a run to be
    /// considered a loop (the signal that separates a loop from a dense-but-
    /// legitimate sentence, where each custom word appears once or twice).
    static let minRepeatCount = 3
    /// Isolated non-loop tokens tolerated *inside* a loop (Whisper mangles the
    /// odd word — "la", "la-fa" — between clean repeats). A run of more than
    /// this many consecutive non-loop words means coherent speech resumed.
    static let nonLoopyTolerance = 1

    /// The outcome of `scrub`: the cleaned text plus whether a regurgitation
    /// loop was actually removed (the signal the engine uses to decide a clean
    /// re-decode without the vocabulary prompt is warranted).
    public struct ScrubResult: Equatable {
        public let text: String
        public let removedRegurgitation: Bool
    }

    /// `text` with any trailing regurgitation / repetition loop removed, or ""
    /// when the entire text is degenerate.
    public static func strip(_ text: String, vocabulary: [String]) -> String {
        scrub(text, vocabulary: vocabulary).text
    }

    /// Like `strip`, but also reports whether a loop was removed.
    public static func scrub(_ text: String, vocabulary: [String]) -> ScrubResult {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).map(String.init)
        let n = tokens.count
        guard n >= minLoopTokens else { return ScrubResult(text: text, removedRegurgitation: false) }

        let cores = tokens.map(core)
        var counts: [String: Int] = [:]
        for c in cores where !c.isEmpty { counts[c, default: 0] += 1 }

        let vocabCores = vocabularyCores(vocabulary)
        let vocabKeys = Set(vocabCores.map { PhoneticMatcher.phoneticKey(for: $0) }.filter { !$0.isEmpty })

        func loopy(_ i: Int) -> Bool {
            let c = cores[i]
            guard !c.isEmpty else { return false }
            if vocabCores.contains(c) { return true }
            let key = PhoneticMatcher.phoneticKey(for: c)
            if !key.isEmpty, vocabKeys.contains(key) { return true }
            // A word the user actually repeats ≥3× is a loop too (catches
            // generic, non-vocabulary Whisper loops) — but stopwords repeat
            // naturally in prose, so they never qualify on count alone.
            return (counts[c] ?? 0) >= minRepeatCount && !stopwords.contains(c)
        }

        // 1. Quick gate: does the END look loopy at all (dense in loop tokens)?
        //    Repetition is NOT required here — a long cycle (e.g. four distinct
        //    multi-word custom phrases) only repeats twice inside a fixed tail
        //    window, so demanding ≥3 here would miss it. The real repetition
        //    requirement is enforced by the final validation over the whole loop
        //    run (step 3), which sees every cycle. Normal speech fails the
        //    density check and is returned untouched.
        guard isDegenerate(range: max(0, n - tailWindow)..<n, cores: cores, loopy: loopy, requireRepeat: false) else {
            return ScrubResult(text: text, removedRegurgitation: false)
        }

        // 2. Walk left to the loop onset, tolerating isolated mangled tokens but
        //    stopping at a run of coherent (non-loop) words.
        var onset = n
        var consecutiveNonLoopy = 0
        var i = n - 1
        while i >= 0 {
            defer { i -= 1 }
            if cores[i].isEmpty { continue }   // pure punctuation: neutral
            if loopy(i) {
                onset = i
                consecutiveNonLoopy = 0
            } else {
                consecutiveNonLoopy += 1
                if consecutiveNonLoopy > nonLoopyTolerance { break }
            }
        }

        // 3. Validate the stripped run is long *and* repetitive enough to be a
        //    real loop (never strip a brief, legitimate vocabulary mention).
        guard onset < n, isDegenerate(range: onset..<n, cores: cores, loopy: loopy) else {
            return ScrubResult(text: text, removedRegurgitation: false)
        }

        if onset == 0 { return ScrubResult(text: "", removedRegurgitation: true) }
        let kept = tokens[0..<onset].joined(separator: " ")
        return ScrubResult(text: kept.trimmingCharacters(in: trailingSeparators), removedRegurgitation: true)
    }

    // MARK: - Internals

    /// A range of `cores` is degenerate when most of its non-empty tokens are
    /// loop tokens, it is long enough, and some token repeats ≥ `minRepeatCount`.
    private static func isDegenerate(range: Range<Int>, cores: [String], loopy: (Int) -> Bool, requireRepeat: Bool = true) -> Bool {
        let nonEmpty = range.filter { !cores[$0].isEmpty }
        guard nonEmpty.count >= minLoopTokens else { return false }
        let loopCount = nonEmpty.filter { loopy($0) }.count
        guard Double(loopCount) / Double(nonEmpty.count) >= densityThreshold else { return false }
        guard requireRepeat else { return true }
        var counts: [String: Int] = [:]
        for idx in nonEmpty { counts[cores[idx], default: 0] += 1 }
        return (counts.values.max() ?? 0) >= minRepeatCount
    }

    /// Lowercased letters/digits only — strips the surrounding punctuation
    /// (commas, the period, quotes) Whisper attaches to loop tokens.
    static func core(_ token: String) -> String {
        String(token.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Every spoken sub-word of every custom phrase, as bare cores: "sub agents"
    /// → {sub, agents, subagents}, "VS Code" → {vs, code, vscode},
    /// "li-fraumeni" → {li, fraumeni, lifraumeni}. The transcript lists them as
    /// separate tokens, so the parts are what actually match.
    static func vocabularyCores(_ vocabulary: [String]) -> Set<String> {
        var result: Set<String> = []
        for word in vocabulary {
            let whole = core(word)
            if whole.count >= 2 { result.insert(whole) }
            for part in word.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "/" }) {
                var current = ""
                for (idx, ch) in part.enumerated() {
                    if idx > 0, ch.isUppercase, !current.isEmpty {
                        let c = core(current); if c.count >= 2 { result.insert(c) }
                        current = ""
                    }
                    current.append(ch)
                }
                let c = core(current); if c.count >= 2 { result.insert(c) }
            }
        }
        return result
    }

    static let trailingSeparators = CharacterSet(charactersIn: " ,;:")

    /// Function words that repeat naturally in prose; excluded from the
    /// repeat-count loop signal so a sentence isn't mistaken for a loop.
    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "by", "from",
        "is", "are", "was", "were", "be", "been", "being", "am", "do", "does", "did", "have", "has", "had",
        "it", "its", "i", "you", "he", "she", "we", "they", "me", "him", "her", "us", "them", "my", "your",
        "this", "that", "these", "those", "so", "as", "if", "then", "there", "here", "not", "no", "yes",
        "just", "like", "what", "which", "who", "when", "where", "how", "why", "about", "up", "out", "now",
    ]
}
