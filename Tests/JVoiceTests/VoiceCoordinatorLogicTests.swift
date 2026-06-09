#if canImport(Testing)
import Testing
@testable import JVoice

// MARK: - resolveTargetPID (BLD-06)

@Test
func resolveTargetPID_normalFrontmostApp_returnsIt() {
    let result = VoiceCoordinator.resolveTargetPID(frontmostPID: 42, ownPID: 7, lastNonSelfPID: 99)
    #expect(result == 42)
}

@Test
func resolveTargetPID_frontmostIsSelf_fallsBackToLastNonSelf() {
    let result = VoiceCoordinator.resolveTargetPID(frontmostPID: 7, ownPID: 7, lastNonSelfPID: 99)
    #expect(result == 99)
}

@Test
func resolveTargetPID_frontmostIsSelfAndNoFallback_returnsNil() {
    let result = VoiceCoordinator.resolveTargetPID(frontmostPID: 7, ownPID: 7, lastNonSelfPID: nil)
    #expect(result == nil)
}

@Test
func resolveTargetPID_noFrontmost_fallsBackToLastNonSelf() {
    let result = VoiceCoordinator.resolveTargetPID(frontmostPID: nil, ownPID: 7, lastNonSelfPID: 99)
    #expect(result == 99)
}

// MARK: - shouldPromptAX (BLD-20)

@Test
func shouldPromptAX_notTrustedNotPrompted_prompts() {
    #expect(VoiceCoordinator.shouldPromptAX(trusted: false, hasPrompted: false) == true)
}

@Test
func shouldPromptAX_notTrustedAlreadyPrompted_doesNotPrompt() {
    #expect(VoiceCoordinator.shouldPromptAX(trusted: false, hasPrompted: true) == false)
}

@Test
func shouldPromptAX_trusted_doesNotPrompt() {
    #expect(VoiceCoordinator.shouldPromptAX(trusted: true, hasPrompted: false) == false)
    #expect(VoiceCoordinator.shouldPromptAX(trusted: true, hasPrompted: true) == false)
}

// MARK: - fixLastTranscript / revertLastFix round-trip (BLD-06 revert)

@MainActor
@Test
func fixLastTranscript_thenRevert_restoresStateAndVocabulary() {
    let coordinator = VoiceCoordinator()

    // Seed a known last transcript via a first fix (from empty), then reset the
    // vocabulary + revert buffer so the round-trip below starts from a clean,
    // deterministic state (no case-insensitive collisions with seed words).
    coordinator.fixLastTranscript("python is great")
    coordinator.customWords = []
    coordinator.clearRevertBuffer()
    #expect(coordinator.lastTranscript == "python is great")

    // Real round-trip: a same-word-count case change yields exactly one
    // corrected word ("Python"), which becomes a new custom word.
    coordinator.fixLastTranscript("Python is great")
    #expect(coordinator.lastTranscript == "Python is great")
    #expect(coordinator.customWords.contains("Python"))
    #expect(coordinator.canRevert == true)

    coordinator.revertLastFix()
    #expect(coordinator.lastTranscript == "python is great")
    #expect(!coordinator.customWords.contains("Python"))
    #expect(coordinator.canRevert == false)
}

// MARK: - addCustomWord validation (UI-09)

@MainActor
@Test
func addCustomWord_rejectsEmptyPunctuationOversizeAndCaseDuplicates() {
    let coordinator = VoiceCoordinator()
    coordinator.customWords = []

    #expect(coordinator.addCustomWord("   ") == nil)
    #expect(coordinator.addCustomWord("!!!") == nil)
    #expect(coordinator.addCustomWord(String(repeating: "a", count: 61)) == nil)

    #expect(coordinator.addCustomWord("VS Code") == "VS Code")
    // Case-insensitive duplicate rejected.
    #expect(coordinator.addCustomWord("vs code") == nil)
    // Trimmed, returned value is the normalized (trimmed) word.
    #expect(coordinator.addCustomWord("  Swift  ") == "Swift")

    #expect(coordinator.customWords.contains("VS Code"))
    #expect(coordinator.customWords.contains("Swift"))
}
#endif
