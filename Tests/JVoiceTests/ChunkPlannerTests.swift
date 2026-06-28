#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

private func tone(seconds: Double, amplitude: Double) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
}

@Test func waitsBelowMinimumChunkLength() {
    #expect(ChunkPlanner.plan(unconsumed: tone(seconds: 10, amplitude: 0.5)) == .wait)
    #expect(ChunkPlanner.plan(unconsumed: []) == .wait)
}

@Test func waitsThroughContinuousSpeechUntilCap() {
    // 16 s of nonstop speech: no pause to cut at, cap not reached → wait.
    #expect(ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0.5)) == .wait)
}

@Test func cutsInsideAPauseAfterMinimum() throws {
    let audio = tone(seconds: 17, amplitude: 0.5) + tone(seconds: 1, amplitude: 0) + tone(seconds: 2, amplitude: 0.5)
    guard case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: audio) else {
        Issue.record("expected a cut inside the pause")
        return
    }
    #expect(at >= 17 * 16_000 && at <= 18 * 16_000)
    #expect(!silent)
}

@Test func cutsAtEarliestQualifyingPauseNotDeepest() throws {
    // Two sub-threshold pauses: pause A (amp 0.02 → ~0.014 RMS, below the
    // relative threshold but above silence) is earlier; pause B (0 RMS) is
    // deeper and later. The cut must land in pause A so the streaming chunk is
    // emitted sooner — every candidate below threshold is already a valid
    // boundary, so the earliest one is taken rather than the quietest.
    let audio = tone(seconds: 16, amplitude: 0.5)
        + tone(seconds: 1, amplitude: 0.02)
        + tone(seconds: 2, amplitude: 0.5)
        + tone(seconds: 1, amplitude: 0)
        + tone(seconds: 1, amplitude: 0.5)
    guard case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: audio) else {
        Issue.record("expected a cut at the earlier pause")
        return
    }
    #expect(at >= 16 * 16_000 && at <= 17 * 16_000)
    #expect(!silent)
}

@Test func forcesCutAtSingleWindowCap() {
    // 26 s of nonstop speech: cap exceeded → forced cut, bounded to the
    // proven single-window range.
    guard case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 26, amplitude: 0.5)) else {
        Issue.record("expected a forced cut past the cap")
        return
    }
    #expect(at >= 15 * 16_000 && at <= 25 * 16_000)
    #expect(!silent)
}

@Test func marksAllSilenceChunksAsSilent() {
    guard case let .cut(_, silent) = ChunkPlanner.plan(unconsumed: tone(seconds: 16, amplitude: 0)) else {
        Issue.record("silence still produces a cut (which is then dropped)")
        return
    }
    #expect(silent)
}

@Test func silenceDetectionUsesAbsoluteFloor() {
    #expect(ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0)))
    #expect(ChunkPlanner.isSilent([]))
    #expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.5)))
    #expect(!ChunkPlanner.isSilent(tone(seconds: 3, amplitude: 0.05))) // quiet speech is NOT silence
}

@Test func windowRMSCoversPartialFinalWindow() {
    let energies = ChunkPlanner.windowRMS(tone(seconds: 0.5, amplitude: 0.5)[...], window: 4_800)
    #expect(energies.count == 2) // 0.3 s window over 0.5 s → full + partial
    #expect(energies[1].start == 4_800)
}
#endif
