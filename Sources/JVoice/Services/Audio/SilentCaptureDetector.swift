import Foundation

/// Sample-level statistics of one finished recording: how many of its 16-bit PCM
/// samples were not exactly zero.
public struct CaptureSignalStats: Equatable, Sendable {
    public let totalSamples: Int
    public let nonZeroSamples: Int
    public let seconds: Double

    public init(totalSamples: Int, nonZeroSamples: Int, seconds: Double) {
        self.totalSamples = totalSamples
        self.nonZeroSamples = nonZeroSamples
        self.seconds = seconds
    }

    /// Measures 16-bit PCM samples (the format `RecordingManager` writes and
    /// `WavTailReader.samples(from:)` returns).
    public init(samples: [Int16], sampleRate: Int) {
        var nonZero = 0
        for sample in samples where sample != 0 { nonZero += 1 }
        self.init(totalSamples: samples.count,
                  nonZeroSamples: nonZero,
                  seconds: sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0)
    }

    public var nonZeroRatio: Double {
        totalSamples > 0 ? Double(nonZeroSamples) / Double(totalSamples) : 0
    }
}

/// Tells "the input device delivered no signal at all" (an app-less virtual input
/// such as BlackHole, a muted device, input level 0) apart from "the user didn't
/// speak", so a dead input is reported as a DEVICE problem naming the device,
/// instead of the generic "We didn't hear anything" that blames the user.
/// Ported from the Windows port (`windows/JVoice.Core/Policy/SilentCaptureDetector.cs`,
/// docs/HANDOFF-WINDOWS.md §7 #46), where a virtual default mic delivered
/// bit-exact zeros (0 of 1,224,640 samples non-zero over 76 s).
///
/// NOT an amplitude/RMS gate: the discriminator is EXACT-ZERO samples. A real
/// microphone always carries a noise floor (an idle mic measured 99.46 % non-zero
/// on Windows); a dead endpoint returns exact zeros. And it is fail-safe by
/// construction: the caller consults it only on a path that is already showing a
/// no-speech error, so it can change that error's wording but never reject audio
/// or suppress a transcript.
public enum SilentCaptureDetector {
    /// Shorter recordings aren't judged — a very short clip can legitimately be
    /// all-zero (the device hasn't ramped up yet on its first frames).
    public static let minSecondsToJudge: Double = 0.35

    /// At or below this fraction of non-zero samples the input is dead. Far above
    /// the observed dead-device value (exactly 0) and far below a real idle mic's
    /// noise floor (~0.99).
    public static let maxNonZeroRatio: Double = 0.0005

    /// Device names longer than this are shortened so the fix ("System Settings >
    /// Sound") still fits the HUD's two-line error pill.
    public static let maxDeviceNameLength = 28

    public static func isDeadInput(_ stats: CaptureSignalStats) -> Bool {
        guard stats.totalSamples > 0 else { return false }           // nothing measured — don't guess
        guard stats.seconds >= minSecondsToJudge else { return false } // too short to judge fairly
        return stats.nonZeroRatio <= maxNonZeroRatio
    }

    /// The user-facing error for a dead input, naming the device so the fix is obvious.
    public static func deadInputMessage(deviceName: String?) -> String {
        let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subject: String
        if trimmed.isEmpty {
            subject = "Your microphone"
        } else if trimmed.count > maxDeviceNameLength {
            subject = "\"\(trimmed.prefix(maxDeviceNameLength - 1))…\""
        } else {
            subject = "\"\(trimmed)\""
        }
        return "\(subject) is sending no audio — pick another mic in System Settings > Sound."
    }

    /// The copy for a recording that produced no speech: the device-naming message
    /// when the recording is digital silence, else the usual `.noSpeechHeard` copy.
    /// `stats == nil` (the WAV couldn't be read) keeps the usual copy.
    public static func noSpeechMessage(stats: CaptureSignalStats?, deviceName: String?) -> String {
        guard let stats, isDeadInput(stats) else { return DictationError.noSpeechHeard.message }
        return deadInputMessage(deviceName: deviceName)
    }
}
