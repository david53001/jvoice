using System.Windows;
using System.Windows.Input;
using JVoice.Core.Models;

namespace JVoice.App.UI;

/// A button-like control. Click -> "Press a key..." capture -> next key+modifiers
/// becomes the HotkeyChord. Esc cancels; Backspace/Delete resets to default.
public sealed class HotkeyRecorder : System.Windows.Controls.Button
{
    private bool _capturing;

    public static readonly DependencyProperty ChordProperty = DependencyProperty.Register(
        nameof(Chord), typeof(HotkeyChord), typeof(HotkeyRecorder),
        new FrameworkPropertyMetadata(HotkeyChord.Default,
            FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnChordChanged));

    public HotkeyChord Chord
    {
        get => (HotkeyChord)GetValue(ChordProperty);
        set => SetValue(ChordProperty, value);
    }

    public event Action<HotkeyChord>? ChordChanged;

    /// When true this recorder supports an "unset" state: Backspace/Delete (and the external
    /// <see cref="ShowCleared"/>) show <see cref="Placeholder"/> and raise <see cref="Cleared"/>
    /// instead of resetting to the default chord. Off by default, so the main record recorder keeps
    /// its "Backspace = restore default" behavior; the opt-in undo recorder turns it on.
    public bool AllowClear { get; set; }
    public string Placeholder { get; set; } = "None";
    public event Action? Cleared;
    private bool _cleared;

    public HotkeyRecorder()
    {
        Focusable = true;
        Content = HotkeyChord.Default.Format();
        Click += (_, _) => BeginCapture();
        LostFocus += (_, _) => EndCapture();
    }

    /// Put the recorder into the unset/placeholder display state (external sync; does NOT raise
    /// Cleared). Used when the bound value is "disabled/none".
    public void ShowCleared()
    {
        _cleared = true;
        if (!_capturing) Content = Placeholder;
    }

    private static void OnChordChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var r = (HotkeyRecorder)d;
        if (r._capturing) return;
        r._cleared = false; // an externally-set chord is a real value, not the unset state
        r.Content = ((HotkeyChord)e.NewValue).Format();
    }

    private void BeginCapture()
    {
        _capturing = true;
        Content = "Press a key...";
        Focus();
        Keyboard.Focus(this);
    }

    private void EndCapture()
    {
        if (!_capturing) return;
        _capturing = false;
        Content = _cleared ? Placeholder : Chord.Format();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (!_capturing) { base.OnPreviewKeyDown(e); return; }
        e.Handled = true;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return; // wait for a non-modifier key

        if (key == Key.Escape) { EndCapture(); return; }
        if (key is Key.Back or Key.Delete)
        {
            if (AllowClear)
            {
                _cleared = true;
                EndCapture();          // shows Placeholder (since _cleared)
                Cleared?.Invoke();
                return;
            }
            SetChord(HotkeyChord.Default);
            EndCapture();
            return;
        }

        var mods = HotkeyModifiers.None;
        var m = Keyboard.Modifiers;
        if (m.HasFlag(ModifierKeys.Control)) mods |= HotkeyModifiers.Control;
        if (m.HasFlag(ModifierKeys.Alt))     mods |= HotkeyModifiers.Alt;
        if (m.HasFlag(ModifierKeys.Shift))   mods |= HotkeyModifiers.Shift;
        if (m.HasFlag(ModifierKeys.Windows)) mods |= HotkeyModifiers.Win;

        int vk = KeyInterop.VirtualKeyFromKey(key);
        string name = key == Key.Space ? "Space" : key.ToString();
        var chord = new HotkeyChord(mods, vk, name);
        SetChord(chord);
        EndCapture();
    }

    private void SetChord(HotkeyChord chord)
    {
        _cleared = false;
        Chord = chord;
        ChordChanged?.Invoke(chord);
    }
}
