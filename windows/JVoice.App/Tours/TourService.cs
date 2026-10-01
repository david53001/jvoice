using System.Windows;
using JVoice.App.Platform;
using JVoice.App.UI;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// The app's tour wiring (Mac <c>AppDelegate</c>'s tour part): one <see cref="TourCoordinator"/> with tours.json, the tag
/// overlay, the tray icon as an extra anchor host, the Opacity demo, the Welcome window and the HUD notices; installed
/// on <see cref="TourEvents"/> so surfaces can post. Only ever writes tours.json.
/// </summary>
public sealed class TourService
{
    private readonly VoiceCoordinator _coordinator;
    private readonly TrayTourHost _trayHost;
    private WelcomeWindow? _welcome;

    public TourCoordinator Tours { get; }

    public TourService(VoiceCoordinator coordinator, TourPrefs prefs, TrayIcon tray)
    {
        _coordinator = coordinator;
        _trayHost = new TrayTourHost(() => tray.Identity);
        Tours = new TourCoordinator(prefs, () => TourStore.Save(prefs), () => new TagOverlay(), ShortcutText,
            new DispatcherTourClock(Application.Current.Dispatcher))
        {
            OpenSurface = OpenSurface,
            Notify = coordinator.ShowTourNotice,
            OnFinished = id => { if (id == TourId.Welcome) _welcome?.Close(); },
            ExtraAnchorHosts = () => new ITourHost[] { _trayHost },
            MakeDemo = step => step.Anchor == OpacityDemoTimeline.Anchor ? new OpacityTourDemo(coordinator) : null,
        };
        TourEvents.Coordinator = Tours;
    }

    /// <summary>"Show Me Around" (Settings → Tours &amp; Tips), bound two-way.</summary>
    public bool FirstUseToursEnabled
    {
        get => Tours.FirstUseToursEnabled;
        set => Tours.FirstUseToursEnabled = value;
    }

    /// <summary>At launch: a new user who hasn't answered gets the Welcome window. Never an existing user.</summary>
    public void ShowWelcomeIfNeeded()
    {
        if (!Tours.ShouldOpenWelcomeOnLaunch) return;
        DiagnosticLog.Write("Tours: new user, showing the Welcome window");
        ShowWelcome(allSet: false);
    }

    /// <summary>Opens (or brings back) the Welcome window; on page 2 for Help &amp; Tours → Welcome Tour.</summary>
    public void ShowWelcome(bool allSet)
    {
        if (_welcome is { IsLoaded: true })
        {
            if (allSet) _welcome.ShowAllSet();
            else _welcome.Activate();
            return;
        }
        _welcome = new WelcomeWindow(_coordinator, askQuestion: Tours.ShouldAskQuestion, startOnAllSet: allSet)
        {
            OnTourAnswer = (yes, window) => Tours.AnswerQuestion(yes, WindowTourHost.For(window)),
        };
        _welcome.Closed += (_, _) => _welcome = null;
        ActiveScreen.CenterBeforeShow(_welcome, SettingsWindow.OuterSizeEstimate(_welcome, (FrameworkElement)_welcome.Content));
        _welcome.Show();
        _welcome.Activate();
    }

    private bool OpenSurface(TourSurface surface)
    {
        switch (surface)
        {
            case TourSurface.Welcome: ShowWelcome(allSet: true); return true;
            case TourSurface.Settings: _coordinator.ShowSettings(); return true;
            default: return false; // the pill appears only with a recording
        }
    }

    private string? ShortcutText(string name) => name switch
    {
        "toggleRecording" => _coordinator.Hotkey.Format(),
        "undoLastPaste" => _coordinator.UndoHotkey?.Format() ?? TourText.UnboundShortcut,
        _ => null,
    };
}
