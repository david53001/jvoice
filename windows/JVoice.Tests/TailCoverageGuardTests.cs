using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the §7 #39 tail-coverage recovery policy (Windows-only): trigger threshold,
/// merge/dedupe semantics, and the normalization the containment check rides on.
public class TailCoverageGuardTests
{
    // ---- constants locked ----

    [Fact]
    public void Threshold_IsOnePointFiveSeconds()
        => Assert.Equal(1.5, TailCoverageGuard.MinUncoveredSeconds);

    // ---- ShouldRecover trigger ----

    [Theory]
    [InlineData(3.48, 1.40, true)]   // the observed truncation: ≈2.1 s uncovered → fires
    [InlineData(10.0, 8.5, true)]    // exactly at the threshold → fires
    [InlineData(10.0, 8.6, false)]   // under the threshold → quiet
    [InlineData(5.0, 4.9, false)]    // normal decode, covered to the end
    [InlineData(5.0, 5.2, false)]    // segment end past clip end (timestamp slack)
    public void ShouldRecover_FiresOnlyOnBigUncoveredTails(double audio, double lastEnd, bool expected)
        => Assert.Equal(expected, TailCoverageGuard.ShouldRecover(audio, lastEnd));

    [Fact]
    public void ShouldRecover_NeverFiresWithoutASegment()
        => Assert.False(TailCoverageGuard.ShouldRecover(10.0, 0.0)); // no segments ⇒ empty path owns it

    // ---- Merge / dedupe ----

    [Fact]
    public void Merge_AppendsRecoveredWords()
        => Assert.Equal(
            "please get this into an actual app that I can run.",
            TailCoverageGuard.Merge("please get this", "into an actual app that I can run."));

    [Fact]
    public void Merge_EmptyTail_LeavesTranscriptUntouched()
        => Assert.Equal("please get this", TailCoverageGuard.Merge("please get this", ""));

    [Fact]
    public void Merge_WhitespaceTail_LeavesTranscriptUntouched()
        => Assert.Equal("please get this", TailCoverageGuard.Merge("please get this", "  \n "));

    [Fact]
    public void Merge_TailAlreadyPresent_IsNotDuplicated()
        => Assert.Equal(
            "please get this into an actual app that I can run.",
            TailCoverageGuard.Merge(
                "please get this into an actual app that I can run.",
                "that I can run"));

    [Fact]
    public void Merge_TailPresentModuloCaseAndPunctuation_IsNotDuplicated()
        => Assert.Equal(
            "We ship on Friday, then we rest.",
            TailCoverageGuard.Merge("We ship on Friday, then we rest.", "Then we REST!"));

    [Fact]
    public void Merge_TrimsBoundaryWhitespace()
        => Assert.Equal("first part and the rest", TailCoverageGuard.Merge("first part  ", "  and the rest"));

    // ---- Normalize (the containment substrate) ----

    [Theory]
    [InlineData("Hello, World!", "hello world")]
    [InlineData("  a  b  ", "a b")]
    [InlineData("don't", "don t")]
    [InlineData("", "")]
    public void Normalize_StripsCaseAndPunctuation(string input, string expected)
        => Assert.Equal(expected, TailCoverageGuard.Normalize(input));
}
