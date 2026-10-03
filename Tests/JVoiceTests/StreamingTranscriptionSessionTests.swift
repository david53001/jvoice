#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

// 20 ms polls + tiny "chunks" (override config) keep these tests fast.
private func fastConfig() -> ChunkPlanner.Config {
    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 0.5
    cfg.maxChunkSeconds = 1.0
    return cfg
}

private func makeWav(seconds: Double, amplitude: Double) -> Data {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16)
    b += Array("data".utf8) + le32(0)
    let n = Int(seconds * 16_000)
    for i in 0..<n {
        let s = Int16(amplitude * 32_000 * sin(Double(i) * 2 * .pi * 220 / 16_000))
        b += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)]
    }
    return Data(b)
}

private func makeWavSegments(_ segments: [(seconds: Double, amplitude: Double)]) -> Data {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)] }
    var b: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
    b += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16)
    b += Array("data".utf8) + le32(0)
    for seg in segments {
        let n = Int(seg.seconds * 16_000)
        for i in 0..<n {
            let s = Int16(seg.amplitude * 32_000 * sin(Double(i) * 2 * .pi * 220 / 16_000))
            b += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)]
        }
    }
    return Data(b)
}

private func tempWavURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID().uuidString).wav")
}

@Test func transcribesChunksAndTailInOrder() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // 2.6 s of speech-level audio: with max=1.0 s chunks the session must
    // forcibly cut ~1 s pieces and finish() drains the rest.
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)

    let counter = TranscribeCounter()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await counter.next(sampleCount: samples.count) },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 200_000_000) // a few polls
    let result = await session.finish()

    let calls = await counter.calls
    #expect(result == (1...calls.count).map { "piece\($0)" }.joined(separator: " "))
    #expect(calls.count >= 2) // at least one streamed chunk + the tail
    // Every piece stayed within the single-window cap (1.0 s here, with slack).
    #expect(calls.allSatisfy { $0 <= 16_000 + 1_600 })
    // Nothing lost, nothing duplicated.
    #expect(calls.reduce(0, +) == Int(2.6 * 16_000))
}

@Test func neverStreamedReturnsNilForFallback() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 0.2, amplitude: 0.5).write(to: url) // below min chunk

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "never" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await session.finish() == nil)
}

@Test func vanishedFileFailsSessionSafely() async throws {
    let url = tempWavURL()
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "x" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 60_000_000)
    try FileManager.default.removeItem(at: url) // mid-recording teardown
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await session.finish() == nil)
}

@Test func cancelDiscardsEverything() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "x" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 100_000_000)
    await session.cancel()
    #expect(await session.finish() == nil)
}

@Test func transcriberErrorTriggersFallback() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.0, amplitude: 0.5).write(to: url)

    struct Boom: Error {}
    let session = StreamingTranscriptionSession(
        transcribe: { _ in throw Boom() },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(await session.finish() == nil)
}

@Test func finishIsIdempotent() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)

    let session = StreamingTranscriptionSession(
        transcribe: { _ in "piece" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 100_000_000)
    let first = await session.finish()
    #expect(first != nil)
    // A second finish() must NOT re-drain the backlog and duplicate audio —
    // it reports "nothing to offer" so the caller's fallback stays correct.
    #expect(await session.finish() == nil)
}

// MARK: - Data-loss guards (the "it cut out a big chunk of my dictation" bug)

@Test func emptyNonSilentChunkForcesFallbackNotSilentDrop() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)
    // Every non-silent chunk decodes to "" (e.g. a regurgitation the guard
    // stripped to empty, or an empty WhisperKit decode). The session MUST NOT
    // emit a transcript that silently omits that speech — it returns nil so the
    // caller re-runs the lossless whole-file path.
    let session = StreamingTranscriptionSession(
        transcribe: { _ in "" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 250_000_000)
    #expect(await session.finish() == nil)
}

@Test func oneEmptyChunkAnywhereForcesWholeFileFallback() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)
    // Only the 2nd transcribed chunk comes back empty; the rest are fine.
    // Rather than emit a transcript missing that chunk's ~1 s of speech, the
    // session fails so the whole-file fallback produces a COMPLETE transcript.
    let mock = IndexedEmptyMock(emptyAtCall: 2)
    let session = StreamingTranscriptionSession(
        transcribe: { _ in await mock.next() },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(await session.finish() == nil)
}

@Test func silentRegionIsDroppedNotTreatedAsDataLoss() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // 1.2 s of speech-level audio, then 1.2 s of true silence. The silent chunk
    // is dropped (never transcribed) — a legitimate drop that must NOT fail the
    // session. The speech still streams through.
    try makeWavSegments([(1.2, 0.5), (1.2, 0.0)]).write(to: url)
    let session = StreamingTranscriptionSession(
        transcribe: { _ in "speech" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 300_000_000)
    let result = await session.finish()
    #expect(result != nil)
    #expect(result?.contains("speech") == true)
}

private actor TranscribeCounter {
    private(set) var calls: [Int] = []
    func next(sampleCount: Int) -> String {
        calls.append(sampleCount)
        return "piece\(calls.count)"
    }
}

// MARK: - Latency layer (2026-09-12): in-flight decodes survive finish(); speculative tail decode.

private final class EventLogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func add(_ e: String) { lock.lock(); events.append(e); lock.unlock() }
    func contains(_ needle: String) -> Bool { lock.lock(); defer { lock.unlock() }; return events.contains { $0.contains(needle) } }
}

private actor SampleSum {
    private(set) var total = 0
    private(set) var lastCount = 0
    func next(_ n: Int) -> String { total += n; lastCount = n; return "p" }
}

private func speculationConfig() -> ChunkPlanner.Config {
    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 5
    cfg.maxChunkSeconds = 10
    return cfg
}

private func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: data.dropFirst(44)) // strip the 44-byte WAV header
    try handle.close()
}

/// A chunk decode in flight at finish() is awaited and kept, never cancelled
/// into a failure (which forced a whole-file re-decode of the whole dictation).
@Test func inFlightChunkDecodeSurvivesFinish() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)

    let sum = SampleSum()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in
            try await Task.sleep(nanoseconds: 250_000_000) // a cancelled task would throw here
            return await sum.next(samples.count)
        },
        config: fastConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 120_000_000) // first chunk decode is mid-flight
    let result = await session.finish()
    #expect(result != nil)
    #expect(await sum.total == Int(2.6 * 16_000)) // every sample exactly once
}

/// Pending audio that ends in a pause is decoded during the pause; finish()
/// returns that result without decoding anything more.
@Test func speculativeTailHitMakesFinishImmediate() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWavSegments([(1.2, 0.5), (0.8, 0.0)]).write(to: url)

    let sum = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await sum.next(samples.count) },
        config: speculationConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 150_000_000)
    let decodedDuringPause = await sum.total
    #expect(decodedDuringPause == Int(2.0 * 16_000))
    let result = await session.finish()
    #expect(result == "p")
    #expect(await sum.total == decodedDuringPause) // nothing decoded at finish
    #expect(events.contains("HIT"))
}

/// Speech resuming after the pause drops the speculation; the real tail
/// (all of the pending speech) is what gets decoded.
@Test func speculativeTailMissRedecodesWholeTail() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWavSegments([(1.2, 0.5), (0.6, 0.0)]).write(to: url)

    let sum = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await sum.next(samples.count) },
        config: speculationConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(events.contains("started"))
    try append(makeWavSegments([(1.0, 0.5), (0.5, 0.0)]), to: url) // the user keeps talking
    try await Task.sleep(nanoseconds: 120_000_000)
    let result = await session.finish()
    #expect(result != nil)
    #expect(await sum.lastCount == Int(3.3 * 16_000)) // final decode covered the whole pending audio
    #expect(events.contains("resumed"))
}

/// A chunk cut that lands inside the speculated pause reuses the speculative
/// decode instead of decoding the same speech twice.
@Test func chunkCutReusesSpeculativeDecode() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWavSegments([(1.0, 0.5), (0.5, 0.0)]).write(to: url)

    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 1.5
    cfg.maxChunkSeconds = 3.0
    let sum = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await sum.next(samples.count) },
        config: cfg,
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(events.contains("started"))
    try append(makeWavSegments([(0.5, 0.0)]), to: url) // more silence → a cut candidate appears
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(events.contains("reuses"))
    let result = await session.finish()
    #expect(result == "p")
    #expect(await sum.total == Int(1.5 * 16_000)) // exactly one decode
}

private actor IndexedEmptyMock {
    private let emptyAtCall: Int
    private(set) var call = 0
    init(emptyAtCall: Int) { self.emptyAtCall = emptyAtCall }
    func next() -> String {
        call += 1
        return call == emptyAtCall ? "" : "piece\(call)"
    }
}

// MARK: - Local recovery (2026-09-23): a failed chunk re-decodes a region, not the whole recording

@Test func failedChunkRecoversLocallyFromTheLastGoodPiece() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 5.2, amplitude: 0.5).write(to: url)
    // Chunk 5 decodes empty. Before: the whole recording was re-decoded (a 100 s
    // dictation: 7 s after stop). Now pieces 1–3 are kept and only the audio from
    // the start of piece 4 onward is decoded again — replacing piece 4 — so every
    // sample is still covered by a successful decode.
    let mock = IndexedEmptyMock(emptyAtCall: 5)
    let recovered = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { _ in await mock.next() },
        recover: { samples in await recovered.next(samples.count) },
        config: fastConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 350_000_000)
    #expect(await session.finish() == "piece1 piece2 piece3 p")
    let regionSamples = await recovered.lastCount
    #expect(regionSamples >= 16_000 && Double(regionSamples) <= StreamingTranscriptionSession.maxRecoveryFraction * 5.2 * 16_000)
    #expect(events.contains("local recovery"))
}

@Test func emptyLocalRecoveryFallsBackToWholeFile() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 5.2, amplitude: 0.5).write(to: url)
    let mock = IndexedEmptyMock(emptyAtCall: 5)
    let session = StreamingTranscriptionSession(
        transcribe: { _ in await mock.next() },
        recover: { _ in "" },
        config: fastConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 350_000_000)
    #expect(await session.finish() == nil)
}

@Test func firstChunkFailureSkipsLocalRecovery() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 2.6, amplitude: 0.5).write(to: url)
    // Nothing decoded before the failure: the region would be the whole
    // recording, so the caller's whole-file path runs directly.
    let mock = IndexedEmptyMock(emptyAtCall: 1)
    let recovered = SampleSum()
    let session = StreamingTranscriptionSession(
        transcribe: { _ in await mock.next() },
        recover: { samples in await recovered.next(samples.count) },
        config: fastConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 350_000_000)
    #expect(await session.finish() == nil)
    #expect(await recovered.total == 0)
}

@Test func emptySpeculativeTailIsNotDecodedTwice() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // Three 1.1 s speech + 0.5 s pause blocks arrive (one cut each), then 0.4 s
    // speech + 0.6 s pause (the speculation) — the pending tail never reaches a cut.
    try makeWavSegments([(1.1, 0.5), (0.5, 0.0)]).write(to: url)
    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 1.0
    cfg.maxChunkSeconds = 3.0
    let mock = IndexedEmptyMock(emptyAtCall: 4) // pieces 1–3, then the speculative tail decodes ""
    let recovered = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { _ in await mock.next() },
        recover: { samples in await recovered.next(samples.count) },
        config: cfg,
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await waitUntil { await mock.call >= 1 }
    // One growth per poll: each block is cut (calls 2–3), then the tail is speculated (call 4).
    for (index, segments) in [[(1.1, 0.5), (0.5, 0.0)], [(1.1, 0.5), (0.5, 0.0)], [(0.4, 0.5), (0.6, 0.0)]].enumerated() {
        try append(makeWavSegments(segments), to: url)
        try await waitUntil { await mock.call >= index + 2 }
    }
    let result = await session.finish()
    #expect(await mock.call == 4)
    #expect(events.contains("decoded empty"))
    // Recovered in context from the last good piece — and the empty tail was NOT
    // decoded again on its own (a fifth transcribe call would yield "piece5").
    #expect(result == "piece1 piece2 p")
    let regionSamples = await recovered.lastCount
    #expect(regionSamples > 0 && regionSamples < Int(5.8 * 16_000) / 2)
}

// MARK: - Wasted speculation (2026-09-23): speech-end jitter, and the reuse gap.

/// A 30 ms near-floor sound inside the pause reads as speech on one 0.1 s probe
/// grid and as silence on the next (the grid is anchored at the growing file's
/// end), so the measured speech end jumps ~0.4 s with nothing new said. The
/// speculation already heard all of it: it must stay valid — no restart (each
/// restart is another encoder pass) — and the stop press is a HIT.
@Test func speechEndJitterInsideDecodedPauseKeepsSpeculation() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWavSegments([(1.0, 0.5), (0.3, 0.0), (0.03, 0.016), (0.47, 0.0)]).write(to: url)

    let sum = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await sum.next(samples.count) },
        config: speculationConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(events.contains("started"))
    try append(makeWavSegments([(0.015, 0.0)]), to: url) // shifts the probe grid; the blip now splits
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(!events.contains("dropped"))
    let result = await session.finish()
    #expect(result == "p")
    #expect(events.contains("HIT"))
    #expect(await sum.total == Int(1.8 * 16_000)) // exactly one decode
}

/// The cut window is only RELATIVELY quiet (10 % of the chunk's peak), so soft
/// audio after a speculation's decoded end can form it; the poll that sees the
/// cut never re-checks the speculation. Reusing it there would skip that audio.
@Test func chunkCutDoesNotReuseSpeculationOverUnheardAudio() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWavSegments([(1.0, 0.5), (0.5, 0.0)]).write(to: url)

    var cfg = ChunkPlanner.Config()
    cfg.minChunkSeconds = 1.5
    cfg.maxChunkSeconds = 3.0
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in "p\(samples.count)" },
        config: cfg,
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(events.contains("started")) // over [0, 1.5 s)
    // Soft audio (RMS ≈ 0.014: above the 0.005 floor, below 10 % of the peak) → cut window [1.5, 1.8).
    try append(makeWavSegments([(0.3, 0.02)]), to: url)
    try await Task.sleep(nanoseconds: 120_000_000)
    #expect(!events.contains("reuses"))
    let result = await session.finish()
    #expect(result == "p26400 p2400") // chunk [0, 1.65 s) decoded in full, then the soft tail
}

/// Polls `condition` every 10 ms (up to 5 s): waits on real progress instead of
/// fixed sleeps, so the timing-sensitive tests hold on slow, parallel CI runners.
private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<500 {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private actor SlowIndexedMock {
    private(set) var counts: [Int] = []
    private let emptyAtCall: Int
    init(emptyAtCall: Int) { self.emptyAtCall = emptyAtCall }
    func next(_ n: Int) async -> String {
        counts.append(n)
        let call = counts.count
        try? await Task.sleep(nanoseconds: 150_000_000)
        return call == emptyAtCall ? "" : "piece\(call)"
    }
}

@Test func speechAfterTheSpeculatedAudioIsNotAHit() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    // The first poll speculates over 1.0 s speech + 0.6 s pause; more speech then
    // arrives and the stop press comes before any poll sees it. A HIT needs
    // silence after the speculation's DECODED END — so this must be a MISS that
    // decodes the whole pending audio, never the speculation alone.
    try makeWavSegments([(1.0, 0.5), (0.6, 0.0)]).write(to: url)
    let last = SampleSum()
    let events = EventLogBox()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await last.next(samples.count) },
        config: speculationConfig(),
        pollNanoseconds: 2_000_000_000,
        speculateAfterSeconds: 0.4,
        log: { events.add($0) }
    )
    await session.start(url: url)
    try await waitUntil { events.contains("started") } // the first poll speculated; the next is 2 s away
    try append(makeWavSegments([(0.5, 0.5), (0.2, 0.0)]), to: url)
    _ = await session.finish()
    #expect(events.contains("MISS"))
    #expect(await last.lastCount == Int(2.3 * 16_000))
}

@Test func drainedBacklogThenFailureCoversEverySampleOnce() async throws {
    let url = tempWavURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try makeWav(seconds: 5.2, amplitude: 0.5).write(to: url)
    // Slow decodes leave a backlog at the stop press; finish() drains it chunk
    // by chunk and the 5th chunk fails. Local recovery must start at the LAST
    // kept piece's true start: kept pieces + recovered region = every sample once.
    let slow = SlowIndexedMock(emptyAtCall: 5)
    let recovered = SampleSum()
    let session = StreamingTranscriptionSession(
        transcribe: { samples in await slow.next(samples.count) },
        recover: { samples in await recovered.next(samples.count) },
        config: fastConfig(),
        pollNanoseconds: 20_000_000,
        speculateAfterSeconds: 0
    )
    await session.start(url: url)
    try await waitUntil { await slow.counts.count >= 1 } // chunk 1 in flight; the rest is backlog
    let result = await session.finish()
    let counts = await slow.counts
    let regionSamples = await recovered.lastCount
    #expect(counts.count == 5)
    #expect(result == "piece1 piece2 piece3 p")
    #expect(counts.count == 5 && counts[0] + counts[1] + counts[2] + regionSamples == Int(5.2 * 16_000))
}
#endif
