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

    // ===== ShouldRecord — port of StatsStore.record's `guard words > 0, durationSeconds > 0` =====

    [Theory]
    [InlineData(1, 0.001, true)]    // smallest positive sample is recordable
    [InlineData(120, 60.0, true)]
    [InlineData(0, 60.0, false)]    // no words
    [InlineData(-3, 60.0, false)]   // negative words
    [InlineData(120, 0.0, false)]   // no duration
    [InlineData(120, -1.0, false)]  // negative duration
    public void ShouldRecord_PositiveOnly(int words, double seconds, bool expected)
        => Assert.Equal(expected, StatsMath.ShouldRecord(words, seconds));

    // bug #6: StatsStore.record's C# guard `durationSeconds <= 0` let NaN through (NaN <= 0 == false),
    // so a NaN duration was added to totalSeconds (poisoning stats + breaking JSON). Swift's
    // `durationSeconds > 0` (NaN > 0 == false) rejects it — ShouldRecord must too.
    [Fact]
    public void ShouldRecord_NaNDuration_IsFalse()
        => Assert.False(StatsMath.ShouldRecord(120, double.NaN));

    // Infinity passes `> 0` in both Swift and C# (matches AverageWpm, which then yields 0).
    [Fact]
    public void ShouldRecord_PositiveInfinityDuration_IsTrue()
        => Assert.True(StatsMath.ShouldRecord(120, double.PositiveInfinity));

    // ===== EstimatedMinutesSaved — Windows-only "time saved" stat (§ quick-wins 1c) =====
    // saved = wordsAtTypingBaseline(40 wpm) − minutesSpoken, floored at 0.

    // Typical: 400 words spoken in 60s. Typing 400 words @40wpm = 10 min; spoken = 1 min ⇒ 9 saved.
    [Fact]
    public void EstimatedMinutesSaved_TypicalCase()
        => Assert.Equal(9.0, StatsMath.EstimatedMinutesSaved(400, 60.0), precision: 6);

    // No words ⇒ nothing saved (mirrors the AverageWpm/ShouldRecord zero-word guard).
    [Fact]
    public void EstimatedMinutesSaved_ZeroWords_IsZero()
        => Assert.Equal(0, StatsMath.EstimatedMinutesSaved(0, 60.0));

    [Fact]
    public void EstimatedMinutesSaved_NegativeWords_IsZero()
        => Assert.Equal(0, StatsMath.EstimatedMinutesSaved(-10, 60.0));

    // If dictation took LONGER than typing would have (few words, long silence), floor at 0 — never
    // report negative "saved" time. 10 words @40wpm = 0.25 min typing; 600s spoken = 10 min ⇒ 0.
    [Fact]
    public void EstimatedMinutesSaved_SlowerThanTyping_FloorsAtZero()
        => Assert.Equal(0, StatsMath.EstimatedMinutesSaved(10, 600.0));

    // NaN seconds must not poison the result (same NaN-safety class as AverageWpm): treat as 0 spoken.
    // 40 words @40wpm = 1 min typing, 0 spoken ⇒ 1.0 saved.
    [Fact]
    public void EstimatedMinutesSaved_NaNSeconds_TreatedAsZeroSpoken()
        => Assert.Equal(1.0, StatsMath.EstimatedMinutesSaved(40, double.NaN), precision: 6);

    // Negative seconds can't happen for real, but clamp spoken to 0 rather than inflate the estimate.
    [Fact]
    public void EstimatedMinutesSaved_NegativeSeconds_TreatedAsZeroSpoken()
        => Assert.Equal(1.0, StatsMath.EstimatedMinutesSaved(40, -100.0), precision: 6);
}
