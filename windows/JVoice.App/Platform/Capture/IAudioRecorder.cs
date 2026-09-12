namespace JVoice.App.Platform;

/// Microphone capture to a growing 16 kHz/mono/16-bit PCM WAV. Faithful port of
/// the RecordingManager.swift surface (start/stop/permission/orphan sweep/usable
/// check). The DI seam lets Phase 4's VoiceCoordinator be tested with a fake.
public interface IAudioRecorder
{
    bool TryStart(out string? error);

    /// True when the most recent TryStart failed because the OS denied microphone access
    /// (privacy gate), as opposed to a device/driver error. Lets the coordinator surface the
    /// Settings deep link WITHOUT a separate probe on every press: RequestPermissionAsync opened,
    /// started and stopped a whole extra capture client before each recording (13 ms idle,
    /// 100-200 ms under CPU load) and told us nothing TryStart's own failure doesn't.
    bool LastStartWasPermissionDenied { get; }
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
