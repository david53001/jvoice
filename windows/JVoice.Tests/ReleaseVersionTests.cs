using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the pure version parser/comparer behind the in-app updater. The updater must NEVER
/// prompt for a "downgrade" or a same-version release, and must tolerate the many shapes a
/// GitHub release tag can take (v-prefix, 2/3/4 components, pre-release/build metadata).
public class ReleaseVersionTests
{
    [Theory]
    [InlineData("1.2.3", 1, 2, 3, 0)]
    [InlineData("v1.2.3", 1, 2, 3, 0)]
    [InlineData("V2", 2, 0, 0, 0)]
    [InlineData("1.2", 1, 2, 0, 0)]
    [InlineData("1.2.3.4", 1, 2, 3, 4)]
    [InlineData("  1.0.0  ", 1, 0, 0, 0)]
    [InlineData("1.2.3-beta.1", 1, 2, 3, 0)]   // pre-release metadata stripped
    [InlineData("1.2.3+build5", 1, 2, 3, 0)]   // build metadata stripped
    [InlineData("2026.7.1", 2026, 7, 1, 0)]
    public void TryParse_ValidTags(string raw, int maj, int min, int pat, int build)
    {
        Assert.True(ReleaseVersion.TryParse(raw, out var v));
        Assert.Equal(maj, v.Major);
        Assert.Equal(min, v.Minor);
        Assert.Equal(pat, v.Patch);
        Assert.Equal(build, v.Build);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("v")]
    [InlineData("abc")]
    [InlineData("x.y.z")]
    public void TryParse_Rejects_NonVersions(string? raw)
        => Assert.False(ReleaseVersion.TryParse(raw, out _));

    [Fact]
    public void Compare_Orders_ByComponent()
    {
        Assert.True(Parse("1.0.1").CompareTo(Parse("1.0.0")) > 0);
        Assert.True(Parse("1.1.0").CompareTo(Parse("1.0.9")) > 0);
        Assert.True(Parse("2.0.0").CompareTo(Parse("1.9.9")) > 0);
        Assert.True(Parse("1.2.3.4").CompareTo(Parse("1.2.3")) > 0); // build component breaks the tie
        Assert.Equal(0, Parse("1.2.3").CompareTo(Parse("1.2.3")));
        Assert.Equal(0, Parse("v1.0.0").CompareTo(Parse("1.0.0")));  // v-prefix is cosmetic
        Assert.True(Parse("1.0.0").CompareTo(Parse("1.0.1")) < 0);
    }

    private static ReleaseVersion Parse(string raw)
    {
        Assert.True(ReleaseVersion.TryParse(raw, out var v));
        return v;
    }
}
