import AVFoundation
import Foundation

/// Publishes a smoothed 0…1 microphone level for the recording HUD bars. Polls
/// the existing `AVAudioRecorder` metering at a modest 15 Hz (the bars redraw
/// is the only continuous work while recording, and it's tiny — a handful of
/// capsules). Never rebuilds the HUD view; the bar subview observes `level`.
@MainActor
public final class AudioLevelMeter: ObservableObject {
    @Published public private(set) var level: Float = 0

    private var timer: Timer?
    private weak var recorder: AVAudioRecorder?
    private let fps: Double = 15

    public init() {}

    public func start(recorder: AVAudioRecorder) {
        self.recorder = recorder
        level = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        level = 0
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let target = AudioLevel.normalize(recorder.averagePower(forChannel: 0))
        // Equal-weight smoothing so bars glide rather than jitter.
        level = level * 0.5 + target * 0.5
    }
}
