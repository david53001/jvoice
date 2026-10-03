#if canImport(Testing)
import Testing
@testable import JVoice

private let rate = 16_000

/// A real mic's noise floor: small, mostly non-zero values.
private func noiseFloor(seconds: Double) -> [Int16] {
    (0..<Int(seconds * Double(rate))).map { Int16(($0 * 7919) % 9) - 4 }
}

@Test func measuresNonZeroSamples() {
    let stats = CaptureSignalStats(samples: [0, 1, 0, -3, 0, 0, 0, 2], sampleRate: 8)
    #expect(stats.totalSamples == 8)
    #expect(stats.nonZeroSamples == 3)
    #expect(stats.seconds == 1)
    #expect(stats.nonZeroRatio == 3.0 / 8.0)
}

@Test func digitalSilenceIsADeadInput() {
    let stats = CaptureSignalStats(samples: [Int16](repeating: 0, count: rate * 2), sampleRate: rate)
    #expect(SilentCaptureDetector.isDeadInput(stats))
}

@Test func aQuietRealMicIsNotADeadInput() {
    // Mostly non-zero even though it is far below any speech level.
    let stats = CaptureSignalStats(samples: noiseFloor(seconds: 2), sampleRate: rate)
    #expect(stats.nonZeroRatio > 0.5)
    #expect(!SilentCaptureDetector.isDeadInput(stats))
}

@Test func aMicThatRampsUpLateIsNotADeadInput() {
    // 0.3 s of start-up zeros, then a noise floor.
    let samples = [Int16](repeating: 0, count: Int(0.3 * Double(rate))) + noiseFloor(seconds: 0.7)
    #expect(!SilentCaptureDetector.isDeadInput(CaptureSignalStats(samples: samples, sampleRate: rate)))
}

@Test func tooShortOrEmptyRecordingsAreNotJudged() {
    let short = CaptureSignalStats(samples: [Int16](repeating: 0, count: Int(0.2 * Double(rate))), sampleRate: rate)
    #expect(!SilentCaptureDetector.isDeadInput(short))
    #expect(!SilentCaptureDetector.isDeadInput(CaptureSignalStats(samples: [], sampleRate: rate)))
}

@Test func deadInputMessageNamesTheDevice() {
    let message = SilentCaptureDetector.deadInputMessage(deviceName: "BlackHole 16ch")
    #expect(message.contains("\"BlackHole 16ch\""))
    #expect(message.contains("System Settings > Sound"))
}

@Test func deadInputMessageWithoutANameFallsBackToYourMicrophone() {
    #expect(SilentCaptureDetector.deadInputMessage(deviceName: nil).hasPrefix("Your microphone"))
    #expect(SilentCaptureDetector.deadInputMessage(deviceName: "  ").hasPrefix("Your microphone"))
}

@Test func longDeviceNamesAreShortenedSoTheFixStaysVisible() {
    let long = String(repeating: "x", count: 80)
    let message = SilentCaptureDetector.deadInputMessage(deviceName: long)
    #expect(message.contains("…\""))
    #expect(!message.contains(long))
    #expect(message.hasSuffix("System Settings > Sound."))
}

/// Fail-safe: only a digital-silence recording changes the copy; anything else
/// (quiet real mic, unreadable file) keeps the usual no-speech message.
@Test func noSpeechMessageChangesOnlyForDigitalSilence() {
    let dead = CaptureSignalStats(samples: [Int16](repeating: 0, count: rate), sampleRate: rate)
    let quiet = CaptureSignalStats(samples: noiseFloor(seconds: 1), sampleRate: rate)
    #expect(SilentCaptureDetector.noSpeechMessage(stats: dead, deviceName: "BlackHole 16ch")
        == SilentCaptureDetector.deadInputMessage(deviceName: "BlackHole 16ch"))
    #expect(SilentCaptureDetector.noSpeechMessage(stats: quiet, deviceName: "MacBook Air Microphone")
        == DictationError.noSpeechHeard.message)
    #expect(SilentCaptureDetector.noSpeechMessage(stats: nil, deviceName: "BlackHole 16ch")
        == DictationError.noSpeechHeard.message)
}
#endif
