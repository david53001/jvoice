import Foundation

/// One persisted transcript in the recent-history list. `id` gives SwiftUI a
/// stable identity for rows (delete-by-id) independent of the text.
struct TranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// Remembers the most recent transcripts (newest first), capped at `maxEntries`.
///
/// Persisted as JSON in `UserDefaults` (same plaintext-in-prefs posture as
/// `LastTranscriptStore`): a few dozen short dictation snippets is only a few KB,
/// disk-backed and lazily loaded, so nothing heavy stays resident. Privacy: the
/// list is only ever erased by explicit user action (the "Clear all"/per-row
/// delete controls, or "Restore Default Settings").
final class TranscriptHistoryStore {
    static let maxEntries = 30

    private let defaults: UserDefaults
    private static let key = "jvoice.app.transcriptHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Newest first. A corrupt/absent blob decodes to an empty list (same as a
    /// fresh install) rather than throwing.
    var entries: [TranscriptEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return [] }
        return decoded
    }

    /// Prepend a new transcript and trim to `maxEntries`, dropping the oldest.
    /// Blank text is ignored.
    @discardableResult
    func add(_ text: String) -> [TranscriptEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        var list = entries
        list.insert(TranscriptEntry(text: trimmed), at: 0)
        if list.count > Self.maxEntries {
            list.removeLast(list.count - Self.maxEntries)
        }
        persist(list)
        return list
    }

    @discardableResult
    func remove(id: UUID) -> [TranscriptEntry] {
        var list = entries
        list.removeAll { $0.id == id }
        persist(list)
        return list
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func persist(_ list: [TranscriptEntry]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
