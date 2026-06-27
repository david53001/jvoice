import AVFoundation
import Combine
import CoreAudio
import Foundation

@MainActor
public final class RecordingManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    public enum Phase: Equatable, Sendable {
        case idle
        case recording
    }

    /// Failure modes surfaced via `lastError`. Mid-recording delegate failures
    /// (encode error, didFinishRecording successfully:false) are set by the
    /// AVAudioRecorderDelegate methods below; start-time failures (permission,
    /// engine setup, file size) are set by `startRecording()` and consumed by
    /// `VoiceCoordinator.startRecordingFlow`.
    public enum RecordingError: Error, Equatable {
        case encodeFailure(message: String)
        case finishedUnsuccessfully
        case permissionDenied
        case engineSetupFailed(message: String)
        case fileTooSmall(bytes: Int)
    }

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var startedAt: Date?
    @Published public private(set) var recordedURL: URL?
    @Published public private(set) var lastError: RecordingError?

    private var recorder: AVAudioRecorder?

    /// Live mic level (0…1) for the recording HUD bars. Driven only while a
    /// recording is active.
    public let levelMeter = AudioLevelMeter()

    /// When a recording temporarily redirects capture away from a Bluetooth
    /// default input (see `AudioInputRouter`), this holds the original default
    /// input device to restore once recording ends.
    private var inputDeviceToRestore: AudioDeviceID?

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public var recordingStartedAt: Date? {
        startedAt
    }

    public var phase: Phase {
        isRecording ? .recording : .idle
    }

    public var elapsedTime: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    public var hasRecordedAudio: Bool {
        recordedURL != nil
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    @discardableResult
    public func startRecording() -> Bool {
        guard !isRecording else { return false }
        self.lastError = nil

        // Redirect capture off a Bluetooth default input first so the recorder,
        // which follows the system default input, never opens the headset's mic
        // and forces it out of A2DP. No-op for non-Bluetooth inputs.
        redirectInputAwayFromBluetooth()

        do {
            let url = Self.makeTemporaryRecordingURL()
            let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else {
                self.lastError = .engineSetupFailed(message: "audio engine couldn't prepare")
                restoreDefaultInput()
                return false
            }

            guard recorder.record() else {
                self.lastError = .engineSetupFailed(message: "audio device is unavailable")
                restoreDefaultInput()
                return false
            }

            self.recorder = recorder
            self.recordedURL = url
            self.startedAt = Date()
            self.isRecording = true
            levelMeter.start(recorder: recorder)
            return true
        } catch {
            self.lastError = .engineSetupFailed(message: error.localizedDescription)
            restoreDefaultInput()
            return false
        }
    }

    /// Temporarily move the system default input to a non-Bluetooth mic when the
    /// current default is a Bluetooth device, remembering the original so it can
    /// be restored. See `AudioInputRouter` for why this preserves music quality.
    private func redirectInputAwayFromBluetooth() {
        guard let redirect = AudioInputRouter.bluetoothSafeRedirect() else { return }
        if AudioInputRouter.setDefaultInputDevice(redirect.target) {
            inputDeviceToRestore = redirect.original
        }
    }

    /// Restore the default input device redirected by `redirectInputAwayFromBluetooth()`.
    /// No-op when no redirect was applied.
    private func restoreDefaultInput() {
        guard let original = inputDeviceToRestore else { return }
        AudioInputRouter.setDefaultInputDevice(original)
        inputDeviceToRestore = nil
    }

    @discardableResult
    public func stopRecording() -> URL? {
        guard isRecording else {
            return recordedURL
        }

        recorder?.stop()
        recorder = nil
        levelMeter.stop()
        isRecording = false
        startedAt = nil
        restoreDefaultInput()

        let url = recordedURL
        recordedURL = nil
        return url
    }

    @discardableResult
    public func start() -> Bool {
        startRecording()
    }

    @discardableResult
    public func stop() -> URL? {
        stopRecording()
    }

    public func toggleRecording() {
        if isRecording {
            _ = stopRecording()
        } else {
            _ = startRecording()
        }
    }

    public func toggle() {
        toggleRecording()
    }

    private static func makeTemporaryRecordingURL() -> URL {
        let filename = "jvoice-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    // MARK: - AVAudioRecorderDelegate

    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let msg = error?.localizedDescription ?? "Unknown encoder error"
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastError = .encodeFailure(message: msg)
            self.tearDownFailedRecording()
        }
    }

    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }   // success path is handled by stopRecording()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastError = .finishedUnsuccessfully
            self.tearDownFailedRecording()
        }
    }

    @objc private func handleEngineConfigurationChange(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.lastError = .encodeFailure(message: "Audio input changed mid-recording")
            self.tearDownFailedRecording()
        }
    }

    /// Shared teardown for mid-recording failures (encoder error, unsuccessful
    /// finish, input device change). Removes the partial WAV — a failed
    /// recording must not leave raw audio behind in the temp directory — and
    /// clears `recordedURL` so the coordinator's next stop reports "no
    /// recording was captured" instead of transcribing a broken file.
    private func tearDownFailedRecording() {
        isRecording = false
        recorder?.stop()
        recorder = nil
        levelMeter.stop()
        restoreDefaultInput()
        if let url = recordedURL {
            try? FileManager.default.removeItem(at: url)
            recordedURL = nil
        }
    }

    /// Best-effort launch-time sweep of recordings orphaned by a crash or
    /// force-quit. Safe at startup: nothing is recording yet, and every
    /// recording this app makes matches the `jvoice-*.wav` pattern in the
    /// user's temporary directory.
    public static func sweepOrphanedRecordings() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in entries where url.lastPathComponent.hasPrefix("jvoice-") && url.pathExtension == "wav" {
            try? fileManager.removeItem(at: url)
        }
    }

#if DEBUG
    public func _setRecordingStateForTesting(isRecording: Bool) {
        self.isRecording = isRecording
    }

    public func simulateConfigurationChangeForTesting() {
        isRecording = true
        handleEngineConfigurationChange(Notification(name: .AVAudioEngineConfigurationChange))
    }
#endif

    /// Returns `true` if `url` points to a recording large enough to plausibly
    /// contain audio. 1024 bytes is roughly the minimum a non-empty 16 kHz/16-bit
    /// WAV occupies (header + ~32ms of samples).
    public static func isUsableRecording(at url: URL, minBytes: Int = 1024) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        let size = (attrs[.size] as? Int) ?? 0
        return size >= minBytes
    }
}
