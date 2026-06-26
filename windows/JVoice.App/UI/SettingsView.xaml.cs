using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using JVoice.Core;

namespace JVoice.App.UI;

public partial class SettingsView : UserControl
{
    private VoiceCoordinator Vm => (VoiceCoordinator)DataContext;

    public SettingsView()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            Recorder.Chord = Vm.Hotkey;
            Recorder.ChordChanged += chord => Vm.SetHotkey(chord);
            // Keep the recorder in sync when the coordinator changes the hotkey itself
            // (e.g. Restore Defaults). Setting Recorder.Chord only updates its display —
            // it does NOT raise ChordChanged — so this can't loop back into SetHotkey.
            // One SettingsView instance lives for the app's lifetime (the window is hidden,
            // not destroyed), so this subscription doesn't accumulate.
            Vm.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName == nameof(VoiceCoordinator.Hotkey)) Recorder.Chord = Vm.Hotkey;
            };
        };
    }

    private void OnAddWord(object sender, RoutedEventArgs e) => SubmitWord();
    private void OnNewWordKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { SubmitWord(); e.Handled = true; }
    }
    private void SubmitWord()
    {
        Vm.AddCustomWord(NewWordBox.Text);
        NewWordBox.Clear();
    }

    private void OnRemoveWord(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is string word)
            Vm.RemoveCustomWord(word);
    }

    private void OnAddCorrection(object sender, RoutedEventArgs e) => SubmitCorrection();
    private void OnCorrectionKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { SubmitCorrection(); e.Handled = true; }
    }
    private void SubmitCorrection()
    {
        // Clear only on a successful add (AddCorrection ignores blank/duplicate input).
        if (Vm.AddCorrection(CorrectionFromBox.Text, CorrectionToBox.Text))
        {
            CorrectionFromBox.Clear();
            CorrectionToBox.Clear();
            CorrectionFromBox.Focus();
        }
    }

    private void OnRemoveCorrection(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is JVoice.Core.Models.CorrectionRule rule)
            Vm.RemoveCorrection(rule);
    }

    // ---- Recent Transcripts ----

    private void OnCopyTranscript(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement fe || fe.DataContext is not TranscriptRow row) return;

        try { Clipboard.SetText(row.Text); }
        catch { return; } // clipboard busy — no checkmark feedback, nothing copied

        // Flash a checkmark, then flip back after ~1.2s.
        row.JustCopied = true;
        var timer = new DispatcherTimer { Interval = AppTimings.CopyFeedbackDuration };
        timer.Tick += (_, _) => { timer.Stop(); row.JustCopied = false; };
        timer.Start();
    }

    private void OnDeleteTranscript(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.DataContext is TranscriptRow row)
            Vm.RemoveRecentTranscript(row.Id);
    }

    private void OnClearTranscripts(object sender, RoutedEventArgs e) => Vm.ClearRecentTranscripts();

    private void OnRestoreDefaults(object sender, RoutedEventArgs e)
    {
        var r = MessageBox.Show(
            "Your custom words, corrections, recent transcripts, model choice, and language will be restored to defaults — your recent transcripts will be cleared. Recording statistics will not be affected.",
            "Reset all JVoice settings to defaults?",
            MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (r == MessageBoxResult.OK) Vm.ResetSettings();
    }

    private void OnQuit(object sender, RoutedEventArgs e) => Vm.QuitApp();
}
