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
}
