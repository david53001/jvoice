namespace JVoice.Core.Models;

public enum HudStateKind
{
    Idle,
    Recording,
    PreparingModel,
    DownloadingModel,
    Transcribing,
    /// AI Polish (opt-in): waiting on Claude to clean the finished transcript — "AI refining" with a
    /// Claude-orange sweep (Mac `HUDState.refining`). Busy, never terminal; at most the 3 s deadline.
    Refining,
    Done,
    /// Clipboard-only mode finished: the transcript is on the clipboard, not in an app — never "Pasted".
    Copied,
    Error,
    /// A neutral note from the app itself (tour confirmations: "Tours reset", "The recording tour starts at your
    /// next dictation") — Mac `HUDState.notice`. Never shown over a recording or transcription.
    Notice,
}

public readonly record struct HudState(HudStateKind Kind, string? Payload = null, double? Progress = null)
{
    public static readonly HudState Idle = new(HudStateKind.Idle);
    public static readonly HudState Recording = new(HudStateKind.Recording);
    public static readonly HudState PreparingModel = new(HudStateKind.PreparingModel);
    public static HudState DownloadingModel(double progress) => new(HudStateKind.DownloadingModel, Progress: progress);
    public static readonly HudState Transcribing = new(HudStateKind.Transcribing);
    public static readonly HudState Refining = new(HudStateKind.Refining);
    public static HudState Done(string text) => new(HudStateKind.Done, text);
    public static HudState Copied(string text) => new(HudStateKind.Copied, text);
    public static HudState Error(string message) => new(HudStateKind.Error, message);
    public static HudState Notice(string message) => new(HudStateKind.Notice, message);

    public string Headline => Kind switch
    {
        HudStateKind.Idle => "Ready",
        HudStateKind.Recording => "Listening",
        HudStateKind.PreparingModel => "Preparing Model",
        HudStateKind.DownloadingModel => "Downloading Model",
        HudStateKind.Transcribing => "Transcribing",
        HudStateKind.Refining => "AI refining",
        HudStateKind.Done => "Pasted",
        HudStateKind.Copied => "Copied",
        HudStateKind.Error => "Something Went Wrong",
        HudStateKind.Notice => Payload ?? "",
        _ => "Ready",
    };

    public string? Subtitle => Kind switch
    {
        HudStateKind.Idle => "JVoice is standing by.",
        HudStateKind.Recording => "Listening…",
        HudStateKind.PreparingModel => "One-time setup — keep JVoice open",
        HudStateKind.DownloadingModel => "Downloading the speech model…",
        HudStateKind.Transcribing => "Processing…",
        HudStateKind.Refining => null,
        HudStateKind.Done => null,
        HudStateKind.Copied => "On your clipboard",
        HudStateKind.Error => string.IsNullOrEmpty(Payload) ? "Something went wrong" : Payload,
        _ => null,
    };

    public bool IsVisible => Kind != HudStateKind.Idle;

    public bool IsBusy => Kind is HudStateKind.Recording or HudStateKind.PreparingModel
        or HudStateKind.DownloadingModel or HudStateKind.Transcribing or HudStateKind.Refining;

    public bool IsTerminal => Kind is HudStateKind.Done or HudStateKind.Copied or HudStateKind.Error or HudStateKind.Notice;
}
