import Foundation

public struct TextProcessor: Sendable {
    public static let shared = TextProcessor()

    public static let correctionDictionary: [String: String] = [
        "app kit": "AppKit",
        "appkit": "AppKit",
        "j voice": "JVoice",
        "jvoice": "JVoice",
        "keyboard shortcuts": "KeyboardShortcuts",
        "keyboardshortcuts": "KeyboardShortcuts",
        "mac os": "macOS",
        "whisper kit": "WhisperKit",
        "whisperkit": "WhisperKit"
    ]

    public init() {}

    public func process(_ text: String, mode: AppMode) -> String {
        Self.process(text, mode: mode)
    }

    public static func process(_ text: String, mode: AppMode, extraDictionary: [String: String] = [:], removeFillerWords: Bool = false, vocabulary: [String] = []) -> String {
        let normalized = normalizeWhitespace(text)
        let clean = removeFillerWords ? removeDisfluencies(normalized) : normalized
        // Very Casual lowercases the sentence — but corrections must win over
        // the lowering, so lower *first* and correct after. Custom words keep
        // their exact casing in every tone.
        let cased = mode == .veryCasual ? clean.lowercased() : clean
        let corrected = applyCorrections(cased, extraDictionary: extraDictionary)
        let phonetic = PhoneticMatcher.correct(corrected, vocabulary: vocabulary)
        return format(phonetic, mode: mode)
    }

    public func transform(_ text: String, mode: AppMode) -> String {
        process(text, mode: mode)
    }

    public static func transform(_ text: String, mode: AppMode) -> String {
        process(text, mode: mode)
    }

    public static func applyCorrections(_ text: String, extraDictionary: [String: String] = [:]) -> String {
        var result = text
        let combined = extraDictionary.merging(correctionDictionary) { _, builtin in builtin }
        for (needle, replacement) in combined.sorted(by: { $0.key.count > $1.key.count }) {
            result = replaceOccurrences(of: needle, in: result, with: replacement)
        }
        return result
    }

    public static func buildUserDictionary(from words: [String]) -> [String: String] {
        var dict: [String: String] = [:]
        for word in words {
            for variant in spokenVariants(for: word) where correctionDictionary[variant] == nil {
                dict[variant] = word
            }
        }
        return dict
    }

    public static func extractCorrections(from original: String, corrected: String) -> [String] {
        let originalWords = original.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let correctedWords = corrected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var results: [String] = []

        if originalWords.count == correctedWords.count {
            for (orig, corr) in zip(originalWords, correctedWords) where orig != corr {
                let stripped = corr.trimmingCharacters(in: .punctuationCharacters)
                if !stripped.isEmpty { results.append(stripped) }
            }
        } else {
            let originalExact = Set(originalWords)
            for word in correctedWords where !originalExact.contains(word) {
                let stripped = word.trimmingCharacters(in: .punctuationCharacters)
                if !stripped.isEmpty { results.append(stripped) }
            }
        }

        return Array(Set(results)).filter { $0.count > 1 }
    }

    public static func spokenVariants(for word: String) -> [String] {
        var variants: Set<String> = []
        let lower = word.lowercased()

        variants.insert(lower)
        variants.insert(lower.replacingOccurrences(of: " ", with: ""))
        variants.insert(lower.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: ""))
        variants.insert(lower.replacingOccurrences(of: ".", with: " "))

        var camelSplit = ""
        for (i, char) in word.enumerated() {
            if char.isUppercase && i > 0 {
                camelSplit += " "
            }
            camelSplit += String(char).lowercased()
        }
        variants.insert(camelSplit)
        variants.insert(camelSplit.replacingOccurrences(of: " ", with: ""))

        // Drop any variant that is itself a substring of the canonical word
        // (case-insensitive). A punctuated custom word like ".NET" otherwise
        // registers the bare "net" variant, whose \b…\b pattern then re-matches
        // the letter-run inside the already-inserted ".NET" replacement,
        // corrupting it into "..NET"/"...NET" (TRX-01). A variant that is a
        // substring of the word can never correct anything the word itself
        // wouldn't already, so removing it is safe and stops the self-overlap.
        return Array(variants).filter { !$0.isEmpty && $0 != word && !lower.contains($0) }
    }

    public static func format(_ text: String, mode: AppMode) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch mode {
        case .casual:
            return removeTerminalPunctuation(trimmed)
        case .formal:
            let capitalized = capitalizeFirstCharacter(trimmed)
            return ensureTerminalPeriod(capitalized)
        case .veryCasual:
            // Lowercasing happens in `process` *before* the correction passes
            // (so corrections survive); re-lowering here would destroy them.
            let tidied = collapseRepeatedCommas(trimmed)
            return ensureTerminalDotOrQuestion(tidied)
        }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func removeDisfluencies(_ text: String) -> String {
        let pattern = #"(?i)\b(um+h?|uh+|er+|a+h+|hmm+)\b[,.]?\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        var result = normalizeWhitespace(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.hasSuffix(",") { result.removeLast() }
        return result
    }

    /// Known non-speech sentinel keywords WhisperKit/Whisper emit inside
    /// brackets. A bracketed token only counts as an artifact if its content
    /// contains an underscore (e.g. "BLANK_AUDIO", "NOISE_1") OR matches one of
    /// these words. This keeps legitimate dictated tokens like "[A]", "[I]",
    /// "[II]", "[X]" (option labels, citation markers, Roman numerals) intact.
    private static let decoderSentinelKeywords: Set<String> = [
        "BLANK_AUDIO", "BLANK_TEXT", "MUSIC", "APPLAUSE", "NOISE", "SILENCE",
        "INAUDIBLE", "LAUGHTER", "SOUND", "CROSSTALK"
    ]

    /// Removes WhisperKit/Whisper special-token renderings that leak into the
    /// transcript on silence / non-speech — "[BLANK_AUDIO]", "[BLANK_TEXT]",
    /// "[MUSIC]", "[APPLAUSE]", etc. These are never user speech and can appear
    /// mid-transcript on pause-heavy dictation. Only bracketed tokens that are
    /// real decoder sentinels (underscore-bearing or in `decoderSentinelKeywords`)
    /// are stripped, so legitimate dictated labels like "[A]"/"[II]"/"[X]" survive.
    public static func stripDecoderArtifacts(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[[A-Z_][A-Z0-9_ ]*\]"#) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text
        // Replace strippable matches back-to-front so earlier ranges stay valid.
        for match in regex.matches(in: text, options: [], range: range).reversed() {
            let bracketed = nsText.substring(with: match.range)
            let inner = bracketed.dropFirst().dropLast() // strip the surrounding [ ]
            let isSentinel = inner.contains("_") || decoderSentinelKeywords.contains(String(inner))
            guard isSentinel, let r = Range(match.range, in: result) else { continue }
            result.replaceSubrange(r, with: " ")
        }
        return normalizeWhitespace(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips known Whisper hallucination outputs that occur on near-silent or zero-content
    /// audio. Returns an empty string if the entire input is hallucination noise.
    public static func removeWhisperHallucinations(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lone punctuation
        if trimmed.isEmpty { return "" }
        if trimmed.allSatisfy({ ".,;:!? ".contains($0) }) { return "" }
        // Whisper-specific sentinels (stored without terminal punctuation).
        let blanklikePatterns = [
            "[BLANK_TEXT]",
            "BLANK_TEXT",
            "Thanks for watching",
            "Thank you",
            "Thank you for watching",
            "Subscribe to my channel",
            "Please subscribe to my channel",
            "Bye",
        ]
        // The tone formatter rewrites terminal "."/"!"/"?" before this filter
        // runs (Casual strips it, Formal/Very-Casual add one), so compare with
        // any trailing terminal punctuation removed — otherwise a whole-transcript
        // hallucination leaks whenever the formatter dropped its punctuation.
        let core = removeTerminalPunctuation(trimmed)
        for pattern in blanklikePatterns {
            if core.caseInsensitiveCompare(pattern) == .orderedSame {
                return ""
            }
        }
        return text
    }

    private static func replaceOccurrences(of needle: String, in text: String, with replacement: String) -> String {
        let pattern = phrasePattern(for: needle)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let safeTemplate = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: safeTemplate)
    }

    private static func phrasePattern(for phrase: String) -> String {
        let components = phrase
            .split(separator: " ")
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        return #"\b"# + components.joined(separator: #"\s+"#) + #"\b"#
    }

    private static func removeTerminalPunctuation(_ text: String) -> String {
        var result = text
        while let last = result.last, ".!?".contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func capitalizeFirstCharacter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    private static func ensureTerminalPeriod(_ text: String) -> String {
        guard let last = text.last else { return text }
        if ".!?".contains(last) { return text }
        return text + "."
    }

    /// Collapses runs of commas — and the whitespace around them — into a
    /// single ", " so a very-casual transcript separates clauses without
    /// piling up commas.
    private static func collapseRepeatedCommas(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s*,(?:\s*,)*\s*"#) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: ", ")
    }

    /// Guarantees the very-casual output ends on a dot or a question mark.
    /// An existing `?`/`.` is kept, a trailing `!` becomes `.`, and any
    /// dangling comma or whitespace separator is dropped before the period.
    private static func ensureTerminalDotOrQuestion(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "," {
            result.removeLast()
        }
        guard let last = result.last else { return result }
        if last == "?" || last == "." { return result }
        if last == "!" {
            result.removeLast()
            return result + "."
        }
        return result + "."
    }
}
