using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

/// The gate must call mains-hum room tone, low-frequency rumble and silence "silent" so a
/// whisper.cpp hallucination never reaches the user, while calling a person's speech —
/// including quiet/short dictation at the SAME raw level as hum — "not silent" so it
/// transcribes. Level alone can't separate them; spectral character (high-passed vs raw
/// energy) can. Sample-based tests lock the DSP; the metric-based tests lock the policy to
/// the real-mic anchor points measured on David's hardware (2026-06-23).
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

    // ---- sample-based: the DSP separates speech from hum/silence ----------------------

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

    // The discriminator: at equal raw level, high-passed RMS is far higher for speech than
    // hum, and the SpeechFloor sits between them.
    [Fact]
    public void HighPassRms_SeparatesHumFromSpeech_AtEqualRawLevel()
    {
        float hum = HighPassSilence.PeakHighPassRms(Tone(60, 0.0044));
        float speech = HighPassSilence.PeakHighPassRms(Broadband(0.0044));
        Assert.True(hum < HighPassSilence.SpeechFloor, $"hum hpRMS {hum} should be below floor");
        Assert.True(speech > HighPassSilence.SpeechFloor, $"speech hpRMS {speech} should be above floor");
        Assert.True(speech > hum * 3, $"speech ({speech}) should dwarf hum ({hum})");
    }

    // ---- metric-based: policy locked to David's real-mic anchors ----------------------
    // The original gate (single hpRMS < 0.0012 floor, tuned on synthesized clips) rejected
    // these REAL quiet/short dictations as "No speech detected." The (hp, raw) pairs below
    // are the exact values logged from his mic; the gate must pass real speech and still
    // gate his accidental taps, hum and silence.

    [Theory]
    [InlineData(0.0006f, 0.0014f)] // 2.38 s real dictation, ratio 0.43
    [InlineData(0.0009f, 0.0017f)] // 1.51 s real dictation, ratio 0.53
    public void RealMicQuietDictation_IsNotSilent(float hp, float raw)
        => Assert.False(HighPassSilence.IsSilent(hp, raw));

    [Theory]
    [InlineData(0.0002f, 0.0017f)] // 0.45 s tap, ratio 0.12 — low-frequency, no speech
    [InlineData(0.0003f, 0.0027f)] // 0.89 s tap, ratio 0.11 — low-frequency, no speech
    [InlineData(0.0001f, 0.0044f)] // mains hum at room tone, ratio 0.02
    [InlineData(0.0000f, 0.0000f)] // digital silence
    public void RealMicNonSpeech_IsSilent(float hp, float raw)
        => Assert.True(HighPassSilence.IsSilent(hp, raw));

    [Fact]
    public void LoudClearSpeech_IsNotSilent() // unambiguous broadband energy, passes via SpeechFloor
        => Assert.False(HighPassSilence.IsSilent(0.05f, 0.10f));

    [Fact]
    public void AmbiguousZone_LowFrequencyDominated_IsSilentByRatio()
        // hp in [HardFloor, SpeechFloor) but ratio 0.045 « SpeechRatioFloor → rumble, gated.
        => Assert.True(HighPassSilence.IsSilent(0.0009f, 0.0200f));

    [Fact]
    public void AmbiguousZone_Broadband_IsNotSilentByRatio()
        // hp in [HardFloor, SpeechFloor) with ratio 0.50 ≥ SpeechRatioFloor → quiet speech, passes.
        => Assert.False(HighPassSilence.IsSilent(0.0010f, 0.0020f));

    [Fact]
    public void Gate_IsMonotonic_NeverGatesAboveOldFloor()
    {
        // Above the old single-threshold floor the answer is always "not silent" regardless
        // of ratio, so no working dictation can regress.
        Assert.False(HighPassSilence.IsSilent(HighPassSilence.SpeechFloor, 1.0f));
        Assert.False(HighPassSilence.IsSilent(HighPassSilence.SpeechFloor + 0.001f, 0.0001f));
    }
}
