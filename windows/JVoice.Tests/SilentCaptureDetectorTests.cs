using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

/// Locks the dead-input detector (§7 #46). Calibrated on REAL measurements from David's machine
/// on 2026-08-11, when the system default capture endpoint was the Voicemod virtual microphone
/// with Voicemod not running: it produced bit-exact digital silence, which whisper turned into
/// hallucinated filler ("Thank you. Thank you. Thank you.") or an empty transcript reported as
/// the misleading "No speech detected."
///
/// The separation between the two populations is total — dead endpoints measure exactly 0.0
/// non-zero samples, a live mic in a quiet room measures ~0.99 — so this is emphatically NOT the
/// retired RMS amplitude gate (§7 #21) that rejected real quiet dictation.
public class SilentCaptureDetectorTests
{
    // ---- real dead-endpoint captures (all zeros) ----

    [Fact]
    public void RealVoicemodCapture_76s_IsDeadInput()
    {
        // capture-20260811-151829-989.wav — 76.54 s, 0 of 1,224,640 samples non-zero.
        var stats = new CaptureSignalStats(TotalSamples: 1_224_640, NonZeroSamples: 0, Seconds: 76.54);
        Assert.True(SilentCaptureDetector.IsDeadInput(stats));
    }

    [Fact]
    public void RealVoicemodCapture_18s_IsDeadInput()
    {
        // capture-20260811-151906-661.wav — 18.49 s, 0 of 295,840 non-zero.
        var stats = new CaptureSignalStats(295_840, 0, 18.49);
        Assert.True(SilentCaptureDetector.IsDeadInput(stats));
    }

    [Fact]
    public void RealVoicemodCapture_1s_IsDeadInput()
    {
        // capture-20260811-151924-143.wav — 1.13 s, 0 of 18,080 non-zero.
        var stats = new CaptureSignalStats(18_080, 0, 1.13);
        Assert.True(SilentCaptureDetector.IsDeadInput(stats));
    }

    // ---- real LIVE-microphone captures (must never be called dead) ----

    /// David's Yeti Classic sitting IDLE in a quiet room, measured on the RAW 48 kHz float capture
    /// buffers: 283,584 of 285,120 samples non-zero (99.46%) at peak 0.045.
    [Fact]
    public void RealYetiIdleNoiseFloor_RawCapture_IsNotDeadInput()
    {
        var stats = new CaptureSignalStats(285_120, 283_584, 2.97);
        Assert.False(SilentCaptureDetector.IsDeadInput(stats));
    }

    /// The same idle Yeti measured where it actually matters — the FINISHED 16 kHz/16-bit WAV that
    /// CaptureSignal reads (downsampling + 16-bit quantization zero out many near-silent samples,
    /// so this is much lower than the raw-capture figure above and is the true worst case for a
    /// live mic): 6,931 of 47,520 non-zero = 14.6%, still ~290x the dead-input threshold.
    /// Recorded on-device 2026-08-11 via `audio-input-probe --recorder 3`.
    [Fact]
    public void RealYetiIdleNoiseFloor_WrittenWav_IsNotDeadInput()
    {
        var stats = new CaptureSignalStats(47_520, 6_931, 2.97);
        Assert.False(SilentCaptureDetector.IsDeadInput(stats));
    }

    /// A real quiet dictation that transcribed correctly (2026-07-29, rawRms 0.0186):
    /// 152,367 of 185,440 samples non-zero. His quiet speech MUST keep working (§7 #21).
    [Fact]
    public void RealQuietDictation_IsNotDeadInput()
    {
        var stats = new CaptureSignalStats(185_440, 152_367, 11.59);
        Assert.False(SilentCaptureDetector.IsDeadInput(stats));
    }

    /// Even a mic far quieter than David's — 1% of samples non-zero — is still a live device.
    [Fact]
    public void ExtremelyQuietButLiveMic_IsNotDeadInput()
    {
        var stats = new CaptureSignalStats(160_000, 1_600, 10.0);
        Assert.False(SilentCaptureDetector.IsDeadInput(stats));
    }

    // ---- guards ----

    [Fact]
    public void VeryShortRecording_IsNeverJudged()
    {
        // Below MinSecondsToJudge a legitimately all-zero clip (mic still ramping) must not be
        // blamed on the device.
        var stats = new CaptureSignalStats(3_200, 0, 0.2);
        Assert.False(SilentCaptureDetector.IsDeadInput(stats));
    }

    [Fact]
    public void NoSamplesMeasured_IsNotDeadInput()
    {
        Assert.False(SilentCaptureDetector.IsDeadInput(new CaptureSignalStats(0, 0, 5.0)));
    }

    [Fact]
    public void NonZeroRatio_ComputesSafely()
    {
        Assert.Equal(0d, new CaptureSignalStats(0, 0, 0).NonZeroRatio);
        Assert.Equal(0.5d, new CaptureSignalStats(100, 50, 1).NonZeroRatio, 6);
    }

    /// The threshold sits far from BOTH populations (dead = 0.0, live ≈ 0.99), so neither is
    /// near the boundary. Locked so a future tweak can't drift it into real audio.
    [Fact]
    public void Threshold_SitsBetweenTheTwoPopulations()
    {
        Assert.True(SilentCaptureDetector.MaxNonZeroRatio > 0d);
        Assert.True(SilentCaptureDetector.MaxNonZeroRatio < 0.01d);
    }

    [Fact]
    public void JustAboveThreshold_IsNotDeadInput()
    {
        long total = 1_000_000;
        long nonZero = (long)(total * SilentCaptureDetector.MaxNonZeroRatio) + 1;
        Assert.False(SilentCaptureDetector.IsDeadInput(new CaptureSignalStats(total, nonZero, 30)));
    }

    // ---- message ----

    [Fact]
    public void DeadInputMessage_NamesTheDevice()
    {
        string msg = SilentCaptureDetector.DeadInputMessage("Microphone (Voicemod Virtual Audio Device (WDM))");
        Assert.Contains("Voicemod", msg);
        Assert.Contains("Settings", msg);
        // It must NOT blame the user's voice — that wording is exactly what hid this bug.
        Assert.DoesNotContain("No speech", msg);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void DeadInputMessage_FallsBackWhenNameUnknown(string? name)
    {
        string msg = SilentCaptureDetector.DeadInputMessage(name);
        Assert.Contains("Your microphone", msg);
        Assert.DoesNotContain("\"\"", msg);
    }
}
