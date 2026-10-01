namespace JVoice.Core.Audio;

/// Transcribes completed speech chunks of a still-growing WAV while recording.
/// Port of StreamingTranscriptionSession.swift. A failed chunk is re-covered by a LOCAL
/// recovery of the last stretch (else Finish() returns null and the caller falls back to
/// whole-file transcription) — never a silent drop. Audio is never lost.
///
/// Latency layer (Mac 2026-09-12/23, parity rows 2–4, 6):
///  • a chunk decode in flight when the user presses stop is AWAITED and its result kept
///    (it used to be thrown away and decoded again after the press);
///  • a SPECULATIVE TAIL DECODE: once the pending audio ends in `speculateAfterSeconds` of
///    silence, it is decoded right away, betting the next event is the stop press — if it
///    is (and nothing new was said), Finish() returns that result with zero post-stop decode;
///  • LOCAL RECOVERY: a chunk that decodes empty or throws keeps every piece before it and
///    re-decodes only from the start of the last kept piece to the end (whole-file
///    semantics via `recover`), unless that region exceeds MaxRecoveryFraction of the
///    recording — then the caller's whole-file decode runs, as before;
///  • the poll skips its read when the file hasn't grown (cheap at a 100 ms cadence).
///
/// WINDOWS DIVERGENCES from Swift (David's-mic bugs; his speech has read BELOW ChunkPlanner's
/// 0.005 absolute silence floor, so an absolute classification cannot be trusted to mean "no
/// speech" here):
///  #1 (2026-06-23; refined 2026-09-11, §7 #49): a silent-classified FINAL tail is DECODED —
///     empty ⇒ the model confirms silence, keep the pieces; non-empty ⇒ a classifier/model
///     disagreement whose isolated decode may be partial ⇒ treated as a failed chunk.
///  #2 (2026-07-03, §7 #39; refined 2026-07-13, §7 #41): a MID-STREAM chunk cut as "silent"
///     is DECODED under the same policy (empty ⇒ skip losslessly; non-empty ⇒ failure).
///  #4 (2026-10-02, speculation): the trailing-pause probe uses ChunkPlanner.AdaptivePauseFloor
///     (15 % of the pending audio's 90th-percentile window RMS) — the absolute floor called most
///     of David's speech a pause, so speculations started mid-sentence and were always dropped.
///  #3 (2026-10-02, speculation): a speculation is accepted only when the audio after the
///     part it decoded is silent by the absolute floor AND no louder than the pause's own
///     room tone (no 2 consecutive 0.1 s windows above the pause's median window RMS × 1.5 + 0.0003) —
///     soft speech below the absolute floor is still louder than the room it's spoken in,
///     so it reads as "speech resumed" and the normal tail decode runs. Remainders longer
///     than MaxSpeculationRemainderSeconds are never accepted.
/// A "failure" in either divergence goes to local recovery, whose whole-file-semantics
/// decode of the region is exactly what the #41 fallback guaranteed for that audio.
public sealed class StreamingTranscriptionSession
{
    /// Local recovery is skipped (→ whole-file decode) when its region would be more than this
    /// share of the recording (it would cost what the whole-file decode costs).
    public const double MaxRecoveryFraction = 0.7;
    /// A speculation is never accepted with more than this much audio after the part it decoded.
    public const double MaxSpeculationRemainderSeconds = 3.0;
    private const double ProbeSeconds = 0.1;

    private readonly Func<float[], CancellationToken, Task<string>> _transcribe;
    private readonly Func<short[], Task<string>>? _recover;
    private readonly ChunkPlanner.Config _config;
    private readonly int _pollMs;
    private readonly double _speculateAfterSeconds;
    // Optional diagnostics sink (e.g. the app's DiagnosticLog). Never affects behavior.
    private readonly Action<string>? _log;

    private string? _url;
    private WavTailReader? _reader;
    private int _consumedSamples;
    private readonly List<string> _pieces = new();
    /// Absolute sample where each entry of `_pieces` begins (parallel list).
    private readonly List<int> _pieceStarts = new();
    private Task? _pollTask;
    private CancellationTokenSource? _cts;
    private volatile bool _failed;
    private volatile bool _cancelled;
    private bool _finished;
    private int _openRetriesRemaining = 10;
    private long _lastSeenByteLength = -1;
    private Speculation? _speculation;

    private sealed class Speculation
    {
        /// Absolute sample where the decoded audio starts (== _consumedSamples then).
        public int Start;
        /// Latest speech end any poll measured inside the decoded audio.
        public int SpeechEnd;
        /// Absolute sample where the decoded audio ends.
        public int End;
        /// Room tone of the pause that triggered it (median 0.1 s window RMS) — divergence #3.
        public float Noise;
        public required Task<string> Task;
        public required CancellationTokenSource Cts;
    }

    /// The original (test) shape: no recovery, no speculation, decode never cancelled.
    public StreamingTranscriptionSession(
        Func<float[], Task<string>> transcribe,
        ChunkPlanner.Config? config = null,
        int pollMilliseconds = 1000,
        Action<string>? log = null)
        : this((samples, _) => transcribe(samples), recover: null, config, pollMilliseconds, speculateAfterSeconds: 0, log)
    {
    }

    public StreamingTranscriptionSession(
        Func<float[], CancellationToken, Task<string>> transcribe,
        Func<short[], Task<string>>? recover,
        ChunkPlanner.Config? config = null,
        int pollMilliseconds = 1000,
        double speculateAfterSeconds = 0.4,
        Action<string>? log = null)
    {
        _transcribe = transcribe;
        _recover = recover;
        _config = config ?? new ChunkPlanner.Config();
        _pollMs = pollMilliseconds;
        _speculateAfterSeconds = speculateAfterSeconds;
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
        // Interrupts the poll loop's sleep only: a running chunk decode completes and is consumed.
        _cts?.Cancel();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;

        if (_cancelled || _url is null)
        {
            await DiscardSpeculationAsync();
            _log?.Invoke($"Stream finish -> null (cancelled={_cancelled})");
            return null;
        }
        if (_failed)
        {
            await DiscardSpeculationAsync();
            return await RecoverLocally();
        }
        if (_consumedSamples <= 0 && _pieces.Count == 0 && _speculation is null) return null;

        _reader ??= WavTailReader.Open(_url);
        if (_reader is null) { await DiscardSpeculationAsync(); return null; }
        var tail = _reader.Samples(_consumedSamples);
        if (tail is null) { await DiscardSpeculationAsync(); return null; }

        // The bet paid off: the pending audio was decoded during the pause and nothing but the
        // room's own silence arrived after it.
        if (_speculation is { } spec)
        {
            _speculation = null;
            int endRel = spec.End - spec.Start;
            if (spec.Start == _consumedSamples && tail.Length >= endRel && RemainderIsQuiet(tail.AsSpan(endRel), spec.Noise))
            {
                string? text = null;
                try { text = await spec.Task; }
                catch (Exception ex) { _log?.Invoke($"Stream speculative tail decode failed ({ex.GetType().Name}) -> normal tail decode"); }
                if (text is { Length: > 0 })
                {
                    RecordPiece(text, spec.Start);
                    _log?.Invoke($"Stream speculative tail HIT - {(spec.SpeechEnd - spec.Start) / (double)_config.SampleRate:0.0} s of pending speech decoded during the pause");
                    return JoinedOrNull();
                }
                if (text is not null)
                {
                    // The model heard nothing in exactly this audio; decoding it alone again would
                    // say the same. Re-hear it in context instead.
                    _log?.Invoke("Stream speculative tail decoded empty -> local recovery");
                    _failed = true;
                    return await RecoverLocally();
                }
            }
            else
            {
                await CancelSpeculationAsync(spec);
                _log?.Invoke($"Stream speculative tail MISS - speech resumed after the pause ({Describe(tail, endRel, spec.Noise)})");
            }
        }

        // Drain any backlog the poll loop didn't get to. Terminates: every cut shrinks tail.
        // Silent-classified cuts are decoded too (divergence #2) — empty decode ⇒ skip.
        while (true)
        {
            var decision = ChunkPlanner.Plan(tail, _config);
            if (decision.Kind != ChunkPlanner.DecisionKind.Cut) break;
            if (!await AppendPiece(
                    WavTail.FloatSamples(tail.AsSpan(0, decision.AtSample)),
                    silentClassified: decision.IsSilent))
                return await RecoverLocally();
            _consumedSamples += decision.AtSample;
            tail = tail[decision.AtSample..];
        }
        if (tail.Length > 0)
        {
            // The FINAL tail is the user's last words (divergence #1): a silent-classified tail is
            // DECODED — the model confirming it empty (the user paused, then pressed stop) keeps
            // the streamed pieces; a non-empty decode is a classifier/model disagreement → recovery.
            bool silentTail = ChunkPlanner.IsSilent(tail, _config);
            if (silentTail)
                _log?.Invoke($"Stream final tail silent-classified ({tail.Length} samples) -> decoding to confirm");
            if (!await AppendPiece(WavTail.FloatSamples(tail), silentClassified: silentTail))
                return await RecoverLocally();
            _consumedSamples += tail.Length;
        }

        string? joined = JoinedOrNull();
        _log?.Invoke($"Stream finish -> {(joined is null ? "null (no pieces)" : $"{_pieces.Count} pieces, {joined.Length} chars")}");
        return joined;
    }

    /// Abandon this recording: discard everything; Finish() returns null if ever called.
    /// Joins the poll task (and any speculation) so no decode is still in flight when it returns.
    public async Task Cancel()
    {
        _cancelled = true;
        _cts?.Cancel();
        await DiscardSpeculationAsync();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;
        await DiscardSpeculationAsync();
        _pieces.Clear();
        _pieceStarts.Clear();
    }

    /// A chunk decoded empty, threw, or (Windows) a silent-classified chunk decoded non-empty. Keep
    /// the pieces before it; re-decode only from the start of the LAST kept piece to the end of the
    /// finalized recording through `recover`, and let that decode replace the last piece — the
    /// failed audio is heard with ≥ MinChunkSeconds of context. null ⇒ the caller's whole-file
    /// decode: no `recover`, nothing kept before the failure, an unreadable file, a region over
    /// MaxRecoveryFraction, or a recovery that also came back empty / threw.
    private async Task<string?> RecoverLocally()
    {
        _failed = true;
        if (_recover is null || _pieceStarts.Count == 0 || _url is null)
        {
            _log?.Invoke($"Stream FAILED -> whole-file fallback ({(_recover is null ? "no local recovery" : "nothing kept before the failure")})");
            return null;
        }
        int regionStart = _pieceStarts[^1];
        _reader ??= WavTailReader.Open(_url);
        var region = _reader?.Samples(regionStart);
        if (region is null || region.Length == 0) return null;
        if (region.Length > MaxRecoveryFraction * (regionStart + region.Length))
        {
            _log?.Invoke("Stream FAILED -> whole-file fallback (recovery region over 70% of the recording)");
            return null;
        }
        double rate = _config.SampleRate;
        _log?.Invoke($"Stream chunk decode empty/failed -> local recovery of the last {region.Length / rate:0.0} s (not the whole {(regionStart + region.Length) / rate:0.0} s)");
        string text;
        try { text = await _recover(region); }
        catch (Exception ex)
        {
            _log?.Invoke($"Stream local recovery threw {ex.GetType().Name} -> whole-file fallback");
            return null;
        }
        if (text.Length == 0)
        {
            _log?.Invoke("Stream local recovery empty -> whole-file fallback");
            return null;
        }
        if (_cancelled || _pieces.Count == 0) return null;
        _pieces.RemoveAt(_pieces.Count - 1);
        _pieceStarts.RemoveAt(_pieceStarts.Count - 1);
        RecordPiece(text, regionStart);
        return JoinedOrNull();
    }

    private void RecordPiece(string text, int start)
    {
        _pieces.Add(text);
        _pieceStarts.Add(start);
    }

    private string? JoinedOrNull()
    {
        string joined = string.Join(" ", _pieces).Trim();
        return joined.Length == 0 ? null : joined;
    }

    /// Decode one chunk (starting at _consumedSamples) and record its text. `silentClassified` carries
    /// ChunkPlanner's classification: for a silent-classified chunk an empty decode CONFIRMS silence
    /// (skip, keep going) and a NON-EMPTY decode may be partial (divergence #2) → failure. For a
    /// non-silent chunk an empty decode would silently delete speech → failure.
    private async Task<bool> AppendPiece(float[] samples, bool silentClassified)
    {
        try
        {
            string text = await _transcribe(samples, CancellationToken.None);
            return Accept(text, samples.Length, silentClassified);
        }
        catch (Exception ex)
        {
            _failed = true;
            _log?.Invoke($"Stream FAILED: chunk decode threw {ex.GetType().Name}");
            return false;
        }
    }

    private bool Accept(string text, int sampleCount, bool silentClassified)
    {
        if (text.Length == 0)
        {
            if (silentClassified)
            {
                _log?.Invoke($"Stream chunk {sampleCount} samples: silent-classified, model confirmed empty -> skipped");
                return true;
            }
            _failed = true; // non-silent chunk decoded to nothing → never silently drop
            _log?.Invoke($"Stream FAILED: non-silent chunk ({sampleCount} samples) decoded empty");
            return false;
        }
        if (silentClassified)
        {
            _failed = true; // quiet speech: the isolated decode may be partial
            _log?.Invoke($"Stream chunk {sampleCount} samples: silent-classified but decoded {text.Length} chars -> re-decode in context (partial-decode risk)");
            return false;
        }
        RecordPiece(text, _consumedSamples);
        return true;
    }

    private async Task RunPollLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !_failed && !_cancelled)
        {
            await PollOnce();
            try { await Task.Delay(_pollMs, ct); }
            catch (OperationCanceledException) { break; }
        }
        if (_failed || _cancelled) await DiscardSpeculationAsync();
    }

    private async Task PollOnce()
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

        // Nothing flushed since the last poll: skip the read entirely (stat before read).
        long? length = _reader.ByteLength();
        if (length is null) { _failed = true; return; } // file vanished
        if (length.Value == _lastSeenByteLength) return;
        _lastSeenByteLength = length.Value;

        var unconsumed = _reader.Samples(_consumedSamples);
        if (unconsumed is null) { _failed = true; return; } // file vanished

        var decision = ChunkPlanner.Plan(unconsumed, _config);
        if (decision.Kind != ChunkPlanner.DecisionKind.Cut)
        {
            await UpdateSpeculation(unconsumed);
            return;
        }

        // A speculative decode that already covers this chunk's speech IS this chunk's decode (the
        // cut sits inside the same pause) — but only if the audio between the decoded end and the cut
        // is the room's silence (divergence #3), or reusing it would skip that audio.
        Task<string>? reused = null;
        if (!decision.IsSilent && _speculation is { } spec && spec.Start == _consumedSamples
            && decision.AtSample >= spec.SpeechEnd - spec.Start
            && (decision.AtSample <= spec.End - spec.Start
                || RemainderIsQuiet(unconsumed.AsSpan(spec.End - spec.Start, decision.AtSample - (spec.End - spec.Start)), spec.Noise)))
        {
            _speculation = null;
            reused = spec.Task;
            double r = _config.SampleRate;
            _log?.Invoke($"Stream chunk cut reuses the speculative decode (decoded {(spec.End - spec.Start) / r:0.00}s, speechEnd {(spec.SpeechEnd - spec.Start) / r:0.00}s, cut {decision.AtSample / r:0.00}s; {Describe(unconsumed[..decision.AtSample], spec.End - spec.Start, spec.Noise)})");
        }
        else
        {
            await DiscardSpeculationAsync();
        }

        // Divergence #2 (§7 #39/#41): silent-classified chunks are decoded too — empty ⇒ true
        // silence, skip; non-empty ⇒ classifier and model disagree, the isolated decode may be
        // partial → failure → local recovery / whole-file at Finish.
        try
        {
            // Never cancelled by Finish(): an in-flight decode survives the stop press (row 4) and
            // its result is kept — only Cancel() (abandoned recording) discards it.
            string text = reused is not null
                ? await reused
                : await _transcribe(WavTail.FloatSamples(unconsumed.AsSpan(0, decision.AtSample)), CancellationToken.None);
            if (_cancelled) return;
            if (!Accept(text, decision.AtSample, decision.IsSilent)) return;
            _consumedSamples += decision.AtSample;
        }
        catch (Exception ex)
        {
            _failed = true;
            _log?.Invoke($"Stream FAILED: chunk decode threw {ex.GetType().Name}");
        }
    }

    /// Pause-triggered speculative tail decode, called only on a Wait decision — the pending audio is
    /// exactly what Finish() would decode after the stop press. Once it ends in
    /// `speculateAfterSeconds` of silence, decode it now; it stays valid while no speech lies beyond
    /// the audio it decoded, and is dropped when speech resumes.
    private async Task UpdateSpeculation(short[] unconsumed)
    {
        double rate = _config.SampleRate;
        int maxSamples = (int)(_config.MaxChunkSeconds * rate);
        if (_speculateAfterSeconds <= 0 || unconsumed.Length == 0 || unconsumed.Length >= maxSamples) return;
        // Divergence #4: the pause is judged against this audio's own speech level, not the
        // absolute floor most of David's speech sits under.
        float pauseFloor = ChunkPlanner.AdaptivePauseFloor(unconsumed, _config, ProbeSeconds);
        int trailing = ChunkPlanner.TrailingSilenceSamples(unconsumed, _config, ProbeSeconds, pauseFloor);
        int speechEndRel = unconsumed.Length - trailing;
        if (speechEndRel <= 0) return; // nothing but silence so far
        int absSpeechEnd = _consumedSamples + speechEndRel;
        if (_speculation is { } spec)
        {
            // Same pause: the measured speech end jitters on near-floor sounds (breaths) as the probe
            // grid shifts with the growing file. Only speech the decode did not hear invalidates it.
            if (spec.Start == _consumedSamples && absSpeechEnd <= spec.End)
            {
                spec.SpeechEnd = Math.Max(spec.SpeechEnd, absSpeechEnd);
                return;
            }
            await DiscardSpeculationAsync();
            _log?.Invoke("Stream speculative tail dropped - speech resumed");
        }
        if (trailing / rate < _speculateAfterSeconds) return;

        var audio = WavTail.FloatSamples(unconsumed);
        var cts = new CancellationTokenSource();
        var token = cts.Token;
        var task = Task.Run(() => _transcribe(audio, token));
        _speculation = new Speculation
        {
            Start = _consumedSamples,
            SpeechEnd = absSpeechEnd,
            End = _consumedSamples + unconsumed.Length,
            Noise = RoomTone(unconsumed.AsSpan(speechEndRel)),
            Task = task,
            Cts = cts,
        };
        _log?.Invoke($"Stream speculative tail decode started - {speechEndRel / rate:0.0} s of speech, {trailing / rate:0.0} s pause");
    }

    /// Median 0.1 s window RMS of a pause — the room's own tone.
    private float RoomTone(ReadOnlySpan<short> pause)
    {
        int step = Math.Max(1, (int)(ProbeSeconds * _config.SampleRate));
        var rms = new List<float>();
        for (int i = 0; i < pause.Length; i += step)
            rms.Add(ChunkPlanner.Rms(pause.Slice(i, Math.Min(step, pause.Length - i))));
        if (rms.Count == 0) return 0;
        rms.Sort();
        return rms[rms.Count / 2];
    }

    /// Divergence #3: the audio after a speculation's decoded end holds nothing new — silent by the
    /// absolute floor AND no 0.1 s window louder than the pause's room tone (× 1.5 + 0.0003), and
    /// not longer than MaxSpeculationRemainderSeconds.
    private bool RemainderIsQuiet(ReadOnlySpan<short> remainder, float roomTone)
    {
        if (remainder.Length == 0) return true;
        if (remainder.Length > MaxSpeculationRemainderSeconds * _config.SampleRate) return false;
        if (!ChunkPlanner.IsSilent(remainder, _config)) return false;
        float limit = roomTone * 1.5f + 0.0003f;
        int step = Math.Max(1, (int)(ProbeSeconds * _config.SampleRate));
        // Speech is ≥ 2 consecutive windows (0.2 s) above the room; a lone window is a click (the stop
        // press itself lands in the last 0.1 s) or a breath fragment.
        int run = 0;
        for (int i = 0; i < remainder.Length; i += step)
        {
            run = ChunkPlanner.Rms(remainder.Slice(i, Math.Min(step, remainder.Length - i))) > limit ? run + 1 : 0;
            if (run >= 2) return false;
        }
        return true;
    }

    /// Diagnostics for a MISS: the remainder's length and 0.1 s window RMS profile vs the limit.
    private string Describe(short[] tail, int endRel, float roomTone)
    {
        if (tail.Length < endRel) return "file shorter than the decoded audio";
        var rem = tail.AsSpan(endRel);
        int step = Math.Max(1, (int)(ProbeSeconds * _config.SampleRate));
        var w = new List<string>();
        for (int i = 0; i < rem.Length; i += step) w.Add(ChunkPlanner.Rms(rem.Slice(i, Math.Min(step, rem.Length - i))).ToString("0.0000"));
        return $"remainder {rem.Length / (double)_config.SampleRate:0.00}s, room {roomTone:0.0000}, limit {roomTone * 1.5f + 0.0003f:0.0000}, windows [{string.Join(" ", w)}]";
    }

    private async Task DiscardSpeculationAsync()
    {
        var spec = _speculation;
        _speculation = null;
        if (spec is not null) await CancelSpeculationAsync(spec);
    }

    /// Cancel a speculation and wait for it to stop, so decodes never overlap.
    private static async Task CancelSpeculationAsync(Speculation spec)
    {
        try { spec.Cts.Cancel(); } catch (ObjectDisposedException) { }
        try { await spec.Task; } catch { /* cancelled or failed — either way it's gone */ }
        spec.Cts.Dispose();
    }
}
