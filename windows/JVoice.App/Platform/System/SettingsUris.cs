using System.Diagnostics;

namespace JVoice.App.Platform;

/// Deep links into Windows Settings via the ms-settings: scheme. Faithful port of
/// SettingsURLs.swift, re-expressed for Windows (overview §6.4). Only microphone is
/// relevant to JVoice on Windows (paste needs no permission).
public static class SettingsUris
{
    public const string Microphone = "ms-settings:privacy-microphone";

    /// Open a settings URI in the default handler (the Settings app).
    public static void Open(string uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Could not open Settings ({uri}). {ex.Message}");
        }
    }

    public static void OpenMicrophoneSettings() => Open(Microphone);
}
