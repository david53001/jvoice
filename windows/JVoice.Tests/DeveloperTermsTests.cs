using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class DeveloperTermsTests
{
    private static readonly IReadOnlyDictionary<string, string> Empty =
        new Dictionary<string, string>();

    // ===== Map hygiene =====

    [Fact]
    public void Map_IsNonEmpty()
        => Assert.NotEmpty(DeveloperTerms.Map);

    [Fact]
    public void Map_KeysAreLowercasedTrimmed_AndValuesNonEmpty()
    {
        foreach (var (key, value) in DeveloperTerms.Map)
        {
            Assert.Equal(key.Trim(), key);
            Assert.Equal(key.ToLowerInvariant(), key);
            Assert.NotEqual(0, key.Length);
            Assert.NotEqual(0, value.Trim().Length);
        }
    }

    // Locks the conservative-curation policy: ambiguous single English words must
    // never enter the pack, or ordinary dictation would be corrupted.
    [Theory]
    [InlineData("go")]
    [InlineData("rust")]
    [InlineData("swift")]
    [InlineData("react")]
    [InlineData("java")]
    [InlineData("pandas")]
    [InlineData("dotnet")]   // bare "dotnet" must stay the lowercase CLI, never ".NET"
    [InlineData("sequel")]   // "sequel"->"SQL" would wreck "the movie sequel"
    [InlineData("flask")]
    [InlineData("pip")]
    public void Map_ExcludesAmbiguousEnglishWords(string risky)
        => Assert.False(DeveloperTerms.Map.ContainsKey(risky), $"pack must not contain ambiguous key '{risky}'");

    // ===== Augment precedence =====

    [Fact]
    public void Augment_AddsPackEntries()
    {
        var merged = DeveloperTerms.Augment(Empty);
        Assert.Equal("Node.js", merged["node js"]);
        Assert.Equal("GitHub", merged["git hub"]);
    }

    [Fact]
    public void Augment_PreservesNonCollidingBaseEntries()
    {
        var baseDict = new Dictionary<string, string> { ["foo bar"] = "FooBar" };
        var merged = DeveloperTerms.Augment(baseDict);
        Assert.Equal("FooBar", merged["foo bar"]);   // base kept
        Assert.Equal("Node.js", merged["node js"]);  // pack added
    }

    [Fact]
    public void Augment_BaseWins_OnKeyCollision()
    {
        // A user's own custom-word variant outranks the generic pack.
        var baseDict = new Dictionary<string, string> { ["react js"] = "React.js" };
        var merged = DeveloperTerms.Augment(baseDict);
        Assert.Equal("React.js", merged["react js"]);
    }

    // ===== End-to-end through TextProcessor.Process =====

    [Theory]
    [InlineData("i use node js daily", "i use Node.js daily")]
    [InlineData("clone it from git hub", "clone it from GitHub")]
    [InlineData("written in type script", "written in TypeScript")]
    [InlineData("i love java script", "i love JavaScript")]
    [InlineData("built with dot net", "built with .NET")]
    [InlineData("learning c sharp", "learning C#")]
    [InlineData("call the open ai api", "call the OpenAI API")]
    [InlineData("parse the jason", "parse the JSON")]
    [InlineData("train with py torch", "train with PyTorch")]
    [InlineData("deploy to vs code", "deploy to VS Code")]
    public void Process_AppliesPack(string input, string expected)
    {
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(expected, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // The conservative exclusions really do leave ordinary dictation untouched.
    [Theory]
    [InlineData("i will go to the store")]
    [InlineData("the movie sequel was great")]
    [InlineData("i drink java every morning")]
    public void Process_LeavesAmbiguousWordsUntouched(string input)
    {
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(input, TextProcessor.Process(input, ToneStyle.Casual, extra));
    }

    // ===== Layering with the rest of the correction stack =====

    [Fact]
    public void UserCorrectionRule_OverridesPack()
    {
        // user Corrections sit ABOVE the dev pack in UserCorrections.Merge.
        var extra = UserCorrections.Merge(
            DeveloperTerms.Augment(Empty),
            new[] { new CorrectionRule("git hub", "GitLab") });
        Assert.Equal("push to GitLab", TextProcessor.Process("push to git hub", ToneStyle.Casual, extra));
    }

    [Fact]
    public void BuiltinCorrection_StillApplies_AlongsidePack()
    {
        // builtin CorrectionDictionary ("jvoice"->"JVoice") and the pack both fire.
        var extra = DeveloperTerms.Augment(Empty);
        Assert.Equal(
            "OpenAI and JVoice",
            TextProcessor.Process("open ai and jvoice", ToneStyle.Casual, extra));
    }
}
