using System.Windows;
using System.Windows.Input;
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.UI;

/// A button-like control. Click -> "Press a key..." capture -> next key+modifiers
/// becomes the HotkeyChord. Esc or Tab cancels; Backspace/Delete resets to default (or clears,
/// with <see cref="AllowClear"/>). The rules are <see cref="ShortcutCapturePolicy"/> (parity row
/// 18): a bare key (except F1–F24) or Shift alone is rejected, and a well-formed chord can still be
/// refused by <see cref="Validate"/> — either way the reason is raised through
/// <see cref="NoticeChanged"/> and the recorder keeps listening.
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

    /// Why a chord <see cref="ShortcutCapturePolicy.Decide"/> accepted must still be refused, or
    /// null when it is free (the other action's chord, a Windows/app shortcut, …).
    public Func<HotkeyChord, string?>? Validate { get; set; }

    /// The reason line for the row under the recorder; null clears it.
    public event Action<string?>? NoticeChanged;

    /// Raised when listening starts / stops — the owner suspends the global hooks meanwhile, or
    /// the chord being recorded would be swallowed (or would start a dictation).
    public event Action? CaptureStarted;
    public event Action? CaptureEnded;

    public HotkeyRecorder()
    {
        Focusable = true;
        Content = HotkeyChord.Default.Format();
        Click += (_, _) => BeginCapture();
        LostFocus += (_, _) => EndCapture();
        // Deactivating or closing the window also ends listening, so the hooks come back.
        LostKeyboardFocus += (_, _) => EndCapture();
        Unloaded += (_, _) => EndCapture();
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
        if (!_capturing) CaptureStarted?.Invoke();
        _capturing = true;
        NoticeChanged?.Invoke(null);
        Content = "Press a key...";
        Focus();
        Keyboard.Focus(this);
    }

    private void EndCapture()
    {
        if (!_capturing) return;
        _capturing = false;
        Content = _cleared ? Placeholder : Chord.Format();
        CaptureEnded?.Invoke();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (!_capturing) { base.OnPreviewKeyDown(e); return; }
        e.Handled = true;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return; // wait for a non-modifier key

        var mods = HotkeyModifiers.None;
        var m = Keyboard.Modifiers;
        if (m.HasFlag(ModifierKeys.Control)) mods |= HotkeyModifiers.Control;
        if (m.HasFlag(ModifierKeys.Alt))     mods |= HotkeyModifiers.Alt;
        if (m.HasFlag(ModifierKeys.Shift))   mods |= HotkeyModifiers.Shift;
        if (m.HasFlag(ModifierKeys.Windows)) mods |= HotkeyModifiers.Win;
        int vk = KeyInterop.VirtualKeyFromKey(key);

        var captureKey = key switch
        {
            Key.Escape => ShortcutCapturePolicy.CaptureKey.Escape,
            Key.Tab => ShortcutCapturePolicy.CaptureKey.Tab,
            Key.Back or Key.Delete => ShortcutCapturePolicy.CaptureKey.Delete,
            _ => ShortcutCapturePolicy.CaptureKey.Other,
        };
        var decision = ShortcutCapturePolicy.Decide(captureKey, mods, vk);
        if (decision == ShortcutCapturePolicy.Decision.Cancel) { EndCapture(); return; }
        if (decision == ShortcutCapturePolicy.Decision.Reject)
        {
            NoticeChanged?.Invoke(ShortcutCapturePolicy.RejectMessage(mods));
            return; // keep listening
        }
        if (decision == ShortcutCapturePolicy.Decision.Clear)
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

        string name = key == Key.Space ? "Space" : key.ToString();
        var chord = new HotkeyChord(mods, vk, name);
        if (Validate?.Invoke(chord) is { } reason)
        {
            NoticeChanged?.Invoke(reason);
            return; // keep listening
        }
        NoticeChanged?.Invoke(null);
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
