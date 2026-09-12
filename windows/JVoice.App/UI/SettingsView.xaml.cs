using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using JVoice.App.Platform;
using JVoice.Core;
using JVoice.Core.Models;

namespace JVoice.App.UI;

public partial class SettingsView : UserControl
{
    private VoiceCoordinator Vm => (VoiceCoordinator)DataContext;

    // The mode a new app-rule will be added with; cycled by the chip button in the add row.
    private ToneStyle _appRuleMode = ToneStyle.Code;

    public SettingsView()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            Recorder.Chord = Vm.Hotkey;
            Recorder.ChordChanged += chord => Vm.SetHotkey(chord);

            // Undo-last-paste recorder: opt-in, so it supports an "unset" (None) state — Backspace
            // clears it instead of arming the default (record) chord.
            UndoRecorder.AllowClear = true;
            SyncUndoRecorder();
            UndoRecorder.ChordChanged += chord => Vm.SetUndoHotkey(chord);
            UndoRecorder.Cleared += () => Vm.ClearUndoHotkey();

            // App-rule mode chip: seed its label from the default add-mode.
            AppRuleModeButton.Content = _appRuleMode.DisplayName();

            // Keep the recorders in sync when the coordinator changes a hotkey itself (e.g. Restore
            // Defaults). Setting HotkeyRecorder.Chord only updates its display — it does NOT raise
            // ChordChanged — so this can't loop back into SetHotkey/SetUndoHotkey. One SettingsView
            // instance lives for the app's lifetime (the window is hidden, not destroyed), so this
            // subscription doesn't accumulate.
            Vm.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName == nameof(VoiceCoordinator.Hotkey)) Recorder.Chord = Vm.Hotkey;
                else if (e.PropertyName == nameof(VoiceCoordinator.UndoHotkey)) SyncUndoRecorder();
            };
        };
    }

    private void SyncUndoRecorder()
    {
        if (Vm.UndoHotkey is { } c) UndoRecorder.Chord = c;
        else UndoRecorder.ShowCleared();
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

    // ---- App Modes (per-app tone rules) ----

    // Cycle order for the add-row mode chip (includes Code, unlike ToneStyle.Toggled).
    private static readonly ToneStyle[] AppRuleModeCycle =
        { ToneStyle.Casual, ToneStyle.Formal, ToneStyle.VeryCasual, ToneStyle.Code };

    private void OnCycleAppRuleMode(object sender, RoutedEventArgs e)
    {
        int i = Array.IndexOf(AppRuleModeCycle, _appRuleMode);
        _appRuleMode = AppRuleModeCycle[(i + 1) % AppRuleModeCycle.Length];
        AppRuleModeButton.Content = _appRuleMode.DisplayName();
    }

    // ---- searchable open-app picker (fills AppRuleBox with the chosen app's exe) ----
    private List<AppChoice> _allApps = new();
    private bool _suppressPick; // guards the pick round-trip (setting Text/SelectedItem re-fires events)

    private void OnAppRuleFocus(object sender, RoutedEventArgs e)
    {
        _allApps = RunningApps.List().ToList(); // refresh on focus so newly-opened apps appear
        FilterApps(AppRuleBox.Text);
        AppPickerPopup.IsOpen = AppPickerList.Items.Count > 0;
    }

    private void OnAppRuleTextChanged(object sender, TextChangedEventArgs e)
    {
        AppRuleWatermark.Visibility = string.IsNullOrEmpty(AppRuleBox.Text) ? Visibility.Visible : Visibility.Collapsed;
        if (_suppressPick) return;
        FilterApps(AppRuleBox.Text);
        if (AppRuleBox.IsKeyboardFocusWithin)
            AppPickerPopup.IsOpen = AppPickerList.Items.Count > 0;
    }

    private void FilterApps(string? text)
    {
        text = text?.Trim();
        AppPickerList.ItemsSource = string.IsNullOrEmpty(text)
            ? _allApps
            : _allApps.Where(a => a.Display.Contains(text, System.StringComparison.OrdinalIgnoreCase)
                               || a.Exe.Contains(text, System.StringComparison.OrdinalIgnoreCase)).ToList();
    }

    private void OnAppPicked(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressPick || AppPickerList.SelectedItem is not AppChoice choice) return;
        _suppressPick = true;
        AppRuleBox.Text = choice.Exe; // the exact exe name AppModeResolver matches
        AppPickerList.SelectedItem = null;
        _suppressPick = false;
        AppPickerPopup.IsOpen = false;
        AppRuleBox.CaretIndex = AppRuleBox.Text.Length;
        AppRuleBox.Focus();
    }

    private void OnAddAppRule(object sender, RoutedEventArgs e) => SubmitAppRule();
    private void OnAppRuleKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { AppPickerPopup.IsOpen = false; SubmitAppRule(); e.Handled = true; }
        else if (e.Key == Key.Escape) { AppPickerPopup.IsOpen = false; e.Handled = true; }
    }
    private void SubmitAppRule()
    {
        // Clear only on a successful add (AddAppRule ignores blank/duplicate matches). A typed
        // partial name is fine — AppModeResolver matches on substring, so "chr" still catches chrome.
        if (Vm.AddAppRule(AppRuleBox.Text, _appRuleMode))
        {
            AppRuleBox.Clear();
            AppPickerPopup.IsOpen = false;
            AppRuleBox.Focus();
        }
    }

    private void OnRemoveAppRule(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is AppModeRule rule)
            Vm.RemoveAppRule(rule);
    }

    private void OnClearUndoHotkey(object sender, RoutedEventArgs e) => Vm.ClearUndoHotkey();
    // (ClearUndoHotkey raises UndoHotkey → SyncUndoRecorder → ShowCleared, so the display follows.)

    // ---- Updates (in-app version check + one-click update) ----

    private async void OnCheckForUpdates(object sender, RoutedEventArgs e)
        => await Vm.Updates.CheckAsync(userInitiated: true);

    private void OnUpdateNow(object sender, RoutedEventArgs e)
        => Vm.Updates.StartDownloadAndInstall();

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
