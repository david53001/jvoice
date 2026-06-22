using System.Windows;
using JVoice.App.Platform;
using JVoice.App.Whisper;

namespace JVoice.App;

public partial class App : Application
{
    /// Explicit entry so the --bench CLI branch runs BEFORE any WPF startup
    /// (mirrors the macOS app calling BenchRunner.shouldRun before showing UI).
    [STAThread]
    public static int Main(string[] args)
    {
        // 1) Headless bench path — never shows UI.
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        // 2) Single instance: if another JVoice is already running, exit quietly.
        if (!SingleInstance.TryAcquire())
            return 0;

        // 3) Force the native whisper runtime to resolve early (CUDA→Vulkan→CPU)
        //    so first dictation isn't delayed by the native load.
        try { WhisperRuntime.EnsureLoaded(); } catch { /* engine load is retried lazily */ }

        var app = new App();
        app.InitializeComponent();   // loads App.xaml + merged dictionaries
        int code = app.Run();
        SingleInstance.Release();
        return code;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Coordinator + tray + first-run wiring is added in Task 9 (final wiring).
        // OnExplicitShutdown means the app stays alive with no window until then.
    }
}
