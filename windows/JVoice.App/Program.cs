using JVoice.App.Whisper;

namespace JVoice.App;

/// Temporary entry point for Phase 2 so the engine + --bench are runnable before
/// the WPF UI exists. Phase 4 replaces this with the WPF App.xaml [STAThread] Main,
/// which MUST keep the `BenchRunner.ShouldRun(args)` branch (run bench, then exit)
/// BEFORE constructing/showing any UI — mirroring the macOS app's startup order.
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (BenchRunner.ShouldRun(args))
            return BenchRunner.RunAndExit(args);

        // No UI yet (Phase 4). For now, a runnable no-op so the WinExe launches and exits cleanly.
        Console.Error.WriteLine("JVoice (Windows) — UI not built yet (Phase 4). Use --bench <audio.wav>.");
        return 0;
    }
}
