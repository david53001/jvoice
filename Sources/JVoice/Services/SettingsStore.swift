import Combine
import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    public static let defaultKey = "jvoice.app.settings.state"
    public static let defaultCorruptBackupKey = "jvoice.app.settings.state.corrupt.bak"

    @Published public var state: SettingsState {
        didSet {
            scheduleSave(state)
        }
    }

    private let defaults: UserDefaults
    private let key: String
    private let corruptBackupKey: String
    private let encoder = JSONEncoder()
    private var saveTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5

    public init(defaults: UserDefaults = .standard,
                key: String = "jvoice.app.settings.state",
                corruptBackupKey: String = "jvoice.app.settings.state.corrupt.bak") {
        self.defaults = defaults
        self.key = key
        self.corruptBackupKey = corruptBackupKey

        let loadedState = Self.loadState(from: defaults,
                                         primaryKey: key,
                                         backupKey: corruptBackupKey)
        self.state = loadedState ?? SettingsState()

        if loadedState == nil {
            performSave(self.state)
        }
    }

    public func update(_ transform: (inout SettingsState) -> Void) {
        var updated = state
        transform(&updated)
        state = updated
    }

    public func reset() {
        state = SettingsState()
    }

    private func scheduleSave(_ state: SettingsState) {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.debounceInterval ?? 0.5) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.performSave(snapshot)
        }
    }

    public func flush() {
        saveTask?.cancel()
        performSave(state)
    }

    private func performSave(_ state: SettingsState) {
        guard let data = try? encoder.encode(state) else {
            SystemActions.errorHandler?("Failed to encode settings — changes may be lost on next launch.")
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func loadState(from defaults: UserDefaults,
                                  primaryKey: String,
                                  backupKey: String) -> SettingsState? {
        guard let data = defaults.data(forKey: primaryKey) else { return nil }
        do {
            return try JSONDecoder().decode(SettingsState.self, from: data)
        } catch {
            // Preserve the corrupt blob under a backup key BEFORE we replace it
            // so the user can recover their custom words / panel layout manually.
            defaults.set(data, forKey: backupKey)
            SystemActions.errorHandler?("Settings file was unreadable and reset to defaults. A backup was kept under \(backupKey). Error: \(error.localizedDescription)")
            return nil
        }
    }
}
