using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class VocabularyPromptTests
{
    [Fact]
    public void Empty_ReturnsNull()
    {
        Assert.Null(VocabularyPrompt.Text(Array.Empty<string>()));
        Assert.Null(VocabularyPrompt.Text(new[] { "", "   " }));
    }

    [Fact]
    public void JoinsWithLeadingSpaceAndCommas()
    {
        // The leading space is required (Whisper BPE merges a leading space into word tokens).
        Assert.Equal(" VS Code, JVoice", VocabularyPrompt.Text(new[] { "VS Code", "JVoice" }));
    }

    [Fact]
    public void TrimsAndDropsBlanks()
    {
        Assert.Equal(" Claude", VocabularyPrompt.Text(new[] { "  Claude  ", "" }));
    }

    [Fact]
    public void CapsAtMaxWords()
    {
        var words = Enumerable.Range(0, 50).Select(i => $"w{i}").ToArray();
        var text = VocabularyPrompt.Text(words)!;
        Assert.Equal(VocabularyPrompt.MaxWords, text.Split(", ").Length);
    }

    // ===== Swift-parity + boundary/edge coverage =====

    [Fact]
    public void Constants_MatchSwift()
    {
        Assert.Equal(40, VocabularyPrompt.MaxWords);
        Assert.Equal(96, VocabularyPrompt.MaxPromptTokens);
    }

    // Mirrors VocabularyPromptTests.swift vocabularyIsCappedToBoundDecodeCost: word39 present,
    // word40 dropped, does not end on word99, exactly 40 segments, last segment is word39.
    [Fact]
    public void CapsAtMaxWords_PrecisePrefix()
    {
        var words = Enumerable.Range(0, 100).Select(i => $"word{i}").ToArray();
        var text = VocabularyPrompt.Text(words)!;
        Assert.Contains($"word{VocabularyPrompt.MaxWords - 1}", text);   // word39
        Assert.DoesNotContain($"word{VocabularyPrompt.MaxWords},", text); // no word40,
        Assert.False(text.EndsWith("word99"));
        var segs = text.Split(", ");
        Assert.Equal(VocabularyPrompt.MaxWords, segs.Length);
        Assert.Equal("word39", segs[^1]);
        Assert.Equal(" word0", segs[0]);
    }

    [Theory]
    [InlineData(39, 39)]
    [InlineData(40, 40)]
    [InlineData(41, 40)]
    public void WordCount_BoundaryCappedAt40(int input, int expectedSegments)
    {
        var words = Enumerable.Range(0, input).Select(i => $"w{i}").ToArray();
        var text = VocabularyPrompt.Text(words)!;
        Assert.Equal(expectedSegments, text.Split(", ").Length);
    }

    [Fact]
    public void SingleWord_AndOrderPreserved()
    {
        Assert.Equal(" solo", VocabularyPrompt.Text(new[] { "solo" }));
        Assert.Equal(" b, a", VocabularyPrompt.Text(new[] { "b", "a" }));   // order preserved, not sorted
    }

    // Trim uses the SAME set as Swift's .whitespacesAndNewlines (tab, newline, and Zs incl. U+00A0).
    [Fact]
    public void Trims_TabNewlineNbsp()
    {
        Assert.Equal(" Claude", VocabularyPrompt.Text(new[] { "\t Claude \n" }));
        Assert.Equal(" Claude", VocabularyPrompt.Text(new[] { " Claude " }));
        Assert.Null(VocabularyPrompt.Text(new[] { " ", "\t", "\n" }));   // all-whitespace dropped
    }

    [Fact]
    public void Duplicates_NotDeduped()
        => Assert.Equal(" A, A", VocabularyPrompt.Text(new[] { "A", "A" }));

    // An entry that itself contains ", " is NOT escaped — faithful to Swift (no special handling).
    [Fact]
    public void EntryContainingComma_IsNotEscaped()
        => Assert.Equal(" VS, Code", VocabularyPrompt.Text(new[] { "VS, Code" }));

    // Text never throws, and the output is well-formed: null iff no non-blank entries,
    // otherwise it starts with a single leading space.
    [Fact]
    public void Fuzz_Text_NeverThrows_WellFormed()
    {
        var rng = new Random(20260623);
        const string alpha = "ab CD, \t\n .-";
        for (int iter = 0; iter < 300; iter++)
        {
            int n = rng.Next(0, 60);
            var words = new string[n];
            for (int i = 0; i < n; i++) words[i] = RandomString(rng, alpha, rng.Next(0, 8));

            var text = VocabularyPrompt.Text(words);
            bool anyNonBlank = words.Any(w => w.Trim().Length > 0);
            if (anyNonBlank)
            {
                Assert.NotNull(text);
                Assert.StartsWith(" ", text!);
            }
            else
            {
                Assert.Null(text);
            }
        }
    }

    private static string RandomString(Random rng, string alphabet, int length)
    {
        var sb = new System.Text.StringBuilder(length);
        for (int i = 0; i < length; i++) sb.Append(alphabet[rng.Next(alphabet.Length)]);
        return sb.ToString();
    }
}
