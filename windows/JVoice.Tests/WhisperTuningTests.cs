using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

public class WhisperTuningTests
{
    [Theory]
    // Short clips clamp UP to the 768 floor (which covers ~15 s of audio, so never under-covers).
    [InlineData(0.5, 768)]
    [InlineData(5.0, 768)]
    [InlineData(12.0, 768)]
    // Mid clips: (s/30)*1500 + 128, rounded UP to a multiple of 64.
    [InlineData(13.0, 832)]
    [InlineData(15.0, 896)]
    [InlineData(20.0, 1152)]
    [InlineData(25.0, 1408)]
    public void AudioContextFor_ShortAndMidClips_ReturnsSizedContext(double seconds, int expected)
        => Assert.Equal(expected, WhisperTuning.AudioContextFor(seconds));

    [Theory]
    // Long enough that the sized value meets/exceeds the full window → null (don't set; use default).
    [InlineData(27.0)]
    [InlineData(30.0)]
    [InlineData(125.0)]
    public void AudioContextFor_LongClips_ReturnsNull(double seconds)
        => Assert.Null(WhisperTuning.AudioContextFor(seconds));

    [Theory]
    [InlineData(0.0)]
    [InlineData(-3.0)]
    [InlineData(double.NaN)]
    public void AudioContextFor_NonPositiveOrNaN_ReturnsFloor(double seconds)
        => Assert.Equal(WhisperTuning.MinAudioContext, WhisperTuning.AudioContextFor(seconds));

    [Fact]
    public void AudioContextForSamples_ConvertsSamplesToSeconds()
        // 80 000 samples / 16 000 Hz = 5 s → 768 floor.
        => Assert.Equal(768, WhisperTuning.AudioContextForSamples(80_000));

    [Fact]
    public void AudioContextFor_NeverUnderCoversTheClip()
    {
        // The returned context (in 50-frames/sec units) must always cover the clip duration.
        for (double s = 0.5; s < 27.0; s += 0.5)
        {
            int? ctx = WhisperTuning.AudioContextFor(s);
            int frames = ctx ?? WhisperTuning.FullAudioContext;
            Assert.True(frames / 50.0 >= s, $"ctx {frames} (~{frames / 50.0}s) under-covers {s}s clip");
        }
    }

    [Theory]
    [InlineData(6, 6)]
    [InlineData(1, 1)]
    [InlineData(0, 1)]    // clamp up to 1
    [InlineData(24, 16)]  // clamp down to 16
    public void DecodeThreads_ClampsToSaneRange(int physical, int expected)
        => Assert.Equal(expected, WhisperTuning.DecodeThreads(physical));
}
