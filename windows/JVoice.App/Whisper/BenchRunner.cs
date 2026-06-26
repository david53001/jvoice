using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using Whisper.net.LibraryLoader;

namespace JVoice.App.Whisper;

/// Hidden CLI bench mode (port of BenchRunner.swift):
///
///     JVoice --bench &lt;audio.wav&gt; [--model tiny|base|small|large] [--lang en|ro]
///            [--vocab "Word1,Word2"] [--stream] [--no-prompt]
///
/// Transcribes one file with timing and prints the raw transcript and the
/// TextProcessor-processed output. The primary end-to-end verification of
/// transcription speed and vocabulary biasing on Windows (no XUnit coverage of
/// the native path). Runs BEFORE any UI (Program.Main / Phase 4 App startup).
internal static class BenchRunner
{
    public static bool ShouldRun(string[] arguments) => arguments.Contains("--bench");

    /// Blocks on the async run and returns the process exit code.
    public static int RunAndExit(string[] arguments)
        => RunAsync(arguments).GetAwaiter().GetResult();

    private static async Task<int> RunAsync(string[] arguments)
    {
        int benchIndex = Array.IndexOf(arguments, "--bench");
        if (benchIndex < 0 || arguments.Length <= benchIndex + 1)
        {
            Console.Error.WriteLine(
                "usage: JVoice --bench <audio.wav> [--model tiny|base|small|large] [--lang en|ro] " +
                "[--vocab \"Word1,Word2\"] [--stream] [--no-prompt] " +
                "[--iters N] [--flash on|off] [--threads N] [--audio-ctx off|auto|N] " +
                "[--runtime auto|cuda|cuda12|cuda-any|vulkan|cpu] [--log-runtime]");
            return 64;
        }

        string audioPath = arguments[benchIndex + 1];
        if (!File.Exists(audioPath))
        {
            Console.Error.WriteLine($"no such file: {audioPath}");
            return 66;
        }

        var model = WhisperModelOption.Base;
        int modelIndex = Array.IndexOf(arguments, "--model");
        if (modelIndex >= 0 && arguments.Length > modelIndex + 1)
        {
            switch (arguments[modelIndex + 1])
            {
                case "tiny": model = WhisperModelOption.Tiny; break;
                case "base": model = WhisperModelOption.Base; break;
                case "small": model = WhisperModelOption.Small; break;
                case "large":
                case "large-v3_turbo":
                case "largeTurbo":
                case "large-v3-v20240930":
                    model = WhisperModelOption.LargeTurbo; break;
                default:
                    Console.Error.WriteLine($"unknown model {arguments[modelIndex + 1]}");
                    return 64;
            }
        }

        var language = TranscriptionLanguage.English;
        int langIndex = Array.IndexOf(arguments, "--lang");
        if (langIndex >= 0 && arguments.Length > langIndex + 1)
        {
            switch (arguments[langIndex + 1])
            {
                case "en":
                case "english": language = TranscriptionLanguage.English; break;
                case "ro":
                case "romanian": language = TranscriptionLanguage.Romanian; break;
                default:
                    Console.Error.WriteLine($"unknown lang {arguments[langIndex + 1]}");
                    return 64;
            }
        }

        var vocabulary = new List<string>();
        int vocabIndex = Array.IndexOf(arguments, "--vocab");
        if (vocabIndex >= 0 && arguments.Length > vocabIndex + 1)
        {
            vocabulary = arguments[vocabIndex + 1]
                .Split(',')
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .ToList();
        }

        bool useDecoderPrompt = !arguments.Contains("--no-prompt");

        // ---- speed-measurement flags (speed plan 2026-06-27) ----
        int iters = ReadIntFlag(arguments, "--iters", 3);

        bool? flash = null;
        int fi = Array.IndexOf(arguments, "--flash");
        if (fi >= 0 && arguments.Length > fi + 1)
            flash = arguments[fi + 1] is "on" or "true" or "1";

        int? threads = null;
        int thi = Array.IndexOf(arguments, "--threads");
        if (thi >= 0 && arguments.Length > thi + 1 && int.TryParse(arguments[thi + 1], out int tparsed))
            threads = tparsed;

        // --audio-ctx: "off" (default, full window) | "auto" (per-clip policy) | <int> (fixed)
        bool adaptiveCtx = false;
        int? fixedCtx = null;
        int aci = Array.IndexOf(arguments, "--audio-ctx");
        if (aci >= 0 && arguments.Length > aci + 1)
        {
            string v = arguments[aci + 1];
            if (v == "auto") adaptiveCtx = true;
            else if (v != "off" && int.TryParse(v, out int cparsed)) fixedCtx = cparsed;
        }

        if (arguments.Contains("--log-runtime")) WhisperRuntime.EnableDebugLogging();

        int ri = Array.IndexOf(arguments, "--runtime");
        if (ri >= 0 && arguments.Length > ri + 1)
        {
            switch (arguments[ri + 1])
            {
                case "auto": break; // default probe order
                case "cuda": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda); break;
                case "cuda12": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda12); break;
                case "cuda-any": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cuda, RuntimeLibrary.Cuda12); break;
                case "vulkan": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Vulkan); break;
                case "cpu": WhisperRuntime.ForceRuntimeOrder(RuntimeLibrary.Cpu); break;
                default:
                    Console.Error.WriteLine($"unknown runtime {arguments[ri + 1]}");
                    return 64;
            }
        }

        var tuning = new EngineTuning(
            UseFlashAttention: flash ?? false,
            AdaptiveAudioContext: adaptiveCtx,
            FixedAudioContext: fixedCtx,
            Threads: threads);

        // Matches the Swift header line. Swift printed `model.rawValue`; we print the
        // GGML file stem (the closest stable Windows analog of the model identity).
        string vocabDisplay = vocabulary.Count == 0 ? "—" : string.Join(", ", vocabulary);
        Console.WriteLine(
            $"model: {model.GgmlFileName()}   audio: {Path.GetFileName(audioPath)}   " +
            $"lang: {language.WhisperCode()}   vocab: {vocabDisplay}   " +
            $"decoderPrompt: {(useDecoderPrompt ? "on" : "off")}");
        Console.WriteLine(
            $"tuning: flash={(tuning.UseFlashAttention ? "on" : "off")}  " +
            $"threads={(tuning.Threads?.ToString() ?? "default")}  " +
            $"audio_ctx={(tuning.FixedAudioContext?.ToString() ?? (tuning.AdaptiveAudioContext ? "auto" : "full"))}  " +
            $"iters={iters}");

        var store = new WhisperModelStore();
        var engine = new WhisperNetTranscriptionEngine(
            model, language, vocabulary, useDecoderPrompt, store, tuning);

        var loadSw = Stopwatch.StartNew();
        await engine.PrewarmAsync();
        loadSw.Stop();
        WhisperRuntime.EnsureLoaded();
        Console.WriteLine($"runtime: {WhisperRuntime.Describe()}");
        Console.WriteLine($"load+prewarm: {loadSw.Elapsed.TotalSeconds:0.00}s");

        if (!await engine.IsReadyAsync())
        {
            Console.Error.WriteLine("engine has no loaded model (download or runtime failure)");
            return 70;
        }

        if (arguments.Contains("--stream"))
            return await RunStreamAsync(audioPath, engine, vocabulary);

        try
        {
            // One warm-up decode (excluded) so steady-state timing isn't polluted by lazy init.
            string raw = await engine.TranscribeAsync(audioPath, CancellationToken.None);

            var times = new List<double>();
            for (int i = 0; i < Math.Max(1, iters); i++)
            {
                var sw = Stopwatch.StartNew();
                raw = await engine.TranscribeAsync(audioPath, CancellationToken.None);
                sw.Stop();
                times.Add(sw.Elapsed.TotalSeconds);
            }
            times.Sort();
            double median = times[times.Count / 2];
            Console.WriteLine(
                $"transcribe: median={median:0.000}s  min={times[0]:0.000}s  " +
                $"max={times[^1]:0.000}s  (n={times.Count}, warm-up excluded)");
            Console.WriteLine($"raw:       \"{raw}\"");
            var userDict = TextProcessor.BuildUserDictionary(vocabulary);
            string processed = TextProcessor.Process(
                raw, ToneStyle.Casual, userDict, removeFillerWords: false, vocabulary: vocabulary);
            Console.WriteLine($"processed: \"{processed}\"");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"transcription failed: {ex.Message}");
            return 1;
        }
    }

    private static int ReadIntFlag(string[] args, string name, int fallback)
    {
        int i = Array.IndexOf(args, name);
        return (i >= 0 && args.Length > i + 1 && int.TryParse(args[i + 1], out int v)) ? v : fallback;
    }

    /// Streaming E2E without a microphone: replays `audioPath` into a growing temp
    /// WAV at ~10× real time while a real StreamingTranscriptionSession consumes it,
    /// then compares against the whole-file transcript. Port of BenchRunner.runStream.
    private static async Task<int> RunStreamAsync(
        string audioPath, WhisperNetTranscriptionEngine engine, IReadOnlyList<string> vocabulary)
    {
        byte[] sourceBytes;
        try { sourceBytes = await File.ReadAllBytesAsync(audioPath); }
        catch (Exception)
        {
            Console.Error.WriteLine($"cannot read file: {audioPath}");
            return 65;
        }

        int probe = Math.Min(sourceBytes.Length, WavTail.HeaderProbeBytes);
        var info = WavTail.ParseHeader(sourceBytes.AsSpan(0, probe));
        if (info is not { } header)
        {
            Console.Error.WriteLine($"not a 16 kHz mono 16-bit PCM wav: {audioPath}");
            return 65;
        }

        var session = engine.MakeStreamingSession(pollMilliseconds: 100);
        if (session is null)
        {
            Console.Error.WriteLine("engine has no loaded model");
            return 70;
        }

        string growingPath = Path.Combine(
            Path.GetTempPath(), $"jv-stream-{Guid.NewGuid():N}.wav");
        try
        {
            // Seed the growing file with just the header (everything up to dataOffset).
            await File.WriteAllBytesAsync(growingPath, sourceBytes[..header.DataOffset]);

            int sliceBytes = header.SampleRate * header.BytesPerSample / 2; // 0.5 s of audio
            var writer = Task.Run(async () =>
            {
                await using var handle = new FileStream(
                    growingPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite);
                handle.Seek(0, SeekOrigin.End);
                int offset = header.DataOffset;
                while (offset < sourceBytes.Length)
                {
                    int end = Math.Min(offset + sliceBytes, sourceBytes.Length);
                    await handle.WriteAsync(sourceBytes.AsMemory(offset, end - offset));
                    await handle.FlushAsync();
                    offset = end;
                    await Task.Delay(50); // …every 50 ms ⇒ ~10× real time
                }
            });

            var wallSw = Stopwatch.StartNew();
            session.Start(growingPath);
            await writer;                       // "recording" ends here
            var stopSw = Stopwatch.StartNew();
            string? streamed = await session.Finish();
            stopSw.Stop();
            wallSw.Stop();

            Console.WriteLine(
                $"stream wall: {wallSw.Elapsed.TotalSeconds:0.00}s   " +
                $"post-stop (finish): {stopSw.Elapsed.TotalSeconds:0.00}s");
            Console.WriteLine($"streamed:  {(streamed is null ? "nil (session fell back)" : $"\"{streamed}\"")}");

            try
            {
                var wholeSw = Stopwatch.StartNew();
                string whole = await engine.TranscribeAsync(audioPath, CancellationToken.None);
                wholeSw.Stop();
                Console.WriteLine($"wholefile: {wholeSw.Elapsed.TotalSeconds:0.00}s");
                Console.WriteLine($"wholefile: \"{whole}\"");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"whole-file comparison failed: {ex.Message}");
                return 1;
            }
            return 0;
        }
        finally
        {
            try { if (File.Exists(growingPath)) File.Delete(growingPath); } catch (IOException) { }
        }
    }
}
