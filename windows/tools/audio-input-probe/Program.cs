using System.IO;
using JVoice.App.Platform;
using JVoice.Core;
using JVoice.Core.Models;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace JVoice.Tools.AudioInputProbe;

/// Diagnoses the "JVoice records digital silence" class of bug: every capture endpoint
/// with its mute state, master level, form factor and Bluetooth verdict, WHICH endpoint
/// the shipping AudioInputRouter would actually open, and (opt-in) a short real capture
/// reporting peak/RMS so you can tell a muted/zero-level mic from a dead one.
///
///   audio-input-probe                      passive enumeration only (no mic use)
///   audio-input-probe --record 3           record 3s from the endpoint JVoice would pick
///   audio-input-probe --record 3 --all     record 3s from EVERY active endpoint in turn
///   audio-input-probe --recorder 3         END-TO-END: run the REAL NAudioRecorder with the
///                                          device chosen in settings.json and grade the WAV
///                                          exactly as VoiceCoordinator does
internal static class Program
{
    // PKEY_Device_EnumeratorName {a45c254e-df1c-4efd-8020-67d146a850e0},24
    private static readonly PropertyKey PkeyEnumeratorName =
        new(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 24);

    // PKEY_AudioEndpoint_FormFactor {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0
    private static readonly PropertyKey PkeyFormFactor =
        new(new Guid("1da5d803-d492-4edd-8c23-e0c0ffee7f0e"), 0);

    private static readonly string[] FormFactorNames =
    {
        "RemoteNetworkDevice", "Speakers", "LineLevel", "Headphones", "Microphone",
        "Headset", "Handset", "UnknownDigitalPassthrough", "SPDIF", "DigitalAudioDisplayDevice",
    };

    private static int Main(string[] args)
    {
        double recordSeconds = 0, recorderSeconds = 0;
        bool recordAll = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--record" && i + 1 < args.Length && double.TryParse(args[i + 1], out var s))
            { recordSeconds = s; i++; }
            else if (args[i] == "--recorder" && i + 1 < args.Length && double.TryParse(args[i + 1], out var r))
            { recorderSeconds = r; i++; }
            else if (args[i] == "--all") recordAll = true;
        }

        // --measure <wav...>: grade existing recordings with the shipping CaptureSignal +
        // SilentCaptureDetector pair (what decides "No speech detected." vs naming a dead mic).
        var measureFiles = new List<string>();
        for (int i = 0; i < args.Length; i++)
            if (args[i] == "--measure")
                for (int j = i + 1; j < args.Length && !args[j].StartsWith("--"); j++) measureFiles.Add(args[j]);
        if (measureFiles.Count > 0) return MeasureFiles(measureFiles);

        if (recorderSeconds > 0) return RunRealRecorder(recorderSeconds);

        using var enumerator = new MMDeviceEnumerator();

        string? defaultId = null;
        try
        {
            if (enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
            {
                using var def = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
                defaultId = def.ID;
            }
        }
        catch (Exception ex) { Console.WriteLine($"!! default endpoint query failed: {ex.Message}"); }

        // What the SHIPPING app would open (real production code path).
        string? routedId = AudioInputRouter.PreferredCaptureDeviceId();
        string? openedId = routedId ?? defaultId;

        Console.WriteLine("=== Active capture endpoints ===");
        var actives = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
        if (actives.Count == 0) Console.WriteLine("  (none — no active capture endpoint at all)");

        foreach (var dev in actives) Describe(dev, defaultId, openedId);

        Console.WriteLine();
        Console.WriteLine("=== Endpoints that are NOT active (disabled / unplugged / missing) ===");
        var inactive = enumerator
            .EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Disabled | DeviceState.Unplugged | DeviceState.NotPresent)
            .ToList();
        if (inactive.Count == 0) Console.WriteLine("  (none)");
        foreach (var dev in inactive)
        {
            Console.WriteLine($"  [{dev.State,-10}] {Safe(() => dev.FriendlyName)}");
            dev.Dispose();
        }

        Console.WriteLine();
        Console.WriteLine("=== What JVoice opens ===");
        Console.WriteLine($"  system default (Console) : {NameOf(enumerator, defaultId)}");
        Console.WriteLine($"  AudioInputRouter override: {(routedId is null ? "(none — uses system default)" : NameOf(enumerator, routedId))}");
        Console.WriteLine($"  => RECORDS FROM          : {NameOf(enumerator, openedId)}");

        int exit = 0;
        if (recordSeconds > 0)
        {
            Console.WriteLine();
            Console.WriteLine($"=== Live capture test ({recordSeconds:0.#}s each) ===");
            var targets = recordAll
                ? actives.ToList()
                : actives.Where(d => d.ID == openedId).ToList();
            if (targets.Count == 0) { Console.WriteLine("  (no target endpoint)"); exit = 2; }
            foreach (var dev in targets)
            {
                bool gotSignal = RecordAndReport(dev, recordSeconds);
                if (dev.ID == openedId && !gotSignal) exit = 1;
            }
        }

        foreach (var dev in actives) dev.Dispose();
        return exit;
    }

    /// Grades existing WAVs with the production CaptureSignal + SilentCaptureDetector pair, so a
    /// real capture can be replayed against the dead-input decision without a microphone.
    private static int MeasureFiles(IReadOnlyList<string> files)
    {
        Console.WriteLine("=== CaptureSignal / SilentCaptureDetector verdicts ===");
        foreach (string f in files)
        {
            var stats = CaptureSignal.Measure(f);
            if (stats is not { } s) { Console.WriteLine($"  {Path.GetFileName(f)}  -> UNREADABLE"); continue; }
            bool dead = SilentCaptureDetector.IsDeadInput(s);
            Console.WriteLine($"  {Path.GetFileName(f),-40} secs={s.Seconds,6:0.00}  " +
                $"nonZero={s.NonZeroSamples,9}/{s.TotalSamples,-9} ratio={s.NonZeroRatio:0.000000}  " +
                $"-> {(dead ? "DEAD INPUT" : "live audio")}");
        }
        return 0;
    }

    /// End-to-end check of the shipping path: read the user's chosen device from settings.json,
    /// record with the REAL NAudioRecorder, then grade the resulting WAV with the same
    /// CaptureSignal + SilentCaptureDetector the coordinator uses. Exit 0 = real audio captured.
    private static int RunRealRecorder(double seconds)
    {
        string? chosenId = null, chosenName = null;
        try
        {
            string file = PlatformPaths.SettingsFile;
            if (File.Exists(file))
            {
                var state = SettingsStateJson.Deserialize(File.ReadAllText(file));
                chosenId = state.InputDeviceId;
                chosenName = state.InputDeviceName;
            }
        }
        catch (Exception ex) { Console.WriteLine($"!! settings.json unreadable: {ex.Message}"); }

        Console.WriteLine("=== End-to-end recorder test (real NAudioRecorder) ===");
        Console.WriteLine($"  settings inputDeviceId  : {chosenId ?? "(null = system default)"}");
        Console.WriteLine($"  settings inputDeviceName: {chosenName ?? "(null)"}");
        Console.WriteLine($"  resolved endpoint       : {AudioInputRouter.ResolveDeviceName(chosenId) ?? "(unknown)"}");

        var recorder = new NAudioRecorder { PreferredDeviceId = chosenId };
        if (!recorder.TryStart(out string? error))
        {
            Console.WriteLine($"  FAILED to start: {error}");
            recorder.Dispose();
            return 2;
        }

        Thread.Sleep((int)(seconds * 1000));
        string? path = recorder.Stop();
        recorder.Dispose();

        if (path is null || !File.Exists(path))
        {
            Console.WriteLine("  FAILED: no WAV produced.");
            return 2;
        }

        try
        {
            var stats = CaptureSignal.Measure(path);
            if (stats is not { } s)
            {
                Console.WriteLine($"  FAILED: could not measure {path}");
                return 2;
            }

            bool dead = SilentCaptureDetector.IsDeadInput(s);
            Console.WriteLine($"  wav      : {path} ({new FileInfo(path).Length} bytes)");
            Console.WriteLine($"  samples  : {s.TotalSamples}  nonZero={s.NonZeroSamples}  ratio={s.NonZeroRatio:0.000000}  secs={s.Seconds:0.00}");
            Console.WriteLine(dead
                ? $"  VERDICT  : DEAD INPUT -> \"{SilentCaptureDetector.DeadInputMessage(chosenName ?? AudioInputRouter.ResolveDeviceName(chosenId))}\""
                : "  VERDICT  : OK — the microphone is sending real audio.");
            return dead ? 1 : 0;
        }
        finally
        {
            try { File.Delete(path); } catch { /* privacy: best effort */ }
        }
    }

    private static void Describe(MMDevice dev, string? defaultId, string? openedId)
    {
        var tags = new List<string>();
        if (dev.ID == defaultId) tags.Add("SYSTEM-DEFAULT");
        if (dev.ID == openedId) tags.Add("<== JVOICE RECORDS HERE");

        Console.WriteLine();
        Console.WriteLine($"  {Safe(() => dev.FriendlyName)}  {string.Join(" ", tags)}");
        Console.WriteLine($"    id           : {dev.ID}");
        Console.WriteLine($"    formFactor   : {FormFactorName(dev)}");
        Console.WriteLine($"    enumerator   : {EnumeratorName(dev)}");

        // The two settings that silently produce all-zero PCM.
        try
        {
            var vol = dev.AudioEndpointVolume;
            Console.WriteLine($"    MUTED        : {vol.Mute}{(vol.Mute ? "   <<< delivers digital silence" : "")}");
            double pct = vol.MasterVolumeLevelScalar * 100.0;
            Console.WriteLine($"    level        : {pct:0.#}%{(pct <= 0.05 ? "   <<< delivers digital silence" : "")}");
        }
        catch (Exception ex) { Console.WriteLine($"    volume       : (unreadable: {ex.Message})"); }

        try { Console.WriteLine($"    live peak    : {dev.AudioMeterInformation.MasterPeakValue:0.000000}"); }
        catch (Exception ex) { Console.WriteLine($"    live peak    : (unreadable: {ex.Message})"); }

        try
        {
            var f = dev.AudioClient.MixFormat;
            Console.WriteLine($"    mix format   : {f.SampleRate} Hz, {f.Channels} ch, {f.BitsPerSample}-bit {f.Encoding}");
        }
        catch (Exception ex) { Console.WriteLine($"    mix format   : (unreadable: {ex.Message})"); }
    }

    /// Opens the endpoint exactly like NAudioRecorder does and reports whether real
    /// signal arrived. Returns true if any non-zero sample was seen.
    private static bool RecordAndReport(MMDevice dev, double seconds)
    {
        Console.WriteLine();
        Console.WriteLine($"  -> {Safe(() => dev.FriendlyName)}");
        try
        {
            using var capture = new WasapiCapture(dev, useEventSync: true);
            var fmt = capture.WaveFormat;
            long samples = 0, nonZero = 0;
            double peak = 0, sumSquares = 0;
            int packets = 0;

            capture.DataAvailable += (_, e) =>
            {
                packets++;
                if (fmt.Encoding == WaveFormatEncoding.IeeeFloat || fmt.BitsPerSample == 32)
                {
                    for (int i = 0; i + 3 < e.BytesRecorded; i += 4)
                    {
                        float v = BitConverter.ToSingle(e.Buffer, i);
                        samples++; if (v != 0f) nonZero++;
                        double a = Math.Abs(v);
                        if (a > peak) peak = a;
                        sumSquares += (double)v * v;
                    }
                }
                else if (fmt.BitsPerSample == 16)
                {
                    for (int i = 0; i + 1 < e.BytesRecorded; i += 2)
                    {
                        float v = BitConverter.ToInt16(e.Buffer, i) / 32768f;
                        samples++; if (v != 0f) nonZero++;
                        double a = Math.Abs(v);
                        if (a > peak) peak = a;
                        sumSquares += (double)v * v;
                    }
                }
            };

            capture.StartRecording();
            Thread.Sleep((int)(seconds * 1000));
            capture.StopRecording();
            Thread.Sleep(250); // let the last packets land

            double rms = samples > 0 ? Math.Sqrt(sumSquares / samples) : 0;
            Console.WriteLine($"     format={fmt.SampleRate}Hz/{fmt.Channels}ch/{fmt.BitsPerSample}bit  packets={packets}  samples={samples}");
            Console.WriteLine($"     nonZero={nonZero}/{samples}  peak={peak:0.000000}  rms={rms:0.000000}");
            if (packets == 0)
                Console.WriteLine("     VERDICT: NO DATA — the endpoint delivered no packets at all.");
            else if (nonZero == 0)
                Console.WriteLine("     VERDICT: DIGITAL SILENCE — packets arrived but every sample is 0 (muted / level 0 / dead input).");
            else if (peak < 0.001)
                Console.WriteLine("     VERDICT: signal present but extremely weak.");
            else
                Console.WriteLine("     VERDICT: OK — real audio.");
            return nonZero > 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"     FAILED to open: {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    private static string NameOf(MMDeviceEnumerator enumerator, string? id)
    {
        if (id is null) return "(none)";
        try { using var d = enumerator.GetDevice(id); return $"{d.FriendlyName}"; }
        catch { return id; }
    }

    private static string FormFactorName(MMDevice dev)
    {
        try
        {
            if (!dev.Properties.Contains(PkeyFormFactor)) return "(absent)";
            int v = Convert.ToInt32(dev.Properties[PkeyFormFactor].Value);
            return v >= 0 && v < FormFactorNames.Length ? $"{FormFactorNames[v]} ({v})" : v.ToString();
        }
        catch { return "(unreadable)"; }
    }

    private static string EnumeratorName(MMDevice dev)
    {
        try
        {
            if (!dev.Properties.Contains(PkeyEnumeratorName)) return "(absent)";
            return dev.Properties[PkeyEnumeratorName].Value?.ToString() ?? "(null)";
        }
        catch { return "(unreadable)"; }
    }

    private static string Safe(Func<string> f)
    {
        try { return f(); } catch (Exception ex) { return $"(unreadable: {ex.Message})"; }
    }
}
