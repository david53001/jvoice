# Vocabulary v2: Prompt Biasing + Phonetic Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make custom words actually work: bias Whisper's decoder toward the user's vocabulary at recognition time (`promptTokens`), and catch the remaining phonetic mishearings ("jay voice" → "JVoice") with a fuzzy phonetic post-correction pass. Also fix the Very Casual tone destroying custom-word casing.

**Why the current system fails (the user's complaint):** `TextProcessor.buildUserDictionary` generates *predictable spelling variants* of each custom word (lowercase, no-space, camel-split) and regex-replaces them after transcription. But Whisper never saw the vocabulary, so it transcribes what it *hears*: "JVoice" becomes "jay voice", "Jay Voice", "G voice", "j-voice" — none of which match the generated variants. Recognition must be biased *inside* the model, and the post-pass must match by *sound*, not by spelling.

**Architecture:** Three layers, each independently testable:
1. **Decoder biasing** — `WhisperKitTranscriptionEngine` feeds the custom words to WhisperKit as `DecodingOptions.promptTokens` (the decoder conditions on them exactly like OpenAI's `initial_prompt`; WhisperKit prepends them after `<|startofprev|>` — verified in `.build/checkouts/WhisperKit/Sources/WhisperKit/Core/TextDecoder.swift:198-202`). Token IDs are computed once per vocabulary change via `kit.tokenizer` and cached on the actor.
2. **Phonetic post-correction** — new `PhoneticMatcher` compares transcript word-windows against each custom word using a simplified-Metaphone sound key + Levenshtein distance, replacing sound-alike windows. Runs in `TextProcessor.process` right after the existing exact-variant corrections.
3. **Casing preservation** — Very Casual mode currently lowercases the *final* text (`TextProcessor.format`), destroying corrections like "JVoice" → "jvoice". Lowercasing moves *before* the correction passes.

**Tech Stack:** Pure Swift + Foundation for layers 2/3 (zero deps), WhisperKit 1.0.0 API for layer 1.

**Session constraints:**
- NO git commits/pushes (David's explicit instruction).
- `swift test` compiles but executes 0 tests locally (CLT-only machine). XCTest files are written for CI; *actual local verification* uses the new `scripts/run-logic-tests.sh` standalone harness (compiles the pure-logic sources with an assertion `main` and runs them).

**Key API facts (verified against the WhisperKit 1.0.0 checkout):**
- `DecodingOptions.promptTokens: [Int]?` exists; consumed only when `usePrefillPrompt` is true (default true).
- `TextDecoder` trims prompt tokens to `maxTokenContext/2 - 1` and filters `$0 < tokenizer.specialTokens.specialTokenBegin`, so over-long or special-token-containing arrays are safe.
- `WhisperKit.tokenizer: WhisperTokenizer?` exposes `encode(text:) -> [Int]` and `specialTokens.specialTokenBegin`.

---

### Task 1: `VocabularyPrompt` — pure prompt-text builder

**Files:**
- Create: `Sources/JVoice/Services/VocabularyPrompt.swift`
- Test: `Tests/JVoiceTests/VocabularyPromptTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import JVoice

final class VocabularyPromptTests: XCTestCase {
    func testEmptyVocabularyProducesNoPrompt() {
        XCTAssertNil(VocabularyPrompt.text(for: []))
        XCTAssertNil(VocabularyPrompt.text(for: ["", "   "]))
    }

    func testWordsAreCommaJoinedWithLeadingSpace() {
        // The leading space matters: Whisper's BPE merges a leading space into
        // word tokens, so conditioning text must look like natural transcript.
        XCTAssertEqual(VocabularyPrompt.text(for: ["JVoice", "WhisperKit"]), " JVoice, WhisperKit")
    }

    func testVocabularyIsCappedToBoundDecodeCost() {
        let words = (0..<100).map { "word\($0)" }
        let text = VocabularyPrompt.text(for: words)!
        XCTAssertTrue(text.contains("word\(VocabularyPrompt.maxWords - 1)"))
        XCTAssertFalse(text.contains("word\(VocabularyPrompt.maxWords)"))
    }
}
```

- [ ] **Step 2: Verify failure**

Run: `swift build --build-tests 2>&1 | tail -3`
Expected: error: cannot find 'VocabularyPrompt'

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Builds the decoder-conditioning prompt from the user's custom words.
///
/// Whisper conditions its decoder on "previous transcript" text. Feeding the
/// custom vocabulary as that text (OpenAI's `initial_prompt` technique) makes
/// the model strongly prefer those spellings when the audio sounds like them —
/// fixing recognition at the source instead of patching it afterwards.
public enum VocabularyPrompt {
    /// Cap on words included — keeps the decoder prefill cheap; prompt tokens
    /// linearly increase per-window decode cost.
    public static let maxWords = 40
    /// Hard cap on encoded tokens, well under WhisperKit's own
    /// `maxTokenContext/2 - 1` (~111) trim.
    public static let maxPromptTokens = 96

    /// The conditioning text, or nil when there is nothing to bias toward.
    public static func text(for words: [String]) -> String? {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return " " + cleaned.prefix(maxWords).joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build --build-tests`
Expected: `Build complete!`

---

### Task 2: `PhoneticMatcher` — sound-alike fuzzy correction

**Files:**
- Create: `Sources/JVoice/Services/PhoneticMatcher.swift`
- Test: `Tests/JVoiceTests/PhoneticMatcherTests.swift`

**Algorithm (locked during spec):**
- `phoneticKey(for:)` — simplified Metaphone over letters-only lowercase input:
  - Pass 0 (prefixes): `kn→n`, `wr→r`, `ps→s`, `wh→w`.
  - Pass 1 (map, walking with digraph consumption): `ph→f`, `sh→x`, `ch→x`, `th→0`, `ck→k`, `qu→k`, `gh→k`; singles `b→p`, `c→s` before e/i/y else `k`, `d→t`, `g→j` (a deliberate g/j merge — spoken letter "G" and "J" both read /dʒ/, and Whisper writes either), `j→j`, `q→k`, `v→f`, `x→s`, `z→s`; vowels and remaining consonants pass through.
  - Pass 2: keep index 0 as-is; drop vowels (`aeiouy`) elsewhere.
  - Pass 3: collapse consecutive duplicates.
  - Worked examples (used as tests): `jvoice→jfs`, `jayvoice→jfs`, `gvoice→jfs`, `whisperkit→wsprkt`, `whispercat→wsprkt`, `voice→fs`.
- `levenshtein(_:_:limit:)` — classic 2-row DP; returns `limit+1` early when a full row's minimum exceeds `limit`.
- `correct(_:vocabulary:)` — tokenize on single spaces (input is upstream-normalized by `TextProcessor.normalizeWhitespace`), strip per-token leading/trailing punctuation, then greedy left-to-right scan with windows from largest to 1 (window cap = vocab word's spoken-word count + 1, spoken words = whitespace splits + camelCase splits). A window matches an entry when:
  - exact: candidate letters == entry letters (pure spacing/casing drift), OR
  - phonetic: keys share the first character (initial-sound guard — this is what stops `voice` → `JVoice`: key `fs` vs `jfs`) AND
    - keys equal AND letter-distance ≤ max(1, entryLetters/3), OR
    - entryLetters ≥ 6 AND keyDistance ≤ 1 AND letter-distance ≤ 2.
  - replacement preserves the first token's leading and last token's trailing punctuation; entries shorter than 3 letters never participate (too false-positive-prone).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import JVoice

final class PhoneticMatcherTests: XCTestCase {

    // MARK: phoneticKey

    func testPhoneticKeyWorkedExamples() {
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "jvoice"), "jfs")
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "jayvoice"), "jfs")
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "gvoice"), "jfs")
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "whisperkit"), "wsprkt")
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "whispercat"), "wsprkt")
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "voice"), "fs")
    }

    func testPhoneticKeyKeepsLeadingVowel() {
        XCTAssertEqual(PhoneticMatcher.phoneticKey(for: "appkit").first, "a")
    }

    // MARK: levenshtein

    func testLevenshteinBasics() {
        XCTAssertEqual(PhoneticMatcher.levenshtein("jvoice", "jayvoice", limit: 3), 2)
        XCTAssertEqual(PhoneticMatcher.levenshtein("same", "same", limit: 3), 0)
        XCTAssertEqual(PhoneticMatcher.levenshtein("abc", "xyz", limit: 2), 3) // early-exit cap = limit+1
    }

    // MARK: correct — the cases the user actually hits

    func testHearsSpelledOutName() {
        XCTAssertEqual(
            PhoneticMatcher.correct("open jay voice settings", vocabulary: ["JVoice"]),
            "open JVoice settings"
        )
    }

    func testHearsLetterGVariant() {
        XCTAssertEqual(
            PhoneticMatcher.correct("g voice is running", vocabulary: ["JVoice"]),
            "JVoice is running"
        )
    }

    func testHearsSoundalikeCompound() {
        XCTAssertEqual(
            PhoneticMatcher.correct("built with whisper cat", vocabulary: ["WhisperKit"]),
            "built with WhisperKit"
        )
    }

    func testPreservesPunctuation() {
        XCTAssertEqual(
            PhoneticMatcher.correct("is jay voice, ready", vocabulary: ["JVoice"]),
            "is JVoice, ready"
        )
    }

    // MARK: correct — false-positive guards

    func testPlainWordIsNotHijacked() {
        // "voice" alone must NOT become JVoice — initial sound differs (f vs j).
        XCTAssertEqual(
            PhoneticMatcher.correct("use your voice now", vocabulary: ["JVoice"]),
            "use your voice now"
        )
    }

    func testAlreadyCorrectTextIsUntouched() {
        XCTAssertEqual(
            PhoneticMatcher.correct("JVoice is great", vocabulary: ["JVoice"]),
            "JVoice is great"
        )
    }

    func testEmptyVocabularyIsNoop() {
        XCTAssertEqual(PhoneticMatcher.correct("hello there", vocabulary: []), "hello there")
    }

    func testShortVocabularyWordsAreIgnored() {
        // <3 letters is too false-positive-prone to fuzzy-match.
        XCTAssertEqual(PhoneticMatcher.correct("ay bee sea", vocabulary: ["AB"]), "ay bee sea")
    }
}
```

- [ ] **Step 2: Verify failure**

Run: `swift build --build-tests 2>&1 | tail -3`
Expected: error: cannot find 'PhoneticMatcher'

- [ ] **Step 3: Implement**

```swift
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
            windowSearch: for window in stride(from: upperWindow, through: 1, by: -1) {
                let slice = Array(tokens[i..<(i + window)])
                let candidate = slice.map(\.coreLetters).joined()
                guard candidate.count >= 3 else { continue }
                for entry in entries where window <= entry.maxWindow {
                    guard matches(candidate: candidate, entry: entry) else { continue }
                    let renderedCore = slice.map(\.core).joined(separator: " ")
                    if window == 1 && renderedCore == entry.word {
                        // Already exact — nothing to do, stop probing this position.
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
    /// merge (spoken letter "G" is /dʒ/ — Whisper writes either for names like
    /// JVoice), vowels vanish except in initial position.
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
```

- [ ] **Step 4: Build**

Run: `swift build --build-tests`
Expected: `Build complete!`

> Implementation note discovered during spec: `"g voice"` tokenizes to cores `g` + `voice` → candidate `gvoice` (6 letters) at window 2 — passes the ≥3 candidate gate even though the single token `g` is short. The `Entry` letter gate (≥3) only constrains vocabulary entries.

---

### Task 3: Pipeline integration in `TextProcessor` + Very Casual casing fix

**Files:**
- Modify: `Sources/JVoice/Services/TextProcessor.swift:24-29` (`process`), `:102-117` (`format`)
- Test: `Tests/JVoiceTests/TextProcessorTests.swift` (append)

- [ ] **Step 1: Write the failing tests** (append to the existing test file, matching its style — read it first)

```swift
    func testProcessAppliesPhoneticVocabularyCorrection() {
        let result = TextProcessor.process(
            "open jay voice now",
            mode: .casual,
            vocabulary: ["JVoice"]
        )
        XCTAssertEqual(result, "open JVoice now")
    }

    func testVeryCasualPreservesCustomWordCasing() {
        // Very Casual lowercases the sentence — but never the user's vocabulary.
        let result = TextProcessor.process(
            "Open Jay Voice Settings",
            mode: .veryCasual,
            vocabulary: ["JVoice"]
        )
        XCTAssertEqual(result, "open JVoice settings.")
    }

    func testVeryCasualPreservesDictionaryCasing() {
        // Built-in corrections (e.g. "mac os" → "macOS") must also survive.
        let result = TextProcessor.process("I Love Mac OS", mode: .veryCasual)
        XCTAssertEqual(result, "i love macOS.")
    }
```

- [ ] **Step 2: Verify failure**

Run: `swift build --build-tests 2>&1 | tail -3`
Expected: error: extra argument 'vocabulary' in call

- [ ] **Step 3: Implement.** In `TextProcessor.process`, add the `vocabulary` parameter and move Very Casual lowercasing *before* the correction passes:

```swift
    public static func process(_ text: String, mode: AppMode, extraDictionary: [String: String] = [:], removeFillerWords: Bool = false, vocabulary: [String] = []) -> String {
        let normalized = normalizeWhitespace(text)
        let clean = removeFillerWords ? removeDisfluencies(normalized) : normalized
        // Very Casual lowercases the sentence — but corrections must win over
        // the lowering, so lower *first* and correct after.
        let cased = mode == .veryCasual ? clean.lowercased() : clean
        let corrected = applyCorrections(cased, extraDictionary: extraDictionary)
        let phonetic = PhoneticMatcher.correct(corrected, vocabulary: vocabulary)
        return format(phonetic, mode: mode)
    }
```

And in `format(_:mode:)`, the `.veryCasual` case stops lowercasing (the text arrives pre-lowered; re-lowering would destroy corrections):

```swift
        case .veryCasual:
            let tidied = collapseRepeatedCommas(trimmed)
            return ensureTerminalDotOrQuestion(tidied)
```

**Check before changing `format`:** read `Tests/JVoiceTests/TextProcessorTests.swift` for tests that call `format`/`transform`/`process` with `.veryCasual` and expect lowercasing of pre-cased input. Any such test must be updated to call through `process` (the public pipeline) or to pass pre-lowered input — note the behavior change in the test comment: *casing policy moved from format to process so corrections survive*.

- [ ] **Step 4: Build**

Run: `swift build --build-tests`
Expected: `Build complete!`

---

### Task 4: Decoder biasing in `WhisperKitTranscriptionEngine`

**Files:**
- Modify: `Sources/JVoice/Services/TranscriptionManager.swift:4-13` (protocol), `:96-182` (engine), `:185-255` (manager)

- [ ] **Step 1: Extend the protocol** (default no-op keeps `FileBackedTranscriptionEngine` and test fakes source-compatible):

```swift
public protocol TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String
    /// Eagerly load the underlying model so the first transcription isn't a
    /// cold-start model load. Default is a no-op for engines needing no warm-up.
    func prewarm() async
    /// Update the user vocabulary used to bias decoding toward custom words.
    /// Default is a no-op for engines without vocabulary support.
    func updateVocabulary(_ words: [String]) async
}

extension TranscriptionEngine {
    public func prewarm() async {}
    public func updateVocabulary(_ words: [String]) async {}
}
```

- [ ] **Step 2: Engine changes.** In `WhisperKitTranscriptionEngine`:

```swift
public actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    private let model: WhisperModelOption
    private let language: TranscriptionLanguage
    private var vocabulary: [String]
    /// Token IDs for the vocabulary prompt, computed once per vocabulary
    /// change (requires the loaded model's tokenizer). Empty array = computed,
    /// nothing to bias. nil = needs (re)computation.
    private var cachedPromptTokens: [Int]?
    private var whisperKit: WhisperKit?
    private var loadTask: Task<Void, Error>?

    public init(model: WhisperModelOption, language: TranscriptionLanguage = .english, vocabulary: [String] = []) {
        self.model = model
        self.language = language
        self.vocabulary = vocabulary
    }

    public func updateVocabulary(_ words: [String]) {
        guard words != vocabulary else { return }
        vocabulary = words
        cachedPromptTokens = nil
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let kit = try await loadWhisperKit()
        var decodeOptions = DecodingOptions()
        decodeOptions.language = language.whisperCode
        // Language is fixed by the user — skip the language-detection pass.
        decodeOptions.detectLanguage = false
        // Fewer temperature-fallback retries on a hard window → lower tail latency.
        decodeOptions.temperatureFallbackCount = 2
        // VAD chunking parallelises long recordings across workers and skips
        // silence. No effect on short clips that fit in a single window.
        decodeOptions.chunkingStrategy = .vad
        // Bias the decoder toward the user's custom words (initial_prompt).
        if let prompt = promptTokens(using: kit), !prompt.isEmpty {
            decodeOptions.promptTokens = prompt
        }
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
        let transcript = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if transcript.isEmpty {
            throw TranscriptionError.emptyTranscript
        }

        return transcript
    }

    /// Encode (and cache) the vocabulary prompt with the loaded tokenizer.
    /// WhisperKit filters special tokens and trims length internally; the
    /// local cap just bounds the decode-cost increase.
    private func promptTokens(using kit: WhisperKit) -> [Int]? {
        if let cachedPromptTokens { return cachedPromptTokens }
        guard let text = VocabularyPrompt.text(for: vocabulary),
              let tokenizer = kit.tokenizer else {
            cachedPromptTokens = []
            return cachedPromptTokens
        }
        let raw = tokenizer.encode(text: text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        cachedPromptTokens = Array(raw.prefix(VocabularyPrompt.maxPromptTokens))
        return cachedPromptTokens
    }
    // … loadWhisperKit / performLoad / prewarm unchanged …
}
```

Note: `promptTokens(using:)` deliberately caches `[]` when the tokenizer is unavailable *and* vocabulary is empty — but when vocabulary is non-empty and the tokenizer is nil (not yet loaded), it must NOT cache emptiness. Guard order above handles this: `kit` is the *loaded* instance (post-`loadWhisperKit()`), so `kit.tokenizer` is only nil in pathological cases; if it is nil, caching `[]` simply disables biasing for this engine instance — acceptable degradation, never a crash. (If vocabulary is empty, `VocabularyPrompt.text` returns nil and `[]` is cached — correct.)

- [ ] **Step 3: Manager passthrough.** In `TranscriptionManager`:

```swift
    /// Push a vocabulary change to the active engine (and any engine queued
    /// behind an in-flight transcription) without reloading the model.
    public func updateVocabulary(_ words: [String]) {
        let active = engine
        Task { await active.updateVocabulary(words) }
        if let pending = pendingEngine {
            Task { await pending.updateVocabulary(words) }
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

---

### Task 5: Wire `VoiceCoordinator`

**Files:**
- Modify: `Sources/JVoice/VoiceCoordinator.swift:55-73` (didSets), `:120-138` (init), `:396-397` (finishTranscription), `:528-534` (factory)

- [ ] **Step 1: Factory gains vocabulary:**

```swift
    private static func makeTranscriptionEngine(for model: WhisperModelOption, language: TranscriptionLanguage = .english, vocabulary: [String] = []) -> any TranscriptionEngine {
        #if canImport(WhisperKit)
        return WhisperKitTranscriptionEngine(model: model, language: language, vocabulary: vocabulary)
        #else
        return FileBackedTranscriptionEngine()
        #endif
    }
```

- [ ] **Step 2: All three call sites pass the current words.** `whisperModel.didSet` and `transcriptionLanguage.didSet` become:

```swift
            transcriptionManager.updateEngine(Self.makeTranscriptionEngine(for: whisperModel.modelOption, language: transcriptionLanguage, vocabulary: customWords))
```

and in `init`:

```swift
        self.transcriptionManager = TranscriptionManager(
            engine: Self.makeTranscriptionEngine(for: settingsStore.state.model, language: settingsStore.state.language, vocabulary: settingsStore.state.customWords)
        )
```

- [ ] **Step 3: Live vocabulary updates.** `customWords.didSet` becomes:

```swift
    @Published var customWords: [String] {
        didSet {
            persistSettings()
            transcriptionManager.updateVocabulary(customWords)
        }
    }
```

(Swift property observers do not fire during `init` assignments — no startup double-write.)

- [ ] **Step 4: Post-processing uses the phonetic layer.** In `finishTranscription` (line ~396):

```swift
            let userDict = TextProcessor.buildUserDictionary(from: customWords)
            let processed = removeBlankTranscriptPlaceholder(from: TextProcessor.process(transcript, mode: toneMode.appMode, extraDictionary: userDict, removeFillerWords: removeFillerWords, vocabulary: customWords))
```

- [ ] **Step 5: Build everything**

Run: `swift build && swift build --build-tests`
Expected: `Build complete!` twice

---

### Task 6: Local verification harness (actually runs)

**Files:**
- Create: `scripts/run-logic-tests.sh` (chmod +x)

XCTest cannot execute on this machine. This harness compiles the pure-logic sources plus an assertion `main` and runs them — true local verification for Tasks 1-3.

- [ ] **Step 1: Write the harness**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Local logic-test runner. `swift test` COMPILES but cannot EXECUTE tests on
# this CLT-only machine (no xctest runner; CI runs the real suite). This
# script compiles the dependency-free logic sources with a standalone
# assertion main and executes it, so TextProcessor / PhoneticMatcher /
# VocabularyPrompt changes get real local verification.
#
# Usage:  scripts/run-logic-tests.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        print("  ✗ FAIL: \(message)")
        failures += 1
    }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual == expected {
        print("  ✓ \(message)")
    } else {
        print("  ✗ FAIL: \(message) — got \(actual), expected \(expected)")
        failures += 1
    }
}

print("PhoneticMatcher.phoneticKey")
expectEqual(PhoneticMatcher.phoneticKey(for: "jvoice"), "jfs", "jvoice → jfs")
expectEqual(PhoneticMatcher.phoneticKey(for: "jayvoice"), "jfs", "jayvoice → jfs")
expectEqual(PhoneticMatcher.phoneticKey(for: "gvoice"), "jfs", "gvoice → jfs")
expectEqual(PhoneticMatcher.phoneticKey(for: "whisperkit"), "wsprkt", "whisperkit → wsprkt")
expectEqual(PhoneticMatcher.phoneticKey(for: "whispercat"), "wsprkt", "whispercat → wsprkt")
expectEqual(PhoneticMatcher.phoneticKey(for: "voice"), "fs", "voice → fs")
expect(PhoneticMatcher.phoneticKey(for: "appkit").first == "a", "leading vowel kept")

print("PhoneticMatcher.levenshtein")
expectEqual(PhoneticMatcher.levenshtein("jvoice", "jayvoice", limit: 3), 2, "jvoice↔jayvoice = 2")
expectEqual(PhoneticMatcher.levenshtein("same", "same", limit: 3), 0, "identity = 0")
expectEqual(PhoneticMatcher.levenshtein("abc", "xyz", limit: 2), 3, "early exit caps at limit+1")

print("PhoneticMatcher.correct")
expectEqual(PhoneticMatcher.correct("open jay voice settings", vocabulary: ["JVoice"]), "open JVoice settings", "jay voice → JVoice")
expectEqual(PhoneticMatcher.correct("g voice is running", vocabulary: ["JVoice"]), "JVoice is running", "g voice → JVoice")
expectEqual(PhoneticMatcher.correct("built with whisper cat", vocabulary: ["WhisperKit"]), "built with WhisperKit", "whisper cat → WhisperKit")
expectEqual(PhoneticMatcher.correct("is jay voice, ready", vocabulary: ["JVoice"]), "is JVoice, ready", "punctuation preserved")
expectEqual(PhoneticMatcher.correct("use your voice now", vocabulary: ["JVoice"]), "use your voice now", "no hijack of plain 'voice'")
expectEqual(PhoneticMatcher.correct("JVoice is great", vocabulary: ["JVoice"]), "JVoice is great", "already-correct untouched")
expectEqual(PhoneticMatcher.correct("hello there", vocabulary: []), "hello there", "empty vocabulary noop")

print("VocabularyPrompt")
expect(VocabularyPrompt.text(for: []) == nil, "empty → nil")
expectEqual(VocabularyPrompt.text(for: ["JVoice", "WhisperKit"]) ?? "", " JVoice, WhisperKit", "comma join with leading space")

print("TextProcessor integration")
expectEqual(TextProcessor.process("open jay voice now", mode: .casual, vocabulary: ["JVoice"]), "open JVoice now", "process applies phonetic pass")
expectEqual(TextProcessor.process("Open Jay Voice Settings", mode: .veryCasual, vocabulary: ["JVoice"]), "open JVoice settings.", "very casual preserves vocab casing")
expectEqual(TextProcessor.process("I Love Mac OS", mode: .veryCasual), "i love macOS.", "very casual preserves dictionary casing")
expectEqual(TextProcessor.process("hello world", mode: .formal), "Hello world.", "formal unchanged")
expectEqual(TextProcessor.process("um hello world", mode: .casual, removeFillerWords: true), "hello world", "filler removal unchanged")

if failures > 0 {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
print("\nAll logic tests passed.")
EOF

xcrun swiftc -O \
    "$REPO_ROOT/Sources/JVoice/Models/AppMode.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/TextProcessor.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/PhoneticMatcher.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/VocabularyPrompt.swift" \
    "$TMP_DIR/main.swift" \
    -o "$TMP_DIR/logic-tests"

"$TMP_DIR/logic-tests"
```

- [ ] **Step 2: Run it**

Run: `chmod +x scripts/run-logic-tests.sh && scripts/run-logic-tests.sh`
Expected: all `✓` lines, exit 0. Any `✗` → fix the implementation (or a wrong worked-example expectation in the *plan*, if hand-computation erred — phonetic keys are easy to miscompute by hand; the implementation rules are normative, the examples advisory) before proceeding.

---

### Task 7: End-to-end verification with real audio (depends on the speed plan's bench mode)

The speed plan (`2026-06-06-large-model-speed.md` Task 2) adds a hidden `--bench` CLI mode. Once both plans land:

- [ ] **Step 1: Synthesize a test clip** (macOS TTS → 16 kHz mono WAV, same format the recorder produces):

```bash
say -o /tmp/jv-vocab-test.aiff "open jay voice settings please"
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/jv-vocab-test.aiff /tmp/jv-vocab-test.wav
```

- [ ] **Step 2: Transcribe with and without vocabulary**

```bash
.build/release/JVoice --bench /tmp/jv-vocab-test.wav --model base
.build/release/JVoice --bench /tmp/jv-vocab-test.wav --model base --vocab "JVoice"
```

Expected: the `--vocab` run prints a transcript containing `JVoice` (either because biasing got it right or the phonetic layer corrected it — the bench prints both raw and processed text to show which layer fired).

---

### Self-review checklist
- [x] Layer 1 (promptTokens) — Task 4; cache invalidation on vocab change; no model reload
- [x] Layer 2 (PhoneticMatcher) — Task 2; false-positive guards tested
- [x] Layer 3 (Very Casual casing) — Task 3
- [x] Wiring (engine creation, didSet, finishTranscription) — Task 5
- [x] Local executable verification — Task 6; end-to-end — Task 7
- [x] Names consistent: `VocabularyPrompt.text(for:)`, `PhoneticMatcher.correct(_:vocabulary:)`, `updateVocabulary(_:)` across protocol/engine/manager/coordinator
- [x] No commits (session constraint)
