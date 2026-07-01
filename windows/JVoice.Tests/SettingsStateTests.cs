using System.Text.Json;
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStateTests
{
    [Fact]
    public void Default_MatchesSwiftDefaults()
    {
        var s = SettingsState.Default;
        Assert.Equal(3, s.SchemaVersion);
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.Empty(s.CustomWords);
        Assert.True(s.RemoveFillerWords);
        Assert.Empty(s.Corrections);
        Assert.True(s.DeveloperTerms);   // Windows-only pack, default ON
        Assert.Equal(GameDetectionMode.Balanced, s.GameMode);
        Assert.Equal(HotkeyChord.Default, s.Hotkey);  // Windows-only; Ctrl+Shift+Space
        // v3 (Windows-only dictation features)
        Assert.False(s.CopyToClipboardOnly);   // auto-paste by default
        Assert.Null(s.UndoHotkey);             // undo-last-paste is opt-in (no default chord)
        Assert.False(s.TranslateToEnglish);
        Assert.True(s.AppAwareModes);          // app-aware modes ON by default
        Assert.Empty(s.AppModeRules);          // no user rules (built-in code apps are implicit)
    }

    [Fact]
    public void CurrentSchemaVersion_Is3()
        => Assert.Equal(3, SettingsState.CurrentSchemaVersion);

    [Fact]
    public void Record_With_OverridesOnlyNamedFields()
    {
        var s = SettingsState.Default with { Mode = ToneStyle.Formal, RemoveFillerWords = false };
        Assert.Equal(ToneStyle.Formal, s.Mode);
        Assert.False(s.RemoveFillerWords);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);   // unchanged
        Assert.Equal(3, s.SchemaVersion);
        Assert.Equal(GameDetectionMode.Balanced, s.GameMode);  // unchanged
    }

    // ===== Migration / decode parity (Swift SettingsStateMigrationTests) =====
    // Swift vectors: legacy-no-version, forward-version-fails, unknown-enum->default, encode-has-version
    // are already locked by SettingsStoreJsonTests. These add cross-format + leniency edges.

    // A settings file written in the macOS rawValue style (lowercase) must still decode (Enum.TryParse
    // is case-insensitive and the model switch handles the spoken forms). Mirrors the Swift rawValues.
    [Fact]
    public void Deserialize_AcceptsMacOSLowercaseRawValues()
    {
        var s = SettingsStateJson.Deserialize(
            """{"mode":"casual","model":"tiny","language":"english","customWords":["X"],"removeFillerWords":true}""");
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.Equal(new[] { "X" }, s.CustomWords);

        var s2 = SettingsStateJson.Deserialize("""{"mode":"veryCasual","language":"romanian","model":"small"}""");
        Assert.Equal(ToneStyle.VeryCasual, s2.Mode);
        Assert.Equal(TranscriptionLanguage.Romanian, s2.Language);
        Assert.Equal(WhisperModelOption.Small, s2.Model);

        var s3 = SettingsStateJson.Deserialize("""{"mode":"formal","model":"base"}""");
        Assert.Equal(ToneStyle.Formal, s3.Mode);
        Assert.Equal(WhisperModelOption.Base, s3.Model);
    }

    // C# leniency (documented in SettingsStateJson + locked here): a customWords array with non-string
    // elements keeps only the strings. (Swift's decodeIfPresent([String]) would throw on a mixed array;
    // see the ledger "intentional deviations" note.)
    [Fact]
    public void Deserialize_CustomWords_KeepsOnlyStrings()
    {
        var s = SettingsStateJson.Deserialize("""{"customWords":["ok",5,null,"yes",true]}""");
        Assert.Equal(new[] { "ok", "yes" }, s.CustomWords);
    }

    // C# leniency: a non-numeric schemaVersion reads as absent (version 0) and is accepted+normalized.
    // (Swift's decodeIfPresent(Int) would throw on the type mismatch.)
    [Fact]
    public void Deserialize_SchemaVersionWrongType_TreatedAsZero()
    {
        var s = SettingsStateJson.Deserialize("""{"schemaVersion":"oops","mode":"Formal"}""");
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion);
        Assert.Equal(ToneStyle.Formal, s.Mode);
    }

    // schemaVersion exactly == current is accepted (boundary; only > current is refused).
    [Fact]
    public void Deserialize_SchemaVersionEqualToCurrent_IsAccepted()
    {
        var s = SettingsStateJson.Deserialize("""{"schemaVersion":3,"mode":"Formal"}""");
        Assert.Equal(ToneStyle.Formal, s.Mode);
    }

    // Deserialize over arbitrary well-formed settings JSON never throws anything except
    // ForwardVersionException (version > current); valid blobs always normalize schemaVersion forward.
    [Fact]
    public void Fuzz_Deserialize_OnlyThrowsForwardVersion()
    {
        var rng = new Random(20260623);
        string[] modes = { "Casual", "casual", "Formal", "VeryCasual", "Banana", "" };
        string[] models = { "Tiny", "tiny", "LargeTurbo", "large-v3_turbo", "Quantum" };
        string[] langs = { "English", "english", "Romanian", "Klingon" };
        for (int i = 0; i < 400; i++)
        {
            int version = rng.Next(0, 5); // 0..4 — anything > 2 must throw ForwardVersionException
            var dto = new
            {
                schemaVersion = version,
                mode = modes[rng.Next(modes.Length)],
                model = models[rng.Next(models.Length)],
                language = langs[rng.Next(langs.Length)],
                customWords = new[] { "a", "b" },
                removeFillerWords = rng.Next(2) == 0,
            };
            string json = JsonSerializer.Serialize(dto);
            if (version > SettingsState.CurrentSchemaVersion)
            {
                Assert.Throws<ForwardVersionException>(() => SettingsStateJson.Deserialize(json));
            }
            else
            {
                var s = SettingsStateJson.Deserialize(json);
                Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion); // always normalized forward
            }
        }
    }

    // ===== GameMode (schema v2) =====

    // A v1 file (no "gameMode" field) must deserialize cleanly and default GameMode to Balanced.
    [Fact]
    public void Deserialize_V1File_DefaultsGameModeToBalanced()
    {
        const string v1Json = """
            {
                "schemaVersion": 1,
                "mode": "Casual",
                "model": "Tiny",
                "language": "English",
                "customWords": [],
                "removeFillerWords": true,
                "corrections": []
            }
            """;
        var s = SettingsStateJson.Deserialize(v1Json);
        Assert.Equal(GameDetectionMode.Balanced, s.GameMode);
        Assert.Equal(SettingsState.CurrentSchemaVersion, s.SchemaVersion); // normalized to 2
        Assert.Equal(ToneStyle.Casual, s.Mode);
    }

    // GameMode round-trips: Aggressive and Off survive serialize → deserialize unchanged.
    [Fact]
    public void GameMode_RoundTrips()
    {
        foreach (var expected in new[] { GameDetectionMode.Aggressive, GameDetectionMode.Off, GameDetectionMode.Balanced })
        {
            var original = SettingsState.Default with { GameMode = expected };
            string json = SettingsStateJson.Serialize(original);
            var roundTripped = SettingsStateJson.Deserialize(json);
            Assert.Equal(expected, roundTripped.GameMode);
        }
    }
}
