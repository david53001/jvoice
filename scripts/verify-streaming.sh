#!/usr/bin/env bash
set -euo pipefail

# Local EXECUTION harness for the streaming session's data-loss guarantees.
# StreamingTranscriptionSession depends only on Foundation + WavTail + ChunkPlanner
# (no WhisperKit), so unlike the swift-testing suite this actually RUNS on a
# CLT-only machine. It drives the real actor with mock transcribers and asserts
# that audio is NEVER silently dropped: any non-silent chunk that decodes to ""
# fails the session so the caller falls back to the lossless whole-file path.
#
# Mirrors Tests/JVoiceTests/StreamingTranscriptionSessionTests.swift — keep both
# in sync; the suite is the authority.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

final class Box { var failures = 0 }
let box = Box()
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ FAIL: \(msg)"); box.failures += 1 }
}

func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
func wavSegments(_ segs: [(Double, Double)]) -> Data {
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16)
    b += Array("data".utf8) + le32(0)
    for (seconds, amplitude) in segs {
        let n = Int(seconds * 16_000)
        for i in 0..<n {
            let s = Int16(amplitude * 32_000 * sin(Double(i) * 2 * .pi * 220 / 16_000))
            b += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)]
        }
    }
    return Data(b)
}
func tmpURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("verify-\(UUID().uuidString).wav") }
func fastConfig() -> ChunkPlanner.Config {
    var c = ChunkPlanner.Config(); c.minChunkSeconds = 0.5; c.maxChunkSeconds = 1.0; return c
}

actor IdxMock {
    private let emptyAtCall: Int
    private var call = 0
    init(emptyAtCall: Int) { self.emptyAtCall = emptyAtCall }
    func next() -> String { call += 1; return call == emptyAtCall ? "" : "piece\(call)" }
}
actor SumMock {
    private(set) var total = 0
    func next(_ n: Int) -> String { total += n; return "p" }
}
actor DecodeRecorder {
    private(set) var calls: [Bool] = []
    let promptResult: String
    let cleanResult: String
    init(_ promptResult: String, _ cleanResult: String) { self.promptResult = promptResult; self.cleanResult = cleanResult }
    func decode(_ usePrompt: Bool) -> String { calls.append(usePrompt); return usePrompt ? promptResult : cleanResult }
}

let recVocab = ["sub agents", "claude", "li-fraumeni", "vs code"]
let regurg = "so the thing about money is that sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code"

let sem = DispatchSemaphore(value: 0)
Task {
    // 1. Every non-silent chunk decodes empty → no lossy partial, fall back (nil).
    do {
        let url = tmpURL(); try wavSegments([(2.6, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let s = StreamingTranscriptionSession(transcribe: { _ in "" }, config: fastConfig(), pollNanoseconds: 20_000_000)
        await s.start(url: url); try await Task.sleep(nanoseconds: 300_000_000)
        expect(await s.finish() == nil, "all-empty non-silent chunks → fallback (nil), audio NOT silently dropped")
    } catch { expect(false, "scenario 1 threw \(error)") }

    // 2. A single empty chunk anywhere → whole recording falls back (no missing span).
    do {
        let url = tmpURL(); try wavSegments([(2.6, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = IdxMock(emptyAtCall: 2)
        let s = StreamingTranscriptionSession(transcribe: { _ in await mock.next() }, config: fastConfig(), pollNanoseconds: 20_000_000)
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        expect(await s.finish() == nil, "one empty chunk among good ones → fallback (nil), not a transcript missing that chunk")
    } catch { expect(false, "scenario 2 threw \(error)") }

    // 3. A genuinely silent region is dropped WITHOUT failing the session.
    do {
        let url = tmpURL(); try wavSegments([(1.2, 0.5), (1.2, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let s = StreamingTranscriptionSession(transcribe: { _ in "speech" }, config: fastConfig(), pollNanoseconds: 20_000_000)
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        let r = await s.finish()
        expect(r != nil, "silent region dropped does NOT fail the session")
        expect(r?.contains("speech") == true, "speech before the silence is preserved")
    } catch { expect(false, "scenario 3 threw \(error)") }

    // 4. Happy path: all non-empty chunks → joined, every sample accounted for.
    do {
        let url = tmpURL(); try wavSegments([(2.6, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = SumMock()
        let s = StreamingTranscriptionSession(transcribe: { samples in await mock.next(samples.count) }, config: fastConfig(), pollNanoseconds: 20_000_000)
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        let r = await s.finish()
        let total = await mock.total
        expect(r != nil && !(r!.isEmpty), "all-good chunks → non-nil transcript")
        expect(total == Int(2.6 * 16_000), "every sample transcribed exactly once (\(total) == \(Int(2.6 * 16_000)))")
    } catch { expect(false, "scenario 4 threw \(error)") }

    // 5. Recovery: a prompted decode that REGURGITATED → re-decode without the
    //    prompt and use that clean result (the symptom-A fix).
    do {
        let rec = DecodeRecorder(regurg, "the actual spoken sentence about the economy")
        let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
        expect(out == "the actual spoken sentence about the economy", "regurgitated prompted decode → clean no-prompt re-decode used")
        expect(await rec.calls == [true, false], "recovery decoded WITH prompt, then WITHOUT")
    }
    // 6. Clean prompted decode is used as-is — no wasteful re-decode.
    do {
        let rec = DecodeRecorder("I use VS Code and Claude every day with my sub agents", "SHOULD NOT BE USED")
        let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
        expect(out == "I use VS Code and Claude every day with my sub agents", "clean prompted decode kept (vocab accuracy preserved)")
        expect(await rec.calls == [true], "clean decode → exactly one decode, no re-decode")
    }
    // 7. Empty prompted decode (the WhisperKit immediate-EOT trap) → recover.
    do {
        let rec = DecodeRecorder("", "recovered speech that was nearly lost")
        let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
        expect(out == "recovered speech that was nearly lost", "empty prompted decode → clean re-decode recovers speech")
        expect(await rec.calls == [true, false], "empty decode triggered re-decode")
    }
    // 8. Prompt disabled → single prompt-free decode, never a recovery pass.
    do {
        let rec = DecodeRecorder("UNUSED", "plain decode result")
        let out = await RegurgitationRecovery.decode(useVocabularyPrompt: false, vocabulary: recVocab) { await rec.decode($0) }
        expect(out == "plain decode result", "prompt disabled → prompt-free decode used")
        expect(await rec.calls == [false], "prompt disabled → exactly one (prompt-free) decode")
    }

    sem.signal()
}
sem.wait()
if box.failures > 0 { print("\n\(box.failures) FAILURE(S)"); exit(1) }
print("\nAll streaming + recovery verification passed.")
exit(0)
EOF

xcrun swiftc -O \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/WavTail.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/ChunkPlanner.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/StreamingTranscriptionSession.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/PhoneticMatcher.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RepetitionGuard.swift" \
    "$REPO_ROOT/Sources/JVoice/Services/Transcription/RegurgitationRecovery.swift" \
    "$TMP_DIR/main.swift" \
    -o "$TMP_DIR/verify-streaming"

"$TMP_DIR/verify-streaming"
