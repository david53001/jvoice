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

private actor IndexedEmptyMock {
    private let emptyAtCall: Int
    private var call = 0
    init(emptyAtCall: Int) { self.emptyAtCall = emptyAtCall }
    func next() -> String {
        call += 1
        return call == emptyAtCall ? "" : "piece\(call)"
    }
}
#endif
