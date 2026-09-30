import AppKit

/// What a value typed into a Settings text field becomes, and — when it is
/// turned away — the one-line reason shown under the field. Pure (apart from
/// the installed-app lookup at the bottom) so `scripts/run-logic-tests.sh`
/// can verify it without a window.
enum SettingsEntryPolicy {
    // MARK: - Custom Words

    /// Mirrors `VoiceCoordinator.addCustomWord`'s length guard.
    static let customWordMaxLength = 60

    /// Why `VoiceCoordinator.addCustomWord(word)` turns `word` away, in words
    /// the user can act on — nil when it would be accepted (or is blank, which
    /// the field never submits). Mirrors that method's guards one for one.
    static func customWordRejection(_ word: String, existing: [String]) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > customWordMaxLength {
            return "Too long: a custom word can be up to \(customWordMaxLength) characters."
        }
        if trimmed.rangeOfCharacter(from: .alphanumerics) == nil {
            return "A custom word needs at least one letter or number."
        }
        if let existing = existing.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "“\(existing)” is already in your list."
        }
        return nil
    }

    // MARK: - App Modes

    struct InstalledApp: Equatable, Sendable {
        let name: String
        let bundleID: String
    }

    /// What an entry in the App Modes field refers to. Rules match the
    /// frontmost app's BUNDLE ID (`AppModeResolver`), so an app's name has to
    /// be turned into its bundle ID first — "Google Chrome" stored verbatim
    /// never matches "com.google.Chrome".
    enum AppRuleTarget: Equatable, Sendable {
        /// Typed as a bundle ID (or a vendor prefix like "com.jetbrains.") —
        /// kept verbatim.
        case bundleID(String)
        /// An installed app's name, resolved to its bundle ID.
        case app(InstalledApp)
        /// Several installed apps match — their names.
        case ambiguous([String])
        case notFound
    }

    /// Resolve `typed` against the installed apps: an exact (case- and
    /// space-insensitive) app name wins; otherwise text shaped like a bundle
    /// ID is kept as typed; otherwise a single app whose name contains it.
    static func appRuleTarget(for typed: String, installed: [InstalledApp]) -> AppRuleTarget {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = nameKey(trimmed)
        guard !query.isEmpty else { return .notFound }

        if let exact = installed.first(where: { nameKey($0.name) == query }) {
            return .app(exact)
        }
        if looksLikeBundleID(trimmed) {
            return .bundleID(trimmed)
        }

        var partial: [InstalledApp] = []
        for app in installed where nameKey(app.name).contains(query) {
            if !partial.contains(where: { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }) {
                partial.append(app)
            }
        }
        switch partial.count {
        case 0: return .notFound
        case 1: return .app(partial[0])
        default: return .ambiguous(partial.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        }
    }

    /// The line shown under the field when `target` cannot become a rule;
    /// nil when it can.
    static func appRuleNotice(for target: AppRuleTarget, typed: String) -> String? {
        let shown = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case .bundleID, .app:
            return nil
        case .ambiguous(let names):
            let listed = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
            return "“\(shown)” matches \(listed). Type the full app name."
        case .notFound:
            return "No app named “\(shown)” found in Applications. Check the name, or enter its bundle ID."
        }
    }

    /// "com.tinyspeck.slackmacgap", "com.jetbrains." — dotted, no spaces, and
    /// not an app file name ("Notes.app").
    static func looksLikeBundleID(_ text: String) -> Bool {
        text.contains(".")
            && text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !text.lowercased().hasSuffix(".app")
    }

    /// Case- and space-insensitive comparison key ("Voice Memos" = "VoiceMemos"),
    /// ignoring a trailing ".app".
    private static func nameKey(_ name: String) -> String {
        var key = name.lowercased().filter { !$0.isWhitespace }
        if key.hasSuffix(".app") {
            key.removeLast(4)
        }
        return key
    }
}

// MARK: - Installed apps (I/O)

extension SettingsEntryPolicy {
    /// Apps in the standard Applications folders (and one folder level down,
    /// e.g. "Microsoft Office/…") plus running regular apps, by file name and
    /// localized name. Only called when the user adds a rule (~40 ms).
    static func installedApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots: [(url: URL, descend: Bool)] = [
            (URL(fileURLWithPath: "/Applications"), true),
            (URL(fileURLWithPath: "/Applications/Utilities"), false),
            (URL(fileURLWithPath: "/System/Applications"), false),
            (URL(fileURLWithPath: "/System/Applications/Utilities"), false),
            (home.appendingPathComponent("Applications"), true),
        ]

        var appURLs: [URL] = []
        for root in roots {
            let entries = (try? fileManager.contentsOfDirectory(
                at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    appURLs.append(entry)
                } else if root.descend, entry.lastPathComponent != "Utilities" {
                    let nested = (try? fileManager.contentsOfDirectory(
                        at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                    )) ?? []
                    appURLs += nested.filter { $0.pathExtension == "app" }
                }
            }
        }

        var apps: [InstalledApp] = []
        for url in appURLs {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            apps.append(InstalledApp(name: url.deletingPathExtension().lastPathComponent, bundleID: bundleID))
            let localized = fileManager.displayName(atPath: url.path)
            apps.append(InstalledApp(name: localized, bundleID: bundleID))
        }
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            if let name = running.localizedName, let bundleID = running.bundleIdentifier {
                apps.append(InstalledApp(name: name, bundleID: bundleID))
            }
        }
        return apps
    }
}
