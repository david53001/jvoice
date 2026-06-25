using System.IO;

namespace JVoice.App.Platform;

/// Canonical Windows file locations for JVoice (overview §4.9). Centralized so
/// every store agrees on the same %APPDATA%\JVoice folder and the recorder uses
/// the same temp pattern.
public static class PlatformPaths
{
    /// %APPDATA%\JVoice — settings.json, stats.json, last-transcript.txt,
    /// transcript-history.json live here.
    public static string AppDataDirectory
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "JVoice");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// %LOCALAPPDATA%\JVoice\models — GGML model cache (Phase 2 owns it; defined here for consistency).
    public static string ModelsDirectory
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "JVoice", "models");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string SettingsFile => Path.Combine(AppDataDirectory, "settings.json");
    public static string SettingsCorruptBackupFile => Path.Combine(AppDataDirectory, "settings.corrupt.bak");
    public static string StatsFile => Path.Combine(AppDataDirectory, "stats.json");
    public static string LastTranscriptFile => Path.Combine(AppDataDirectory, "last-transcript.txt");
    public static string TranscriptHistoryFile => Path.Combine(AppDataDirectory, "transcript-history.json");

    /// %APPDATA%\JVoice\capture — recordings kept for no-speech threshold calibration
    /// when the JVOICE_KEEP_WAV env var is set. Outside the jvoice-*.wav sweep pattern,
    /// so kept clips survive app restarts. Empty/unused in normal operation.
    public static string CaptureDirectory
    {
        get
        {
            string dir = Path.Combine(AppDataDirectory, "capture");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// True when JVOICE_KEEP_WAV is set: the coordinator copies each recording into
    /// CaptureDirectory instead of just deleting it, so real on-device clips can be
    /// captured through the LIVE pipeline (same mic/router/format) for calibration.
    public static bool KeepRecordings =>
        !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("JVOICE_KEEP_WAV"));

    /// The system temp directory — recordings are written as jvoice-<guid>.wav here.
    public static string TempDirectory => Path.GetTempPath();

    public const string RecordingPrefix = "jvoice-";
    public const string RecordingExtension = ".wav";
    public const string RecordingSweepPattern = "jvoice-*.wav";
}
