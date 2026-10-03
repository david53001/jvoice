#if canImport(Testing)
import Testing
@testable import JVoice

// Mirrors windows/JVoice.Tests/SparseTranscriptGuardTests.cs. The Windows failure:
// 32.11 s of audio decoded WITH the prompt to 61 chars (head + tail only, ≈ 1.9 chars/s)
// while the unprompted witness carried 566. The prompted stand-in below is original
// text of the same length and shape; only the lengths matter to the policy.
private let sparsePrompted = "Okay, first we plan the garden beds. water them nightly. Done"
private let sparseSeconds = 32.11
private let sparseWitness = String(repeating: "w", count: 566)

@Test func sparseGuardConstantsAreLocked() {
    // Calibrated on the Windows 30-clip sweep; changing one means recalibrating.
    #expect(sparsePrompted.count == 61)
    #expect(SparseTranscriptGuard.minAudioSeconds == 10.0)
    #expect(SparseTranscriptGuard.sparseCharsPerSecond == 4.0)
    #expect(SparseTranscriptGuard.witnessAdoptFactor == 2)
}

@Test func sparseGuardTriggersOnTheHeadAndTailDecode() {
    #expect(SparseTranscriptGuard.shouldVerify(audioSeconds: sparseSeconds, promptedTranscript: sparsePrompted))
}

@Test(arguments: [
    (62.58, 555),   // the sparsest legitimate long clip measured (8.87 chars/s)
    (12.49, 148),   // normal dictation density
    (97.10, 1255),  // a long clip after healing
    (32.62, 438),   // the swallowed paragraph, re-dictated
])
func sparseGuardIgnoresNormalDensity(_ seconds: Double, _ chars: Int) {
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: seconds, promptedTranscript: String(repeating: "x", count: chars)))
}

@Test(arguments: [
    (8.12, 10),  // a legitimately terse clip — but SHORT
    (3.97, 11),  // short mumble
    (9.99, 5),   // just under the audio floor
])
func sparseGuardNeverTriggersOnShortClips(_ seconds: Double, _ chars: Int) {
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: seconds, promptedTranscript: String(repeating: "x", count: chars)))
}

@Test func sparseGuardLeavesBlankTranscriptsToTheEmptyPath() {
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 30.0, promptedTranscript: ""))
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 30.0, promptedTranscript: "   "))
}

@Test func sparseGuardBoundaries() {
    // At exactly the audio floor, sparseness triggers.
    #expect(SparseTranscriptGuard.shouldVerify(audioSeconds: 10.0, promptedTranscript: String(repeating: "x", count: 39)))
    // chars == sparseCharsPerSecond × seconds is NOT sparse (strict <).
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 10.0, promptedTranscript: String(repeating: "x", count: 40)))
}

@Test func sparseGuardIgnoresZeroOrNonFiniteDurations() {
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: 0.0, promptedTranscript: "hi"))
    #expect(!SparseTranscriptGuard.shouldVerify(audioSeconds: .nan, promptedTranscript: "hi"))
}

@Test func sparseGuardAdoptsARicherWitness() {
    #expect(SparseTranscriptGuard.resolve(promptedTranscript: sparsePrompted, unpromptedWitness: sparseWitness) == sparseWitness)
}

@Test(arguments: [
    61,   // identical length (every legitimate sweep clip: ratio ≤ 1.1×)
    66,   // +10 % — normal prompt/no-prompt wording drift
    121,  // just under 2×
])
func sparseGuardKeepsPromptedWhenWitnessIsComparable(_ witnessChars: Int) {
    let witness = String(repeating: "w", count: witnessChars)
    #expect(SparseTranscriptGuard.resolve(promptedTranscript: sparsePrompted, unpromptedWitness: witness) == sparsePrompted)
}

@Test func sparseGuardAdoptsAnExactlyDoubleWitness() {
    let witness = String(repeating: "w", count: 122)
    #expect(SparseTranscriptGuard.resolve(promptedTranscript: sparsePrompted, unpromptedWitness: witness) == witness)
}

@Test(arguments: ["", "   "])
func sparseGuardNeverAdoptsABlankWitness(_ witness: String) {
    #expect(SparseTranscriptGuard.resolve(promptedTranscript: sparsePrompted, unpromptedWitness: witness) == sparsePrompted)
}
#endif
