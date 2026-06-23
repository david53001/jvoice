using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

/// The key property: mains-hum room tone and quiet speech can sit at the SAME raw RMS, yet
/// HighPassSilence must call the hum silent and the speech not-silent (so quiet/short
/// dictation transcribes while true silence still can't reach whisper.cpp). Signals are
/// generated at a representative room-tone level (~0.0044 RMS) to lock that separation.
public class HighPassSilenceTests
{
    private const int Sr = 16000;

    /// A single sine at the given overall RMS.
    private static short[] Tone(double freq, double rms, double seconds = 1.0)
    {
        int n = (int)(seconds * Sr);
        var s = new short[n];
        double amp = rms * Math.Sqrt(2); // sine RMS = amp/√2
        for (int i = 0; i < n; i++)
            s[i] = (short)Math.Clamp(Math.Round(amp * Math.Sin(2 * Math.PI * freq * i / Sr) * 32768.0), -32768, 32767);
        return s;
    }

    /// Three equal-power speech-band partials summed to the given overall RMS — broadband
    /// energy a quiet voice carries (unlike low-frequency hum).
    private static short[] Broadband(double rms, double seconds = 1.0)
    {
        int n = (int)(seconds * Sr);
        var s = new short[n];
        double partial = rms / Math.Sqrt(3);     // each partial's RMS
        double amp = partial * Math.Sqrt(2);
        double[] freqs = { 400, 1000, 2200 };
        for (int i = 0; i < n; i++)
        {
            double v = 0;
            foreach (var f in freqs) v += amp * Math.Sin(2 * Math.PI * f * i / Sr);
            s[i] = (short)Math.Clamp(Math.Round(v * 32768.0), -32768, 32767);
        }
        return s;
    }

    [Fact]
    public void MainsHum_AtRoomToneLevel_IsSilent()
        => Assert.True(HighPassSilence.IsSilent(Tone(60, 0.0044)));

    [Fact]
    public void LoudMainsHum_IsStillSilent() // low-frequency: even a strong hum has no speech energy
        => Assert.True(HighPassSilence.IsSilent(Tone(60, 0.02)));

    [Fact]
    public void QuietSpeech_AtSameRawLevelAsHum_IsNotSilent()
        => Assert.False(HighPassSilence.IsSilent(Broadband(0.0044)));

    [Fact]
    public void DigitalSilence_IsSilent()
        => Assert.True(HighPassSilence.IsSilent(new short[Sr]));

    [Fact]
    public void Empty_IsSilent()
        => Assert.True(HighPassSilence.IsSilent(Array.Empty<short>()));

    [Fact]
    public void NormalSpeech_IsNotSilent()
        => Assert.False(HighPassSilence.IsSilent(Broadband(0.05)));

    // The discriminator: at equal raw level, high-passed RMS is far higher for speech than hum,
    // and the floor sits between them.
    [Fact]
    public void HighPassRms_SeparatesHumFromSpeech_AtEqualRawLevel()
    {
        float hum = HighPassSilence.PeakHighPassRms(Tone(60, 0.0044));
        float speech = HighPassSilence.PeakHighPassRms(Broadband(0.0044));
        Assert.True(hum < HighPassSilence.DefaultFloor, $"hum hpRMS {hum} should be below floor");
        Assert.True(speech > HighPassSilence.DefaultFloor, $"speech hpRMS {speech} should be above floor");
        Assert.True(speech > hum * 3, $"speech ({speech}) should dwarf hum ({hum})");
    }
}
