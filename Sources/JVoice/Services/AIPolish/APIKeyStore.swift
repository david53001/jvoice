import Foundation
import Security

/// The user's Anthropic API key, in the macOS Keychain as a generic password — the ONLY place it is
/// ever stored (never UserDefaults, `SettingsState`, history, files, the clipboard or a log line).
///
/// `WhenUnlockedThisDeviceOnly` and not synchronizable: it never syncs to iCloud and never comes
/// back from a backup on another Mac. Next to the secret the item carries a `kSecAttrComment` hint
/// ("••••abcd", last 4 at most) so Settings can say a key is saved by reading attributes only — the
/// secret itself is read for a dictation, a Test, or when the user presses the eye button.
enum APIKeyStore {
    static let service = "com.jvoice.app.anthropic"
    static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The masked form shown in Settings: "••••" + the last 4 characters.
    static func hint(for key: String) -> String {
        "••••" + String(key.suffix(4))
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// The saved key's hint, or nil when there is none. Reads attributes only, never the secret.
    static func savedHint() -> String? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else { return nil }
        return attributes[kSecAttrComment as String] as? String ?? "••••"
    }

    /// Replaces any saved key. False when the Keychain refused it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = kCFBooleanFalse
        item[kSecAttrLabel as String] = "JVoice — Anthropic API key"
        item[kSecAttrComment as String] = hint(for: trimmed)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
