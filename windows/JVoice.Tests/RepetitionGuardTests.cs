using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class RepetitionGuardTests
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };

    [Fact]
    public void Strip_RemovesTrailingRegurgitationLoop()
    {
        const string input = "so the thing about money is that " +
            "sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code, " +
            "sub agents, claude, li-fraumeni, vs code";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("so the thing about money is that", r.Text);
    }

    [Fact]
    public void Scrub_LeavesCoherentSpeechUntouched()
    {
        const string input = "i really like using vs code and claude every day for my work here";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
        Assert.Equal(input, r.Text);
    }

    [Fact]
    public void Scrub_SingleVocabMention_NotStripped()
    {
        const string input = "we studied li-fraumeni syndrome in the lab last year for a long time okay";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
    }

    [Fact]
    public void Scrub_ShortInput_NeverStripped()
    {
        var r = RepetitionGuard.Scrub("claude claude claude", Vocab); // < MinLoopTokens
        Assert.False(r.RemovedRegurgitation);
    }

    // Fuzz: a coherent prefix + a loop-dominated tail must always strip back to (at
    // least) the prefix. The guard is conservative — it only fires when the trailing
    // run is genuinely loop-dominated — so we construct only loop-dominated tails:
    //   (a) the full 4-phrase cycle (6 tokens/rep) repeated 3..8× (18..48 loop tokens), and
    //   (b) a single-token loop repeated 9..14× (>= the 12-token tail window).
    [Fact]
    public void Fuzz_LoopDominatedTailsAlwaysStripped()
    {
        string[] prefixes =
        {
            "okay so here is the plan for the week ahead everyone",
            "the most important thing to remember about this topic is simple",
            "let me explain how the whole process actually works in practice",
        };
        string[] cycle = { "claude", "sub agents", "li-fraumeni", "vs code" };
        int cases = 0, failures = 0;

        foreach (var prefix in prefixes)
        {
            // (a) full-cycle loops
            for (int reps = 3; reps <= 8; reps++)
            {
                string loop = string.Join(", ",
                    Enumerable.Range(0, reps).SelectMany(_ => cycle));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
            // (b) single-token loops
            for (int reps = 9; reps <= 14; reps++)
            {
                string loop = string.Join(", ", Enumerable.Repeat("claude", reps));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
        }

        Assert.True(cases >= 36);
        Assert.Equal(0, failures);
    }

    // Control: a single mention of each vocab phrase inside a long coherent sentence
    // must NEVER be stripped (the inverse of the fuzz).
    [Fact]
    public void Fuzz_SingleMentions_NeverStripped()
    {
        string[] sentences =
        {
            "today i opened vs code and asked claude about the li-fraumeni paper for the lab meeting",
            "my favourite tool is claude and i also run a whole system of sub agents every single day now",
            "we discussed sub agents and vs code at length during the long planning session this afternoon",
        };
        foreach (var s in sentences)
            Assert.False(RepetitionGuard.Scrub(s, Vocab).RemovedRegurgitation);
    }
}
