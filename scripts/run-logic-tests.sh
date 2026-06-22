#!/usr/bin/env bash
set -euo pipefail

# Local logic-test runner. `swift test` COMPILES but cannot EXECUTE tests on
# this CLT-only machine (no xctest/swift-testing runner; CI runs the real
# suite). This script compiles the dependency-free logic sources with a
# standalone assertion main and executes it, so TextProcessor /
# PhoneticMatcher / VocabularyPrompt changes get real local verification.
#
# NOTE: these assertions deliberately mirror a subset of the canonical
# swift-testing suite (Tests/JVoiceTests/{TextProcessor,PhoneticMatcher,
# VocabularyPrompt}Tests.swift). When you change behavior, update BOTH —
# the suite is the authority; this harness is the local smoke check.
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
expectEqual(PhoneticMatcher.correct("JVoice is so fast", vocabulary: ["JVoice"]), "JVoice is so fast", "exact word does not swallow following words")
expectEqual(PhoneticMatcher.correct("I use VS Code daily", vocabulary: ["VS Code"]), "I use VS Code daily", "multi-token exact spelling untouched")
expectEqual(PhoneticMatcher.correct("hello there", vocabulary: []), "hello there", "empty vocabulary noop")
expectEqual(PhoneticMatcher.correct("ay bee sea", vocabulary: ["AB"]), "ay bee sea", "short vocab words ignored")
expectEqual(PhoneticMatcher.correct("use dot .NET daily", vocabulary: [".NET"]), "use dot .NET daily", "TRX-01: already-correct .NET not doubled to ..NET")

print("VocabularyPrompt")
expect(VocabularyPrompt.text(for: []) == nil, "empty → nil")
expectEqual(VocabularyPrompt.text(for: ["JVoice", "WhisperKit"]) ?? "", " JVoice, WhisperKit", "comma join with leading space")

print("TextProcessor integration")
expectEqual(TextProcessor.process("open jay voice now", mode: .casual, vocabulary: ["JVoice"]), "open JVoice now", "process applies phonetic pass")
expectEqual(TextProcessor.process("Open Jay Voice Settings", mode: .veryCasual, vocabulary: ["JVoice"]), "open JVoice settings.", "very casual preserves vocab casing")
expectEqual(TextProcessor.process("use j voice now", mode: .veryCasual), "use JVoice now.", "very casual preserves dictionary casing")
expectEqual(TextProcessor.process("Hello World From Me", mode: .veryCasual), "hello world from me.", "very casual still lowercases plain text")
expectEqual(TextProcessor.process("hello world", mode: .formal), "Hello world.", "formal unchanged")
expectEqual(TextProcessor.process("Um, hello world", mode: .casual, removeFillerWords: true), "hello world", "filler removal unchanged")
expectEqual(TextProcessor.process("please use j voice with whisper kit", mode: .casual), "please use JVoice with WhisperKit", "built-in dictionary unchanged")
expectEqual(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world"), "hello world", "strip [BLANK_AUDIO] mid-string")
expectEqual(TextProcessor.stripDecoderArtifacts("a [MUSIC] b [APPLAUSE] c"), "a b c", "strip multiple bracketed sentinels")
expectEqual(TextProcessor.stripDecoderArtifacts("[BLANK_AUDIO]"), "", "all-artifact → empty")
expectEqual(TextProcessor.stripDecoderArtifacts("the quick brown fox"), "the quick brown fox", "ordinary text untouched")
expectEqual(TextProcessor.stripDecoderArtifacts("see [note] here"), "see [note] here", "lowercase brackets are NOT decoder sentinels")

print("TextProcessor.applyCorrections — TRX-01 (no double/triple substitution)")
expectEqual(
    TextProcessor.applyCorrections("use dot net daily", extraDictionary: TextProcessor.buildUserDictionary(from: [".NET"])),
    "use dot .NET daily",
    "TRX-01: .NET corrected once, no ..NET/...NET")
expectEqual(
    TextProcessor.applyCorrections("use whisperkit now"),
    "use WhisperKit now",
    "TRX-01 control: built-in dictionary idempotence preserved")
expectEqual(
    TextProcessor.applyCorrections("please use j voice with whisper kit"),
    "please use JVoice with WhisperKit",
    "TRX-01 control: built-in multi-entry corrections unchanged")
do {
    // End-to-end through process(): applyCorrections inserts ".NET", then the
    // phonetic pass must NOT re-prepend the entry's own "." (was "..NET").
    // format() may capitalize/punctuate, so assert robustly on the token.
    let e2e = TextProcessor.process(
        "use dot net daily", mode: .casual,
        extraDictionary: TextProcessor.buildUserDictionary(from: [".NET"]), vocabulary: [".NET"])
    expect(e2e.contains(".NET") && !e2e.contains("..NET"),
        "TRX-01 end-to-end: process renders exactly one leading dot, got: \(e2e)")
}

print("TextProcessor.stripDecoderArtifacts — TRX-06 (preserve legitimate bracketed tokens)")
expectEqual(TextProcessor.stripDecoderArtifacts("see figure [A] here"), "see figure [A] here", "TRX-06: [A] preserved")
expectEqual(TextProcessor.stripDecoderArtifacts("reference [I] and [II]"), "reference [I] and [II]", "TRX-06: [I] and [II] preserved")
expectEqual(TextProcessor.stripDecoderArtifacts("the answer is [X]"), "the answer is [X]", "TRX-06: [X] preserved")
expectEqual(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world"), "hello world", "TRX-06: [BLANK_AUDIO] still stripped")
expectEqual(TextProcessor.stripDecoderArtifacts("a [MUSIC] b"), "a b", "TRX-06: [MUSIC] still stripped")
expectEqual(TextProcessor.stripDecoderArtifacts("a [APPLAUSE] b"), "a b", "TRX-06: [APPLAUSE] still stripped")
expectEqual(TextProcessor.stripDecoderArtifacts("a [NOISE_1] b"), "a b", "TRX-06: [NOISE_1] still stripped")
expectEqual(TextProcessor.stripDecoderArtifacts("see figure [A] then [MUSIC] plays"), "see figure [A] then plays", "TRX-06: mixed — keep [A], strip [MUSIC]")

print("TextProcessor.extractCorrections — BLD-12 (bounded, no junk flood)")
do {
    // Full-sentence rewrite (length mismatch): the else-branch appends only
    // corrected words absent from the original, punctuation-stripped, deduped,
    // and filtered to length > 1. The result must stay bounded by the corrected
    // word count — never an unbounded flood.
    let rewrite = TextProcessor.extractCorrections(
        from: "i think we should go now",
        corrected: "Honestly, I believe that the team ought to proceed immediately at once.")
    expect(rewrite.count <= 12, "BLD-12: full-sentence rewrite bounded by corrected word count (got \(rewrite.count))")
    expect(!rewrite.contains("I"), "BLD-12: single-char tokens filtered out (count > 1 rule)")
    expect(rewrite.allSatisfy { $0.count > 1 }, "BLD-12: every extracted token has length > 1")
    expect(!rewrite.contains(""), "BLD-12: no empty tokens leak through")
}
expectEqual(
    TextProcessor.extractCorrections(from: "please send the report by friday afternoon", corrected: "please send the report"),
    [],
    "BLD-12: pure-deletion edit yields no corrections (no new words appear)")
expectEqual(
    TextProcessor.extractCorrections(from: "i use whisper kit daily", corrected: "i use WhisperKit daily"),
    ["WhisperKit"],
    "BLD-12: genuine same-length single correction is captured")

print("RepetitionGuard.strip")
let regurgVocab = ["sub agents", "claude", "li-fraumeni", "vs code"]
let regurgInput = "so basically what tariffs are is when governments put taxes on imported goods and who pays them is the people buying the item from a country that is sub agents, claude, li-fraumeni, sub agents, claude, vs code, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, la-fa, li-fraumeni, sub agents, li-fraumeni"
let regurgOut = RepetitionGuard.strip(regurgInput, vocabulary: regurgVocab)
expect(regurgOut.hasPrefix("so basically what tariffs are"), "regurgitation: real speech survives")
expect(regurgOut.contains("country"), "regurgitation: coherent prefix kept")
expect(!regurgOut.lowercased().contains("li-fraumeni"), "regurgitation: loop word removed")
expect(!regurgOut.lowercased().contains("sub agents"), "regurgitation: loop phrase removed")
expect(regurgOut.count < regurgInput.count / 2, "regurgitation: bulk stripped")
expectEqual(RepetitionGuard.strip("claude claude claude claude claude claude claude claude claude claude", vocabulary: ["claude"]), "", "all-loop → empty")
expectEqual(RepetitionGuard.strip("the meeting is tomorrow afternoon thanks thanks thanks thanks thanks thanks thanks thanks thanks", vocabulary: []), "the meeting is tomorrow afternoon", "generic repetition loop stripped")
expectEqual(RepetitionGuard.strip("I love using VS Code and Claude for my projects every single day at work", vocabulary: regurgVocab), "I love using VS Code and Claude for my projects every single day at work", "legitimate single vocab mention untouched")
expectEqual(RepetitionGuard.strip("today I paired Claude with VS Code and my sub agents to ship the feature", vocabulary: regurgVocab), "today I paired Claude with VS Code and my sub agents to ship the feature", "dense non-repetitive vocab untouched")
expectEqual(RepetitionGuard.strip("the quick brown fox jumps over the lazy dog and then runs back again to sleep", vocabulary: []), "the quick brown fox jumps over the lazy dog and then runs back again to sleep", "ordinary prose untouched")
expectEqual(RepetitionGuard.strip("sub agents claude", vocabulary: regurgVocab), "sub agents claude", "short text never stripped")
// scrub: the re-decode trigger
expect(RepetitionGuard.scrub(regurgInput, vocabulary: regurgVocab).removedRegurgitation, "scrub flags regurgitation for re-decode")
expect(!RepetitionGuard.scrub("today I paired Claude with VS Code and my sub agents to ship the feature on time", vocabulary: regurgVocab).removedRegurgitation, "scrub does NOT flag clean vocab use")
expect(RepetitionGuard.scrub("claude claude claude claude claude claude claude claude claude", vocabulary: ["claude"]).removedRegurgitation, "scrub flags all-loop")

// Real-world sample (2026-06-10): loop interleaves whole vocabulary words,
// then degenerates into a truncated "li-, li-, li-" run.
let truncSpeech = "oh these are actually all really good it's very hard to make a choice maybe we could have like a theme settings in the app where you could really just pick your theme that you wanted out of all these different options and i also want you to add one that is it's just a minimalistic one just pretty minimalistic"
let truncLoop = "sub agents, code, li-fraumeni, code, li-fraumeni, code, li-fraumeni, code, li-fraumeni, code, li-fraumeni, sub agents, code, li-fraumeni, code, li-fraumeni, code, " + Array(repeating: "li-,", count: 75).joined(separator: " ") + " li-."
let truncResult = RepetitionGuard.scrub(truncSpeech + " " + truncLoop, vocabulary: regurgVocab)
expect(truncResult.removedRegurgitation, "truncated-token loop (li-) flagged")
expectEqual(truncResult.text, truncSpeech, "truncated-token loop stripped, speech intact")

// Fuzz: hundreds of generated (coherent prefix + vocabulary loop) inputs must
// strip cleanly, and the matching single-mention controls must stay untouched.
do {
    let prefixes = [
        "so basically what tariffs are is when governments put taxes on imported goods",
        "the weather has been really strange this week with rain and then sudden sunshine",
        "when you cook a good sauce you should start with fresh tomatoes and some garlic",
        "i talked for a while about the economy and how everything is deeply connected today",
        "last summer we drove across the country and met so many kind and generous people",
    ]
    let vocabSets: [[String]] = [
        ["sub agents", "claude", "li-fraumeni", "vs code"],
        ["kubernetes", "postgres", "webhook", "oauth", "redis"],
        ["jvoice", "whisperkit", "phonetic"],
    ]
    var loopFails = 0, cleanFails = 0, cases = 0
    for prefix in prefixes {
        for vocab in vocabSets {
            for repeats in [3, 4, 5, 6, 8, 10, 12, 15] {
                var loopWords: [String] = []
                for _ in 0..<repeats { loopWords.append(contentsOf: vocab) }
                let input = prefix + " " + loopWords.joined(separator: ", ")
                let r = RepetitionGuard.scrub(input, vocabulary: vocab)
                cases += 1
                let lowerOut = r.text.lowercased()
                let anyVocabSurvives = vocab.contains { lowerOut.contains($0.lowercased()) }
                if !(r.removedRegurgitation && !anyVocabSurvives && r.text.hasPrefix(String(prefix.prefix(24)))) {
                    loopFails += 1
                }
                let clean = prefix + " using " + vocab[0] + " every day"
                let rc = RepetitionGuard.scrub(clean, vocabulary: vocab)
                if rc.removedRegurgitation || rc.text != clean { cleanFails += 1 }
            }
        }
    }
    expect(loopFails == 0, "fuzz: all \(cases) generated loops stripped (fails=\(loopFails))")
    expect(cleanFails == 0, "fuzz: all \(cases) single-mention controls untouched (fails=\(cleanFails))")
}

print("WavTail.parseHeader")
func wavHeader(format: UInt16 = 1, channels: UInt16 = 1, rate: UInt32 = 16_000, bits: UInt16 = 16, fllrBytes: Int = 0, dataSize: UInt32 = 0) -> [UInt8] {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16)
    b += le16(format) + le16(channels) + le32(rate)
    b += le32(rate * UInt32(channels) * UInt32(bits / 8)) + le16(channels * bits / 8) + le16(bits)
    if fllrBytes > 0 { b += Array("FLLR".utf8) + le32(UInt32(fllrBytes)) + [UInt8](repeating: 0, count: fllrBytes) }
    b += Array("data".utf8) + le32(dataSize)
    return b
}
let plain = wavHeader()
expectEqual(WavTail.parseHeader(plain)?.dataOffset ?? -1, 44, "plain 44-byte header")
let padded = wavHeader(fllrBytes: 4000)
expectEqual(WavTail.parseHeader(padded)?.dataOffset ?? -1, 44 + 8 + 4000, "FLLR-padded header")
expectEqual(WavTail.parseHeader(wavHeader(dataSize: 0))?.dataOffset ?? -1, 44, "stale zero data size tolerated")
expect(WavTail.parseHeader(wavHeader(rate: 44_100)) == nil, "wrong sample rate refused")
expect(WavTail.parseHeader(wavHeader(channels: 2)) == nil, "stereo refused")
expect(WavTail.parseHeader(wavHeader(format: 3)) == nil, "non-PCM refused")
expect(WavTail.parseHeader([UInt8]("RIFFxxxx".utf8)) == nil, "truncated header refused")
expectEqual(WavTail.floatSamples(([16_384, -16_384] as [Int16])[...]), [0.5, -0.5], "Int16→Float scaling")

print("ChunkPlanner")
func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}
let cfg = ChunkPlanner.Config()
expectEqual(ChunkPlanner.plan(unconsumed: tone(seconds: 10, amplitude: 0.5), config: cfg), .wait, "10s: below min → wait")
expectEqual(ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.5), config: cfg), .wait, "16s continuous speech: no pause → wait")
let speechWithPause = tone(seconds: 17, amplitude: 0.5) + tone(seconds: 1, amplitude: 0.0) + tone(seconds: 2, amplitude: 0.5)
if case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: speechWithPause, config: cfg) {
    expect(at >= 17 * 16_000 && at <= 18 * 16_000, "cut lands inside the 17-18s pause (at=\(at))")
    expect(!silent, "speech chunk not marked silent")
} else {
    expect(false, "pause after min → cut")
}
if case let .cut(at, _) = ChunkPlanner.plan(unconsumed: tone(seconds: 26, amplitude: 0.5), config: cfg) {
    expect(at >= 15 * 16_000 && at <= 25 * 16_000, "26s no pause → forced cut within [min,max] (at=\(at))")
} else {
    expect(false, "26s continuous → forced cut")
}
if case let .cut(_, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.0), config: cfg) {
    expect(silent, "16s of silence → silent chunk (dropped, not transcribed)")
} else {
    expect(false, "16s silence still produces a cut")
}
expect(ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.0), config: cfg), "isSilent: zeros")
expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.5), config: cfg), "isSilent: speech-level tone")

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
    "$REPO_ROOT/Sources/JVoice/Services/RepetitionGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/VocabularyPrompt.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/WavTail.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/ChunkPlanner.swift" \
    "$TMP_DIR/main.swift" \
    -o "$TMP_DIR/logic-tests"

"$TMP_DIR/logic-tests"
