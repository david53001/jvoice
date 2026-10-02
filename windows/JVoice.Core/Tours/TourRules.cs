using System.Text.RegularExpressions;

namespace JVoice.Core.Tours;

public enum TourAudienceKind { New, Existing }

/// <summary>
/// What the first launch with tours can see (parity §10.1, the Windows equivalents of the Mac's signals). The app
/// gathers these BEFORE anything writes settings (<c>SettingsStore</c> writes settings.json on construction).
/// </summary>
/// <param name="DataFolderEntries">Names in %APPDATA%\JVoice other than tours.json (settings, stats, transcripts…).</param>
/// <param name="ModelDownloaded">A Whisper model is already on disk.</param>
/// <param name="MicrophoneConsentAllowed">Windows' microphone privacy consent for this exe is already "Allow".</param>
/// <param name="RegistryKeyExists">HKCU\Software\JVoice exists (first-run / launch-at-login flags of an older build).</param>
/// <param name="IsDevBuild">Running from a bin\Debug or bin\…\Release build output, not an install.</param>
public sealed record AudienceSignals(
    IReadOnlyCollection<string> DataFolderEntries,
    bool ModelDownloaded,
    bool MicrophoneConsentAllowed,
    bool RegistryKeyExists,
    bool IsDevBuild,
    bool LaunchedByJVoice = false);

/// <summary>
/// Who gets tours (Mac <c>TourAudience</c>) — new users only, decided once and stored. When in doubt: existing (a
/// missed new user loses nothing; a nagged existing user is what the owner forbade — David's PC must never see the
/// Welcome window).
/// </summary>
public static class TourAudience
{
    /// <summary>The tour file itself never counts as "the app was used".</summary>
    public const string TourFileName = "tours.json";

    public static TourAudienceKind Classify(AudienceSignals s)
    {
        if (s.IsDevBuild) return TourAudienceKind.Existing;
        // An elevated relaunch or a logon (--autostart) launch: JVoice was already installed and running — even when
        // this token's profile is empty (a relaunch into another admin account; review round 1 JV #12a).
        if (s.LaunchedByJVoice) return TourAudienceKind.Existing;
        if (s.DataFolderEntries.Any(n => !string.Equals(n, TourFileName, StringComparison.OrdinalIgnoreCase)))
            return TourAudienceKind.Existing;
        if (s.ModelDownloaded) return TourAudienceKind.Existing;
        if (s.MicrophoneConsentAllowed) return TourAudienceKind.Existing;
        if (s.RegistryKeyExists) return TourAudienceKind.Existing;
        return TourAudienceKind.New;
    }

    /// <summary>Stored value: absent → not classified yet; exactly "new" → new; anything else → existing.</summary>
    public static TourAudienceKind? Parse(string? stored) =>
        stored is null ? null : stored == "new" ? TourAudienceKind.New : TourAudienceKind.Existing;

    public static string Store(TourAudienceKind kind) => kind == TourAudienceKind.New ? "new" : "existing";

    /// <summary>
    /// The value name Windows uses under <c>…\ConsentStore\microphone\NonPackaged</c> for an exe: its full path with
    /// every '\' replaced by '#'.
    /// </summary>
    public static string ConsentKeyName(string exePath) => exePath.Replace('\\', '#');

    /// <summary>A build-output path (bin\Debug, bin\Release, bin\x64\…) — a developer's copy, never a new user.</summary>
    public static bool IsDevBuildPath(string exeDirectory)
    {
        var p = exeDirectory.Replace('/', '\\');
        return p.Contains("\\bin\\Debug", StringComparison.OrdinalIgnoreCase)
            || p.Contains("\\bin\\Release", StringComparison.OrdinalIgnoreCase)
            || p.Contains("\\bin\\x64\\", StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>The pure "may this happen by itself?" rules (Mac <c>TourRules</c>). The coordinator only asks these.</summary>
public static class TourRules
{
    /// <summary>True once this tour was finished or skipped at (at least) its current version.</summary>
    public static bool IsSeen(Tour tour, int? seenVersion) => (seenVersion ?? 0) >= tour.Version;

    /// <summary>"Want a quick tour?" is shown only to new users who haven't answered it.</summary>
    public static bool ShouldAskQuestion(TourAudienceKind? audience, bool answered) =>
        audience == TourAudienceKind.New && !answered;

    /// <summary>At launch: a new user who hasn't answered gets the Welcome window.</summary>
    public static bool ShouldOpenWelcomeOnLaunch(TourAudienceKind? audience, bool answered) =>
        ShouldAskQuestion(audience, answered);

    /// <summary>A tour starts by itself only with first-use tours on (absent = off) and this version not yet seen.
    /// The audience never turns tours on — it only decides whether the question is asked.</summary>
    public static bool ShouldAutoStart(Tour tour, bool? firstUseToursEnabled, int? seenVersion) =>
        firstUseToursEnabled == true && !IsSeen(tour, seenVersion);

    /// <summary>What Reset All Tours confirms. With first-use tours off nothing starts by itself afterwards, so it says how.</summary>
    public static string ResetConfirmation(bool? firstUseToursEnabled) =>
        firstUseToursEnabled == true ? "Tours reset" : "Tours reset — turn on Show Me Around to see them again";
}

/// <summary><c>{shortcut:&lt;action&gt;}</c> placeholders in tour bodies (Mac <c>TourText</c>): the user's CURRENT keys.</summary>
public static class TourText
{
    /// <summary>What a placeholder shows when that shortcut is cleared — short so every body still fits two lines.</summary>
    public const string UnboundShortcut = "(not set)";

    /// <summary>The longest shortcut text a placeholder can show on Windows (the fit lint measures with it).</summary>
    public const string LongestShortcut = "Ctrl+Alt+Shift+Win+F12";

    /// <summary>The placeholder names the app resolves.</summary>
    public static readonly IReadOnlySet<string> KnownShortcuts = new HashSet<string> { "toggleRecording", "undoLastPaste" };

    private static readonly Regex Placeholder = new(@"\{shortcut:([A-Za-z0-9]+)\}", RegexOptions.Compiled);

    /// <summary>Replaces each placeholder whose name <paramref name="resolve"/> knows (non-null); unknown names stay as typed.</summary>
    public static string Resolve(string body, Func<string, string?> resolve) =>
        Placeholder.Replace(body, m => resolve(m.Groups[1].Value) ?? m.Value);

    /// <summary>The placeholder names in order.</summary>
    public static IReadOnlyList<string> Names(string body) => Placeholder.Matches(body).Select(m => m.Groups[1].Value).ToList();
}
