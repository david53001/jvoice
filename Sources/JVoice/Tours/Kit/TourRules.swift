/// The pure "may this happen by itself?" rules (spec §14.9). The app's `TourCoordinator` only asks
/// these; it never decides on its own.
public enum TourRules {
    /// True once this tour was finished or skipped at (at least) its current catalog version.
    public static func isSeen(_ tour: Tour, seen: [String: Int]) -> Bool {
        (seen[tour.id.rawValue] ?? 0) >= tour.version
    }

    /// A tour starts **by itself** only if first-use tours are on (absent = off) and this version of
    /// it hasn't been seen. The audience never turns tours on — it only decides whether the question
    /// is asked, i.e. what `firstUseToursEnabled` becomes.
    public static func shouldAutoStart(_ tour: Tour, firstUseToursEnabled: Bool?, seen: [String: Int]) -> Bool {
        (firstUseToursEnabled ?? false) && !isSeen(tour, seen: seen)
    }

    /// "Want a quick tour?" is shown only to new users who haven't answered it.
    public static func shouldAskQuestion(audience: TourAudience?, answered: Bool) -> Bool {
        audience == .new && !answered
    }

    /// At launch, with permission already granted (so the permission pages are skipped): a new user who
    /// still hasn't answered gets the Welcome window opened straight on its last page, which asks.
    public static func shouldOpenWelcomeOnLaunch(audience: TourAudience?, answered: Bool,
                                                 permissionGranted: Bool) -> Bool {
        permissionGranted && shouldAskQuestion(audience: audience, answered: answered)
    }

    /// The tours whose automatic trigger is `trigger`, in catalog order.
    public static func tours(triggeredBy trigger: TourTrigger, in catalog: [Tour]) -> [Tour] {
        catalog.filter { $0.trigger == trigger }
    }

    /// What Reset All Tours confirms (the Help & Tours menu's HUD, Settings → Tours & tips). With first-use
    /// tours off (absent = off) nothing starts by itself afterwards, so it says how to get them (review I1).
    public static func resetConfirmation(firstUseToursEnabled: Bool?) -> String {
        (firstUseToursEnabled ?? false) ? "Tours reset" : "Tours reset — turn on Tours & tips to see them again"
    }
}

/// `{shortcut:<HotkeyAction raw value>}` placeholders in step bodies (spec §14.3: shortcuts show the
/// user's **current** keys).
public enum TourText {
    /// What a `{shortcut:…}` placeholder shows when the user has cleared that shortcut — short enough that
    /// every body still fits the tag's two lines (`TagFitTests`), instead of the action's name
    /// ("Capture Area area…", review W3).
    public static let unboundShortcut = "(not set)"

    /// Replaces every `{shortcut:name}` with `lookup(name)`. A nil lookup leaves that placeholder as is
    /// (the catalog lint tests make sure every name is a real action).
    public static func resolvingShortcuts(in text: String, _ lookup: (String) -> String?) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: prefix) {
            out += rest[..<open.lowerBound]
            let afterPrefix = rest[open.upperBound...]
            guard let close = afterPrefix.firstIndex(of: "}") else {
                out += rest[open.lowerBound...]
                return out
            }
            let name = String(afterPrefix[..<close])
            out += lookup(name) ?? String(rest[open.lowerBound...close])
            rest = afterPrefix[afterPrefix.index(after: close)...]
        }
        return out + rest
    }

    /// The action names used in `text`'s placeholders, in order.
    public static func shortcutNames(in text: String) -> [String] {
        var names: [String] = []
        _ = resolvingShortcuts(in: text) { names.append($0); return nil }
        return names
    }

    private static let prefix = "{shortcut:"
}
