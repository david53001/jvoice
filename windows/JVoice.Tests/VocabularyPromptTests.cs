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
}
