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
        // ThrowsAny - the contract is "a JsonException", not the exact leaf type.
        => Assert.ThrowsAny<JsonException>(() => SettingsStateJson.Deserialize("{ not json"));

    // ===== Serialize-side fidelity + round-trip fuzz =====

    // Swift's CodingKeys are schemaVersion/mode/model/language/customWords/removeFillerWords - the
    // C# Serialize must emit exactly those six keys (the on-disk contract).
    [Fact]
    public void Serialize_EmitsExactlyTheSixSwiftKeys()
    {
        using var doc = JsonDocument.Parse(SettingsStateJson.Serialize(SettingsState.Default));
        var keys = doc.RootElement.EnumerateObject().Select(p => p.Name).OrderBy(n => n).ToArray();
        Assert.Equal(
            new[] { "customWords", "language", "mode", "model", "removeFillerWords", "schemaVersion" },
            keys);
    }

    [Fact]
    public void Serialize_WritesEnumNames()
    {
        var s = SettingsState.Default with
        {
            Mode = ToneStyle.VeryCasual,
            Model = WhisperModelOption.LargeTurbo,
            Language = TranscriptionLanguage.Romanian,
        };
        using var doc = JsonDocument.Parse(SettingsStateJson.Serialize(s));
        var root = doc.RootElement;
        Assert.Equal("VeryCasual", root.GetProperty("mode").GetString());
        Assert.Equal("LargeTurbo", root.GetProperty("model").GetString());
        Assert.Equal("Romanian", root.GetProperty("language").GetString());
    }

    // JSON-special characters in custom words must survive a round-trip (escaping/unescaping).
    [Fact]
    public void RoundTrip_CustomWordsWithSpecialChars()
    {
        var state = SettingsState.Default with
        {
            CustomWords = new[] { "a\"b", "c\\d", "e\tf", "g\nh", "\u00e9unicode", "" },
        };
        var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
        Assert.Equal(state.CustomWords, back.CustomWords);
    }

    // Serialize - Deserialize is an identity on all fields, for any valid SettingsState.
    [Fact]
    public void Fuzz_SerializeDeserialize_RoundTrips()
    {
        var rng = new Random(20260623);
        var modes = Enum.GetValues<ToneStyle>();
        var models = Enum.GetValues<WhisperModelOption>();
        var langs = Enum.GetValues<TranscriptionLanguage>();
        for (int i = 0; i < 400; i++)
        {
            int wc = rng.Next(0, 6);
            var words = new string[wc];
            for (int w = 0; w < wc; w++) words[w] = RandomWord(rng);
            var state = new SettingsState(
                SchemaVersion: SettingsState.CurrentSchemaVersion,
                Mode: modes[rng.Next(modes.Length)],
                Model: models[rng.Next(models.Length)],
                Language: langs[rng.Next(langs.Length)],
                CustomWords: words,
                RemoveFillerWords: rng.Next(2) == 0);

            var back = SettingsStateJson.Deserialize(SettingsStateJson.Serialize(state));
            Assert.Equal(state.Mode, back.Mode);
            Assert.Equal(state.Model, back.Model);
            Assert.Equal(state.Language, back.Language);
            Assert.Equal(state.CustomWords, back.CustomWords);
            Assert.Equal(state.RemoveFillerWords, back.RemoveFillerWords);
            Assert.Equal(SettingsState.CurrentSchemaVersion, back.SchemaVersion);
        }
    }

    private static string RandomWord(Random rng)
    {
        const string alpha = "abc XYZ 123 \"\\/,.-_'";
        int n = rng.Next(0, 8);
        var sb = new System.Text.StringBuilder(n);
        for (int i = 0; i < n; i++) sb.Append(alpha[rng.Next(alpha.Length)]);
        return sb.ToString();
    }
}
