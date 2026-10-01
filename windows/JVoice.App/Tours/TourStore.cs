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
    private static string DataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JVoice");

    public static string FilePath => Path.Combine(DataDirectory, TourAudience.TourFileName);

    public static TourPrefs Load()
    {
        try { return File.Exists(FilePath) ? TourPrefs.FromJson(File.ReadAllText(FilePath)) : new TourPrefs(); }
        catch (IOException) { return new TourPrefs(); }
        catch (UnauthorizedAccessException) { return new TourPrefs(); }
    }

    /// <summary>Atomic write (temp file + replace) so a crash mid-save never leaves a half file.</summary>
    public static void Save(TourPrefs prefs)
    {
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
