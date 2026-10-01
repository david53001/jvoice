using System.Windows;
using System.Windows.Documents;

namespace JVoice.App.UI;

/// Real focusable app window hosting SettingsView. Ports SettingsWindow.swift
/// (titled "Settings", centered, hidden — not destroyed — on close).
public sealed class SettingsWindow : Window
{
    private readonly SettingsView _view = new();

    public SettingsWindow(VoiceCoordinator coordinator)
    {
        Title = "Settings";
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        SizeToContent = SizeToContent.WidthAndHeight;
        // Never let SizeToContent grow the window past the screen's work area — otherwise the
        // title bar (and its close button) can be pushed off the top of the screen, which is
        // exactly what happened at David's non-native 1600x1080 desktop. WorkArea is in DIPs
        // (WPF units); the small margin keeps the window off the very edges. If the content ever
        // exceeds this cap, the view's inner ScrollViewer scrolls instead of the X going away.
        MaxHeight = SystemParameters.WorkArea.Height - 16;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = true; // a real app window while open
        // The native look: Mica behind a Window.Backing layer (Opacity), title bar follows the theme.
        Theme.Attach(this);
        SetResourceReference(TextElement.ForegroundProperty, "Text.Primary");
        _view.DataContext = coordinator;
        Content = _view;
        // Don't destroy on close — hide so a re-open is instant and state persists.
        Closing += (s, e) => { e.Cancel = true; Hide(); };
    }

    public void ShowOrActivate()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true; Topmost = false; // bring to front then release topmost
        Focus();
    }
}
