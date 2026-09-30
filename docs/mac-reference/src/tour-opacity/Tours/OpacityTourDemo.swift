import AppKit

/// Something a tour step plays while it's on screen — today only the Opacity step's slider demo.
/// `TourCoordinator` starts it after the step's tag shows and stops it the moment the step leaves
/// (Next, Skip, the tour ending or pausing).
@MainActor
protocol TourStepDemo: AnyObject {
    /// Starts playing. `readout` is a short live caption the tag appends to the step's body.
    func start(readout: @escaping (String) -> Void)
    /// Stops and puts back whatever the demo changed.
    func stop()
}

/// The Settings tour's Opacity step (David, 2026-09-30: "show the bar slowly going down… how the
/// opacity decreased and increased"): the real slider glides from the user's value down to Transparent,
/// up to Opaque, and back, looping, while the whole Settings window (and the tag) follow it live and the
/// tag reads out the value ("Watch: 37 % ↓").
///
/// Never saves anything: the store stops persisting while the demo runs, so quitting mid-demo leaves
/// the stored setting untouched, and `stop()` restores the user's value. Touching the slider (or
/// Default) during the demo hands it back to the user — their value is kept and saved.
@MainActor
final class OpacityTourDemo: TourStepDemo {
    /// The one step that plays it.
    nonisolated static let anchor = OpacityDemoTimeline.anchor

    private let store: UIOpacityStore
    private var original = UIOpacity.defaultValue
    /// The store's own persist mode, put back on stop (`--ui-preview` never persists).
    private var wasPersisting = true
    private var lastSet: Double?
    private var started = Date()
    private var timer: Timer?
    private var readout: ((String) -> Void)?
    private var lastReadout = ""

    init(store: UIOpacityStore? = nil) {
        self.store = store ?? .shared
    }

    func start(readout: @escaping (String) -> Void) {
        stop()
        self.readout = readout
        original = store.value
        wasPersisting = store.persists
        store.persists = false
        started = Date()
        lastReadout = ""
        tick()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps playing while a menu or scroll tracks
        self.timer = timer
    }

    func stop() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        readout = nil
        store.persists = wasPersisting
        // Only undo the demo's own change; a value the user set meanwhile stays (and is saved by `tick`).
        if let lastSet, store.value == lastSet { store.value = original }
        lastSet = nil
    }

    private func tick() {
        if let lastSet, store.value != lastSet {
            // The user moved the slider or pressed Default: their value wins and is saved.
            let theirs = store.value
            timer?.invalidate()
            timer = nil
            readout = nil
            self.lastSet = nil
            store.persists = wasPersisting
            store.value = theirs
            return
        }
        let frame = OpacityDemoTimeline.frame(at: Date().timeIntervalSince(started), from: original)
        lastSet = frame.value
        store.value = frame.value
        if frame.readout != lastReadout {
            lastReadout = frame.readout
            readout?(frame.readout)
        }
    }
}
