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

    /// Fast path on every press: an already-decided authorization is a
    /// synchronous TCC lookup, so only the very first run (status
    /// `.notDetermined`) pays the `requestAccess` round trip — the prompt is
    /// the one thing that must stay explicit. A denied/restricted status is
    /// reported without a round trip either.
    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            fallthrough
        @unknown default:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Touch the audio stack once at launch, off the main thread: the first
    /// in-process TCC lookup (~35 ms) and the first Core Audio device
    /// enumeration (~55 ms) are cold-start costs that would otherwise land on
    /// the first hotkey press. Warm, both are sub-millisecond.
    public nonisolated static func prewarmAudioStack() {
        Task.detached(priority: .utility) {
            _ = AVCaptureDevice.authorizationStatus(for: .audio)
            _ = AudioInputRouter.hasInputDevice()
        }
    }

    /// Bumped by every stop so a start that was still opening the device when
    /// the stop (or a quit) arrived discards its recorder instead of leaking it.
    private var startGeneration = 0

    /// A recorder created and `prepareToRecord()`'d AHEAD of the press. Measured
    /// on this machine: create + prepare is 20–55 ms, and it engages NO device
    /// while idle (verified via `kAudioDevicePropertyDeviceIsRunningSomewhere`):
    /// no orange mic indicator, no Bluetooth profile switch. Leaves only
    /// `record()` (~60 ms) on the press. It is NOT used after a Bluetooth
    /// redirect: a spare prepared while the headset was the default input only
    /// follows the switch once the default-input change reaches its audio queue,
    /// and a `record()` 0.2 ms after the switch sometimes wins that race and opens
    /// the headset's mic (2 of 34 presses, 2026-09-23: HFP/SCO, music jumps).
    /// A recorder created after the switch spends its 20–55 ms create + prepare
    /// before `record()` — the 1.1.0 ordering, which never showed the problem
    /// (bad presses had ~16 ms between switch and `record()`, good ones ≥ 42 ms).
    /// It is still timing-based; the robust fix is capturing from the built-in
    /// mic directly (AVAudioEngine/AUHAL) without touching the default input.
    private var spare: (recorder: AVAudioRecorder, url: URL)?
    private var isPreparingSpare = false

    /// Prepare the next press's recorder off the main actor. Call after launch
    /// (once the orphan sweep ran) and after every stop; a no-op while one exists.
    public func prepareSpareRecorder() {
        guard spare == nil, !isPreparingSpare, !isRecording else { return }
        isPreparingSpare = true
        let url = Self.makeTemporaryRecordingURL()
        Task { [weak self] in
            let prepared = await Task.detached(priority: .utility) { Self.prepareRecorder(at: url) }.value
            guard let self else { try? FileManager.default.removeItem(at: url); return }
            self.installSpare(prepared, url: url)
        }
    }

    private func installSpare(_ prepared: AVAudioRecorder?, url: URL) {
        isPreparingSpare = false
        if let prepared, spare == nil, !isRecording {
            spare = (prepared, url)
        } else {
            try? FileManager.default.removeItem(at: url) // prepare failed, or no longer wanted
        }
    }

    /// Drop the spare and its (empty) file — on quit, so nothing is orphaned.
    public func discardSpareRecorder() {
        guard let spare else { return }
        self.spare = nil
        try? FileManager.default.removeItem(at: spare.url)
    }

    private nonisolated static func prepareRecorder(at url: URL) -> AVAudioRecorder? {
        guard let recorder = try? AVAudioRecorder(url: url, settings: recordingSettings) else { return nil }
        recorder.isMeteringEnabled = true
        return recorder.prepareToRecord() ? recorder : nil
    }

    /// Opens the microphone and starts capturing. The `AVAudioRecorder`
    /// create + prepare + `record()` (measured 20–90 ms on this machine; a
    /// cross-process call into coreaudiod that can spike under load) runs OFF
    /// the main actor so the recording pill — shown by the coordinator before
    /// this is called — never has its first frames blocked by it.
    @discardableResult
    public func startRecording() async -> Bool {
        guard !isRecording, recorder == nil else { return false }
        self.lastError = nil

        // Redirect capture off a Bluetooth default input first so the recorder,
        // which follows the system default input, never opens the headset's mic
        // and forces it out of A2DP. No-op for non-Bluetooth inputs. After a
        // redirect the spare (prepared on the headset) is dropped for a fresh
        // recorder created after the switch — see `spare`.
        if redirectInputAwayFromBluetooth() {
            discardSpareRecorder()
        }

        let generation = startGeneration
        // Prefer the spare prepared while idle: only `record()` remains.
        let spare = self.spare
        self.spare = nil
        let url = spare?.url ?? Self.makeTemporaryRecordingURL()
        let opened = await Task.detached(priority: .userInitiated) {
            if let spare {
                if spare.recorder.record() { return Result<AVAudioRecorder, RecordingError>.success(spare.recorder) }
                // A stale spare (device change, sleep/wake) — fall back to a fresh open.
                try? FileManager.default.removeItem(at: spare.url)
                return Self.openRecorder(at: url)
            }
            return Self.openRecorder(at: url)
        }.value

        switch opened {
        case .failure(let error):
            self.lastError = error
            restoreDefaultInput()
            return false
        case .success(let recorder):
            // A stop/quit raced the open: the recording was abandoned before it
            // began. Release the device and the (empty) file rather than leaking.
            guard generation == startGeneration else {
                recorder.stop()
                try? FileManager.default.removeItem(at: url)
                restoreDefaultInput()
                return false
            }
            recorder.delegate = self
            self.recorder = recorder
            self.recordedURL = url
            self.startedAt = Date()
            self.isRecording = true
            levelMeter.start(recorder: recorder)
            return true
        }
    }

    /// The blocking part of a start, isolated from the main actor. Returns a
    /// recorder that is already capturing to `url`.
    private nonisolated static func openRecorder(at url: URL) -> Result<AVAudioRecorder, RecordingError> {
        do {
            let recorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else {
                return .failure(.engineSetupFailed(message: "audio engine couldn't prepare"))
            }
            guard recorder.record() else {
                return .failure(.engineSetupFailed(message: "audio device is unavailable"))
            }
            return .success(recorder)
        } catch {
            return .failure(.engineSetupFailed(message: error.localizedDescription))
        }
    }

    /// Temporarily move the system default input to a non-Bluetooth mic when the
    /// current default is a Bluetooth device, remembering the original so it can
    /// be restored. See `AudioInputRouter` for why this preserves music quality.
    /// Returns true when the default input was actually switched.
    private func redirectInputAwayFromBluetooth() -> Bool {
        guard let redirect = AudioInputRouter.bluetoothSafeRedirect() else { return false }
        guard AudioInputRouter.setDefaultInputDevice(redirect.target) else { return false }
        inputDeviceToRestore = redirect.original
        return true
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
        startGeneration += 1 // abandon a start still opening the device
        guard isRecording else {
            return recordedURL
        }

        recorder?.stop()
        recorder = nil
        levelMeter.stop()
        isRecording = false
        startedAt = nil
        // A press that redirected off Bluetooth never uses a spare (see `spare`),
        // so don't prepare one for the next press — it would only be discarded.
        let redirected = inputDeviceToRestore != nil
        restoreDefaultInput()

        let url = recordedURL
        recordedURL = nil
        if !redirected { prepareSpareRecorder() }
        return url
    }

    @discardableResult
    public func start() async -> Bool {
        await startRecording()
    }

    @discardableResult
    public func stop() -> URL? {
        stopRecording()
    }

    public func toggleRecording() async {
        if isRecording {
            _ = stopRecording()
        } else {
            _ = await startRecording()
        }
    }

    public func toggle() async {
        await toggleRecording()
    }

    private static func makeTemporaryRecordingURL() -> URL {
        let filename = "jvoice-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private nonisolated static var recordingSettings: [String: Any] {
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
        startGeneration += 1
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

    /// True when a finished recording contains no audio above the silence floor
    /// (user held the hotkey but didn't speak, or the mic captured nothing).
    /// Reuses the streaming pipeline's WAV reader + the proven
    /// `ChunkPlanner.isSilent` policy. Fails open (returns `false`) when the
    /// file can't be read, so an uninspectable recording still reaches
    /// transcription rather than being wrongly rejected.
    public static func isSilentRecording(at url: URL) -> Bool {
        guard let reader = WavTailReader.open(url: url),
              let samples = reader.samples(from: 0),
              !samples.isEmpty else {
            return false
        }
        return ChunkPlanner.isSilent(samples)
    }
}
