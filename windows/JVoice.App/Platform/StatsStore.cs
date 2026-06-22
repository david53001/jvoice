using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using JVoice.Core;

namespace JVoice.App.Platform;

/// Lifetime dictation stats persisted to %APPDATA%\JVoice\stats.json.
/// Faithful port of StatsStore.swift (totalWords + totalSeconds, averageWPM,
/// Record ignores non-positive inputs). Persists synchronously on every Record
/// (stats are small and written rarely — once per dictation).
public sealed class StatsStore
{
    private sealed class StatsDto
    {
        [JsonPropertyName("totalWords")] public int TotalWords { get; set; }
        [JsonPropertyName("totalSeconds")] public double TotalSeconds { get; set; }
    }

    private readonly string _path;
    private readonly object _gate = new();
    private StatsDto _data;

    public StatsStore(string? statsPath = null)
    {
        _path = statsPath ?? PlatformPaths.StatsFile;
        _data = Load();
    }

    public int TotalWords { get { lock (_gate) return _data.TotalWords; } }
    public double TotalSeconds { get { lock (_gate) return _data.TotalSeconds; } }
    public double AverageWpm { get { lock (_gate) return StatsMath.AverageWpm(_data.TotalWords, _data.TotalSeconds); } }

    public void Record(int words, double durationSeconds)
    {
        if (words <= 0 || durationSeconds <= 0) return; // Swift guard
        lock (_gate)
        {
            _data.TotalWords += words;
            _data.TotalSeconds += durationSeconds;
            Save(_data);
        }
    }

    public void Reset()
    {
        lock (_gate)
        {
            _data = new StatsDto();
            Save(_data);
        }
    }

    private StatsDto Load()
    {
        try
        {
            if (!File.Exists(_path)) return new StatsDto();
            string json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<StatsDto>(json) ?? new StatsDto();
        }
        catch
        {
            return new StatsDto(); // corrupt stats are non-critical: start fresh
        }
    }

    private void Save(StatsDto data)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            string tmp = _path + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Failed to save stats. {ex.Message}");
        }
    }
}
