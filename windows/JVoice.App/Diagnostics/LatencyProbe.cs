using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.App.Whisper;
using JVoice.Core.Models;

namespace JVoice.App.Diagnostics;

/// Hidden dev aid: `JVoice.exe --latency-probe [--wav <clip.wav>] [--threads 6,4,2] [--out <log>]`.
///
/// Measures, ON THIS MACHINE, every stage of the hotkey → HUD → record → stop → paste path that
/// the diagnostic log cannot see (the log's first line is written only after the microphone is
/// already running), plus how badly a whisper decode stalls the UI thread. Headless-friendly:
/// the HUD is realized OFF-SCREEN (HudWindow.Offscreen), the microphone is opened for ~0.3 s
/// per cycle and the WAV deleted at once, the clipboard is read but never written, and no
/// hotkey is registered — so it can run beside the tray instance without any visible side
/// effect. Results go to %TEMP%\jvoice-latency-probe.log (and stdout when piped).
internal static class LatencyProbe
{
    public static bool ShouldRun(string[] args)
        => Array.Exists(args, a => string.Equals(a, "--latency-probe", StringComparison.OrdinalIgnoreCase));

    private static readonly StringBuilder Report = new();
    private static string _outPath = Path.Combine(Path.GetTempPath(), "jvoice-latency-probe.log");

    private static void Line(string s)
    {
        Report.AppendLine(s);
        try { Console.WriteLine(s); } catch { }
        try { File.AppendAllText(_outPath, s + Environment.NewLine); } catch { }
    }

    public static async void Run(Application app, string[] args)
    {
        string? outArg = ArgValue(args, "--out");
        if (outArg is not null) _outPath = outArg;
        try { File.Delete(_outPath); } catch { }
        int exit = 0;
        try
        {
            await RunAsync(args);
        }
        catch (Exception ex)
        {
            Line($"PROBE FAILED: {ex}");
            exit = 1;
        }
        app.Shutdown(exit);
    }

    private static async Task RunAsync(string[] args)
    {
        Line($"latency-probe  {DateTime.Now:yyyy-MM-dd HH:mm:ss}  pid={Environment.ProcessId}  " +
             $"cores={Environment.ProcessorCount}  physical={CpuInfo.PhysicalCoreCount}");

        // Optional synthetic CPU load (N Normal-priority spinning threads in THIS process — thread
        // base priorities make that equivalent to other Normal-class processes hogging the CPU)
        // and an optional UI-thread priority boost, to measure the hotkey hop + HUD show when
        // "a lot is running".
        int load = int.TryParse(ArgValue(args, "--load"), out var l) ? l : 0;
        var spinners = new List<Thread>();
        bool stopLoad = false;
        for (int i = 0; i < load; i++)
        {
            var t = new Thread(() => { while (!Volatile.Read(ref stopLoad)) { } }) { IsBackground = true, Priority = ThreadPriority.Normal, Name = "probe-load" };
            t.Start(); spinners.Add(t);
        }
        string? prio = ArgValue(args, "--ui-priority");
        if (prio is not null && Enum.TryParse<ThreadPriority>(prio, true, out var tp))
            Thread.CurrentThread.Priority = tp;
        Line($"load threads={load}  ui-thread priority={Thread.CurrentThread.Priority}");
        if (load > 0) await Task.Delay(300); // let the load settle before measuring

        // ---------------------------------------------------------------- 1. HUD show latency
        var hud = new HudWindow { Offscreen = true };
        Line("");
        Line("== HUD (off-screen) ==");
        if (Array.Exists(args, a => a == "--prewarm-hud"))
        {
            var swPre = Stopwatch.StartNew();
            hud.Prewarm();
            Line($"Prewarm(): {swPre.Elapsed.TotalMilliseconds:0.0} ms (call) — waiting 300 ms for its frame");
            await Task.Delay(300);
        }
        for (int i = 1; i <= 3; i++)
        {
            var sw = Stopwatch.StartNew();
            hud.Update(HudState.Recording);
            double callMs = sw.Elapsed.TotalMilliseconds;
            double firstFrameMs = await WaitFirstRenderAsync(sw);
            Line($"show #{i} (Recording): Update() call={callMs:0.0} ms  first rendered frame={firstFrameMs:0.0} ms");
            await Task.Delay(150);
            sw.Restart();
            hud.Update(HudState.Transcribing);
            Line($"  -> Transcribing switch: {sw.Elapsed.TotalMilliseconds:0.0} ms");
            await Task.Delay(150);
            sw.Restart();
            hud.Update(HudState.Idle);
            Line($"  -> Hide: {sw.Elapsed.TotalMilliseconds:0.0} ms");
            await Task.Delay(200);
        }

        // Render-loop cost: how many CompositionTarget.Rendering ticks per second does the
        // animated pill drive, and how much UI-thread time does each frame eat?
        Line("");
        Line("== HUD animation load (2 s each) ==");
        var idleGap = await MeasureDispatcherAsync(TimeSpan.FromSeconds(2));
        Line($"hidden:       render ticks/s={idleGap.RenderHz:0}  process CPU={idleGap.CpuPercent:0.0}% of one core  hop(Send) avg={idleGap.HopAvgMs:0.00} max={idleGap.HopMaxMs:0.00} ms");
        hud.Update(HudState.Recording);
        var recGap = await MeasureDispatcherAsync(TimeSpan.FromSeconds(2));
        Line($"recording:    render ticks/s={recGap.RenderHz:0}  process CPU={recGap.CpuPercent:0.0}% of one core  hop(Send) avg={recGap.HopAvgMs:0.00} max={recGap.HopMaxMs:0.00} ms");
        hud.Update(HudState.Transcribing);
        var txGap = await MeasureDispatcherAsync(TimeSpan.FromSeconds(2));
        Line($"transcribing: render ticks/s={txGap.RenderHz:0}  process CPU={txGap.CpuPercent:0.0}% of one core  hop(Send) avg={txGap.HopAvgMs:0.00} max={txGap.HopMaxMs:0.00} ms");
        hud.Update(HudState.Idle);

        // ---------------------------------------------------------------- 2. microphone path
        Line("");
        Line("== Microphone start path ==");
        string? deviceId = null;
        try { deviceId = new SettingsStore().State.InputDeviceId; } catch { }
        Line($"settings inputDeviceId = {deviceId ?? "<system default>"}");
        var recorder = new NAudioRecorder { PreferredDeviceId = deviceId };
        for (int i = 1; i <= 3; i++)
        {
            var sw = Stopwatch.StartNew();
            bool granted = await recorder.RequestPermissionAsync();
            Line($"RequestPermissionAsync #{i}: {sw.Elapsed.TotalMilliseconds:0.0} ms (granted={granted})");
        }
        for (int i = 1; i <= 3; i++)
        {
            var sw = Stopwatch.StartNew();
            string? id = AudioInputRouter.PreferredCaptureDeviceId(deviceId);
            Line($"PreferredCaptureDeviceId #{i}: {sw.Elapsed.TotalMilliseconds:0.0} ms -> {(id is null ? "<default>" : id[..Math.Min(24, id.Length)] + "…")}");
        }
        for (int i = 1; i <= 3; i++)
        {
            var sw = Stopwatch.StartNew();
            bool ok = recorder.TryStart(out var err);
            double startMs = sw.Elapsed.TotalMilliseconds;
            if (!ok) { Line($"TryStart #{i}: FAILED {err}"); break; }
            await Task.Delay(300);
            sw.Restart();
            string? path = recorder.Stop();
            double stopMs = sw.Elapsed.TotalMilliseconds;
            long bytes = path is not null && File.Exists(path) ? new FileInfo(path).Length : -1;
            if (path is not null) { try { File.Delete(path); } catch { } }
            Line($"TryStart #{i}: {startMs:0.0} ms   Stop: {stopMs:0.0} ms   wav={bytes} bytes");
            await Task.Delay(200);
        }
        recorder.Dispose();

        // ---------------------------------------------------------------- 3. UI-thread file I/O
        Line("");
        Line("== UI-thread file writes ==");
        string tmpLog = Path.Combine(Path.GetTempPath(), "jvoice-latency-probe-append.log");
        var swLog = Stopwatch.StartNew();
        for (int i = 0; i < 50; i++)
            File.AppendAllText(tmpLog, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  [{Environment.ProcessId}/2]  HUD Recording{Environment.NewLine}");
        Line($"AppendAllText x50 (DiagnosticLog pattern): avg {swLog.Elapsed.TotalMilliseconds / 50:0.00} ms");
        try { File.Delete(tmpLog); } catch { }

        // ---------------------------------------------------------------- 4. clipboard snapshot
        Line("");
        Line("== Clipboard snapshot (Paster.CaptureClipboard pattern; READ ONLY) ==");
        for (int i = 1; i <= 2; i++)
        {
            var sw = Stopwatch.StartNew();
            int formats = 0, cloned = 0;
            try
            {
                IDataObject current = Clipboard.GetDataObject();
                var clone = new DataObject();
                foreach (string fmt in current.GetFormats(autoConvert: false))
                {
                    formats++;
                    try
                    {
                        object? data = current.GetData(fmt, autoConvert: false);
                        if (data is not null) { clone.SetData(fmt, data); cloned++; }
                    }
                    catch { }
                }
            }
            catch (Exception ex) { Line($"  clipboard read threw {ex.GetType().Name}"); }
            Line($"snapshot #{i}: {sw.Elapsed.TotalMilliseconds:0.0} ms  formats={formats} cloned={cloned}");
        }

        // ---------------------------------------------------------------- 5. decode vs UI stall
        string? wav = ArgValue(args, "--wav");
        if (wav is not null && File.Exists(wav))
        {
            Line("");
            Line($"== Whisper decode vs UI-thread stall  clip={Path.GetFileName(wav)} ==");
            var threadList = (ArgValue(args, "--threads") ?? EngineTuning.Default.Threads?.ToString() ?? "4")
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(int.Parse).ToList();
            var store = new WhisperModelStore();
            List<string> vocab = new();
            try { vocab = new SettingsStore().State.CustomWords.ToList(); } catch { }
            foreach (int threads in threadList)
            {
                var tuning = EngineTuning.Default with { Threads = threads };
                var engine = new WhisperNetTranscriptionEngine(
                    WhisperModelOption.LargeTurbo, TranscriptionLanguage.English, vocab, true, store, tuning);
                var swLoad = Stopwatch.StartNew();
                await engine.PrewarmAsync();
                Line($"threads={threads}: prewarm {swLoad.Elapsed.TotalSeconds:0.00} s  runtime={WhisperRuntime.Describe()}");
                if (!await engine.IsReadyAsync()) { Line("  engine not ready — skipping"); continue; }
                _ = await engine.TranscribeAsync(wav); // warm-up
                if (threads == threadList[0])
                {
                    // Per-decode fixed cost: the engine builds a fresh WhisperProcessor (whisper state)
                    // for EVERY decode. Measure that alone via the same factory path.
                    var f = global::Whisper.net.WhisperFactory.FromPath(store.PathFor(WhisperModelOption.LargeTurbo),
                        new global::Whisper.net.WhisperFactoryOptions { UseFlashAttention = tuning.UseFlashAttention });
                    for (int b = 1; b <= 3; b++)
                    {
                        var swB = Stopwatch.StartNew();
                        var proc = f.CreateBuilder().WithLanguage("en").WithThreads(threads).Build();
                        double buildMs = swB.Elapsed.TotalMilliseconds;
                        swB.Restart();
                        await proc.DisposeAsync();
                        Line($"  processor Build() #{b}: {buildMs:0.0} ms   Dispose: {swB.Elapsed.TotalMilliseconds:0.0} ms");
                    }
                    f.Dispose();
                }
                for (int i = 1; i <= 2; i++)
                {
                    hud.Update(HudState.Transcribing); // the real app animates the pill during decode
                    var hook = StartHookThreadProxy();
                    var gapTask = MeasureDispatcherAsync(TimeSpan.FromSeconds(30), stopWhen: () => hook.Done);
                    var sw = Stopwatch.StartNew();
                    string text = await engine.TranscribeAsync(wav);
                    sw.Stop();
                    hook.Stop();
                    var gap = await gapTask;
                    hud.Update(HudState.Idle);
                    Line($"  decode #{i}: {sw.Elapsed.TotalSeconds:0.000} s  chars={text.Length}  " +
                         $"process CPU={gap.CpuPercent:0}% of one core ({gap.CpuPercent / 100.0:0.00} cores)  " +
                         $"hop(Send) max={gap.HopMaxMs:0.00} ms  highest-prio thread max stall {hook.MaxStallMs:0.0} ms");
                    await Task.Delay(300);
                }
            }
        }
        else
        {
            Line("");
            Line("(no --wav given or file missing — decode/stall section skipped)");
        }

        Volatile.Write(ref stopLoad, true);
        Line("");
        Line($"report: {_outPath}");
    }

    // ---- helpers ----

    private static string? ArgValue(string[] args, string name)
    {
        int i = Array.FindIndex(args, a => string.Equals(a, name, StringComparison.OrdinalIgnoreCase));
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    /// Milliseconds from `since` to the next CompositionTarget.Rendering tick (the first frame
    /// WPF actually renders after a show/update).
    private static Task<double> WaitFirstRenderAsync(Stopwatch since)
    {
        var tcs = new TaskCompletionSource<double>();
        EventHandler? h = null;
        h = (_, _) =>
        {
            CompositionTarget.Rendering -= h;
            tcs.TrySetResult(since.Elapsed.TotalMilliseconds);
        };
        CompositionTarget.Rendering += h;
        return tcs.Task;
    }

    private readonly record struct GapStats(double RenderHz, double CpuPercent, double HopAvgMs, double HopMaxMs);

    /// For `duration`: counts CompositionTarget.Rendering ticks, measures this process's CPU
    /// time (all threads) as a % of one core, and, from a background thread, how long a
    /// DispatcherPriority.Send InvokeAsync takes to actually run on the UI thread (the exact hop
    /// the hotkey takes from the hook thread to ToggleRecording).
    private static async Task<GapStats> MeasureDispatcherAsync(TimeSpan duration, Func<bool>? stopWhen = null)
    {
        var proc = Process.GetCurrentProcess();
        var cpu0 = proc.TotalProcessorTime;
        var sw = Stopwatch.StartNew();
        int renders = 0;
        EventHandler onRender = (_, _) => renders++;
        CompositionTarget.Rendering += onRender;
        var dispatcher = Dispatcher.CurrentDispatcher;
        double hopSum = 0, hopMax = 0; int hops = 0;
        bool stop = false;
        var hopper = Task.Run(async () =>
        {
            while (!stop)
            {
                var t = Stopwatch.StartNew();
                await dispatcher.InvokeAsync(() => { double ms = t.Elapsed.TotalMilliseconds; hopSum += ms; if (ms > hopMax) hopMax = ms; hops++; }, DispatcherPriority.Send);
                await Task.Delay(20);
            }
        });
        while (sw.Elapsed < duration && !(stopWhen?.Invoke() ?? false))
            await Task.Delay(10);
        stop = true;
        await hopper;
        CompositionTarget.Rendering -= onRender;
        double total = sw.Elapsed.TotalMilliseconds;
        proc.Refresh();
        double cpuMs = (proc.TotalProcessorTime - cpu0).TotalMilliseconds;
        return new GapStats(renders / (total / 1000.0), 100.0 * cpuMs / total, hops > 0 ? hopSum / hops : 0, hopMax);
    }

    /// A Highest-priority thread sleeping 1 ms at a time, recording the worst overshoot — a proxy
    /// for how late the WH_KEYBOARD_LL hook thread (also Highest) gets scheduled during a decode.
    private sealed class HookProxy
    {
        public volatile bool Done;
        private volatile bool _stop;
        public double MaxStallMs;
        public void Stop() { _stop = true; }
        public void Run()
        {
            var sw = Stopwatch.StartNew();
            double last = 0;
            while (!_stop)
            {
                Thread.Sleep(1);
                double now = sw.Elapsed.TotalMilliseconds;
                double stall = now - last - 1;
                if (stall > MaxStallMs) MaxStallMs = stall;
                last = now;
            }
            Done = true;
        }
    }

    private static HookProxy StartHookThreadProxy()
    {
        var p = new HookProxy();
        new Thread(p.Run) { IsBackground = true, Priority = ThreadPriority.Highest, Name = "probe-hook-proxy" }.Start();
        return p;
    }
}
