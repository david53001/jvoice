using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;
using JVoice.Core.Models;

namespace JVoice.App;

public partial class App : Application
{
    private VoiceCoordinator? _coordinator;
    private TrayIcon? _tray;
    private HudWindow? _hud;

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

        // Hidden dev aids for inspecting/screenshotting the real rendering, both bypassing
        // the single-instance lock so they can run alongside a normal instance:
        //   `--hud-preview [state]`  — shows ONLY the HUD pill (no tray/mic/whisper).
        //   `--hud-render [path]`    — renders the HUD pill off-screen to a PNG (headless/CI).
        //   `--settings-preview`     — shows ONLY the Settings window (coordinator, no prewarm).
        bool preview = Array.Exists(args,
            a => string.Equals(a, "--hud-preview", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--settings-preview", StringComparison.OrdinalIgnoreCase)
              || string.Equals(a, "--settings-render", StringComparison.OrdinalIgnoreCase));

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
        if (Array.Exists(e.Args, a => string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase)))
        {
            RenderHudToFile(e.Args);
            return;
        }

        // 1) Coordinator (must be created on the UI thread — captures the dispatcher).
        _coordinator = new VoiceCoordinator();

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
            LaunchAtLoginEnabled = () => _coordinator.LaunchAtLoginEnabled,
            IsElevated = () => _coordinator.IsElevated,
            RunAsAdminAtLoginEnabled = () => _coordinator.RunAsAdminAtLoginEnabled,
            OnToggleDictation = () => _coordinator.ToggleRecording(),
            OnOpenSettings = () => _coordinator.ShowSettings(),
            OnToggleLaunchAtLogin = () => _coordinator.ToggleLaunchAtLogin(),
            OnRestartAsAdministrator = () => _coordinator.RestartAsAdministrator(),
            OnToggleRunAsAdminAtLogin = () => _coordinator.ToggleRunAsAdminAtLogin(),
            OnQuit = () => _coordinator.QuitApp(),
        };
        _coordinator.Tray = _tray;
        _tray.RebuildMenu();

        // 4) Start the pipeline (sweep orphans, hooks, hotkey, prewarm).
        _coordinator.Start();
        _coordinator.BootstrapLaunchAtLogin();

        // 4b) If we were relaunched elevated specifically to register/unregister the elevated
        //     logon task, apply that now (we are guaranteed elevated on this path).
        _coordinator.ApplyElevationStartupIntent(e.Args);

        // 5) First-run: show Settings once so the app isn't invisible.
        if (IsFirstRun())
        {
            _coordinator.ShowSettings();
            MarkFirstRunDone();
            MessageBox.Show(
                "JVoice is running in your system tray — press Ctrl + Shift + Space to dictate.",
                "JVoice", MessageBoxButton.OK, MessageBoxImage.Information);
        }
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
        var path = (idx >= 0 && idx + 1 < args.Length)
            ? args[idx + 1]
            : Path.Combine(Path.GetTempPath(), "jvoice-settings.png");

        var coordinator = new VoiceCoordinator();
        var view = new SettingsView { DataContext = coordinator };

        const double scale = 2.0;
        var size = new Size(320, 520); // SettingsView's declared size (one screenful)
        view.Measure(size);
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

    /// Render the HUD pill off-screen to a PNG (`--hud-render [path]`) so its real shape and
    /// proportions can be inspected headlessly (the live `--hud-preview` can't be captured, and
    /// a fullscreen game can cover the on-screen overlay). The bars are posed in a representative
    /// static frame (the per-frame animation loop never runs in this path).
    private void RenderHudToFile(string[] args)
    {
        var idx = Array.FindIndex(args,
            a => string.Equals(a, "--hud-render", StringComparison.OrdinalIgnoreCase));
        var path = (idx >= 0 && idx + 1 < args.Length)
            ? args[idx + 1]
            : Path.Combine(Path.GetTempPath(), "jvoice-hud.png");

        var view = new HudView();
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

    // First-run flag in HKCU\Software\JVoice\UiFirstRunShown (separate from the
    // launch-at-login init flag so the two concerns don't entangle).
    private static bool IsFirstRun()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\JVoice");
        return key?.GetValue("UiFirstRunShown") is null;
    }

    private static void MarkFirstRunDone()
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\JVoice");
        key.SetValue("UiFirstRunShown", 1, RegistryValueKind.DWord);
    }
}
