using System;
using System.Threading;

namespace JVoice.App.Update;

/// Hidden developer CLI for the in-app updater:
///
///     JVoice --update-check
///
/// Runs the REAL update query (HTTP GET to the configured GitHub endpoint → parse → version
/// decision → asset pick) once and prints the outcome, so the network+parse seam can be smoke-
/// tested on-device without the unit-tested pure pieces. While the repo is private this prints
/// "no update" (the anonymous API 404s), proving the dormant-until-published behavior. Runs BEFORE
/// any WPF startup (see App.Main).
internal static class UpdateProbeRunner
{
    public static bool ShouldRun(string[] args) =>
        Array.Exists(args, a => string.Equals(a, "--update-check", StringComparison.OrdinalIgnoreCase));

    public static int RunAndExit(string[] args)
    {
        Console.WriteLine($"JVoice --update-check");
        Console.WriteLine($"  repo     : {UpdateConfig.RepoSlug}");
        Console.WriteLine($"  endpoint : {UpdateConfig.ReleasesApiUrl}");
        Console.WriteLine($"  current  : {UpdateConfig.CurrentVersion}  (flavor: {(UpdateConfig.PreferCpuInstaller ? "cpu" : "gpu")})");
        try
        {
            var service = new UpdateService();
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(25));
            var result = service.CheckAsync(cts.Token).GetAwaiter().GetResult();
            Console.WriteLine($"  available: {result.Available}");
            Console.WriteLine($"  latest   : {result.LatestVersion ?? "<none>"}");
            Console.WriteLine($"  asset    : {result.DownloadUrl ?? "<none>"}");
            Console.WriteLine($"  release  : {result.ReleaseUrl ?? "<none>"}");
            Console.WriteLine($"  error    : {result.Error ?? "<none>"}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"  fatal    : {ex.GetType().Name} {ex.Message}");
        }
        return 0;
    }
}
