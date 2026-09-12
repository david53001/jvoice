using JVoice.Core;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

// Windows-only app-aware modes: pure resolution of a foreground exe name → the tone override
// (if any) it should dictate under. User rules win over the built-in code-app defaults; when
// nothing matches (or the feature is off) the resolver returns null and the caller keeps the
// user's global tone. No I/O — the privileged exe-name read lives in JVoice.App/Platform/System.
public class AppModeResolverTests
{
    private static readonly IReadOnlyList<AppModeRule> None = Array.Empty<AppModeRule>();

    [Fact]
    public void Disabled_ReturnsNull()
        => Assert.Null(AppModeResolver.Resolve("code", None, enabled: false));

    [Fact]
    public void NullOrEmptyExe_ReturnsNull()
    {
        Assert.Null(AppModeResolver.Resolve(null, None, enabled: true));
        Assert.Null(AppModeResolver.Resolve("", None, enabled: true));
        Assert.Null(AppModeResolver.Resolve("   ", None, enabled: true));
    }

    [Fact]
    public void UnknownApp_ReturnsNull()
        => Assert.Null(AppModeResolver.Resolve("notepad", None, enabled: true));

    // Built-in code apps (terminals / editors / IDEs) resolve to Code with zero config.
    [Theory]
    [InlineData("code")]            // VS Code
    [InlineData("cursor")]
    [InlineData("windowsterminal")]
    [InlineData("wt")]
    [InlineData("cmd")]
    [InlineData("powershell")]
    [InlineData("pwsh")]
    [InlineData("conhost")]
    [InlineData("devenv")]          // Visual Studio
    [InlineData("rider64")]
    [InlineData("idea64")]
    [InlineData("pycharm64")]
    [InlineData("clion64")]
    [InlineData("webstorm64")]
    [InlineData("goland64")]
    [InlineData("sublime_text")]
    [InlineData("notepad++")]
    [InlineData("alacritty")]
    [InlineData("wezterm")]
    [InlineData("windsurf")]
    public void BuiltInCodeApps_ResolveToCode(string exe)
        => Assert.Equal(ToneStyle.Code, AppModeResolver.Resolve(exe, None, enabled: true));

    // The exe name arrives from Path.GetFileNameWithoutExtension (e.g. "Code"); resolution is
    // case-insensitive and tolerates a stray ".exe".
    [Theory]
    [InlineData("Code")]
    [InlineData("CODE")]
    [InlineData("Code.exe")]
    [InlineData("WindowsTerminal")]
    public void ExeName_IsCaseInsensitive_AndStripsExtension(string exe)
        => Assert.Equal(ToneStyle.Code, AppModeResolver.Resolve(exe, None, enabled: true));

    // A user rule overrides even a built-in code app.
    [Fact]
    public void UserRule_WinsOverBuiltIn()
    {
        var rules = new[] { new AppModeRule("code", ToneStyle.Formal) };
        Assert.Equal(ToneStyle.Formal, AppModeResolver.Resolve("code", rules, enabled: true));
    }

    // A user rule for a non-code app applies its chosen tone.
    [Fact]
    public void UserRule_AppliesToArbitraryApp()
    {
        var rules = new[] { new AppModeRule("slack", ToneStyle.VeryCasual) };
        Assert.Equal(ToneStyle.VeryCasual, AppModeResolver.Resolve("slack", rules, enabled: true));
    }

    // User-rule matching is substring + case-insensitive (so "studio" catches "studio64").
    [Fact]
    public void UserRule_SubstringMatch_CaseInsensitive()
    {
        var rules = new[] { new AppModeRule("STUDIO", ToneStyle.Formal) };
        Assert.Equal(ToneStyle.Formal, AppModeResolver.Resolve("studio64", rules, enabled: true));
    }

    // First matching user rule wins (list order is precedence).
    [Fact]
    public void FirstMatchingUserRule_Wins()
    {
        var rules = new[]
        {
            new AppModeRule("chat", ToneStyle.Casual),
            new AppModeRule("chat", ToneStyle.Formal),
        };
        Assert.Equal(ToneStyle.Casual, AppModeResolver.Resolve("chatapp", rules, enabled: true));
    }

    // A blank AppMatch never matches (guards against an empty add-row silently rewriting every app).
    [Fact]
    public void BlankUserRuleMatch_IsIgnored()
    {
        var rules = new[] { new AppModeRule("   ", ToneStyle.Formal) };
        Assert.Null(AppModeResolver.Resolve("notepad", rules, enabled: true));
    }

    [Fact]
    public void CodeApps_AreLowercaseAndNonEmpty()
    {
        Assert.NotEmpty(AppModeResolver.CodeApps);
        Assert.All(AppModeResolver.CodeApps, a => Assert.Equal(a.ToLowerInvariant(), a));
    }
}
