using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using JVoice.App.Platform;
using Microsoft.Win32;

namespace JVoice.App.UI;

/// <summary>What the Welcome window shows (parity §10.2): the page, the live shortcuts, the microphone status, the question.</summary>
public sealed class WelcomeModel : INotifyPropertyChanged
{
    private bool _isPermissionsPage = true;
    private bool _pendingQuestion;
    private bool _microphoneAllowed;
    private string _toggleShortcut = "";
    private string? _undoShortcut;

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool IsPermissionsPage { get => _isPermissionsPage; set => Set(ref _isPermissionsPage, value); }
    /// <summary>A new user who hasn't answered "Want a quick tour?" yet.</summary>
    public bool PendingQuestion { get => _pendingQuestion; set => Set(ref _pendingQuestion, value); }
    public bool MicrophoneAllowed { get => _microphoneAllowed; set => Set(ref _microphoneAllowed, value); }

    public string ToggleShortcut
    {
        get => _toggleShortcut;
        set { if (Set(ref _toggleShortcut, value)) { Raise(nameof(Intro)); Raise(nameof(TryIt)); } }
    }

    public string? UndoShortcut
    {
        get => _undoShortcut;
        set { if (Set(ref _undoShortcut, value)) Raise(nameof(HasUndoShortcut)); }
    }

    public bool HasUndoShortcut => _undoShortcut is not null;

    public string Intro =>
        $"Press {ToggleShortcut} anywhere, talk, press it again — your words are typed for you. Everything stays on this PC.";

    public string TryIt => $"Try it: click into any text box and press {ToggleShortcut}";

    /// <summary>
    /// Windows' microphone privacy switches, read-only: the global "Microphone access" and "Let desktop apps access
    /// your microphone" (the ConsentStore values; absent = Windows' default, Allow).
    /// </summary>
    public static bool ReadMicrophoneAllowed()
    {
        const string root = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
        try
        {
            foreach (var path in new[] { root, root + @"\NonPackaged" })
            {
                using var key = Registry.CurrentUser.OpenSubKey(path);
                if (key?.GetValue("Value") is string v && string.Equals(v, "Deny", StringComparison.OrdinalIgnoreCase)) return false;
            }
            return true;
        }
        catch { return true; }
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name!);
        return true;
    }

    private void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public partial class WelcomeView : UserControl
{
    public event Action? Continue;
    public event Action<bool>? Answer;
    public event Action? StartDictating;

    public WelcomeView()
    {
        InitializeComponent();
        AppIcon.Source = LargestIconFrame();
    }

    /// <summary>The app icon's biggest frame — an Image given the .ico takes its FIRST (smallest) frame and blurs it.</summary>
    private static System.Windows.Media.ImageSource? LargestIconFrame()
    {
        try
        {
            var uri = new Uri("pack://application:,,,/Assets/JVoice.ico");
            var decoder = System.Windows.Media.Imaging.BitmapDecoder.Create(uri,
                System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
            return decoder.Frames.OrderByDescending(f => f.PixelWidth).FirstOrDefault();
        }
        catch (Exception) { return null; }
    }

    /// <summary>Puts the ⓘ in the top-right corner.</summary>
    public void SetInfoButton(FrameworkElement button) => InfoHost.Content = button;

    /// <summary>The try-it box has the keyboard (so a dictation should land in it).</summary>
    public bool TryBoxHasKeyboard => TryBox.IsKeyboardFocused;

    private void OnContinue(object sender, RoutedEventArgs e) => Continue?.Invoke();
    private void OnShowMeAround(object sender, RoutedEventArgs e) => Answer?.Invoke(true);
    private void OnNoThanks(object sender, RoutedEventArgs e) => Answer?.Invoke(false);
    private void OnStartDictating(object sender, RoutedEventArgs e) => StartDictating?.Invoke();
    private void OnOpenMicSettings(object sender, RoutedEventArgs e) => SettingsUris.OpenMicrophoneSettings();
}
