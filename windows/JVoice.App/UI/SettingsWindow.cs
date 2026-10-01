using System.Windows;
using System.Windows.Documents;
using JVoice.App.Platform;

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
        // The tour tag's Enter/Esc go to a shortcut recorder while it listens ("claims keys").
        JVoice.App.Tours.WindowTourHost.For(this).KeysClaimed = () => _view.IsCapturingShortcut;
        // Don't destroy on close — hide so a re-open is instant and state persists.
        Closing += (s, e) => { e.Cancel = true; Hide(); };
    }

    public void ShowOrActivate()
    {
        // Parity row 34: opening from hidden centres it on the monitor with the mouse pointer, placed BEFORE it
        // shows (no flash on the old monitor). Already open → just brought forward.
        if (!IsVisible) ActiveScreen.CenterBeforeShow(this, OuterSizeEstimate(this, _view));
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true; Topmost = false; // bring to front then release topmost
        Focus();
    }

    /// <summary>A window's outer size in DIPs before it shows: its last size once it has been shown, else its content's
    /// desired size plus the title bar and frame (SizeToContent sizes the HWND only on the first show).</summary>
    internal static Size OuterSizeEstimate(Window window, FrameworkElement content)
    {
        if (window.ActualWidth > 0 && window.ActualHeight > 0) return new Size(window.ActualWidth, window.ActualHeight);
        content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var frame = SystemParameters.WindowResizeBorderThickness;
        double h = Math.Min(content.DesiredSize.Height + SystemParameters.WindowCaptionHeight + frame.Top + frame.Bottom, window.MaxHeight);
        return new Size(content.DesiredSize.Width + frame.Left + frame.Right, h);
    }
}
