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
#endif
