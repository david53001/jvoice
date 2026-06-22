using System.Text.Json;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStoreJsonTests
{
    [Fact]
    public void RoundTrip_PreservesAllFields()
    {
        var original = new SettingsState(
            SchemaVersion: SettingsState.CurrentSchemaVersion,
            Mode: ToneStyle.Formal,
            Model: WhisperModelOption.LargeTurbo,
            Language: TranscriptionLanguage.Romanian,
            CustomWords: new[] { "JVoice", "Li-Fraumeni" },
            RemoveFillerWords: false);

        string json = SettingsStateJson.Serialize(original);
        var back = SettingsStateJson.Deserialize(json);

        Assert.Equal(original.Mode, back.Mode);
        Assert.Equal(original.Model, back.Model);
        Assert.Equal(original.Language, back.Language);
        Assert.Equal(original.CustomWords, back.CustomWords);
        Assert.Equal(original.RemoveFillerWords, back.RemoveFillerWords);
        Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
    }

    [Fact]
    public void Serialize_AlwaysWritesCurrentSchemaVersion()
    {
        var s = SettingsState.Default with { SchemaVersion = 0 };
        string json = SettingsStateJson.Serialize(s);
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion,
            doc.RootElement.GetProperty("schemaVersion").GetInt32());
    }

    [Fact]
    public void Deserialize_ForwardVersion_Throws()
    {
        string json = """
            { "schemaVersion": 2, "mode": "Casual", "model": "Tiny",
              "language": "English", "customWords": [], "removeFillerWords": true }
            """;
        var ex = Assert.Throws<ForwardVersionException>(() => SettingsStateJson.Deserialize(json));
        Assert.Equal(2, ex.FileVersion);
        Assert.Equal(SettingsState.CurrentSchemaVersion, ex.CurrentVersion);
    }

    [Fact]
    public void Deserialize_MissingSchemaVersion_DefaultsToZero_AndIsAcceptable()
    {
        string json = """{ "mode": "Formal" }""";
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion);
        Assert.Equal(ToneStyle.Formal, s.Mode);
    }

    [Fact]
    public void Deserialize_UnknownEnumValues_FallBackPerField()
    {
        string json = """
            { "schemaVersion": 1, "mode": "Banana", "model": "Quantum",
              "language": "Klingon", "removeFillerWords": "notabool" }
            """;
        var s = SettingsStateJson.Deserialize(json);
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.CustomWords);
    }

    [Fact]
    public void Deserialize_MissingFields_UseDefaults()
    {
        var s = SettingsStateJson.Deserialize("{}");
        Assert.Equal(SettingsState.Default.Mode, s.Mode);
        Assert.Equal(SettingsState.Default.Model, s.Model);
        Assert.Equal(SettingsState.Default.Language, s.Language);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.CustomWords);
    }

    [Theory]
    [InlineData("tiny", WhisperModelOption.Tiny)]
    [InlineData("Tiny", WhisperModelOption.Tiny)]
    [InlineData("largeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("LargeTurbo", WhisperModelOption.LargeTurbo)]
    [InlineData("large-v3_turbo", WhisperModelOption.LargeTurbo)]      // legacy macOS raw value
    [InlineData("large-v3-v20240930", WhisperModelOption.LargeTurbo)]  // legacy macOS raw value
    public void Deserialize_ModelAcceptsLegacyAndCSharpNames(string raw, WhisperModelOption expected)
    {
        string json = $$"""{ "schemaVersion": 1, "model": "{{raw}}" }""";
        Assert.Equal(expected, SettingsStateJson.Deserialize(json).Model);
    }

    [Fact]
    public void Deserialize_StructurallyInvalidJson_ThrowsJsonException()
        // JsonDocument.Parse throws JsonReaderException (a JsonException subclass), so
        // ThrowsAny — the contract is "a JsonException", not the exact leaf type.
        => Assert.ThrowsAny<JsonException>(() => SettingsStateJson.Deserialize("{ not json"));
}
