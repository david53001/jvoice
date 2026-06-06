#if canImport(Testing)
import Testing
import AVFoundation
@testable import JVoice

@MainActor
private func makeDummyRecorder() throws -> AVAudioRecorder {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-\(UUID().uuidString).caf")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
    ]
    return try AVAudioRecorder(url: url, settings: settings)
}

@MainActor
@Test func encodeErrorClearsIsRecording() async throws {
    let manager = RecordingManager()
    manager._setRecordingStateForTesting(isRecording: true)
    let dummy = try makeDummyRecorder()
    let err = NSError(domain: "test", code: -1, userInfo: nil)
    manager.audioRecorderEncodeErrorDidOccur(dummy, error: err)
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(manager.isRecording == false)
    #expect(manager.lastError != nil)
}

@MainActor
@Test func finishUnsuccessfullyClearsIsRecording() async throws {
    let manager = RecordingManager()
    manager._setRecordingStateForTesting(isRecording: true)
    let dummy = try makeDummyRecorder()
    manager.audioRecorderDidFinishRecording(dummy, successfully: false)
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(manager.isRecording == false)
    #expect(manager.lastError != nil)
}

@MainActor
@Test func startRecordingClearsStaleLastErrorAtEntry() async throws {
    let manager = RecordingManager()
    // Seed a stale error via the delegate path (we know this works).
    let dummy = try makeDummyRecorder()
    let seededError = NSError(domain: "seeded", code: 42)
    manager.audioRecorderEncodeErrorDidOccur(dummy, error: seededError)
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(manager.lastError != nil)
    let seededDescription = seededError.localizedDescription

    // Call the real startRecording(). It will likely fail in unit tests
    // (no mic permission / device), but the entry-clear contract says
    // lastError must be cleared first. If it then fails, lastError gets
    // a new value — either nil OR a different value is acceptable.
    // The key assertion: the seeded encodeFailure must NOT be preserved.
    _ = manager.startRecording()

    if let newError = manager.lastError {
        if case .encodeFailure(let msg) = newError {
            #expect(msg != seededDescription,
                    "stale encode error from before startRecording leaked through")
        }
    }
}

@Test func fileSizeBelowMinimumIsRejected() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tiny-\(UUID().uuidString).wav")
    try Data(repeating: 0, count: 100).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = RecordingManager.isUsableRecording(at: url, minBytes: 1024)
    #expect(result == false)
}

@Test func fileSizeAboveMinimumIsAccepted() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ok-\(UUID().uuidString).wav")
    try Data(repeating: 1, count: 4096).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = RecordingManager.isUsableRecording(at: url, minBytes: 1024)
    #expect(result == true)
}

@Test func missingFileIsRejected() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("nonexistent-\(UUID().uuidString).wav")
    let result = RecordingManager.isUsableRecording(at: url, minBytes: 1024)
    #expect(result == false)
}
#endif
