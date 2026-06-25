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

    func record(words: Int, durationSeconds: Double) {
        guard words > 0, durationSeconds > 0 else { return }
        totalWords += words
        totalSeconds += durationSeconds
    }
}
