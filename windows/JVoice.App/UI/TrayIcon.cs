using System.Windows.Controls;
using System.Windows.Media.Imaging;
using H.NotifyIcon;

namespace JVoice.App.UI;

/// Ports MenuBarController.swift: the tray "J" with 3 activity states (idle "J" /
/// red mic / cyan waveform) and the menu (Start/Stop Dictation, Settings…,
/// Launch at Login ✓, Quit JVoice). Wraps H.NotifyIcon.Wpf's TaskbarIcon.
public sealed class TrayIcon : IDisposable
{
    public enum Activity { Idle, Recording, Transcribing }

    private readonly TaskbarIcon _icon;
    private readonly BitmapImage _idle = Load("tray-idle.png");
    private readonly BitmapImage _recording = Load("tray-recording.png");
    private readonly BitmapImage _transcribing = Load("tray-transcribing.png");
    private Activity _activity = Activity.Idle;

    // Wiring (set by App on construction).
    public Func<bool> IsRecording { get; set; } = () => false;
    public Func<bool> LaunchAtLoginEnabled { get; set; } = () => false;
    public Action OnToggleDictation { get; set; } = () => { };
    public Action OnOpenSettings { get; set; } = () => { };
    public Action OnToggleLaunchAtLogin { get; set; } = () => { };
    public Action OnQuit { get; set; } = () => { };

    public TrayIcon()
    {
        _icon = new TaskbarIcon
        {
            ToolTipText = "JVoice",
            IconSource = _idle,
        };
        // Rebuild the context menu each time it opens so item titles/checkmarks
        // reflect live state (mirrors NSMenuDelegate.menuNeedsUpdate).
        _icon.TrayContextMenuOpen += (_, _) => RebuildMenu();
        _icon.ContextMenu = new ContextMenu();
        _icon.ForceCreate(); // ensure the icon is shown immediately
    }

    private static BitmapImage Load(string file)
        => new(new Uri($"pack://application:,,,/Assets/{file}"));

    public void SetActivity(Activity activity)
    {
        if (_activity == activity) return;
        _activity = activity;
        _icon.IconSource = activity switch
        {
            Activity.Recording => _recording,
            Activity.Transcribing => _transcribing,
            _ => _idle,
        };
        _icon.ToolTipText = activity switch
        {
            Activity.Recording => "JVoice — recording",
            Activity.Transcribing => "JVoice — transcribing",
            _ => "JVoice",
        };
    }

    public void RebuildMenu()
    {
        var menu = new ContextMenu();

        var dictation = new MenuItem { Header = IsRecording() ? "Stop Dictation" : "Start Dictation" };
        dictation.Click += (_, _) => OnToggleDictation();
        menu.Items.Add(dictation);

        menu.Items.Add(new Separator());

        var settings = new MenuItem { Header = "Settings…" };
        settings.Click += (_, _) => OnOpenSettings();
        menu.Items.Add(settings);

        var launch = new MenuItem { Header = "Launch at Login", IsChecked = LaunchAtLoginEnabled() };
        launch.Click += (_, _) => OnToggleLaunchAtLogin();
        menu.Items.Add(launch);

        menu.Items.Add(new Separator());

        var quit = new MenuItem { Header = "Quit JVoice" };
        quit.Click += (_, _) => OnQuit();
        menu.Items.Add(quit);

        _icon.ContextMenu = menu;
    }

    public void Dispose() => _icon.Dispose();
}
