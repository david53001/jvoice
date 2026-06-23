using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

public class StatsMathTests
{
    [Fact]
    public void Zero_Seconds_ReturnsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, 0));

    [Fact]
    public void Negative_Seconds_ReturnsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, -5));

    [Theory]
    [InlineData(120, 60.0, 120.0)]   // 120 words in 60s = 120 wpm
    [InlineData(60, 30.0, 120.0)]    // 60 words in 30s = 120 wpm
    [InlineData(150, 120.0, 75.0)]   // 150 words in 120s = 75 wpm
    public void Computes_WordsPerMinute(int words, double seconds, double expected)
        => Assert.Equal(expected, StatsMath.AverageWpm(words, seconds), precision: 6);

    // Swift's guard is `totalSeconds > 0 else return 0`, so NaN seconds (NaN > 0 == false) returns 0.
    // C#'s `totalSeconds <= 0` guard let NaN through (NaN <= 0 == false) and returned NaN — bug #4.
    [Fact]
    public void NaN_Seconds_ReturnsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, double.NaN));

    [Fact]
    public void ZeroWords_IsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(0, 60));

    [Fact]
    public void ZeroWords_ZeroSeconds_IsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(0, 0));

    [Fact]
    public void TinySeconds_LargeButFinite()
    {
        var wpm = StatsMath.AverageWpm(1, 0.001); // 1 word in 1 ms
        Assert.Equal(60000.0, wpm, precision: 3);
    }

    [Fact]
    public void LargeWordCount_NoOverflow()
    {
        // int.MaxValue words over 60 s — double arithmetic, no overflow, finite result.
        var wpm = StatsMath.AverageWpm(int.MaxValue, 60.0);
        Assert.True(double.IsFinite(wpm));
        Assert.Equal((double)int.MaxValue / 60.0 * 60.0, wpm, precision: 0);
    }

    // PositiveInfinity passes the `> 0` guard in both Swift and C# → words/Inf*60 = 0.
    [Fact]
    public void PositiveInfinitySeconds_IsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, double.PositiveInfinity));

    [Fact]
    public void NegativeInfinitySeconds_IsZero()
        => Assert.Equal(0, StatsMath.AverageWpm(100, double.NegativeInfinity));
}
