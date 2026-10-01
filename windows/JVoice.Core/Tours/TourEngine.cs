namespace JVoice.Core.Tours;

public enum TourStatus { Idle, Running, Paused, Finished, Skipped }

public enum TourEffectKind { None, Show, Finished, Skipped, Paused, NothingToShow }

/// <summary>What the caller must do after an engine call.</summary>
public readonly record struct TourEffect(TourEffectKind Kind, int Step = -1, TourId? HandsOverTo = null)
{
    public static TourEffect None => new(TourEffectKind.None);
    public static TourEffect NothingToShow => new(TourEffectKind.NothingToShow);
    public static TourEffect Skipped => new(TourEffectKind.Skipped);
}

/// <summary>
/// The tour state machine (Mac <c>TourEngine</c>, ported 1:1 — shared with BetterScreenshot's Windows port). Steps whose anchor isn't present, Try steps
/// whose event already happened, and steps whose <c>Requires</c> wasn't seen this run are skipped; a run with
/// nothing to show changes nothing (a surface without its anchors yet never burns a tour).
/// </summary>
public sealed class TourEngine
{
    private readonly List<TourEvent> _observed = new();
    private readonly HashSet<int> _shown = new();
    private int _runStart;

    public TourEngine(Tour tour, IEnumerable<TourEvent>? observed = null)
    {
        Tour = tour;
        if (observed is not null) _observed.AddRange(observed);
    }

    public Tour Tour { get; }
    public TourStatus Status { get; private set; } = TourStatus.Idle;
    public int Current { get; private set; }
    public IReadOnlyList<TourEvent> Observed => _observed;
    public TourStep? CurrentStep => Status is TourStatus.Running or TourStatus.Paused && Current < Tour.Steps.Count ? Tour.Steps[Current] : null;
    public bool IsOnLastStep => Status is TourStatus.Running or TourStatus.Paused && NextPresentable(Current + 1, _ => true) is null;

    private bool Presentable(int i, Func<string, bool> isPresent)
    {
        var s = Tour.Steps[i];
        if (!isPresent(s.Anchor)) return false;
        if (s.AdvanceOn is { } e && _observed.Contains(e)) return false;
        if (s.Requires is { } r && !_observed.Contains(r)) return false;
        return true;
    }

    private int? NextPresentable(int from, Func<string, bool> isPresent)
    {
        for (int i = Math.Max(0, from); i < Tour.Steps.Count; i++)
            if (Presentable(i, isPresent)) return i;
        return null;
    }

    public TourEffect Start(int at, Func<string, bool> isPresent)
    {
        if (Status is not (TourStatus.Idle or TourStatus.Paused)) return TourEffect.None;
        if (at < 0 || at >= Tour.Steps.Count) at = 0;
        if (NextPresentable(at, isPresent) is not { } i) return TourEffect.NothingToShow;
        Status = TourStatus.Running;
        Current = i;
        _runStart = at;
        _shown.Add(i);
        return new TourEffect(TourEffectKind.Show, i);
    }

    private TourEffect Advance(Func<string, bool> isPresent)
    {
        if (NextPresentable(Current + 1, isPresent) is { } i)
        {
            Current = i;
            _shown.Add(i);
            return new TourEffect(TourEffectKind.Show, i);
        }
        Status = TourStatus.Finished;
        return new TourEffect(TourEffectKind.Finished, HandsOverTo: Tour.HandsOverTo);
    }

    public TourEffect Next(Func<string, bool> isPresent) =>
        Status == TourStatus.Running && !Tour.Steps[Current].IsTry ? Advance(isPresent) : TourEffect.None;

    public TourEffect SkipStep(Func<string, bool> isPresent) =>
        Status == TourStatus.Running ? Advance(isPresent) : TourEffect.None;

    public TourEffect Handle(TourEvent e, Func<string, bool> isPresent)
    {
        if (Status != TourStatus.Running) return TourEffect.None;
        _observed.Add(e);
        return Tour.Steps[Current].AdvanceOn is { } a && a == e ? Advance(isPresent) : TourEffect.None;
    }

    public TourEffect SkipIfAnchorMissing(Func<string, bool> isPresent) =>
        Status == TourStatus.Running && !isPresent(Tour.Steps[Current].Anchor) ? Advance(isPresent) : TourEffect.None;

    public TourEffect SkipTour()
    {
        if (Status is not (TourStatus.Running or TourStatus.Paused)) return TourEffect.None;
        Status = TourStatus.Skipped;
        return TourEffect.Skipped;
    }

    public TourEffect Pause()
    {
        if (Status != TourStatus.Running) return TourEffect.None;
        Status = TourStatus.Paused;
        return new TourEffect(TourEffectKind.Paused, Current);
    }

    public TourEffect Resume(Func<string, bool> isPresent)
    {
        if (Status != TourStatus.Paused) return TourEffect.None;
        if (NextPresentable(Current, isPresent) is not { } i) return TourEffect.NothingToShow;
        Status = TourStatus.Running;
        Current = i;
        _shown.Add(i);
        return new TourEffect(TourEffectKind.Show, i);
    }

    /// <summary>"n of m" counted only over steps that actually show (§7.2 progress), or null unless running/paused.</summary>
    public (int Number, int Total)? Progress(Func<string, bool> isPresent)
    {
        if (Status is not (TourStatus.Running or TourStatus.Paused)) return null;
        int number = 0, total = 0;
        var pendingTryEvents = new List<TourEvent>();
        for (int i = 0; i < Tour.Steps.Count; i++)
        {
            var s = Tour.Steps[i];
            bool counted;
            if (i < Current) counted = _shown.Contains(i) || (i < _runStart && isPresent(s.Anchor));
            else if (i == Current) counted = true;
            else
            {
                bool tryDone = s.AdvanceOn is { } e && _observed.Contains(e);
                bool reqMet = s.Requires is not { } r || _observed.Contains(r) || pendingTryEvents.Contains(r);
                counted = isPresent(s.Anchor) && !tryDone && reqMet;
            }
            if (!counted) continue;
            total++;
            if (i <= Current) number++;
            if (i >= Current && s.AdvanceOn is { } ev) pendingTryEvents.Add(ev);
        }
        return (number, total);
    }
}
