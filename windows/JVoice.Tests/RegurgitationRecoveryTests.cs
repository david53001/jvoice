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

    // ===== Edge / parity coverage the suite missed =====

    // Even with the prompt OFF, the single decode is still scrubbed (RepetitionGuard runs
    // regardless of the prompt flag) — the result is the scrubbed text, not the raw decode.
    [Fact]
    public async Task PromptDisabled_StillScrubs()
    {
        var result = await RegurgitationRecovery.Decode(false, Vocab, _ => Task.FromResult(Regurgitated));
        Assert.Equal("so the thing about money is that", result);
    }

    // The prompted (clean) decode's single call receives usePrompt == true.
    [Fact]
    public async Task CleanDecode_FirstCall_IsPrompted()
    {
        bool? firstArg = null;
        await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            firstArg ??= usePrompt;
            return Task.FromResult(CleanSpeech);
        });
        Assert.True(firstArg);
    }

    // The recovery (second) decode is always prompt-free.
    [Fact]
    public async Task Recovery_SecondDecode_IsPromptFree()
    {
        int calls = 0;
        bool? secondArg = null;
        await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            if (calls == 2) secondArg = usePrompt;
            return Task.FromResult(usePrompt ? Regurgitated : CleanSpeech);
        });
        Assert.False(secondArg);
    }

    // The recovery decode is ALSO scrubbed — a generic loop in the prompt-free decode is stripped.
    [Fact]
    public async Task Recovery_OutputIsAlsoScrubbed()
    {
        const string promptFreeWithLoop =
            "the real words that were spoken here today thanks thanks thanks thanks thanks thanks thanks thanks thanks";
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
            Task.FromResult(usePrompt ? Regurgitated : promptFreeWithLoop));
        Assert.Equal("the real words that were spoken here today", result);
    }

    // If the prompt-free recovery decode is itself all-loop, the result is empty (no silent fallback to the loop).
    [Fact]
    public async Task Recovery_AllLoopPromptFree_ReturnsEmpty()
    {
        var result = await RegurgitationRecovery.Decode(true, new[] { "claude" }, usePrompt =>
            Task.FromResult(usePrompt
                ? ""  // empty prompted decode triggers recovery
                : "claude claude claude claude claude claude claude claude claude claude"));
        Assert.Equal("", result);
    }

    // A decode failure propagates (never swallowed) — both on the first decode and on recovery.
    [Fact]
    public async Task FirstDecodeThrows_Propagates()
        => await Assert.ThrowsAsync<InvalidOperationException>(() =>
            RegurgitationRecovery.Decode(true, Vocab, _ =>
                Task.FromException<string>(new InvalidOperationException("boom"))));

    [Fact]
    public async Task RecoveryDecodeThrows_Propagates()
        => await Assert.ThrowsAsync<InvalidOperationException>(() =>
            RegurgitationRecovery.Decode(true, Vocab, usePrompt => usePrompt
                ? Task.FromResult(Regurgitated)                                  // triggers recovery
                : Task.FromException<string>(new InvalidOperationException("boom"))));
}
