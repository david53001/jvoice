import Foundation

/// The user's Anthropic API key, in ONE owner-only file — the only place it is ever stored (never
/// UserDefaults, `SettingsState`, history, the clipboard or a log line):
/// `~/Library/Application Support/JVoice/anthropic-api-key`, file mode 0600 in a 0700 folder,
/// excluded from Time Machine backups, never synced.
///
/// Why not the Keychain (2026-10-17, David's decision): JVoice is self-signed ($0 budget, no Apple
/// Developer ID), so the login keychain ties its access list to each build's code hash — every
/// update made macOS ask for the user's PASSWORD again before a dictation could read the key. The
/// data-protection keychain would fix that but needs a provisioning-profile entitlement. The cost of
/// the file: other software running as the same macOS user could read it without a prompt (the same
/// trade the `aws` / `anthropic` CLIs make for their keys); the user's Anthropic spend limit caps it.
///
/// The hint ("••••abcd", last 4 at most) is computed from the file, so Settings can say a key is
/// saved without any prompt.
enum APIKeyStore {
    /// Overridable for tests; the app always uses the default.
    static var directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JVoice", isDirectory: true)

    static var fileURL: URL { directory.appendingPathComponent("anthropic-api-key") }

    /// For the dev modes that draw Settings (`--ui-preview`, `--settings-smoke`): points the store at a
    /// fresh, empty temp folder (removed when the process exits), so a test copy never reads the owner's
    /// real key and its last 4 characters can't end up in a screenshot. `fakeKey` is saved there so the
    /// "key saved" state still draws.
    static func useScratchDirectory(fakeKey: String? = nil) {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jvoice-preview-key-\(UUID().uuidString)", isDirectory: true)
        atexit { try? FileManager.default.removeItem(at: APIKeyStore.directory) }
        if let fakeKey { save(fakeKey) }
    }

    /// The masked form shown in Settings: "••••" + the last 4 characters.
    static func hint(for key: String) -> String {
        "••••" + String(key.suffix(4))
    }

    static func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    /// The saved key's hint, or nil when there is none.
    static func savedHint() -> String? {
        read().map(hint(for:))
    }

    /// Replaces any saved key. False when the file couldn't be written.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            // The folder may already exist (the clipboard history lives there too) with 0755.
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // Write a 0600 temp file first, then swap it in: the key never exists with wider
            // permissions, even for a moment.
            let temp = directory.appendingPathComponent(".anthropic-api-key-\(UUID().uuidString)")
            guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return false
            }
            if fm.fileExists(atPath: fileURL.path) {
                _ = try fm.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: fileURL)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func delete() -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return (error as NSError).code == NSFileNoSuchFileError
        }
    }
}
