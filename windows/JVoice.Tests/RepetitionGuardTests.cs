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
    // least) the prefix. The guard is conservative  it only fires when the trailing
    // run is genuinely loop-dominated  so we construct only loop-dominated tails:
    //   (a) the full 4-phrase cycle (6 tokens/rep) repeated 3..8 (18..48 loop tokens), and
    //   (b) a single-token loop repeated 9..14 (>= the 12-token tail window).
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

    // ===== Bug #2: Core must keep marks + ALL number categories (Swift CharacterSet.alphanumerics) =====

    [Fact]
    public void Core_KeepsMarksAndNumberSymbols_LikeSwiftAlphanumerics()
    {
        // Swift core() filters on CharacterSet.alphanumerics (Unicode L* + M* + N*).
        // char.IsLetterOrDigit is only L* + Nd, wrongly dropping combining marks (Mn,
        // here U+0301) and the No number category (here U+00BD = ).
        Assert.Equal("a\u00bd\u0301b", RepetitionGuard.Core("a\u00bd\u0301b"));
    }

    // End-to-end consequence of the Core bug: a repeated No-category token IS a loop in
    // Swift (the token's core is non-empty) but C# dropped it, so the loop went undetected.
    [Fact]
    public void Scrub_NumberSymbolLoop_StrippedLikeSwift()
    {
        string input = "here is a fairly long and coherent sentence that precedes the loop " +
            string.Join(" ", Enumerable.Repeat("\u00bd", 12));
        var r = RepetitionGuard.Scrub(input, Array.Empty<string>());
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("here is a fairly long and coherent sentence that precedes the loop", r.Text);
    }

    // ===== Swift-parity vectors the C# suite was missing =====

    // The original real-world report: a tariffs dictation that degenerated into a
    // vocabulary loop (with a mangled "la-fa" token tolerated mid-loop).
    [Fact]
    public void Strip_ReportedBug_KeepsSpeech_DropsRegurgitation()
    {
        const string input =
            "so basically what tariffs are is when governments put taxes on imported goods " +
            "and who pays them is the people buying the item from a country that is " +
            "sub agents, claude, li-fraumeni, sub agents, claude, vs code, li-fraumeni, " +
            "sub agents, li-fraumeni, sub agents, li-fraumeni, sub agents, li-fraumeni, " +
            "sub agents, li-fraumeni, sub agents, la-fa, li-fraumeni, sub agents, li-fraumeni";
        var outText = RepetitionGuard.Strip(input, Vocab);
        Assert.StartsWith("so basically what tariffs are", outText);
        Assert.Contains("country", outText);
        Assert.DoesNotContain("li-fraumeni", outText.ToLowerInvariant());
        Assert.DoesNotContain("sub agents", outText.ToLowerInvariant());
        Assert.DoesNotContain(",", outText);
        Assert.True(outText.Length < input.Length / 2);
    }

    [Fact]
    public void Strip_WholeTranscriptLoop_ReducesToEmpty()
        => Assert.Equal("", RepetitionGuard.Strip(
            "claude claude claude claude claude claude claude claude claude claude", new[] { "claude" }));

    [Fact]
    public void Strip_GenericRepetitionLoop_NoVocabulary()
        => Assert.Equal("the meeting is tomorrow afternoon", RepetitionGuard.Strip(
            "the meeting is tomorrow afternoon thanks thanks thanks thanks thanks thanks thanks thanks thanks",
            Array.Empty<string>()));

    [Fact]
    public void Strip_OrdinaryProse_Untouched()
    {
        const string input = "the quick brown fox jumps over the lazy dog and then runs back again to sleep";
        Assert.Equal(input, RepetitionGuard.Strip(input, Array.Empty<string>()));
    }

    [Fact]
    public void Strip_DenseButNonRepetitive_Untouched()
    {
        const string input = "today I paired Claude with VS Code and my sub agents to ship the feature";
        Assert.Equal(input, RepetitionGuard.Strip(input, Vocab));
    }

    [Fact]
    public void Strip_EmptyAndWhitespaceInputs_AreSafe()
    {
        Assert.Equal("", RepetitionGuard.Strip("", Vocab));
        Assert.Equal("hello world", RepetitionGuard.Strip("hello world", Vocab));
    }

    [Fact]
    public void Scrub_FlagsAllLoopAsEmpty()
    {
        var r = RepetitionGuard.Scrub(
            "claude claude claude claude claude claude claude claude claude", new[] { "claude" });
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("", r.Text);
    }

    [Fact]
    public void Scrub_FlagsRemovedRegurgitation()
    {
        const string input = "and that is the part sub agents claude li-fraumeni sub agents claude " +
            "vs code li-fraumeni sub agents li-fraumeni sub agents li-fraumeni";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.True(r.RemovedRegurgitation);
        Assert.DoesNotContain("li-fraumeni", r.Text.ToLowerInvariant());
        Assert.StartsWith("and that is the part", r.Text);
    }

    // White-box parity: VocabularyCores splits spoken parts (cf. Swift vocabularyCoresSplitsSpokenParts).
    // NOTE: the Swift test also asserts cores.contains("vs"), but the Swift *algorithm* (faithfully
    // ported here) does NOT produce "vs" for "VS Code": the part "VS" camelCase-splits at the uppercase
    // 'S' into "V"/"S", each <2 chars, so neither is kept — only the whole "vscode" survives. C# matches
    // the Swift algorithm exactly; that one Swift assertion is inconsistent with its own algorithm (a
    // swift-testing #expect failure doesn't abort, so it goes unnoticed). We lock the REAL behaviour.
    [Fact]
    public void VocabularyCores_SplitsSpokenParts()
    {
        var cores = RepetitionGuard.VocabularyCores(new[] { "sub agents", "VS Code", "li-fraumeni" });
        Assert.Contains("sub", cores);
        Assert.Contains("agents", cores);
        Assert.Contains("subagents", cores);
        Assert.Contains("code", cores);
        Assert.Contains("vscode", cores);   // the whole entry, alphanumerics-only
        Assert.Contains("li", cores);
        Assert.Contains("fraumeni", cores);
        Assert.Contains("lifraumeni", cores);
        Assert.DoesNotContain("vs", cores); // "VS" camelCase-splits to V/S (each <2 chars)
    }

    // Contrast: lowercase "vs code" has no camelCase boundary, so "vs" IS kept as a 2-char part.
    [Fact]
    public void VocabularyCores_LowercaseMultiword_KeepsShortPart()
        => Assert.Contains("vs", RepetitionGuard.VocabularyCores(new[] { "vs code" }));

    // Scrub never throws on arbitrary token soup, and never lengthens the text.
    [Fact]
    public void Fuzz_Scrub_NeverThrows_NeverLengthens()
    {
        var rng = new Random(20260623);
        string[] words = { "claude", "vs", "code", "sub", "agents", "the", "and", "a",
                           "li", "fraumeni", "x", "loop", "thanks", ",", ".", "" };
        string[][] vocabs =
        {
            Array.Empty<string>(),
            new[] { "claude" },
            new[] { "sub agents", "vs code", "li-fraumeni" },
        };
        for (int iter = 0; iter < 400; iter++)
        {
            int n = rng.Next(0, 40);
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < n; i++) { if (i > 0) sb.Append(' '); sb.Append(words[rng.Next(words.Length)]); }
            string input = sb.ToString();
            var vocab = vocabs[rng.Next(vocabs.Length)];

            var r = RepetitionGuard.Scrub(input, vocab);
            Assert.NotNull(r.Text);
            Assert.True(r.Text.Length <= input.Length);
            if (!r.RemovedRegurgitation) Assert.Equal(input, r.Text);
        }
    }
}
