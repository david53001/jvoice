namespace JVoice.App.Platform;

/// Microphone capture to a growing 16 kHz/mono/16-bit PCM WAV. Faithful port of
/// the RecordingManager.swift surface (start/stop/permission/orphan sweep/usable
/// check). The DI seam lets Phase 4's VoiceCoordinator be tested with a fake.
public interface IAudioRecorder
{
    bool TryStart(out string? error);
    string? Stop();
    string? CurrentPath { get; }
    bool IsRecording { get; }
    DateTime? StartedAt { get; }
    Task<bool> RequestPermissionAsync();

    /// Raised when a recording fails mid-stream (device lost, write error). The
    /// partial WAV has already been torn down. Analog of the Swift delegate
    /// failure callbacks (encodeFailure / finishedUnsuccessfully / config change).
    event Action<string>? Failed;
}
