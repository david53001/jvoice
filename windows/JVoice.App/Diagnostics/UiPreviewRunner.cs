using System.Diagnostics;
using System.IO;
using JVoice.App.Platform;

namespace JVoice.App.Diagnostics;

/// <summary>
/// <c>--ui-preview &lt;outDir&gt;</c> (parity §12, REVAMP §5): renders every JVoice surface off-screen into one folder —
/// Settings (dark, light, an Updates state), every HUD pill state, the Welcome pages and the tour tag sheet — by running
/// the app's own single-surface render flags (<c>--settings-render</c>, <c>--hud-render</c>, <c>--welcome-render</c>,
/// <c>--tour-render</c>) one child process each. Every child gets a throwaway profile folder
/// (<see cref="PlatformPaths.ProfileOverrideVariable"/>), so a preview never reads or writes the user's settings,
/// tours.json or log. Writes <c>_preview-log.txt</c> (ok / FAIL per shot) and exits 1 if any shot failed.
/// </summary>
internal static class UiPreviewRunner
{
    public static bool ShouldRun(string[] args) =>
        args.Length >= 2 && string.Equals(args[0], "--ui-preview", StringComparison.OrdinalIgnoreCase);

    public static int RunAndExit(string[] args)
    {
        string outDir = Path.GetFullPath(args[1]);
        Directory.CreateDirectory(outDir);
        string profile = Path.Combine(Path.GetTempPath(), "jvoice-preview-profile-" + Environment.ProcessId);
        string exe = Environment.ProcessPath ?? throw new InvalidOperationException("no process path");
        string P(string name) => Path.Combine(outDir, name + ".png");

        var shots = new List<(string Name, string[] Args)>
        {
            ("settings-dark", new[] { "--settings-render", P("settings-dark"), "dark" }),
            ("settings-light", new[] { "--settings-render", P("settings-light"), "light" }),
            ("settings-update-available", new[] { "--settings-render", P("settings-update-available"), "available", "dark" }),
            ("hud-recording", new[] { "--hud-render", P("hud-recording") }),
            ("welcome-permissions", new[] { "--welcome-render", P("welcome-permissions"), "dark" }),
            ("welcome-allset", new[] { "--welcome-render", P("welcome-allset"), "allset", "dark" }),
            ("welcome-question", new[] { "--welcome-render", P("welcome-question"), "allset", "question", "dark" }),
            ("welcome-question-light", new[] { "--welcome-render", P("welcome-question-light"), "allset", "question", "light" }),
            ("tour-tags-dark", new[] { "--tour-render", P("tour-tags-dark"), "dark" }),
            ("tour-tags-light", new[] { "--tour-render", P("tour-tags-light"), "light" }),
            // The resizable window (WINDOWS-HANDOFF §9.1/9.7): the masonry layout at its sizes, both themes.
            // wide = 4 columns at full height; fill = maximized on a 1920x1080 screen (content capped at
            // 1440 and centred) and on David's 1600x1080 desktop; small = the minimum window (700x420, the
            // visible viewport) plus the same 2-column width at full height to check for holes.
            ("settings-wide-dark", new[] { "--settings-render", P("settings-wide-dark"), "--size", "1400xfull", "dark" }),
            ("settings-wide-light", new[] { "--settings-render", P("settings-wide-light"), "--size", "1400xfull", "light" }),
            ("settings-fill-dark", new[] { "--settings-render", P("settings-fill-dark"), "--size", "1920x1009", "dark" }),
            ("settings-fill-light", new[] { "--settings-render", P("settings-fill-light"), "--size", "1920x1009", "light" }),
            ("settings-fill1600-dark", new[] { "--settings-render", P("settings-fill1600-dark"), "--size", "1600x1009", "dark" }),
            ("settings-small-dark", new[] { "--settings-render", P("settings-small-dark"), "--size", "684x381", "dark" }),
            ("settings-small-light", new[] { "--settings-render", P("settings-small-light"), "--size", "684x381", "light" }),
            ("settings-small-full-dark", new[] { "--settings-render", P("settings-small-full-dark"), "--size", "684xfull", "dark" }),
            ("settings-small-full-light", new[] { "--settings-render", P("settings-small-full-light"), "--size", "684xfull", "light" }),
            // AI Polish card states (staged in memory; the key field only ever shows a placeholder).
            ("settings-aipolish-nokey", new[] { "--settings-render", P("settings-aipolish-nokey"), "aipolish-nokey", "dark" }),
            ("settings-aipolish-zero", new[] { "--settings-render", P("settings-aipolish-zero"), "aipolish-zero", "dark" }),
            ("settings-aipolish-on", new[] { "--settings-render", P("settings-aipolish-on"), "aipolish-on", "dark" }),
            ("settings-aipolish-on-light", new[] { "--settings-render", P("settings-aipolish-on-light"), "aipolish-on", "light" }),
            ("settings-aipolish-revealed", new[] { "--settings-render", P("settings-aipolish-revealed"), "aipolish-revealed", "light" }),
            ("settings-aipolish-usedup", new[] { "--settings-render", P("settings-aipolish-usedup"), "aipolish-usedup", "dark" }),
        };
        foreach (var state in new[] { "transcribing", "refining", "preparing", "downloading", "error", "copied", "unpasted", "done" })
            shots.Add(("hud-" + state, new[] { "--hud-render", P("hud-" + state), state }));

        var log = new List<string>();
        foreach (var (name, childArgs) in shots)
        {
            string png = P(name);
            if (File.Exists(png)) File.Delete(png);
            var psi = new ProcessStartInfo(exe) { UseShellExecute = false };
            foreach (var a in childArgs) psi.ArgumentList.Add(a);
            psi.Environment[PlatformPaths.ProfileOverrideVariable] = profile;
            using var child = Process.Start(psi);
            bool exited = child?.WaitForExit(60_000) == true;
            if (!exited) { try { child?.Kill(); } catch (InvalidOperationException) { } }
            log.Add(exited && File.Exists(png) ? "ok   " + name : "FAIL " + name + (exited ? " (no image)" : " (timeout)"));
        }
        File.WriteAllLines(Path.Combine(outDir, "_preview-log.txt"), log);
        try { Directory.Delete(profile, recursive: true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        return log.Any(l => l.StartsWith("FAIL", StringComparison.Ordinal)) ? 1 : 0;
    }
}
