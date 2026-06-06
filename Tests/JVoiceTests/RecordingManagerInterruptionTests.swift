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
#endif
