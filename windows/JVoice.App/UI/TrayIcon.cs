using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;

namespace JVoice.App.UI;

/// Ports MenuBarController.swift: the tray "J" with 3 activity states (idle "J" /
/// red mic / cyan waveform) and the menu (Start/Stop Dictation, Settings…,
/// Launch at Login ✓, Quit JVoice). Wraps H.NotifyIcon.Wpf's TaskbarIcon.
///
/// Tray icons are set via the System.Drawing.Icon `Icon` property (converted from
/// the embedded PNGs), NOT `IconSource` — H.NotifyIcon feeds an IconSource PNG to
/// `new System.Drawing.Icon(stream)`, which only accepts .ico bytes and throws on PNG.
public sealed class TrayIcon : IDisposable
{
    public enum Activity { Idle, Recording, Transcribing }

    private readonly TaskbarIcon _icon;
    private readonly Icon _idle = LoadIcon("tray-idle.png");
    private readonly Icon _recording = LoadIcon("tray-recording.png");
    private readonly Icon _transcribing = LoadIcon("tray-transcribing.png");
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
            Icon = _idle,
        };
        // Rebuild the context menu each time it opens so item titles/checkmarks
        // reflect live state (mirrors NSMenuDelegate.menuNeedsUpdate).
        _icon.TrayContextMenuOpen += (_, _) => RebuildMenu();
        _icon.ContextMenu = new ContextMenu();
        // enablesEfficiencyMode: false — the default (true) calls SetProcessInformation
        // (process QoS/power throttling), which throws COMException 0x80070001
        // ("Incorrect function") on some Windows builds and crashes startup.
        _icon.ForceCreate(enablesEfficiencyMode: false); // ensure the icon is shown immediately
    }

    /// Load an embedded PNG (WPF Resource) and convert it to a System.Drawing.Icon
    /// via a 32-bit HICON (the tray API speaks HICON, not ImageSource).
    private static Icon LoadIcon(string file)
    {
        var uri = new Uri($"pack://application:,,,/Assets/{file}");
        using var stream = System.Windows.Application.GetResourceStream(uri)!.Stream;
        using var bmp = new Bitmap(stream);
        return Icon.FromHandle(bmp.GetHicon());
    }

    public void SetActivity(Activity activity)
    {
        if (_activity == activity) return;
        _activity = activity;
        _icon.Icon = activity switch
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
