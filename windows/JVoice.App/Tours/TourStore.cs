using System.IO;
using JVoice.App.Platform;
using JVoice.Core.Tours;
using Microsoft.Win32;

namespace JVoice.App.Tours;

/// <summary>
/// <c>%APPDATA%\JVoice\tours.json</c> (the five tour keys, nothing else) and the read-only audience signals (parity
/// §10.1). Nothing here writes the registry or any setting — the only file it ever writes is tours.json.
/// </summary>
internal static class TourStore
{
    private static string DataDirectory => JVoice.App.Platform.PlatformPaths.AppDataDirectory;

    public static string FilePath => Path.Combine(DataDirectory, TourAudience.TourFileName);

    public static TourPrefs Load()
    {
        // Any failure (unreadable, or JSON the lenient parser still rejects — e.g. duplicate keys) starts from empty
        // prefs: the audience is then re-classified, and the existing settings.json makes that "existing". A bad
        // tours.json must never crash every launch (review round 1 JV #12b).
        if (!File.Exists(FilePath)) return new TourPrefs();
        Exception? error = null;
        for (int attempt = 0; attempt < 2; attempt++)
        {
            try { return TourPrefs.FromJson(File.ReadAllText(FilePath)); }
            catch (Exception ex) { error = ex; if (attempt == 0) Thread.Sleep(150); } // a brief AV lock: one retry
        }
        // Still unreadable: this session runs as an existing user in memory and never writes tours.json, so a new
        // user's answer and progress aren't overwritten by one bad read (review round 2 JV #3). A copy is kept.
        _readOnly = true;
        string kept = FilePath + ".bad-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
        try { File.Copy(FilePath, kept, overwrite: true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { kept = "(not copied: " + ex.Message + ")"; }
        DiagnosticLog.Write($"Tours load failed ({error?.GetType().Name}: {error?.Message}); existing user for this session, file kept as {kept}");
        return new TourPrefs { Audience = TourAudience.Store(TourAudienceKind.Existing) };
    }

    private static bool _readOnly;

    /// <summary>Atomic write (temp file + replace) so a crash mid-save never leaves a half file.</summary>
    public static void Save(TourPrefs prefs)
    {
        if (_readOnly) return; // tours.json couldn't be read this session — leave it as it is
        try
        {
            Directory.CreateDirectory(DataDirectory);
            string tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, prefs.ToJson());
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            DiagnosticLog.Write($"Tours save failed: {ex.Message}");
        }
    }

    /// <summary>
    /// What the first launch with tours can see — gathered BEFORE <c>SettingsStore</c> exists (it writes settings.json on
    /// construction). Every probe is read-only; one that fails counts as "used before" (doubt → existing).
    /// </summary>
    public static AudienceSignals GatherSignals()
    {
        IReadOnlyCollection<string> entries;
        try
        {
            entries = Directory.Exists(DataDirectory)
                ? Directory.EnumerateFileSystemEntries(DataDirectory).Select(Path.GetFileName).OfType<string>().ToList()
                : Array.Empty<string>();
        }
        catch { entries = new[] { "<unreadable>" }; }

        bool model;
        try
        {
            string models = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JVoice", "models");
            model = Directory.Exists(models) && Directory.EnumerateFiles(models, "*", SearchOption.AllDirectories).Any();
        }
        catch { model = true; }

        string exe = Environment.ProcessPath ?? "";
        bool consent;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged\"
                + TourAudience.ConsentKeyName(exe));
            consent = string.Equals(key?.GetValue("Value") as string, "Allow", StringComparison.OrdinalIgnoreCase);
        }
        catch { consent = true; }

        bool registry;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\JVoice");
            registry = key is not null;
        }
        catch { registry = true; }

        bool dev = TourAudience.IsDevBuildPath(AppContext.BaseDirectory);
        return new AudienceSignals(entries, model, consent, registry, dev);
    }
}
