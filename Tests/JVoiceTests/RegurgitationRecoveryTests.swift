#if canImport(Testing)
import Testing
@testable import JVoice

private let recVocab = ["sub agents", "claude", "li-fraumeni", "vs code"]
private let regurg = "so the thing about money is that sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code"

private actor DecodeRecorder {
    private(set) var calls: [Bool] = []
    let promptResult: String
    let cleanResult: String
    init(_ promptResult: String, _ cleanResult: String) { self.promptResult = promptResult; self.cleanResult = cleanResult }
    func decode(_ usePrompt: Bool) -> String { calls.append(usePrompt); return usePrompt ? promptResult : cleanResult }
}

@Test func regurgitatedDecodeRecoversViaPromptFreeReDecode() async {
    let rec = DecodeRecorder(regurg, "the actual spoken sentence about the economy")
    let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
    #expect(out == "the actual spoken sentence about the economy")
    #expect(await rec.calls == [true, false])
}

@Test func cleanPromptedDecodeIsKeptWithoutReDecode() async {
    let rec = DecodeRecorder("I use VS Code and Claude every day with my sub agents", "SHOULD NOT BE USED")
    let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
    #expect(out == "I use VS Code and Claude every day with my sub agents")
    #expect(await rec.calls == [true])
}

@Test func emptyPromptedDecodeRecoversSpeech() async {
    let rec = DecodeRecorder("", "recovered speech that was nearly lost")
    let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: recVocab) { await rec.decode($0) }
    #expect(out == "recovered speech that was nearly lost")
    #expect(await rec.calls == [true, false])
}

@Test func promptDisabledDoesASinglePromptFreeDecode() async {
    let rec = DecodeRecorder("UNUSED", "plain decode result")
    let out = await RegurgitationRecovery.decode(useVocabularyPrompt: false, vocabulary: recVocab) { await rec.decode($0) }
    #expect(out == "plain decode result")
    #expect(await rec.calls == [false])
}

// MARK: - Witness triggers (2026-09-23): loop anywhere, sparse, quiet, recited list

private let userVocab = ["sub agents", "AISB", "Li-Fraumeni", "Vercel", "Ollama"]

@Test func midTextLoopAdoptsTheWitness() async {
    let loop = "we met at noon and " + String(repeating: "the plan is on track. ", count: 8) + "then we left for the airport"
    let rec = DecodeRecorder(loop, "we met at noon and the plan is on track. then we reviewed the budget and left for the airport")
    let out = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab) { await rec.decode($0) }
    #expect(out.contains("reviewed the budget"))
    #expect(await rec.calls == [true, false])
}

@Test func sparseDecodeAdoptsARicherWitnessButKeepsATerseOne() async {
    let rich = DecodeRecorder("Now next, the chapter opens. not forgiven. Amen, that's it.",
                              "a full sentence the prompted decode skipped over, then the part about the budget review, the new hires starting on Monday, and the plan for the office move next spring, plus the reminder to send the slides.")
    let adopted = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 30) { await rich.decode($0) }
    #expect(adopted.hasPrefix("a full sentence"))
    let terse = DecodeRecorder("Yes, that works for me.", "Yes that works for me")
    let kept = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 12) { await terse.decode($0) }
    #expect(kept == "Yes, that works for me.")
}

@Test func quietHallucinationIsRejectedButQuietSpeechIsKept() async {
    let hiss = DecodeRecorder("and the other side of the body", "so")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 4, peakRMS: 0.02) { await hiss.decode($0) } == "")
    let quiet = DecodeRecorder("We run Ollama and deploy to Vercel", "We run Alima and deploy to Versil.")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 4, peakRMS: 0.02) { await quiet.decode($0) } == "We run Ollama and deploy to Vercel")
    let loud = DecodeRecorder("Can you move it to Thursday?", "UNUSED")
    _ = await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 4, peakRMS: 0.15) { await loud.decode($0) }
    #expect(await loud.calls == [true])
}

@Test func recitedVocabularyListIsRejectedButDictatedCustomWordsAreKept() async {
    let hum = DecodeRecorder("BISB, Li-Fraumeni, Vercel, Oluf", "")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 4, peakRMS: 0.08) { await hum.decode($0) } == "")
    let sentence = DecodeRecorder("Vercel and Ollama", "UNUSED")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 2, peakRMS: 0.15) { await sentence.decode($0) } == "Vercel and Ollama")
    #expect(await sentence.calls == [true])
    let list = DecodeRecorder("Vercel, Ollama, and AISB", "Versil, Alima, and AISB.")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 3, peakRMS: 0.15) { await list.decode($0) } == "Vercel, Ollama, and AISB")
}

@Test func dictatedMathsRepetitionCostsOneDecode() async {
    let maths = DecodeRecorder("and then it's 26 x 26 x 26 x 10 x 10 x 10", "UNUSED")
    #expect(await RegurgitationRecovery.decode(useVocabularyPrompt: true, vocabulary: userVocab, audioSeconds: 5, peakRMS: 0.15) { await maths.decode($0) } == "and then it's 26 x 26 x 26 x 10 x 10 x 10")
    #expect(await maths.calls == [true])
}

@Test func vocabularyListNeedsListShapeAndTwoCustomWords() {
    #expect(RepetitionGuard.isVocabularyList("BISB, Li-Fraumeni, Vercel, Oluf", vocabulary: userVocab))
    #expect(!RepetitionGuard.isVocabularyList("I use VS Code and Claude every day with my sub agents", vocabulary: ["sub agents", "claude", "li-fraumeni", "vs code"]))
    #expect(!RepetitionGuard.isVocabularyList("apples, pears, plums, and figs", vocabulary: userVocab))
    #expect(!RepetitionGuard.isVocabularyList("Vercel,", vocabulary: userVocab))
}
#endif
