namespace JVoice.Core.Tours;

/// <summary>A window (or the tray icon) a tour's tag can attach to. The app wraps its WPF windows in one of these.</summary>
public interface ITourHost
{
    /// <summary>On screen (visible, not minimised).</summary>
    bool IsVisible { get; }
    /// <summary>The window the user is in right now.</summary>
    bool IsActive { get; }
    /// <summary>A control with this anchor id is in the host and visible.</summary>
    bool HasAnchor(string anchor);
    /// <summary>Scroll the control into view (no-op when it already is).</summary>
    void BringIntoView(string anchor);
}

/// <summary>What the coordinator drives (Mac <c>TourTagPresenting</c>): the real tag overlay, or a test fake.</summary>
public interface ITourTagPresenter
{
    Action? OnNext { get; set; }
    Action? OnSkipStep { get; set; }
    Action? OnSkipTour { get; set; }
    void Show(ITourHost host, TourStep step, string body, int number, int total, bool isLast);
    /// <summary>A Try step was done: the tag's brief "Done" state.</summary>
    void ShowCompleted();
    void UpdateProgress(int number, int total, bool isLast);
    /// <summary>The step's body with a live caption appended (the Opacity demo's readout).</summary>
    void UpdateBody(string body);
    void Hide();
}

/// <summary>Something a step plays while it's on screen (today only the Opacity step's slider demo).</summary>
public interface ITourStepDemo
{
    /// <summary>Starts playing; <paramref name="readout"/> receives a short live caption for the tag.</summary>
    void Start(Action<string> readout);
    /// <summary>Stops and puts back whatever the demo changed.</summary>
    void Stop();
}

/// <summary>The coordinator's timers (a DispatcherTimer in the app, a manual clock in tests).</summary>
public interface ITourClock
{
    /// <summary>Runs <paramref name="action"/> once after <paramref name="delay"/>.</summary>
    void After(TimeSpan delay, Action action);
    /// <summary>Runs <paramref name="action"/> every <paramref name="interval"/> until disposed.</summary>
    IDisposable Every(TimeSpan interval, Action action);
    /// <summary>Runs <paramref name="action"/> on the next UI turn (after the UI has updated).</summary>
    void Post(Action action);
}

/// <summary>
/// Runs JVoice's guided tours (Mac <c>TourCoordinator.swift</c>, ported 1:1 and kept UI-free so it is unit-tested).
/// Owns triggers, hand-overs, pausing (host closed or hidden → pause; resumes when its surface shows again),
/// persistence and driving the tag. Surfaces never call it directly — they post through the app's TourEvents bus.
///
/// New users only: the app classifies the audience before anything writes settings; only a "new" user is asked
/// "Want a quick tour?", and nothing ever starts by itself unless that user said yes (or later turned "Show Me
/// Around" on in Settings).
/// </summary>
public sealed class TourCoordinator
{
    private readonly TourPrefs _prefs;
    private readonly Action _save;
    private readonly IReadOnlyList<Tour> _catalog;
    private readonly Func<ITourTagPresenter> _makePresenter;
    private readonly Func<string, string?> _shortcutText;
    private readonly ITourClock _clock;

    /// <summary>Opens a surface's window so a tour asked for from the menu can start; false = can't (the pill).</summary>
    public Func<TourSurface, bool>? OpenSurface { get; set; }
    /// <summary>A short confirmation for the user (the HUD's notice pill).</summary>
    public Action<string>? Notify { get; set; }
    /// <summary>A tour was finished (not Skip Tour). The app closes the Welcome window when the Welcome tour ends.</summary>
    public Action<TourId>? OnFinished { get; set; }
    /// <summary>Hosts besides a tour's own where a step's anchor may live (the tray icon), searched after the host.</summary>
    public Func<IEnumerable<ITourHost>> ExtraAnchorHosts { get; set; } = () => Array.Empty<ITourHost>();
    /// <summary>What a step plays while it's on screen; null for most steps.</summary>
    public Func<TourStep, ITourStepDemo?> MakeDemo { get; set; } = _ => null;
    /// <summary>How long a completed Try step shows its "Done" state before the next step.</summary>
    public TimeSpan CompletedDelay { get; set; } = TimeSpan.FromSeconds(0.8);

    private sealed class Session
    {
        public required TourEngine Engine;
        public required ITourHost Host;
        /// <summary>A single part from the ⓘ's Show Me list: never marks seen, never pauses/resumes, never reports finished.</summary>
        public bool IsPart;
    }

    private sealed record Suspended(TourId Id, ITourHost Host, IReadOnlyList<TourEvent> Observed);

    private Session? _running;
    private readonly List<Suspended> _suspended = new();
    private readonly List<TourId> _pending = new();
    private readonly List<(TourSurface Surface, ITourHost Host)> _surfaceHosts = new();
    private ITourTagPresenter? _presenter;
    private int _generation;
    private bool _showingCompleted;
    private (int Number, int Total, bool IsLast)? _shownProgress;
    private IDisposable? _watchdog;
    private ITourStepDemo? _demo;

    public TourCoordinator(TourPrefs prefs, Action save, Func<ITourTagPresenter> makePresenter,
        Func<string, string?> shortcutText, ITourClock clock, IReadOnlyList<Tour>? catalog = null)
    {
        _prefs = prefs;
        _save = save;
        _makePresenter = makePresenter;
        _shortcutText = shortcutText;
        _clock = clock;
        _catalog = catalog ?? TourCatalog.All;
    }

    public TourPrefs Prefs => _prefs;

    /// <summary>The tour on screen (a Show Me part counts), or null.</summary>
    public TourId? RunningTour => _running?.Engine.Tour.Id;

    /// <summary>The host the running tour's tag is on.</summary>
    public ITourHost? RunningHost => _running?.Host;

    // ------------------------------------------------------------------ who gets tours

    /// <summary>
    /// Call first thing at launch, BEFORE anything writes settings. Classifies once and stores the audience; later
    /// launches just read it. <paramref name="signals"/> is only evaluated when nothing is stored yet.
    /// </summary>
    public static TourAudienceKind ClassifyAudienceIfNeeded(TourPrefs prefs, Func<AudienceSignals> signals, Action save)
    {
        if (prefs.AudienceKind is { } stored) return stored;
        var audience = TourAudience.Classify(signals());
        prefs.Audience = TourAudience.Store(audience);
        save();
        return audience;
    }

    public bool ShouldAskQuestion => TourRules.ShouldAskQuestion(_prefs.AudienceKind, _prefs.QuestionAnswered);

    public bool ShouldOpenWelcomeOnLaunch => TourRules.ShouldOpenWelcomeOnLaunch(_prefs.AudienceKind, _prefs.QuestionAnswered);

    /// <summary>The answer (closing the window unanswered = No). Show Me Around turns first-use tours on and starts
    /// the Welcome tour in <paramref name="host"/> (the Welcome window) right away.</summary>
    public void AnswerQuestion(bool showMeAround, ITourHost? host)
    {
        _prefs.FirstUseToursEnabled = showMeAround;
        _prefs.QuestionAnswered = true;
        _save();
        if (!showMeAround) return;
        if (host is not null)
        {
            Track(TourSurface.Welcome, host);
            if (Start(TourId.Welcome, host, 0)) return;
        }
        Queue(TourId.Welcome);
    }

    // ------------------------------------------------------------------ Settings → Tours & Tips

    /// <summary>"Show Me Around". Absent = off (existing users, and new users until they say yes).</summary>
    public bool FirstUseToursEnabled
    {
        get => _prefs.FirstUseToursEnabled == true;
        set { _prefs.FirstUseToursEnabled = value; _save(); }
    }

    /// <summary>Clears seen + paused only — never the audience or the answer.</summary>
    public void ResetAllTours()
    {
        _prefs.Seen.Clear();
        _prefs.Paused.Clear();
        _suspended.Clear();
        _save();
    }

    /// <summary><see cref="ResetAllTours"/> + the HUD confirmation.</summary>
    public void ResetAllToursAndConfirm()
    {
        ResetAllTours();
        Notify?.Invoke(TourRules.ResetConfirmation(_prefs.FirstUseToursEnabled));
    }

    // ------------------------------------------------------------------ tray Help & Tours / ⓘ

    /// <summary>Runs <paramref name="id"/> from its first step: now in <paramref name="host"/> (the ⓘ), or — from the
    /// tray (null) — now if its surface is on screen, otherwise when it next appears (opening it first if we can).</summary>
    public void Replay(TourId id, ITourHost? host)
    {
        if (Find(id) is not { } tour) return;
        if (host is not null)
        {
            Track(tour.Surface, host);
            if (!Start(id, host, 0, restart: true)) Queue(id);
            return;
        }
        if (VisibleHost(tour.Surface) is { } visible && Start(id, visible, 0, restart: true)) return;
        Queue(id);
        if (OpenSurface?.Invoke(tour.Surface) != true) Notify?.Invoke(StartsLaterMessage(id));
    }

    /// <summary>The ⓘ's Show Me list: just step <paramref name="step"/> of <paramref name="id"/>, now. A part whose
    /// control isn't on screen says so instead.</summary>
    public void ReplayPart(TourId id, int step, ITourHost? host)
    {
        if (Find(id) is not { } full || step < 0 || step >= full.Steps.Count) return;
        if ((host ?? VisibleHost(full.Surface)) is not { } h) return;
        var part = full with { Trigger = TourTrigger.ByApp, Steps = new[] { full.Steps[step] }, HandsOverTo = null };
        Track(full.Surface, h);
        if (!Start(id, h, 0, restart: true, explicitTour: part))
            Notify?.Invoke($"{full.Steps[step].Title} isn't on screen right now");
    }

    /// <summary>The HUD note when a requested tour can't start now.</summary>
    public static string StartsLaterMessage(TourId id) => id == TourId.RecordingPill
        ? "The recording tour starts at your next dictation"
        : $"{id.MenuTitle()} starts the next time you open it";

    // ------------------------------------------------------------------ bus handlers

    /// <summary>A surface's window is on screen (call right after it shows).</summary>
    public void SurfaceShown(TourSurface surface, ITourHost host)
    {
        Track(surface, host);
        foreach (var id in _pending.ToList())
            if (Find(id)?.Surface == surface) { Start(id, host, 0, restart: true); return; }
        foreach (var tour in _catalog.Where(t => t.Surface == surface && t.Id != _running?.Engine.Tour.Id))
            if (_prefs.Paused.TryGetValue(tour.Id.Raw(), out var index) && Start(tour.Id, host, index)) return;
        foreach (var tour in _catalog.Where(t => t.Trigger == TourTrigger.Shown(surface) && t.Id != _running?.Engine.Tour.Id))
            if (MayAutoStart(tour) && Start(tour.Id, host, 0)) return;
    }

    /// <summary>Something the user did (<see cref="TourEventName"/>).</summary>
    public void Post(TourEvent e)
    {
        bool wasRunning = _running is not null;
        if (_running is { } session)
        {
            var effect = session.Engine.Handle(e, Presence(session.Host));
            if (effect.Kind != TourEffectKind.None) Apply(effect, completedTry: true);
            else _clock.Post(CheckHost); // the action may have hidden the step's control
        }
        // Event-triggered tours never interrupt a running tour; they stay eligible for the next time.
        if (wasRunning || _running is not null) return;
        var trigger = TourTrigger.On(e);
        var requested = _pending.Select(Find).OfType<Tour>().Where(t => t.Trigger == trigger);
        var automatic = _catalog.Where(t => t.Trigger == trigger && MayAutoStart(t));
        foreach (var tour in requested.Concat(automatic).ToList())
            if (VisibleHost(tour.Surface) is { } host && Start(tour.Id, host, 0, restart: true)) return;
    }

    /// <summary>The host window closed: the running tour on it pauses (resumes the next time its surface shows).</summary>
    public void HostClosed(ITourHost host)
    {
        if (ReferenceEquals(_running?.Host, host)) PauseRunning();
        _surfaceHosts.RemoveAll(p => ReferenceEquals(p.Host, host));
    }

    // ------------------------------------------------------------------ running

    private bool Start(TourId id, ITourHost host, int index, bool restart = false,
        IReadOnlyList<TourEvent>? observed = null, Tour? explicitTour = null)
    {
        if ((explicitTour ?? Find(id)) is not { } tour) return false;
        if (!restart && _running is { } same && same.Engine.Tour.Id == id && ReferenceEquals(same.Host, host)) return true;
        var engine = new TourEngine(tour, observed);
        var effect = engine.Start(index, Presence(host));
        if (effect.Kind != TourEffectKind.Show) return false; // nothing presentable: never started, never marked seen

        FinishToursHandingOver(id);
        if (_running is { } current)
        {
            if (current.Engine.Tour.Id == id || current.IsPart)
            {
                StopRunning(); // replay of the running tour / a part: start over
            }
            else
            {
                var paused = current.Engine.Pause();
                if (paused.Kind == TourEffectKind.Paused)
                {
                    SetPausedIndex(paused.Step, current.Engine.Tour.Id);
                    _suspended.Add(new Suspended(current.Engine.Tour.Id, current.Host, current.Engine.Observed.ToList()));
                }
                StopRunning();
            }
        }
        _running = new Session { Engine = engine, Host = host, IsPart = explicitTour is not null };
        if (explicitTour is null)
        {
            _pending.Remove(id);
            ClearPausedIndex(id);
        }
        Watch();
        Apply(effect);
        return true;
    }

    private void PresenterNext() => Advance(s => s.Engine.Next(Presence(s.Host)));
    private void PresenterSkipStep() => Advance(s => s.Engine.SkipStep(Presence(s.Host)));
    private void PresenterSkipTour() => Advance(s => s.Engine.SkipTour());

    private void Advance(Func<Session, TourEffect> step)
    {
        if (_running is not { } session || _showingCompleted) return;
        Apply(step(session));
    }

    private void Apply(TourEffect effect, bool completedTry = false)
    {
        if (_running is not { } session) return;
        var tour = session.Engine.Tour;
        if (session.IsPart)
        {
            switch (effect.Kind)
            {
                case TourEffectKind.Show: Present(effect.Step); break;
                case TourEffectKind.Finished or TourEffectKind.Skipped or TourEffectKind.Paused:
                    StopRunning();
                    ResumeSuspended();
                    break;
            }
            return;
        }
        switch (effect.Kind)
        {
            case TourEffectKind.Show:
                int index = effect.Step;
                if (completedTry) AfterCompleted(() => Present(index));
                else Present(index);
                break;
            case TourEffectKind.Finished:
                MarkSeen(tour);
                var next = effect.HandsOverTo;
                if (next is { } n) Queue(n); // queued now, so the hand-over survives something else taking the screen
                void End()
                {
                    StopRunning(); // reports OnFinished
                    if (next is { } h) HandOver(h);
                    ResumeSuspended();
                }
                if (completedTry) AfterCompleted(End);
                else End();
                break;
            case TourEffectKind.Skipped:
                MarkSeen(tour);
                StopRunning();
                ResumeSuspended();
                break;
            case TourEffectKind.Paused:
                SetPausedIndex(effect.Step, tour.Id);
                StopRunning();
                ResumeSuspended();
                break;
        }
    }

    private void Present(int index)
    {
        if (_running is not { } session || index < 0 || index >= session.Engine.Tour.Steps.Count) return;
        StopDemo();
        var step = session.Engine.Tour.Steps[index];
        if (Locate(step.Anchor, session.Host) is not { } anchorHost)
        {
            CheckHost();
            return;
        }
        anchorHost.BringIntoView(step.Anchor);
        _generation++;
        _showingCompleted = false;
        string body = TourText.Resolve(step.Body, _shortcutText);
        // Counted over the steps that actually show (anchor present, precondition met) — never 1 → 3.
        var (number, total) = session.Engine.Progress(Presence(session.Host)) ?? (index + 1, session.Engine.Tour.Steps.Count);
        bool isLast = session.Engine.IsOnLastStep;
        _shownProgress = (number, total, isLast);
        Presenter.Show(anchorHost, step, body, number, total, isLast);
        if (MakeDemo(step) is { } demo)
        {
            _demo = demo;
            demo.Start(readout => _presenter?.UpdateBody(body + " " + readout));
        }
    }

    private void StopDemo()
    {
        _demo?.Stop();
        _demo = null;
    }

    /// <summary>Redoes "n of m" for the step on screen; the tag is told only when it changed.</summary>
    private void RefreshProgress()
    {
        if (_running is not { } session || _showingCompleted || _shownProgress is not { } shown) return;
        if (session.Engine.Progress(Presence(session.Host)) is not { } p) return;
        var now = (p.Number, p.Total, session.Engine.IsOnLastStep);
        if (now == shown) return;
        _shownProgress = now;
        _presenter?.UpdateProgress(p.Number, p.Total, now.IsOnLastStep);
    }

    /// <summary>The Try step's brief "Done" state, then <paramref name="then"/> (unless something else was shown).</summary>
    private void AfterCompleted(Action then)
    {
        StopDemo();
        int token = ++_generation;
        _showingCompleted = true;
        Presenter.ShowCompleted();
        _clock.After(CompletedDelay, () =>
        {
            if (_generation != token) return;
            _showingCompleted = false;
            then();
        });
    }

    /// <summary>Takes the running tour off screen; one that had finished is reported through <see cref="OnFinished"/>.</summary>
    private void StopRunning()
    {
        TourId? finished = _running is { IsPart: false } s && s.Engine.Status == TourStatus.Finished ? s.Engine.Tour.Id : null;
        StopDemo();
        _generation++;
        _showingCompleted = false;
        _shownProgress = null;
        _running = null;
        _presenter?.Hide();
        _watchdog?.Dispose();
        _watchdog = null;
        if (finished is { } f) OnFinished?.Invoke(f);
    }

    private void HandOver(TourId id)
    {
        if (Find(id) is not { } tour || VisibleHost(tour.Surface) is not { } host) return;
        Start(id, host, 0, restart: true);
    }

    /// <summary>A tour that hands over to <paramref name="id"/> and stopped on its last step is done once
    /// <paramref name="id"/> starts. (No JVoice tour hands over today; kept so a chain behaves like BetterScreenshot's.)</summary>
    private void FinishToursHandingOver(TourId id)
    {
        foreach (var tour in _catalog.Where(t => t.HandsOverTo == id && t.Steps.Count > 0))
        {
            int last = tour.Steps.Count - 1;
            if (_running is { } current && current.Engine.Tour.Id == tour.Id && current.Engine.Current == last)
            {
                MarkSeen(tour);
                StopRunning();
                OnFinished?.Invoke(tour.Id);
            }
            else if (_prefs.Paused.TryGetValue(tour.Id.Raw(), out var at) && at == last)
            {
                MarkSeen(tour);
                OnFinished?.Invoke(tour.Id);
            }
        }
    }

    /// <summary>After a tour ends: pick up the newest one it interrupted, if its host is still on screen.</summary>
    private void ResumeSuspended()
    {
        if (_running is not null) return;
        while (_suspended.Count > 0)
        {
            var entry = _suspended[^1];
            _suspended.RemoveAt(_suspended.Count - 1);
            if (!entry.Host.IsVisible || !_prefs.Paused.TryGetValue(entry.Id.Raw(), out var index)) continue;
            if (Start(entry.Id, entry.Host, index, observed: entry.Observed)) return;
        }
    }

    // ------------------------------------------------------------------ host watching

    private void Watch()
    {
        _watchdog?.Dispose();
        _watchdog = _clock.Every(TimeSpan.FromSeconds(0.5), CheckHost);
    }

    /// <summary>Host gone or hidden (the pill hides, it isn't closed) → pause; the step's control gone → skip it.</summary>
    public void CheckHost()
    {
        if (_running is not { } session || _showingCompleted) return;
        if (!session.Host.IsVisible)
        {
            PauseRunning();
            return;
        }
        var effect = session.Engine.SkipIfAnchorMissing(Presence(session.Host));
        Apply(effect);
        if (effect.Kind == TourEffectKind.None) RefreshProgress();
    }

    private void PauseRunning()
    {
        if (_running is not { } session) return;
        Apply(session.Engine.Pause());
    }

    // ------------------------------------------------------------------ helpers

    private ITourTagPresenter Presenter
    {
        get
        {
            if (_presenter is not null) return _presenter;
            var made = _makePresenter();
            made.OnNext = PresenterNext;
            made.OnSkipStep = PresenterSkipStep;
            made.OnSkipTour = PresenterSkipTour;
            return _presenter = made;
        }
    }

    private Tour? Find(TourId id) => _catalog.FirstOrDefault(t => t.Id == id);

    private Func<string, bool> Presence(ITourHost host) => anchor => Locate(anchor, host) is not null;

    /// <summary>The host the anchor is in: the tour's own host first, then <see cref="ExtraAnchorHosts"/> (only visible
    /// ones — a tray icon hidden in the overflow counts as missing, so its step is skipped).</summary>
    private ITourHost? Locate(string anchor, ITourHost host)
    {
        if (!host.IsVisible) return null;
        if (host.HasAnchor(anchor)) return host;
        foreach (var other in ExtraAnchorHosts())
            if (!ReferenceEquals(other, host) && other.IsVisible && other.HasAnchor(anchor)) return other;
        return null;
    }

    private bool MayAutoStart(Tour tour) =>
        TourRules.ShouldAutoStart(tour, _prefs.FirstUseToursEnabled, _prefs.SeenVersion(tour.Id));

    private void Queue(TourId id)
    {
        if (!_pending.Contains(id)) _pending.Add(id);
    }

    private void Track(TourSurface surface, ITourHost host)
    {
        _surfaceHosts.RemoveAll(p => ReferenceEquals(p.Host, host));
        _surfaceHosts.Add((surface, host));
    }

    /// <summary>The active host if it's one of <paramref name="surface"/>'s, else the newest visible one.</summary>
    private ITourHost? VisibleHost(TourSurface surface)
    {
        var mine = _surfaceHosts.Where(p => p.Surface == surface && p.Host.IsVisible).Select(p => p.Host).ToList();
        return mine.LastOrDefault(h => h.IsActive) ?? mine.LastOrDefault();
    }

    private void MarkSeen(Tour tour)
    {
        _prefs.Seen[tour.Id.Raw()] = Math.Max(_prefs.SeenVersion(tour.Id) ?? 0, tour.Version);
        _prefs.Paused.Remove(tour.Id.Raw());
        _save();
    }

    private void SetPausedIndex(int index, TourId id)
    {
        _prefs.Paused[id.Raw()] = index;
        _save();
    }

    private void ClearPausedIndex(TourId id)
    {
        if (_prefs.Paused.Remove(id.Raw())) _save();
    }
}
