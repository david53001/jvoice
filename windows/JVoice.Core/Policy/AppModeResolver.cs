using JVoice.Core.Models;

namespace JVoice.Core;

/// Pure resolution for the Windows-only "app-aware modes" feature: given the foreground app's
/// exe name, decide which tone (if any) dictation should use. User rules take precedence over a
/// built-in list of code apps (terminals / editors / IDEs) that default to <see cref="ToneStyle.Code"/>.
/// Returns null when the feature is off, the exe is unknown, or nothing matches — the caller then
/// keeps the user's global tone. No I/O: the privileged exe-name read lives in
/// JVoice.App/Platform/System (anti-cheat-safe, PROCESS_QUERY_LIMITED_INFORMATION only).
public static class AppModeResolver
{
    /// Exe names (lowercase, without ".exe") that use Code mode out of the box: terminals,
    /// editors and IDEs. Matched by exact normalized name (user rules use substring matching).
    public static readonly IReadOnlyList<string> CodeApps = new[]
    {
        // Terminals / shells
        "windowsterminal", "wt", "cmd", "powershell", "pwsh", "conhost", "alacritty",
        "wezterm", "wezterm-gui", "mintty",
        // Editors / IDEs
        "code", "code - insiders", "cursor", "windsurf", "devenv", "rider64", "idea64",
        "pycharm64", "clion64", "webstorm64", "goland64", "phpstorm64", "rubymine64",
        "datagrip64", "sublime_text", "notepad++", "vim", "gvim", "nvim",
    };

    public static ToneStyle? Resolve(string? exeName, IReadOnlyList<AppModeRule> userRules, bool enabled)
    {
        if (!enabled) return null;
        string? exe = Normalize(exeName);
        if (exe is null) return null;

        // User rules win, in list order (substring, case-insensitive). A blank match never matches.
        foreach (var rule in userRules)
        {
            string? token = Normalize(rule.AppMatch);
            if (token is not null && exe.Contains(token, StringComparison.Ordinal))
                return rule.Mode;
        }

        // Built-in code apps: exact normalized-name match.
        return CodeApps.Contains(exe) ? ToneStyle.Code : null;
    }

    /// Lowercase, trim, and drop a trailing ".exe" so callers may pass "Code", "code" or "code.exe".
    private static string? Normalize(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        string n = name.Trim().ToLowerInvariant();
        if (n.EndsWith(".exe", StringComparison.Ordinal)) n = n[..^4];
        return n.Length == 0 ? null : n;
    }
}
