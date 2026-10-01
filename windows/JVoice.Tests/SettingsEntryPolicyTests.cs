using JVoice.Core;
using Xunit;

namespace JVoice.Tests;

/// <summary>Parity row 19 (doc §6.6; Mac SettingsEntryPolicy): a refused Settings entry says why and keeps its text.</summary>
public class SettingsEntryPolicyTests
{
    private static readonly string[] Words = { "VS Code", "Claude", "JVoice" };

    [Theory]
    [InlineData("Kubernetes")]
    [InlineData("  .NET  ")]
    [InlineData("C#")]
    [InlineData("Li-Fraumeni")]
    [InlineData("")]     // blank is never a rejection (the field doesn't submit it)
    [InlineData("   ")]
    public void CustomWordsThatAreAccepted(string word) => Assert.Null(SettingsEntryPolicy.CustomWordRejection(word, Words));

    [Fact]
    public void CustomWordRejectionsSayWhy()
    {
        Assert.Equal("“VS Code” is already in your list.", SettingsEntryPolicy.CustomWordRejection("vs code", Words));
        Assert.Equal("“Claude” is already in your list.", SettingsEntryPolicy.CustomWordRejection("  CLAUDE ", Words));
        Assert.Equal("A custom word needs at least one letter or number.", SettingsEntryPolicy.CustomWordRejection("—!?", Words));
        Assert.Equal("Too long: a custom word can be up to 60 characters.",
            SettingsEntryPolicy.CustomWordRejection(new string('a', 61), Words));
        Assert.Null(SettingsEntryPolicy.CustomWordRejection(new string('a', 60), Words));
    }

    [Fact]
    public void AppRules()
    {
        var rules = new[] { "chrome.exe", " Code.exe " };
        Assert.Null(SettingsEntryPolicy.AppRuleRejection("discord", rules));
        Assert.Null(SettingsEntryPolicy.AppRuleRejection("chr", rules)); // a partial name is fine: rules match by substring
        Assert.Null(SettingsEntryPolicy.AppRuleRejection("", rules));
        Assert.Equal("“chrome.exe” already has a mode. Remove it first to change it.",
            SettingsEntryPolicy.AppRuleRejection("CHROME.EXE", rules));
        Assert.Equal("“Code.exe” already has a mode. Remove it first to change it.",
            SettingsEntryPolicy.AppRuleRejection("code.exe", rules));
        Assert.Equal("An app name needs at least one letter or number.", SettingsEntryPolicy.AppRuleRejection("...", rules));
    }

    [Fact]
    public void Corrections()
    {
        var froms = new[] { "web api" };
        Assert.Null(SettingsEntryPolicy.CorrectionRejection("jay voice", "JVoice", froms));
        Assert.Null(SettingsEntryPolicy.CorrectionRejection("github", "GitHub", froms)); // a case change is a real fix
        Assert.Null(SettingsEntryPolicy.CorrectionRejection(" ", " ", froms));
        Assert.Equal("Type what JVoice hears on the left.", SettingsEntryPolicy.CorrectionRejection("", "x", froms));
        Assert.Equal("Type what it should become on the right.", SettingsEntryPolicy.CorrectionRejection("x", "  ", froms));
        Assert.Equal("Both sides are the same, so there's nothing to fix.", SettingsEntryPolicy.CorrectionRejection("same", "same", froms));
        Assert.Equal("“web api” already has a correction. Remove it first to change it.",
            SettingsEntryPolicy.CorrectionRejection("Web API", "web app", froms));
    }
}
