using System.ComponentModel;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Threading;
using JVoice.App.Tours;
using JVoice.Core.Tours;

namespace JVoice.App.UI;

/// <summary>
/// JVoice's first-run window (parity §10.2; Mac <c>WelcomeWindow.swift</c>) — shown at launch to NEW users who haven't
/// answered "Want a quick tour?" (never to David: <see cref="TourAudience"/> decides once). Also opened on its second
/// page, without the question, by Help &amp; Tours → Welcome Tour.
///
/// Closing it before the question was answered counts as No Thanks, on either page: JVoice launches at login, so a
/// first-run window that came back every login until clicked through would nag the very people it welcomes. Quitting
/// JVoice with it open is not an answer (it asks again next launch).
/// </summary>
public sealed class WelcomeWindow : Window
{
    private readonly WelcomeView _view = new();
    private readonly WelcomeModel _model = new();
    private readonly VoiceCoordinator _coordinator;
    private readonly DispatcherTimer _poll;

    /// <summary>The answer: true = Show Me Around (with this window, so the Welcome tour runs over it).</summary>
    public Action<bool, Window>? OnTourAnswer { get; set; }

    /// <summary>Set when JVoice is quitting, so closing isn't taken as "No Thanks".</summary>
    public static bool AppIsQuitting { get; set; }

    public WelcomeWindow(VoiceCoordinator coordinator, bool askQuestion, bool startOnAllSet)
    {
        _coordinator = coordinator;
        Title = "Welcome to JVoice";
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = true;
        Theme.Attach(this);
        SetResourceReference(TextElement.ForegroundProperty, "Text.Primary");

        _model.PendingQuestion = askQuestion;
        _model.IsPermissionsPage = !startOnAllSet;
        Refresh();
        _view.DataContext = _model;
        _view.SetInfoButton(new InfoButton(TourId.Welcome, () => Shortcuts(coordinator)));
        _view.Continue += () => _model.IsPermissionsPage = false;
        _view.Answer += Answer;
        _view.StartDictating += Close;
        Content = _view;

        // The microphone row follows a change made in Windows Settings while the window is up (once a second, only
        // while it's open — new users only, so this never runs on an existing install).
        _poll = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(1) };
        _poll.Tick += (_, _) => Refresh();
        IsVisibleChanged += (_, _) => { if (IsVisible) _poll.Start(); else _poll.Stop(); };
        coordinator.PropertyChanged += OnCoordinatorChanged;

        ContentRendered += (_, _) => TourEvents.SurfaceShown(TourSurface.Welcome, this);
        Closing += OnClosing;
        s_open = this;
        Closed += (_, _) =>
        {
            if (s_open == this) s_open = null;
            _poll.Stop();
            coordinator.PropertyChanged -= OnCoordinatorChanged;
        };
    }

    /// <summary>The ⓘ's Keyboard Shortcuts list (Settings uses the same).</summary>
    public static IReadOnlyList<(string Keys, string Action)> Shortcuts(VoiceCoordinator c)
    {
        var list = new List<(string, string)> { (c.Hotkey.Format(), "Start / stop dictation") };
        if (c.UndoHotkey is { } undo) list.Add((undo.Format(), "Undo last paste"));
        return list;
    }

    public void ShowAllSet()
    {
        _model.IsPermissionsPage = false;
        if (!IsVisible)
        {
            JVoice.App.Platform.ActiveScreen.CenterBeforeShow(this, SettingsWindow.OuterSizeEstimate(this, _view));
            Show();
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    private static WelcomeWindow? s_open;

    /// <summary>True when <paramref name="hwnd"/> is the open Welcome window and its try-it box has the keyboard:
    /// a dictation stopped there pastes into the box (JVoice's own windows are otherwise never a paste target).
    /// UI thread only.</summary>
    public static bool AcceptsDictation(IntPtr hwnd) =>
        s_open is { } w && hwnd != IntPtr.Zero && new System.Windows.Interop.WindowInteropHelper(w).Handle == hwnd
        && w._view.TryBoxHasKeyboard;

    private void OnCoordinatorChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(VoiceCoordinator.Hotkey) or nameof(VoiceCoordinator.UndoHotkey)) Refresh();
    }

    private void Refresh()
    {
        _model.ToggleShortcut = _coordinator.Hotkey.Format();
        _model.UndoShortcut = _coordinator.UndoHotkey?.Format();
        _model.MicrophoneAllowed = WelcomeModel.ReadMicrophoneAllowed();
    }

    private void Answer(bool showMeAround)
    {
        if (!_model.PendingQuestion) return;
        _model.PendingQuestion = false;
        OnTourAnswer?.Invoke(showMeAround, this);
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_model.PendingQuestion && !AppIsQuitting) Answer(false);
    }
}
