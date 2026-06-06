import Foundation

final class LastTranscriptStore {
    private let defaults: UserDefaults
    private static let key = "jvoice.app.lastTranscript"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var transcript: String {
        get { defaults.string(forKey: Self.key) ?? "" }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
