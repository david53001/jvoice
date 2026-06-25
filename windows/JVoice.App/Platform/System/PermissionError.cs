namespace JVoice.App.Platform;

public enum PermissionErrorKind
{
    MicrophoneDenied,
}

/// Permission failures surfaced to the user with a message + a Settings deep link.
/// Faithful port of PermissionError.swift, scoped to microphone (overview §6.4).
public sealed class PermissionError : Exception
{
    public PermissionErrorKind Kind { get; }
    public string UserMessage { get; }
    public string DeepLink { get; }

    private PermissionError(PermissionErrorKind kind, string userMessage, string deepLink)
        : base(userMessage)
    {
        Kind = kind;
        UserMessage = userMessage;
        DeepLink = deepLink;
    }

    public static PermissionError Microphone() => new(
        PermissionErrorKind.MicrophoneDenied,
        "Microphone access denied. Grant access in Settings → Privacy & security → Microphone (turn on \"Let desktop apps access your microphone\").",
        SettingsUris.Microphone);

    /// Report the message via the global error hook (HUD in Phase 4).
    public void Surface() => SystemActions.ReportError(UserMessage);

    /// Report and open the Settings deep link.
    public void SurfaceAndOpenSettings()
    {
        Surface();
        SettingsUris.Open(DeepLink);
    }
}
