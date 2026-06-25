import Foundation

/// Fuzzy phonetic matcher that corrects Whisper mishearings of user-defined
/// vocabulary. The exact-variant pass (`TextProcessor.applyCorrections`) only
/// fixes spellings it can predict; this pass catches *phonetic* misses —
/// "jay voice" → "JVoice", "whisper cat" → "WhisperKit" — by comparing a
/// sound key + edit distance between transcript word-windows and each word.
public enum PhoneticMatcher {

    // MARK: - Public API

    /// Replaces word-windows in `text` that sound like a vocabulary entry with
    /// that entry's exact spelling. `text` is expected to be
    /// whitespace-normalized (single spaces), as produced by
    /// `TextProcessor.normalizeWhitespace`.
    public static func correct(_ text: String, vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty, !text.isEmpty else { return text }

        let entries = vocabulary
            .map(Entry.init)
            .filter { $0.letters.count >= 3 }
            .sorted { $0.letters.count > $1.letters.count }
        guard !entries.isEmpty else { return text }

        var tokens = text.split(separator: " ").map { Token(String($0)) }
        let maxWindow = entries.map(\.maxWindow).max() ?? 1

        var i = 0
        while i < tokens.count {
            var advanced = false
            let upperWindow = min(maxWindow, tokens.count - i)
            // Smallest window first: an exact single-token hit ("JVoice")
            // must short-circuit before a larger fuzzy window ("JVoice is" →
            // "jvoiceis") can swallow neighboring words.
            windowSearch: for window in 1...upperWindow {
                let slice = Array(tokens[i..<(i + window)])
                let candidate = slice.map(\.coreLetters).joined()
                guard candidate.count >= 3 else { continue }
                for entry in entries where window <= entry.maxWindow {
                    guard matches(candidate: candidate, entry: entry) else { continue }
                    let renderedCore = slice.map(\.core).joined(separator: " ")
                    let renderedFull = slice.map(\.rendered).joined(separator: " ")
                    if renderedCore == entry.word || renderedFull == entry.word {
                        // Already exact — either the cores spell the word
                        // ("VS Code" correctly spelled), or the full token
                        // already reads as the word *including its own
                        // punctuation*. The latter guards ".NET": its leading
                        // "." is split into `leading`, so the bare core "NET"
                        // fuzzy-matches the entry and the replacement would
                        // re-prepend entry.word's own ".", corrupting it into
                        // "..NET" (TRX-01). Nothing to do — stop probing here.
                        break windowSearch
                    }
                    let replacement = Token(
                        leading: slice.first?.leading ?? "",
                        core: entry.word,
                        trailing: slice.last?.trailing ?? ""
                    )
                    tokens.replaceSubrange(i..<(i + window), with: [replacement])
                    i += 1
                    advanced = true
                    break windowSearch
                }
            }
            if !advanced { i += 1 }
        }

        return tokens.map(\.rendered).joined(separator: " ")
    }

    // MARK: - Matching

    private static func matches(candidate: String, entry: Entry) -> Bool {
        if candidate == entry.letters { return true }   // spacing/casing drift only

        // Length sanity: wildly different lengths can't be the same word.
        guard abs(candidate.count - entry.letters.count) <= 2 + entry.letters.count / 3 else {
            return false
        }

        let candidateKey = phoneticKey(for: candidate)
        // Initial-sound guard: "voice"(fs…) must never match "JVoice"(jfs…).
        guard let cFirst = candidateKey.first, let eFirst = entry.key.first, cFirst == eFirst else {
            return false
        }

        let letterDistance = levenshtein(candidate, entry.letters, limit: 3)
        if candidateKey == entry.key && letterDistance <= max(1, entry.letters.count / 3) {
            return true
        }
        if entry.letters.count >= 6 {
            let keyDistance = levenshtein(candidateKey, entry.key, limit: 1)
            if keyDistance <= 1 && letterDistance <= 2 { return true }
        }
        return false
    }

    // MARK: - Phonetic key (simplified Metaphone)

    /// A compact "how it sounds" key: letters-only input → consonant skeleton
    /// with merged sound-alike consonants. Deliberate simplifications: g and j
    /// merge (the spoken letter "G" is /dʒ/ — Whisper writes either for names
    /// like JVoice), vowels vanish except in initial position.
    static func phoneticKey(for input: String) -> String {
        var s = Array(input.lowercased().filter(\.isLetter))
        guard !s.isEmpty else { return "" }

        // Prefix simplifications.
        let prefixes: [(match: [Character], replacement: [Character])] = [
            (["k", "n"], ["n"]), (["w", "r"], ["r"]), (["p", "s"], ["s"]), (["w", "h"], ["w"]),
        ]
        for rule in prefixes where s.count >= rule.match.count && Array(s.prefix(rule.match.count)) == rule.match {
            s.replaceSubrange(0..<rule.match.count, with: rule.replacement)
            break
        }

        // Pass 1: map letters (consuming digraphs), keeping vowels for now.
        var mapped: [Character] = []
        var i = 0
        while i < s.count {
            let ch = s[i]
            let nxt: Character? = i + 1 < s.count ? s[i + 1] : nil
            var out: Character
            var consumed = 1
            switch (ch, nxt) {
            case ("p", "h"): out = "f"; consumed = 2
            case ("s", "h"), ("c", "h"): out = "x"; consumed = 2
            case ("t", "h"): out = "0"; consumed = 2
            case ("c", "k"), ("q", "u"), ("g", "h"): out = "k"; consumed = 2
            default:
                switch ch {
                case "b": out = "p"
                case "c": out = (nxt.map { "eiy".contains($0) } ?? false) ? "s" : "k"
                case "d": out = "t"
                case "g", "j": out = "j"
                case "k", "q": out = "k"
                case "v": out = "f"
                case "x", "z": out = "s"
                default: out = ch
                }
            }
            mapped.append(out)
            i += consumed
        }

        // Pass 2: keep position 0; drop vowels elsewhere. Pass 3: dedupe runs.
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var key: [Character] = []
        for (idx, ch) in mapped.enumerated() {
            if idx > 0 && vowels.contains(ch) { continue }
            if key.last == ch { continue }
            key.append(ch)
        }
        return String(key)
    }

    // MARK: - Edit distance

    /// Levenshtein distance with an early-exit cap: returns `limit + 1` as soon
    /// as the distance provably exceeds `limit`.
    static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if abs(aChars.count - bChars.count) > limit { return limit + 1 }
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for (i, ca) in aChars.enumerated() {
            current[0] = i + 1
            var rowMin = current[0]
            for (j, cb) in bChars.enumerated() {
                let cost = ca == cb ? 0 : 1
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost)
                rowMin = min(rowMin, current[j + 1])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return min(previous[bChars.count], limit + 1)
    }

    // MARK: - Internals

    private struct Entry {
        let word: String
        let letters: String
        let key: String
        let maxWindow: Int

        init(_ word: String) {
            self.word = word
            self.letters = word.lowercased().filter(\.isLetter)
            self.key = PhoneticMatcher.phoneticKey(for: letters)
            // Spoken-word estimate: whitespace splits + camelCase boundaries.
            var spokenWords = 0
            for part in word.split(separator: " ") {
                var boundaries = 1
                for (i, ch) in part.enumerated() where i > 0 && ch.isUppercase {
                    boundaries += 1
                }
                spokenWords += boundaries
            }
            self.maxWindow = max(1, spokenWords) + 1
        }
    }

    private struct Token {
        let leading: String
        let core: String
        let trailing: String

        init(leading: String, core: String, trailing: String) {
            self.leading = leading
            self.core = core
            self.trailing = trailing
        }

        init(_ raw: String) {
            let chars = Array(raw)
            var start = 0
            var end = chars.count
            while start < end && !chars[start].isLetter && !chars[start].isNumber { start += 1 }
            while end > start && !chars[end - 1].isLetter && !chars[end - 1].isNumber { end -= 1 }
            leading = String(chars[0..<start])
            core = String(chars[start..<end])
            trailing = String(chars[end...])
        }

        var coreLetters: String { core.lowercased().filter(\.isLetter) }
        var rendered: String { leading + core + trailing }
    }
}
