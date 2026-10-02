using JVoice.Core.Tours;
using Xunit;

namespace JVoice.Tests;

/// <summary>
/// Parity §10.1/§10.4/§10.6/§10.8: the tour coordinator (Mac <c>TourCoordinator.swift</c>) against fake hosts, a fake
/// tag and a manual clock — who gets tours, auto-start, Try steps, missing anchors, pausing/resuming, replays, Show Me
/// parts, Reset All Tours and the Opacity step's demo.
/// </summary>
public class TourCoordinatorTests
{
    private sealed class Host : ITourHost
    {
        public readonly HashSet<string> Anchors;
        public bool IsVisible { get; set; } = true;
        public bool IsActive { get; set; } = true;
        public readonly List<string> Scrolled = new();
        public Host(params string[] anchors) => Anchors = new HashSet<string>(anchors);
        public bool HasAnchor(string anchor) => Anchors.Contains(anchor);
        public void BringIntoView(string anchor) => Scrolled.Add(anchor);
    }

    private sealed class Tag : ITourTagPresenter
    {
        public Action? OnNext { get; set; }
        public Action? OnSkipStep { get; set; }
        public Action? OnSkipTour { get; set; }
        public ITourHost? Host;
        public TourStep? Step;
        public string Body = "";
        public (int N, int Total, bool IsLast) Progress;
        public bool Visible, Completed;
        public int Shows;
        public void Show(ITourHost host, TourStep step, string body, int number, int total, bool isLast)
        {
            Host = host; Step = step; Body = body; Progress = (number, total, isLast); Visible = true; Completed = false; Shows++;
        }
        public void ShowCompleted() => Completed = true;
        public void UpdateProgress(int number, int total, bool isLast) => Progress = (number, total, isLast);
        public void UpdateBody(string body) => Body = body;
        public void Hide() { Visible = false; Step = null; }
    }

    private sealed class Clock : ITourClock
    {
        private readonly List<Action> _after = new();
        private readonly List<Action> _posted = new();
        public readonly List<(Action Tick, bool Disposed)> Timers = new();
        public void After(TimeSpan delay, Action action) => _after.Add(action);
        public void Post(Action action) => _posted.Add(action);
        public IDisposable Every(TimeSpan interval, Action action)
        {
            var t = new Timer(this, Timers.Count);
            Timers.Add((action, false));
            return t;
        }
        /// <summary>Runs everything delayed/posted so far (the "Done" pause elapsing, the next UI turn).</summary>
        public void Elapse()
        {
            var a = _after.ToList(); _after.Clear();
            var p = _posted.ToList(); _posted.Clear();
            foreach (var x in p.Concat(a)) x();
        }
        /// <summary>One 0.5 s watchdog tick on every live timer.</summary>
        public void Tick() { foreach (var t in Timers.Where(t => !t.Disposed).ToList()) t.Tick(); }
        private sealed class Timer(Clock c, int i) : IDisposable
        {
            public void Dispose() => c.Timers[i] = (c.Timers[i].Tick, true);
        }
    }

    private sealed class Demo : ITourStepDemo
    {
        public bool Running;
        public Action<string>? Readout;
        public void Start(Action<string> readout) { Running = true; Readout = readout; }
        public void Stop() => Running = false;
    }

    private static readonly string[] SettingsAnchors = TourCatalog.Settings.Steps.Select(s => s.Anchor).ToArray();
    private static Host Settings() => new(SettingsAnchors);
    private static Host Welcome() => new("welcome.shortcut", "welcome.tryIt");
    private static Host Pill() => new("pill.controls");

    private readonly TourPrefs _prefs = new();
    private readonly Tag _tag = new();
    private readonly Clock _clock = new();
    private readonly List<string> _notes = new();
    private readonly List<TourId> _finished = new();
    private int _saves;

    private TourCoordinator Make(string audience, bool? enabled = null)
    {
        _prefs.Audience = audience;
        _prefs.FirstUseToursEnabled = enabled;
        return new TourCoordinator(_prefs, () => _saves++, () => _tag,
            n => n == "toggleRecording" ? "Ctrl+Shift+Space" : null, _clock)
        {
            Notify = _notes.Add,
            OnFinished = _finished.Add,
        };
    }

    private static readonly TourEvent Started = TourEvent.Action(TourEventName.RecordingStarted);
    private static readonly TourEvent Stopped = TourEvent.Action(TourEventName.RecordingStopped);

    // ---------------------------------------------------------------- only the first time

    [Fact]
    public void ExistingUsersNeverGetATourByThemselves()
    {
        var c = Make("existing");
        Assert.False(c.ShouldAskQuestion);
        Assert.False(c.ShouldOpenWelcomeOnLaunch);
        c.SurfaceShown(TourSurface.Settings, Settings());
        c.SurfaceShown(TourSurface.RecordingPill, Pill());
        c.Post(Started);
        Assert.Null(c.RunningTour);
        Assert.Equal(0, _tag.Shows);
        // …also not after a version bump of a tour they never saw.
        _prefs.Seen["settings"] = 1;
        var bumped = new TourCoordinator(_prefs, () => { }, () => _tag, _ => null, _clock,
            new[] { TourCatalog.Settings with { Version = 2 } });
        bumped.SurfaceShown(TourSurface.Settings, Settings());
        Assert.Null(bumped.RunningTour);
    }

    [Fact]
    public void NewUserIsAskedOnceAndNoThanksMeansNothingStarts()
    {
        var c = Make("new");
        Assert.True(c.ShouldAskQuestion);
        Assert.True(c.ShouldOpenWelcomeOnLaunch);
        c.AnswerQuestion(false, Welcome());
        Assert.False(c.ShouldAskQuestion);
        Assert.False(c.ShouldOpenWelcomeOnLaunch);
        Assert.False(_prefs.FirstUseToursEnabled);
        Assert.True(_prefs.QuestionAnswered);
        c.SurfaceShown(TourSurface.Settings, Settings());
        Assert.Null(c.RunningTour);
    }

    [Fact]
    public void TheWelcomeAnswerAndTheToggleBothRaiseFirstUseToursChanged()
    {
        var c = Make("new");
        int raised = 0;
        c.FirstUseToursChanged += () => raised++;
        c.AnswerQuestion(true, Welcome());
        Assert.Equal(1, raised);
        c.FirstUseToursEnabled = true; // unchanged → no event
        Assert.Equal(1, raised);
        c.FirstUseToursEnabled = false;
        Assert.Equal(2, raised);
    }

    [Fact]
    public void ShowMeAroundRunsTheWelcomeTourThenFirstUseTours()
    {
        var c = Make("new");
        var welcome = Welcome(); // the tray icon isn't visible → step 1 is skipped
        c.AnswerQuestion(true, welcome);
        Assert.True(_prefs.FirstUseToursEnabled);
        Assert.Equal(TourId.Welcome, c.RunningTour);
        Assert.Equal("welcome.shortcut", _tag.Step!.Anchor);
        Assert.Equal("Press Ctrl+Shift+Space in any app to start talking. Press it again to stop.", _tag.Body);
        Assert.Equal((1, 2, false), _tag.Progress);

        _tag.OnNext!();
        Assert.Equal("welcome.tryIt", _tag.Step!.Anchor);
        Assert.Equal((2, 2, true), _tag.Progress);
        _tag.OnNext!(); // Next does nothing on a Try step
        Assert.Equal("welcome.tryIt", _tag.Step!.Anchor);

        // The user dictates: "Done", then the tour finishes after the pause.
        c.Post(Started);
        Assert.True(_tag.Completed);
        Assert.Empty(_finished);
        _clock.Elapse();
        Assert.Null(c.RunningTour);
        Assert.Equal(new[] { TourId.Welcome }, _finished);
        Assert.Equal(1, _prefs.Seen["welcome"]);

        // First-use tours are on now: the recording pill's tour starts by itself, once.
        var pill = Pill();
        c.SurfaceShown(TourSurface.RecordingPill, pill);
        Assert.Equal(TourId.RecordingPill, c.RunningTour);
        Assert.Equal("Speak, then press Ctrl+Shift+Space or click ■. Your words get typed.", _tag.Body);
        c.Post(Stopped);
        _clock.Elapse();
        Assert.Null(c.RunningTour);
        c.SurfaceShown(TourSurface.RecordingPill, pill);
        Assert.Null(c.RunningTour);
    }

    [Fact]
    public void TheTrayStepShowsOnTheTrayHostWhenTheIconIsVisible()
    {
        var c = Make("new");
        var tray = new Host(TourCatalog.TrayIconAnchor);
        c.ExtraAnchorHosts = () => new[] { tray };
        var welcome = Welcome();
        c.AnswerQuestion(true, welcome);
        Assert.Same(tray, _tag.Host);
        Assert.Equal((1, 3, false), _tag.Progress);
        _tag.OnNext!();
        Assert.Same(welcome, _tag.Host);
        Assert.Equal((2, 3, false), _tag.Progress);

        // Hidden in the overflow flyout → that step is skipped.
        tray.IsVisible = false;
        c.Replay(TourId.Welcome, welcome);
        Assert.Equal("welcome.shortcut", _tag.Step!.Anchor);
        Assert.Equal((1, 2, false), _tag.Progress);
    }

    // ---------------------------------------------------------------- the Settings tour

    [Fact]
    public void SettingsTourWalksEveryCardScrollingEachIntoViewAndIsSeenOnce()
    {
        var c = Make("new", enabled: true);
        var host = Settings();
        c.SurfaceShown(TourSurface.Settings, host);
        Assert.Equal(TourId.Settings, c.RunningTour);
        for (int i = 0; i < 10; i++)
        {
            Assert.Equal(SettingsAnchors[i], _tag.Step!.Anchor);
            Assert.Equal((i + 1, 10, i == 9), _tag.Progress);
            _tag.OnNext!();
        }
        Assert.Null(c.RunningTour);
        Assert.Equal(SettingsAnchors, host.Scrolled);
        Assert.Equal(1, _prefs.Seen["settings"]);
        c.SurfaceShown(TourSurface.Settings, Settings());
        Assert.Null(c.RunningTour);
    }

    [Fact]
    public void SkipTourMarksSeenAndAMissingCardIsSkipped()
    {
        var c = Make("new", enabled: true);
        var host = Settings();
        host.Anchors.Remove("settings.model");
        c.SurfaceShown(TourSurface.Settings, host);
        Assert.Equal((1, 9, false), _tag.Progress);
        _tag.OnNext!();
        Assert.Equal("settings.processing", _tag.Step!.Anchor);
        // A card that vanishes mid-step is skipped by the watchdog.
        host.Anchors.Remove("settings.processing");
        _clock.Tick();
        Assert.Equal("settings.voiceStyle", _tag.Step!.Anchor);
        _tag.OnSkipTour!();
        Assert.Null(c.RunningTour);
        Assert.False(_tag.Visible);
        Assert.Equal(1, _prefs.Seen["settings"]);
        Assert.Empty(_finished); // Skip Tour isn't "finished"
    }

    [Fact]
    public void ClosingTheHostPausesAndTheTourResumesWhereItStopped()
    {
        var c = Make("new", enabled: true);
        var host = Settings();
        c.SurfaceShown(TourSurface.Settings, host);
        _tag.OnNext!();
        _tag.OnNext!();
        c.HostClosed(host);
        Assert.Null(c.RunningTour);
        Assert.False(_tag.Visible);
        Assert.Equal(2, _prefs.Paused["settings"]);
        Assert.False(_prefs.Seen.ContainsKey("settings"));

        c.SurfaceShown(TourSurface.Settings, Settings());
        Assert.Equal("settings.processing", _tag.Step!.Anchor);
        Assert.Equal((3, 10, false), _tag.Progress);
        Assert.False(_prefs.Paused.ContainsKey("settings"));
    }

    [Fact]
    public void AHiddenHostPausesOnTheWatchdog()
    {
        var c = Make("new", enabled: true);
        var pill = Pill();
        c.SurfaceShown(TourSurface.RecordingPill, pill);
        pill.IsVisible = false; // the pill hides, it isn't closed
        _clock.Tick();
        Assert.Null(c.RunningTour);
        Assert.Equal(0, _prefs.Paused["recordingPill"]);
    }

    [Fact]
    public void TheOpacityStepPlaysItsDemoOnlyWhileOnScreen()
    {
        var demo = new Demo();
        var c = Make("new", enabled: true);
        c.MakeDemo = s => s.Anchor == OpacityDemoTimeline.Anchor ? demo : null;
        c.SurfaceShown(TourSurface.Settings, Settings());
        for (int i = 0; i < 8; i++) _tag.OnNext!();
        Assert.Equal("Opacity", _tag.Step!.Title);
        Assert.True(demo.Running);
        demo.Readout!("Watch: 37 % ↓");
        Assert.Equal("Sets how see-through JVoice's windows and pill are. Watch: 37 % ↓", _tag.Body);
        _tag.OnNext!();
        Assert.False(demo.Running);
        Assert.Equal("Replay any tour", _tag.Step!.Title);

        // Stopped by a pause too.
        var host = Settings();
        c.Replay(TourId.Settings, host);
        for (int i = 0; i < 8; i++) _tag.OnNext!();
        Assert.True(demo.Running);
        c.HostClosed(host);
        Assert.False(demo.Running);
    }

    // ---------------------------------------------------------------- replays, parts, reset

    [Fact]
    public void ReplayFromTheTrayOpensTheSurfaceOrSaysWhen()
    {
        var c = Make("existing");
        var opened = new List<TourSurface>();
        c.OpenSurface = s => { opened.Add(s); return s != TourSurface.RecordingPill; };

        c.Replay(TourId.Settings, null);
        Assert.Equal(new[] { TourSurface.Settings }, opened);
        Assert.Null(c.RunningTour);
        c.SurfaceShown(TourSurface.Settings, Settings()); // the window it opened
        Assert.Equal(TourId.Settings, c.RunningTour);
        _tag.OnSkipTour!();

        c.Replay(TourId.RecordingPill, null);
        Assert.Equal("The recording tour starts at your next dictation", _notes.Single());
        c.SurfaceShown(TourSurface.RecordingPill, Pill()); // queued: runs even with first-use tours off
        Assert.Equal(TourId.RecordingPill, c.RunningTour);
        Assert.Equal("Welcome Tour starts the next time you open it", TourCoordinator.StartsLaterMessage(TourId.Welcome));
    }

    [Fact]
    public void ReplayInAWindowRestartsFromStepOne()
    {
        var c = Make("existing");
        var host = Settings();
        c.Replay(TourId.Settings, host);
        _tag.OnNext!();
        _tag.OnNext!();
        c.Replay(TourId.Settings, host);
        Assert.Equal("settings.stats", _tag.Step!.Anchor);
        Assert.Equal((1, 10, false), _tag.Progress);
    }

    [Fact]
    public void ShowMePartsNeverTouchSeenOrPaused()
    {
        var c = Make("existing");
        var host = Settings();
        c.ReplayPart(TourId.Settings, 7, host);
        Assert.Equal("Custom words", _tag.Step!.Title);
        Assert.Equal((1, 1, true), _tag.Progress);
        _tag.OnNext!();
        Assert.Null(c.RunningTour);
        Assert.Empty(_prefs.Seen);
        Assert.Empty(_finished);

        c.ReplayPart(TourId.Settings, 2, host);
        c.HostClosed(host);
        Assert.Empty(_prefs.Paused);

        var missing = Settings();
        missing.Anchors.Remove("settings.shortcut");
        c.ReplayPart(TourId.Settings, 5, missing);
        Assert.Equal("Your shortcut isn't on screen right now", _notes.Last());
        c.ReplayPart(TourId.Settings, 99, missing); // out of range: nothing
        Assert.Single(_notes);
    }

    [Fact]
    public void ResetAllToursClearsOnlySeenAndPaused()
    {
        var c = Make("new");
        _prefs.QuestionAnswered = true;
        _prefs.Seen["settings"] = 1;
        _prefs.Paused["welcome"] = 1;
        c.ResetAllToursAndConfirm();
        Assert.Empty(_prefs.Seen);
        Assert.Empty(_prefs.Paused);
        Assert.Equal("new", _prefs.Audience);
        Assert.True(_prefs.QuestionAnswered);
        Assert.Equal("Tours reset — turn on Show Me Around to see them again", _notes.Single());
        c.FirstUseToursEnabled = true;
        c.ResetAllToursAndConfirm();
        Assert.Equal("Tours reset", _notes.Last());
    }

    // ---------------------------------------------------------------- one tour at a time

    [Fact]
    public void ARecordingDuringTheSettingsTourPausesItAndResumesAfter()
    {
        var c = Make("new", enabled: true);
        var settings = Settings();
        c.SurfaceShown(TourSurface.Settings, settings);
        _tag.OnNext!();
        var pill = Pill();
        c.SurfaceShown(TourSurface.RecordingPill, pill);
        Assert.Equal(TourId.RecordingPill, c.RunningTour);
        Assert.Equal(1, _prefs.Paused["settings"]);

        c.Post(Stopped);
        _clock.Elapse();
        Assert.Equal(TourId.Settings, c.RunningTour);
        Assert.Equal("settings.model", _tag.Step!.Anchor);
        Assert.False(_prefs.Paused.ContainsKey("settings"));
    }

    [Fact]
    public void EventsWithNoTourRunningDoNothing()
    {
        var c = Make("new", enabled: true);
        c.Post(Started);
        c.Post(Stopped);
        _clock.Elapse();
        Assert.Null(c.RunningTour);
        Assert.Equal(0, _tag.Shows);
    }
}
