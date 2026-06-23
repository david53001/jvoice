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
    private readonly IAudioRecorder _recorder = new NAudioRecorder();
    private readonly Paster _paster = new();
    private readonly ForegroundWindowTracker _foreground = new();
    private readonly GlobalHotkey _hotkey = new();
    private readonly WhisperModelStore _modelStore = new();

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
    private IntPtr _selfHwnd;
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
        _removeFillerWords = s.RemoveFillerWords;
        _hotkeyChord = HotkeyChord.Default;
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

    // ---- derived flags for the segmented pickers + visibility binders ----
    public bool HasTranscript => !string.IsNullOrEmpty(LastTranscript);
    public bool HasCustomWords => CustomWords.Count > 0;
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

    // ====================== lifecycle / wiring ======================

    /// Ports VoiceCoordinator.start(): sweep orphans, install hooks, hotkey, prewarm.
    public void Start()
    {
        NAudioRecorder.SweepOrphanedRecordings();

        _selfHwnd = ForegroundWindowTracker.GetForegroundWindowNow();
        _foreground.Start();

        SystemActions.ErrorHandler = msg => _dispatcher.InvokeAsync(() => ShowError(msg));
        _settingsStore.Changed += _ => _dispatcher.InvokeAsync(() => { /* UI binds live props */ });
        _recorder.Failed += msg => _dispatcher.InvokeAsync(() => ShowError(msg));
        _hotkey.Triggered += () => _dispatcher.InvokeAsync(ToggleRecording);
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
        RemoveFillerWords = s.RemoveFillerWords;
        _isInitializing = false;
        _settingsStore.Flush();
        RaiseToneFlags(); RaiseLanguageFlags(); RaiseModelFlags();
        Raise(nameof(RemoveFillerWords)); Raise(nameof(HasCustomWords)); Raise(nameof(ModelGuidance));
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

        IntPtr current = ForegroundWindowTracker.GetForegroundWindowNow();
        IntPtr target = CoordinatorDecisions.ResolveTargetWindow(current, _selfHwnd, _foreground.LastForegroundWindow);

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

            if (ct.IsCancellationRequested) return;

            var vocab = CustomWords.ToList();
            var userDict = TextProcessor.BuildUserDictionary(vocab);
            string processed = TextProcessor.RemoveWhisperHallucinations(
                TextProcessor.Process(transcript, _toneMode, userDict, _removeFillerWords, vocab));

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
                _statsStore.Record(wordCount, _lastRecordingSeconds);
                TotalWordsSpoken = _statsStore.TotalWords;
                AverageWpm = _statsStore.AverageWpm;
                UpdateHud(HudState.Done(processed));
                ScheduleHudReset(AppTimings.HudResetDelay);
            });
        }
        catch (TranscriptionException tex)
        {
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
