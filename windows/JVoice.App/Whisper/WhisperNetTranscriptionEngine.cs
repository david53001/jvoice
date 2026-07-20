using System.IO;
using System.Text;
using JVoice.App.Platform;
using JVoice.Core;
using JVoice.Core.Audio;
using JVoice.Core.Models;
using JVoice.Core.Policy;
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
    private readonly EngineTuning _tuning;
    // When true, whisper runs its "translate" task: output is English regardless of the
    // spoken/source _language. Immutable per engine (a toggle rebuilds the engine, like _language).
    private readonly bool _translate;

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
        WhisperModelStore store,
        EngineTuning? tuning = null,
        bool translate = false)
    {
        _model = model;
        _language = language;
        _vocabulary = vocabulary ?? Array.Empty<string>();
        _useVocabularyPrompt = useVocabularyPrompt;
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _tuning = tuning ?? EngineTuning.Default;
        _translate = translate;
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
            // runtime (Vulkan on this dev machine — CUDA needs the toolkit; else CPU).
            // Flash attention is a FACTORY option (not a per-decode builder knob). It is a
            // clean win on CUDA, a coin-flip on Vulkan (needs NVIDIA coopmat2), and a
            // REGRESSION on CPU — so it is force-disabled in the cpu publish flavor.
            bool useFlash = _tuning.UseFlashAttention;
#if JVOICE_CPU
            useFlash = false; // flash attention degrades CPU decode (whisper.cpp PR #2152)
#endif
            return WhisperFactory.FromPath(
                modelPath, new WhisperFactoryOptions { UseFlashAttention = useFlash });
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
        double audioSeconds = pcm.Length / 16_000.0;

        // Same decode-and-recover policy as Swift decodeRecoveringFromRegurgitation:
        // prompted decode; on regurgitation/empty, a prompt-free re-decode. One decode
        // path (DecodeSamplesAsync) serves both whole-file and chunk transcription.
        // NonSpeechAnnotation.Reduce maps a whole-transcript annotation to "" (no-speech).
        // `lastOutcome` tracks the segment coverage of the LAST decode executed — i.e. the
        // one whose text RegurgitationRecovery returned (calls are sequential) — for the
        // §7 #39 tail-coverage guard below. The witness/tail decodes deliberately do NOT
        // update it.
        DecodeOutcome lastOutcome = default;
        string guarded = NonSpeechAnnotation.Reduce(await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            async usePrompt =>
            {
                var outcome = await DecodeSamplesAsync(samples, factory, usePrompt, ct).ConfigureAwait(false);
                lastOutcome = outcome;
                DiagnosticLog.Write(
                    $"Engine decode prompt={(usePrompt ? "on" : "off")} chars={outcome.Text.Length} " +
                    $"segs={outcome.SegmentCount} lastEnd={outcome.LastSegmentEndSeconds:0.00}s " +
                    $"audio={audioSeconds:0.00}s rawRms={rawRms:0.0000}");
                return outcome.Text;
            }).ConfigureAwait(false));

        // §7 #38 silence-hallucination gate: on a NEAR-SILENT clip the prompted decode can
        // confidently invent text ("you're welcome.") that escapes the blocklist. Measured
        // discriminator: the UNPROMPTED decode of the same audio collapses to a stock phrase
        // the blocklist reduces to empty (10/10 silent presses) while keeping real quiet
        // speech (7/7). So near-silence only TRIGGERS a witness decode without the prompt —
        // an empty witness means no-speech; a non-empty one vouches for the prompted text.
        // Skipped when no prompt is active (the decode already was unprompted). Whole-file
        // path only: short silent presses never produce a completed streaming chunk, and a
        // silent chunk already falls back losslessly via the empty-chunk policy.
        if (guarded.Length > 0 && _useVocabularyPrompt
            && SilenceHallucinationGate.ShouldVerify(rawRms, guarded)
            && await CurrentPromptAsync().ConfigureAwait(false) is { Length: > 0 })
        {
            string witness = TextProcessor.RemoveWhisperHallucinations(NonSpeechAnnotation.Reduce(
                (await DecodeSamplesAsync(samples, factory, usePrompt: false, ct).ConfigureAwait(false)).Text));
            guarded = SilenceHallucinationGate.Resolve(guarded, witness);
            DiagnosticLog.Write(
                $"Engine witness rawRms={rawRms:0.0000} witnessChars={witness.Length} -> " +
                (guarded.Length == 0 ? "no-speech" : "kept"));
        }

        // §7 #42 phrase-loop guard: on a long dictation the PROMPTED decode can lock into
        // whisper's classic repetition loop ("You're not a man of Caesar." × 16 on the real
        // clip capture-20260720-225708-670.wav) MID-transcript, overwriting real speech
        // while claiming full timestamp coverage — invisible to RepetitionGuard (trailing,
        // vocab-dense runs only) and to the tail guard (no uncovered tail). Measured on the
        // real clip: the UNPROMPTED decode of the same audio is clean and restores the
        // swallowed words — so a detected loop triggers a witness re-decode without the
        // prompt (RegurgitationRecovery's remedy), and PhraseLoopGuard.Resolve prefers that
        // witness, else deterministically collapses the run. Looped text can never paste.
        if (guarded.Length > 0 && PhraseLoopGuard.HasLoop(guarded))
        {
            string loopWitness = "";
            if (_useVocabularyPrompt && await CurrentPromptAsync().ConfigureAwait(false) is { Length: > 0 })
                loopWitness = TextProcessor.RemoveWhisperHallucinations(NonSpeechAnnotation.Reduce(
                    (await DecodeSamplesAsync(samples, factory, usePrompt: false, ct).ConfigureAwait(false)).Text));
            string healed = PhraseLoopGuard.Resolve(guarded, loopWitness);
            DiagnosticLog.Write(
                $"Engine phraseLoop chars={guarded.Length} witnessChars={loopWitness.Length} -> " +
                $"{(loopWitness.Length > 0 ? "witness" : "collapsed")} ({healed.Length} chars)");
            guarded = healed;
        }

        // §7 #43 sparse-transcript guard: on a long dictation the PROMPTED decode can
        // silently SKIP whole stretches of speech — the real clip capture-20260720-231246-541
        // .wav (32 s) decoded to just its head + tail (61 chars ≈ 1.9 chars/s) with the last
        // segment near the audio end, so the loop, repetition, tail, and silence guards were
        // all blind. Measured on the 2026-07-20 30-clip sweep: legitimate ≥10 s dictation
        // never dips below 8.9 chars/s, so conspicuous sparseness TRIGGERS an unprompted
        // witness re-decode; the witness replaces the prompted text only when it carries ≥2×
        // the characters (the skip's witness was 9.3× — legit drift measured ≤1.1×). When the
        // witness is adopted, its segment coverage drives the tail guard below.
        if (guarded.Length > 0 && _useVocabularyPrompt
            && SparseTranscriptGuard.ShouldVerify(audioSeconds, guarded)
            && await CurrentPromptAsync().ConfigureAwait(false) is { Length: > 0 })
        {
            var witnessOutcome = await DecodeSamplesAsync(samples, factory, usePrompt: false, ct).ConfigureAwait(false);
            string witness = TextProcessor.RemoveWhisperHallucinations(
                NonSpeechAnnotation.Reduce(witnessOutcome.Text));
            string resolved = SparseTranscriptGuard.Resolve(guarded, witness);
            bool adopted = !ReferenceEquals(resolved, guarded);
            if (adopted) lastOutcome = witnessOutcome;
            DiagnosticLog.Write(
                $"Engine sparseGuard chars={guarded.Length} audio={audioSeconds:0.00}s " +
                $"witnessChars={witness.Length} -> {(adopted ? "witness" : "kept")}");
            guarded = resolved;
        }

        // §7 #39 tail-coverage guard: the decode sometimes ends EARLY on David's quiet
        // audio — EOT after the louder leading clause — leaving trailing words that ARE in
        // the WAV untranscribed (confirmed 2026-07-02 23:58: 3.48 s of audio on disk,
        // decode covered ~the first clause only; he re-dictated). Whisper's own segment
        // timestamps expose it: a big uncovered tail after the last segment. Recover by
        // decoding JUST the uncovered tail (unprompted, witness-style, fully reduced) and
        // appending what the model finds; a trailing thinking-pause decodes to empty and
        // merges to nothing. Trigger is timestamp coverage — never an RMS level (§7 #21).
        if (guarded.Length > 0 && TailCoverageGuard.ShouldRecover(audioSeconds, lastOutcome.LastSegmentEndSeconds))
        {
            int startSample = Math.Clamp((int)(lastOutcome.LastSegmentEndSeconds * 16_000), 0, pcm.Length);
            string tailText = "";
            if (pcm.Length - startSample >= 16_000) // ≥1 s — enough audio to decode on its own
            {
                var tailOutcome = await DecodeSamplesAsync(
                    WavTail.FloatSamples(pcm.AsSpan(startSample)), factory, usePrompt: false, ct).ConfigureAwait(false);
                tailText = TextProcessor.RemoveWhisperHallucinations(NonSpeechAnnotation.Reduce(tailOutcome.Text));
            }
            string merged = TailCoverageGuard.Merge(guarded, tailText);
            DiagnosticLog.Write(
                $"Engine tailGuard lastEnd={lastOutcome.LastSegmentEndSeconds:0.00}s audio={audioSeconds:0.00}s " +
                $"uncovered={audioSeconds - lastOutcome.LastSegmentEndSeconds:0.00}s tail=\"{tailText}\" -> " +
                (merged.Length > guarded.Length ? "RECOVERED" : "unchanged"));
            guarded = merged;
        }

        if (guarded.Length == 0)
            throw TranscriptionException.EmptyTranscript(
                $"no-speech (model empty/annotation) hpRms={hpRms:0.0000} rawRms={rawRms:0.0000} " +
                $"ratio={(rawRms > 0 ? hpRms / rawRms : 0):0.00}");
        return guarded;
    }

    // ---- the single shared sample decode ------------------------------------

    /// One decode's result plus its segment coverage: how far (in seconds) whisper's
    /// LAST segment claims to reach into the audio. Fuel for the §7 #39 tail-coverage
    /// guard — an early-EOT truncation shows up as LastSegmentEndSeconds ≪ audio length.
    private readonly record struct DecodeOutcome(string Text, double LastSegmentEndSeconds, int SegmentCount);

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
    private async Task<DecodeOutcome> DecodeSamplesAsync(
        float[] samples, WhisperFactory factory, bool usePrompt, CancellationToken ct)
    {
        string? promptText = usePrompt ? await CurrentPromptAsync().ConfigureAwait(false) : null;

        var builder = factory.CreateBuilder()
            .WithLanguage(_language.WhisperCode());   // fixed language, no auto-detect

        // Optional "translate" task: emit English regardless of the spoken source language.
        if (_translate)
            builder = builder.WithTranslate();

        builder = ApplyTemperatureFallback(builder);

        // Decode threads — only set when configured (null = whisper's own min(4, logical) default).
        if (_tuning.Threads is int threads)
            builder = builder.WithThreads(threads);

        // Per-clip encoder context: a short utterance doesn't need the full 30 s window, so a
        // smaller audio_ctx skips wasted encoder work. FixedAudioContext (bench A/B) wins; else
        // the adaptive policy; else leave whisper's full default. Sized from THIS decode's sample
        // count, so both the whole-file and the 15–25 s streaming-chunk paths are covered.
        int? audioCtx = _tuning.FixedAudioContext
            ?? (_tuning.AdaptiveAudioContext
                ? WhisperTuning.AudioContextForSamples(samples.Length)
                : null);
        if (audioCtx is int ctx)
            builder = builder.WithAudioContextSize(ctx);

        if (promptText is { Length: > 0 })
            builder = builder.WithPrompt(promptText);

        await using var processor = builder.Build();

        var sb = new StringBuilder();
        double lastEnd = 0;
        int segmentCount = 0;
        await foreach (var segment in processor.ProcessAsync(samples, ct).ConfigureAwait(false))
        {
            sb.Append(segment.Text);
            segmentCount++;
            double end = segment.End.TotalSeconds;
            if (end > lastEnd) lastEnd = end;
        }

        string text = sb.ToString().Trim();
        // Remove "[BLANK_AUDIO]"-style decoder sentinels that leak in on silence.
        return new DecodeOutcome(TextProcessor.StripDecoderArtifacts(text), lastEnd, segmentCount);
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
        // an empty chunk decode as "fall back to whole-file" (lossless), never a silent drop
        // (and, since §7 #39, as "confirmed silence — skip" for a silent-classified chunk).
        string text = NonSpeechAnnotation.Reduce(await RegurgitationRecovery.Decode(
            _useVocabularyPrompt,
            vocabulary,
            async usePrompt =>
                (await DecodeSamplesAsync(samples, factory, usePrompt, ct).ConfigureAwait(false)).Text)
            .ConfigureAwait(false));

        // §7 #42: a chunk decode that degenerated into a phrase loop must never be pasted —
        // and collapsing it here would hide the speech the loop overwrote. Throwing fails
        // the session (its catch → whole-file fallback, lossless by contract), where the
        // whole-file phrase-loop guard heals via the unprompted witness. Deliberately NOT
        // "" — an empty decode of a silent-classified chunk means "confirmed silence, skip",
        // which would silently drop the chunk's real speech.
        if (PhraseLoopGuard.HasLoop(text))
        {
            DiagnosticLog.Write($"Engine chunk phraseLoop chars={text.Length} -> chunk decode failed (whole-file fallback)");
            throw TranscriptionException.DegenerateDecode($"streaming chunk, {text.Length} chars");
        }

        // §7 #43: a conspicuously sparse chunk decode is the same skip fingerprint the
        // whole-file sparse guard catches (and the #41 lesson says never trust a suspicious
        // chunk decode). Failing the session is lossless by contract — the whole-file
        // fallback re-decodes everything and its own sparse guard heals via the witness.
        // Deliberately NOT "" — an empty decode of a silent-classified chunk means
        // "confirmed silence, skip", which would silently drop the chunk's real speech.
        double chunkSeconds = samples.Length / 16_000.0;
        if (text.Length > 0 && SparseTranscriptGuard.ShouldVerify(chunkSeconds, text))
        {
            DiagnosticLog.Write(
                $"Engine chunk sparse chars={text.Length} audio={chunkSeconds:0.00}s -> " +
                "chunk decode failed (whole-file fallback)");
            throw TranscriptionException.DegenerateDecode(
                $"sparse streaming chunk, {text.Length} chars over {chunkSeconds:0.0}s");
        }
        return text;
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
            pollMilliseconds: pollMilliseconds,
            log: DiagnosticLog.Write);
    }
}
