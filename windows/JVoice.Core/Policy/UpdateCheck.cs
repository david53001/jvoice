using System.Text.Json;

namespace JVoice.Core.Policy;

/// One downloadable file attached to a GitHub release (the installer .exe, a .zip, …).
public sealed record ReleaseAsset(string Name, string DownloadUrl);

/// The parsed subset of a GitHub `releases/latest` payload the updater needs.
public sealed record ReleaseInfo(
    string TagName,
    string? Body,
    string? HtmlUrl,
    IReadOnlyList<ReleaseAsset> Assets);

/// Pure parser for a GitHub `releases/latest` JSON body. All HTTP lives in the App layer
/// (UpdateService); this is a string→model transform so it is unit-locked (UpdateCheckTests),
/// with the same lenient, never-throw philosophy as SettingsStateJson.
public static class GitHubReleaseParser
{
    public static bool TryParse(string json, out ReleaseInfo release)
    {
        release = default!;
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { return false; }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;

            string? tag = Str(root, "tag_name");
            if (string.IsNullOrWhiteSpace(tag)) return false; // no version → nothing to decide

            string? body = Str(root, "body");
            string? htmlUrl = Str(root, "html_url");

            var assets = new List<ReleaseAsset>();
            if (root.TryGetProperty("assets", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in arr.EnumerateArray())
                {
                    if (el.ValueKind != JsonValueKind.Object) continue;
                    string? name = Str(el, "name");
                    string? url = Str(el, "browser_download_url");
                    if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(url)) continue;
                    assets.Add(new ReleaseAsset(name!, url!));
                }
            }

            release = new ReleaseInfo(tag!, body, htmlUrl, assets);
            return true;
        }
    }

    private static string? Str(JsonElement obj, string name)
        => obj.TryGetProperty(name, out var e) && e.ValueKind == JsonValueKind.String
            ? e.GetString() : null;
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
