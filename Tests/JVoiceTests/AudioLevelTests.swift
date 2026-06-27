#if canImport(Testing)
import Testing
@testable import JVoice

@Test func audioLevelClampsSilenceToZero() {
    #expect(AudioLevel.normalize(-160) == 0)
    #expect(AudioLevel.normalize(-55) == 0)
}

@Test func audioLevelClampsLoudToOne() {
    #expect(AudioLevel.normalize(0) == 1)
    #expect(AudioLevel.normalize(5) == 1)
}

@Test func audioLevelIsMonotonicInBetween() {
    let quiet = AudioLevel.normalize(-40)
    let mid = AudioLevel.normalize(-20)
    let loud = AudioLevel.normalize(-5)
    #expect(quiet < mid)
    #expect(mid < loud)
    #expect(quiet >= 0 && loud <= 1)
}

@Test func audioLevelHandlesNaN() {
    #expect(AudioLevel.normalize(Float.nan) == 0)
}
#endif
