using System.Diagnostics;
using System.IO;
using System.Net.Http;
using JVoice.App.Platform;
using JVoice.Core.Policy;

namespace JVoice.App.Update;

/// The result of one update check. `Error` is set only on a real failure (network/parse); a healthy
/// "no newer version" check returns Available=false with Error=null.
public sealed record UpdateQueryResult(
    bool Available,
    string? LatestVersion = null,
    string? DownloadUrl = null,
    string? ReleaseUrl = null,
    string? Notes = null,
    string? Error = null);

/// All the network + process I/O behind the in-app updater. The *decisions* (parse, version
/// compare, asset pick) are the pure Core/Policy helpers — this class only does HTTP and launching.
/// Windows-only feature; the SECOND and only other network call in the app besides the one-time
/// model download, and it sends no user data (an anonymous GET to the GitHub API).
public sealed class UpdateService
{
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        // GitHub's API rejects requests with no User-Agent. Identify as the updater (no PII).
        c.DefaultRequestHeaders.UserAgent.ParseAdd("JVoice-Updater");
        c.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        c.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28");
        return c;
    }

    /// Query GitHub for the latest release and decide whether it is newer than the running build.
    /// Never throws: any failure comes back as a result with `Error` set (the caller shows it only
    /// for a user-initiated check, so an offline auto-check stays silent).
    public async Task<UpdateQueryResult> CheckAsync(CancellationToken ct)
    {
        if (!UpdateConfig.Enabled)
            return new UpdateQueryResult(false);

        string json;
        try
        {
            using var resp = await Http.GetAsync(UpdateConfig.ReleasesApiUrl, ct);
            if (!resp.IsSuccessStatusCode)
            {
                // 404 = private repo or no releases yet → treat as "no update", not an error, so the
                // feature is silently dormant until David publishes. Other codes are soft errors.
                DiagnosticLog.Write($"Update check HTTP {(int)resp.StatusCode}");
                return resp.StatusCode == System.Net.HttpStatusCode.NotFound
                    ? new UpdateQueryResult(false)
                    : new UpdateQueryResult(false, Error: $"GitHub returned {(int)resp.StatusCode}.");
            }
            json = await resp.Content.ReadAsStringAsync(ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            DiagnosticLog.Write($"Update check failed: {ex.GetType().Name} {ex.Message}");
            return new UpdateQueryResult(false, Error: "Couldn't reach the update server.");
        }

        if (!GitHubReleaseParser.TryParseList(json, out var releases))
            return new UpdateQueryResult(false, Error: "Update information was unreadable.");

        // Mono-repo: pick the newest FINAL release that ships a Windows installer, ignoring macOS
        // (.dmg-only) releases and pre-releases. No such release → nothing to offer.
        var release = WindowsReleaseSelector.PickLatestWindows(releases);
        if (release is null)
            return new UpdateQueryResult(false);

        bool available = UpdateDecision.IsUpdateAvailable(UpdateConfig.CurrentVersion, release.TagName);
        DiagnosticLog.Write($"Update check: current={UpdateConfig.CurrentVersion} latest={release.TagName} available={available}");
        if (!available)
            return new UpdateQueryResult(false, LatestVersion: release.TagName, ReleaseUrl: release.HtmlUrl);

        var asset = UpdateAssetSelector.Pick(release.Assets, UpdateConfig.PreferCpuInstaller);
        if (asset is null)
            // A newer release exists but has no installer we can run — point the user at the page.
            return new UpdateQueryResult(false, LatestVersion: release.TagName, ReleaseUrl: release.HtmlUrl,
                Error: "A new version is available, but no installer was found. Open the release page to download it.");

        return new UpdateQueryResult(true, release.TagName, asset.DownloadUrl, release.HtmlUrl, release.Body);
    }

    /// Stream the installer to <paramref name="destPath"/>, reporting (bytesReceived, totalBytesOrNull)
    /// as it goes. Total is null when the server sends no Content-Length (the progress model crawls).
    public async Task DownloadAsync(string url, string destPath, Action<long, long?> onProgress, CancellationToken ct)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destPath)!);

        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        long? total = resp.Content.Headers.ContentLength;

        await using var src = await resp.Content.ReadAsStreamAsync(ct);
        await using var dst = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true);

        var buffer = new byte[1 << 16];
        long received = 0;
        int read;
        onProgress(0, total);
        while ((read = await src.ReadAsync(buffer, ct)) > 0)
        {
            await dst.WriteAsync(buffer.AsMemory(0, read), ct);
            received += read;
            onProgress(received, total);
        }
    }

    /// Launch the downloaded installer (detached, via the shell) so it can overwrite the install
    /// while THIS process exits. The caller quits the app immediately after so file locks release.
    public void LaunchInstaller(string path)
    {
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    /// Open a URL (the release page) in the default browser.
    public void OpenInBrowser(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception ex) { DiagnosticLog.Write($"OpenInBrowser failed: {ex.Message}"); }
    }
}
