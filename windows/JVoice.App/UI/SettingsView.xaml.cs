using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

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
            Vm.SyncEditedTranscriptFromLast();
        };
        Unloaded += (_, _) => Vm.ClearRevertBuffer();
    }

    private void OnFix(object sender, RoutedEventArgs e) => Vm.FixLastTranscript(Vm.EditedTranscript);
    private void OnRevert(object sender, RoutedEventArgs e) => Vm.RevertLastFix();

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

    private void OnRestoreDefaults(object sender, RoutedEventArgs e)
    {
        var r = MessageBox.Show(
            "Your custom words, corrections, model choice, and language will be restored to defaults. Recording statistics will not be affected.",
            "Reset all JVoice settings to defaults?",
            MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (r == MessageBoxResult.OK) Vm.ResetSettings();
    }

    private void OnQuit(object sender, RoutedEventArgs e) => Vm.QuitApp();
}
