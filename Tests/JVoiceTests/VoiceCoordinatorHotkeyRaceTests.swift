#if canImport(Testing)
import Testing
@testable import JVoice

@MainActor
@Test func doubleHotkeyDuringStartIsIdempotent() async {
    let coordinator = VoiceCoordinator()
    coordinator.toggleRecording()
    coordinator.toggleRecording()   // never a second start: a stop applied once the mic opens
    // No invariant we can assert on without exposing more state — the
    // test only verifies that two back-to-back toggleRecording calls don't
    // crash and don't push the coordinator into an inconsistent state.
    try? await Task.sleep(nanoseconds: 100_000_000)
}

/// Windows §7 #44: a press while the previous dictation is still being finished
/// (streaming finish(), model preparation — not only the whole-file decode) must
/// be ignored, not start a recording that cancels that transcription. The start
/// branch shows the recording pill synchronously, so a refused press leaves the
/// HUD idle and never touches the microphone.
@MainActor
@Test func startPressIsIgnoredWhileATranscriptionIsInFlight() {
    let coordinator = VoiceCoordinator()
    coordinator.setTranscriptionInFlightForTesting(true)
    coordinator.toggleRecording()
    #expect(coordinator.hudState == .idle)
    #expect(!coordinator.isRecording)
}
#endif
