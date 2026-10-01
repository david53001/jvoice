using System.Text.Json;
using System.Text.Json.Nodes;

namespace JVoice.Core.Tours;

/// <summary>
/// Everything the tour system persists (Mac <c>TourPreferenceKey</c>) — nothing else. Stored on Windows as
/// <c>%APPDATA%\JVoice\tours.json</c>, its own file so the audience can be written BEFORE settings.json exists and so
/// "the data folder holds anything but tours.json" means the app was used before.
/// </summary>
public sealed class TourPrefs
{
    public const string AudienceKey = "tourAudience";
    public const string QuestionAnsweredKey = "tourQuestionAnswered";
    public const string FirstUseToursEnabledKey = "firstUseToursEnabled";
    public const string SeenKey = "toursSeen";
    public const string PausedKey = "toursPaused";

    public static readonly IReadOnlySet<string> AllKeys = new HashSet<string>
    {
        AudienceKey, QuestionAnsweredKey, FirstUseToursEnabledKey, SeenKey, PausedKey,
    };

    /// <summary>"new" | "existing"; null = not classified yet. Written once, never recomputed.</summary>
    public string? Audience { get; set; }
    /// <summary>True once a new user answered "Want a quick tour?" (or closed the window on it).</summary>
    public bool QuestionAnswered { get; set; }
    /// <summary>Absent (null) = off. True only after "Show Me Around" or the Settings switch.</summary>
    public bool? FirstUseToursEnabled { get; set; }
    /// <summary>Tour id (raw) → catalog version seen (finished or skipped).</summary>
    public Dictionary<string, int> Seen { get; } = new();
    /// <summary>Tour id (raw) → step index to resume at.</summary>
    public Dictionary<string, int> Paused { get; } = new();

    public TourAudienceKind? AudienceKind => TourAudience.Parse(Audience);

    public int? SeenVersion(TourId id) => Seen.TryGetValue(id.Raw(), out var v) ? v : null;

    public string ToJson()
    {
        var o = new JsonObject();
        if (Audience is not null) o[AudienceKey] = Audience;
        if (QuestionAnswered) o[QuestionAnsweredKey] = true;
        if (FirstUseToursEnabled is { } f) o[FirstUseToursEnabledKey] = f;
        if (Seen.Count > 0) o[SeenKey] = Map(Seen);
        if (Paused.Count > 0) o[PausedKey] = Map(Paused);
        return o.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

        static JsonObject Map(Dictionary<string, int> d)
        {
            var m = new JsonObject();
            foreach (var (k, v) in d.OrderBy(p => p.Key, StringComparer.Ordinal)) m[k] = v;
            return m;
        }
    }

    /// <summary>Lenient: a bad file or a bad field reads as absent (an unreadable audience → re-classified, and the
    /// classifier answers "existing" for anyone whose data folder holds anything).</summary>
    public static TourPrefs FromJson(string? json)
    {
        var p = new TourPrefs();
        if (string.IsNullOrWhiteSpace(json)) return p;
        JsonObject? o;
        try { o = JsonNode.Parse(json) as JsonObject; }
        catch (JsonException) { return p; }
        if (o is null) return p;
        if (o[AudienceKey] is JsonValue a && a.TryGetValue(out string? s)) p.Audience = s;
        if (o[QuestionAnsweredKey] is JsonValue q && q.TryGetValue(out bool qa)) p.QuestionAnswered = qa;
        if (o[FirstUseToursEnabledKey] is JsonValue f && f.TryGetValue(out bool fe)) p.FirstUseToursEnabled = fe;
        Read(o[SeenKey], p.Seen);
        Read(o[PausedKey], p.Paused);
        return p;

        static void Read(JsonNode? node, Dictionary<string, int> into)
        {
            if (node is not JsonObject m) return;
            foreach (var (k, v) in m)
                if (v is JsonValue jv && jv.TryGetValue(out int i)) into[k] = i;
        }
    }
}
