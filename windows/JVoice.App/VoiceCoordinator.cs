using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;
using JVoice.Core;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using JVoice.Core.Transcription;

namespace JVoice.App;

public sealed class VoiceCoordinator : INotifyPropertyChanged, IDisposable
{
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;

    // Platform services (Phase 3) + engine pieces (Phase 2).
    private readonly SettingsStore _settingsStore;
    private readonly StatsStore _statsStore = new();
    private readonly LastTranscriptStore _lastTranscriptStore = new();
    private readonly TranscriptHistoryStore _historyStore = new();
    private readonly IAudioRecorder _recorder = new NAudioRecorder();
    private readonly Paster _paster = new();
    private readonly ForegroundWindowTracker _foreground = new();
    private readonly GlobalHotkey _hotkey = new();
    private readonly WhisperModelStore _modelStore = new();
    private GameDetector? _gameDetector;

    private ITranscriptionEngine _engine;

    // UI surfaces (set by App in Task 9).
    public HudWindow? Hud { get; set; }
    public TrayIcon? Tray { get; set; }
    private SettingsWindow? _settingsWindow;

    // ---- coordinator state (mirrors the Swift @Published / private fields) ----
    private int _recordingGeneration;
    private bool _isStartingRecording;
    private bool _isStoppingRecording;
    private bool _isInitializing = true;
    private DateTime? _recordingStartUtc;
    private double _lastRecordingSeconds;
    private StreamingTranscriptionSession? _streamingSession;
    private CancellationTokenSource? _transcriptionCts;
    private DispatcherTimer? _hudResetTimer;
    private string[] _pendingRevertWords = [];
    private string _preFixTranscript = "";

    public VoiceCoordinator()
    {
        _settingsStore = new SettingsStore();
        var s = _settingsStore.State;

        _toneMode = s.Mode;
        _whisperModel = s.Model;
        _language = s.Language;
        CustomWords = new ObservableCollection<string>(s.CustomWords);
        Corrections = new ObservableCollection<CorrectionRule>(s.Corrections);
        RecentTranscripts = new ObservableCollection<TranscriptRow>(
            _historyStore.Entries.Select(e => new TranscriptRow(e.Id, e.Text)));
        _removeFillerWords = s.RemoveFillerWords;
        _hotkeyChord = HotkeyChord.Default;
        _gameMode = s.GameMode;
        _totalWordsSpoken = _statsStore.TotalWords;
        _averageWpm = _statsStore.AverageWpm;
        _lastTranscript = _lastTranscriptStore.Transcript;
        EditedTranscript = _lastTranscript;
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;

        _engine = MakeEngine(_whisperModel, _language, CustomWords.ToList());
        _isInitializing = false;
    }

    // ====================== bindable properties ======================

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private ToneStyle _toneMode;
    public ToneStyle ToneMode
    {
        get => _toneMode;
        set { if (_toneMode == value) return; _toneMode = value; PersistSettings(); RaiseToneFlags(); }
    }

    private WhisperModelOption _whisperModel;
    public WhisperModelOption WhisperModel
    {
        get => _whisperModel;
        set
        {
            if (_whisperModel == value) return;
            _whisperModel = value;
            SwapEngine();
            PersistSettings();
            Raise(nameof(ModelGuidance)); RaiseModelFlags();
        }
    }

    private TranscriptionLanguage _language;
    public TranscriptionLanguage Language
    {
        get => _language;
        set
        {
            if (_language == value) return;
            _language = value;
            SwapEngine();
            PersistSettings();
            RaiseLanguageFlags();
        }
    }

    private bool _removeFillerWords;
    public bool RemoveFillerWords
    {
        get => _removeFillerWords;
        set { if (_removeFillerWords == value) return; _removeFillerWords = value; PersistSettings(); Raise(); }
    }

    public ObservableCollection<string> CustomWords { get; }

    /// User-defined post-processing corrections ("heard phrase" → replacement).
    /// Unlike CustomWords these don't touch the decoder/vocabulary — they are applied
    /// to the final text in the transcription path (see ProcessAndPaste), so adding or
    /// removing one just persists; no engine reload.
    public ObservableCollection<CorrectionRule> Corrections { get; }

    /// Read-only history of the most recent finalized transcripts (newest first,
    /// capped at TranscriptHistory.MaxEntries). Backed by _historyStore (persisted
    /// JSON); the rows carry only Id + Text plus a transient "just copied" flag.
    public ObservableCollection<TranscriptRow> RecentTranscripts { get; }

    private HotkeyChord _hotkeyChord;
    public HotkeyChord Hotkey => _hotkeyChord;

    private string _lastTranscript = "";
    public string LastTranscript
    {
        get => _lastTranscript;
        private set { _lastTranscript = value; Raise(); Raise(nameof(HasTranscript)); }
    }

    private string _editedTranscript = "";
    public string EditedTranscript
    {
        get => _editedTranscript;
        set { _editedTranscript = value; Raise(); Raise(nameof(CanFix)); }
    }

    private bool _canRevert;
    public bool CanRevert { get => _canRevert; private set { _canRevert = value; Raise(); } }

    private int _totalWordsSpoken;
    public int TotalWordsSpoken { get => _totalWordsSpoken; private set { _totalWordsSpoken = value; Raise(); } }

    private double _averageWpm;
    public double AverageWpm { get => _averageWpm; private set { _averageWpm = value; Raise(); Raise(nameof(AverageWpmDisplay)); } }
    public string AverageWpmDisplay => AverageWpm > 0 ? AverageWpm.ToString("F0") : "—";

    public bool LaunchAtLoginEnabled { get; private set; }

    private bool _isRecording;
    public bool IsRecording { get => _isRecording; private set { _isRecording = value; Raise(); } }

    private HudState _hudState = HudState.Idle;
    public HudState HudState { get => _hudState; private set { _hudState = value; Raise(); } }

    /// Live microphone level (0..1 peak) for the HUD voice-activity bars. The HUD's
    /// per-frame render loop polls this; it reads 0 whenever we're not recording.
    public float CurrentInputLevel => _recorder.CurrentLevel;

    // ---- derived flags for the segmented pickers + visibility binders ----
    public bool HasTranscript => !string.IsNullOrEmpty(LastTranscript);
    public bool HasCustomWords => CustomWords.Count > 0;
    public bool HasCorrections => Corrections.Count > 0;
    public bool HasRecentTranscripts => RecentTranscripts.Count > 0;
    public bool CanFix => EditedTranscript.Trim() != LastTranscript.Trim();
    public string ModelGuidance => WhisperModel.Guidance();

    public bool IsEnglish { get => Language == TranscriptionLanguage.English; set { if (value) Language = TranscriptionLanguage.English; } }
    public bool IsRomanian { get => Language == TranscriptionLanguage.Romanian; set { if (value) Language = TranscriptionLanguage.Romanian; } }
    public bool IsCasual { get => ToneMode == ToneStyle.Casual; set { if (value) ToneMode = ToneStyle.Casual; } }
    public bool IsFormal { get => ToneMode == ToneStyle.Formal; set { if (value) ToneMode = ToneStyle.Formal; } }
    public bool IsVeryCasual { get => ToneMode == ToneStyle.VeryCasual; set { if (value) ToneMode = ToneStyle.VeryCasual; } }
    public bool IsTiny { get => WhisperModel == WhisperModelOption.Tiny; set { if (value) WhisperModel = WhisperModelOption.Tiny; } }
    public bool IsBase { get => WhisperModel == WhisperModelOption.Base; set { if (value) WhisperModel = WhisperModelOption.Base; } }
    public bool IsSmall { get => WhisperModel == WhisperModelOption.Small; set { if (value) WhisperModel = WhisperModelOption.Small; } }
    public bool IsLarge { get => WhisperModel == WhisperModelOption.LargeTurbo; set { if (value) WhisperModel = WhisperModelOption.LargeTurbo; } }

    private void RaiseToneFlags() { Raise(nameof(IsCasual)); Raise(nameof(IsFormal)); Raise(nameof(IsVeryCasual)); }
    private void RaiseLanguageFlags() { Raise(nameof(IsEnglish)); Raise(nameof(IsRomanian)); }
    private void RaiseModelFlags() { Raise(nameof(IsTiny)); Raise(nameof(IsBase)); Raise(nameof(IsSmall)); Raise(nameof(IsLarge)); }

    private GameDetectionMode _gameMode;
    public GameDetectionMode GameMode
    {
        get => _gameMode;
        set { if (_gameMode == value) return; _gameMode = value; if (_gameDetector is not null) _gameDetector.Mode = value; PersistSettings(); RaiseGameModeFlags(); }
    }
    public bool IsGameOff        { get => GameMode == GameDetectionMode.Off;        set { if (value) GameMode = GameDetectionMode.Off; } }
    public bool IsGameBalanced   { get => GameMode == GameDetectionMode.Balanced;   set { if (value) GameMode = GameDetectionMode.Balanced; } }
    public bool IsGameAggressive { get => GameMode == GameDetectionMode.Aggressive; set { if (value) GameMode = GameDetectionMode.Aggressive; } }
    private void RaiseGameModeFlags() { Raise(nameof(IsGameOff)); Raise(nameof(IsGameBalanced)); Raise(nameof(IsGameAggressive)); }

    // ====================== lifecycle / wiring ======================

    /// Ports VoiceCoordinator.start(): sweep orphans, install hooks, hotkey, prewarm.
    public void Start()
    {
        NAudioRecorder.SweepOrphanedRecordings();

        _foreground.Start();

        _gameDetector = new GameDetector(_foreground) { Mode = _gameMode };
        _gameDetector.Start();

        SystemActions.ErrorHandler = msg => _dispatcher.InvokeAsync(() => ShowError(msg));
        _settingsStore.Changed += _ => _dispatcher.InvokeAsync(() => { /* UI binds live props */ });
        _recorder.Failed += msg => _dispatcher.InvokeAsync(() => ShowError(msg));
        _hotkey.Triggered += () => _dispatcher.InvokeAsync(ToggleRecording);
        _hotkey.SuppressPredicate = () => _gameDetector?.ShouldSuppress == true;
        _hotkey.Register(_hotkeyChord);

        UpdateHud(HudState.Idle);

        _ = _engine.PrewarmAsync();
    }

    public void BootstrapLaunchAtLogin()
    {
        LaunchAtLogin.PerformFirstRunEnableIfNeeded();
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;
        Raise(nameof(LaunchAtLoginEnabled));
    }

    public void SetLaunchAtLogin(bool enabled)
    {
        LaunchAtLogin.SetEnabled(enabled);
        LaunchAtLoginEnabled = LaunchAtLogin.IsEnabled;
        Raise(nameof(LaunchAtLoginEnabled));
        Tray?.RebuildMenu();
    }

    public void ToggleLaunchAtLogin() => SetLaunchAtLogin(!LaunchAtLoginEnabled);

    // ---- elevation (UIPI) — let the hotkey/paste reach "Run as administrator" windows ----
    // A non-elevated process's global keyboard hook never fires while an elevated window has focus
    // (UIPI), so JVoice itself must run elevated. For an unsigned app, running elevated is the only
    // available fix (uiAccess=true needs signing + Program Files). See Elevation / ElevatedAutostart.

    /// True when THIS process is already elevated (full administrator).
    public bool IsElevated => Elevation.IsElevated;

    /// True when the elevated logon task is registered (JVoice auto-starts elevated at login).
    public bool RunAsAdminAtLoginEnabled => ElevatedAutostart.IsEnabled;

    /// One-off: relaunch elevated NOW (no persistence) so the hotkey/paste work in elevated apps
    /// for this session. On success the current (non-elevated) instance quits so the elevated copy
    /// can take over the single-instance slot.
    public void RestartAsAdministrator()
    {
        if (IsElevated) return; // already elevated — nothing to do
        var result = Elevation.RelaunchElevated(Elevation.RelaunchFlag);
        if (result == Elevation.RelaunchResult.Started)
            QuitApp(); // releases the hotkey hook + single-instance mutex for the elevated copy
        else
            Tray?.RebuildMenu(); // UAC cancelled / failed — no state change, just refresh
    }

    public void ToggleRunAsAdminAtLogin() => SetRunAsAdminAtLogin(!RunAsAdminAtLoginEnabled);

    /// Enable/disable elevated auto-start (the Task Scheduler HIGHEST logon task). Registering or
    /// removing that task is privileged, so when we're not already elevated we relaunch elevated and
    /// let the elevated copy apply it on startup (ApplyElevationStartupIntent).
    public void SetRunAsAdminAtLogin(bool enabled)
    {
        if (enabled)
        {
            if (IsElevated)
            {
                EnableElevatedAutostartInProcess();
            }
            else
            {
                var result = Elevation.RelaunchElevated(Elevation.EnableAutostartFlag);
                if (result == Elevation.RelaunchResult.Started) { QuitApp(); return; }
            }
        }
        else
        {
            // Try in-process first (works when elevated — the common case after enabling). If it
            // fails only because we're not elevated, relaunch elevated just to remove the task.
            if (!ElevatedAutostart.Disable(out var err))
            {
                if (!IsElevated)
                {
                    var result = Elevation.RelaunchElevated(Elevation.DisableAutostartFlag);
                    if (result == Elevation.RelaunchResult.Started) { QuitApp(); return; }
                }
                else ShowError($"Couldn't disable admin auto-start. {err}");
            }
        }
        Raise(nameof(RunAsAdminAtLoginEnabled));
        Tray?.RebuildMenu();
    }

    /// Called once on startup when this (elevated) process was relaunched specifically to register
    /// or unregister the elevated logon task. No-op for a normal launch.
    public void ApplyElevationStartupIntent(string[] args)
    {
        var flag = Elevation.MatchedFlag(args);
        if (flag == Elevation.EnableAutostartFlag)
        {
            EnableElevatedAutostartInProcess();
        }
        else if (flag == Elevation.DisableAutostartFlag)
        {
            if (!ElevatedAutostart.Disable(out var err))
                ShowError($"Couldn't disable admin auto-start. {err}");
        }
        else return; // RelaunchFlag (one-off) or normal launch — nothing to persist
        Raise(nameof(RunAsAdminAtLoginEnabled));
        Tray?.RebuildMenu();
    }

    /// Register the elevated logon task (must be called elevated). If non-elevated launch-at-login
    /// is ALSO on, rewrite its Run-key value so it carries the --autostart marker — that makes the
    /// logon copy step aside for this elevated task (App.Main) instead of racing it and possibly
    /// winning as a non-elevated instance, which would silently break the hotkey in elevated apps.
    private void EnableElevatedAutostartInProcess()
    {
        if (!ElevatedAutostart.Enable(out var err))
        {
            ShowError($"Couldn't enable admin auto-start. {err}");
            return;
        }
        if (LaunchAtLogin.IsEnabled) LaunchAtLogin.SetEnabled(true);
    }

    public void SetHotkey(HotkeyChord chord)
    {
        _hotkeyChord = chord;
        _hotkey.Register(chord);
        Raise(nameof(Hotkey));
        // SettingsState has no hotkey field in Phase 1 — rebind lives for the session
        // and resets to Default on relaunch (documented assumption).
    }

    public void ShowSettings()
    {
        _settingsWindow ??= new SettingsWindow(this);
        _settingsWindow.ShowOrActivate();
    }

    // ---- engine construction / swap (TranscriptionManager analog) ----

    private ITranscriptionEngine MakeEngine(WhisperModelOption model, TranscriptionLanguage lang, IReadOnlyList<string> vocab)
    {
        try
        {
            return new WhisperNetTranscriptionEngine(model, lang, vocab, useVocabularyPrompt: true, _modelStore);
        }
        catch
        {
            return new FileBackedTranscriptionEngine();
        }
    }

    private void SwapEngine()
    {
        var model = _whisperModel;
        var lang = _language;
        var vocab = CustomWords.ToList();
        _engine = MakeEngine(model, lang, vocab);

        _ = Task.Run(async () =>
        {
            try
            {
                if (_modelStore.CompleteModelPath(model) is null)
                {
                    var progress = new Progress<double>(p =>
                        _dispatcher.InvokeAsync(() => UpdateHud(HudState.DownloadingModel(double.IsNaN(p) ? 0 : p))));
                    await _modelStore.EnsureAsync(model, progress, CancellationToken.None);
                    await _dispatcher.InvokeAsync(() => { if (HudState.Kind == HudStateKind.DownloadingModel) UpdateHud(HudState.Idle); });
                }
                await _engine.PrewarmAsync();
            }
            catch (Exception ex)
            {
                _dispatcher.InvokeAsync(() => ShowError($"Couldn't prepare the model: {ex.Message}"));
            }
        });
    }

    // ---- persistence ----

    private void PersistSettings()
    {
        if (_isInitializing) return;
        _settingsStore.Update(prev => prev with
        {
            Mode = _toneMode,
            Model = _whisperModel,
            Language = _language,
            CustomWords = CustomWords.ToList(),
            RemoveFillerWords = _removeFillerWords,
            Corrections = Corrections.ToList(),
            GameMode = _gameMode,
        });
    }

    public void FlushSettings() => _settingsStore.Flush();

    public void ResetSettings()
    {
        _isInitializing = true;
        _settingsStore.Reset();
        var s = _settingsStore.State;
        ToneMode = s.Mode;
        WhisperModel = s.Model;
        Language = s.Language;
        CustomWords.Clear();
        foreach (var w in s.CustomWords) CustomWords.Add(w);
        Corrections.Clear();
        foreach (var c in s.Corrections) Corrections.Add(c);
        RemoveFillerWords = s.RemoveFillerWords;
        GameMode = s.GameMode;
        // Restore Defaults also clears the recent-transcripts history (an explicit
        // user action). Recording statistics (_statsStore) are deliberately NOT reset.
        _historyStore.Clear();
        RecentTranscripts.Clear();
        _isInitializing = false;
        _settingsStore.Flush();
        RaiseToneFlags(); RaiseLanguageFlags(); RaiseModelFlags(); RaiseGameModeFlags();
        Raise(nameof(RemoveFillerWords)); Raise(nameof(HasCustomWords)); Raise(nameof(HasCorrections)); Raise(nameof(HasRecentTranscripts)); Raise(nameof(ModelGuidance));
        _engine = MakeEngine(_whisperModel, _language, CustomWords.ToList());
        _ = _engine.PrewarmAsync();
    }

    // ---- custom words / fix-revert (ports the Swift methods 1:1) ----

    public void AddCustomWord(string word)
    {
        var trimmed = word.Trim();
        if (trimmed.Length == 0 || CustomWords.Contains(trimmed)) return;
        CustomWords.Add(trimmed);
        Raise(nameof(HasCustomWords));
        PersistSettings();
        _ = _engine.UpdateVocabularyAsync(CustomWords.ToList());
    }

    public void RemoveCustomWord(string word)
    {
        if (!CustomWords.Remove(word)) return;
        Raise(nameof(HasCustomWords));
        PersistSettings();
        _ = _engine.UpdateVocabularyAsync(CustomWords.ToList());
    }

    /// Adds a correction rule. Returns false (no-op) when either field is blank or a
    /// rule with the same heard phrase (case-insensitive) already exists.
    public bool AddCorrection(string from, string to)
    {
        var f = from.Trim();
        var t = to.Trim();
        if (f.Length == 0 || t.Length == 0) return false;
        // Dedupe on the heard phrase (case-insensitive) — same key as the merge.
        if (Corrections.Any(c => string.Equals(c.From.Trim(), f, StringComparison.OrdinalIgnoreCase))) return false;
        Corrections.Add(new CorrectionRule(f, t));
        Raise(nameof(HasCorrections));
        PersistSettings();
        // Post-processing only: no engine/vocabulary reload needed.
        return true;
    }

    public void RemoveCorrection(CorrectionRule rule)
    {
        if (!Corrections.Remove(rule)) return;
        Raise(nameof(HasCorrections));
        PersistSettings();
    }

    // ---- recent transcripts (Windows-only Recent Transcripts history) ----

    /// Record a finalized transcript at the top of the history. Trimming / blank-ignore /
    /// the 30-entry cap live in the store; here we mirror its result into the bound
    /// collection (insert at front, trim the tail) so the UI and store stay in lockstep.
    public void AddRecentTranscript(string text)
    {
        var entry = _historyStore.Add(text);
        if (entry is null) return; // blank — nothing recorded
        RecentTranscripts.Insert(0, new TranscriptRow(entry.Id, entry.Text));
        while (RecentTranscripts.Count > TranscriptHistory.MaxEntries)
            RecentTranscripts.RemoveAt(RecentTranscripts.Count - 1);
        Raise(nameof(HasRecentTranscripts));
    }

    public void RemoveRecentTranscript(Guid id)
    {
        _historyStore.Remove(id);
        for (int i = RecentTranscripts.Count - 1; i >= 0; i--)
            if (RecentTranscripts[i].Id == id) RecentTranscripts.RemoveAt(i);
        Raise(nameof(HasRecentTranscripts));
    }

    public void ClearRecentTranscripts()
    {
        _historyStore.Clear();
        RecentTranscripts.Clear();
        Raise(nameof(HasRecentTranscripts));
    }

    public void SyncEditedTranscriptFromLast() => EditedTranscript = LastTranscript;

    public void FixLastTranscript(string corrected)
    {
        var trimmed = corrected.Trim();
        if (trimmed.Length == 0) return;
        _preFixTranscript = LastTranscript;
        var newWords = TextProcessor.ExtractCorrections(LastTranscript, trimmed);
        var inserted = new List<string>();
        foreach (var w in newWords)
        {
            var t = w.Trim();
            if (t.Length == 0 || CustomWords.Contains(t)) continue;
            AddCustomWord(t);
            inserted.Add(t);
        }
        _pendingRevertWords = inserted.ToArray();
        CanRevert = inserted.Count > 0;
        _lastTranscriptStore.Transcript = trimmed;
        LastTranscript = trimmed;
        EditedTranscript = trimmed;
    }

    public void RevertLastFix()
    {
        foreach (var w in _pendingRevertWords) RemoveCustomWord(w);
        _pendingRevertWords = [];
        CanRevert = false;
        LastTranscript = _preFixTranscript;
        EditedTranscript = _preFixTranscript;
        _lastTranscriptStore.Transcript = _preFixTranscript;
        _preFixTranscript = "";
    }

    public void ClearRevertBuffer() { _pendingRevertWords = []; CanRevert = false; }

    // ---- HUD + tray mirror (updateHUD analog) ----

    private void UpdateHud(HudState state)
    {
        if (state.Kind == HudStateKind.Error)
            DiagnosticLog.Write($"HUD Error  payload=\"{state.Payload}\"\n{Environment.StackTrace}");
        else
            DiagnosticLog.Write($"HUD {state.Kind}");
        HudState = state;
        Hud?.Update(state);
        Tray?.SetActivity((TrayIcon.Activity)CoordinatorDecisions.HudToTray(state.Kind));
    }

    public void ShowError(string message)
    {
        UpdateHud(HudState.Error(message));
        ScheduleHudReset(AppTimings.HudErrorResetDelay);
    }

    private void ScheduleHudReset(TimeSpan delay)
    {
        _hudResetTimer?.Stop();
        _hudResetTimer = new DispatcherTimer { Interval = delay };
        _hudResetTimer.Tick += (_, _) => { _hudResetTimer?.Stop(); UpdateHud(HudState.Idle); };
        _hudResetTimer.Start();
    }

    // ====================== the dictation pipeline ======================

    /// Ports toggleRecording: synchronous reentrancy guards on the UI thread.
    public void ToggleRecording()
    {
        if (IsRecording)
        {
            if (_isStoppingRecording) return;
            _isStoppingRecording = true;
            try { StopRecordingAndTranscribe(); }
            finally { _isStoppingRecording = false; }
        }
        else
        {
            if (!IsRecording && _gameDetector?.ShouldSuppress == true) return;
            if (_isStartingRecording) return;
            _isStartingRecording = true;
            _transcriptionCts?.Cancel();
            _transcriptionCts = null;
            _ = StartRecordingFlowAsync().ContinueWith(
                _ => _dispatcher.InvokeAsync(() => _isStartingRecording = false),
                TaskScheduler.Default);
        }
        Tray?.RebuildMenu();
    }

    private async Task StartRecordingFlowAsync()
    {
        _hudResetTimer?.Stop();

        bool granted = await _recorder.RequestPermissionAsync();
        if (!granted)
        {
            await _dispatcher.InvokeAsync(() => PermissionError.Microphone().SurfaceAndOpenSettings());
            return;
        }

        await _dispatcher.InvokeAsync(() =>
        {
            if (!_recorder.TryStart(out var error))
            {
                ShowError(error ?? "Unable to start recording.");
                return;
            }

            IsRecording = true;
            _recordingGeneration++;
            _recordingStartUtc = DateTime.UtcNow;
            UpdateHud(HudState.Recording);

            var path = _recorder.CurrentPath;
            if (path is not null)
            {
                int generation = _recordingGeneration;
                _ = StartStreamingAsync(path, generation);
            }
        });
    }

    private async Task StartStreamingAsync(string path, int generation)
    {
        var session = await _engine.MakeStreamingSessionAsync();
        await _dispatcher.InvokeAsync(async () =>
        {
            if (!IsRecording || _recordingGeneration != generation)
            {
                if (session is not null) await session.Cancel();
                return;
            }
            _streamingSession = session;
            session?.Start(path);
        });
    }

    private void StopRecordingAndTranscribe()
    {
        if (!IsRecording) return;

        IsRecording = false;
        _lastRecordingSeconds = _recordingStartUtc is { } t ? (DateTime.UtcNow - t).TotalSeconds : 0;
        _recordingStartUtc = null;

        string? audioPath = _recorder.Stop();
        var session = _streamingSession;
        _streamingSession = null;

        DiagnosticLog.Write($"StopRecording  audioPath={(audioPath ?? "<null>")}  " +
            $"exists={(audioPath is not null && File.Exists(audioPath))}  " +
            $"bytes={(audioPath is not null && File.Exists(audioPath) ? new FileInfo(audioPath).Length : -1)}  " +
            $"recSecs={_lastRecordingSeconds:0.00}  hasStreamingSession={session is not null}");

        // The paste target is the live foreground window — unless it is one of OUR own
        // windows (HUD/Settings), decided by process ownership, not a stale HWND snapshot.
        // This is what makes "click a window, then dictate" land where the user clicked,
        // including the terminal JVoice itself was launched from.
        IntPtr current = ForegroundWindowTracker.GetForegroundWindowNow();
        bool currentIsSelf = ForegroundWindowTracker.IsOwnedByCurrentProcess(current);
        IntPtr target = CoordinatorDecisions.ResolveTargetWindow(current, currentIsSelf, _foreground.LastForegroundWindow);

        DiagnosticLog.Write($"ResolveTarget  current={current}  currentIsSelf={currentIsSelf}  " +
            $"lastNonSelf={_foreground.LastForegroundWindow}  -> target={target}");

        if (target == IntPtr.Zero)
        {
            ShowError("No target app — focus an app that accepts text before recording.");
            ScheduleHudReset(AppTimings.HudErrorResetDelay);
            if (audioPath is not null) TryDelete(audioPath);
            if (session is not null) _ = session.Cancel();
            Tray?.RebuildMenu();
            return;
        }

        UpdateHud(HudState.Transcribing);

        _transcriptionCts?.Cancel();
        _transcriptionCts = new CancellationTokenSource();
        var ct = _transcriptionCts.Token;
        _ = FinishTranscriptionAsync(audioPath, target, session, ct);
        Tray?.RebuildMenu();
    }

    private async Task FinishTranscriptionAsync(string? audioPath, IntPtr target, StreamingTranscriptionSession? session, CancellationToken ct)
    {
        if (audioPath is null)
        {
            if (session is not null) await session.Cancel();
            await _dispatcher.InvokeAsync(() => ShowError("No recording was captured."));
            return;
        }

        try
        {
            if (!NAudioRecorder.IsUsableRecording(audioPath))
            {
                if (session is not null) await session.Cancel();
                await _dispatcher.InvokeAsync(() =>
                {
                    UpdateHud(HudState.Error("Recording too short — please hold the hotkey longer."));
                    ScheduleHudReset(AppTimings.HudErrorResetDelay);
                });
                return;
            }

            if (!await _engine.IsReadyAsync())
            {
                await _dispatcher.InvokeAsync(() => UpdateHud(HudState.PreparingModel));
                await _engine.PrewarmAsync();
                if (ct.IsCancellationRequested) return;
                await _dispatcher.InvokeAsync(() => UpdateHud(HudState.Transcribing));
            }

            string transcript;
            string? streamed = session is not null ? await session.Finish() : null;
            if (streamed is not null) transcript = streamed;
            else transcript = await _engine.TranscribeAsync(audioPath, ct);

            DiagnosticLog.Write($"Transcribed  source={(streamed is not null ? "stream" : "wholefile")}  " +
                $"raw=\"{transcript}\"");

            if (ct.IsCancellationRequested) return;

            var vocab = CustomWords.ToList();
            var userDict = TextProcessor.BuildUserDictionary(vocab);
            var extraDict = UserCorrections.Merge(userDict, Corrections.ToList());
            string processed = TextProcessor.RemoveWhisperHallucinations(
                TextProcessor.Process(transcript, _toneMode, extraDict, _removeFillerWords, vocab));

            if (string.IsNullOrEmpty(processed))
            {
                await _dispatcher.InvokeAsync(() => { UpdateHud(HudState.Error("No speech detected.")); ScheduleHudReset(AppTimings.HudResetDelay); });
                return;
            }

            await _dispatcher.InvokeAsync(() => ActivateWindow(target));
            await Task.Delay(AppTimings.PasteActivationDelay, ct);
            PasteOutcome outcome = _paster.Paste(processed, target);

            switch (outcome)
            {
                case PasteOutcome.Ok:
                    break;
                case PasteOutcome.AccessDenied:
                    await _dispatcher.InvokeAsync(() => { ShowError("Can't paste into an elevated (admin) window. Run that app non-elevated, or focus a normal window."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
                case PasteOutcome.ClipboardLocked:
                    await _dispatcher.InvokeAsync(() => { ShowError("Clipboard is busy — try again."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
                case PasteOutcome.TargetRejected:
                    await _dispatcher.InvokeAsync(() => { ShowError("Unable to paste into the active app."); ScheduleHudReset(AppTimings.HudResetDelay); });
                    return;
            }

            int wordCount = processed.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
            await _dispatcher.InvokeAsync(() =>
            {
                _lastTranscriptStore.Transcript = processed;
                LastTranscript = processed;
                EditedTranscript = processed;
                AddRecentTranscript(processed);
                _statsStore.Record(wordCount, _lastRecordingSeconds);
                TotalWordsSpoken = _statsStore.TotalWords;
                AverageWpm = _statsStore.AverageWpm;
                // Silent success: the text is already in the user's app, so the HUD just
                // disappears — no "Pasted" confirmation pill (per the bars-only redesign).
                UpdateHud(HudState.Idle);
            });
        }
        catch (TranscriptionException tex)
        {
            DiagnosticLog.Write($"CATCH TranscriptionException  kind={tex.Kind}  msg=\"{tex.Message}\"");
            // A silent/empty recording is "no speech", not a failure — surface the same
            // "No speech detected." HUD the post-processing empty-result path uses (above),
            // so "I didn't say anything" never looks like an error or pastes a hallucination.
            if (tex.Kind == TranscriptionErrorKind.EmptyTranscript)
                await _dispatcher.InvokeAsync(() =>
                {
                    UpdateHud(HudState.Error("No speech detected."));
                    ScheduleHudReset(AppTimings.HudResetDelay);
                });
            else
                await _dispatcher.InvokeAsync(() => ShowError(tex.Message));
        }
        catch (OperationCanceledException)
        {
            // user moved on; do nothing.
        }
        catch (Exception ex)
        {
            DiagnosticLog.Write($"CATCH {ex.GetType().Name}  msg=\"{ex.Message}\"\n{ex}");
            await _dispatcher.InvokeAsync(() => ShowError(ex.Message));
        }
        finally
        {
            TryDelete(audioPath); // privacy: always delete the WAV
        }
    }

    private static void ActivateWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        SetForegroundWindow(hwnd);
    }

    private static void TryDelete(string path)
    {
        // Calibration mode (JVOICE_KEEP_WAV): keep a copy of each real recording for
        // no-speech threshold measurement, then still delete the temp WAV (privacy).
        if (PlatformPaths.KeepRecordings) { TryKeepForCalibration(path); return; }
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }

    /// Copy the recording into CaptureDirectory (timestamped) before deleting the temp
    /// file, so on-device clips survive for no-speech calibration. Best-effort: a failure
    /// here must never disrupt the dictation flow. Only reached when JVOICE_KEEP_WAV is set.
    private static void TryKeepForCalibration(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                string dest = Path.Combine(PlatformPaths.CaptureDirectory,
                    $"capture-{DateTime.Now:yyyyMMdd-HHmmss-fff}.wav");
                File.Copy(path, dest, overwrite: true);
                DiagnosticLog.Write($"KeptCapture  {dest}");
            }
        }
        catch { /* best-effort: never break dictation for a diagnostic capture */ }
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
    }

    /// Ports quitApp(): cancel streaming, delete in-flight WAV, idle HUD, shut down.
    public void QuitApp()
    {
        _hudResetTimer?.Stop();
        FlushSettings();

        if (IsRecording)
        {
            var session = _streamingSession;
            _streamingSession = null;
            if (session is not null) _ = session.Cancel();
            var abandoned = _recorder.Stop();
            if (abandoned is not null) TryDelete(abandoned);
            IsRecording = false;
        }

        UpdateHud(HudState.Idle);
        Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    public void Dispose()
    {
        _gameDetector?.Dispose();
        _hotkey.Dispose();
        _foreground.Dispose();
        _paster.Dispose();
        (_recorder as IDisposable)?.Dispose();
        _settingsStore.Dispose();
        Tray?.Dispose();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);
}
