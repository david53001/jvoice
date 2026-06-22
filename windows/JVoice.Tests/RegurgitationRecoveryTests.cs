using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class RegurgitationRecoveryTests
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };
    private const string Regurgitated =
        "so the thing about money is that sub agents, claude, li-fraumeni, vs code, " +
        "sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code";
    private const string CleanSpeech = "so the thing about money is that it grows over time with patience";

    [Fact]
    public async Task RegurgitatedPrompt_ReDecodesWithoutPrompt()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(usePrompt ? Regurgitated : CleanSpeech);
        });
        Assert.Equal(2, calls);            // prompted, then prompt-free recovery
        Assert.Equal(CleanSpeech, result); // the recovered clean decode
    }

    [Fact]
    public async Task CleanPromptedDecode_KeptWithoutRedecode()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(CleanSpeech);
        });
        Assert.Equal(1, calls);            // no wasteful re-decode
        Assert.Equal(CleanSpeech, result);
    }

    [Fact]
    public async Task EmptyPromptedDecode_TriggersRecovery()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(usePrompt ? "" : CleanSpeech);
        });
        Assert.Equal(2, calls);
        Assert.Equal(CleanSpeech, result);
    }

    [Fact]
    public async Task PromptDisabled_SingleDecode_NoRecovery()
    {
        int calls = 0;
        await RegurgitationRecovery.Decode(false, Vocab, _ =>
        {
            calls++;
            return Task.FromResult(Regurgitated);  // would scrub, but no recovery pass when prompt off
        });
        Assert.Equal(1, calls);
    }
}
