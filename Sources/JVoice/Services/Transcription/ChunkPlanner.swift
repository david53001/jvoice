import Foundation

/// Pure chunking policy for streaming transcription: decides where to cut the
/// next chunk out of not-yet-transcribed audio. Cuts only at silence (so words
/// are never split) until `maxChunkSeconds` forces one — the same compromise
/// WhisperKit's VAD chunker makes on the whole-file path today. All functions
/// are pure so they run in both the swift-testing suite and
/// scripts/run-logic-tests.sh.
public enum ChunkPlanner {
    public struct Config: Sendable {
        public var sampleRate: Int = 16_000
        /// Don't chunk dictations shorter than this — post model-swap they are
        /// already fast transcribed whole.
        public var minChunkSeconds: Double = 15
        /// Hard cap keeping every chunk provably single-window and on the
        /// proven ≤25 s `withoutTimestamps` fast path (see
        /// WhisperKitTranscriptionEngine.isSingleWindowClip).
        public var maxChunkSeconds: Double = 25
        public var silenceWindowSeconds: Double = 0.3
        /// Absolute RMS floor (full scale = 1.0) below which audio is silence
        /// regardless of the relative threshold: ~-46 dBFS, far below speech.
        public var silenceRMSFloor: Float = 0.005
        /// A window quieter than this fraction of the loudest window counts as
        /// a pause in speech (relative, mirrors WhisperKit's energy VAD).
        public var relativeSilenceFraction: Float = 0.1
        public init() {}
    }

    public enum Decision: Equatable, Sendable {
        case wait
        /// Cut `unconsumed[..<atSample]` as the next chunk. `isSilent` chunks
        /// must be dropped, not transcribed — Whisper hallucinates on silence.
        case cut(atSample: Int, isSilent: Bool)
    }

    public static func plan(unconsumed: [Int16], config: Config = .init()) -> Decision {
        let minSamples = Int(config.minChunkSeconds * Double(config.sampleRate))
        let maxSamples = Int(config.maxChunkSeconds * Double(config.sampleRate))
        let window = max(1, Int(config.silenceWindowSeconds * Double(config.sampleRate)))
        guard unconsumed.count >= minSamples else { return .wait }

        let searchEnd = min(unconsumed.count, maxSamples)
        let energies = windowRMS(unconsumed[..<searchEnd], window: window)
        let peak = energies.map(\.rms).max() ?? 0
        let threshold = max(config.silenceRMSFloor, peak * config.relativeSilenceFraction)

        // Candidate cut points: complete windows starting at/after the minimum
        // chunk length. `windowRMS` yields windows left-to-right, so `candidates`
        // is in ascending start order.
        let candidates = energies.filter { $0.start >= minSamples && $0.start + window <= searchEnd }

        // Cut at the EARLIEST window quiet enough to be a real pause, not the
        // globally quietest one. Every candidate below `threshold` is already a
        // valid (silence-level) boundary, so taking the first one emits the
        // streaming chunk as soon as a pause appears — lower latency with no loss
        // of cut safety, instead of waiting to compare against later, deeper pauses.
        if let earliest = candidates.first(where: { $0.rms < threshold }) {
            return makeCut(unconsumed, at: earliest.start + window / 2, config: config)
        }
        // No pause below threshold: keep waiting until the single-window cap
        // forces a cut at the least-bad (quietest) spot.
        guard unconsumed.count >= maxSamples else { return .wait }
        let quietest = candidates.min { $0.rms < $1.rms }
        return makeCut(unconsumed, at: quietest.map { $0.start + window / 2 } ?? maxSamples, config: config)
    }

    /// True when `samples` never rise above the absolute silence floor — used
    /// for the final tail and to drop all-silence chunks.
    public static func isSilent(_ samples: [Int16], config: Config = .init()) -> Bool {
        let window = max(1, Int(config.silenceWindowSeconds * Double(config.sampleRate)))
        let peak = windowRMS(samples[...], window: window).map(\.rms).max() ?? 0
        return peak < config.silenceRMSFloor
    }

    private static func makeCut(_ unconsumed: [Int16], at sample: Int, config: Config) -> Decision {
        .cut(atSample: sample, isSilent: isSilent(Array(unconsumed[..<sample]), config: config))
    }

    struct WindowEnergy: Equatable {
        let start: Int // relative to the slice's first element
        let rms: Float
    }

    /// Non-overlapping RMS windows; the last (partial) window is included.
    static func windowRMS(_ samples: ArraySlice<Int16>, window: Int) -> [WindowEnergy] {
        guard !samples.isEmpty, window > 0 else { return [] }
        var result: [WindowEnergy] = []
        let base = samples.startIndex
        var start = base
        while start < samples.endIndex {
            let end = min(start + window, samples.endIndex)
            var sum: Double = 0
            for i in start..<end {
                let v = Double(samples[i]) / 32_768.0
                sum += v * v
            }
            result.append(WindowEnergy(start: start - base, rms: Float((sum / Double(end - start)).squareRoot())))
            start += window
        }
        return result
    }
}
