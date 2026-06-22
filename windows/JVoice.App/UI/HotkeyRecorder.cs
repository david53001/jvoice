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

    public HotkeyRecorder()
    {
        Focusable = true;
        Content = HotkeyChord.Default.Format();
        Click += (_, _) => BeginCapture();
        LostFocus += (_, _) => EndCapture();
    }

    private static void OnChordChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var r = (HotkeyRecorder)d;
        if (!r._capturing) r.Content = ((HotkeyChord)e.NewValue).Format();
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
        Content = Chord.Format();
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
        Chord = chord;
        ChordChanged?.Invoke(chord);
    }
}
