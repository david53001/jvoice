using System.IO;
using System.Text;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Text;
using JVoice.Core.Transcription;
using Whisper.net;

namespace JVoice.App.Whisper;

/// On-device speech engine backed by whisper.cpp (via Whisper.net) and GGML models.
/// Faithful behavioral port of WhisperKitTranscriptionEngine (TranscriptionManager.swift):
/// load-dedupe, prewarm, whole-file + chunk decode both guarded by RegurgitationRecovery,
/// vocabulary-prompt biasing with a cache invalidated on vocabulary change, decoder-
/// artifact stripping, fixed language, ~2 temperature fallbacks. The two WhisperKit-1.0.0
/// workarounds (SuppressBlankFilter, single-window timestamp gate) are intentionally NOT
/// ported — whisper.cpp doesn't need them (overview §6.3).
internal sealed class WhisperNetTranscriptionEngine : ITranscriptionEngine
{
    private readonly WhisperModelOption _model;
    private readonly TranscriptionLanguage _language;
    private readonly bool _useVocabularyPrompt;
    private readonly WhisperModelStore _store;

    // Guards model load/dedupe AND the prompt-text cache recompute (the actor analog).
    private readonly SemaphoreSlim _gate = new(1, 1);

    private IReadOnlyList<string> _vocabulary;

    /// The vocabulary prompt string, computed once per vocabulary change.
    /// null = nothing to bias toward; _promptComputed distinguishes "computed → null"
    /// from "not yet computed" (mirrors Swift's `cachedPromptTokens: [Int]?`).
    private string? _cachedPromptText;
    private bool _promptComputed;

    private WhisperFactory? _factory;
    private Task<WhisperFactory>? _loadTask;

    public WhisperNetTranscriptionEngine(
        WhisperModelOption model,
        TranscriptionLanguage language,
        IReadOnlyList<string> vocabulary,
        bool useVocabularyPrompt,
        WhisperModelStore store)
    {
        _model = model;
        _language = language;
        _vocabulary = vocabulary ?? Array.Empty<string>();
        _useVocabularyPrompt = useVocabularyPrompt;
        _store = store ?? throw new ArgumentNullException(nameof(store));
    }

    public async Task UpdateVocabularyAsync(IReadOnlyList<string> words)
    {
        words ??= Array.Empty<string>();
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (words.SequenceEqual(_vocabulary)) return; // no change → keep cache
            _vocabulary = words.ToArray();
            _cachedPromptText = null;
            _promptComputed = false;
        }
        finally { _gate.Release(); }
    }

    public Task<bool> IsReadyAsync() => Task.FromResult(_factory is not null);

    public async Task PrewarmAsync()
    {
        // Errors ignored — a failed prewarm just means the next TranscribeAsync
        // retries the load and surfaces the error (Swift `prewarm()` semantics).
        try { _ = await LoadFactoryAsync(CancellationToken.None).ConfigureAwait(false); }
        catch { /* swallow */ }
    }

    // ---- model load + dedupe -------------------------------------------------

    /// Load the WhisperFactory once, deduping concurrent callers (a background
    /// prewarm racing the first transcribe). Mirrors Swift loadWhisperKit/performLoad:
    /// the shared task is created under the gate; on failure the task is dropped so
    /// a later call retries; errors surface as TranscriptionException.ModelLoadFailed.
    private async Task<WhisperFactory> LoadFactoryAsync(CancellationToken ct)
    {
        if (_factory is { } ready) return ready;

        Task<WhisperFactory> task;
        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (_factory is { } already) return already;
            task = _loadTask ??= PerformLoadAsync(ct);
        }
        finally { _gate.Release(); }

        try
        {
            var factory = await task.ConfigureAwait(false);
            // Publish under the gate so concurrent callers see it atomically.
            await _gate.WaitAsync(ct).ConfigureAwait(false);
            try { _factory ??= factory; }
            finally { _gate.Release(); }
            return _factory!;
        }
        catch (Exception ex)
        {
            await _gate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
            try { _loadTask = null; }   // drop the failed task so a later call retries
            finally { _gate.Release(); }
            if (ex is TranscriptionException) throw;
            throw TranscriptionException.ModelLoadFailed(ex.Message);
        }
    }

    /// Download (if needed) the GGML file, then build the WhisperFactory from it.
    /// The download is the one allowed runtime network call (overview §5).
    private async Task<WhisperFactory> PerformLoadAsync(CancellationToken ct)
    {
        WhisperRuntime.EnsureLoaded();
        string modelPath = await _store.EnsureAsync(_model, progress: null, ct).ConfigureAwait(false);
        try
        {
            // WhisperFactory.FromPath loads the GGML weights and selects the native
            // runtime (CUDA on this dev machine, else Vulkan/CPU). Confirmed present
            // in Whisper.net 1.9.1 (Task 1 Step 7 probe).
            return WhisperFactory.FromPath(modelPath);
        }
        catch (Exception ex)
        {
            throw TranscriptionException.ModelLoadFailed(
                $"Failed to load GGML model {_model.GgmlFileName()}: {ex.Message}");
        }
    }

    // ---- vocabulary prompt cache --------------------------------------------

    /// The vocabulary prompt string, cached once per vocabulary change.
    /// Returns null when there's nothing to bias toward. MUST be called with the
    /// gate held (call CurrentPromptAsync from the decode paths).
    ///
    /// Swift cached encoded token IDs because WhisperKit took `promptTokens: [Int]`.
    /// Whisper.net's WithPrompt(string) tokenizes internally, so we cache the prompt
    /// STRING instead. The VocabularyPrompt.MaxPromptTokens cap was enforced post-
    /// tokenization in Swift; Whisper.net has no public token-trim hook, so we rely on
    /// VocabularyPrompt.Text's MaxWords=40 cap (the prompt string is short by design).
    private string? PromptTextLocked()
    {
        if (_promptComputed) return _cachedPromptText;
        _cachedPromptText = VocabularyPrompt.Text(_vocabulary); // null when empty/blank
        _promptComputed = true;
        return _cachedPromptText;
    }

    /// Gate-acquiring accessor for the decode paths.
    private async Task<string?> CurrentPromptAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { return PromptTextLocked(); }
        finally { _gate.Release(); }
    }

    /// Snapshot the vocabulary under the gate (RegurgitationRecovery needs it,
    /// and it can change between decodes).
    private async Task<IReadOnlyList<string>> CurrentVocabularyAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { return _vocabulary; }
        finally { _gate.Release(); }
    }

    // ---- whole-file decode path ---------------------------------------------

    public async Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)
    {
        if (!File.Exists(audioPath))
            throw TranscriptionException.AudioFileMissing(audioPath);

        // Read the PCM once (also validates the WAV). The recorder guarantees 16 kHz
        // mono 16-bit — exactly what both ChunkPlanner and whisper.cpp expect.
        short[] pcm = ReadWavPcm(audioPath);

        // No-speech is decided by the MODEL, not by the signal level. whisper.cpp decodes
        // even very quiet speech correctly (verified on-device down to rawRMS ≈ 0.001 —
        // below David's real ≈0.004), and on genuine no-speech it emits a NON-SPEECH
        // ANNOTATION ("[BLANK_AUDIO]", "[Music]", "(birds chirping)") — never a plausible
        // sentence. So we DECODE first, then map an annotation-only transcript to empty.
        //
        // This REPLACES the old absolute-RMS/spectral HighPassSilence pre-gate, which
        // rejected David's real quiet/short dictation: on his low-level mic his speech and
        // his room hum sit at the SAME ≈0.004 raw RMS (and 0.08–0.12 spectral ratio), so no
        // level/ratio floor can separate them — but whisper transcribes the one and
        // annotates the other. The hp/raw RMS are kept ONLY as diagnostics in the
        // empty-result message (so the log still records David's mic spectrum).
        // See NonSpeechAnnotation + docs/superpowers/plans/2026-06-23-windows-nospeech-and-tail-fix.md.
        float hpRms = HighPassSilence.PeakHighPassRms(pcm);
        float rawRms = HighPassSilence.PeakWindowRms(pcm);

        var factory = await LoadFactoryAsync(ct).ConfigureAwait(false);
        var vocabulary = await CurrentVocabularyAsync().ConfigureAwait(false);
        float[] samples = WavTail.FloatSamples(pcm);

        // Same decode-and-recover policy as Swift decodeRecoveringFromRegurgitation:
        // prompted decode; on regurgitation/empty, a prompt-free re-decode. One decode
        // path (DecodeSamplesAsync) serves both whole-file and chunk transcription.
        // NonSpeechAnnotation.Reduce maps a whole-transcript annotation to "" (no-speech).
        string guarded = NonSpeechAnnotation.Reduce(await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            usePrompt => DecodeSamplesAsync(samples, factory, usePrompt, ct)).ConfigureAwait(false));

        if (guarded.Length == 0)
            throw TranscriptionException.EmptyTranscript(
                $"no-speech (model empty/annotation) hpRms={hpRms:0.0000} rawRms={rawRms:0.0000} " +
                $"ratio={(rawRms > 0 ? hpRms / rawRms : 0):0.00}");
        return guarded;
    }

    // ---- the single shared sample decode ------------------------------------

    /// The single decode implementation for both the whole-file and chunk paths.
    /// Builds a fresh WhisperProcessor (cheap relative to the factory load),
    /// streams segments, joins them, and strips decoder artifacts.
    ///
    /// Builder configuration reproduces the Swift DecodingOptions:
    ///   - WithLanguage(code)         ← language fixed; NO detect-language pass
    ///   - WithPrompt(promptText)     ← vocabulary biasing (only when usePrompt && prompt != null)
    ///   - temperature fallback ≈ 2   ← WithTemperature(0) + WithTemperatureInc(0.2)
    ///   - NO timestamp suppression   ← Whisper.net 1.9.1 has no WithoutTimestamps(); whisper.cpp
    ///                                   does its own 30s windowing with context carry, so the full
    ///                                   transcript is produced and NOT truncated (verified Task 6
    ///                                   Step 5). This is the "timestamps on" position — the
    ///                                   documented Task 3 Step 9 fallback — so the dropped WhisperKit
    ///                                   isSingleWindowClip gate stays dropped. Do NOT add
    ///                                   WithSingleSegment() (it would force one segment / truncate).
    ///   - suppress_blank stays ON    ← we never call WithoutSuppressBlank(), so the WhisperKit
    ///                                   SuppressBlankFilter trap cannot occur (§6.3; verified T6 S4).
    private async Task<string> DecodeSamplesAsync(
        float[] samples, WhisperFactory factory, bool usePrompt, CancellationToken ct)
    {
        string? promptText = usePrompt ? await CurrentPromptAsync().ConfigureAwait(false) : null;

        var builder = factory.CreateBuilder()
            .WithLanguage(_language.WhisperCode());   // fixed language, no auto-detect

        builder = ApplyTemperatureFallback(builder);

        if (promptText is { Length: > 0 })
            builder = builder.WithPrompt(promptText);

        await using var processor = builder.Build();

        var sb = new StringBuilder();
        await foreach (var segment in processor.ProcessAsync(samples, ct).ConfigureAwait(false))
            sb.Append(segment.Text);

        string text = sb.ToString().Trim();
        // Remove "[BLANK_AUDIO]"-style decoder sentinels that leak in on silence.
        return TextProcessor.StripDecoderArtifacts(text);
    }

    /// Isolated so the temperature/threshold knobs are easy to adapt. Reproduces
    /// WhisperKit's temperatureFallbackCount = 2 approximately: start greedy at temp 0
    /// and allow escalated retries by temperature_inc when a window fails whisper.cpp's
    /// entropy/logprob gates. WithTemperature/WithTemperatureInc confirmed present in
    /// Whisper.net 1.9.1; entropy/logprob thresholds left at whisper.cpp defaults.
    private static WhisperProcessorBuilder ApplyTemperatureFallback(WhisperProcessorBuilder builder)
        => builder
            .WithTemperature(0.0f)
            .WithTemperatureInc(0.2f);

    /// Read a 16 kHz mono 16-bit PCM WAV into raw samples. The recorder (Phase 3)
    /// always writes this exact format. We reuse Core's WavTail header parser so there
    /// is one WAV truth in the repo; callers normalize via WavTail.FloatSamples.
    private static short[] ReadWavPcm(string audioPath)
    {
        var reader = WavTailReader.Open(audioPath)
            ?? throw TranscriptionException.UnsupportedAudioFile(audioPath);
        return reader.Samples(0)
            ?? throw TranscriptionException.UnsupportedAudioFile(audioPath);
    }

    // ---- chunk decode path (used by the streaming session, Task 4) ----------

    /// Decode a chunk of raw 16 kHz mono float samples cut by ChunkPlanner.
    /// Chunks are ≤ maxChunkSeconds by construction, but whisper.cpp windows
    /// internally regardless, so no special-casing is needed. Same regurgitation
    /// recovery as the whole-file path: an all-loop chunk reduces to "" and the
    /// streaming session treats that as a failure → lossless whole-file fallback.
    private async Task<string> TranscribeChunkSamplesAsync(float[] samples, CancellationToken ct)
    {
        var factory = await LoadFactoryAsync(ct).ConfigureAwait(false);
        var vocabulary = await CurrentVocabularyAsync().ConfigureAwait(false);
        // Reduce a whisper no-speech annotation chunk to "" — the streaming session treats
        // an empty chunk decode as "fall back to whole-file" (lossless), never a silent drop.
        return NonSpeechAnnotation.Reduce(await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            usePrompt => DecodeSamplesAsync(samples, factory, usePrompt, ct)).ConfigureAwait(false));
    }

    // ---- streaming session integration (Task 4) -----------------------------

    /// A streaming session bound to this engine, or null when no model is loaded.
    /// Default cadence = AppTimings.StreamingPollMs (1000 ms), matching the app.
    public Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()
        => Task.FromResult(MakeStreamingSession(JVoice.Core.AppTimings.StreamingPollMs));

    /// Parameterized variant so the bench can poll faster (e.g. 100 ms) when it
    /// grows the WAV at ~10× real time. NEVER triggers a model load: no loaded
    /// factory → null → the caller uses the whole-file fallback (Swift guard).
    ///
    /// A strong capture of `this` in the transcribe closure is correct: the engine
    /// outlives the session (the coordinator owns both and tears the session down on
    /// stop). The session itself catches decode exceptions and fails losslessly
    /// (Core StreamingTranscriptionSession.AppendPiece/PollOnce).
    internal StreamingTranscriptionSession? MakeStreamingSession(int pollMilliseconds)
    {
        if (_factory is null) return null;
        return new StreamingTranscriptionSession(
            transcribe: samples => TranscribeChunkSamplesAsync(samples, CancellationToken.None),
            config: new ChunkPlanner.Config(),
            pollMilliseconds: pollMilliseconds);
    }
}
