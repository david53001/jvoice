using System.IO;
using JVoice.App.Platform;

// capture-stop-probe — deterministic, headless, on-device regression check for the
// §7 #37 capture-teardown deadlock (the "first recording freeze"): Stop() used to
// dispose the WASAPI capture — whose Dispose JOINS the capture thread — while holding
// the recorder gate that OnDataAvailable needs, freezing the calling thread forever.
//
// The probe drives the REAL NAudioRecorder (compiled from source) through
// start → record → stop cycles with the JVOICE_TEST_SLOW_CAPTURE_MS seam widening the
// capture callback's gate hold, which made the unfixed code deadlock on the first
// stop every time. No GUI, no HUD, no paste, no clipboard — it opens the default mic
// for ~1.5 s per cycle and deletes the temp WAV immediately.
//
//   dotnet run --project windows/tools/capture-stop-probe -c Release -- [--cycles 3]
//       [--slow-ms 200] [--record-ms 1500]
//
// Exit codes: 0 = all cycles passed · 2 = Stop() deadlocked (regression!) ·
//             3 = capture couldn't start (no/denied mic — not a verdict).

int cycles = ArgInt("--cycles", 3);
int slowMs = ArgInt("--slow-ms", 200);
int recordMs = ArgInt("--record-ms", 1500);
const int stopTimeoutSeconds = 10;

// The seam is read once at NAudioRecorder's static init — set it before first use.
if (slowMs > 0)
    Environment.SetEnvironmentVariable("JVOICE_TEST_SLOW_CAPTURE_MS", slowMs.ToString());

Console.WriteLine($"capture-stop-probe: cycles={cycles} slow-ms={slowMs} record-ms={recordMs}");

for (int i = 1; i <= cycles; i++)
{
    var recorder = new NAudioRecorder();
    if (!recorder.TryStart(out var error))
    {
        Console.WriteLine($"cycle {i}: NO-MIC — could not start capture: {error}");
        return 3;
    }
    Thread.Sleep(recordMs);

    string? path = null;
    var stop = Task.Run(() => path = recorder.Stop());
    if (!stop.Wait(TimeSpan.FromSeconds(stopTimeoutSeconds)))
    {
        Console.WriteLine(
            $"cycle {i}: FAIL — Stop() DEADLOCKED (> {stopTimeoutSeconds}s). " +
            "The §7 #37 capture-teardown regression is back (join under the gate).");
        return 2; // exiting the process is the only way out of the deadlock
    }

    long bytes = path is not null && File.Exists(path) ? new FileInfo(path).Length : -1;
    if (path is not null) { try { File.Delete(path); } catch { /* best effort */ } }
    recorder.Dispose();
    Console.WriteLine($"cycle {i}: PASS — Stop() returned, wav={(bytes >= 0 ? $"{bytes} bytes" : "<missing>")}");
}

Console.WriteLine("ALL PASS — capture stop teardown is deadlock-free under the seeded race.");
return 0;

int ArgInt(string name, int fallback)
{
    var a = Environment.GetCommandLineArgs();
    for (int i = 0; i < a.Length - 1; i++)
        if (string.Equals(a[i], name, StringComparison.OrdinalIgnoreCase)
            && int.TryParse(a[i + 1], out var v) && v >= 0)
            return v;
    return fallback;
}
