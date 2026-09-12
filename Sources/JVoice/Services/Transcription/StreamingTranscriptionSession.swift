import Foundation
import os

/// Transcribes completed speech chunks in the background *while the user is
/// still recording*, by reading the growing WAV that `RecordingManager`'s
/// AVAudioRecorder writes. This is a read-only overlay on the proven pipeline:
/// any failure marks the session failed and `finish()` returns nil, telling
/// the caller to fall back to whole-file transcription — worst case equals
/// today's behavior, and audio is never lost (correctness is anchored at the
/// finalized file, which is read after the recorder stops).
///
/// Latency layer (2026-09-12): (1) a chunk decode that is in flight when the
/// user presses stop is never cancelled — it is awaited and its result kept
/// (cancelling it made WhisperKit throw, which failed the session and forced
/// a whole-file re-decode of the entire dictation: 6.6 s instead of 1 s on a
/// 96 s recording); (2) a **speculative tail decode**: once the pending audio
/// ends in `speculateAfterSeconds` of silence, the pending audio is decoded
/// right away, on the bet that the user is about to press stop. If they do
/// (and said nothing more), `finish()` returns that result without decoding
/// anything — the stop→paste wait collapses toward zero. If they keep
/// talking, the speculation is cancelled and the normal path runs.
public actor StreamingTranscriptionSession {
    public typealias SampleTranscriber = @Sendable ([Float]) async throws -> String
    public typealias EventLog = @Sendable (String) -> Void

    private static let logger = Logger(subsystem: "com.jvoice.app", category: "latency")
    public static let defaultLog: EventLog = { message in
        logger.info("Stream \(message, privacy: .public)")
    }

    private let transcribe: SampleTranscriber
    private let config: ChunkPlanner.Config
    private let pollNanoseconds: UInt64
    private let speculateAfterSeconds: Double
    private let log: EventLog

    private var url: URL?
    private var reader: WavTailReader?
    private var consumedSamples = 0
    private var pieces: [String] = []
    private var pollTask: Task<Void, Never>?
    private var failed = false
    private var cancelled = false
    /// Polls tolerated before a never-parseable header is fatal (the recorder
    /// may still be flushing its first buffer right after start).
    private var openRetriesRemaining = 10
    /// Enforces the finish-once contract: a second `finish()` would re-drain
    /// the backlog from the un-advanced `consumedSamples` and duplicate audio.
    private var finished = false
    /// File size at the last poll. The recorder flushes in ~320 ms bursts, so
    /// most polls at a faster cadence see nothing new and skip the read.
    private var lastSeenByteCount: UInt64 = 0
    /// The chunk decode currently running — an UNSTRUCTURED task on purpose.
    /// `finish()` cancels the poll task to interrupt its sleep, and WhisperKit
    /// honours task cancellation inside its decode: a structured decode would
    /// throw, the session would mark itself failed, and the caller would
    /// re-decode the whole dictation. Only `cancel()` (abandon) cancels this.
    private var inFlight: Task<String, Error>?

    private struct Speculation {
        /// Absolute sample where the decoded audio starts (== consumedSamples then).
        let start: Int
        /// Absolute sample where speech ended and the trailing silence began.
        let speechEnd: Int
        let task: Task<String, Error>
    }
    private var speculation: Speculation?

    public init(
        transcribe: @escaping SampleTranscriber,
        config: ChunkPlanner.Config = .init(),
        pollNanoseconds: UInt64 = 1_000_000_000,
        speculateAfterSeconds: Double = 0.4,
        log: @escaping EventLog = StreamingTranscriptionSession.defaultLog
    ) {
        self.transcribe = transcribe
        self.config = config
        self.pollNanoseconds = pollNanoseconds
        self.speculateAfterSeconds = speculateAfterSeconds
        self.log = log
    }

    public func start(url: URL) {
        // `!finished` matters: the coordinator assigns the session and then
        // suspends before calling start — a fast stop can finish() the session
        // in that window, and starting it afterwards would spawn an orphan
        // poll loop.
        guard pollTask == nil, !cancelled, !failed, !finished else { return }
        self.url = url
        pollTask = Task { await runPollLoop() }
    }

    /// Stop polling, transcribe whatever remains in the (now finalized) file,
    /// and return the combined raw transcript. nil ⇒ the caller MUST fall back
    /// to whole-file transcription (session failed, was cancelled, or never
    /// streamed anything — in which case the fallback is equally fast).
    public func finish() async -> String? {
        guard !finished else { return nil }
        finished = true
        // Interrupts the poll loop's sleep only: a running pollOnce completes
        // its (unstructured) decode and consumes the chunk normally.
        pollTask?.cancel()
        await pollTask?.value
        pollTask = nil
        guard !failed, !cancelled, let url else { discardSpeculation(); return nil }
        guard consumedSamples > 0 || !pieces.isEmpty || speculation != nil else { return nil }

        if reader == nil { reader = WavTailReader.open(url: url) }
        guard let reader, var tail = reader.samples(from: consumedSamples) else { discardSpeculation(); return nil }

        // The bet paid off: the pending audio was already decoded during the
        // pause and nothing but silence arrived after it.
        if let spec = speculation {
            speculation = nil
            let speechEndRel = spec.speechEnd - spec.start
            if spec.start == consumedSamples, tail.count >= speechEndRel,
               ChunkPlanner.isSilent(Array(tail[speechEndRel...]), config: config) {
                if let text = try? await spec.task.value, !text.isEmpty {
                    pieces.append(text)
                    log("speculative tail HIT — \(String(format: "%.1f", Double(speechEndRel) / Double(config.sampleRate))) s of pending speech was decoded during the pause")
                    return joinedOrNil()
                }
                log("speculative tail decode empty/failed → normal tail decode")
            } else {
                spec.task.cancel()
                log("speculative tail MISS — speech resumed after the pause")
            }
        }

        // Drain any backlog the poll loop didn't get to (slow decodes), keeping
        // every transcribed piece a provable single window. Terminates because
        // `plan` never cuts at 0 — every `.cut` strictly shrinks `tail`.
        while case let .cut(at, silent) = ChunkPlanner.plan(unconsumed: tail, config: config) {
            if !silent {
                guard await appendPiece(WavTail.floatSamples(tail[..<at])) else { return nil }
            }
            tail = Array(tail[at...])
        }
        // After the drain the tail is < maxChunkSeconds by construction.
        if !tail.isEmpty, !ChunkPlanner.isSilent(tail, config: config) {
            guard await appendPiece(WavTail.floatSamples(tail[...])) else { return nil }
        }
        return joinedOrNil()
    }

    /// All-silence audio joins to "": let the fallback produce today's exact
    /// empty-transcript behavior rather than inventing a new path.
    private func joinedOrNil() -> String? {
        let joined = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// The user abandoned this recording (new hotkey press, quit): discard
    /// everything; `finish()` will return nil if it is ever called. Joins the
    /// poll task so no chunk decode from this session is still in flight when
    /// cancel returns — the next recording's decodes never overlap ours.
    public func cancel() async {
        cancelled = true
        inFlight?.cancel()
        discardSpeculation()
        pollTask?.cancel()
        await pollTask?.value
        pollTask = nil
        pieces = []
    }

    private func discardSpeculation() {
        speculation?.task.cancel()
        speculation = nil
    }

    private func appendPiece(_ samples: [Float]) async -> Bool {
        do {
            let text = try await transcribe(samples)
            guard !text.isEmpty else {
                // A non-silent chunk (callers only pass non-silent audio here)
                // that decodes to nothing is anomalous — an empty WhisperKit
                // decode or a regurgitation the guard stripped to "". Appending
                // nothing while advancing past it would SILENTLY DELETE up to
                // maxChunkSeconds of speech. Fail instead so finish() returns
                // nil and the lossless whole-file path re-covers this audio.
                failed = true
                return false
            }
            pieces.append(text)
            return true
        } catch {
            failed = true
            return false
        }
    }

    private func runPollLoop() async {
        while !Task.isCancelled, !failed, !cancelled {
            await pollOnce()
            do {
                try await Task.sleep(nanoseconds: pollNanoseconds)
            } catch {
                break // cancelled during sleep
            }
        }
    }

    private func pollOnce() async {
        guard let url else {
            failed = true
            return
        }
        // Recorder torn down (file gone) — abort, the fallback handles it.
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else {
            failed = true
            return
        }
        // Nothing flushed since the last poll: skip the read entirely.
        if size.uint64Value == lastSeenByteCount { return }
        lastSeenByteCount = size.uint64Value
        if reader == nil {
            guard let opened = WavTailReader.open(url: url) else {
                openRetriesRemaining -= 1
                if openRetriesRemaining <= 0 { failed = true }
                return
            }
            reader = opened
        }
        guard let reader else { return }
        guard let unconsumed = reader.samples(from: consumedSamples) else {
            failed = true // file vanished mid-recording (failure teardown)
            return
        }
        guard case let .cut(atSample, isSilent) = ChunkPlanner.plan(unconsumed: unconsumed, config: config) else {
            updateSpeculation(unconsumed)
            return
        }
        if isSilent {
            discardSpeculation()
            consumedSamples += atSample // dropped, never transcribed
            return
        }
        // A speculative decode that already covers this chunk's speech IS this
        // chunk's decode (the cut sits inside the same trailing pause).
        let task: Task<String, Error>
        if let spec = speculation, spec.start == consumedSamples, atSample >= spec.speechEnd - spec.start {
            speculation = nil
            task = spec.task
            log("chunk cut reuses the speculative decode")
        } else {
            discardSpeculation()
            let chunk = WavTail.floatSamples(unconsumed[..<atSample])
            let transcribe = self.transcribe
            task = Task { try await transcribe(chunk) }
        }
        inFlight = task
        defer { inFlight = nil }
        do {
            let text = try await task.value
            // Abandoned mid-decode: don't consume — nothing is pasted anyway.
            guard !cancelled else { return }
            guard !text.isEmpty else {
                // Non-silent chunk (silent ones were dropped above) decoded to
                // nothing: consuming it would silently delete up to
                // maxChunkSeconds of speech. Fail the session so finish()
                // returns nil and the caller re-runs the lossless whole-file
                // path over the finalized recording. (This is the data-loss bug
                // behind "it cut out a big chunk of my dictation".)
                failed = true
                return
            }
            pieces.append(text)
            consumedSamples += atSample
        } catch {
            failed = true
        }
    }

    /// Pause-triggered speculative tail decode. Called only when `plan` said
    /// `.wait`, i.e. the pending audio is below the chunk minimum or has no
    /// qualifying pause yet — exactly the audio `finish()` would have to decode
    /// after the stop press. Once it ends in `speculateAfterSeconds` of
    /// silence, decode it now; a speculation stays valid while the speech end
    /// doesn't move (more silence only), and is dropped when speech resumes.
    private func updateSpeculation(_ unconsumed: [Int16]) {
        let sampleRate = Double(config.sampleRate)
        let maxSamples = Int(config.maxChunkSeconds * sampleRate)
        guard speculateAfterSeconds > 0, !unconsumed.isEmpty, unconsumed.count < maxSamples else { return }
        let trailing = ChunkPlanner.trailingSilenceSamples(unconsumed, config: config)
        let speechEndRel = unconsumed.count - trailing
        guard speechEndRel > 0 else { return } // nothing but silence so far
        let absSpeechEnd = consumedSamples + speechEndRel
        if let spec = speculation {
            // Same pause (the speech end may jitter by one probe step on noise).
            let tolerance = Int(0.2 * sampleRate)
            if spec.start == consumedSamples, abs(spec.speechEnd - absSpeechEnd) <= tolerance { return }
            discardSpeculation()
            log("speculative tail dropped — speech resumed")
        }
        guard Double(trailing) / sampleRate >= speculateAfterSeconds else { return }
        let audio = WavTail.floatSamples(unconsumed[...])
        let transcribe = self.transcribe
        let task = Task { try await transcribe(audio) }
        speculation = Speculation(start: consumedSamples, speechEnd: absSpeechEnd, task: task)
        log("speculative tail decode started — \(String(format: "%.1f", Double(speechEndRel) / sampleRate)) s of speech, \(String(format: "%.1f", Double(trailing) / sampleRate)) s pause")
    }
}
