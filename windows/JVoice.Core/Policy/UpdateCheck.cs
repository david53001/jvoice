using System.Text.Json;

namespace JVoice.Core.Policy;

/// One downloadable file attached to a GitHub release (the installer .exe, a .zip, …).
public sealed record ReleaseAsset(string Name, string DownloadUrl);

/// The parsed subset of a GitHub release payload the updater needs. `Draft`/`Prerelease` let the
/// Windows-channel selector skip non-final releases (they default false so existing construction and
/// the single-object parse are unaffected).
public sealed record ReleaseInfo(
    string TagName,
    string? Body,
    string? HtmlUrl,
    IReadOnlyList<ReleaseAsset> Assets,
    bool Draft = false,
    bool Prerelease = false);

/// Pure parser for GitHub release JSON. All HTTP lives in the App layer (UpdateService); this is a
/// string→model transform so it is unit-locked (UpdateCheckTests), with the same lenient, never-throw
/// philosophy as SettingsStateJson.
public static class GitHubReleaseParser
{
    /// Parse a single release object (a `releases/latest` body).
    public static bool TryParse(string json, out ReleaseInfo release)
    {
        release = default!;
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { return false; }

        using (doc)
        {
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return false;
            return TryParseElement(doc.RootElement, out release);
        }
    }

    /// Parse a GitHub `/repos/{owner}/{repo}/releases` array (all releases, newest first) into
    /// models. Same lenient philosophy as the single-object parse; a non-array or malformed body
    /// yields false so the caller treats it as "no update". Elements that don't parse are skipped.
    public static bool TryParseList(string json, out IReadOnlyList<ReleaseInfo> releases)
    {
        releases = Array.Empty<ReleaseInfo>();
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { return false; }

        using (doc)
        {
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return false;

            var list = new List<ReleaseInfo>();
            foreach (var el in doc.RootElement.EnumerateArray())
                if (TryParseElement(el, out var info)) list.Add(info);

            releases = list;
            return true;
        }
    }

    private static bool TryParseElement(JsonElement el, out ReleaseInfo release)
    {
        release = default!;
        if (el.ValueKind != JsonValueKind.Object) return false;

        string? tag = Str(el, "tag_name");
        if (string.IsNullOrWhiteSpace(tag)) return false; // no version → nothing to decide

        var assets = new List<ReleaseAsset>();
        if (el.TryGetProperty("assets", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var a in arr.EnumerateArray())
            {
                if (a.ValueKind != JsonValueKind.Object) continue;
                string? name = Str(a, "name");
                string? url = Str(a, "browser_download_url");
                if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(url)) continue;
                assets.Add(new ReleaseAsset(name!, url!));
            }
        }

        release = new ReleaseInfo(tag!, Str(el, "body"), Str(el, "html_url"), assets,
                                  Bool(el, "draft"), Bool(el, "prerelease"));
        return true;
    }

    private static string? Str(JsonElement obj, string name)
        => obj.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String
            ? e.GetString() : null;

    private static bool Bool(JsonElement obj, string name)
        => obj.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.True;
}

/// Selects the update the *Windows* app should track from a repo-wide releases list. This is a
/// mono-repo (macOS `v1.x` + Windows `windows-v1.x` under one repo), so the naive `releases/latest`
/// can return a macOS release; this picks the newest FINAL release that actually ships a Windows
/// installer (`.exe`), which structurally excludes macOS `.dmg`-only releases and any pre-release/
/// draft. Returns null when no such release exists (caller → "no update").
public static class WindowsReleaseSelector
{
    public static ReleaseInfo? PickLatestWindows(IReadOnlyList<ReleaseInfo> releases)
    {
        ReleaseInfo? best = null;
        ReleaseVersion bestVer = default;
        foreach (var rel in releases)
        {
            if (rel.Draft || rel.Prerelease) continue;                     // finals only
            if (!rel.Assets.Any(a => a.Name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)))
                continue;                                                  // Windows-installer channel only
            if (!ReleaseVersion.TryParse(rel.TagName, out var ver)) continue;
            if (best is null || ver.CompareTo(bestVer) > 0) { best = rel; bestVer = ver; }
        }
        return best;
    }
}

/// Picks the installer asset matching the running build's flavor (CPU vs GPU). The two shipped
/// installers are `JVoice-Setup.exe` (CPU, the default) and `JVoice-Setup-GPU.exe` (NVIDIA).
public static class UpdateAssetSelector
{
    public static ReleaseAsset? Pick(IReadOnlyList<ReleaseAsset> assets, bool preferCpu)
    {
        static bool IsExe(ReleaseAsset a) => a.Name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
        static bool IsGpu(ReleaseAsset a) => a.Name.Contains("GPU", StringComparison.OrdinalIgnoreCase);

        var exes = assets.Where(IsExe).ToList();
        if (exes.Count == 0) return null;

        if (preferCpu)
        {
            // Exact flavor first (a Setup .exe with no "GPU" in the name), else any non-GPU exe,
            // else fall back to whatever exe exists so an update is still possible.
            return exes.FirstOrDefault(a => !IsGpu(a)
                        && a.Name.Contains("Setup", StringComparison.OrdinalIgnoreCase))
                ?? exes.FirstOrDefault(a => !IsGpu(a))
                ?? exes[0];
        }

        return exes.FirstOrDefault(IsGpu) ?? exes[0];
    }
}

/// The "should we prompt?" decision. Fail-safe: a same, older, or unparseable release tag never
/// yields an update, so a malformed/duplicate release can't nag the user or offer a downgrade.
public static class UpdateDecision
{
    public static bool IsUpdateAvailable(string currentVersion, string latestTag)
    {
        if (!ReleaseVersion.TryParse(latestTag, out var latest)) return false;
        // Our own build version is always well-formed, but fall back to 0.0.0 if it somehow isn't
        // so a valid newer release can still be offered.
        if (!ReleaseVersion.TryParse(currentVersion, out var current)) current = new ReleaseVersion(0);
        return latest.CompareTo(current) > 0;
    }
}
