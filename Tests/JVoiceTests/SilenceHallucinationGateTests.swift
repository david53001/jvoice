#if canImport(Testing)
import Testing
@testable import JVoice

// Mirrors windows/JVoice.Tests/SilenceHallucinationGateTests.cs, re-levelled for the
// macOS trigger and extended with the macOS verdict (a witness that shares no word
// with the prompted text also rejects it). Levels are peak 0.3 s-window RMS.

private let gateVocab = ["Vercel", "Ollama", "sub agents"]

// MARK: - shouldVerify: quiet audio that still produced text gets a witness

@Test func quietClipWithTextIsVerified() {
    let cases: [(Float, String)] = [
        // Windows-measured silent presses (below the macOS 0.005 rejector too).
        (0.0000, "see you soon."),
        (0.0001, "you"),
        (0.0003, "and that is all for today, and that is all for today."),
        // macOS synthetic non-speech levels measured 2026-09-23 (hum, hiss, breath):
        // above the 0.005 floor, so they reach the decoder today.
        (0.0196, "and then the Vercel,"),
        (0.0217, "and the rest of the road"),
        (0.0409, "The"),
        // Quiet real speech also verifies — and passes via resolve.
        (0.0300, "can you move the meeting to Friday"),
    ]
    for (rms, text) in cases {
        #expect(SilenceHallucinationGate.shouldVerify(peakRMS: rms, prompted: text))
    }
}

@Test func loudClipIsNotVerified() {
    let cases: [(Float, String)] = [
        // Synthetic `say` speech measured 2026-09-23: 0.10–0.25.
        (0.1049, "four digits then two letters"),
        (0.2522, "the first answer is eight choose three"),
        (0.0500, "exactly at the trigger is not quiet"),
    ]
    for (rms, text) in cases {
        #expect(!SilenceHallucinationGate.shouldVerify(peakRMS: rms, prompted: text))
    }
}

@Test(arguments: ["", "   "])
func blankTranscriptIsNotVerified(_ prompted: String) {
    #expect(!SilenceHallucinationGate.shouldVerify(peakRMS: 0, prompted: prompted))
}

@Test func nanLevelCountsAsQuiet() {
    #expect(SilenceHallucinationGate.shouldVerify(peakRMS: .nan, prompted: "see you soon."))
}

// MARK: - resolve: the witness (unprompted decode of the same audio) decides

@Test func emptyWitnessRejectsAsNoSpeech() {
    let cases: [(String, String)] = [
        ("see you soon.", ""),
        ("you", ""),
        ("Vercel", "   "),
        ("The", "..."),              // a witness with no words at all
    ]
    for (prompted, witness) in cases {
        #expect(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab) == "")
    }
}

@Test func witnessSharingNoWordRejectsAsNoSpeech() {
    // The macOS extension: both decodes produced text, but nothing in common.
    let cases: [(String, String)] = [
        ("and the rest of the road", "so"),
        ("The", "A"),
        ("Vercel, Olla, Vercel", "and so on"),
    ]
    for (prompted, witness) in cases {
        #expect(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab) == "")
    }
}

@Test func agreeingWitnessKeepsThePromptedTranscript() {
    // Real speech: same words either way, even when case, digits or the spelling
    // of a vocabulary word differ. The PROMPTED text is returned.
    let cases: [(String, String)] = [
        ("Hey, what's new?", "Hey, what's new?"),
        ("Move the meeting to Friday", "move the meeting to friday"),
        ("We need 3 more chairs", "We need three more chairs"),
        ("We pushed the preview build to Vercel.", "We pushed the preview build to Versil."),
        ("The main agent starts two sub agents.", "The main agent starts two sub-agents."),
    ]
    for (prompted, witness) in cases {
        #expect(SilenceHallucinationGate.resolve(prompted: prompted, witness: witness, vocabulary: gateVocab) == prompted)
    }
}

@Test func oneWordCustomWordSurvivesThroughItsSoundAlike() {
    // The prompt's whole job is respelling vocabulary, so a one-word dictation of
    // a custom word shares no LITERAL word with its witness. PhoneticMatcher maps
    // the witness back, so it is kept — and it would be dropped without the list.
    #expect(SilenceHallucinationGate.resolve(prompted: "Vercel.", witness: "Versil.", vocabulary: gateVocab) == "Vercel.")
    #expect(SilenceHallucinationGate.resolve(prompted: "Ollama", witness: "Olima", vocabulary: gateVocab) == "Ollama")
    #expect(SilenceHallucinationGate.resolve(prompted: "Vercel.", witness: "Versil.", vocabulary: []) == "")
}

// MARK: - peakWindowRMS is the rejector's measure

@Test func peakWindowRMSMatchesTheSilenceFloorScale() {
    // Just under / over ChunkPlanner's 0.005 floor, as a constant-level signal.
    let quiet = [Int16](repeating: 150, count: 16_000)   // 150/32768 ≈ 0.0046
    let audible = [Int16](repeating: 170, count: 16_000) // 170/32768 ≈ 0.0052
    #expect(ChunkPlanner.isSilent(quiet))
    #expect(!ChunkPlanner.isSilent(audible))
    #expect(SilenceHallucinationGate.peakWindowRMS(WavTail.floatSamples(quiet[...])) < ChunkPlanner.Config().silenceRMSFloor)
    #expect(SilenceHallucinationGate.peakWindowRMS(WavTail.floatSamples(audible[...])) >= ChunkPlanner.Config().silenceRMSFloor)
    #expect(SilenceHallucinationGate.peakWindowRMS([]) == 0)
}

@Test func peakWindowRMSIsTheLoudestWindowNotTheAverage() {
    // 0.9 s of silence then one 0.3 s window at half scale: the peak is that window.
    let samples = [Float](repeating: 0, count: 14_400) + [Float](repeating: 0.5, count: 4_800)
    #expect(abs(SilenceHallucinationGate.peakWindowRMS(samples) - 0.5) < 0.0001)
}
#endif
