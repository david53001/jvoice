#if canImport(Testing)
import Testing
@testable import JVoice

// PhraseLoopGuard: a decoder loop in the MIDDLE of a transcript (the Windows
// port's §7 #42/#45 failure shape) — invisible to the trailing-only
// RepetitionGuard — while dictated maths and emphasis stay untouched.

private func occurrences(of needle: String, in text: String) -> Int {
    text.lowercased().components(separatedBy: needle.lowercased()).count - 1
}

private let loopVocab = ["sub agents", "AISB", "Li-Fraumeni", "Vercel", "Ollama"]

private let sentenceLoop =
    "After lunch we walked down to the harbor, and the captain told us that "
    + String(repeating: "The ferry leaves at noon. ", count: 16)
    + "Then we bought our tickets and waited on the pier for about an hour."

private let clause = "the new library downtown has a huge reading room and i used to go there every weekend but now i work so"
private let clauseLoop = "okay so about the city "
    + String(repeating: clause + " ", count: 6)
    + "anyway that is my update for today and i will call you tomorrow"

// MARK: - Constants

@Test func phraseLoopConstantsAreLocked() {
    #expect(PhraseLoopGuard.minRepeats == 4)
    #expect(PhraseLoopGuard.maxPhraseTokens == 32)
    #expect(PhraseLoopGuard.minLoopTokens == 16)
    #expect(PhraseLoopGuard.mathMinRepeats == 12)
}

// MARK: - Mid-transcript loops are caught

@Test func midTranscriptSentenceLoopCollapsesToOneOccurrence() {
    let result = PhraseLoopGuard.collapse(sentenceLoop)
    #expect(result.foundLoop)
    #expect(occurrences(of: "ferry leaves at noon", in: result.text) == 1)
    #expect(result.text.hasPrefix("After lunch we walked down to the harbor"))
    #expect(result.text.hasSuffix("waited on the pier for about an hour."))
    // The trailing-only guard cannot see it: speech resumes after the loop.
    #expect(!RepetitionGuard.scrub(sentenceLoop, vocabulary: loopVocab).removedRegurgitation)
}

@Test func longPeriodClauseLoopIsCaught() {
    // A 22-token clause ×6 — above RepetitionGuard's 12-token phrase window.
    let result = PhraseLoopGuard.collapse(clauseLoop)
    #expect(result.foundLoop)
    #expect(occurrences(of: "reading room", in: result.text) == 1)
    #expect(result.text == "okay so about the city " + clause + " anyway that is my update for today and i will call you tomorrow")
    #expect(!RepetitionGuard.scrub(clauseLoop, vocabulary: []).removedRegurgitation)
}

@Test func midTranscriptVocabularyRegurgitationIsCaught() {
    let input = "we deployed the new build on friday and then "
        + String(repeating: "sub agents, AISB, Li-Fraumeni, Vercel, Ollama, ", count: 5)
        + "after that everyone packed up their laptops and went home early for the long weekend"
    let result = PhraseLoopGuard.collapse(input)
    #expect(result.foundLoop)
    #expect(occurrences(of: "Li-Fraumeni", in: result.text) == 1)
    #expect(result.text.hasSuffix("for the long weekend"))
    #expect(!RepetitionGuard.scrub(input, vocabulary: loopVocab).removedRegurgitation)
}

@Test func loopBrokenByOneMangledRepeatStillCollapsesBothHalves() {
    let input = "so the plan is "
        + String(repeating: "we meet at the station ", count: 5)
        + "we meat at the station "
        + String(repeating: "we meet at the station ", count: 5)
        + "and then we take the bus together to the office"
    let result = PhraseLoopGuard.collapse(input)
    #expect(result.foundLoop)
    #expect(result.text == "so the plan is we meet at the station we meat at the station we meet at the station and then we take the bus together to the office")
}

// MARK: - Dictated maths is never a loop

@Test(arguments: [
    // RepetitionGuardTests' maths cases — the 2026-09-23 fix must hold here too.
    "and then it's 26 x 26 x 26 x 10 x 10 x 10",
    "and then it's 26 times 26 times 26 times 10 times 10 times 10",
    "So the answer is minus 3 minus 3 minus 3 minus 3",
    "1 over 2 plus 1 over 4 plus 1 over 8 plus 1 over 16",
    "2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 is 256",
    "ten times ten times ten times ten is ten thousand",
    "five letters so 26 times 26 times 26 times 26 times 26 times 26",
    // Longer dictated repeats.
    "so 2 to the tenth is 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 x 2 which is 1024",
    "x times x times x times x times x times x times x is x to the seventh",
    "1 over 2 plus 1 over 2 plus 1 over 2 plus 1 over 2 plus 1 over 2 equals 5 over 2",
    "count it out 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4 and then the chorus starts",
    "one half plus one half plus one half plus one half plus one half is two and a half",
])
func dictatedMathsRepetitionIsNotAPhraseLoop(_ maths: String) {
    #expect(!PhraseLoopGuard.hasLoop(maths))
    #expect(PhraseLoopGuard.collapse(maths).text == maths)
    let embedded = "okay for the homework question " + maths + " and then we move on to the next problem on the sheet"
    #expect(PhraseLoopGuard.collapse(embedded).text == embedded)
}

// MARK: - Emphasis is never a loop

@Test(arguments: [
    "No, no, no, no, that is not what I asked for at all, please read it again.",
    "Honestly the concert was very, very, very, very good and we stayed until the end.",
    "Come on, come on, come on, come on, we are going to be late for the train again.",
    "Ha ha ha ha ha ha ha ha, that was the funniest thing I have heard all week long.",
    "I love you, I love you, I love you, I love you, said the little card on the table.",
    "Please please please please please let the build pass this time around, I am begging.",
    "Tick tock, tick tock, tick tock, tick tock, the clock on the wall kept going all night.",
    "Four more days, four more days, four more days, four more days until the holiday starts.",
])
func emphasisIsNotAPhraseLoop(_ text: String) {
    #expect(!PhraseLoopGuard.hasLoop(text))
    #expect(PhraseLoopGuard.collapse(text).text == text)
}

// MARK: - Thresholds

@Test func coverageBoundary() {
    // 4-token phrase ×4 = 16 tokens: a loop.
    #expect(PhraseLoopGuard.hasLoop("we said " + String(repeating: "we need more chairs ", count: 4) + "for the party tonight"))
    // 3-token phrase ×5 = 15 tokens: not.
    #expect(!PhraseLoopGuard.hasLoop("we said " + String(repeating: "more chairs please ", count: 5) + "for the party tonight"))
    // 2-token phrase: ×8 is a loop, ×7 is not.
    #expect(PhraseLoopGuard.hasLoop("and then " + String(repeating: "thank you ", count: 8) + "for coming everyone"))
    #expect(!PhraseLoopGuard.hasLoop("and then " + String(repeating: "thank you ", count: 7) + "for coming everyone"))
}

@Test func mathsPhraseNeedsTwelveRepeats() {
    let before = "the total is ", after = "and that is the whole bill for the month"
    #expect(!PhraseLoopGuard.hasLoop(before + String(repeating: "minus 3 ", count: 11) + after))
    let twelve = PhraseLoopGuard.collapse(before + String(repeating: "minus 3 ", count: 12) + after)
    #expect(twelve.foundLoop)
    #expect(twelve.text == before + "minus 3 " + after)
}

@Test func matchingIgnoresCaseAndPunctuationAndKeepsTheFirstVerbatim() {
    let result = PhraseLoopGuard.collapse("Hold on a second. hold on a second, HOLD ON A SECOND hold on a second!")
    #expect(result.foundLoop)
    #expect(result.text == "Hold on a second.")
}

@Test func smallestPeriodWins() {
    let result = PhraseLoopGuard.collapse(String(repeating: "again then ", count: 8))
    #expect(result.text == "again then")
}

@Test func phraseLengthCap() {
    let words32 = (1...32).map { "w\($0)" }.joined(separator: " ")
    #expect(PhraseLoopGuard.collapse(Array(repeating: words32, count: 4).joined(separator: " ")).text == words32)
    let words33 = (1...33).map { "w\($0)" }.joined(separator: " ")
    let above = Array(repeating: words33, count: 4).joined(separator: " ")
    #expect(!PhraseLoopGuard.hasLoop(above))
}

// MARK: - Run edges

@Test func trailingPartialRepeatStays() {
    let result = PhraseLoopGuard.collapse(String(repeating: "wait for me ", count: 6) + "wait for")
    #expect(result.foundLoop)
    #expect(result.text == "wait for me wait for")
}

@Test func allLoopKeepsOnePhraseNeverEmpty() {
    #expect(PhraseLoopGuard.collapse(String(repeating: "the end ", count: 10)).text == "the end")
}

@Test func twoSeparateLoopsBothCollapse() {
    let input = String(repeating: "left side ", count: 8) + "middle words here " + String(repeating: "right side ", count: 8)
    #expect(PhraseLoopGuard.collapse(input).text == "left side middle words here right side")
}

@Test func cleanTextIsReturnedUnchanged() {
    let text = "Throughout the week,\nwe kept the office\tquiet so the team could focus on the release notes and the demo."
    let result = PhraseLoopGuard.collapse(text)
    #expect(!result.foundLoop)
    #expect(result.text == text)
    for short in ["", "   ", "one two three"] {
        #expect(PhraseLoopGuard.collapse(short) == .init(text: short, foundLoop: false))
    }
}

// MARK: - resolve: the unprompted witness is preferred

@Test func resolvePrefersTheWitness() {
    let witness = "the captain told us that the ferry leaves at noon and the next one is at three"
    #expect(PhraseLoopGuard.resolve(looped: sentenceLoop, witness: witness) == witness)
}

@Test(arguments: ["", "   "])
func resolveWithoutAWitnessCollapsesThePrimary(_ witness: String) {
    let resolved = PhraseLoopGuard.resolve(looped: sentenceLoop, witness: witness)
    #expect(occurrences(of: "ferry leaves at noon", in: resolved) == 1)
    #expect(resolved.hasSuffix("for about an hour."))
}

@Test func resolveCollapsesALoopedWitness() {
    let witness = "he said " + String(repeating: "wait ", count: 16) + "and left the room"
    #expect(PhraseLoopGuard.resolve(looped: sentenceLoop, witness: witness) == "he said wait and left the room")
}
#endif
