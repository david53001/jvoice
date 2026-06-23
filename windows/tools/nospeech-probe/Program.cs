using System.Text;
using JVoice.Core.Audio;
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
}
