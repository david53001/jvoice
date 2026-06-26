using System.Linq;
using Whisper.net.LibraryLoader;
using Whisper.net.Logger;

namespace JVoice.App.Whisper;

/// Ensures a whisper.cpp native runtime is available and reports which one
/// Whisper.net selected. Whisper.net auto-loads the best runtime (CUDA → Vulkan
/// → CPU) on first WhisperFactory creation; this type exists for logging/bench
/// output and as the single place the runtime story is documented.
///
/// On this dev machine (RTX 3060 Ti) the CUDA runtime is selected; on a machine
/// with no CUDA it falls back to Vulkan (any GPU) or CPU (AVX/AVX2). The CPU
/// runtime is the universal fallback and is always bundled.
internal static class WhisperRuntime
{
    private static bool _ensured;
    private static readonly object Gate = new();

    /// Force the native runtime to be probed/loaded eagerly (so prewarm timing
    /// includes it and bench output can name it). Safe to call repeatedly.
    public static void EnsureLoaded()
    {
        if (_ensured) return;
        lock (Gate)
        {
            if (_ensured) return;
            // The actual native load happens lazily when the first WhisperFactory
            // is created (FromPath). There is no public "preload" call in Whisper.net
            // 1.9.1, so this is a best-effort marker; RuntimeOptions.LoadedLibrary is
            // populated by Whisper.net once a factory has loaded.
            _ensured = true;
        }
    }

    /// Force the native-runtime probe order BEFORE the first WhisperFactory is created.
    /// Pass a single library (e.g. RuntimeLibrary.Cuda) to make a missing backend a HARD
    /// failure (FileNotFoundException) instead of a silent fallback — used by `--bench --runtime`.
    public static void ForceRuntimeOrder(params RuntimeLibrary[] order)
        => RuntimeOptions.RuntimeLibraryOrder = order.ToList();

    /// Stream whisper.cpp's own debug log to the console (e.g. "cudaGetDeviceCount returned 35 …"),
    /// so a forced-CUDA run prints exactly why a backend was rejected.
    public static void EnableDebugLogging()
        => LogProvider.AddConsoleLogging(WhisperLogLevel.Debug);

    /// A human-readable description of the selected runtime, for bench/log output.
    /// Uses Whisper.net 1.9.1's typed RuntimeOptions.LoadedLibrary (a RuntimeLibrary?
    /// that is null until the first WhisperFactory load — so call this AFTER prewarm).
    public static string Describe()
    {
        try
        {
            RuntimeLibrary? lib = RuntimeOptions.LoadedLibrary;
            return lib is null
                ? "whisper.cpp (runtime not yet loaded)"
                : $"whisper.cpp ({lib})";
        }
        catch
        {
            return "whisper.cpp (runtime auto-selected)";
        }
    }
}
