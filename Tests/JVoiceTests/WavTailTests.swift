#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

private func makeHeader(
    format: UInt16 = 1, channels: UInt16 = 1, rate: UInt32 = 16_000,
    bits: UInt16 = 16, fllrBytes: Int = 0, dataSize: UInt32 = 0
) -> [UInt8] {
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

@Test func parsesPlainHeader() {
    let info = WavTail.parseHeader(makeHeader())
    #expect(info?.dataOffset == 44)
    #expect(info?.sampleRate == 16_000)
}

@Test func parsesAppleFillerPaddedHeader() {
    // CoreAudio pads headers with a FLLR chunk; payload starts ~4 KB in.
    #expect(WavTail.parseHeader(makeHeader(fllrBytes: 4000))?.dataOffset == 44 + 8 + 4000)
}

@Test func toleratesStaleZeroDataSize() {
    // AVAudioRecorder patches RIFF/data sizes only on stop.
    #expect(WavTail.parseHeader(makeHeader(dataSize: 0))?.dataOffset == 44)
}

@Test func refusesForeignFormats() {
    #expect(WavTail.parseHeader(makeHeader(rate: 44_100)) == nil)
    #expect(WavTail.parseHeader(makeHeader(channels: 2)) == nil)
    #expect(WavTail.parseHeader(makeHeader(format: 3)) == nil)
    #expect(WavTail.parseHeader([UInt8]("RIFFxxxx".utf8)) == nil)
    #expect(WavTail.parseHeader([]) == nil)
}

@Test func readerStreamsGrowingFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wavtail-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var bytes = makeHeader()
    let firstSamples: [Int16] = [100, -200, 300]
    for s in firstSamples { bytes += [UInt8(UInt16(bitPattern: s) & 0xff), UInt8(UInt16(bitPattern: s) >> 8)] }
    try Data(bytes).write(to: url)

    let reader = try #require(WavTailReader.open(url: url))
    #expect(reader.samples(from: 0) == firstSamples)
    #expect(reader.samples(from: 3) == [])

    // File grows (plus a trailing odd byte mid-sample) — reader picks up only complete samples.
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0x2A, 0x00, 0x99])) // sample 42 + half a sample
    try handle.close()
    #expect(reader.samples(from: 3) == [42])
}

@Test func readerReportsVanishedFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wavtail-\(UUID().uuidString).wav")
    try Data(makeHeader()).write(to: url)
    let reader = try #require(WavTailReader.open(url: url))
    try FileManager.default.removeItem(at: url)
    #expect(reader.samples(from: 0) == nil)
}

@Test func floatScalingIsFullScale16Bit() {
    let floats = WavTail.floatSamples(([16_384, -16_384, 0] as [Int16])[...])
    #expect(abs(floats[0] - 0.5) < 0.001)
    #expect(abs(floats[1] + 0.5) < 0.001)
    #expect(floats[2] == 0)
}
#endif
