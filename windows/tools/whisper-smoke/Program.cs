using JVoice.App.Whisper;
using JVoice.Core.Models;

namespace JVoice.Tools.WhisperSmoke;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine(
                "usage: whisper-smoke <audio.wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab \"a,b\"] [--no-prompt]");
            return 64;
        }

        string audioPath = args[0];
        if (!File.Exists(audioPath))
        {
            Console.Error.WriteLine($"no such file: {audioPath}");
            return 66;
        }

        var model = WhisperModelOption.Tiny;
        int mi = Array.IndexOf(args, "--model");
        if (mi >= 0 && args.Length > mi + 1)
            model = args[mi + 1] switch
            {
                "tiny" => WhisperModelOption.Tiny,
                "base" => WhisperModelOption.Base,
                "small" => WhisperModelOption.Small,
                "large" => WhisperModelOption.LargeTurbo,
                _ => WhisperModelOption.Tiny,
            };

        var language = TranscriptionLanguage.English;
        int li = Array.IndexOf(args, "--lang");
        if (li >= 0 && args.Length > li + 1 && args[li + 1] is "ro" or "romanian")
            language = TranscriptionLanguage.Romanian;

        var vocab = new List<string>();
        int vi = Array.IndexOf(args, "--vocab");
        if (vi >= 0 && args.Length > vi + 1)
            vocab = args[vi + 1].Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();

        bool usePrompt = !args.Contains("--no-prompt");

        var store = new WhisperModelStore();
        Console.WriteLine($"models dir: {store.ModelsDirectory}");
        var progress = new Progress<double>(p =>
        {
            if (!double.IsNaN(p)) Console.Error.Write($"\rdownload: {p * 100,5:0.0}%   ");
        });
        // Ensure the model up front so download progress is visible.
        await store.EnsureAsync(model, progress, CancellationToken.None);
        Console.Error.WriteLine();

        var engine = new WhisperNetTranscriptionEngine(model, language, vocab, usePrompt, store);
        await engine.PrewarmAsync();
        Console.WriteLine($"runtime: {WhisperRuntime.Describe()}");

        try
        {
            string text = await engine.TranscribeAsync(audioPath, CancellationToken.None);
            Console.WriteLine($"transcript: \"{text}\"");
            return text.Trim().Length == 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"transcription failed: {ex.Message}");
            return 1;
        }
    }
}
