namespace JVoice.App;

/// Temporary entry point for Phase 2 so the engine + --bench are runnable before
/// the WPF UI exists. Phase 4 replaces this with the WPF App.xaml [STAThread] Main,
/// which MUST keep the `BenchRunner.ShouldRun(args)` branch (run bench, then exit)
/// BEFORE constructing/showing any UI — mirroring the macOS app's startup order.
///
/// NOTE: the `BenchRunner` branch is wired in by Task 5 (once BenchRunner.cs exists);
/// until then this is a runnable no-op so Tasks 1–4 each build green.
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // No UI yet (Phase 4) and no bench wiring yet (Task 5). For now, a runnable
        // no-op so the WinExe launches and exits cleanly.
        Console.Error.WriteLine("JVoice (Windows) — UI not built yet (Phase 4). Use --bench <audio.wav>.");
        return 0;
    }
}
