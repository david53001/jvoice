using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;

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

        if (!SingleInstance.TryAcquire())
            return 0;

        try { WhisperRuntime.EnsureLoaded(); } catch { /* lazy retry in engine */ }

        var app = new App();
        app.InitializeComponent();
        int code = app.Run();
        SingleInstance.Release();
        return code;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // Group taskbar/toasts under "com.jvoice.app" before any window appears.
        try { SetCurrentProcessExplicitAppUserModelID(AppUserModelId); } catch { /* non-fatal */ }

        base.OnStartup(e);

        // 1) Coordinator (must be created on the UI thread — captures the dispatcher).
        _coordinator = new VoiceCoordinator();

        // 2) HUD overlay window.
        _hud = new HudWindow { OnStop = () => _coordinator.ToggleRecording() };
        _coordinator.Hud = _hud;

        // 3) Tray icon + menu wiring.
        _tray = new TrayIcon
        {
            IsRecording = () => _coordinator.IsRecording,
            LaunchAtLoginEnabled = () => _coordinator.LaunchAtLoginEnabled,
            OnToggleDictation = () => _coordinator.ToggleRecording(),
            OnOpenSettings = () => _coordinator.ShowSettings(),
            OnToggleLaunchAtLogin = () => _coordinator.ToggleLaunchAtLogin(),
            OnQuit = () => _coordinator.QuitApp(),
        };
        _coordinator.Tray = _tray;
        _tray.RebuildMenu();

        // 4) Start the pipeline (sweep orphans, hooks, hotkey, prewarm).
        _coordinator.Start();
        _coordinator.BootstrapLaunchAtLogin();

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
