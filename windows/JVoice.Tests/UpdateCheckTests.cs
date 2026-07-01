using JVoice.Core.Policy;
using Xunit;

namespace JVoice.Tests;

/// Locks the pure GitHub-release parsing + asset selection + "is there an update?" decision that
/// the App-layer UpdateService composes with HttpClient. All I/O lives in the App; everything
/// here is a pure string→model transform so it can be unit-tested with no network.
public class UpdateCheckTests
{
    // A trimmed but shape-faithful GitHub `releases/latest` payload with both installer flavors.
    private const string SampleJson = """
    {
      "tag_name": "v1.3.0",
      "name": "JVoice 1.3.0",
      "html_url": "https://github.com/owner/jvoice/releases/tag/v1.3.0",
      "body": "### What's new\n- In-app updates",
      "assets": [
        { "name": "JVoice-Setup.exe",     "browser_download_url": "https://example.com/JVoice-Setup.exe" },
        { "name": "JVoice-Setup-GPU.exe", "browser_download_url": "https://example.com/JVoice-Setup-GPU.exe" },
        { "name": "JVoice-cpu-win-x64.zip","browser_download_url": "https://example.com/JVoice-cpu-win-x64.zip" }
      ]
    }
    """;

    [Fact]
    public void Parse_ExtractsTagBodyUrlAndAssets()
    {
        Assert.True(GitHubReleaseParser.TryParse(SampleJson, out var r));
        Assert.Equal("v1.3.0", r.TagName);
        Assert.Equal("https://github.com/owner/jvoice/releases/tag/v1.3.0", r.HtmlUrl);
        Assert.Contains("In-app updates", r.Body);
        Assert.Equal(3, r.Assets.Count);
        Assert.Contains(r.Assets, a => a.Name == "JVoice-Setup.exe"
                                     && a.DownloadUrl == "https://example.com/JVoice-Setup.exe");
    }

    [Fact]
    public void Parse_Rejects_MalformedJson()
        => Assert.False(GitHubReleaseParser.TryParse("{ not json", out _));

    [Fact]
    public void Parse_Rejects_WhenTagMissing()
        => Assert.False(GitHubReleaseParser.TryParse("""{ "name": "no tag", "assets": [] }""", out _));

    [Fact]
    public void Parse_TagPresent_NoAssets_YieldsEmptyList()
    {
        Assert.True(GitHubReleaseParser.TryParse("""{ "tag_name": "v9.9.9" }""", out var r));
        Assert.Equal("v9.9.9", r.TagName);
        Assert.Empty(r.Assets);
    }

    [Fact]
    public void AssetSelector_Cpu_PicksNonGpuSetup()
    {
        Assert.True(GitHubReleaseParser.TryParse(SampleJson, out var r));
        var picked = UpdateAssetSelector.Pick(r.Assets, preferCpu: true);
        Assert.NotNull(picked);
        Assert.Equal("JVoice-Setup.exe", picked!.Name);
    }

    [Fact]
    public void AssetSelector_Gpu_PicksGpuSetup()
    {
        Assert.True(GitHubReleaseParser.TryParse(SampleJson, out var r));
        var picked = UpdateAssetSelector.Pick(r.Assets, preferCpu: false);
        Assert.NotNull(picked);
        Assert.Equal("JVoice-Setup-GPU.exe", picked!.Name);
    }

    [Fact]
    public void AssetSelector_FallsBackToAnyExe_WhenFlavorMissing()
    {
        var only = new[] { new ReleaseAsset("JVoice-Setup-GPU.exe", "u") };
        // A CPU build with only a GPU installer present still gets a usable exe rather than nothing.
        Assert.Equal("JVoice-Setup-GPU.exe", UpdateAssetSelector.Pick(only, preferCpu: true)!.Name);
    }

    [Fact]
    public void AssetSelector_ReturnsNull_WhenNoExe()
    {
        var none = new[] { new ReleaseAsset("JVoice-cpu-win-x64.zip", "u") };
        Assert.Null(UpdateAssetSelector.Pick(none, preferCpu: true));
        Assert.Null(UpdateAssetSelector.Pick(Array.Empty<ReleaseAsset>(), preferCpu: false));
    }

    [Theory]
    [InlineData("1.0.0", "v1.0.1", true)]
    [InlineData("1.0.0", "1.1.0", true)]
    [InlineData("1.0.0", "v2.0.0", true)]
    [InlineData("1.0.0", "1.0.0", false)]   // same version — no prompt
    [InlineData("1.0.0", "v0.9.9", false)]  // older release — never offer a downgrade
    [InlineData("1.0.0", "garbage", false)] // unparseable tag — fail safe, no prompt
    [InlineData("1.0.0", "v1.2.0-beta", true)] // pre-release metadata ignored; 1.2.0 > 1.0.0
    public void Decision_IsUpdateAvailable(string current, string latest, bool expected)
        => Assert.Equal(expected, UpdateDecision.IsUpdateAvailable(current, latest));
}
