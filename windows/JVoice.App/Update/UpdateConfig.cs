using System.Reflection;

namespace JVoice.App.Update;

/// Static configuration for the in-app updater. All the "who/where" lives here so David edits ONE
/// place at publish time. Windows-only feature (root CLAUDE.md §7 #34).
public static class UpdateConfig
{
    /// Master gate. The updater is inert while this is false — no network call is ever made.
    /// It stays on; the feature is naturally dormant while the repo/releases are private (the
    /// anonymous GitHub API returns 404, which the service treats as "no update").
    /// (static readonly, not const, so the runtime guard in UpdateService isn't folded away.)
    public static readonly bool Enabled = true;

    /// `owner/repo` the releases are published under. Points at the real repo so it "just works"
    /// once David makes the repo (or its Releases) public; until then the anonymous API 404s and
    /// the updater silently reports no update. NOTE: publishing is on David's call (hard rules).
    public const string RepoSlug = "david53001/jvoice";

    /// The GitHub "list releases" endpoint for <see cref="RepoSlug"/> (newest first). We list rather
    /// than use `/releases/latest` because this is a mono-repo: `/releases/latest` is repo-wide and
    /// can return a macOS release, so the updater filters the list down to the Windows channel
    /// (see WindowsReleaseSelector). 50 covers a long interleaved macOS+Windows release history.
    public static string ReleasesApiUrl => $"https://api.github.com/repos/{RepoSlug}/releases?per_page=50";

    /// True when THIS build is the CPU installer flavor, so the updater downloads `JVoice-Setup.exe`
    /// rather than the NVIDIA `JVoice-Setup-GPU.exe`. Mirrors the engine's JVOICE_CPU flavor switch.
#if JVOICE_CPU
    public const bool PreferCpuInstaller = true;
#else
    public const bool PreferCpuInstaller = false;
#endif

    /// The running build's version (AssemblyVersion, e.g. "1.0.0.0"), compared against a release tag.
    public static string CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";

    /// Human-friendly current version for the Settings card ("v1.0.0").
    public static string CurrentVersionDisplay
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v is null ? "v0.0.0" : $"v{v.Major}.{v.Minor}.{v.Build}";
        }
    }
}
