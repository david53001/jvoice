import Foundation

final class StatsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var totalWords: Int {
        get { defaults.integer(forKey: "jvoice.app.stats.totalWords") }
        set { defaults.set(newValue, forKey: "jvoice.app.stats.totalWords") }
    }

    private var totalSeconds: Double {
        get { defaults.double(forKey: "jvoice.app.stats.totalSeconds") }
        set { defaults.set(newValue, forKey: "jvoice.app.stats.totalSeconds") }
    }

    var averageWPM: Double {
        guard totalSeconds > 0 else { return 0 }
        return (Double(totalWords) / totalSeconds) * 60.0
    }

    /// Estimated minutes saved by dictating instead of typing: how much longer it
    /// would have taken to TYPE the dictated words (at a 40-wpm typist baseline)
    /// than it took to SPEAK them. Floored at 0 so a slow dictation never reports
    /// negative savings. Port of the Windows `StatsMath.EstimatedMinutesSaved`.
    var estimatedMinutesSaved: Double {
        guard totalWords > 0 else { return 0 }
        let typingMinutes = Double(totalWords) / 40.0
        let spokenMinutes = totalSeconds > 0 ? totalSeconds / 60.0 : 0
        return max(0, typingMinutes - spokenMinutes)
    }

    func record(words: Int, durationSeconds: Double) {
        guard words > 0, durationSeconds > 0 else { return }
        totalWords += words
        totalSeconds += durationSeconds
    }
}
