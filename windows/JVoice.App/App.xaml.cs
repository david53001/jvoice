using JVoice.Core;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using JVoice.App.Platform;
using JVoice.App.Tours;
using JVoice.App.UI;
using JVoice.App.Whisper;
using JVoice.Core.Models;
using JVoice.Core.Tours;

namespace JVoice.App;

public partial class App : Application
{
    private VoiceCoordinator? _coordinator;
    private TrayIcon? _tray;
    private HudWindow? _hud;

    /// tours.json, read (and the audience classified) in Main before anything writes a setting.
    private static TourPrefs? s_tourPrefs;

    /// JVoice's stable Application User Model ID (matches the macOS bundle id).
    /// Windows uses it to group taskbar buttons and route toast notifications.
    private const string AppUserModelId = "com.jvoice.app";

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string AppID);

    /// Explicit entry so the --bench CLI branch runs BEFORE any WPF startup
    /// (mirrors the macOS app calling BenchRunner.shouldRun before showing UI).
    [STAThread]
    public static int Main(string[] args)
    {
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        if (Diagnostics.UiPreviewRunner.ShouldRun(args))
            return Diagnostics.UiPreviewRunner.RunAndExit(args);

        if (MathProbeRunner.ShouldRun(args))
            return MathProbeRunner.RunAndExit(args);

        if (GameProbeRunner.ShouldRun(args))
            return GameProbeRunner.RunAndExit(args);

        if (JVoice.App.Update.UpdateProbeRunner.ShouldRun(args))
            return JVoice.App.Update.UpdateProbeRunner.RunAndExit(args);

        // Hidden dev aids for inspecting/screenshotting the real rendering, both bypassing
        // the single-instance lock so they can run alongside a normal instance:
        //   `--hud-preview [state]`  — shows ONLY the HUD pill (no tray/mic/whisper).
        //   `--hud-render [path]`    — renders the HUD pill off-screen to a PNG (headless/CI).
        //   `--settings-preview`     — shows ONLY the Settings window (coordinator, no prewarm).
        bool preview = Array.Exists(args,
            a => string.Equals(a, "--hud-preview", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--settings-preview", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--settings-render", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--update-preview", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--welcome-render", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--tour-render", StringComparison.OrdinalIgnoreCase)
              || Diagnostics.LatencyProbe.ShouldRun(args));

        // A logon launch (the Run-key entry carries --autostart) steps aside when the elevated
        // auto-start task is configured: that task launches an ELEVATED copy — the one that can
        // receive the hotkey in admin windows (UIPI). Without this, a non-elevated Run-key copy
        // could win the single-instance slot at logon and silently break the hotkey in elevated
        // apps. A manual double-click (no --autostart) never steps aside.
        bool isAutostart = Array.Exists(args,
            a => string.Equals(a, Elevation.AutostartFlag, StringComparison.OrdinalIgnoreCase));
        if (!preview && isAutostart && !Elevation.IsElevated && ElevatedAutostart.IsEnabled)
            return 0;

        if (!preview)
        {
            // An elevated relaunch must wait for the outgoing instance to release the mutex
            // (handoff); a normal launch keeps the original single-shot "already running → exit".
            int acquireTimeoutMs = Elevation.IsRelaunch(args) ? 5000 : 0;
            if (!SingleInstance.TryAcquire(acquireTimeoutMs))
                return 0;
        }

        if (!preview)
        {
            // Tours (parity §10.1): decide new vs existing ONCE, before anything writes to %APPDATA%\JVoice —
            // SettingsStore writes settings.json on construction and DiagnosticLog appends there, so classifying
            // any later would call every fresh install "existing". Read-only probes; only tours.json is written.
            var prefs = TourStore.Load();
            bool launchedByJVoice = Elevation.IsRelaunch(args) || args.Contains(Elevation.AutostartFlag, StringComparer.OrdinalIgnoreCase);
            var audience = TourCoordinator.ClassifyAudienceIfNeeded(prefs,
                () => TourStore.GatherSignals() with { LaunchedByJVoice = launchedByJVoice }, () => TourStore.Save(prefs));
            s_tourPrefs = prefs;
            DiagnosticLog.Write($"Tours: audience={TourAudience.Store(audience)}");
        }

        if (!preview)
            try { WhisperRuntime.EnsureLoaded(); } catch { /* lazy retry in engine */ }

        var app = new App();
        app.InitializeComponent();
        int code = app.Run();
        if (!preview) SingleInstance.Release();
        return code;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // Group taskbar/toasts under "com.jvoice.app" before any window appears.
        try { SetCurrentProcessExplicitAppUserModelID(AppUserModelId); } catch { /* non-fatal */ }

        base.OnStartup(e);

        // Hidden dev aids (see Main): show just one surface and stop.
        if (Array.Exists(e.Args, a => string.Equals(a, "--hud-preview", StringComparison.OrdinalIgnoreCase)))
        {
            ShowHudPreview(e.Args);
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--settings-preview", StringComparison.OrdinalIgnoreCase)))
        {
            // A coordinator is the DataContext, but we never call Start() → no prewarm,
            // no hotkey, no mic — just the styled Settings window for visual inspection.
            var previewCoordinator = new VoiceCoordinator();
            var previewSettings = new SettingsWindow(previewCoordinator);
            previewSettings.ShowOrActivate();
            previewSettings.Topmost = true; // keep it above other windows for inspection
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--settings-render", StringComparison.OrdinalIgnoreCase)))
        {
            RenderSettingsToFile(e.Args);
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--update-preview", StringComparison.OrdinalIgnoreCase)))
        {
            // Show ONLY the Settings window with the Updates card forced into a given state (no tray,
            // no network): `--update-preview [available|downloading|checking|uptodate|error]`.
            var idx = Array.FindIndex(e.Args, a => string.Equals(a, "--update-preview", StringComparison.OrdinalIgnoreCase));
            var state = (idx >= 0 && idx + 1 < e.Args.Length) ? e.Args[idx + 1] : "available";
            var previewCoordinator = new VoiceCoordinator();
            previewCoordinator.Updates.EnterPreviewState(state);
            var previewSettings = new SettingsWindow(previewCoordinator);
            previewSettings.ShowOrActivate();
            previewSettings.Topmost = true;
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--welcome-render", StringComparison.OrdinalIgnoreCase)))
        {
            try { TourRenders.Welcome(e.Args, new VoiceCoordinator()); }
            catch (Exception ex) { File.WriteAllText(Path.Combine(Path.GetTempPath(), "jvoice-render-error.txt"), ex.ToString()); }
            Shutdown();
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--tour-render", StringComparison.OrdinalIgnoreCase)))
        {
            try { TourRenders.Tags(e.Args); }
            catch (Exception ex) { File.WriteAllText(Path.Combine(Path.GetTempPath(), "jvoice-render-error.txt"), ex.ToString()); }
            Shutdown();
            return;
        }
        if (Array.Exists(e.Args, a => string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase)))
        {
            RenderHudToFile(e.Args);
            return;
        }
        if (Diagnostics.LatencyProbe.ShouldRun(e.Args))
        {
            // Measures the hotkey→HUD→mic→stop path + decode-time UI stalls on this machine
            // (off-screen HUD, seconds-short mic use, clipboard read-only). See LatencyProbe.
            Diagnostics.LatencyProbe.Run(this, e.Args);
            return;
        }

        // 1) Coordinator (must be created on the UI thread — captures the dispatcher).
        _coordinator = new VoiceCoordinator();
        // The native look: stored System/Light/Dark + Opacity, before any window exists (row 28/30).
        Theme.Initialize(_coordinator.Appearance, _coordinator.UiOpacity);

        // 2) HUD overlay window. The live mic level is still wired up below but is currently
        //    UNUSED: the recording bars are a continuous, mic-independent wave (David preferred a
        //    steady flow; mic-reactive bars stuttered on his words — see HudView.InputLevelProvider).
        //    Kept so a mic-reactive mode can be re-enabled without re-threading the callback.
        _hud = new HudWindow { OnStop = () => _coordinator.ToggleRecording() };
        _hud.InputLevelProvider = () => _coordinator.CurrentInputLevel;
        _coordinator.Hud = _hud;

        // 3) Tray icon + menu wiring.
        _tray = new TrayIcon
        {
            IsRecording = () => _coordinator.IsRecording,
            UpdateAvailable = () => _coordinator.Updates.UpdateAvailable,
            LaunchAtLoginEnabled = () => _coordinator.LaunchAtLoginEnabled,
            IsElevated = () => _coordinator.IsElevated,
            RunAsAdminAtLoginEnabled = () => _coordinator.RunAsAdminAtLoginEnabled,
            OnToggleDictation = () => _coordinator.ToggleRecording(),
            OnOpenSettings = () => _coordinator.ShowSettings(),
            OnToggleLaunchAtLogin = () => _coordinator.ToggleLaunchAtLogin(),
            OnRestartAsAdministrator = () => _coordinator.RestartAsAdministrator(),
            OnToggleRunAsAdminAtLogin = () => _coordinator.ToggleRunAsAdminAtLogin(),
            OnQuit = () => _coordinator.QuitApp(),
            OnTour = id => TourEvents.Replay(id, null),
            OnResetTours = TourEvents.ResetAll,
        };
        _coordinator.Tray = _tray;
        _tray.RebuildMenu();

        // 4) Start the pipeline (sweep orphans, hooks, hotkey, prewarm).
        _coordinator.Start();
        _coordinator.BootstrapLaunchAtLogin();

        // 4b) If we were relaunched elevated specifically to register/unregister the elevated
        //     logon task, apply that now (we are guaranteed elevated on this path).
        _coordinator.ApplyElevationStartupIntent(e.Args);

        // 5) Guided tours (parity rows 31/32): a NEW user who hasn't answered gets the Welcome window ("Want a quick
        //    tour?"); an existing user (every upgrade, David's PC) never sees it. Replaces the old first-run
        //    Settings + MessageBox.
        var tours = new TourService(_coordinator, s_tourPrefs ?? TourStore.Load(), _tray);
        _coordinator.TourService = tours;
        tours.ShowWelcomeIfNeeded();
    }

    /// Show a single static HUD pill for visual inspection (`--hud-preview [state]`).
    private void ShowHudPreview(string[] args)
    {
        var idx = Array.FindIndex(args,
            a => string.Equals(a, "--hud-preview", StringComparison.OrdinalIgnoreCase));
        var name = (idx >= 0 && idx + 1 < args.Length) ? args[idx + 1].ToLowerInvariant() : "recording";
        var state = name switch
        {
            "transcribing" => HudState.Transcribing,
            "preparing"    => HudState.PreparingModel,
            "downloading"  => HudState.DownloadingModel(0.42),
            "error"        => HudState.Error("Something went wrong"),
            _              => HudState.Recording,
        };
        _hud = new HudWindow { OnStop = () => { } };
        // No coordinator/mic in preview, so feed the recording bars a steady synthetic level
        // (the per-bar wobble still varies them) — otherwise they'd just idle at the floor.
        if (state.Kind == HudStateKind.Recording)
            _hud.InputLevelProvider = () => 0.32f;
        _hud.Update(state);
    }

    /// Render the Settings view off-screen to a PNG (`--settings-render [path]`) so its
    /// real styling can be inspected headlessly — immune to whatever (e.g. a fullscreen
    /// game) is covering the desktop, and usable from CI. Renders the visible viewport at 2×.
    private void RenderSettingsToFile(string[] args)
    {
        var idx = Array.FindIndex(args,
            a => string.Equals(a, "--settings-render", StringComparison.OrdinalIgnoreCase));

        // Args after the flag: an optional output path and an optional Updates-card state token
        // (so `--settings-render out.png available` screenshots the card mid-update). Tell them
        // apart by the known state names rather than position.
        var known = new[] { "checking", "available", "downloading", "uptodate", "error", "light", "dark" };
        var rest = idx >= 0 ? args.Skip(idx + 1).ToArray() : Array.Empty<string>();
        string? updateState = rest.FirstOrDefault(a => known.Contains(a.ToLowerInvariant()));
        string? pathArg = rest.FirstOrDefault(a => !known.Contains(a.ToLowerInvariant()));
        var path = pathArg ?? Path.Combine(Path.GetTempPath(), "jvoice-settings.png");

        var coordinator = new VoiceCoordinator();
        if (updateState is not null) coordinator.Updates.EnterPreviewState(updateState);
        // `light` / `dark` force an appearance for the shot (default: the stored one); Mica can't be
        // captured off-screen, so the panel is rendered over the solid window colour.
        var forced = rest.Any(a => a.Equals("light", StringComparison.OrdinalIgnoreCase)) ? AppAppearance.Light
            : rest.Any(a => a.Equals("dark", StringComparison.OrdinalIgnoreCase)) ? AppAppearance.Dark
            : coordinator.Appearance;
        Theme.Initialize(forced, coordinator.UiOpacity);
        var view = new SettingsView { DataContext = coordinator };
        view.SetResourceReference(System.Windows.Controls.Control.BackgroundProperty, "Window.Solid");

        const double scale = 2.0;
        // The view declares a fixed Width but sizes its Height to content (SettingsView.xaml has
        // no Height — the live SizeToContent window does the same). Measure at that width with
        // unbounded height to get the natural size, then render exactly that, so this harness
        // tracks the panel's real on-screen size and never goes stale when the panel is resized.
        //
        // Two full layout passes are REQUIRED: the panel's outer ScrollViewer settles its
        // Auto scrollbar / content extent only after a Measure→Arrange→UpdateLayout cycle, so
        // DesiredSize.Height read straight after the first Measure is under-reported (it would
        // clip the tallest column). Re-measure after the first cycle to get the settled height.
        view.Measure(new Size(view.Width, double.PositiveInfinity));
        view.Arrange(new Rect(view.DesiredSize));
        view.UpdateLayout();
        view.Measure(new Size(view.Width, double.PositiveInfinity));
        var size = new Size(view.Width, view.DesiredSize.Height);
        view.Arrange(new Rect(size));
        view.UpdateLayout();

        var rtb = new RenderTargetBitmap(
            (int)(size.Width * scale), (int)(size.Height * scale),
            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        rtb.Render(view);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using (var fs = File.Create(path)) encoder.Save(fs);

        Shutdown();
    }

    /// Render the HUD pill off-screen to a PNG (`--hud-render [path] [state]`) so its real shape
    /// and proportions can be inspected headlessly (the live `--hud-preview` can't be captured, and
    /// a fullscreen game can cover the on-screen overlay). Default poses the bars in a representative
    /// static frame; pass `error` to capture the error pill (the only text-bearing state) so its
    /// glyph crispness can be judged. The per-frame animation loop never runs in this path.
    private void RenderHudToFile(string[] args)
    {
        var idx = Array.FindIndex(args,
            a => string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase));

        // Args after the flag: an optional output path and an optional state token, told apart by
        // the known state names (mirrors --settings-render's path/state disambiguation).
        var known = new[] { "recording", "transcribing", "preparing", "downloading", "error", "copied", "unpasted", "done" };
        var rest = idx >= 0 ? args.Skip(idx + 1).ToArray() : Array.Empty<string>();
        string? stateArg = rest.FirstOrDefault(a => known.Contains(a.ToLowerInvariant()));
        string? pathArg = rest.FirstOrDefault(a => !known.Contains(a.ToLowerInvariant()));
        var path = pathArg ?? Path.Combine(Path.GetTempPath(), "jvoice-hud.png");

        var view = new HudView();
        if (string.Equals(stateArg, "error", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.Error("No speech detected."));  // static error pose (no loop)
        else if (string.Equals(stateArg, "copied", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.Copied("x"));
        else if (string.Equals(stateArg, "done", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.Done("x"));
        else if (string.Equals(stateArg, "transcribing", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.Transcribing);
        else if (string.Equals(stateArg, "preparing", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.PreparingModel);
        else if (string.Equals(stateArg, "downloading", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.DownloadingModel(0.42));
        else if (string.Equals(stateArg, "unpasted", StringComparison.OrdinalIgnoreCase))
            view.Apply(HudState.Error(CoordinatorDecisions.UnpastedMessage(PasteFailure.TargetRejected)));
        else
            view.PrepareStaticCapture();

        // Let the pill size itself to content (SizeToContent in the real window).
        view.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var desired = view.DesiredSize;
        view.Arrange(new Rect(desired));
        view.UpdateLayout();

        const double scale = 3.0; // crisp enough to judge edges/corners at native + HudScale
        var rtb = new RenderTargetBitmap(
            (int)Math.Ceiling(desired.Width * scale), (int)Math.Ceiling(desired.Height * scale),
            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        rtb.Render(view);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using (var fs = File.Create(path)) encoder.Save(fs);

        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _coordinator?.FlushSettings();
        _tray?.Dispose();
        base.OnExit(e);
    }
}
