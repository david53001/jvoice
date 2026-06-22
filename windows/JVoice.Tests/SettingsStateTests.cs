using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStateTests
{
    [Fact]
    public void Default_MatchesSwiftDefaults()
    {
        var s = SettingsState.Default;
        Assert.Equal(1, s.SchemaVersion);
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.Empty(s.CustomWords);
        Assert.True(s.RemoveFillerWords);
    }
}
