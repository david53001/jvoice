namespace JVoice.Core.Audio;

/// <summary>
/// Is a capture endpoint a real microphone or a virtual / loopback device (parity row 17, Mac 8ea5088: "the Bluetooth
/// redirect targets only physical inputs — never virtual devices like VB-Cable")? Windows has no transport type like
/// CoreAudio's, so it's judged from the PnP enumerator and the name. Seen on David's PC (2026-10-02 probe): Voicemod
/// enumerates as <c>ROOT</c>; Elgato's virtual mixes as <c>TUSBAUDIO_ENUM</c> (a USB driver, so only the name tells);
/// the Yeti and the Kraken as <c>USB</c>. Real mics enumerate as USB / HDAUDIO / BTHENUM / BTHLE / INTELAUDIO.
/// </summary>
public static class CaptureEndpointKind
{
    /// <summary>Name fragments of virtual cables, voice changers, streaming mixers and loopback inputs.</summary>
    private static readonly string[] VirtualNameMarks =
    {
        "virtual", "vb-audio", "voicemeeter", "cable output", "cable input", "voicemod", "stereo mix", "what u hear",
        "wave out mix", "nvidia broadcast", "krisp", "steam streaming", "obs", "loopback",
    };

    /// <summary>Software-only PnP enumerators: no hardware behind them.</summary>
    private static readonly string[] VirtualEnumerators = { "ROOT", "SWD" };

    public static bool IsVirtual(string? enumeratorName, string? friendlyName)
    {
        if (enumeratorName is { Length: > 0 } e
            && VirtualEnumerators.Any(v => string.Equals(e.Trim(), v, StringComparison.OrdinalIgnoreCase)))
            return true;
        if (friendlyName is not { Length: > 0 } name) return false;
        foreach (var mark in VirtualNameMarks)
        {
            int i = name.IndexOf(mark, StringComparison.OrdinalIgnoreCase);
            if (i < 0) continue;
            // "obs" only as a whole word (not "Jobs", "Lobster")
            if (mark == "obs" && !IsWord(name, i, mark.Length)) continue;
            return true;
        }
        return false;
    }

    private static bool IsWord(string s, int start, int length)
    {
        bool before = start == 0 || !char.IsLetterOrDigit(s[start - 1]);
        bool after = start + length >= s.Length || !char.IsLetterOrDigit(s[start + length]);
        return before && after;
    }
}
