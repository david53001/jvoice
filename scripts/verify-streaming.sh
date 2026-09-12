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
actor LastMock {
    private(set) var lastCount = 0
    func next(_ n: Int) -> String { lastCount = n; return "p\(n)" }
}
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func add(_ e: String) { lock.lock(); events.append(e); lock.unlock() }
    func contains(_ needle: String) -> Bool { lock.lock(); defer { lock.unlock() }; return events.contains { $0.contains(needle) } }
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

    // 9. A chunk decode IN FLIGHT at finish() is awaited and kept — never
    //    cancelled into a failure (which forced a whole-file re-decode of the
    //    entire dictation: 6.6 s instead of 1 s on a 96 s recording).
    do {
        let url = tmpURL(); try wavSegments([(2.6, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = SumMock()
        let s = StreamingTranscriptionSession(transcribe: { samples in
            try await Task.sleep(nanoseconds: 250_000_000) // slow decode; a cancelled task would throw here
            return await mock.next(samples.count)
        }, config: fastConfig(), pollNanoseconds: 20_000_000, speculateAfterSeconds: 0)
        await s.start(url: url); try await Task.sleep(nanoseconds: 120_000_000) // first chunk decode is mid-flight
        let r = await s.finish()
        let total = await mock.total
        expect(r != nil, "finish() during an in-flight chunk decode → streamed transcript, NOT a fallback")
        expect(total == Int(2.6 * 16_000), "in-flight chunk consumed once, remainder drained: every sample exactly once (\(total))")
    } catch { expect(false, "scenario 9 threw \(error)") }

    // 10. Speculative tail HIT: pending audio ends in a pause → decoded during
    //     the pause; finish() returns it without decoding anything.
    do {
        let url = tmpURL(); try wavSegments([(1.2, 0.5), (0.8, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 5; cfg.maxChunkSeconds = 10
        let mock = SumMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await mock.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 150_000_000)
        let calls = await mock.total
        expect(calls == Int(2.0 * 16_000), "speculative decode ran during the pause over the pending audio (\(calls))")
        let t0 = Date()
        let r = await s.finish()
        let finishMs = Int(Date().timeIntervalSince(t0) * 1000)
        expect(r == "p", "finish() returned the speculative result")
        expect(await mock.total == calls, "finish() decoded NOTHING more (speculation hit)")
        expect(events.contains("HIT"), "log reports the speculative tail HIT")
        expect(finishMs < 50, "finish() was immediate (\(finishMs) ms)")
    } catch { expect(false, "scenario 10 threw \(error)") }

    // 11. Speculative tail MISS: speech resumes after the pause → the
    //     speculation is dropped and the real tail (all speech) is decoded.
    do {
        let url = tmpURL(); try wavSegments([(1.2, 0.5), (0.6, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 5; cfg.maxChunkSeconds = 10
        let last = LastMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await last.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 120_000_000)
        expect(events.contains("started"), "speculation started at the first pause")
        // The user keeps talking: append 1.0 s of speech + 0.5 s silence.
        let more = wavSegments([(1.0, 0.5), (0.5, 0.0)]).dropFirst(44)
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
        try await Task.sleep(nanoseconds: 120_000_000)
        let r = await s.finish()
        expect(r != nil, "miss path still yields a streamed transcript")
        expect(await last.lastCount == Int(3.3 * 16_000), "the final decode covered the WHOLE pending audio (\(await last.lastCount))")
        expect(events.contains("resumed"), "log reports the dropped speculation (speech resumed)")
    } catch { expect(false, "scenario 11 threw \(error)") }

    // 12. A chunk cut that lands inside the speculated pause REUSES the
    //     speculative decode instead of decoding the same speech twice.
    do {
        let url = tmpURL(); try wavSegments([(1.0, 0.5), (0.5, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 1.5; cfg.maxChunkSeconds = 3.0
        let mock = SumMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await mock.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 120_000_000)
        expect(events.contains("started"), "speculation started (1.5 s pending, no cut candidate yet)")
        let more = wavSegments([(0.5, 0.0)]).dropFirst(44) // more silence → a cut candidate appears
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
        try await Task.sleep(nanoseconds: 120_000_000)
        expect(events.contains("reuses"), "the chunk cut reused the speculative decode")
        let r = await s.finish()
        expect(r == "p", "one piece, from the single decode")
        expect(await mock.total == Int(1.5 * 16_000), "exactly one decode ran, over the speculated audio (\(await mock.total))")
    } catch { expect(false, "scenario 12 threw \(error)") }

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
