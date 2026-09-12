namespace JVoice.Core.Models;

public enum HudStateKind
{
    Idle,
    Recording,
    PreparingModel,
    DownloadingModel,
    Transcribing,
    Done,
    Error,
}

public readonly record struct HudState(HudStateKind Kind, string? Payload = null, double? Progress = null)
{
    public static readonly HudState Idle = new(HudStateKind.Idle);
    public static readonly HudState Recording = new(HudStateKind.Recording);
    public static readonly HudState PreparingModel = new(HudStateKind.PreparingModel);
    public static HudState DownloadingModel(double progress) => new(HudStateKind.DownloadingModel, Progress: progress);
    public static readonly HudState Transcribing = new(HudStateKind.Transcribing);
    public static HudState Done(string text) => new(HudStateKind.Done, text);
    public static HudState Error(string message) => new(HudStateKind.Error, message);

    public string Headline => Kind switch
    {
        HudStateKind.Idle => "Ready",
        HudStateKind.Recording => "Listening",
        HudStateKind.PreparingModel => "Preparing Model",
        HudStateKind.DownloadingModel => "Downloading Model",
        HudStateKind.Transcribing => "Transcribing",
        HudStateKind.Done => "Pasted",
        HudStateKind.Error => "Something Went Wrong",
        _ => "Ready",
    };

    public string? Subtitle => Kind switch
    {
        HudStateKind.Idle => "JVoice is standing by.",
        HudStateKind.Recording => "Listening…",
        HudStateKind.PreparingModel => "One-time setup — keep JVoice open",
        HudStateKind.DownloadingModel => "Downloading the speech model…",
        HudStateKind.Transcribing => "Processing…",
        HudStateKind.Done => null,
        HudStateKind.Error => string.IsNullOrEmpty(Payload) ? "Something went wrong" : Payload,
        _ => null,
    };

    public bool IsVisible => Kind != HudStateKind.Idle;

    public bool IsBusy => Kind is HudStateKind.Recording or HudStateKind.PreparingModel
        or HudStateKind.DownloadingModel or HudStateKind.Transcribing;

    public bool IsTerminal => Kind is HudStateKind.Done or HudStateKind.Error;
}
