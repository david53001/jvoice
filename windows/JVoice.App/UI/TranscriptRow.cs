using System.ComponentModel;

namespace JVoice.App.UI;

/// A single Recent-Transcripts row bound in SettingsView. Wraps a persisted
/// TranscriptHistoryEntry (Id + Text, both immutable) with one piece of transient,
/// never-persisted view state: <see cref="JustCopied"/>, which the Copy button flips
/// on for ~1.2 s to swap its icon for a checkmark.
public sealed class TranscriptRow : INotifyPropertyChanged
{
    public Guid Id { get; }
    public string Text { get; }

    public TranscriptRow(Guid id, string text)
    {
        Id = id;
        Text = text;
    }

    private bool _justCopied;
    public bool JustCopied
    {
        get => _justCopied;
        set
        {
            if (_justCopied == value) return;
            _justCopied = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(JustCopied)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
