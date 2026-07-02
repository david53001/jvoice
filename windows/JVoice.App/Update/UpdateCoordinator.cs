using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using JVoice.App.Platform;
using JVoice.Core.Policy;

namespace JVoice.App.Update;

public enum UpdateUiState { Idle, Checking, UpToDate, Available, Downloading, ReadyToRestart, Error }

/// The stateful brain of the in-app updater: owns the UI state machine, drives the eased download
/// bar, and (on "Update") downloads the installer, launches it, and quits so it can overwrite the
/// install. Bindable surface for the Settings "Updates" card + the tray. Windows-only (§7 #34).
///
/// The bar deliberately does NOT show the byte percentage. It targets the pure
/// <see cref="UpdateProgressCurve"/> (fast start, slow finish, capped below full) and a ~30ms timer
/// eases a shown value toward that target, so the fill glides and never jumps — the "marketing"
/// progress David asked for. Full (100%) appears only once the download is genuinely complete.
public sealed class UpdateCoordinator : INotifyPropertyChanged
{
    // How fast the shown bar chases its eased target each tick (0..1). Lower = smoother/lazier.
    private const double SmoothingLerp = 0.14;

    private readonly UpdateService _service;
    private readonly Dispatcher _dispatcher;
    private readonly Action _quitApp;
    private readonly Action? _onStateChanged; // e.g. rebuild the tray menu when availability changes

    public UpdateCoordinator(UpdateService service, Dispatcher dispatcher, Action quitApp, Action? onStateChanged = null)
    {
        _service = service;
        _dispatcher = dispatcher;
        _quitApp = quitApp;
        _onStateChanged = onStateChanged;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    // ---------- bindable state ----------

    private UpdateUiState _state = UpdateUiState.Idle;
    public UpdateUiState State
    {
        get => _state;
        private set { if (_state == value) return; _state = value; RaiseDerived(); _onStateChanged?.Invoke(); }
    }

    public string CurrentVersionDisplay => UpdateConfig.CurrentVersionDisplay;

    private string _statusText = "";
    public string StatusText
    {
        get => _statusText;
        private set { if (_statusText == value) return; _statusText = value; Raise(); Raise(nameof(HasStatus)); }
    }
    public bool HasStatus => !string.IsNullOrEmpty(_statusText);

    private string? _latestVersion;
    public string? LatestVersion { get => _latestVersion; private set { _latestVersion = value; Raise(); } }

    private double _progress;
    /// 0..1 eased fill for the download bar (NOT the true byte fraction).
    public double Progress
    {
        get => _progress;
        private set { if (Math.Abs(_progress - value) < 1e-4) return; _progress = value; Raise(); }
    }

    // Derived visibility flags the card + tray bind to.
    public bool IsChecking => State == UpdateUiState.Checking;
    public bool ShowUpdateButton => State == UpdateUiState.Available;
    public bool ShowProgress => State is UpdateUiState.Downloading or UpdateUiState.ReadyToRestart;
    public bool CanCheck => State is UpdateUiState.Idle or UpdateUiState.UpToDate or UpdateUiState.Available or UpdateUiState.Error;
    /// True when a newer version is ready to install (the tray surfaces this).
    public bool UpdateAvailable => State == UpdateUiState.Available;

    private void RaiseDerived()
    {
        Raise(nameof(State)); Raise(nameof(IsChecking)); Raise(nameof(ShowUpdateButton));
        Raise(nameof(ShowProgress)); Raise(nameof(CanCheck)); Raise(nameof(UpdateAvailable));
    }

    // ---------- download plumbing ----------

    private string? _downloadUrl;
    private string? _installerPath;
    private CancellationTokenSource? _cts;
    private DispatcherTimer? _progressTimer;
    private DispatcherTimer? _quitTimer;
    private DispatcherTimer? _autoCheckTimer;
    private long _received;          // written by the download thread (Interlocked), read by the UI timer
    private long _total = -1;        // -1 = unknown length
    private volatile bool _downloadDone;
    private DateTime _downloadStartUtc;
    private double _shown;           // the eased value currently displayed

    // ---------- automatic detection ----------

    // How often the running app re-checks GitHub for a newer release. A tray app can stay open for
    // days/weeks (it launches at login), so a once-at-launch check would miss any release published
    // while it's running. One anonymous GET per day is negligible against GitHub's 60/hr anon limit.
    public static readonly TimeSpan AutoCheckInterval = TimeSpan.FromHours(24);

    /// Turn on automatic update detection: one silent check now, then a quiet re-check every
    /// <see cref="AutoCheckInterval"/> for as long as the app runs. Every re-check reuses the same
    /// silent path as the startup check — no popups, and 404 (private repo) / offline stay quiet.
    /// Idempotent: calling it again just restarts the timer.
    public void StartAutoCheck()
    {
        _ = CheckAsync(userInitiated: false);

        _autoCheckTimer?.Stop();
        _autoCheckTimer = new DispatcherTimer { Interval = AutoCheckInterval };
        _autoCheckTimer.Tick += (_, _) =>
        {
            // Once we've already surfaced an update (or are mid-download), stop hitting the network —
            // the "Update available" state persists until the user acts on it.
            if (State is UpdateUiState.Available or UpdateUiState.Downloading or UpdateUiState.ReadyToRestart)
                return;
            _ = CheckAsync(userInitiated: false);
        };
        _autoCheckTimer.Start();
    }

    /// Stop the periodic auto-check (e.g. the user turned "Automatic Updates" off). The manual
    /// "Check Now" button still works.
    public void StopAutoCheck() => _autoCheckTimer?.Stop();

    // ---------- check ----------

    /// Query GitHub and reflect the result. `userInitiated` = the user clicked "Check for updates"
    /// (show "up to date" / errors); a startup auto-check passes false and stays silent on no-update.
    public async Task CheckAsync(bool userInitiated)
    {
        if (State is UpdateUiState.Checking or UpdateUiState.Downloading or UpdateUiState.ReadyToRestart) return;

        State = UpdateUiState.Checking;
        StatusText = "Checking for updates…";

        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        UpdateQueryResult result;
        try { result = await _service.CheckAsync(_cts.Token); }
        catch (OperationCanceledException) { return; }
        catch (Exception ex)
        {
            DiagnosticLog.Write($"Update check threw: {ex.Message}");
            result = new UpdateQueryResult(false, Error: "Couldn't check for updates.");
        }

        // WPF captures the dispatcher context across the await, so we're back on the UI thread here.
        ApplyCheckResult(result, userInitiated);
    }

    private void ApplyCheckResult(UpdateQueryResult r, bool userInitiated)
    {
        if (r.Available && r.DownloadUrl is not null)
        {
            _downloadUrl = r.DownloadUrl;
            LatestVersion = r.LatestVersion;
            StatusText = r.LatestVersion is { } v ? $"Update available — {v}" : "Update available";
            State = UpdateUiState.Available;
        }
        else if (r.Error is not null)
        {
            if (userInitiated) { StatusText = r.Error; State = UpdateUiState.Error; }
            else { StatusText = ""; State = UpdateUiState.Idle; } // auto-check failures stay silent
        }
        else
        {
            if (userInitiated) { StatusText = "You're up to date."; State = UpdateUiState.UpToDate; }
            else { StatusText = ""; State = UpdateUiState.Idle; }
        }
    }

    // ---------- download + install ----------

    /// Download the installer (eased bar), then launch it and quit so it can overwrite the install.
    public void StartDownloadAndInstall()
    {
        if (State != UpdateUiState.Available || _downloadUrl is null) return;

        State = UpdateUiState.Downloading;
        StatusText = "Downloading update…";
        Interlocked.Exchange(ref _received, 0);
        Interlocked.Exchange(ref _total, -1);
        _downloadDone = false;
        _shown = 0;
        Progress = 0;
        _downloadStartUtc = DateTime.UtcNow;

        string dest = Path.Combine(Path.GetTempPath(), "JVoice-Update", InstallerFileName(_downloadUrl));
        StartProgressTimer();

        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        string url = _downloadUrl;
        _ = Task.Run(async () =>
        {
            try
            {
                await _service.DownloadAsync(url, dest, (recv, total) =>
                {
                    Interlocked.Exchange(ref _received, recv);
                    Interlocked.Exchange(ref _total, total ?? -1);
                }, ct);
                _dispatcher.InvokeAsync(() => OnDownloadComplete(dest));
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                DiagnosticLog.Write($"Update download failed: {ex.Message}");
                _dispatcher.InvokeAsync(OnDownloadError);
            }
        });
    }

    private void StartProgressTimer()
    {
        _progressTimer?.Stop();
        _progressTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
        _progressTimer.Tick += (_, _) =>
        {
            long recv = Interlocked.Read(ref _received);
            long tot = Interlocked.Read(ref _total);
            double elapsed = (DateTime.UtcNow - _downloadStartUtc).TotalSeconds;
            double target = UpdateProgressCurve.Display(recv, tot < 0 ? null : tot, elapsed, _downloadDone);

            // Chase the target from below only (monotonic — the bar never rewinds).
            if (target > _shown) _shown += (target - _shown) * SmoothingLerp;
            Progress = _shown;

            if (_downloadDone && _shown >= 0.999)
            {
                _shown = 1.0;
                Progress = 1.0;
                _progressTimer?.Stop();
                FinishInstall();
            }
        };
        _progressTimer.Start();
    }

    private void OnDownloadComplete(string dest)
    {
        _installerPath = dest;
        _downloadDone = true; // the timer eases the bar to full, then calls FinishInstall
        StatusText = "Finishing update…";
    }

    private void OnDownloadError()
    {
        _progressTimer?.Stop();
        StatusText = "Update download failed — please try again.";
        State = UpdateUiState.Error;
    }

    private void FinishInstall()
    {
        if (_installerPath is null) { OnDownloadError(); return; }
        State = UpdateUiState.ReadyToRestart;
        StatusText = "Restarting to finish update…";
        try
        {
            _service.LaunchInstaller(_installerPath);
            // Give the installer a beat to spawn/unpack, then quit so JVoice's files unlock and the
            // installer can overwrite them (it relaunches JVoice when it finishes).
            _quitTimer?.Stop();
            _quitTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
            _quitTimer.Tick += (_, _) => { _quitTimer?.Stop(); _quitApp(); };
            _quitTimer.Start();
        }
        catch (Exception ex)
        {
            DiagnosticLog.Write($"LaunchInstaller failed: {ex.Message}");
            OnDownloadError();
        }
    }

    private static string InstallerFileName(string url)
    {
        try
        {
            string name = Path.GetFileName(new Uri(url).AbsolutePath);
            if (!string.IsNullOrWhiteSpace(name) && name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                return name;
        }
        catch { /* fall through to the default name */ }
        return "JVoice-Setup.exe";
    }

    // ---------- preview (screenshots) ----------

    /// Force a representative state for `--update-preview` / `--settings-render <state>` without any
    /// network or download I/O, so each visual can be screenshotted headlessly.
    public void EnterPreviewState(string name)
    {
        switch (name.ToLowerInvariant())
        {
            case "checking":
                StatusText = "Checking for updates…"; State = UpdateUiState.Checking; break;
            case "available":
                LatestVersion = "1.3.0"; _downloadUrl = "https://example.com/JVoice-Setup.exe";
                StatusText = "Update available — v1.3.0"; State = UpdateUiState.Available; break;
            case "downloading":
                StatusText = "Downloading update…"; State = UpdateUiState.Downloading; Progress = 0.62; break;
            case "uptodate":
                StatusText = "You're up to date."; State = UpdateUiState.UpToDate; break;
            case "error":
                StatusText = "Couldn't reach the update server."; State = UpdateUiState.Error; break;
        }
    }
}
