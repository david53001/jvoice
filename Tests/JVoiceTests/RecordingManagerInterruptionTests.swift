#if canImport(Testing)
import Testing
import AVFoundation
@testable import JVoice

@MainActor
@Test func configurationChangeStopsRecording() async throws {
    let manager = RecordingManager()
    manager.simulateConfigurationChangeForTesting()
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(manager.isRecording == false)
    #expect(manager.lastError != nil)
}

/// The torn-down recording is reported to the owner (the coordinator), exactly once.
@MainActor
@Test func configurationChangeNotifiesTheOwner() async throws {
    let manager = RecordingManager()
    var reported: [RecordingManager.RecordingError] = []
    manager.onRecordingFailed = { reported.append($0) }
    manager.simulateConfigurationChangeForTesting()
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(reported == [.encodeFailure(message: "Audio input changed mid-recording")])
}
#endif
