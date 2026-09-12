using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class UserCorrectionsTests
{
    private static readonly IReadOnlyDictionary<string, string> NoVariants =
        new Dictionary<string, string>();

    [Fact]
    public void Merge_AddsRuleKeyedByLowercasedTrimmedFrom()
    {
        var merged = UserCorrections.Merge(NoVariants, new[]
        {
            new CorrectionRule("  Web API ", "web app"),
        });
        Assert.Equal("web app", merged["web api"]);
    }

    [Fact]
    public void Merge_SkipsRulesWithEmptyFromOrTo()
    {
        var merged = UserCorrections.Merge(NoVariants, new[]
        {
            new CorrectionRule("   ", "x"),
            new CorrectionRule("y", "   "),
            new CorrectionRule("", ""),
        });
        Assert.Empty(merged);
    }

    [Fact]
    public void Merge_LaterRuleWins_OnDuplicateKey()
    {
        var merged = UserCorrections.Merge(NoVariants, new[]
        {
            new CorrectionRule("api", "app"),
            new CorrectionRule("API", "Application"),   // same lowercased key
        });
        Assert.Equal("Application", merged["api"]);
    }

    [Fact]
    public void Merge_RuleOverridesSpokenVariantOnKeyCollision()
    {
        var variants = new Dictionary<string, string> { ["claude"] = "Claude" };
        var merged = UserCorrections.Merge(variants, new[]
        {
            new CorrectionRule("claude", "Cloud"),
        });
        Assert.Equal("Cloud", merged["claude"]);
    }

    [Fact]
    public void Merge_PreservesSpokenVariantsWithNoConflictingRule()
    {
        var variants = new Dictionary<string, string> { ["vs code"] = "VS Code" };
        var merged = UserCorrections.Merge(variants, new[]
        {
            new CorrectionRule("web api", "web app"),
        });
        Assert.Equal("VS Code", merged["vs code"]);
        Assert.Equal("web app", merged["web api"]);
    }

    // ===== End-to-end: the real "web app" → "web api" mishearing =====

    [Fact]
    public void Process_PhraseRule_FixesWebApp_ButLeavesStandaloneApiUntouched()
    {
        var extra = UserCorrections.Merge(NoVariants, new[]
        {
            new CorrectionRule("web api", "web app"),
        });

        // The misheard phrase is corrected...
        Assert.Equal(
            "the web app works",
            TextProcessor.Process("the web api works", ToneStyle.Casual, extra));

        // ...but a legitimate standalone "API" (e.g. "REST API") is preserved,
        // because the rule only fires on the full "web api" phrase.
        Assert.Equal(
            "use the REST API",
            TextProcessor.Process("use the REST API", ToneStyle.Casual, extra));
    }

    [Fact]
    public void Process_PhraseRule_MatchesCaseInsensitively_AndReplacesWithLiteralTo()
    {
        var extra = UserCorrections.Merge(NoVariants, new[]
        {
            new CorrectionRule("web api", "web app"),
        });
        // The mixed-case heard phrase "Web API" matches (case-insensitive) and is
        // replaced with the *literal* To value the user typed ("web app").
        Assert.Equal(
            "my web app is ready",
            TextProcessor.Process("my Web API is ready", ToneStyle.Casual, extra));
    }

    [Fact]
    public void Process_NoRules_LeavesTextUnchanged()
    {
        var extra = UserCorrections.Merge(NoVariants, Array.Empty<CorrectionRule>());
        Assert.Equal(
            "the web api works",
            TextProcessor.Process("the web api works", ToneStyle.Casual, extra));
    }
}
