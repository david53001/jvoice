using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

/// Locks the level-independent no-speech discriminator that replaces the absolute-RMS
/// pre-gate. The annotation strings are the ACTUAL whisper.cpp outputs measured on-device
/// (windows/tools/nospeech-probe, 2026-06-23) for silence / hum / rumble / noise.
public class NonSpeechAnnotationTests
{
    [Theory]
    // exact on-device no-speech outputs:
    [InlineData("[BLANK_AUDIO]")]
    [InlineData("[Music]")]
    [InlineData("[Sigh]")]
    [InlineData("(birds chirping)")]
    // other annotation shapes whisper.cpp is known to emit on non-speech:
    [InlineData("[Applause]")]
    [InlineData("[MUSIC]")]
    [InlineData("(wind blowing)")]
    [InlineData("(speaking foreign language)")]
    [InlineData("  [BLANK_AUDIO]  ")]
    [InlineData("[Music] (applause)")]      // multiple annotations, nothing else
    [InlineData("[BLANK_AUDIO].")]          // annotation + lone punctuation
    [InlineData("(...)")]
    public void AnnotationOnly_IsNoSpeech(string raw)
    {
        Assert.True(NonSpeechAnnotation.IsAnnotationOnly(raw));
        Assert.Equal("", NonSpeechAnnotation.Reduce(raw));
    }

    [Theory]
    // real dictation must NEVER be reduced — including quiet/short utterances and
    // sentences that legitimately contain a parenthetical or a bracketed aside:
    [InlineData("you")]                                   // a real short word David might dictate
    [InlineData("Please figure out this issue.")]
    [InlineData("Thank you.")]                             // handled by the blocklist, not here
    [InlineData("Open the (new) file.")]                  // parenthetical inside real speech
    [InlineData("I said (loudly) hello.")]
    [InlineData("The value is [42] units.")]              // bracket inside real speech
    [InlineData("music")]                                 // the word, not an annotation
    [InlineData("(note to self) buy milk")]               // text outside the group
    public void RealSpeech_IsKept(string raw)
    {
        Assert.False(NonSpeechAnnotation.IsAnnotationOnly(raw));
        Assert.Equal(raw, NonSpeechAnnotation.Reduce(raw));
    }

    [Fact]
    public void EmptyString_IsNotAnnotation()
    {
        // Emptiness is the caller's existing empty-transcript path; "" is not an annotation.
        Assert.False(NonSpeechAnnotation.IsAnnotationOnly(""));
        Assert.Equal("", NonSpeechAnnotation.Reduce(""));
    }
}
