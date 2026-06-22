namespace JVoice.Core.Audio;

/// Transcribes completed speech chunks of a still-growing WAV while recording.
/// Faithful port of StreamingTranscriptionSession.swift. Any failure → Finish()
/// returns null and the caller falls back to whole-file transcription (never a
/// silent drop). Audio is never lost.
public sealed class StreamingTranscriptionSession
{
    private readonly Func<float[], Task<string>> _transcribe;
    private readonly ChunkPlanner.Config _config;
    private readonly int _pollMs;

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
        int pollMilliseconds = 1000)
    {
        _transcribe = transcribe;
        _config = config ?? new ChunkPlanner.Config();
        _pollMs = pollMilliseconds;
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

        if (_failed || _cancelled || _url is null) return null;
        if (_consumedSamples <= 0 && _pieces.Count == 0) return null;

        _reader ??= WavTailReader.Open(_url);
        if (_reader is null) return null;
        var tail = _reader.Samples(_consumedSamples);
        if (tail is null) return null;

        // Drain any backlog the poll loop didn't get to. Terminates: every cut shrinks tail.
        while (true)
        {
            var decision = ChunkPlanner.Plan(tail, _config);
            if (decision.Kind != ChunkPlanner.DecisionKind.Cut) break;
            if (!decision.IsSilent)
                if (!await AppendPiece(WavTail.FloatSamples(tail.AsSpan(0, decision.AtSample))))
                    return null;
            tail = tail[decision.AtSample..];
        }
        if (tail.Length > 0 && !ChunkPlanner.IsSilent(tail, _config))
            if (!await AppendPiece(WavTail.FloatSamples(tail)))
                return null;

        string joined = string.Join(" ", _pieces).Trim();
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

    private async Task<bool> AppendPiece(float[] samples)
    {
        try
        {
            string text = await _transcribe(samples);
            if (text.Length == 0)
            {
                // A non-silent chunk that decodes to nothing → fail (would otherwise
                // silently delete up to maxChunkSeconds of speech).
                _failed = true;
                return false;
            }
            _pieces.Add(text);
            return true;
        }
        catch
        {
            _failed = true;
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

        if (decision.IsSilent)
        {
            _consumedSamples += decision.AtSample; // dropped, never transcribed
            return;
        }

        var chunk = WavTail.FloatSamples(unconsumed.AsSpan(0, decision.AtSample));
        try
        {
            string text = await _transcribe(chunk);
            if (ct.IsCancellationRequested || _cancelled) return; // re-cover via finish/fallback
            if (text.Length == 0)
            {
                _failed = true; // non-silent chunk decoded to nothing → never silently drop
                return;
            }
            _pieces.Add(text);
            _consumedSamples += decision.AtSample;
        }
        catch
        {
            _failed = true;
        }
    }
}
