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

    // 13. LOCAL recovery: a chunk decodes empty after good pieces → the earlier
    //     pieces are kept and only the region from the start of the LAST good
    //     piece to the end is re-decoded (not the whole recording), replacing
    //     that piece — every sample still covered by a successful decode.
    do {
        let url = tmpURL(); try wavSegments([(5.2, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = IdxMock(emptyAtCall: 5)
        let rec = LastMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { _ in await mock.next() },
                                              recover: { samples in await rec.next(samples.count) },
                                              config: fastConfig(), pollNanoseconds: 20_000_000, speculateAfterSeconds: 0,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        let r = await s.finish()
        let n = await rec.lastCount
        let total = Int(5.2 * 16_000)
        expect(r == "piece1 piece2 piece3 p\(n)", "earlier pieces kept + recovered region replaces the last good piece (\(r ?? "nil"))")
        expect(n >= Int(1.0 * 16_000) && n < total / 2 + total / 5, "only the region from the last good piece re-decoded (\(n) of \(total) samples)")
        expect(events.contains("local recovery"), "log reports the local recovery")
    } catch { expect(false, "scenario 13 threw \(error)") }

    // 14. Local recovery that ALSO comes back empty → nil (whole-file fallback).
    do {
        let url = tmpURL(); try wavSegments([(5.2, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = IdxMock(emptyAtCall: 5)
        let s = StreamingTranscriptionSession(transcribe: { _ in await mock.next() }, recover: { _ in "" },
                                              config: fastConfig(), pollNanoseconds: 20_000_000, speculateAfterSeconds: 0)
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        expect(await s.finish() == nil, "empty local recovery → fallback (nil), never a transcript missing that audio")
    } catch { expect(false, "scenario 14 threw \(error)") }

    // 15. The FIRST chunk fails (nothing decoded before it) → the region would
    //     be the whole recording: skip recovery, fall back directly.
    do {
        let url = tmpURL(); try wavSegments([(2.6, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let mock = IdxMock(emptyAtCall: 1)
        let rec = SumMock()
        let s = StreamingTranscriptionSession(transcribe: { _ in await mock.next() }, recover: { samples in await rec.next(samples.count) },
                                              config: fastConfig(), pollNanoseconds: 20_000_000, speculateAfterSeconds: 0)
        await s.start(url: url); try await Task.sleep(nanoseconds: 350_000_000)
        expect(await s.finish() == nil, "first chunk failed → fallback (nil)")
        expect(await rec.total == 0, "no local recovery attempted without a preceding piece")
    } catch { expect(false, "scenario 15 threw \(error)") }

    // 16. The speculative tail decoded EMPTY → the same tail is NOT decoded a
    //     second time on its own; it is re-heard in context via local recovery.
    do {
        // The recording grows in three 1.1 s speech + 0.5 s pause blocks (one cut
        // each), then 0.4 s speech + 0.6 s pause (the speculation) — the pending
        // tail never reaches a cut candidate.
        let url = tmpURL(); try wavSegments([(1.1, 0.5), (0.5, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 1.0; cfg.maxChunkSeconds = 3.0
        let mock = IdxMock(emptyAtCall: 4) // piece1–3, then the speculative tail decodes ""
        let rec = LastMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { _ in await mock.next() },
                                              recover: { samples in await rec.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 100_000_000)
        for segs in [[(1.1, 0.5), (0.5, 0.0)], [(1.1, 0.5), (0.5, 0.0)], [(0.4, 0.5), (0.6, 0.0)]] {
            let more = wavSegments(segs).dropFirst(44)
            let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        let r = await s.finish()
        let n = await rec.lastCount
        expect(events.contains("decoded empty"), "the speculative tail decoded empty")
        expect(r == "piece1 piece2 p\(n)" && n > 0 && n < Int(5.8 * 16_000) / 2, "recovered in context from the last good piece (\(r ?? "nil"), \(n) samples)")
        expect(!(r?.contains("piece5") ?? false), "the empty tail was NOT decoded a second time on its own")
    } catch { expect(false, "scenario 16 threw \(error)") }

    // 17. Speech-end JITTER inside the decoded pause does not drop the
    //     speculation. A 30 ms near-floor sound in the pause reads as speech on
    //     one 0.1 s probe grid and as silence on the next (the grid is anchored
    //     at the growing file's end), so the measured speech end jumps by
    //     ~0.4 s although nothing new was said — in the live log such flips
    //     restarted the speculation up to 5× in a row (each ~0.41 s of Neural
    //     Engine time). The speculation already heard every sample up to its
    //     decoded end, so it stays valid and the stop press is a HIT.
    do {
        let url = tmpURL()
        try wavSegments([(1.0, 0.5), (0.3, 0.0), (0.03, 0.016), (0.47, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 5; cfg.maxChunkSeconds = 10
        let mock = SumMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await mock.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 120_000_000)
        expect(events.contains("started"), "speculation started (speech end 1.4 s: the blip reads as speech on this grid)")
        let more = wavSegments([(0.015, 0.0)]).dropFirst(44) // shifts the probe grid: the blip now splits across two probes
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
        try await Task.sleep(nanoseconds: 120_000_000)
        expect(!events.contains("dropped"), "speech end jumped back to 1.0 s inside the decoded audio → speculation kept")
        let r = await s.finish()
        expect(r == "p", "finish() returned the speculative result")
        expect(events.contains("HIT"), "the stop press is a HIT")
        expect(await mock.total == Int(1.8 * 16_000), "exactly one decode ran (\(await mock.total))")
    } catch { expect(false, "scenario 17 threw \(error)") }

    // 18. A chunk cut must NOT reuse a speculation when above-floor audio lies
    //     between the speculation's decoded end and the cut. The cut is placed
    //     by the RELATIVE threshold (10 % of the chunk's peak), so soft audio can
    //     form the "quiet" cut window; the poll that sees the cut never re-checks
    //     the speculation, and reusing it would silently skip that audio.
    do {
        let url = tmpURL(); try wavSegments([(1.0, 0.5), (0.5, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 1.5; cfg.maxChunkSeconds = 3.0
        let last = LastMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await last.next(samples.count) },
                                              config: cfg, pollNanoseconds: 20_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 120_000_000)
        expect(events.contains("started"), "speculation started over [0, 1.5 s)")
        // Soft audio (RMS ≈ 0.014: above the 0.005 floor, below 10 % of the peak) → cut window [1.5, 1.8).
        let more = wavSegments([(0.3, 0.02)]).dropFirst(44)
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
        try await Task.sleep(nanoseconds: 120_000_000)
        expect(!events.contains("reuses"), "the speculation (heard only up to 1.5 s) was NOT reused for the 1.65 s chunk")
        let r = await s.finish()
        expect(r == "p26400 p2400", "the chunk [0, 1.65 s) was decoded in full, then the soft tail (\(r ?? "nil"))")
    } catch { expect(false, "scenario 18 threw \(error)") }

    // 19. A HIT needs silence after the speculation's DECODED END: speech that
    //     arrives after the speculation, with the stop press before any poll
    //     sees it, must be decoded — not dropped by returning the speculation.
    do {
        let url = tmpURL(); try wavSegments([(1.0, 0.5), (0.6, 0.0)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var cfg = ChunkPlanner.Config(); cfg.minChunkSeconds = 5; cfg.maxChunkSeconds = 10
        let last = LastMock()
        let events = EventBox()
        let s = StreamingTranscriptionSession(transcribe: { samples in await last.next(samples.count) },
                                              config: cfg, pollNanoseconds: 2_000_000_000, speculateAfterSeconds: 0.4,
                                              log: { events.add($0) })
        await s.start(url: url); try await Task.sleep(nanoseconds: 100_000_000) // first poll speculated; next poll is 2 s away
        let more = wavSegments([(0.5, 0.5), (0.2, 0.0)]).dropFirst(44)
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: more); try h.close()
        let r = await s.finish()
        expect(events.contains("started") && events.contains("MISS"), "speech after the speculated audio → MISS, not HIT")
        expect(r == "p\(Int(2.3 * 16_000))", "the final decode covered the WHOLE pending audio (\(r ?? "nil"))")
    } catch { expect(false, "scenario 19 threw \(error)") }

    // 20. A backlog at the stop press (slow decodes) is drained chunk by chunk;
    //     when a drained chunk then fails, local recovery starts at the LAST kept
    //     piece's true start — every sample decoded exactly once (no overlap).
    do {
        let url = tmpURL(); try wavSegments([(5.2, 0.5)]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        actor SlowCounter {
            private(set) var counts: [Int] = []
            func next(_ n: Int) async -> String {
                counts.append(n)
                let call = counts.count
                try? await Task.sleep(nanoseconds: 150_000_000)
                return call == 5 ? "" : "piece\(call)"
            }
        }
        let slow = SlowCounter()
        let rec = LastMock()
        let s = StreamingTranscriptionSession(transcribe: { samples in await slow.next(samples.count) },
                                              recover: { samples in await rec.next(samples.count) },
                                              config: fastConfig(), pollNanoseconds: 20_000_000, speculateAfterSeconds: 0)
        await s.start(url: url); try await Task.sleep(nanoseconds: 60_000_000) // chunk 1 in flight; the rest is backlog
        let r = await s.finish()
        let c = await slow.counts
        let n = await rec.lastCount
        let total = Int(5.2 * 16_000)
        expect(c.count == 5, "chunk 1 + four drained chunks decoded, the last failed (\(c))")
        expect(r == "piece1 piece2 piece3 p\(n)", "drained pieces kept, recovery replaced the last kept piece (\(r ?? "nil"))")
        expect(c.count == 5 && c[0] + c[1] + c[2] + n == total, "kept pieces + recovered region cover every sample exactly once (\(c.prefix(3)) + \(n) vs \(total))")
    } catch { expect(false, "scenario 20 threw \(error)") }

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
