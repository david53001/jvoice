using System.Globalization;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using JVoice.Core;
using JVoice.Core.Tours;
using Xunit;

namespace JVoice.Tests;

/// <summary>
/// Parity §10 (first-run Welcome + guided tours) pure logic: audience, rules, placeholders, prefs, the engine
/// (shared with BetterScreenshot's Windows port), tag layout / keys / outline radius, the Opacity demo timeline and
/// the catalog lint (copy rules + every body fits the tag's two lines at 260 with the longest shortcut).
/// </summary>
public class TourTests
{
    // ---------------------------------------------------------------- audience + rules

    private static AudienceSignals S(string[]? entries = null, bool model = false, bool mic = false, bool reg = false, bool dev = false) =>
        new(entries ?? Array.Empty<string>(), model, mic, reg, dev);

    [Fact]
    public void AudienceIsNewOnlyWhenNothingSaysOtherwise()
    {
        Assert.Equal(TourAudienceKind.New, TourAudience.Classify(S()));
        Assert.Equal(TourAudienceKind.New, TourAudience.Classify(S(new[] { "tours.json" })));
        Assert.Equal(TourAudienceKind.New, TourAudience.Classify(S(new[] { "TOURS.JSON" })));
    }

    [Fact]
    public void EveryExistingSignalAloneMakesAnExistingUser()
    {
        // David's own PC: settings, stats, transcripts, models, consent, registry — any ONE is enough.
        foreach (var entry in new[] { "settings.json", "stats.json", "transcript-history.json", "last-transcript.txt",
                     "diagnostic.log", "capture", "models", "settings.corrupt.bak", "anything" })
            Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(new[] { "tours.json", entry })));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(model: true)));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(mic: true)));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(reg: true)));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S(dev: true)));
        Assert.Equal(TourAudienceKind.Existing, TourAudience.Classify(S() with { LaunchedByJVoice = true })); // relaunch/autostart
    }

    [Fact]
    public void StoredAudienceParsingIsFailSafe()
    {
        Assert.Null(TourAudience.Parse(null));
        Assert.Equal(TourAudienceKind.New, TourAudience.Parse("new"));
        foreach (var s in new[] { "existing", "New", "", "true" }) Assert.Equal(TourAudienceKind.Existing, TourAudience.Parse(s));
        Assert.Equal("new", TourAudience.Store(TourAudienceKind.New));
        Assert.Equal("existing", TourAudience.Store(TourAudienceKind.Existing));
    }

    [Fact]
    public void ConsentKeyAndDevPaths()
    {
        Assert.Equal("C:#Users#a#AppData#Local#Programs#JVoice#JVoice.exe",
            TourAudience.ConsentKeyName(@"C:\Users\a\AppData\Local\Programs\JVoice\JVoice.exe"));
        Assert.True(TourAudience.IsDevBuildPath(@"C:\src\windows\JVoice.App\bin\Debug\net9.0-windows\win-x64"));
        Assert.True(TourAudience.IsDevBuildPath(@"C:\src\windows\JVoice.App\bin\x64\Release\net9.0-windows\win-x64\"));
        Assert.True(TourAudience.IsDevBuildPath(@"C:\src\JVoice.App\bin\Release\net9.0-windows"));
        Assert.False(TourAudience.IsDevBuildPath(@"C:\Users\a\AppData\Local\Programs\JVoice"));
        Assert.False(TourAudience.IsDevBuildPath(@"C:\Program Files\JVoice\bin2"));
    }

    [Fact]
    public void ClassifyOnceThenNeverAgain()
    {
        var prefs = new TourPrefs();
        int saves = 0, asked = 0;
        Assert.Equal(TourAudienceKind.New, TourCoordinator.ClassifyAudienceIfNeeded(prefs, () => { asked++; return S(); }, () => saves++));
        Assert.Equal("new", prefs.Audience);
        Assert.Equal(1, saves);
        // A later launch with settings on disk still reads the stored answer, without looking again.
        Assert.Equal(TourAudienceKind.New, TourCoordinator.ClassifyAudienceIfNeeded(prefs, () => { asked++; return S(new[] { "settings.json" }); }, () => saves++));
        Assert.Equal(1, asked);
        Assert.Equal(1, saves);

        var upgrading = new TourPrefs();
        Assert.Equal(TourAudienceKind.Existing,
            TourCoordinator.ClassifyAudienceIfNeeded(upgrading, () => S(new[] { "settings.json" }), () => { }));
        Assert.Equal("existing", upgrading.Audience);
    }

    [Fact]
    public void Rules()
    {
        Assert.True(TourRules.ShouldAskQuestion(TourAudienceKind.New, false));
        Assert.False(TourRules.ShouldAskQuestion(TourAudienceKind.New, true));
        Assert.False(TourRules.ShouldAskQuestion(TourAudienceKind.Existing, false));
        Assert.False(TourRules.ShouldAskQuestion(null, false));
        Assert.True(TourRules.ShouldOpenWelcomeOnLaunch(TourAudienceKind.New, false));
        Assert.False(TourRules.ShouldOpenWelcomeOnLaunch(TourAudienceKind.Existing, false));
        Assert.False(TourRules.ShouldOpenWelcomeOnLaunch(TourAudienceKind.New, true));
        var tour = TourCatalog.Settings;
        Assert.True(TourRules.ShouldAutoStart(tour, true, null));
        Assert.False(TourRules.ShouldAutoStart(tour, false, null));
        Assert.False(TourRules.ShouldAutoStart(tour, null, null));
        Assert.False(TourRules.ShouldAutoStart(tour, true, 1));
        var v2 = tour with { Version = 2 };
        Assert.True(TourRules.ShouldAutoStart(v2, true, 1));
        Assert.False(TourRules.ShouldAutoStart(v2, null, 1)); // existing users never, also not after a version bump
        Assert.Equal("Tours reset", TourRules.ResetConfirmation(true));
        Assert.Equal("Tours reset — turn on Show Me Around to see them again", TourRules.ResetConfirmation(false));
        Assert.Equal("Tours reset — turn on Show Me Around to see them again", TourRules.ResetConfirmation(null));
    }

    [Fact]
    public void ShortcutPlaceholders()
    {
        string? R(string n) => n == "toggleRecording" ? "Ctrl+Shift+Space" : n == "undoLastPaste" ? TourText.UnboundShortcut : null;
        Assert.Equal("Press Ctrl+Shift+Space now", TourText.Resolve("Press {shortcut:toggleRecording} now", R));
        Assert.Equal("Ctrl+Shift+Space and (not set)", TourText.Resolve("{shortcut:toggleRecording} and {shortcut:undoLastPaste}", R));
        Assert.Equal("plain", TourText.Resolve("plain", R));
        Assert.Equal("{shortcut:nope}", TourText.Resolve("{shortcut:nope}", R));
        Assert.Equal("{shortcut:toggleRecording", TourText.Resolve("{shortcut:toggleRecording", R));
        Assert.Equal(new[] { "toggleRecording", "undoLastPaste" }, TourText.Names("{shortcut:toggleRecording} {shortcut:undoLastPaste}"));
    }

    [Fact]
    public void TourIdsRoundTrip()
    {
        foreach (var id in Enum.GetValues<TourId>()) Assert.Equal(id, TourIds.Parse(id.Raw()));
        Assert.Equal("recordingPill", TourId.RecordingPill.Raw());
        Assert.Equal("welcome", TourId.Welcome.Raw());
        Assert.Null(TourIds.Parse("nope"));
        Assert.Null(TourIds.Parse(null));
        Assert.Equal("Welcome Tour", TourId.Welcome.MenuTitle());
        Assert.Equal("Recording Tour", TourId.RecordingPill.MenuTitle());
        Assert.Equal("Settings Tour", TourId.Settings.MenuTitle());
    }

    // ---------------------------------------------------------------- prefs

    [Fact]
    public void PrefsRoundTripAndWriteOnlyTheFiveKeys()
    {
        var p = new TourPrefs { Audience = "new", QuestionAnswered = true, FirstUseToursEnabled = false };
        p.Seen["settings"] = 1;
        p.Paused["welcome"] = 2;
        var json = p.ToJson();
        var back = TourPrefs.FromJson(json);
        Assert.Equal("new", back.Audience);
        Assert.True(back.QuestionAnswered);
        Assert.False(back.FirstUseToursEnabled);
        Assert.Equal(1, back.Seen["settings"]);
        Assert.Equal(2, back.Paused["welcome"]);
        var keys = System.Text.Json.Nodes.JsonNode.Parse(json)!.AsObject().Select(k => k.Key).ToHashSet();
        Assert.True(keys.SetEquals(TourPrefs.AllKeys));
    }

    [Fact]
    public void PrefsReadLeniently()
    {
        foreach (var bad in new[] { null, "", "   ", "not json", "[1,2]", "{\"tourAudience\": 5}" })
        {
            var p = TourPrefs.FromJson(bad);
            Assert.Null(p.Audience);
            Assert.False(p.QuestionAnswered);
            Assert.Null(p.FirstUseToursEnabled); // absent = off
        }
        var partial = TourPrefs.FromJson("{\"tourAudience\":\"existing\",\"toursSeen\":{\"settings\":\"x\",\"welcome\":1}}");
        Assert.Equal(TourAudienceKind.Existing, partial.AudienceKind);
        Assert.Single(partial.Seen);
        Assert.Equal("{}", TourPrefs.FromJson(null).ToJson().Replace("\r", "").Replace("\n", "").Replace(" ", ""));
    }

    // ---------------------------------------------------------------- engine

    private static readonly TourEvent Ev = TourEvent.Action("x.did");

    private static Tour Make(params TourStep[] steps) => new(TourId.Settings, TourSurface.Settings, TourTrigger.ByApp, steps, TourId.Welcome);
    private static TourStep Ex(string a) => new(a, "T", "B");
    private static TourStep Tr(string a, TourEvent e) => new(a, "T", "B", e);
    private static bool All(string _) => true;

    [Fact]
    public void EngineWalksExplainStepsAndFinishesWithHandOver()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), e.Start(0, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Next(All));
        Assert.Equal(new TourEffect(TourEffectKind.Finished, HandsOverTo: TourId.Welcome), e.Next(All));
        Assert.Equal(TourEffect.None, e.Next(All));
        Assert.Equal(TourStatus.Finished, e.Status);
    }

    [Fact]
    public void TryStepsAdvanceOnlyOnTheirExactEvent()
    {
        var e = new TourEngine(Make(Tr("a.a", TourEvent.MenuOpened("x.text")), Ex("a.b")));
        e.Start(0, All);
        Assert.Equal(TourEffect.None, e.Next(All)); // Next ignored on Try
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.MenuOpened("x.arrow"), All));
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.ChoiceMade("x.text"), All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Handle(TourEvent.MenuOpened("x.text"), All));
        Assert.Equal(TourEffect.None, e.Handle(TourEvent.MenuOpened("x.text"), All)); // events do nothing on Explain
    }

    [Fact]
    public void EventSeenEarlierMakesALaterTryStepSkip()
    {
        var e = new TourEngine(Make(Ex("a.a"), Tr("a.b", Ev), Ex("a.c")));
        e.Start(0, All);
        e.Handle(Ev, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Next(All));
    }

    [Fact]
    public void SkipStepLeavesATryStepAndTryOnLastStepFinishes()
    {
        var e = new TourEngine(Make(Tr("a.a", Ev), Tr("a.b", TourEvent.Action("recording.started"))));
        e.Start(0, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.SkipStep(All));
        Assert.Equal(TourEffectKind.Finished, e.Handle(TourEvent.Action("recording.started"), All).Kind);
    }

    [Fact]
    public void MissingAnchorsAreSkipped()
    {
        bool P(string a) => a != "a.b";
        var e = new TourEngine(Make(Ex("a.b"), Ex("a.a"), Ex("a.b"), Ex("a.c")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Start(0, P));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 3), e.Next(P));
        // vanishing mid-step
        Assert.Equal(TourEffectKind.Finished, e.SkipIfAnchorMissing(a => a != "a.c").Kind);
        // trailing missing anchors finish
        var t = new TourEngine(Make(Ex("a.a"), Ex("a.z")));
        t.Start(0, a => a == "a.a");
        Assert.Equal(TourEffectKind.Finished, t.Next(a => a == "a.a").Kind);
    }

    [Fact]
    public void NothingPresentChangesNothing()
    {
        var e = new TourEngine(Make(Ex("a.a")));
        Assert.Equal(TourEffect.NothingToShow, e.Start(0, _ => false));
        Assert.Equal(TourStatus.Idle, e.Status);
        Assert.Equal(TourEffect.NothingToShow, new TourEngine(Make()).Start(0, All));
    }

    [Fact]
    public void SkipPauseResume()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c")));
        Assert.Equal(TourEffect.None, e.Pause());
        e.Start(0, All);
        e.Next(All);
        Assert.Equal(new TourEffect(TourEffectKind.Paused, 1), e.Pause());
        Assert.Equal(TourEffect.None, e.Next(All));
        Assert.Equal(TourEffect.None, e.Handle(Ev, All));
        Assert.Equal(TourEffect.NothingToShow, e.Resume(_ => false));
        Assert.Equal(TourStatus.Paused, e.Status);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Resume(a => a != "a.b")); // resume skips steps now missing
        Assert.Equal(TourEffect.Skipped, e.SkipTour());
        var p = new TourEngine(Make(Ex("a.a")));
        p.Start(0, All);
        p.Pause();
        Assert.Equal(TourEffect.Skipped, p.SkipTour());
        Assert.Equal(TourEffect.None, new TourEngine(Make(Ex("a.a"))).Resume(All));
    }

    [Fact]
    public void StartAtPersistedIndex()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b")));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), e.Start(1, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(Ex("a.a"))).Start(99, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(Ex("a.a"))).Start(-1, All));
    }

    [Fact]
    public void RequiresGatesAStep()
    {
        var req = new TourStep("a.r", "T", "B", Requires: Ev);
        var e = new TourEngine(Make(Ex("a.a"), req, Ex("a.c")));
        e.Start(0, All);
        Assert.Equal(new TourEffect(TourEffectKind.Show, 2), e.Next(All)); // never seen → skipped
        var seen = new TourEngine(Make(Ex("a.a"), req));
        seen.Start(0, All);
        seen.Handle(Ev, All); // seen during an Explain step counts
        Assert.Equal(new TourEffect(TourEffectKind.Show, 1), seen.Next(All));
        Assert.Equal(TourEffect.NothingToShow, new TourEngine(Make(req)).Start(0, All));
        Assert.Equal(new TourEffect(TourEffectKind.Show, 0), new TourEngine(Make(req), new[] { Ev }).Start(0, All));
        var trailing = new TourEngine(Make(Ex("a.a"), req));
        trailing.Start(0, All);
        Assert.Equal(TourEffectKind.Finished, trailing.Next(All).Kind);
    }

    [Fact]
    public void ProgressCountsOnlyStepsThatShow()
    {
        var e = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c"), Ex("a.d"), Ex("a.e")));
        Assert.Null(e.Progress(All));
        e.Start(0, All);
        Assert.Equal((1, 5), e.Progress(All));
        e.Next(All);
        Assert.Equal((2, 5), e.Progress(All));

        // 10-step pill without steps 2 and 5 → 1/8 … 8/8
        var ten = new TourEngine(Make(Enumerable.Range(1, 10).Select(i => Ex($"p.s{i}")).ToArray()));
        bool P(string a) => a != "p.s2" && a != "p.s5";
        ten.Start(0, P);
        Assert.Equal((1, 8), ten.Progress(P));
        for (int i = 0; i < 7; i++) ten.Next(P);
        Assert.Equal((8, 8), ten.Progress(P));

        // the total follows controls appearing / going
        var f = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c")));
        f.Start(0, All);
        Assert.Equal((1, 2), f.Progress(a => a != "a.c"));

        // a Try step already done isn't counted
        var t = new TourEngine(Make(Ex("a.a"), Tr("a.b", Ev), Ex("a.c")));
        t.Start(0, All);
        t.Handle(Ev, All);
        Assert.Equal((1, 2), t.Progress(All));

        // a requires-step counted while the Try step that meets it is ahead; dropped once that Try step is skipped
        var r = new TourEngine(Make(Tr("a.a", Ev), new TourStep("a.r", "T", "B", Requires: Ev)));
        r.Start(0, All);
        Assert.Equal((1, 2), r.Progress(All));
        var r2 = new TourEngine(Make(Tr("a.a", Ev), Ex("a.b"), new TourStep("a.r", "T", "B", Requires: Ev)));
        r2.Start(0, All);
        r2.SkipStep(All);
        Assert.Equal((2, 2), r2.Progress(All));

        // a resumed run at step 3 reads 3/5 (2/4 once step 1's control is gone)
        var res = new TourEngine(Make(Ex("a.a"), Ex("a.b"), Ex("a.c"), Ex("a.d"), Ex("a.e")));
        res.Start(2, All);
        Assert.Equal((3, 5), res.Progress(All));
        Assert.Equal((2, 4), res.Progress(a => a != "a.a"));

        res.SkipTour();
        Assert.Null(res.Progress(All));
    }

    // ---------------------------------------------------------------- layout + keys + colours

    private static readonly TagRect Screen = new(0, 0, 1600, 1040);

    [Fact]
    public void TagGoesLeftFirstThenFallsBack()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 400, 100, 30), 240, 80, Screen));
        Assert.Equal(TagSide.Left, r.Side);
        Assert.Equal(800 - 4 - 24 - 240, r.Tag.X);
        Assert.NotNull(r.Leader);
        var edge = TagLayout.Place(new TagLayoutInput(new TagRect(20, 400, 100, 30), 240, 80, Screen));
        Assert.Equal(TagSide.Right, edge.Side);
    }

    [Fact]
    public void BarsAndTitleBarControlsGoVertical()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 100, 30, 22), 240, 80, Screen, VerticalFirst: true));
        Assert.Equal(TagSide.Below, r.Side);
    }

    [Fact]
    public void StepPlacementWinsWhenItFits()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(800, 400, 100, 30), 240, 80, Screen, Placement: TagPlacement.Below));
        Assert.Equal(TagSide.Below, r.Side);
        var top = TagLayout.Place(new TagLayoutInput(new TagRect(800, 10, 100, 30), 240, 80, Screen, Placement: TagPlacement.Above));
        Assert.NotEqual(TagSide.Above, top.Side); // doesn't fit → automatic
    }

    [Fact]
    public void KeepOutPanelsAreCleared()
    {
        var panel = new TagRect(300, 850, 964, 164);
        var control = new TagRect(320, 870, 300, 28);
        var r = TagLayout.Place(new TagLayoutInput(control, 240, 80, Screen, Host: panel, KeepOut: panel, VerticalFirst: true));
        Assert.Equal(TagSide.Above, r.Side);
        Assert.True(r.Tag.Bottom <= panel.Y - 24 + 1e-6);
    }

    [Fact]
    public void BigControlsGoBesideTheWindowOrInsideTheCorner()
    {
        var host = new TagRect(100, 100, 1000, 700);
        var canvas = new TagRect(110, 150, 900, 600);
        Assert.True(TagLayout.IsBig(canvas, host));
        var r = TagLayout.Place(new TagLayoutInput(canvas, 240, 80, Screen, Host: host));
        Assert.Equal(TagSide.Right, r.Side); // left of the window doesn't fit, right does
        Assert.True(r.Tag.X >= host.Right);

        var full = new TagRect(0, 0, 1600, 1040);
        var inside = TagLayout.Place(new TagLayoutInput(new TagRect(10, 60, 1500, 900), 240, 80, Screen, Host: full));
        Assert.Equal(TagSide.InsideCorner, inside.Side);
        Assert.Null(inside.Leader);
        Assert.Equal(1510 - 16 - 240, inside.Tag.X);

        Assert.False(TagLayout.IsBig(new TagRect(110, 600, 900, 150), host)); // a wide strip isn't big
    }

    [Fact]
    public void NothingFitsGoesOver()
    {
        var r = TagLayout.Place(new TagLayoutInput(new TagRect(0, 0, 1600, 1040), 240, 80, Screen));
        Assert.Equal(TagSide.Over, r.Side);
        Assert.True(Screen.Inflate(-8).Contains(r.Tag) || Screen.Contains(r.Tag));
    }

    [Fact]
    public void TagNeverLeavesTheScreen()
    {
        foreach (var p in Enum.GetValues<TagPlacement>())
            foreach (var c in new[] { new TagRect(0, 0, 40, 40), new TagRect(1560, 1000, 40, 40), new TagRect(700, 500, 200, 40) })
            {
                var r = TagLayout.Place(new TagLayoutInput(c, 240, 80, Screen, Host: new TagRect(0, 0, 1600, 1040), Placement: p));
                Assert.True(Screen.Contains(r.Tag), $"{p} {c}");
            }
    }

    [Fact]
    public void LeaderIsStraightWhenSidesOverlap()
    {
        var box = new TagRect(400, 400, 100, 30).Inflate(4);
        var (from, to) = TagLayout.Leader(new TagRect(100, 380, 240, 80), TagSide.Left, box);
        Assert.Equal(from.Y, to.Y);
        Assert.Equal(340, from.X);
        Assert.Equal(box.X - 2, to.X);
    }

    [Fact]
    public void KeysAct()
    {
        Assert.Equal(TagKeyAction.Next, TagKeys.Action(TagKey.Enter, false, false, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, false, false)); // Try step
        Assert.Equal(TagKeyAction.SkipTour, TagKeys.Action(TagKey.Escape, false, false, false, false, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Escape, true, false, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, true, false, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, true, true, false));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Escape, false, false, false, true, false, hostClaimsEscape: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, true, false, hostClaimsKeys: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Enter, false, false, false, true, doneState: true));
        Assert.Equal(TagKeyAction.None, TagKeys.Action(TagKey.Other, false, false, false, true, false));
    }

    // ---------------------------------------------------------------- outline shape + tag style

    [Fact]
    public void OutlineIsConcentricAroundTheCapsulePill()
    {
        // The pill's capsule (radius 28) grown by the 4 padding: a 64-tall box → radius 32 = a capsule again.
        var pillBox = new TagRect(100, 100, 260, 56).Inflate(TagStyle.BoxPadding);
        Assert.Equal(32, TagStyle.OutlineRadius(pillBox, 28));
        Assert.Equal(pillBox.Height / 2, TagStyle.OutlineRadius(pillBox, 28));
        // Capped at half the short side (a 40-tall control with a big radius).
        Assert.Equal(20, TagStyle.OutlineRadius(new TagRect(0, 0, 200, 40), 50));
        // No declared shape → the default box radius; a square control → just the padding.
        Assert.Equal(TagStyle.BoxRadius, TagStyle.OutlineRadius(pillBox, null));
        Assert.Equal(4, TagStyle.OutlineRadius(new TagRect(0, 0, 100, 100), 0));
        // HudScale enlarges the pill: radius 28 × 1.35 stays concentric.
        var scaled = new TagRect(0, 0, 351, 75.6).Inflate(4);
        Assert.Equal(28 * 1.35 + 4, TagStyle.OutlineRadius(scaled, 28 * 1.35), 6);
    }

    [Fact]
    public void TagStyleStrings()
    {
        Assert.Equal("2 of 7", TagStyle.Counter(2, 7));
        Assert.Equal("Next", TagStyle.PrimaryTitle(isTry: false, isLast: false));
        Assert.Equal("Done", TagStyle.PrimaryTitle(isTry: false, isLast: true));
        Assert.Equal("Skip Step", TagStyle.PrimaryTitle(isTry: true, isLast: true));
        Assert.False(TagStyle.ShowsSkipTour(isLast: true, isExplain: true));
        Assert.True(TagStyle.ShowsSkipTour(isLast: true, isExplain: false));
        Assert.True(TagStyle.ShowsSkipTour(isLast: false, isExplain: true));
        Assert.False(TagStyle.ShowsSkipTour(isLast: true, isExplain: false, total: 1)); // "Skip Step" alone ends it
        Assert.Equal("Press Ctrl+Shift+Space now.".Replace("+", $"{(char)0x2060}+{(char)0x2060}"), TagStyle.KeepChordsTogether("Press Ctrl+Shift+Space now."));
        Assert.Equal("C++ stays", TagStyle.KeepChordsTogether("C++ stays"));
        Assert.Equal("press Ctrl+Alt+Shift+Win+F12 now", TagStyle.KeepChordsTogether("press Ctrl+Alt+Shift+Win+F12 now"));
        Assert.Equal(0.35, TagStyle.DimAlphaFor(hostIsDark: true));
        Assert.Equal(0.2, TagStyle.DimAlphaFor(hostIsDark: false));
        Assert.Equal("Opacity. Body. Step 9 of 10.", TagStyle.Announcement("Opacity", "Body.", 9, 10));
    }

    // ---------------------------------------------------------------- the Opacity demo timeline

    [Fact]
    public void OpacityDemoGoesDownUpAndBackLooping()
    {
        Assert.Equal(9.5, OpacityDemoTimeline.LoopDuration, 9);
        var f0 = OpacityDemoTimeline.FrameAt(0, 0.5);
        Assert.Equal(0.5, f0.Value, 9);
        Assert.Equal("Watch: 50 % ↓", f0.Readout);
        var mid = OpacityDemoTimeline.FrameAt(1.0, 0.5); // halfway down, smoothstep(0.5) = 0.5
        Assert.Equal(0.25, mid.Value, 9);
        Assert.Equal("Watch: 25 % ↓", mid.Readout);
        Assert.Equal(new OpacityDemoTimeline.Frame(0, "Watch: 0 % Transparent"), OpacityDemoTimeline.FrameAt(2.4, 0.5));
        var up = OpacityDemoTimeline.FrameAt(2.9 + 1.3, 0.5);
        Assert.Equal(0.5, up.Value, 9);
        Assert.EndsWith("↑", up.Readout);
        Assert.Equal(new OpacityDemoTimeline.Frame(1, "Watch: 100 % Opaque"), OpacityDemoTimeline.FrameAt(5.6, 0.5));
        var back = OpacityDemoTimeline.FrameAt(6.4 + 0.65, 0.5);
        Assert.Equal(0.75, back.Value, 9);
        Assert.Equal("Watch: 75 % ↓", back.Readout);
        Assert.Equal(new OpacityDemoTimeline.Frame(0.5, "Yours: 50 %"), OpacityDemoTimeline.FrameAt(8.0, 0.5));
        // Loops, and never leaves 0…1.
        Assert.Equal(OpacityDemoTimeline.FrameAt(1.0, 0.5).Value, OpacityDemoTimeline.FrameAt(1.0 + 9.5, 0.5).Value, 9);
        for (double t = -1; t < 20; t += 0.05)
            Assert.InRange(OpacityDemoTimeline.FrameAt(t, 0.37).Value, 0, 1);
        // Eased: the thumb slows into each end (a tiny step right at the start, a bigger one mid-move).
        double first = 1 - OpacityDemoTimeline.FrameAt(0.05, 1).Value;
        double middle = OpacityDemoTimeline.FrameAt(1.0, 1).Value - OpacityDemoTimeline.FrameAt(1.05, 1).Value;
        Assert.True(first < middle);
    }

    [Fact]
    public void OpacityDemoStartsFromTheUsersValueClamped()
    {
        Assert.Equal("Yours: 100 %", OpacityDemoTimeline.FrameAt(8.0, 7).Readout);
        Assert.Equal("Yours: 0 %", OpacityDemoTimeline.FrameAt(8.0, -3).Readout);
        Assert.Equal("Yours: 50 %", OpacityDemoTimeline.FrameAt(8.0, double.NaN).Readout);
        // From 0 the first move has no direction to show.
        Assert.Equal("Watch: 0 %", OpacityDemoTimeline.FrameAt(0.5, 0).Readout);
        Assert.Equal(37, OpacityDemoTimeline.Percent(0.37));
        Assert.Equal(1, OpacityDemoTimeline.Percent(0.005)); // half away from zero, like Swift's rounded()
    }

    // ---------------------------------------------------------------- catalog lint

    private static readonly Regex AnchorRx = new(@"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$");
    private static int Words(string s) => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(w => w.Any(char.IsLetterOrDigit));

    [Fact]
    public void CatalogMatchesTheMac()
    {
        Assert.Equal(new[] { TourId.Welcome, TourId.RecordingPill, TourId.Settings }, TourCatalog.All.Select(t => t.Id));
        Assert.Equal(new[] { "menuBar.icon", "welcome.shortcut", "welcome.tryIt" }, TourCatalog.Welcome.Steps.Select(s => s.Anchor));
        Assert.Equal(TourEvent.Action(TourEventName.RecordingStarted), TourCatalog.Welcome.Steps[2].AdvanceOn);
        Assert.Equal(TriggerKind.StartedByApp, TourCatalog.Welcome.Trigger.Kind);
        Assert.Equal("pill.controls", TourCatalog.RecordingPill.Steps.Single().Anchor);
        Assert.Equal(TourEvent.Action(TourEventName.RecordingStopped), TourCatalog.RecordingPill.Steps[0].AdvanceOn);
        Assert.Equal(TourTrigger.Shown(TourSurface.RecordingPill), TourCatalog.RecordingPill.Trigger);
        Assert.Equal(new[] { "settings.stats", "settings.model", "settings.processing", "settings.voiceStyle", "settings.appModes",
            "settings.shortcut", "settings.transcripts", "settings.customWords", "settings.appearance", "settings.help" },
            TourCatalog.Settings.Steps.Select(s => s.Anchor));
        Assert.All(TourCatalog.Settings.Steps, s => Assert.False(s.IsTry));
        Assert.Equal(OpacityDemoTimeline.Anchor, TourCatalog.Settings.Steps[8].Anchor);
        Assert.Equal("Opacity", TourCatalog.Settings.Steps[8].Title);
        Assert.DoesNotContain(TourCatalog.All.SelectMany(t => t.Steps), s => s.Body.Contains("Mac") || s.Body.Contains("menu bar"));
    }

    [Fact]
    public void CatalogLint()
    {
        foreach (var tour in TourCatalog.All)
        {
            Assert.NotEmpty(tour.Steps);
            // Titles are menu items (ⓘ → Show Me): unique within a tour.
            Assert.Equal(tour.Steps.Count, tour.Steps.Select(s => s.Title).Distinct().Count());
            foreach (var s in tour.Steps)
            {
                string where = $"{tour.Id}/{s.Title}";
                Assert.InRange(Words(s.Title), 1, 4);
                Assert.InRange(Words(s.Body), 1, 20);
                Assert.True(Regex.Split(s.Body.Trim(), @"(?<=[.!?…])\s+").Length <= 2, where);
                Assert.Matches(AnchorRx, s.Anchor);
                Assert.DoesNotContain("{", s.Title);
                foreach (var n in TourText.Names(s.Body)) Assert.Contains(n, TourText.KnownShortcuts);
                Assert.DoesNotContain("{", Regex.Replace(s.Body, @"\{shortcut:[A-Za-z0-9]+\}", ""));
                if (s.IsTry)
                {
                    string first = s.Body.Split(' ')[0].ToLowerInvariant();
                    Assert.DoesNotContain(first, new[] { "this", "these", "that", "the", "your", "a", "an", "here", "it", "you", "jvoice" });
                }
                foreach (var e in new[] { s.AdvanceOn, s.Requires }.Where(e => e is not null).Select(e => e!.Value))
                    Assert.Matches(AnchorRx, e.Name);
            }
        }
    }

    [Fact]
    public void LintBitesOnBadSamples()
    {
        Assert.DoesNotMatch(AnchorRx, "Settings.model");
        Assert.DoesNotMatch(AnchorRx, "settings");
        Assert.True(Words("This is a much too long title") > 4);
        Assert.Equal(1, Words("— {shortcut:toggleRecording} —"));
        Assert.False(BodyFits("Click into any text box, then press Ctrl+Alt+Shift+Win+F12 and say something much longer than two lines can ever hold."));
    }

    /// <summary>The bubble's body: Segoe UI Variable Text at <paramref name="size"/>, inside 260 − 2 × 12, at most
    /// <see cref="TagStyle.BodyMaxLines"/> lines (measured with WPF's own text layout).</summary>
    private static bool BodyFits(string text, double size = TagStyle.BodySize)
    {
        var face = new Typeface(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        var ft = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, size, Brushes.Black, 1.0)
        {
            MaxTextWidth = TagStyle.TagMaxWidth - 2 * TagStyle.TagPaddingX,
        };
        var one = new FormattedText("Ag", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, size, Brushes.Black, 1.0);
        return ft.Height <= one.Height * TagStyle.BodyMaxLines + 0.5;
    }

    [Fact]
    public void EveryBodyFitsTwoLinesWithTheLongestShortcut()
    {
        foreach (var s in TourCatalog.All.SelectMany(t => t.Steps))
        {
            // As the tag renders it: the chord's "+" joined, so it can't wrap between keys.
            string body = TagStyle.KeepChordsTogether(TourText.Resolve(s.Body, _ => TourText.LongestShortcut));
            Assert.True(BodyFits(body), $"{s.Title}: \"{body}\"");
            Assert.True(BodyFits(body, 13), $"{s.Title} at 13: \"{body}\""); // parity §10.7's stricter size
            string usual = TagStyle.KeepChordsTogether(TourText.Resolve(s.Body, _ => "Ctrl+Shift+Space")); // joined whole
            Assert.True(BodyFits(usual, 13), $"{s.Title} at 13: \"{usual}\"");
        }
    }

    [Fact]
    public void OpacityReadoutsFitTheTagToo()
    {
        var step = TourCatalog.Settings.Steps[8];
        var readouts = new HashSet<string>();
        for (double t = 0; t < OpacityDemoTimeline.LoopDuration; t += 0.01)
            foreach (var start in new[] { 0, 0.37, 0.5, 1 })
                readouts.Add(OpacityDemoTimeline.FrameAt(t, start).Readout);
        Assert.Contains("Watch: 0 % Transparent", readouts);
        Assert.Contains("Watch: 100 % Opaque", readouts);
        foreach (var r in readouts) Assert.True(BodyFits(step.Body + " " + r), r);
    }
}
