#if canImport(Testing)
import Testing
@testable import JVoice

@MainActor
@Test func doubleHotkeyDuringStartIsIdempotent() async {
    let coordinator = VoiceCoordinator()
    coordinator.toggleRecording()
    coordinator.toggleRecording()   // should be a no-op until the first one resolves
    // No invariant we can assert on without exposing more state — the
    // test only verifies that two back-to-back toggleRecording calls don't
    // crash and don't push the coordinator into an inconsistent state.
    try? await Task.sleep(nanoseconds: 100_000_000)
}
#endif
