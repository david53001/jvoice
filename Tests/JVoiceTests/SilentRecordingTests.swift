#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

/// Build a minimal PCM/16-bit/mono/16 kHz WAV on disk from Int16 samples so the
/// real WAV-reading + silence path is exercised (matches RecordingManager's
/// output format, which WavTailReader requires).
private func writeWav(_ samples: [Int16]) throws -> URL {
    func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]
    }
    let dataBytes = samples.flatMap { le16(UInt16(bitPattern: $0)) }
    var bytes: [UInt8] = Array("RIFF".utf8) + le32(UInt32(36 + dataBytes.count)) + Array("WAVE".utf8)
    bytes += Array("fmt ".utf8) + le32(16)
    bytes += le16(1) + le16(1) + le32(16_000)
    bytes += le32(16_000 * 2) + le16(2) + le16(16)
    bytes += Array("data".utf8) + le32(UInt32(dataBytes.count)) + dataBytes
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("jvoice-test-\(UUID().uuidString).wav")
    try Data(bytes).write(to: url)
    return url
}

private func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}

@Test func silentRecordingDetected() throws {
    let url = try writeWav(tone(seconds: 1, amplitude: 0.0))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(RecordingManager.isSilentRecording(at: url))
}

@Test func speechRecordingNotSilent() throws {
    let url = try writeWav(tone(seconds: 1, amplitude: 0.5))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(!RecordingManager.isSilentRecording(at: url))
}

@Test func unreadableRecordingFailsOpen() {
    let bogus = URL(fileURLWithPath: "/nonexistent/jvoice-missing.wav")
    #expect(!RecordingManager.isSilentRecording(at: bogus))
}
#endif
