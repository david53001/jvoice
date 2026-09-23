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
expectEqual(TextProcessor.process("J-Voice handles the dictation", mode: .casual), "JVoice handles the dictation", "hyphenated 'J-Voice' (what Whisper emits under a cased prompt) → JVoice")

print("TextProcessor .code tone (verbatim — trims whitespace only, no caps/punctuation changes)")
expectEqual(TextProcessor.format("  const x = 5;  ", mode: .code), "const x = 5;", "code: trims surrounding whitespace only")
expectEqual(TextProcessor.process("MyClass.someMethod()", mode: .code), "MyClass.someMethod()", "code: preserves casing + symbols as spoken")
expectEqual(TextProcessor.process("hello world", mode: .code), "hello world", "code: no capitalization, no terminal period")
expectEqual(TextProcessor.process("let x = 5", mode: .code, removeFillerWords: true), "let x = 5", "code: filler-removal harmless on code")

print("DeveloperTerms — pack + augment")
expectEqual(DeveloperTerms.map["node js"] ?? "", "Node.js", "node js → Node.js")
expectEqual(DeveloperTerms.map["nodejs"] ?? "", "Node.js", "nodejs → Node.js")
expectEqual(DeveloperTerms.map["type script"] ?? "", "TypeScript", "type script → TypeScript")
expectEqual(DeveloperTerms.map["c sharp"] ?? "", "C#", "c sharp → C#")
expectEqual(DeveloperTerms.map["vs code"] ?? "", "VS Code", "vs code → VS Code")
expectEqual(DeveloperTerms.map["json"] ?? "", "JSON", "json → JSON")
expectEqual(DeveloperTerms.map["supabase"] ?? "", "Supabase", "supabase deduped → Supabase (C# last-wins)")
// Kept homophones / near-collisions (same call as "jason").
expectEqual(DeveloperTerms.map["jason"] ?? "", "JSON", "jason → JSON (kept homophone)")
expectEqual(DeveloperTerms.map["groq"] ?? "", "Groq", "groq → Groq (kept, NOT grok)")
expectEqual(DeveloperTerms.map["gemini"] ?? "", "Gemini", "gemini → Gemini (safe both senses)")
expectEqual(DeveloperTerms.map["mistral"] ?? "", "Mistral", "mistral → Mistral (kept)")
// Ambiguous English words are deliberately EXCLUDED (protect ordinary dictation).
let devExclusions = ["cursor","bolt","continue","render","railway","remix","warp","astro","svelte","bun","pinecone","chroma","cohere","perplexity","grok","drizzle","lovable","llama"]
for w in devExclusions { expect(DeveloperTerms.map[w] == nil, "excluded ambiguous word absent: \(w)") }
// augment lays the pack UNDERNEATH base (base wins); pack-only keys survive.
expectEqual(DeveloperTerms.augment([:])["vs code"] ?? "", "VS Code", "augment keeps pack entries")
expectEqual(DeveloperTerms.augment(["node js": "CustomNode"])["node js"] ?? "", "CustomNode", "augment: base value wins over pack")
// End-to-end through process(): pack corrections applied, built-in still wins.
expectEqual(TextProcessor.process("i use node js and type script daily", mode: .casual, extraDictionary: DeveloperTerms.augment([:])), "i use Node.js and TypeScript daily", "dev pack applied in process")
expectEqual(TextProcessor.process("send me the jason file", mode: .casual, extraDictionary: DeveloperTerms.augment([:])), "send me the JSON file", "jason → JSON in process")

print("StatsStore.estimatedMinutesSaved (40-wpm typing baseline)")
do {
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    let store = StatsStore(defaults: d)
    expectEqual(store.estimatedMinutesSaved, 0, "no words → 0 minutes saved")
    // 40 words spoken in 6s: typing = 40/40 = 1 min; spoken = 6/60 = 0.1 min; saved = 0.9.
    store.record(words: 40, durationSeconds: 6)
    expect(abs(store.estimatedMinutesSaved - 0.9) < 1e-9, "40 words in 6s → 0.9 min saved (got \(store.estimatedMinutesSaved))")
    d.removePersistentDomain(forName: suite)
}
do {
    // Slow dictation floors at 0: 10 words in 60s → typing 0.25 min < spoken 1 min.
    let suite = "jvoice.test.stats.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    let store = StatsStore(defaults: d)
    store.record(words: 10, durationSeconds: 60)
    expectEqual(store.estimatedMinutesSaved, 0, "slow dictation floors saved at 0")
    d.removePersistentDomain(forName: suite)
}

print("AppModeResolver")
expect(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: [], enabled: false) == nil, "disabled → nil")
expect(AppModeResolver.resolve(bundleId: nil, userRules: [], enabled: true) == nil, "nil bundleId → nil")
expect(AppModeResolver.resolve(bundleId: "   ", userRules: [], enabled: true) == nil, "blank bundleId → nil")
expectEqual(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: [], enabled: true), .code, "VS Code → code (built-in)")
expectEqual(AppModeResolver.resolve(bundleId: "com.apple.Terminal", userRules: [], enabled: true), .code, "Terminal → code (built-in)")
expectEqual(AppModeResolver.resolve(bundleId: "com.jetbrains.pycharm", userRules: [], enabled: true), .code, "JetBrains wildcard → code")
expectEqual(AppModeResolver.resolve(bundleId: "com.apple.dt.Xcode", userRules: [], enabled: true), .code, "Xcode → code")
expect(AppModeResolver.resolve(bundleId: "com.apple.Safari", userRules: [], enabled: true) == nil, "non-code app → nil")
// User rules win, in order, case-insensitive substring of the bundle id.
expectEqual(AppModeResolver.resolve(bundleId: "com.tinyspeck.slackmacgap", userRules: [AppModeRule(appMatch: "slack", mode: .formal)], enabled: true), .formal, "user rule substring match")
expectEqual(AppModeResolver.resolve(bundleId: "com.microsoft.VSCode", userRules: [AppModeRule(appMatch: "VSCode", mode: .veryCasual)], enabled: true), .veryCasual, "user rule wins over built-in code app (case-insensitive)")
expectEqual(AppModeResolver.resolve(bundleId: "com.apple.Terminal", userRules: [AppModeRule(appMatch: "safari", mode: .formal), AppModeRule(appMatch: "terminal", mode: .veryCasual)], enabled: true), .veryCasual, "first matching user rule in list order")

print("TextProcessor.removeDisfluencies — m-trailing hesitation fillers (uhm/erm)")
expectEqual(TextProcessor.removeDisfluencies("uhm, I was thinking"), "I was thinking", "leading 'uhm' removed")
expectEqual(TextProcessor.removeDisfluencies("I was uhm thinking"), "I was thinking", "mid-sentence 'uhm' removed")
expectEqual(TextProcessor.removeDisfluencies("erm, I think so"), "I think so", "leading 'erm' removed")
expectEqual(TextProcessor.removeDisfluencies("I was uhmm really erm sure"), "I was really sure", "lengthened uhmm/erm removed")
// Regression guards: real -rm/-hm words and existing fillers must be untouched.
expectEqual(TextProcessor.removeDisfluencies("the term was firm and warm"), "the term was firm and warm", "real -rm words preserved")
expectEqual(TextProcessor.removeDisfluencies("Um, I was thinking"), "I was thinking", "existing 'um' still removed")
expectEqual(TextProcessor.removeDisfluencies("The error was clear"), "The error was clear", "'er' inside 'error' preserved")

expectEqual(TextProcessor.stripDecoderArtifacts("hello [BLANK_AUDIO] world"), "hello world", "strip [BLANK_AUDIO] mid-string")
expectEqual(TextProcessor.stripDecoderArtifacts("a [MUSIC] b [APPLAUSE] c"), "a b c", "strip multiple bracketed sentinels")
expectEqual(TextProcessor.stripDecoderArtifacts("[BLANK_AUDIO]"), "", "all-artifact → empty")
expectEqual(TextProcessor.stripDecoderArtifacts("the quick brown fox"), "the quick brown fox", "ordinary text untouched")
expectEqual(TextProcessor.stripDecoderArtifacts("see [note] here"), "see [note] here", "lowercase brackets are NOT decoder sentinels")

print("TextProcessor.applyCorrections — TRX-01 (no double/triple substitution)")
expectEqual(
    TextProcessor.applyCorrections("We use .NET daily.", extraDictionary: TextProcessor.buildUserDictionary(from: [".NET"])),
    "We use .NET daily.",
    "TRX-01: .NET kept once, no ..NET/...NET")
expectEqual(
    TextProcessor.applyCorrections("use dot net daily", extraDictionary: DeveloperTerms.augment(TextProcessor.buildUserDictionary(from: [".NET"]))),
    "use .NET daily",
    "TRX-01: dot net → .NET inserted once")
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

// ---- BEGIN text-processing fixes 2026-09-23 (TextProcessor / PhoneticMatcher / DeveloperTerms) ----
print("Text-processing fixes 2026-09-23 — the default pipeline (Formal, filler removal on, dev terms on, math on)")
do {
    let words = ["sub agents", "AISB", "Li-Fraumeni", "Vercel", "Ollama"]
    func pipeline(_ t: String, mode: AppMode = .formal, words: [String] = words) -> String {
        let extra = DeveloperTerms.augment(TextProcessor.buildUserDictionary(from: words))
        let styled = TextProcessor.removeWhisperHallucinations(
            TextProcessor.process(t, mode: mode, extraDictionary: extra, removeFillerWords: true, vocabulary: words))
        return MathSpeech.convert(styled)
    }
    // 1. The plain lower-cased custom word is a correction key again.
    expectEqual(TextProcessor.buildUserDictionary(from: ["VS Code"])["vs code"] ?? "", "VS Code", "user dict keeps 'vs code'")
    expectEqual(TextProcessor.process("I use claude every day", mode: .casual, extraDictionary: TextProcessor.buildUserDictionary(from: ["Claude"])), "I use Claude every day", "user dict fixes casing drift")
    // 3. A multi-token window never swallows the word in front.
    for s in ["I deployed 2 Vercel apps today.", "Spawn six sub agents now.", "The price is $20 Vercel credit.",
              "The power of Ollama is privacy.", "Is it Claude or Ollama?", "So sub agents do the heavy lifting."] {
        expectEqual(pipeline(s), s, "neighbour kept: \(s)")
    }
    expectEqual(pipeline("run it on olama"), "Run it on Ollama.", "misspelling corrected, 'on' kept")
    expectEqual(PhoneticMatcher.correct("Hey Jay, voice memos", vocabulary: ["JVoice"]), "Hey Jay, voice memos", "no join across a comma")
    // 4. Two edits + a different sound key is a different word; singular ≠ plural; short-word runs ≠ acronym.
    for s in ["Read the next verse aloud.", "We had a verbal agreement.", "She is well versed in Greek.",
              "The vessel left the harbor.", "Obama gave a speech today.", "Such agents are rare in practice.",
              "Spawn a sub agent for this task.", "If a is b and b is c then a is c."] {
        expectEqual(pipeline(s), s, "not a custom word: \(s)")
    }
    expectEqual(PhoneticMatcher.correct("open jay voice settings", vocabulary: ["JVoice"]), "open JVoice settings", "jay voice still → JVoice")
    expectEqual(PhoneticMatcher.correct("built with whisper cat", vocabulary: ["WhisperKit"]), "built with WhisperKit", "whisper cat still → WhisperKit")
    expectEqual(PhoneticMatcher.correct("deploy to versel", vocabulary: ["Vercel"]), "deploy to Vercel", "one-edit mishearing still corrected")
    // 5. Possessives survive.
    for s in ["I like Vercel's new dashboard.", "Ollama's API is local.", "Vercel’s pricing changed."] {
        expectEqual(pipeline(s), s, "possessive kept: \(s)")
    }
    expectEqual(PhoneticMatcher.correct("versel's dashboard", vocabulary: ["Vercel"]), "Vercel's dashboard", "possessive kept through a correction")
    // 6. Everyday English is not a pack/built-in key.
    for s in ["Can you check my SQL query before lunch?", "There is no SQL in this module.", "We want a fast API for the mobile team.",
              "I had a restful weekend at the lake.", "I spoke with Uri about the budget.", "My favorite keyboard shortcuts are simple."] {
        expectEqual(pipeline(s), s, "everyday English kept: \(s)")
    }
    for k in ["my sql", "no sql", "fast api", "restful", "uri"] { expect(DeveloperTerms.map[k] == nil, "dev pack excludes '\(k)'") }
    expect(TextProcessor.correctionDictionary["keyboard shortcuts"] == nil, "built-in excludes 'keyboard shortcuts'")
    // 7. Filler removal keeps real words.
    for s in ["She rushed to the ER last night.", "To err is human.", "Uh-oh, the build broke again.",
              "Uh-huh, that works for me.", "Mm-hmm, sounds good.", "He works at UM now."] {
        expectEqual(pipeline(s), s, "real word kept: \(s)")
    }
    expectEqual(pipeline("Um, I think so, uh, yes."), "I think so, yes.", "real fillers still removed")
    expectEqual(pipeline("Errr, maybe later."), "Maybe later.", "drawn-out 'errr' still a filler")
    // 8. Dot-prefixed custom words never gain dots.
    expectEqual(pipeline("We use .NET daily.", words: [".NET"]), "We use .NET daily.", ".NET kept")
    expectEqual(pipeline("We use .NET daily.", mode: .veryCasual, words: [".NET"]), "we use .NET daily.", ".NET kept in Very Casual")
    expectEqual(pipeline("Copy the .env file first.", words: [".env"]), "Copy the .env file first.", ".env kept")
    expectEqual(PhoneticMatcher.correct("use .nett daily", vocabulary: [".NET"]), "use .NET daily", "fuzzy .nett → .NET, not ..NET")
    // 9. Very Casual keeps thousands separators.
    expectEqual(TextProcessor.process("We raised $1,000,000 last year.", mode: .veryCasual), "we raised $1,000,000 last year.", "$1,000,000 intact")
    expectEqual(TextProcessor.process("1,,2 and 3 , 4", mode: .veryCasual), "1, 2 and 3, 4.", "clause commas next to digits still tidied")
    // 10. Formal does not add a period after a closed sentence.
    for s in ["He said \"hello.\"", "Here are the steps:", "Wait for it…", "It was fine (mostly.)"] {
        expectEqual(TextProcessor.process(s, mode: .formal), s, "already terminated: \(s)")
    }
    expectEqual(TextProcessor.process("She said “yes”", mode: .formal), "She said “yes”.", "unterminated quote still gets a period")
}
// ---- END text-processing fixes 2026-09-23 ----

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

print("TextProcessor.removeWhisperHallucinations — tone-mode punctuation consistency")
// The Casual tone formatter strips terminal .!? BEFORE this filter runs, so a
// whole-transcript YouTube-style hallucination must be caught with OR without
// its trailing punctuation. The author already enumerated both "Bye."/"Bye!"
// and "Thanks for watching!"/"Thanks for watching." — the bare form the Casual
// formatter produces was the gap.
expectEqual(TextProcessor.removeWhisperHallucinations("Thanks for watching!"), "", "punctuated hallucination stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("Thanks for watching"), "", "Casual (unpunctuated) hallucination stripped too")
expectEqual(TextProcessor.removeWhisperHallucinations("Bye"), "", "unpunctuated 'Bye' stripped (matches existing 'Bye.'/'Bye!')")
expectEqual(TextProcessor.removeWhisperHallucinations("OK."), "OK.", "valid short utterance preserved, punctuation intact")
expectEqual(TextProcessor.removeWhisperHallucinations("Hi"), "Hi", "valid short utterance preserved")
expectEqual(TextProcessor.removeWhisperHallucinations("Thanks for watching the fireworks tonight"), "Thanks for watching the fireworks tonight", "longer real sentence untouched")

print("TextProcessor.removeWhisperHallucinations — all-symbol silence artifacts")
// A transcript made ENTIRELY of punctuation/symbols is never dictated speech
// (real speech always carries a letter or digit). The old guard only matched
// the ASCII subset ".,;:!? ", so non-ASCII silence artifacts leaked.
expectEqual(TextProcessor.removeWhisperHallucinations("-"), "", "lone dash stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("…"), "", "lone ellipsis stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("— —"), "", "em-dash run stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("♪ ♪ ♪"), "", "Whisper music-note run stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("."), "", "existing lone period still stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("$20 is the price"), "$20 is the price", "symbols mixed with words/digits preserved")
expectEqual(TextProcessor.removeWhisperHallucinations("OK."), "OK.", "letters present → preserved")

print("TextProcessor.removeWhisperHallucinations — phrase wrapped in surrounding marks")
// Whisper decorates hallucinated phrases with LEADING punctuation (a dash, an
// ellipsis) or wraps them in music notes; the trailing-only trim missed these.
expectEqual(TextProcessor.removeWhisperHallucinations("- Thanks for watching"), "", "leading dash before phrase stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("... Bye"), "", "leading ellipsis before phrase stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("♪ Thanks for watching ♪"), "", "music-note-wrapped phrase stripped")
// Regression guards: real content with the same leading marks is preserved.
expectEqual(TextProcessor.removeWhisperHallucinations("Thanks for watching!"), "", "plain phrase still stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("- send the report by Friday"), "- send the report by Friday", "leading dash on real content preserved")
expectEqual(TextProcessor.removeWhisperHallucinations("Thanks for the help, send the file"), "Thanks for the help, send the file", "longer real sentence untouched")

print("TextProcessor.removeWhisperHallucinations — sub-second 'you' fingerprint (zero-latency port)")
// Whisper answers < 1 s of hum with exactly the bare lowercase token "you";
// a real one-word reply is capitalized + punctuated by Whisper, so it must survive.
expectEqual(TextProcessor.removeWhisperHallucinations("you"), "", "bare lowercase 'you' stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("  you \n"), "", "whitespace-wrapped bare 'you' stripped")
expectEqual(TextProcessor.removeWhisperHallucinations("You."), "You.", "capitalized + punctuated one-word reply preserved")
expectEqual(TextProcessor.removeWhisperHallucinations("You"), "You", "capitalized 'You' preserved (case-sensitive match)")
expectEqual(TextProcessor.removeWhisperHallucinations("you."), "you.", "punctuated lowercase preserved (unpunctuated match only)")
expectEqual(TextProcessor.removeWhisperHallucinations("you know what I mean"), "you know what I mean", "'you' inside a real sentence preserved")

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
// Spoken maths repeats operands/operators legitimately — never a "loop" (it was
// deleted from the paste AND cost a second, unprompted decode).
for maths in ["and then it's 26 x 26 x 26 x 10 x 10 x 10",
              "and then it's 26 times 26 times 26 times 10 times 10 times 10",
              "So the answer is minus 3 minus 3 minus 3 minus 3",
              "1 over 2 plus 1 over 4 plus 1 over 8 plus 1 over 16",
              "2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 is 256"] {
    let r = RepetitionGuard.scrub(maths, vocabulary: regurgVocab)
    expect(!r.removedRegurgitation && r.text == maths, "maths repetition untouched: \"\(maths)\"")
}
expectEqual(RepetitionGuard.strip("and then it's " + String(repeating: "26 x ", count: 20), vocabulary: []), "and then it's", "sustained numeric decoder loop still stripped")
expectEqual(RepetitionGuard.strip("the total is " + String(repeating: "10, ", count: 20), vocabulary: []), "the total is", "sustained number-only loop still stripped")
expectEqual(RepetitionGuard.strip("see " + String(repeating: "page 1 of 10, ", count: 40), vocabulary: []), "see", "long-cycle maths loop stripped (trailing exact-phrase net)")
expectEqual(RepetitionGuard.strip("cut off " + String(repeating: "page 1 of 10, ", count: 7) + "page 1", vocabulary: []), "cut off", "phrase loop cut off mid-cycle stripped")
expect(!RepetitionGuard.scrub("five letters so 26 times 26 times 26 times 26 times 26 times 26", vocabulary: []).removedRegurgitation, "dictated 26^6 (5 phrase repeats) untouched")
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

print("PhraseLoopGuard — a loop in the MIDDLE of a transcript (mirrors Tests/JVoiceTests/PhraseLoopGuardTests.swift)")
do {
    func occurrences(_ needle: String, _ text: String) -> Int { text.lowercased().components(separatedBy: needle.lowercased()).count - 1 }
    let sentenceLoop = "After lunch we walked down to the harbor, and the captain told us that "
        + String(repeating: "The ferry leaves at noon. ", count: 16)
        + "Then we bought our tickets and waited on the pier for about an hour."
    let s = PhraseLoopGuard.collapse(sentenceLoop)
    expect(s.foundLoop && occurrences("ferry leaves at noon", s.text) == 1, "sentence ×16 mid-transcript collapsed to one")
    expect(s.text.hasPrefix("After lunch we walked") && s.text.hasSuffix("for about an hour."), "speech before and after the loop kept")
    expect(!RepetitionGuard.scrub(sentenceLoop, vocabulary: []).removedRegurgitation, "(the trailing-only RepetitionGuard misses it)")
    let clause = "the new library downtown has a huge reading room and i used to go there every weekend but now i work so"
    let clauseLoop = "okay so about the city " + String(repeating: clause + " ", count: 6) + "anyway that is my update for today and i will call you tomorrow"
    expectEqual(PhraseLoopGuard.collapse(clauseLoop).text, "okay so about the city " + clause + " anyway that is my update for today and i will call you tomorrow", "22-token clause ×6 collapsed (the Windows §7 #45 shape)")
    let vocabLoop = "we deployed the new build on friday and then " + String(repeating: "sub agents, AISB, Li-Fraumeni, Vercel, Ollama, ", count: 5) + "after that everyone packed up their laptops and went home early for the long weekend"
    expect(PhraseLoopGuard.hasLoop(vocabLoop) && !RepetitionGuard.scrub(vocabLoop, vocabulary: ["sub agents", "AISB", "Li-Fraumeni", "Vercel", "Ollama"]).removedRegurgitation, "mid-transcript vocabulary regurgitation: caught here, missed by RepetitionGuard")
    for maths in ["and then it's 26 x 26 x 26 x 10 x 10 x 10",
                  "and then it's 26 times 26 times 26 times 10 times 10 times 10",
                  "So the answer is minus 3 minus 3 minus 3 minus 3",
                  "1 over 2 plus 1 over 4 plus 1 over 8 plus 1 over 16",
                  "2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 is 256",
                  "ten times ten times ten times ten is ten thousand",
                  "five letters so 26 times 26 times 26 times 26 times 26 times 26",
                  "so 2 to the tenth is 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 which is 1024",
                  "1 over 2 plus 1 over 2 plus 1 over 2 plus 1 over 2 plus 1 over 2 equals 5 over 2",
                  "count it out 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4 and then the chorus starts"] {
        let embedded = "okay for the homework question " + maths + " and then we move on to the next problem on the sheet"
        expect(PhraseLoopGuard.collapse(maths).text == maths && PhraseLoopGuard.collapse(embedded).text == embedded, "dictated maths untouched: \"\(maths)\"")
    }
    for emphasis in ["No, no, no, no, that is not what I asked for at all, please read it again.",
                     "Come on, come on, come on, come on, we are going to be late for the train again.",
                     "Ha ha ha ha ha ha ha ha, that was the funniest thing I have heard all week long.",
                     "I love you, I love you, I love you, I love you, said the little card on the table."] {
        expect(!PhraseLoopGuard.hasLoop(emphasis), "emphasis untouched: \"\(emphasis.prefix(30))…\"")
    }
    expect(PhraseLoopGuard.hasLoop("we said " + String(repeating: "we need more chairs ", count: 4) + "for the party tonight"), "4 tokens ×4 = 16 → loop")
    expect(!PhraseLoopGuard.hasLoop("we said " + String(repeating: "more chairs please ", count: 5) + "for the party tonight"), "3 tokens ×5 = 15 → not")
    expect(!PhraseLoopGuard.hasLoop("the total is " + String(repeating: "minus 3 ", count: 11) + "and that is the whole bill"), "maths phrase ×11 → not")
    expectEqual(PhraseLoopGuard.collapse("the total is " + String(repeating: "minus 3 ", count: 12) + "and that is the whole bill").text, "the total is minus 3 and that is the whole bill", "maths phrase ×12 → collapsed")
    expectEqual(PhraseLoopGuard.collapse("Hold on a second. hold on a second, HOLD ON A SECOND hold on a second!").text, "Hold on a second.", "case/punctuation-insensitive, first kept verbatim")
    expectEqual(PhraseLoopGuard.collapse(String(repeating: "wait for me ", count: 6) + "wait for").text, "wait for me wait for", "trailing partial repeat stays")
    let words33 = (1...33).map { "w\($0)" }.joined(separator: " ")
    expect(!PhraseLoopGuard.hasLoop(Array(repeating: words33, count: 4).joined(separator: " ")), "33-token period above the cap → not detected")
    expectEqual(PhraseLoopGuard.resolve(looped: sentenceLoop, witness: "the ferry leaves at noon"), "the ferry leaves at noon", "resolve prefers the unprompted witness")
    expect(occurrences("ferry leaves at noon", PhraseLoopGuard.resolve(looped: sentenceLoop, witness: "  ")) == 1, "resolve with an empty witness collapses the primary")

    // Fuzz: prefix + phrase ×R + suffix. R ≥ 4 with ≥ 16 tokens must collapse to
    // exactly prefix + phrase + suffix; R = 3 must come back untouched.
    let prefixes = ["so yesterday i went over to the old market near the river",
                    "the quarterly report is mostly finished but the charts still need work",
                    "when we arrived at the cabin the lights were off and nobody answered"]
    let suffixes = ["and after that we all went back home to rest before dinner",
                    "which honestly surprised everyone who had been waiting there since morning"]
    let pool = "remember the blue kettle sitting beside our kitchen window whenever grandmother visited during winter holidays we laughed about stories nobody believed except little cousins wearing bright yellow raincoats outside every single summer".split(separator: " ").map(String.init)
    var caught = 0, loops = 0, controlsKept = 0, controls = 0
    for p in prefixes { for s in suffixes { for len in [4, 5, 6, 8, 12, 21, 32] { for r in [3, 4, 6, 10, 16] {
        let phrase = pool[0..<len].joined(separator: " ")
        let input = p + " " + Array(repeating: phrase, count: r).joined(separator: " ") + " " + s
        let result = PhraseLoopGuard.collapse(input)
        if r >= 4 { loops += 1; if result.text == p + " " + phrase + " " + s { caught += 1 } }
        else { controls += 1; if !result.foundLoop && result.text == input { controlsKept += 1 } }
    } } } }
    expect(caught == loops, "fuzz: \(caught)/\(loops) mid-transcript loops collapsed exactly")
    expect(controlsKept == controls, "fuzz: \(controlsKept)/\(controls) 3-repeat controls untouched")
    // Maths repeats under the maths threshold, embedded in prose, never move.
    var mathsKept = 0, mathsCases = 0
    for unit in ["x times", "minus 3", "2 x", "plus 1", "26 times", "1 over 2 plus", "a squared plus"] { for k in 2...11 {
        let input = prefixes[0] + " " + Array(repeating: unit, count: k).joined(separator: " ") + " 5 " + suffixes[0]
        mathsCases += 1
        if PhraseLoopGuard.collapse(input).text == input { mathsKept += 1 }
    } }
    expect(mathsKept == mathsCases, "fuzz: \(mathsKept)/\(mathsCases) embedded maths repeats (×2–×11) untouched")
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
expectEqual(ChunkPlanner.trailingSilenceSamples(tone(seconds: 1, amplitude: 0.5) + tone(seconds: 0.5, amplitude: 0), config: cfg), Int(0.5 * 16_000), "trailingSilence: 0.5 s silence after speech → 0.5 s")
expectEqual(ChunkPlanner.trailingSilenceSamples(tone(seconds: 1, amplitude: 0.5), config: cfg), 0, "trailingSilence: speech to the end → 0")
expectEqual(ChunkPlanner.trailingSilenceSamples(tone(seconds: 0.7, amplitude: 0), config: cfg), Int(0.7 * 16_000), "trailingSilence: all silence → everything")
expectEqual(ChunkPlanner.trailingSilenceSamples(tone(seconds: 1, amplitude: 0.5) + tone(seconds: 0.4, amplitude: 0.002), config: cfg), Int(0.4 * 16_000), "trailingSilence: below the absolute floor counts as silence")
expectEqual(ChunkPlanner.trailingSilenceSamples(tone(seconds: 1, amplitude: 0.5) + tone(seconds: 0.4, amplitude: 0.02), config: cfg), 0, "trailingSilence: quiet-but-audible tail is NOT silence")
expectEqual(ChunkPlanner.trailingSilenceSamples([], config: cfg), 0, "trailingSilence: empty → 0")
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
// Earliest-qualifying-pause cut: with TWO sub-threshold pauses, cut at the
// EARLIER (shallower) pause A, not the later (deeper/quietest) pause B — emits
// the streaming chunk sooner. Pause A (amp 0.02 → ~0.014 RMS) is below the
// relative threshold (~0.035) but louder than the silent pause B (0 RMS).
let twoPause = tone(seconds: 16, amplitude: 0.5)
    + tone(seconds: 1, amplitude: 0.02)
    + tone(seconds: 2, amplitude: 0.5)
    + tone(seconds: 1, amplitude: 0.0)
    + tone(seconds: 1, amplitude: 0.5)
if case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: twoPause, config: cfg) {
    expect(at >= 16 * 16_000 && at <= 17 * 16_000, "cut lands in the EARLIER pause A (at=\(at)), not deeper later pause B")
    expect(!silent, "earliest-pause chunk still holds speech → not silent")
} else {
    expect(false, "two-pause input past min → cut")
}

print("NonSpeechAnnotation — caption-only decodes are no-speech")
for raw in ["[BLANK_AUDIO]", "[Music]", "[Sigh]", "[Applause]", "[MUSIC]", "(wind blowing)", "(door closes)",
            "(speaking foreign language)", "  [BLANK_AUDIO]  ", "[Music] (applause)", "[Sigh].", "(...)",
            "*coughs*", "*music*", "*soft music*.", "* sighs *", "*music* *applause*", "[BLANK_AUDIO] *music*"] {
    expect(NonSpeechAnnotation.isAnnotationOnly(raw), "caption only: \(raw)")
    expectEqual(NonSpeechAnnotation.reduce(raw), "", "reduced to empty: \(raw)")
}

print("NonSpeechAnnotation — real speech containing (), [] or * pairs is kept")
for raw in ["you", "Please check the build again.", "Thanks.", "music", "the (optional) flag",
            "Set the (optional) flag before you run it.", "I said (quietly) no.", "The index is [3] here.",
            "(side note) call the bank", "*emphasis* here", "I *really* like this idea.",
            "multiply 2 * 3 * 4", "press the * key"] {
    expect(!NonSpeechAnnotation.isAnnotationOnly(raw), "not a caption: \(raw)")
    expectEqual(NonSpeechAnnotation.reduce(raw), raw, "kept verbatim: \(raw)")
}
expect(!NonSpeechAnnotation.isAnnotationOnly(""), "empty string is not an annotation")
expectEqual(NonSpeechAnnotation.reduce(""), "", "empty string reduces to itself")
expectEqual(NonSpeechAnnotation.reduce(TextProcessor.stripDecoderArtifacts("[BLANK_AUDIO] [Sigh]")), "", "composes with stripDecoderArtifacts")
expectEqual(NonSpeechAnnotation.reduce(TextProcessor.stripDecoderArtifacts("ship it [BLANK_AUDIO] (maybe)")), "ship it (maybe)", "mid-sentence group survives the composition")

print("SilenceHallucinationGate.shouldVerify — quiet audio with text gets a witness")
let quietCases: [(Float, String)] = [
    (0.0000, "see you soon."), (0.0001, "you"), (0.0003, "and that is all for today, and that is all for today."),
    (0.0196, "and then the Vercel,"), (0.0217, "and the rest of the road"), (0.0409, "The"),
    (0.0300, "can you move the meeting to Friday"),
]
for (rms, text) in quietCases {
    expect(SilenceHallucinationGate.shouldVerify(peakRMS: rms, prompted: text), "verify at \(rms): \(text)")
}
let loudCases: [(Float, String)] = [
    (0.1049, "four digits then two letters"), (0.2522, "the first answer is eight choose three"),
    (0.0500, "exactly at the trigger is not quiet"),
]
for (rms, text) in loudCases {
    expect(!SilenceHallucinationGate.shouldVerify(peakRMS: rms, prompted: text), "no witness at \(rms): \(text)")
}
expect(!SilenceHallucinationGate.shouldVerify(peakRMS: 0, prompted: ""), "empty transcript → no witness")
expect(!SilenceHallucinationGate.shouldVerify(peakRMS: 0, prompted: "   "), "blank transcript → no witness")
expect(SilenceHallucinationGate.shouldVerify(peakRMS: .nan, prompted: "see you soon."), "NaN level counts as quiet")

print("SilenceHallucinationGate.resolve — the witness decides")
let gateVocab = ["Vercel", "Ollama", "sub agents"]
for (prompted, witness) in [("see you soon.", ""), ("you", ""), ("Vercel", "   "), ("The", "...")] {
    expectEqual(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab), "", "empty witness rejects \"\(prompted)\"")
}
for (prompted, witness) in [("and the rest of the road", "so"), ("The", "A"), ("Vercel, Olla, Vercel", "and so on")] {
    expectEqual(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab), "", "no shared word rejects \"\(prompted)\" vs \"\(witness)\"")
}
for (prompted, witness) in [("Hey, what's new?", "Hey, what's new?"),
                            ("Move the meeting to Friday", "move the meeting to friday"),
                            ("We need 3 more chairs", "We need three more chairs"),
                            ("We pushed the preview build to Vercel.", "We pushed the preview build to Versil."),
                            ("The main agent starts two sub agents.", "The main agent starts two sub-agents.")] {
    expectEqual(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab), prompted, "agreeing witness keeps \"\(prompted)\"")
}
expectEqual(SilenceHallucinationGate.resolve(prompted: "Vercel.", witness: "Versil.", vocabulary: gateVocab), "Vercel.", "one-word custom word kept via its sound-alike")
expectEqual(SilenceHallucinationGate.resolve(prompted: "Ollama", witness: "Olima", vocabulary: gateVocab), "Ollama", "Olima → Ollama agrees")
expectEqual(SilenceHallucinationGate.resolve(prompted: "Vercel.", witness: "Versil.", vocabulary: []), "", "without the vocabulary the sound-alike would not agree")

print("SilenceHallucinationGate.peakWindowRMS — the rejector's measure")
let gateQuiet = [Int16](repeating: 150, count: 16_000)
let gateAudible = [Int16](repeating: 170, count: 16_000)
expect(ChunkPlanner.isSilent(gateQuiet) && !ChunkPlanner.isSilent(gateAudible), "fixtures straddle the 0.005 floor")
expect(SilenceHallucinationGate.peakWindowRMS(WavTail.floatSamples(gateQuiet[...])) < ChunkPlanner.Config().silenceRMSFloor, "below the floor on the same scale")
expect(SilenceHallucinationGate.peakWindowRMS(WavTail.floatSamples(gateAudible[...])) >= ChunkPlanner.Config().silenceRMSFloor, "above the floor on the same scale")
expectEqual(SilenceHallucinationGate.peakWindowRMS([]), 0, "empty → 0")
let gateBurst = [Float](repeating: 0, count: 14_400) + [Float](repeating: 0.5, count: 4_800)
expect(abs(SilenceHallucinationGate.peakWindowRMS(gateBurst) - 0.5) < 0.0001, "peak is the loudest window, not the average")

print("AppTheme")
expectEqual(AppTheme.dark.toggled, .light, "dark toggles to light")
expectEqual(AppTheme.light.toggled, .dark, "light toggles to dark")
expectEqual(try! JSONDecoder().decode(AppTheme.self, from: "\"sepia\"".data(using: .utf8)!), .dark, "unknown theme → dark")

print("DictationError")
expect(DictationError.allCases.allSatisfy { !$0.message.isEmpty }, "every error has a message")
expect(DictationError.allCases.allSatisfy { $0.message.lowercased() != "something went wrong" }, "no generic fallback copy")
expect(Set(DictationError.allCases.map { $0.message }).count == DictationError.allCases.count, "messages are distinct")
expect(DictationError.noMicrophone.message.lowercased().contains("microphone"), "no-mic mentions microphone")

print("AudioLevel.normalize")
expectEqual(AudioLevel.normalize(-160), 0, "very quiet → 0")
expectEqual(AudioLevel.normalize(-55), 0, "floor → 0")
expectEqual(AudioLevel.normalize(0), 1, "0 dB → 1")
expectEqual(AudioLevel.normalize(5), 1, "above 0 dB clamps to 1")
expect(AudioLevel.normalize(-40) < AudioLevel.normalize(-20), "monotonic increasing")
expectEqual(AudioLevel.normalize(Float.nan), 0, "NaN → 0")

print("ModelDownloadProgress formatting")
expectEqual(ModelDownloadProgress.megabytes(0), "0 MB", "zero bytes")
expectEqual(ModelDownloadProgress.megabytes(632_000_000), "632 MB", "632 MB reads back as the folder-name size")
expectEqual(ModelDownloadProgress.megabytes(-5), "0 MB", "negative clamps to 0 MB")
expectEqual(ModelDownloadProgress.label(downloaded: 284_000_000, total: 632_000_000), "284 MB of ~632 MB", "measured bytes of an approximate total")

print("ModelDownloadProgress.fraction")
expectEqual(ModelDownloadProgress.fraction(downloaded: 316_000_000, total: 632_000_000), 0.5, "half downloaded → 0.5")
expectEqual(ModelDownloadProgress.fraction(downloaded: 0, total: 632_000_000), 0, "nothing downloaded → 0")
expectEqual(ModelDownloadProgress.fraction(downloaded: 700_000_000, total: 632_000_000), 1, "overshooting an approximate total clamps to full")
expectEqual(ModelDownloadProgress.fraction(downloaded: 100, total: 0), 0, "unknown total → 0, never a divide by zero")

print("ModelDownloadProgress.downloadedBytes (real I/O)")
// The model folder AND its HuggingFace staging area must both count: files
// stream into staging as .incomplete and only move into the model folder once
// whole, so counting the model folder alone would show a stalled 0 MB for most
// of a download.
let probeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("jvoice-progress-\(UUID().uuidString)")
let probeRepo = probeRoot.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
let probeModel = probeRepo.appendingPathComponent("openai_whisper-probe/AudioEncoder.mlmodelc/weights")
let probeStaging = probeRepo
    .appendingPathComponent(".cache/huggingface/download/openai_whisper-probe/TextDecoder.mlmodelc/weights")
try? FileManager.default.createDirectory(at: probeModel, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: probeStaging, withIntermediateDirectories: true)
expectEqual(ModelDownloadProgress.downloadedBytes(folderName: "openai_whisper-probe", documentsDirectory: probeRoot), 0, "empty folders → 0 bytes")
try? Data(count: 1_000).write(to: probeModel.appendingPathComponent("weight.bin"))
expectEqual(ModelDownloadProgress.downloadedBytes(folderName: "openai_whisper-probe", documentsDirectory: probeRoot), 1_000, "a completed file in the model folder counts")
try? Data(count: 2_500).write(to: probeStaging.appendingPathComponent("weight.bin.incomplete"))
expectEqual(ModelDownloadProgress.downloadedBytes(folderName: "openai_whisper-probe", documentsDirectory: probeRoot), 3_500, "in-flight staging bytes count too")
expectEqual(ModelDownloadProgress.downloadedBytes(folderName: "openai_whisper-absent", documentsDirectory: probeRoot), 0, "a model that was never fetched → 0, not a crash")
try? FileManager.default.removeItem(at: probeRoot)

print("ShortcutCapturePolicy.decide")
expectEqual(ShortcutCapturePolicy.decide(key: .escape, hasAnyModifier: false, hasModifierBesidesShift: false, isFunctionKey: false), .cancel, "bare Esc cancels")
expectEqual(ShortcutCapturePolicy.decide(key: .tab, hasAnyModifier: false, hasModifierBesidesShift: false, isFunctionKey: false), .cancel, "bare Tab cancels")
expectEqual(ShortcutCapturePolicy.decide(key: .delete, hasAnyModifier: false, hasModifierBesidesShift: false, isFunctionKey: false), .clear, "bare Delete clears")
expectEqual(ShortcutCapturePolicy.decide(key: .delete, hasAnyModifier: true, hasModifierBesidesShift: true, isFunctionKey: false), .accept, "⌘⌫ is a chord, not a clear")
expectEqual(ShortcutCapturePolicy.decide(key: .other, hasAnyModifier: true, hasModifierBesidesShift: true, isFunctionKey: false), .accept, "⌥Space is a chord")
expectEqual(ShortcutCapturePolicy.decide(key: .other, hasAnyModifier: true, hasModifierBesidesShift: false, isFunctionKey: false), .reject, "⇧ alone is not a chord")
expectEqual(ShortcutCapturePolicy.decide(key: .other, hasAnyModifier: false, hasModifierBesidesShift: false, isFunctionKey: false), .reject, "a bare letter is not a chord")
expectEqual(ShortcutCapturePolicy.decide(key: .other, hasAnyModifier: false, hasModifierBesidesShift: false, isFunctionKey: true), .accept, "F-keys need no modifier")

print("MathSpeech.convert — spoken mathematics becomes notation")
expectEqual(MathSpeech.convert("a subscript n equals 1 plus 7n"), "aₙ = 1 + 7n", "the ask: aₙ = 1 + 7n")
expectEqual(MathSpeech.convert("x squared plus y squared equals z squared"), "x² + y² = z²", "powers")
expectEqual(MathSpeech.convert("the square root of 16 equals 4"), "the √16 = 4", "square root")
expectEqual(MathSpeech.convert("twenty five divided by five equals five"), "25 ÷ 5 = 5", "spoken numbers + division")
expectEqual(MathSpeech.convert("3 over 4 plus 1 over 4 equals 1"), "¾ + ¼ = 1", "stacked fractions")
expectEqual(MathSpeech.convert("1 over n squared"), "1 ÷ n²", "the power belongs to the denominator")
expectEqual(MathSpeech.convert("3 times 4 equals 12"), "3 · 4 = 12", "times is the middle dot")
expectEqual(MathSpeech.convert("log base 2 of 8"), "log₂(8)", "a named base activates")
expectEqual(MathSpeech.convert("u n equals 1 plus 7n"), "uₙ = 1 + 7n", "a classic index is a sequence term")
expectEqual(MathSpeech.convert("the limit as x approaches 0 of sine of x over x equals 1"), "the lim_(x→0) sin(x) ÷ x = 1", "limit")
expectEqual(MathSpeech.convert("the sum from n equals 1 to infinity of 1 over n squared"), "the ∑ₙ₌₁^∞ 1 ÷ n²", "bounded sum")
expectEqual(MathSpeech.convert("the derivative of y with respect to x"), "the dy/dx", "derivative")
expectEqual(MathSpeech.convert("n choose k equals 10"), "C(n, k) = 10", "binomial")
expectEqual(MathSpeech.convert("theta equals 30 degrees"), "θ = 30°", "greek + postfix")
expectEqual(MathSpeech.convert("so basically x equals 5 and that's it"), "so basically x = 5 and that's it", "only the equation moves")
expectEqual(MathSpeech.convert("write start equation alpha end equation here"), "write α here", "escape hatch")
// David's real 2026-09-21 physics dictation — the one that exposed the parity gap.
expectEqual(
    MathSpeech.convert("we're just going to use S equals U plus V divided by 2 times T. Basically, since the initial and final velocities are both 6, it would be 12 over 2T equals 400."),
    "we're just going to use S = U + V ÷ 2 · T. Basically, since the initial and final velocities are both 6, it would be 12 ÷ 2T = 400.",
    "David's SUVAT dictation")

print("MathSpeech.convert — ordinary speech comes back byte-identical")
for prose in [
    "this is a subscript of the value",
    "two times a day keeps the doctor away",
    "plus I think we should go now",
    "I'm 100 percent sure about this",
    "it's 30 degrees outside today",
    "the sum of my fears is nothing",
    "an integral part of the plan",
    "the square root of all evil",
    "the alpha version ships tomorrow",
    "God is the alpha and the omega",
    "go to the store and buy some milk",
    "the base of the mountain was covered in snow",
    "I had to choose between the two options",
    "let's say between 60 and negative 50 for now",
    "three quarters of the class passed the test",
    "I woke up at seven and made coffee",
    "there were about a hundred people there",
    "he read chapter three verse sixteen out loud",
    "i think u n is fine the way it is",
    "the log of the tree was rotten through",
    "we drove 60 miles per hour the whole way",
    "my sin is always before me",
    "for all three of us it was a long day",
    "he was given 3 days to think it over",
    "alright so for the Bible study tonight we are in John chapter 3 verse 16, for God so loved the world that he gave his only begotten son, and a lot of people read that verse a hundred times",
] {
    expectEqual(MathSpeech.convert(prose), prose, "untouched: \"\(prose.prefix(46))\"")
}

print("MathSpeech.convert — idempotent, and blank input is returned unchanged")
expectEqual(MathSpeech.convert(MathSpeech.convert("x squared plus y squared equals z squared")), "x² + y² = z²", "converting twice changes nothing")
expectEqual(MathSpeech.convert(""), "", "empty string")
expectEqual(MathSpeech.convert("   "), "   ", "all-whitespace string")

print("MathSymbols — the vocabulary never shadows a construct the engine parses")
expect(!MathSymbols.reservedPhrases.isEmpty, "reserved phrases are listed")
for reserved in MathSymbols.reservedPhrases {
    expect(MathSymbols.phrases[reserved] == nil, "reserved phrase is not a vocabulary key: \"\(reserved)\"")
}
expect(MathSymbols.phrases.count >= 600, "the dictionary is comprehensive (\(MathSymbols.phrases.count) spoken forms)")
for risky in ["and", "or", "is", "by", "at", "than", "cross", "sin", "cos", "tan", "sign",
              "power", "square", "because", "therefore", "since", "about", "less", "arc"] {
    expect(MathSymbols.phrases[risky] == nil, "everyday word excluded: \"\(risky)\"")
}

print("SparseTranscriptGuard (ported from windows/JVoice.Core/Policy, HANDOFF-WINDOWS §7 #43)")
do {
    let prompted = "Okay, first we plan the garden beds. water them nightly. Done" // 61 chars, head + tail shape
    let x = { (n: Int) in String(repeating: "x", count: n) }
    let w = { (n: Int) in String(repeating: "w", count: n) }
    expectEqual(prompted.count, 61, "stand-in has the failure's length")
    expectEqual(SparseTranscriptGuard.minAudioSeconds, 10.0, "minAudioSeconds locked")
    expectEqual(SparseTranscriptGuard.sparseCharsPerSecond, 4.0, "sparseCharsPerSecond locked")
    expectEqual(SparseTranscriptGuard.witnessAdoptFactor, 2, "witnessAdoptFactor locked")
    expect(SparseTranscriptGuard.shouldVerify(audioSeconds: 32.11, promptedTranscript: prompted), "61 chars over 32.11 s (1.9 chars/s) triggers")
    for (s, c) in [(62.58, 555), (12.49, 148), (97.10, 1255), (32.62, 438)] {
        expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: s, promptedTranscript: x(c)), "normal density quiet: \(c) chars / \(s) s")
    }
    for (s, c) in [(8.12, 10), (3.97, 11), (9.99, 5)] {
        expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: s, promptedTranscript: x(c)), "short clip never triggers: \(c) chars / \(s) s")
    }
    expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 30, promptedTranscript: ""), "blank transcript → empty path, not this guard")
    expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 30, promptedTranscript: "   "), "whitespace transcript → empty path")
    expect(SparseTranscriptGuard.shouldVerify(audioSeconds: 10.0, promptedTranscript: x(39)), "boundary: 39 chars / 10 s triggers")
    expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 10.0, promptedTranscript: x(40)), "boundary: 40 chars / 10 s does not (strict <)")
    expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 0, promptedTranscript: "hi"), "zero seconds never triggers")
    expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: .nan, promptedTranscript: "hi"), "NaN seconds never triggers")
    expectEqual(SparseTranscriptGuard.resolve(promptedTranscript: prompted, unpromptedWitness: w(566)), w(566), "9.3× witness adopted")
    for n in [61, 66, 121] {
        expectEqual(SparseTranscriptGuard.resolve(promptedTranscript: prompted, unpromptedWitness: w(n)), prompted, "comparable witness (\(n) chars) keeps prompted")
    }
    expectEqual(SparseTranscriptGuard.resolve(promptedTranscript: prompted, unpromptedWitness: w(122)), w(122), "exactly 2× witness adopted")
    expectEqual(SparseTranscriptGuard.resolve(promptedTranscript: prompted, unpromptedWitness: ""), prompted, "empty witness never adopted")
    expectEqual(SparseTranscriptGuard.resolve(promptedTranscript: prompted, unpromptedWitness: "   "), prompted, "blank witness never adopted")
}

if failures > 0 {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
print("\nAll logic tests passed.")
EOF

xcrun swiftc -O \
    "$REPO_ROOT/Sources/JVoice/Models/AppMode.swift" \
    "$REPO_ROOT/Sources/JVoice/Models/AppModeRule.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/AppModeResolver.swift" \
    "$REPO_ROOT/Sources/JVoice/Models/AppTheme.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Orchestration/DictationError.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Audio/AudioLevel.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Orchestration/StatsStore.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/TextProcessor.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/DeveloperTerms.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/PhoneticMatcher.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RepetitionGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/PhraseLoopGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/SparseTranscriptGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/VocabularyPrompt.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/WavTail.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/ChunkPlanner.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/NonSpeechAnnotation.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/SilenceHallucinationGate.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/ModelDownloadProgress.swift" \
    "$REPO_ROOT/Sources/JVoice/UI/ShortcutCapturePolicy.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/Math/MathSymbol.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/Math/MathScript.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/Math/MathSymbols.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/Math/SpokenNumbers.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/Math/MathSpeech.swift" \
    "$TMP_DIR/main.swift" \
    -o "$TMP_DIR/logic-tests"

"$TMP_DIR/logic-tests"

# ---- BEGIN orchestration/audio decisions (dictation-flow fixes, 2026-09-23) ----
# Separate harness (own main, own source list) so it stays one self-contained
# block: the hotkey press decision (a press during transcription is ignored; a
# stop while the mic opens is honoured), the dead-input wording
# (SilentCaptureDetector), and the Bluetooth redirect never picking a virtual input.
mkdir -p "$TMP_DIR/orchestration"   # top-level code must live in a file named main.swift
cat > "$TMP_DIR/orchestration/main.swift" <<'EOF'
import CoreAudio
import Foundation

var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { print("  ✓ \(message)") } else { print("  ✗ FAIL: \(message)"); failures += 1 }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual == expected { print("  ✓ \(message)") } else { print("  ✗ FAIL: \(message) — got \(actual), expected \(expected)"); failures += 1 }
}

print("CoordinatorDecisions.canStartRecording — a pending transcript outranks a new start")
expect(CoordinatorDecisions.canStartRecording(isStartingRecording: false, isTranscribing: false), "idle → start allowed")
expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: true, isTranscribing: false), "mic still opening → refused")
expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: false, isTranscribing: true), "transcription in flight → refused")
expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: true, isTranscribing: true), "both → refused")

print("CoordinatorDecisions.pressAction — what a hotkey / menu / pill press does")
func press(_ rec: Bool, _ starting: Bool, _ stopping: Bool, _ transcribing: Bool) -> CoordinatorDecisions.PressAction {
    CoordinatorDecisions.pressAction(isRecording: rec, isStartingRecording: starting,
                                     isStoppingRecording: stopping, isTranscribing: transcribing)
}
expectEqual(press(false, false, false, false), .start, "idle → start")
expectEqual(press(true, false, false, false), .stop, "recording → stop")
expectEqual(press(true, true, false, false), .stop, "mic just opened (both flags) → stop")
expectEqual(press(true, false, true, false), .ignore, "stop already running → ignore")
expectEqual(press(false, true, false, false), .stopOnceOpened, "mic still opening → stop once it opens (was dropped)")
expectEqual(press(false, false, false, true), .ignore, "transcription in flight → ignore (was: cancel it)")

print("SilentCaptureDetector — exact-zero input is named, a quiet real mic is not")
let deadRate = 16_000
let deadNoise: (Double) -> [Int16] = { secs in (0..<Int(secs * Double(deadRate))).map { Int16(($0 * 7919) % 9) - 4 } }
let deadStats = CaptureSignalStats(samples: [Int16](repeating: 0, count: deadRate * 2), sampleRate: deadRate)
let quietStats = CaptureSignalStats(samples: deadNoise(2), sampleRate: deadRate)
let measured = CaptureSignalStats(samples: [0, 1, 0, -3, 0, 0, 0, 2], sampleRate: 8)
expectEqual(measured, CaptureSignalStats(totalSamples: 8, nonZeroSamples: 3, seconds: 1), "counts exact-zero samples only")
expect(SilentCaptureDetector.isDeadInput(deadStats), "2 s of digital silence → dead input")
expect(!SilentCaptureDetector.isDeadInput(quietStats), "quiet noise floor (ratio \(String(format: "%.2f", quietStats.nonZeroRatio))) → not dead")
expect(!SilentCaptureDetector.isDeadInput(CaptureSignalStats(samples: [Int16](repeating: 0, count: 0), sampleRate: deadRate)), "empty → not judged")
expect(!SilentCaptureDetector.isDeadInput(CaptureSignalStats(samples: [Int16](repeating: 0, count: 3_200), sampleRate: deadRate)), "0.2 s → too short to judge")
expect(!SilentCaptureDetector.isDeadInput(CaptureSignalStats(samples: [Int16](repeating: 0, count: 4_800) + deadNoise(0.7), sampleRate: deadRate)), "late ramp-up (0.3 s zeros) → not dead")
let deadCopy = SilentCaptureDetector.deadInputMessage(deviceName: "BlackHole 16ch")
expectEqual(deadCopy, "\"BlackHole 16ch\" is sending no audio — pick another mic in System Settings > Sound.", "dead-input copy names the device")
expect(SilentCaptureDetector.deadInputMessage(deviceName: nil).hasPrefix("Your microphone"), "no name → 'Your microphone'")
let longCopy = SilentCaptureDetector.deadInputMessage(deviceName: String(repeating: "x", count: 80))
expect(longCopy.contains("…\"") && longCopy.hasSuffix("System Settings > Sound."), "long name shortened, fix still visible")
expectEqual(SilentCaptureDetector.noSpeechMessage(stats: deadStats, deviceName: "BlackHole 16ch"), deadCopy, "no-speech + digital silence → device copy")
expectEqual(SilentCaptureDetector.noSpeechMessage(stats: quietStats, deviceName: "MacBook Air Microphone"), DictationError.noSpeechHeard.message, "no-speech + quiet real mic → usual copy")
expectEqual(SilentCaptureDetector.noSpeechMessage(stats: nil, deviceName: "BlackHole 16ch"), DictationError.noSpeechHeard.message, "unreadable WAV → usual copy")

print("AudioInputRouter.redirectTarget — only ever a physical mic, never a virtual input")
func dev(_ id: AudioDeviceID, _ transport: UInt32) -> AudioInputRouter.InputDevice { .init(id: id, transport: transport) }
let bt = kAudioDeviceTransportTypeBluetooth
expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: kAudioDeviceTransportTypeBuiltIn,
                                            inputDevices: [dev(1, kAudioDeviceTransportTypeBuiltIn), dev(2, bt)]), nil, "built-in default → untouched")
expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: bt,
                                            inputDevices: [dev(10, bt), dev(20, kAudioDeviceTransportTypeUSB), dev(30, kAudioDeviceTransportTypeBuiltIn)]), 30, "Bluetooth default → built-in preferred")
expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: bt,
                                            inputDevices: [dev(10, bt), dev(20, kAudioDeviceTransportTypeVirtual)]), nil, "no built-in, only BlackHole (virtual) → leave the default alone (was: BlackHole)")
expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: bt,
                                            inputDevices: [dev(10, bt), dev(20, kAudioDeviceTransportTypeAggregate)]), nil, "aggregate → never a target")
expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: bt,
                                            inputDevices: [dev(10, bt), dev(20, kAudioDeviceTransportTypeVirtual), dev(40, kAudioDeviceTransportTypeUSB)]), 40, "virtual listed first, USB mic still found")
for transport in [kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI] {
    expectEqual(AudioInputRouter.redirectTarget(defaultInputTransport: bt, inputDevices: [dev(10, bt), dev(50, transport)]), 50, "physical transport \(transport) accepted")
}

if failures > 0 {
    print("\n\(failures) FAILURE(S) in orchestration/audio decisions")
    exit(1)
}
print("\nAll orchestration/audio decision tests passed.")
EOF

xcrun swiftc -O \
    "$REPO_ROOT/Sources/JVoice/Services/Orchestration/CoordinatorDecisions.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Orchestration/DictationError.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Audio/SilentCaptureDetector.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Audio/AudioInputRouter.swift" \
    "$TMP_DIR/orchestration/main.swift" \
    -o "$TMP_DIR/orchestration-tests"

"$TMP_DIR/orchestration-tests"
# ---- END orchestration/audio decisions ----
