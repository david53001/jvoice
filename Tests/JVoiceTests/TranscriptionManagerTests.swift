#if canImport(Testing)
import Foundation
import Testing
@testable import JVoice

@Test
func fileBackedEngineRejectsBinaryAudio() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jvoice-\(UUID().uuidString).m4a")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)

    defer {
        try? FileManager.default.removeItem(at: url)
    }

    let engine = FileBackedTranscriptionEngine()
    var rejectedBinaryAudio = false

    do {
        _ = try await engine.transcribe(audioURL: url)
    } catch let error as TranscriptionError {
        rejectedBinaryAudio = (error == .unsupportedAudioFile(url))
    } catch {
        rejectedBinaryAudio = false
    }

    #expect(rejectedBinaryAudio)
}

@MainActor
@Test func updateEngineDuringTranscriptionDefersSwap() async {
    let manager = TranscriptionManager()
    let originalEngine = manager.engineForTesting

    manager.setTranscribingForTesting(true)
    let newEngine = MockTranscriptionEngine()
    manager.updateEngine(newEngine)
    #expect(manager.engineForTesting as AnyObject === originalEngine as AnyObject)

    manager.setTranscribingForTesting(false)
    manager.applyPendingEngineForTesting()
    #expect(manager.engineForTesting as AnyObject === newEngine as AnyObject)
}

private final class MockTranscriptionEngine: TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String { return "" }
}

#elseif canImport(XCTest)
import Foundation
import XCTest
@testable import JVoice

final class TranscriptionManagerTests: XCTestCase {
    func testFileBackedEngineRejectsBinaryAudio() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jvoice-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)

        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let engine = FileBackedTranscriptionEngine()
        var rejectedBinaryAudio = false

        do {
            _ = try await engine.transcribe(audioURL: url)
        } catch let error as TranscriptionError {
            rejectedBinaryAudio = (error == .unsupportedAudioFile(url))
        } catch {
            rejectedBinaryAudio = false
        }

        XCTAssertTrue(rejectedBinaryAudio)
    }
}

#else
import Foundation
@testable import JVoice

enum TranscriptionManagerTestsFallback {
    static func run() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jvoice-\(UUID().uuidString).m4a")
        try? Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let engine = FileBackedTranscriptionEngine()
        let result: Bool

        do {
            _ = try await engine.transcribe(audioURL: url)
            result = false
        } catch let error as TranscriptionError {
            result = (error == .unsupportedAudioFile(url))
        } catch {
            result = false
        }

        assert(result)
    }
}
#endif
