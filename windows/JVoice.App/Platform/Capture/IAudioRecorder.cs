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

    /// Live microphone input level (0..1 peak amplitude of the most recent capture
    /// buffer) for the HUD's voice-activity visualizer. 0 while not recording. Read
    /// from the UI render loop each frame; written from the capture thread — a single
    /// float read/write is atomic, so no lock is needed (see NAudioRecorder).
    float CurrentLevel { get; }

    /// The capture endpoint the user picked in Settings; null = follow the system default.
    /// Applied on the next TryStart, so a Settings change needs no restart (schema v5, §7 #46).
    string? PreferredDeviceId { get; set; }

    /// Raised when a recording fails mid-stream (device lost, write error). The
    /// partial WAV has already been torn down. Analog of the Swift delegate
    /// failure callbacks (encodeFailure / finishedUnsuccessfully / config change).
    event Action<string>? Failed;
}
