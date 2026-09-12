using System.IO;
using System.Text;

namespace JVoice.App.Platform;

/// Persists the last transcript text to %APPDATA%\JVoice\last-transcript.txt.
/// Faithful port of LastTranscriptStore.swift (a single get/set string, empty
/// when nothing stored).
public sealed class LastTranscriptStore
{
    private readonly string _path;

    public LastTranscriptStore(string? path = null)
        => _path = path ?? PlatformPaths.LastTranscriptFile;

    public string Transcript
    {
        get
        {
            try { return File.Exists(_path) ? File.ReadAllText(_path, Encoding.UTF8) : ""; }
            catch { return ""; }
        }
        set
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                File.WriteAllText(_path, value, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            }
            catch (Exception ex)
            {
                SystemActions.ReportError($"Failed to save last transcript. {ex.Message}");
            }
        }
    }
}
