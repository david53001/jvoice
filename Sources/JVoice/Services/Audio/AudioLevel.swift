import Foundation

/// Pure mapping from an `AVAudioRecorder` average-power reading (dBFS, roughly
/// -160…0) to a 0…1 amplitude for the waveform bars. Kept dependency-free so
/// it runs in both the swift-testing suite and scripts/run-logic-tests.sh.
public enum AudioLevel {
    /// `floor` is the quietest dB treated as "silence" (maps to 0). Speech sits
    /// well above -55 dBFS, so anything below it flattens the bars.
    public static func normalize(_ db: Float, floor: Float = -55) -> Float {
        if db.isNaN { return 0 }
        if db <= floor { return 0 }
        if db >= 0 { return 1 }
        return (db - floor) / (0 - floor)
    }
}
