using System.Text;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using Whisper.net;

namespace JVoice.Tools.NoSpeechProbe;

// On-device experiment: does whisper.cpp (via Whisper.net 1.9.1) reliably tell
// no-speech (silence / mains hum / room noise) from genuine QUIET speech, at
// David's measured low capture level — independent of the brittle RMS gate?
//
// We feed several clips through the SAME decode whisper uses, with and without
// WithNoSpeechThreshold, and print the raw text + whisper's own per-segment
// avg-logprob (SegmentData.Probability). This decides whether a model-based
// no-speech gate can replace the absolute-level HighPassSilence pre-gate.
internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        // --analyze [<wav> ...]: measure whisper's per-segment confidence on REAL recordings
        // (David's silent presses vs his quiet speech), mirroring the LIVE app's model + vocab
        // from settings.json. This is the no-speech threshold CALIBRATION. With no paths it
        // analyzes every clip in %APPDATA%\JVoice\capture (where JVOICE_KEEP_WAV drops them).
        if (args.Contains("--analyze"))
            return await AnalyzeWavs(
                args.SkipWhile(a => a != "--analyze").Skip(1)
                    .Where(a => !a.StartsWith("--")).ToArray());

        // A real speech clip to scale down to David's quiet level. Use the one given, else
        // synthesize one with SAPI (self-contained — no external fixture needed).
        string speechWav = args.Length > 0 && !args[0].StartsWith("--")
            ? args[0]
            : Path.Combine(Path.GetTempPath(), "jvoice-nospeech-probe-speech.wav");

        string modelPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JVoice", "models", "ggml-tiny.bin");

        if (!File.Exists(modelPath)) { Console.Error.WriteLine($"missing model: {modelPath}"); return 2; }
        if (!File.Exists(speechWav)) GenerateSpeechClip(speechWav);

        // --- read the real SAPI speech clip (16k mono 16-bit) ---
        var reader = WavTailReader.Open(speechWav);
        if (reader is null) { Console.Error.WriteLine("speech wav not 16k/mono/16-bit"); return 2; }
        short[] speechPcm = reader.Samples(0)!;
        float[] speech = ToFloat(speechPcm);
        // --muffle: one-pole low-pass to crush the highs so the high-passed/raw ratio drops
        // to ~0.1–0.2, faithfully matching David's real muffled low-pitched-male mic (his
        // logged ratio 0.08–0.17) rather than SAPI's clean ~0.76.
        if (args.Contains("--muffle")) speech = LowPass(speech, 0.10f);
        float speechPeak = AbsPeak(speech);
        Console.WriteLine($"speech clip: {speech.Length} samples ({speech.Length / 16000.0:0.0}s), peak={speechPeak:0.000}");

        const int sr = 16000;
        int dur3 = sr * 3;

        // --- build the corpus (all 16k mono float in [-1,1]) ---
        var clips = new List<(string Name, float[] Samples)>
        {
            ("digital_silence", new float[dur3]),
            ("hum60_rms0.0044", Sine(60, RmsToAmp(0.0044f, isSine: true), dur3, sr)),
            ("whitenoise_rms0.0044", WhiteNoise(0.0044f, dur3, seed: 1234)),
            ("lowfreq_rumble_rms0.0044", Sine(90, RmsToAmp(0.0044f, isSine: true), dur3, sr)),
            ("speech_normal", speech),
            ("speech_peak0.10", ScaleToPeak(speech, 0.10f)),
            ("speech_peak0.05", ScaleToPeak(speech, 0.05f)),   // ~David's quiet capture
            ("speech_peak0.02", ScaleToPeak(speech, 0.02f)),   // very quiet
            ("speech_peak0.008", ScaleToPeak(speech, 0.008f)), // near his rawRMS floor
            // speech + low-freq hum floor underneath (his real low-SNR situation)
            ("speech0.05+hum0.0044", Mix(ScaleToPeak(speech, 0.05f), Sine(60, RmsToAmp(0.0044f, true), speech.Length, sr))),
        };

        // --dump <dir>: write each corpus clip as a 16k mono 16-bit WAV and exit, so the
        // REAL engine (whisper-smoke -> WhisperNetTranscriptionEngine.TranscribeAsync) can be
        // run against them end-to-end.
        int di = Array.IndexOf(args, "--dump");
        if (di >= 0 && args.Length > di + 1)
        {
            string outDir = args[di + 1];
            Directory.CreateDirectory(outDir);
            foreach (var (name, samples) in clips)
            {
                string p = Path.Combine(outDir, name.Replace("+", "_").Replace(".", "p") + ".wav");
                File.WriteAllBytes(p, BuildWav(ToShort(samples)));
                Console.WriteLine($"wrote {p}");
            }
            return 0;
        }

        var factory = WhisperFactory.FromPath(modelPath);

        // The kind of vocabulary prompt David runs with (the main accuracy lever) — this
        // is what was suspected of making whisper regurgitate / emit "you" on silence.
        string? prompt = VocabularyPrompt.Text(new[] { "JVoice", "Li-Fraumeni", "VS Code" });
        Console.WriteLine($"vocab prompt: \"{prompt}\"");

        Console.WriteLine();
        Console.WriteLine($"{"clip",-26} {"rawRMS",8} {"hpRMS",8} | {"NO-prompt raw",-30} {"stripped",-16} | {"WITH-prompt raw",-30} {"stripped",-16}");
        Console.WriteLine(new string('-', 160));

        foreach (var (name, samples) in clips)
        {
            short[] pcm = ToShort(samples);
            float rawRms = HighPassSilence.PeakWindowRms(pcm);
            float hpRms = HighPassSilence.PeakHighPassRms(pcm);

            string rawNo = await Decode(factory, samples, prompt: null);
            string rawYes = await Decode(factory, samples, prompt: prompt);
            // Exactly what the engine now produces: NonSpeechAnnotation.Reduce maps a whole
            // annotation transcript to "", then StripDecoderArtifacts + the blocklist run.
            // Empty result => "No speech detected.". All no-speech rows MUST end <empty>.
            string cleanNo = Engine(rawNo);
            string cleanYes = Engine(rawYes);

            Console.WriteLine(
                $"{name,-26} {rawRms,8:0.0000} {hpRms,8:0.0000} | " +
                $"{Trunc(rawNo, 30),-30} {Clean(cleanNo),-16} | {Trunc(rawYes, 30),-30} {Clean(cleanYes),-16}");
        }

        Console.WriteLine();
        Console.WriteLine("KEY: no-speech clips should end 'stripped' = <empty> (=> \"No speech detected.\");");
        Console.WriteLine("     quiet-speech clips should keep their words. 'stripped' = StripDecoderArtifacts + blocklist.");
        factory.Dispose();
        return 0;
    }

    private static async Task<string> Decode(WhisperFactory factory, float[] samples, string? prompt)
    {
        var builder = factory.CreateBuilder()
            .WithLanguage("en")
            .WithTemperature(0.0f)
            .WithTemperatureInc(0.2f);
        if (prompt is { Length: > 0 }) builder = builder.WithPrompt(prompt);

        await using var processor = builder.Build();
        var sb = new StringBuilder();
        await foreach (var seg in processor.ProcessAsync(samples))
            sb.Append(seg.Text);
        return sb.ToString().Trim();
    }

    // The engine's no-speech reduction + macOS post-processing, in the engine's order.
    private static string Engine(string raw) =>
        TextProcessor.RemoveWhisperHallucinations(
            TextProcessor.StripDecoderArtifacts(NonSpeechAnnotation.Reduce(raw)));

    private static string Clean(string s) => s.Length == 0 ? "<empty>" : "\"" + (s.Length > 14 ? s[..14] : s) + "\"";

    // Synthesize a 16 kHz mono 16-bit speech clip with Windows SAPI so the probe needs no
    // external fixture. Slowed slightly so a tiny model has clean phonemes to work with.
    private static void GenerateSpeechClip(string path)
    {
        using var synth = new System.Speech.Synthesis.SpeechSynthesizer();
        var fmt = new System.Speech.AudioFormat.SpeechAudioFormatInfo(
            16000, System.Speech.AudioFormat.AudioBitsPerSample.Sixteen,
            System.Speech.AudioFormat.AudioChannel.Mono);
        synth.SetOutputToWaveFile(path, fmt);
        synth.Rate = -1;
        synth.Speak("Please figure out this issue and fix the last part of my sentence.");
        synth.SetOutputToNull();
        Console.WriteLine($"generated speech clip: {path}");
    }

    private static byte[] BuildWav(short[] samples)
    {
        var ms = new MemoryStream();
        void U32(int v) => ms.Write(BitConverter.GetBytes((uint)v));
        void U16(int v) => ms.Write(BitConverter.GetBytes((ushort)v));
        void A(string s) => ms.Write(Encoding.ASCII.GetBytes(s));
        A("RIFF"); U32(36 + samples.Length * 2); A("WAVE");
        A("fmt "); U32(16); U16(1); U16(1); U32(16000); U32(32000); U16(2); U16(16);
        A("data"); U32(samples.Length * 2);
        foreach (var s in samples) ms.Write(BitConverter.GetBytes(s));
        return ms.ToArray();
    }

    // --- signal helpers ---
    private static float[] ToFloat(short[] s) { var f = new float[s.Length]; for (int i = 0; i < s.Length; i++) f[i] = s[i] / 32768f; return f; }
    private static short[] ToShort(float[] f)
    {
        var s = new short[f.Length];
        for (int i = 0; i < f.Length; i++) { int v = (int)MathF.Round(f[i] * 32768f); s[i] = (short)Math.Clamp(v, short.MinValue, short.MaxValue); }
        return s;
    }
    private static float AbsPeak(float[] f) { float p = 0; foreach (var v in f) { float a = MathF.Abs(v); if (a > p) p = a; } return p; }
    private static float[] ScaleToPeak(float[] src, float targetPeak)
    {
        float peak = AbsPeak(src); if (peak <= 0) return (float[])src.Clone();
        float g = targetPeak / peak; var o = new float[src.Length];
        for (int i = 0; i < src.Length; i++) o[i] = src[i] * g; return o;
    }
    private static float[] LowPass(float[] src, float alpha)
    {
        var o = new float[src.Length];
        float y = 0;
        for (int i = 0; i < src.Length; i++) { y += alpha * (src[i] - y); o[i] = y; }
        return o;
    }
    private static float RmsToAmp(float rms, bool isSine) => isSine ? rms * 1.41421356f : rms;
    private static float[] Sine(double hz, float amp, int n, int sr)
    {
        var o = new float[n]; double w = 2 * Math.PI * hz / sr;
        for (int i = 0; i < n; i++) o[i] = (float)(amp * Math.Sin(w * i)); return o;
    }
    private static float[] WhiteNoise(float rms, int n, int seed)
    {
        var r = new Random(seed); var o = new float[n];
        for (int i = 0; i < n; i++) o[i] = (float)((r.NextDouble() * 2 - 1) * rms * 1.732); return o;
    }
    private static float[] Mix(float[] a, float[] b)
    {
        int n = Math.Min(a.Length, b.Length); var o = new float[n];
        for (int i = 0; i < n; i++) o[i] = a[i] + b[i]; return o;
    }
    private static string Trunc(string s, int len)
    {
        s = s.Replace("\n", " ");
        return s.Length <= len ? "\"" + s + "\"" : "\"" + s[..(len - 3)] + "...";
    }

    // ---- no-speech calibration (--analyze) ----------------------------------

    private static string CaptureDir() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JVoice", "capture");

    /// Read the live app's model + vocab from settings.json so the measurement matches
    /// exactly what David runs (model and prompt both change whisper's confidence numbers).
    /// Falls back to LargeTurbo + no vocab if settings are missing/unparseable.
    private static (string modelPath, IReadOnlyList<string> vocab) ReadLiveConfig()
    {
        string appData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JVoice");
        string modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JVoice", "models");

        var model = WhisperModelOption.LargeTurbo;
        var vocab = new List<string>();
        try
        {
            string json = File.ReadAllText(Path.Combine(appData, "settings.json"));
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("model", out var m) &&
                Enum.TryParse<WhisperModelOption>(m.GetString(), out var parsed))
                model = parsed;
            if (root.TryGetProperty("customWords", out var cw) &&
                cw.ValueKind == System.Text.Json.JsonValueKind.Array)
                foreach (var w in cw.EnumerateArray())
                {
                    string? s = w.GetString();
                    if (!string.IsNullOrWhiteSpace(s)) vocab.Add(s);
                }
        }
        catch { /* fall back to LargeTurbo + empty vocab */ }
        return (Path.Combine(modelsDir, model.GgmlFileName()), vocab);
    }

    private static async Task<int> AnalyzeWavs(string[] wavArgs)
    {
        var (modelPath, vocab) = ReadLiveConfig();
        if (!File.Exists(modelPath)) { Console.Error.WriteLine($"missing model: {modelPath}"); return 2; }

        string[] wavs = wavArgs.Length > 0
            ? wavArgs
            : (Directory.Exists(CaptureDir())
                ? Directory.GetFiles(CaptureDir(), "*.wav").OrderBy(p => p, StringComparer.Ordinal).ToArray()
                : Array.Empty<string>());
        if (wavs.Length == 0)
        {
            Console.Error.WriteLine(
                $"no WAVs to analyze. Pass paths, or record with JVOICE_KEEP_WAV set (clips land in {CaptureDir()}).");
            return 2;
        }

        string? prompt = vocab.Count > 0 ? VocabularyPrompt.Text(vocab) : null;
        Console.WriteLine($"model: {Path.GetFileName(modelPath)}   vocab: [{string.Join(", ", vocab)}]");
        Console.WriteLine($"prompt: \"{prompt}\"");
        Console.WriteLine();
        Console.WriteLine($"{"file",-26} {"secs",6} {"rawRMS",8} {"hpRMS",8} | pr {"segs",4} {"avgConf",8} {"minConf",8} {"compR",6}  {"engine",-8} text");
        Console.WriteLine(new string('-', 160));

        var factory = WhisperFactory.FromPath(modelPath);
        foreach (var wav in wavs)
        {
            var reader = WavTailReader.Open(wav);
            if (reader is null) { Console.WriteLine($"{Path.GetFileName(wav),-26}  <not 16k/mono/16-bit>"); continue; }
            short[]? pcm = reader.Samples(0);
            if (pcm is null || pcm.Length == 0) { Console.WriteLine($"{Path.GetFileName(wav),-26}  <empty>"); continue; }
            float[] samples = ToFloat(pcm);
            float rawRms = HighPassSilence.PeakWindowRms(pcm);
            float hpRms = HighPassSilence.PeakHighPassRms(pcm);
            double secs = samples.Length / 16000.0;

            foreach (var (tag, p) in new[] { ("no", (string?)null), ("yes", prompt) })
            {
                var (text, avgConf, minConf, segs) = await DecodeDetailed(factory, samples, p);
                string engine = Engine(text);
                double compR = CompressionRatio(text);
                Console.WriteLine(
                    $"{Path.GetFileName(wav),-26} {secs,6:0.00} {rawRms,8:0.0000} {hpRms,8:0.0000} | {tag,2} {segs,4} " +
                    $"{avgConf,8:0.000} {minConf,8:0.000} {compR,6:0.00}  " +
                    $"{(engine.Length == 0 ? "<EMPTY>" : "KEPT"),-8} {Trunc(text, 48)}");
            }
        }
        factory.Dispose();

        Console.WriteLine();
        Console.WriteLine("avgConf/minConf = whisper SegmentData.Probability/MinProbability (token confidence; lower = less speech-like).");
        Console.WriteLine("compR = gzip ratio of the text (higher = more repetitive — a looped hallucination).");
        Console.WriteLine("engine = current output; <EMPTY> => \"No speech detected\". GOAL: silent rows <EMPTY>, real speech KEPT.");
        Console.WriteLine("Calibration: find a confidence threshold that cleanly splits the silent-press rows from the quiet-speech rows.");
        return 0;
    }

    /// Like Decode, but also returns whisper's per-segment confidence: avgConf = mean of
    /// SegmentData.Probability across segments; minConf = the least-confident token's
    /// MinProbability across segments (the most sensitive hallucination signal).
    private static async Task<(string text, double avgConf, double minConf, int segs)> DecodeDetailed(
        WhisperFactory factory, float[] samples, string? prompt)
    {
        var builder = factory.CreateBuilder()
            .WithLanguage("en")
            .WithTemperature(0.0f)
            .WithTemperatureInc(0.2f)
            .WithProbabilities();   // REQUIRED — else SegmentData.Probability/MinProbability are 0
        if (prompt is { Length: > 0 }) builder = builder.WithPrompt(prompt);

        await using var processor = builder.Build();
        var sb = new StringBuilder();
        double sum = 0; double minConf = 1.0; int segs = 0;
        await foreach (var seg in processor.ProcessAsync(samples))
        {
            sb.Append(seg.Text);
            sum += seg.Probability;
            if (seg.MinProbability < minConf) minConf = seg.MinProbability;
            segs++;
        }
        return (sb.ToString().Trim(), segs > 0 ? sum / segs : 0.0, segs > 0 ? minConf : 0.0, segs);
    }

    /// gzip compression ratio of the decoded text (whisper.cpp's own repetition signal):
    /// rawBytes / compressedBytes. A looped hallucination ("you can't see it, but you
    /// can't see it.") compresses far better than varied real speech.
    private static double CompressionRatio(string text)
    {
        if (string.IsNullOrEmpty(text)) return 0;
        byte[] raw = Encoding.UTF8.GetBytes(text);
        using var ms = new MemoryStream();
        using (var gz = new System.IO.Compression.GZipStream(
                   ms, System.IO.Compression.CompressionLevel.Optimal, leaveOpen: true))
            gz.Write(raw, 0, raw.Length);
        return raw.Length / (double)ms.Length;
    }
}
