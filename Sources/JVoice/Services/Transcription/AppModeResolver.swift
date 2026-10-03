import Foundation

/// Pure resolution for the "app-aware modes" feature: given the paste target app's
/// bundle identifier, decide which tone (if any) dictation should use. User rules
/// take precedence over a built-in list of code apps (terminals / editors / IDEs)
/// that default to `.code`. Returns nil when the feature is off, the id is unknown,
/// or nothing matches — the caller then keeps the user's global tone. No I/O.
///
/// Ported from the Windows port's `AppModeResolver`. The one non-verbatim part is
/// the built-in app list: Windows matched exe names EXACTLY; macOS bundle ids are
/// namespaced (e.g. "com.microsoft.VSCode"), so we match built-in tokens by
/// case-insensitive SUBSTRING. That both handles vendor wildcards (one
/// "com.jetbrains." token covers IntelliJ/PyCharm/CLion/GoLand/WebStorm/Rider/…)
/// and stays false-positive-safe because the tokens are fully qualified.
public enum AppModeResolver {
    /// Bundle-id tokens (lower-cased) whose apps use Code mode out of the box:
    /// terminals, editors and IDEs. Matched as a case-insensitive substring of the
    /// frontmost app's bundle id (user rules use substring matching too).
    static let codeApps: [String] = [
        // Editors / IDEs
        "com.microsoft.vscode",           // VS Code (+ Insiders: com.microsoft.VSCodeInsiders)
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.zed",                    // Zed
        "com.apple.dt.xcode",             // Xcode
        "com.jetbrains.",                 // IntelliJ/PyCharm/CLion/GoLand/WebStorm/Rider/PhpStorm/RubyMine/DataGrip/AppCode/Fleet
        "com.sublimetext.",               // Sublime Text 3/4
        // Terminals (vim/nvim/tmux run inside these, so the terminal id covers them)
        "com.apple.terminal",             // Terminal
        "com.googlecode.iterm2",          // iTerm2
        "dev.warp.warp-stable",           // Warp
        "org.alacritty",                  // Alacritty
        "com.github.wez.wezterm",         // WezTerm
        "net.kovidgoyal.kitty",           // kitty
        "com.mitchellh.ghostty",          // Ghostty
        "co.zeit.hyper",                  // Hyper
    ]

    /// Resolve the effective tone from the target `bundleId`. `nil` means "no
    /// override — keep the global tone".
    public static func resolve(bundleId: String?, userRules: [AppModeRule], enabled: Bool) -> AppMode? {
        guard enabled, let id = normalize(bundleId) else { return nil }

        // User rules win, in list order (substring, case-insensitive). A blank match never matches.
        for rule in userRules {
            if let token = normalize(rule.appMatch), id.contains(token) {
                return rule.mode
            }
        }

        // Built-in code apps → Code mode.
        for token in codeApps where id.contains(token) {
            return .code
        }
        return nil
    }

    /// Lowercase + trim; nil for an empty/whitespace string.
    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
