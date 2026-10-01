namespace JVoice.Core.Tours;

/// <summary>
/// Every JVoice tour, as data (Mac <c>TourCatalog.swift</c>, verbatim with the parity doc §10.3 Windows wording:
/// "tray icon", "this PC"). Anchor ids are <c>AutomationProperties.AutomationId</c>s on real controls; Try steps wait
/// for the <see cref="TourEventName"/> the app posts. Copy rules (lint-tested in <c>TourTests</c>): title ≤ 4 words,
/// body ≤ 20 words, Try steps start with a verb, titles unique within a tour, bodies fit 2 lines at 260 with the
/// longest shortcut.
/// </summary>
public static class TourCatalog
{
    private static TourStep E(string anchor, string title, string body) => new(anchor, title, body);

    private static TourStep T(string anchor, string title, string body, string advanceOn) =>
        new(anchor, title, body, TourEvent.Action(advanceOn));

    /// <summary>The tray icon's anchor id (no window: the overlay finds it with Shell_NotifyIconGetRect).</summary>
    public const string TrayIconAnchor = "menuBar.icon";

    /// <summary>Started by "Show Me Around" on the Welcome window, by Help &amp; Tours or a replay; hosted by Welcome.</summary>
    public static readonly Tour Welcome = new(TourId.Welcome, TourSurface.Welcome, TourTrigger.ByApp, new[]
    {
        E(TrayIconAnchor, "Your tray icon",
            "JVoice lives here, by the clock. Click it to start dictating, open Settings or quit."),
        E("welcome.shortcut", "Your dictation shortcut",
            "Press {shortcut:toggleRecording} in any app to start talking. Press it again to stop."),
        T("welcome.tryIt", "Try it now",
            "Click into any text box, then press {shortcut:toggleRecording} and say something.", TourEventName.RecordingStarted),
    });

    /// <summary>The first recording's pill. One Try step: the user is talking, so nothing asks for a click.</summary>
    public static readonly Tour RecordingPill = new(TourId.RecordingPill, TourSurface.RecordingPill,
        TourTrigger.Shown(TourSurface.RecordingPill), new[]
    {
        // Windows wording: the Mac's "…again or click ■. Your words get typed for you." runs to 3 lines with the longest
        // Windows chord ("Ctrl+Alt+Shift+Win+F12" is far wider than ⌃⌥⇧⌘F12), so "again" and "for you" are dropped.
        T("pill.controls", "JVoice is listening",
            "Speak, then press {shortcut:toggleRecording} or click ■. Your words get typed.", TourEventName.RecordingStopped),
    });

    /// <summary>The first Settings window. The coordinator scrolls each anchor into view before its tag shows.</summary>
    public static readonly Tour Settings = new(TourId.Settings, TourSurface.Settings, TourTrigger.Shown(TourSurface.Settings), new[]
    {
        E("settings.stats", "Your stats", "Words dictated, your speaking speed and the typing time you saved."),
        E("settings.model", "Speech model", "Bigger models are more accurate but slower. Everything runs on this PC."),
        E("settings.processing", "Clean-up options", "Drop filler words, turn spoken maths into symbols, and more."),
        E("settings.voiceStyle", "Voice style", "Choose how your text comes out, from very casual to formal."),
        E("settings.appModes", "App modes", "Give an app its own style, like Code in your editor."),
        E("settings.shortcut", "Your shortcut", "Click the shortcut, then press new keys to change it. Esc cancels."),
        E("settings.transcripts", "Recent transcripts", "Your last dictations, kept on this PC. Hover one to copy it again."),
        E("settings.customWords", "Custom words", "Add names and jargon so JVoice always spells them your way."),
        E(OpacityDemoTimeline.Anchor, "Opacity", "Sets how see-through JVoice's windows and pill are."),
        E("settings.help", "Replay any tour", "Click ⓘ to replay this tour, or pick one part to see again."),
    });

    public static readonly IReadOnlyList<Tour> All = new[] { Welcome, RecordingPill, Settings };

    public static Tour Get(TourId id) => All.First(t => t.Id == id);
}
