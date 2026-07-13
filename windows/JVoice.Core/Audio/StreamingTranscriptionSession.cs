namespace JVoice.Core.Audio;

/// Transcribes completed speech chunks of a still-growing WAV while recording.
/// Port of StreamingTranscriptionSession.swift. Any failure → Finish() returns null and
/// the caller falls back to whole-file transcription (never a silent drop). Audio is
/// never lost.
///
/// WINDOWS DIVERGENCES from Swift (both David's-mic bugs; his real speech peaks at
/// 0.0005–0.004 window-RMS, BELOW ChunkPlanner's 0.005 silence floor, so an absolute RMS
/// classification cannot be trusted to mean "no speech" here):
///  #1 (2026-06-23, bug #2): a FINAL tail judged silent returns null → lossless
///     whole-file fallback instead of being dropped.
///  #2 (2026-07-03, §7 #39): a MID-STREAM chunk cut as "silent" is DECODED like any
///     other chunk instead of being dropped unheard. The model decides: an empty decode
///     confirms silence (skip losslessly — NOT a failure; that policy stays reserved for
///     non-silent chunks), a non-empty decode is rescued speech and is appended. Decode
///     errors still fail the session → whole-file fallback.
public sealed class StreamingTranscriptionSession
{
    private readonly Func<float[], Task<string>> _transcribe;
    private readonly ChunkPlanner.Config _config;
    private readonly int _pollMs;
    // Optional diagnostics sink (e.g. the app's DiagnosticLog). Never affects behavior.
    private readonly Action<string>? _log;

    private string? _url;
    private WavTailReader? _reader;
    private int _consumedSamples;
    private readonly List<string> _pieces = new();
    private Task? _pollTask;
    private CancellationTokenSource? _cts;
    private volatile bool _failed;
    private volatile bool _cancelled;
    private bool _finished;
    private int _openRetriesRemaining = 10;

    public StreamingTranscriptionSession(
        Func<float[], Task<string>> transcribe,
        ChunkPlanner.Config? config = null,
        int pollMilliseconds = 1000,
        Action<string>? log = null)
    {
        _transcribe = transcribe;
        _config = config ?? new ChunkPlanner.Config();
        _pollMs = pollMilliseconds;
        _log = log;
    }

    public void Start(string path)
    {
        if (_pollTask != null || _cancelled || _failed || _finished) return;
        _url = path;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        _pollTask = Task.Run(() => RunPollLoop(ct), ct);
    }

    /// Stop polling, transcribe whatever remains, return the combined raw transcript.
    /// null ⇒ the caller MUST fall back to whole-file transcription.
    public async Task<string?> Finish()
    {
        if (_finished) return null;
        _finished = true;
        _cts?.Cancel();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;

        if (_failed || _cancelled || _url is null)
        {
            _log?.Invoke($"Stream finish -> null (failed={_failed} cancelled={_cancelled})");
            return null;
        }
        if (_consumedSamples <= 0 && _pieces.Count == 0) return null;

        _reader ??= WavTailReader.Open(_url);
        if (_reader is null) return null;
        var tail = _reader.Samples(_consumedSamples);
        if (tail is null) return null;

        // Drain any backlog the poll loop didn't get to. Terminates: every cut shrinks tail.
        // Silent-classified cuts are decoded too (divergence #2) — empty decode ⇒ skip.
        while (true)
        {
            var decision = ChunkPlanner.Plan(tail, _config);
            if (decision.Kind != ChunkPlanner.DecisionKind.Cut) break;
            if (!await AppendPiece(
                    WavTail.FloatSamples(tail.AsSpan(0, decision.AtSample)),
                    emptyMeansSilence: decision.IsSilent))
                return null;
            tail = tail[decision.AtSample..];
        }
        if (tail.Length > 0)
        {
            // The FINAL tail is the user's last words. WINDOWS DIVERGENCE from Swift
            // (2026-06-23, bug #2): do NOT drop it on the strength of the absolute
            // SilenceRmsFloor. On David's low-level mic his quiet trailing clause reads as
            // "silent" here (rawRMS ≈ 0.004 ≈ his room hum), so dropping it cut off the end
            // of his sentences. A tail judged silent now returns null → the caller re-covers
            // the WHOLE recording losslessly via whole-file, where whisper authoritatively
            // yields empty on true silence and full text on quiet speech. A non-silent tail
            // decodes as before, so normal-level users (loud tail) are unaffected and keep
            // the streaming benefit. The never-silently-drop invariant is preserved: an
            // empty decode also returns null → whole-file fallback.
            if (ChunkPlanner.IsSilent(tail, _config))
            {
                _log?.Invoke($"Stream finish -> null (silent final tail, {tail.Length} samples -> whole-file)");
                return null;
            }
            if (!await AppendPiece(WavTail.FloatSamples(tail), emptyMeansSilence: false))
                return null;
        }

        string joined = string.Join(" ", _pieces).Trim();
        _log?.Invoke($"Stream finish -> {(joined.Length == 0 ? "null (no pieces)" : $"{_pieces.Count} pieces, {joined.Length} chars")}");
        return joined.Length == 0 ? null : joined;
    }

    /// Abandon this recording: discard everything; Finish() returns null if ever called.
    /// Joins the poll task so no chunk decode is still in flight when Cancel returns.
    public async Task Cancel()
    {
        _cancelled = true;
        _cts?.Cancel();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;
        _pieces.Clear();
    }

    /// Decode one chunk and append its text. `emptyMeansSilence` carries ChunkPlanner's
    /// classification: for a silent-classified chunk an empty decode is the model
    /// CONFIRMING silence (skip, keep going); for a non-silent chunk an empty decode
    /// would silently delete speech, so it fails the session → whole-file fallback.
    private async Task<bool> AppendPiece(float[] samples, bool emptyMeansSilence)
    {
        try
        {
            string text = await _transcribe(samples);
            if (text.Length == 0)
            {
                if (emptyMeansSilence)
                {
                    _log?.Invoke($"Stream chunk {samples.Length} samples: silent-classified, model confirmed empty -> skipped");
                    return true;
                }
                _failed = true; // non-silent chunk decoded to nothing → never silently drop
                _log?.Invoke($"Stream FAILED: non-silent chunk ({samples.Length} samples) decoded empty");
                return false;
            }
            _pieces.Add(text);
            return true;
        }
        catch (Exception ex)
        {
            _failed = true;
            _log?.Invoke($"Stream FAILED: chunk decode threw {ex.GetType().Name}");
            return false;
        }
    }

    private async Task RunPollLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !_failed && !_cancelled)
        {
            await PollOnce(ct);
            try { await Task.Delay(_pollMs, ct); }
            catch (OperationCanceledException) { break; }
        }
    }

    private async Task PollOnce(CancellationToken ct)
    {
        if (_url is null) { _failed = true; return; }
        if (_reader is null)
        {
            if (!File.Exists(_url)) { _failed = true; return; } // recorder torn down
            var opened = WavTailReader.Open(_url);
            if (opened is null)
            {
                _openRetriesRemaining--;
                if (_openRetriesRemaining <= 0) _failed = true;
                return;
            }
            _reader = opened;
        }

        var unconsumed = _reader.Samples(_consumedSamples);
        if (unconsumed is null) { _failed = true; return; } // file vanished

        var decision = ChunkPlanner.Plan(unconsumed, _config);
        if (decision.Kind != ChunkPlanner.DecisionKind.Cut) return;

        // Divergence #2 (§7 #39): silent-classified chunks are decoded too — on David's
        // low-level mic "silent" can be a whole clause of real speech, and dropping it
        // unheard deleted the middle/end of long dictations. The model is the authority:
        // empty ⇒ true silence, skip; non-empty ⇒ speech, keep.
        var chunk = WavTail.FloatSamples(unconsumed.AsSpan(0, decision.AtSample));
        try
        {
            string text = await _transcribe(chunk);
            if (ct.IsCancellationRequested || _cancelled) return; // re-cover via finish/fallback
            if (text.Length == 0)
            {
                if (!decision.IsSilent)
                {
                    _failed = true; // non-silent chunk decoded to nothing → never silently drop
                    _log?.Invoke($"Stream FAILED: non-silent chunk ({decision.AtSample} samples) decoded empty");
                    return;
                }
                _log?.Invoke($"Stream chunk cut@{decision.AtSample}: silent-classified, model confirmed empty -> skipped");
            }
            else
            {
                _pieces.Add(text);
                if (decision.IsSilent)
                    _log?.Invoke($"Stream chunk cut@{decision.AtSample}: silent-classified but decoded {text.Length} chars -> RESCUED");
            }
            _consumedSamples += decision.AtSample;
        }
        catch (Exception ex)
        {
            _failed = true;
            _log?.Invoke($"Stream FAILED: chunk decode threw {ex.GetType().Name}");
        }
    }
}
