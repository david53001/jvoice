using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using JVoice.Core.Models;

namespace JVoice.App.Whisper;

/// Locates, downloads, and verifies the GGML model files whisper.cpp loads.
///
/// Windows analog of WhisperModelLocator (TranscriptionManager.swift): the point
/// is to only ever hand the engine a *complete* model. WhisperKit's failure mode
/// was a half-finished .mlmodelc folder missing weight.bin; ours is a truncated
/// .bin. We download to "<file>.part", verify size (+ SHA-256 when known), then
/// atomically rename — so a crashed/cancelled download never leaves a usable-
/// looking-but-broken model on disk.
internal sealed class WhisperModelStore
{
    /// %LOCALAPPDATA%\JVoice\models\
    public string ModelsDirectory { get; }

    private readonly HttpClient _http;

    public WhisperModelStore(string? modelsDirectory = null, HttpClient? httpClient = null)
    {
        ModelsDirectory = modelsDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JVoice", "models");
        Directory.CreateDirectory(ModelsDirectory);
        _http = httpClient ?? new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
    }

    /// Base URL for the ggerganov/whisper.cpp GGML files on Hugging Face.
    private const string BaseUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

    private sealed record ModelInfo(string FileName, string Url, long ExpectedBytes, string? Sha256);

    /// The download manifest. ExpectedBytes and Sha256 were recorded at execution
    /// time (Task 2 Step 1) from Hugging Face. Sha256 is null for the larger models
    /// (size is still verified — catches truncation). Tiny has a real SHA-256 (the
    /// automated Task 6 verification depends on it).
    private static readonly IReadOnlyDictionary<WhisperModelOption, ModelInfo> Manifest =
        new Dictionary<WhisperModelOption, ModelInfo>
        {
            [WhisperModelOption.Tiny] = new(
                "ggml-tiny.bin",
                BaseUrl + "ggml-tiny.bin",
                ExpectedBytes: 77_691_713,
                Sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
            [WhisperModelOption.Base] = new(
                "ggml-base.bin",
                BaseUrl + "ggml-base.bin",
                ExpectedBytes: 147_951_465,
                Sha256: null),                        // size-only; record on first real download
            [WhisperModelOption.Small] = new(
                "ggml-small.bin",
                BaseUrl + "ggml-small.bin",
                ExpectedBytes: 487_601_967,
                Sha256: null),
            [WhisperModelOption.LargeTurbo] = new(
                "ggml-large-v3-turbo-q5_0.bin",
                BaseUrl + "ggml-large-v3-turbo-q5_0.bin",
                ExpectedBytes: 574_041_195,
                Sha256: null),
        };

    /// The expected on-disk path (whether or not it exists / is complete).
    public string PathFor(WhisperModelOption model)
        => Path.Combine(ModelsDirectory, model.GgmlFileName());

    /// The path of a *complete* model (exists + correct size), or null.
    /// Cheap: does NOT hash. Full integrity is enforced at download time.
    public string? CompleteModelPath(WhisperModelOption model)
    {
        var info = Manifest[model];
        string path = Path.Combine(ModelsDirectory, info.FileName);
        if (!File.Exists(path)) return null;
        try
        {
            long len = new FileInfo(path).Length;
            return len == info.ExpectedBytes ? path : null;
        }
        catch (IOException) { return null; }
    }

    /// Ensure the model is present and complete, downloading it if needed.
    /// Returns the verified local path.
    public async Task<string> EnsureAsync(
        WhisperModelOption model, IProgress<double>? progress, CancellationToken ct)
    {
        var existing = CompleteModelPath(model);
        if (existing is not null) return existing;
        await DownloadAsync(model, progress ?? new Progress<double>(), ct).ConfigureAwait(false);
        return CompleteModelPath(model)
            ?? throw new InvalidOperationException(
                $"Model {model.GgmlFileName()} still incomplete after download.");
    }

    /// Download to "<file>.part", verify size (+ SHA-256 when known), atomic-rename.
    /// progress reports 0.0–1.0 (NaN when the server doesn't send Content-Length).
    public async Task DownloadAsync(
        WhisperModelOption model, IProgress<double> progress, CancellationToken ct)
    {
        var info = Manifest[model];
        string finalPath = Path.Combine(ModelsDirectory, info.FileName);
        string partPath = finalPath + ".part";

        // Start clean — a stale .part from a prior crash is never resumed (simpler,
        // and HF blobs are immutable so a fresh download is always correct).
        try { if (File.Exists(partPath)) File.Delete(partPath); } catch (IOException) { }

        using (var resp = await _http
                   .GetAsync(info.Url, HttpCompletionOption.ResponseHeadersRead, ct)
                   .ConfigureAwait(false))
        {
            resp.EnsureSuccessStatusCode();
            long? total = resp.Content.Headers.ContentLength;
            await using var src = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            await using var dst = new FileStream(
                partPath, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20, useAsync: true);

            var buffer = new byte[1 << 20];
            long readTotal = 0;
            int n;
            while ((n = await src.ReadAsync(buffer.AsMemory(0, buffer.Length), ct).ConfigureAwait(false)) > 0)
            {
                await dst.WriteAsync(buffer.AsMemory(0, n), ct).ConfigureAwait(false);
                readTotal += n;
                progress.Report(total is > 0 ? (double)readTotal / total.Value : double.NaN);
            }
        }

        // Verify before exposing the file under its real name.
        long actualBytes;
        try { actualBytes = new FileInfo(partPath).Length; }
        catch (IOException ex) { SafeDelete(partPath); throw new InvalidOperationException("Download verification failed (size unreadable).", ex); }

        if (actualBytes != info.ExpectedBytes)
        {
            SafeDelete(partPath);
            throw new InvalidOperationException(
                $"Downloaded {info.FileName} is {actualBytes} bytes; expected {info.ExpectedBytes}.");
        }

        if (info.Sha256 is { } expectedHash)
        {
            string actualHash = await ComputeSha256Async(partPath, ct).ConfigureAwait(false);
            if (!string.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
            {
                SafeDelete(partPath);
                throw new InvalidOperationException(
                    $"SHA-256 mismatch for {info.FileName}: got {actualHash}, expected {expectedHash}.");
            }
        }

        // Atomic publish. If a complete file appeared meanwhile (race), keep it and drop our .part.
        try
        {
            if (File.Exists(finalPath)) { SafeDelete(partPath); return; }
            File.Move(partPath, finalPath);
        }
        catch (IOException)
        {
            if (File.Exists(finalPath)) { SafeDelete(partPath); return; }
            throw;
        }
        progress.Report(1.0);
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken ct)
    {
        await using var fs = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20, useAsync: true);
        using var sha = SHA256.Create();
        byte[] hash = await sha.ComputeHashAsync(fs, ct).ConfigureAwait(false);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static void SafeDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { }
    }
}
