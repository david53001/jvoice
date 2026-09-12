using System.IO;
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.Platform;

/// Debounced JSON persistence of SettingsState to %APPDATA%\JVoice\settings.json.
/// Faithful port of SettingsStore.swift: load-on-init with corruption recovery
/// (bad or forward-version file => reset to defaults, original moved to
/// settings.corrupt.bak, reported via SystemActions), 500 ms debounced async
/// writes, Flush(), Reset(). Thread-safety: Update/Reset/Flush are expected to be
/// called from the UI thread (Phase 4); the debounce timer writes on a pool thread.
public sealed class SettingsStore : IDisposable
{
    private readonly string _settingsPath;
    private readonly string _corruptBackupPath;
    private readonly object _gate = new();

    private SettingsState _state;
    private CancellationTokenSource? _saveCts;
    private bool _disposed;

    public event Action<SettingsState>? Changed;

    public SettingsState State
    {
        get { lock (_gate) return _state; }
    }

    public SettingsStore(string? settingsPath = null, string? corruptBackupPath = null)
    {
        _settingsPath = settingsPath ?? PlatformPaths.SettingsFile;
        _corruptBackupPath = corruptBackupPath ?? PlatformPaths.SettingsCorruptBackupFile;

        var (loaded, wasMissing) = Load();
        _state = loaded;
        // Swift wrote defaults to disk when nothing loaded — keep parity so a
        // fresh install has a settings.json immediately.
        if (wasMissing) PerformSave(_state);
    }

    public void Update(Func<SettingsState, SettingsState> transform)
    {
        SettingsState updated;
        lock (_gate)
        {
            updated = transform(_state);
            _state = updated;
        }
        ScheduleSave(updated);
        Changed?.Invoke(updated);
    }

    public void Reset()
    {
        SettingsState reset = SettingsState.Default;
        lock (_gate) _state = reset;
        ScheduleSave(reset);
        Changed?.Invoke(reset);
    }

    public void Flush()
    {
        SettingsState snapshot;
        lock (_gate)
        {
            _saveCts?.Cancel();
            _saveCts = null;
            snapshot = _state;
        }
        PerformSave(snapshot);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Flush();
    }

    // internals

    private void ScheduleSave(SettingsState snapshot)
    {
        CancellationTokenSource cts;
        lock (_gate)
        {
            _saveCts?.Cancel();
            _saveCts = cts = new CancellationTokenSource();
        }
        var token = cts.Token;
        _ = Task.Run(async () =>
        {
            try { await Task.Delay(AppTimings.SettingsDebounceMs, token); }
            catch (OperationCanceledException) { return; }
            if (token.IsCancellationRequested) return;
            PerformSave(snapshot);
        }, token);
    }

    private void PerformSave(SettingsState state)
    {
        try
        {
            string json = SettingsStateJson.Serialize(state);
            string dir = Path.GetDirectoryName(_settingsPath)!;
            Directory.CreateDirectory(dir);
            // Atomic-ish write: temp file then move, so a crash mid-write can't
            // truncate settings.json.
            string tmp = _settingsPath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _settingsPath, overwrite: true);
        }
        catch (Exception ex)
        {
            SystemActions.ReportError(
                $"Failed to save settings — changes may be lost on next launch. {ex.Message}");
        }
    }

    /// Returns (state, wasMissing). On corruption/forward-version, backs up the
    /// bad file and returns defaults with wasMissing = false (so we don't clobber
    /// the backup with an immediate default write).
    private (SettingsState State, bool WasMissing) Load()
    {
        if (!File.Exists(_settingsPath))
            return (SettingsState.Default, WasMissing: true);

        string json;
        try { json = File.ReadAllText(_settingsPath); }
        catch (Exception ex)
        {
            SystemActions.ReportError($"Settings file was unreadable. Using defaults. {ex.Message}");
            return (SettingsState.Default, WasMissing: false);
        }

        try
        {
            return (SettingsStateJson.Deserialize(json), WasMissing: false);
        }
        catch (ForwardVersionException ex)
        {
            BackupCorrupt(json,
                $"Settings were written by a newer JVoice build and reset to defaults. A backup was kept at {_corruptBackupPath}. ({ex.Message})");
            return (SettingsState.Default, WasMissing: false);
        }
        catch (Exception ex) // JsonException etc.
        {
            BackupCorrupt(json,
                $"Settings file was unreadable and reset to defaults. A backup was kept at {_corruptBackupPath}. ({ex.Message})");
            return (SettingsState.Default, WasMissing: false);
        }
    }

    private void BackupCorrupt(string originalJson, string message)
    {
        try { File.WriteAllText(_corruptBackupPath, originalJson); } catch { /* best effort */ }
        SystemActions.ReportError(message);
    }
}
